#!/usr/bin/env ruby
# frozen_string_literal: true

# F4 health roll-up — advisory composite score (0-10) + trend over time.
#
# Rolls the F4 signals up into ONE weighted 0-10 number plus a trend, so the
# question "is the skill repo trending healthier or worse?" has an answer. This
# is the pattern OpenSSF Scorecard uses for repos (per-check 0-10 -> risk-weighted
# aggregate 0-10, tracked over time); gstack-health uses the same shape for code
# repos. We adapt it to F4 skill-eval signals — we do NOT score code tools.
#
# Dimensions (each scored 0-10, risk-weighted OpenSSF-style):
#   structural      weight 10 (Critical)  — validate-skill.sh: skills load / no leakage
#   routing_static  weight 10 (Critical)  — eval-routing.rb: no blocking routing defect
#   trace           weight 7.5 (High)     — eval-golden-trace.rb pass rate (optional, real agent)
#   bank            weight 5  (Medium)    — eval-routing-bank.rb pass rate (optional, cheap grader)
#
# structural + routing_static are deterministic (no LLM) and run here (each under
# a wall-clock bound so a hung sub-tool can never hang the advisory run). trace/
# bank need the `claude` CLI and are non-deterministic, so they are NOT auto-run;
# pass their JSON reports in (--trace-json / --bank-json) or they are SKIPPED and
# their weight is redistributed across the present dims (honest, labeled). A
# malformed or schema-invalid report is SKIPPED (never silently scored).
#
# ADVISORY ONLY. It never blocks on a score: exit is 0 when it ran AND 0 when
# nothing was computable; only a usage/setup error (bad <repo-root> / no skills/
# dir) exits 2. IO problems (unwritable history / --json path) warn and continue,
# never crash. NEVER wire this into check-ccl-skills.sh. The binary gates
# (structural validation + Tier-1 blocking findings) remain the source of truth
# and block independently of this score. Per Goodhart's law ("when a measure
# becomes a target, it ceases to be a good measure"), a composite that became a
# merge gate would just get gamed; it stays a lens, not a gate. The history file
# is git-ignored for the same reason — a committed number invites tuning the
# number instead of the repo.
#
# CORPUS/VERSION GUARD: the trend is only meaningful between runs that used the
# SAME measuring stick. Each entry records a `corpus` fingerprint (a delimited
# hash of the task-bank + golden-trace inputs, by name + presence + length +
# content so that splitting/merging/renaming/absence cannot collide) and the set
# of `dims` present. A delta verdict (IMPROVING/DECLINING) is shown ONLY against
# the most recent prior entry whose (corpus, dims) match; otherwise the trend is
# reset, not silently compared. This stops "added 10 easy tasks -> score went up"
# from reading as a real gain.
#
# Usage:
#   eval-health.rb <repo-root> [--trace-json <path>] [--bank-json <path>]
#                  [--history <path>] [--no-write] [--json <path>] [--quiet]
# Exit: 0 = ran or nothing computable (advisory, never blocks on a score);
#       2 = usage/setup error (bad <repo-root> or no skills/ dir).

require "json"
require "digest"
require "tmpdir"
require "tempfile"
require "timeout"
require "fileutils"

root = ARGV[0]
if root.nil? || root.empty? || root.start_with?("-")
  warn "usage: eval-health.rb <repo-root> [--trace-json p] [--bank-json p] " \
       "[--history p] [--no-write] [--json p] [--quiet]"
  exit 2
end

def opt(name)
  i = ARGV.index(name)
  return nil unless i
  v = ARGV[i + 1]
  if v.nil? || v.start_with?("-")
    warn "usage: #{name} requires a following path"
    exit 2
  end
  v
end

# Run a subprocess under a wall-clock bound so a hung sub-tool cannot hang this
# advisory run. Returns true (clean exit 0), false (clean non-zero exit), or nil
# (timed out / could not spawn — caller treats nil as "couldn't compute", skip).
def run_bounded(*cmd, timeout: 120)
  pid = Process.spawn(*cmd, out: File::NULL, err: File::NULL)
  Timeout.timeout(timeout) { Process.wait(pid) }
  $?.success?
rescue Timeout::Error
  (Process.kill("KILL", pid) rescue nil)
  Process.detach(pid)
  nil
rescue StandardError
  nil
end

trace_json = opt("--trace-json")
bank_json  = opt("--bank-json")
out_json   = opt("--json")
history    = opt("--history") || File.join(root, "eval", "health-history.jsonl")
no_write   = ARGV.include?("--no-write")
quiet      = ARGV.include?("--quiet")

skills_dir = File.join(root, "skills")
unless Dir.exist?(skills_dir)
  warn "eval_health_no_skills: no skills/ under #{root}"
  exit 2
end

script_dir = __dir__

# --- dimension scoring ------------------------------------------------------
# Each dim: { score: 0-10 (Integer) or nil if skipped, detail: }
RISK = { structural: 10.0, routing_static: 10.0, trace: 7.5, bank: 5.0 }.freeze
dims = {}

# D1 structural — validate-skill.sh exit 0 => skills load, no leakage, refs ok.
validate = File.join(script_dir, "validate-skill.sh")
dims[:structural] =
  if File.executable?(validate)
    case run_bounded("bash", validate, skills_dir)
    when true  then { score: 10, detail: "validate-skill.sh: pass" }
    when false then { score: 0,  detail: "validate-skill.sh: FAIL" }
    else { score: nil, detail: "skipped: validate-skill.sh did not complete" }
    end
  else
    { score: nil, detail: "skipped: validate-skill.sh not executable" }
  end

# D2 routing_static — eval-routing.rb blocking/advisory counts. A fresh Tempfile
# per run (never a stale PID-named file); eval-routing exits 1 when blocking
# findings exist (a VALID run, not a failure), so we gate on "valid JSON with the
# two arrays present", not on subprocess success. Bounded so a hang can't stall us.
routing = File.join(script_dir, "eval-routing.rb")
if File.exist?(routing)
  rep = nil
  Tempfile.create(["eval-routing", ".json"]) do |tf|
    tf.close
    run_bounded("ruby", routing, root, "--json", tf.path, "--quiet")
    parsed = (JSON.parse(File.read(tf.path)) rescue nil) if File.size?(tf.path)
    rep = parsed if parsed.is_a?(Hash) && parsed["blocking"].is_a?(Array) && parsed["advisory"].is_a?(Array)
  end
  if rep
    blk = rep["blocking"].size
    adv = rep["advisory"].size
    score =
      if blk.positive? then 3                 # CRITICAL — but the real gate already blocks this
      elsif adv.zero?  then 10
      elsif adv <= 3   then 9
      elsif adv <= 8   then 8
      else 7
      end
    dims[:routing_static] = { score: score, detail: "blocking=#{blk} advisory=#{adv}" }
  else
    dims[:routing_static] = { score: nil, detail: "skipped: eval-routing.rb produced no valid JSON" }
  end
else
  dims[:routing_static] = { score: nil, detail: "skipped: eval-routing.rb missing" }
end

# Helper: read an optional Tier-2/Tier-3 report and turn a pass-rate into 0-10.
# A malformed or schema-invalid report is SKIPPED, never silently scored.
def from_report(path, pass_key, total_key, label)
  return { score: nil, detail: "skipped: no #{label} report (pass --#{label}-json)" } unless path
  unless File.exist?(path)
    return { score: nil, detail: "skipped: #{label} report not found at #{path}" }
  end
  rep = (JSON.parse(File.read(path)) rescue nil)
  return { score: nil, detail: "skipped: #{label} report not a JSON object" } unless rep.is_a?(Hash)
  total = rep[total_key]
  passes = rep[pass_key]
  unless total.is_a?(Integer) && passes.is_a?(Integer)
    return { score: nil, detail: "skipped: #{label} report has non-integer #{pass_key}/#{total_key}" }
  end
  return { score: nil, detail: "skipped: #{label} had 0 comparable tasks" } if total <= 0
  if passes.negative? || passes > total
    return { score: nil, detail: "skipped: #{label} report invalid (pass=#{passes} out of 0..#{total})" }
  end
  rate = passes.to_f / total
  { score: (rate * 10).round, detail: "#{passes}/#{total} pass (rate #{(rate * 100).round}%)" }
end

# D3 trace (High) — golden-trace pass rate over CONSIDERED (excludes drift).
dims[:trace] = from_report(trace_json, "pass", "considered", "trace")
# D4 bank (Medium) — routing-bank pass rate over tasks. A consumer-truncation
# arm report (desc_budget_chars set) is a diagnostic run, NOT the same
# measuring stick as the plain bank — never fold it into the trend.
bank_arm = begin
  bank_json && File.file?(bank_json) ? JSON.parse(File.read(bank_json))["desc_budget_chars"] : nil
rescue StandardError
  nil
end
if bank_arm
  dims[:bank] = { score: nil, detail: "skipped: bank report is a desc-budget-chars=#{bank_arm} truncation arm (diagnostic, not the trend baseline)" }
else
  dims[:bank] = from_report(bank_json, "pass", "tasks", "bank")
end

# --- composite (weighted over present dims; skipped weight redistributes) ----
present = dims.select { |_, d| !d[:score].nil? }
if present.empty?
  warn "eval_health_no_dims: every dimension skipped (validate-skill.sh / eval-routing.rb " \
       "unavailable, no T2/T3 reports) — nothing to score"
  exit 0 # advisory: nothing computable is NOT a failure; never block.
end
wsum = present.sum { |k, _| RISK[k] }
composite_raw = present.sum { |k, d| d[:score] * RISK[k] } / wsum
composite = (composite_raw * 10).round / 10.0 # one decimal for display

def band(s)
  return "CLEAN"      if s >= 9.0
  return "WARNING"    if s >= 7.0
  return "NEEDS WORK" if s >= 4.0
  "CRITICAL"
end

# --- corpus/version fingerprint ---------------------------------------------
# Hash the measuring-stick inputs so a changed stick is detectable. Delimited by
# name + presence + byte-length so that splitting/merging/renaming inputs cannot
# collide (a raw byte concat would let "A"+"BC" == "AB"+"C"), and an absent file
# cannot collide with a present file whose literal content is the sentinel.
tasks_file  = File.join(root, "eval", "routing-tasks.jsonl")
trace_files = Dir[File.join(root, "eval", "golden-traces", "*.json")].sort
fp = Digest::SHA256.new
([tasks_file] + trace_files).each do |p|
  exists = File.exist?(p)
  content = exists ? (File.read(p) rescue "") : "" # unreadable / is-a-dir: don't crash, treat as empty
  fp.update("#{File.basename(p)}\x00#{exists ? 'present' : 'missing'}\x00#{content.bytesize}\x00")
  fp.update(content)
  fp.update("\x00")
end
corpus = fp.hexdigest[0, 12]

repo_sha = `git -C #{root.inspect} rev-parse --short HEAD 2>/dev/null`.strip
repo_sha = "unknown" if repo_sha.empty?
present_dims = present.keys.map(&:to_s).sort

entry = {
  "ts" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  "repo_sha" => repo_sha,
  "corpus" => corpus,
  "dims" => present_dims,
  "score" => composite,
  "score_raw" => composite_raw.round(4),
  "routing_tasks" => File.exist?(tasks_file) ? "present" : "missing",
  "trace_count" => trace_files.size
}
dims.each { |k, d| entry[k.to_s] = d[:score] }

# --- trend (only against a comparable prior entry) --------------------------
# Per-line parse rescue is not enough: a parseable-but-wrong-schema line (dims as
# String, mixed-type Array, score not Numeric) would crash the comparison.
# Require dims to be an Array of Strings (so .sort is total) and score Numeric.
prior_comparable = nil
recent = []
if File.exist?(history)
  begin
    File.foreach(history) do |line|
      h = (JSON.parse(line) rescue nil)
      next unless h.is_a?(Hash) && h["score"].is_a?(Numeric)
      d = h["dims"]
      next unless d.is_a?(Array) && d.all? { |e| e.is_a?(String) }
      recent << h
      prior_comparable = h if h["corpus"] == corpus && d.sort == present_dims
    end
  rescue StandardError => e
    warn "eval_health_history_read_skipped: #{e.class}: #{e.message}" # is-a-dir / unreadable: skip trend
  end
end

# Trend delta on the RAW score (not the 1-decimal display) so a 9.54 -> 9.46
# regression is not rounded into "flat". Fall back to display score for entries
# written before score_raw existed.
def raw_of(h)
  h["score_raw"].is_a?(Numeric) ? h["score_raw"] : h["score"]
end
trend = prior_comparable ? (composite_raw - raw_of(prior_comparable)).round(2) : nil

# IO never crashes the advisory run — warn and continue on any write failure.
unless no_write
  begin
    FileUtils.mkdir_p(File.dirname(history))
    File.open(history, "a") do |f|
      begin
        f.flock(File::LOCK_EX)
      rescue StandardError
        # locking unsupported on this FS (some network mounts) — proceed without it
      end
      f.puts(JSON.generate(entry))
      f.flock(File::LOCK_UN) rescue nil
    end
  rescue StandardError => e
    warn "eval_health_history_write_skipped: #{e.class}: #{e.message}"
  end
end

report = entry.merge(
  "band" => band(composite),
  "weights_present" => present.to_h { |k, _| [k.to_s, RISK[k]] },
  "details" => dims.to_h { |k, d| [k.to_s, d[:detail]] },
  "trend" => trend,
  "trend_baseline_sha" => prior_comparable&.fetch("repo_sha", nil),
  "history" => history
)
if out_json
  begin
    FileUtils.mkdir_p(File.dirname(out_json))
    File.write(out_json, JSON.pretty_generate(report))
  rescue StandardError => e
    warn "eval_health_json_write_skipped: #{e.class}: #{e.message}"
  end
end

unless quiet
  puts "F4 HEALTH ROLL-UP (advisory — not a gate)"
  puts "  repo=#{repo_sha} corpus=#{corpus} dims=#{present_dims.join(',')}"
  dims.each do |k, d|
    s = d[:score].nil? ? "  -  " : format("%2d/10", d[:score])
    puts "  #{k.to_s.ljust(15)} #{s}  #{d[:detail]}"
  end
  puts "  COMPOSITE  #{format('%.1f', composite)}/10  #{band(composite)}"
  if prior_comparable
    arrow = trend.positive? ? "IMPROVING +#{trend}" : (trend.negative? ? "DECLINING #{trend}" : "FLAT")
    puts "  trend vs #{prior_comparable['repo_sha']} (same corpus+dims): #{arrow}"
  elsif recent.any?
    puts "  trend: no comparable prior run (corpus or dims changed) — baseline reset, not compared"
  else
    puts "  trend: first run — no history yet"
  end
  puts "  (binary gates still block independently of this number; history=#{history}, git-ignored)"
end

exit 0
