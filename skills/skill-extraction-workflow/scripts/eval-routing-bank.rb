#!/usr/bin/env ruby
# frozen_string_literal: true

# F4 Tier-2 routing compatibility eval (cheap-LLM grader over a frozen task bank).
#
# Measures whether the current skill descriptions make a cheap model route a fixed
# set of utterances to the expected skill. This is a ROUTING-COMPATIBILITY signal,
# NOT a truth oracle — the grader can be wrong. Advisory dashboard: it never blocks
# a merge and is not wired into check-ccl-skills.sh.
#
# Anti-game: each task carries frozen_at_sha; `root` resolves to the repository
# root commit, while an explicit SHA must be an ancestor of HEAD. The runner also
# flags when the same change touches both the bank and skill
# descriptions (so "fix skill + rewrite test to pass" is visible).
#
# Usage:
#   eval-routing-bank.rb <repo-root> [--bank <path>] [--model <name>] [--limit N]
#                        [--dry-run] [--json <path>] [--baseline <path>] [--timeout S]
#                        [--desc-budget-chars N] [--with-bootstrap]
#
# --desc-budget-chars N simulates a consumer that truncates each skill description
# to its first N characters before routing (e.g. Codex compresses the skill listing
# under a ~2%-of-context budget, 8000 chars when the window is unknown, shortening
# descriptions first). Run the bank once plain and once with a budget to see which
# routes only survive on the description tail — those triggers need front-loading.
# Exit: 0 = ran (advisory); 2 = usage error; 3 = grader entirely unavailable.

require "yaml"
require "json"
require "open3"
require "shellwords"
require "timeout"
require "digest"

def arg(flag, default = nil)
  i = ARGV.index(flag)
  i ? ARGV[i + 1] : default
end

root = ARGV[0]
if root.nil? || root.start_with?("-")
  warn "usage: eval-routing-bank.rb <repo-root> [--bank p] [--model m] [--limit N] [--dry-run] [--json p] [--baseline p] [--timeout S] [--desc-budget-chars N]"
  exit 2
end
bank_path = arg("--bank", File.join(root, "eval", "routing-tasks.jsonl"))
model = arg("--model", "claude-haiku-4-5")
limit = (l = arg("--limit")) ? l.to_i : nil
dry_run = ARGV.include?("--dry-run")
json_path = arg("--json")
baseline_path = arg("--baseline")
desc_budget = nil
if ARGV.include?("--desc-budget-chars")
  if ARGV.count("--desc-budget-chars") > 1
    warn "--desc-budget-chars given more than once; pass it a single time"
    exit 2
  end
  b = arg("--desc-budget-chars")
  # Strict: a missing value (flag last / next token is another flag) or a
  # non-integer must fail loudly, or the truncation arm silently becomes the
  # baseline arm (to_i coerces "200x" -> 200, nil -> 0).
  unless b && b =~ /\A[1-9]\d*\z/
    warn "--desc-budget-chars requires a positive integer value, got #{b.inspect}"
    exit 2
  end
  desc_budget = b.to_i
end
timeout_s = (t = arg("--timeout")) ? t.to_i : 60

unless File.file?(bank_path)
  warn "eval_bank_missing: #{bank_path}"
  exit 2
end

# ONE immutable snapshot of the bank: the tasks are parsed from, and every
# bank-derived hash below is computed from, the SAME bytes — so grading and the
# report's self-identification cannot diverge if the file changes mid-run.
bank_bytes = File.binread(bank_path)
tasks = []
bank_bytes.dup.force_encoding(Encoding::UTF_8).each_line.with_index(1) do |line, n|
  line = line.strip
  next if line.empty?
  begin
    tasks << JSON.parse(line)
  rescue JSON::ParserError => e
    warn "eval_bank_parse_error: line #{n}: #{e.message}"
    exit 2
  end
end
tasks = tasks.first(limit) if limit

# Schema validation: a task must be answerable, and must not be self-contradictory.
tasks.each do |t|
  id = t["id"] || "(no id)"
  if t["utterance"].to_s.strip.empty? || t["expected_skill"].to_s.strip.empty?
    warn "eval_bank_invalid_task: #{id}: utterance and expected_skill are required"
    exit 2
  end
  if (t["must_not_route_to"] || []).include?(t["expected_skill"])
    warn "eval_bank_invalid_task: #{id}: expected_skill is also in must_not_route_to (impossible)"
    exit 2
  end
end

# --- anti-game ---------------------------------------------------------------
def ancestor?(root, sha)
  return false if sha.nil? || sha.empty?
  system("git", "-C", root, "merge-base", "--is-ancestor", sha, "HEAD",
         out: File::NULL, err: File::NULL)
end

# Working-tree co-change: does the branch diff touch BOTH the bank and any
# SKILL.md description? (advisory governance warning). If the base ref cannot be
# resolved the check is UNAVAILABLE — surfaced explicitly, never silently false.
base = ENV["CCL_SKILL_BASE_REF"].to_s.strip
base = "origin/main" if base.empty?
changed, diff_status = Open3.capture2e("git", "-C", root, "diff", base, "HEAD", "--name-only")
co_change_check_ok = diff_status.success?
changed_files = co_change_check_ok ? changed.lines.map(&:strip) : []
bank_changed = changed_files.any? { |f| f.include?("routing-tasks.jsonl") }
desc_changed = changed_files.any? { |f| f.end_with?("/SKILL.md") }
co_change = bank_changed && desc_changed

# --- build skill routing surface (the same descriptions the agent routes on) -
catalog = Dir[File.join(root, "skills", "*", "SKILL.md")].sort.map do |path|
  name = File.basename(File.dirname(path))
  m = File.read(path).match(/\A---\s*\n(.*?)\n---\s*\n/m)
  next unless m
  desc = (YAML.safe_load(m[1]) rescue {})["description"].to_s.strip
  next if desc.empty?
  desc = desc[0, desc_budget] if desc_budget && desc.length > desc_budget
  "### #{name}\n#{desc}"
end.compact.join("\n\n")

# --- optional always-on entry-routing layer -----------------------------------
# The catalog above is the description-only surface. Hosts ALSO inject
# agent-context/session-start.md into every session, and that layer carries
# cross-skill discrimination rules the descriptions do not. Without this flag the
# bank cannot tell whether a routing miss is fixed by the injected layer, so every
# "this skill must be in the always-on layer" claim stayed unfalsifiable — and the
# layer has a hard zero-net-growth budget, which makes that claim expensive.
# Run the bank twice (plain, then --with-bootstrap) to measure what the layer buys.
bootstrap_layer = nil
if ARGV.include?("--with-bootstrap")
  bpath = File.join(root, "agent-context", "session-start.md")
  unless File.file?(bpath)
    warn "eval-routing-bank: --with-bootstrap given but #{bpath} is missing"
    exit 2
  end
  bootstrap_layer = File.read(bpath)[/ccl:entry-routing:start -->(.*?)<!-- ccl:entry-routing:end/m, 1]&.strip
  if bootstrap_layer.nil? || bootstrap_layer.empty?
    warn "eval-routing-bank: --with-bootstrap given but no ccl:entry-routing region in #{bpath}"
    exit 2
  end
end

# --- routing-surface self-identification -------------------------------------
# Every emitted report names the exact surface it graded, so a round artifact
# can never be attributed to the wrong wording by operator assertion alone.
# descriptions_sha256 mirrors the binding wrapper's surface_hash byte-for-byte
# (dir-name-tagged RAW description lines of every skills/*/SKILL.md in sorted
# glob order — grep semantics, YAML unparsed, trailing newline included — plus
# the bank file bytes), so a sidecar recomputing the same quantity externally
# is an independent check of this claim. per_skill maps each description line
# to its own hash; catalog_sha256 identifies the GRADED catalog text (post
# YAML-parse, post desc-budget truncation), which is what the model actually
# saw. Grading semantics are untouched: nothing below feeds the prompt or the
# verdicts.
surface_parts = +"".b
per_skill_desc_sha = {}
Dir[File.join(root, "skills", "*", "SKILL.md")].sort.each do |path|
  name = File.basename(File.dirname(path))
  line = File.open(path, "rb") { |f| f.each_line.find { |l| l.start_with?("description:") } }
  next unless line
  surface_parts << name.b << "\t".b << line.b
  per_skill_desc_sha[name] = Digest::SHA256.hexdigest(line)
end
routing_surface = {
  descriptions_sha256: Digest::SHA256.hexdigest(surface_parts + bank_bytes),
  per_skill_description_line_sha256: per_skill_desc_sha,
  catalog_sha256: Digest::SHA256.hexdigest(catalog),
  bank_sha256: Digest::SHA256.hexdigest(bank_bytes),
  bootstrap_layer_sha256: bootstrap_layer ? Digest::SHA256.hexdigest(bootstrap_layer) : nil
}

def build_prompt(catalog, utterance, bootstrap_layer = nil)
  <<~PROMPT
    You are a routing classifier for a CCL engineering skill system. Given a
    user utterance and the catalog of skills (name + description), pick the SINGLE
    best skill that should handle it. Use only the catalog; route by the
    descriptions' Use-when / Proactively / Skip rules.

    Output ONLY a JSON object on one line, no other text:
    {"selected_skill": "<exact skill name from the catalog>", "confidence": <0.0-1.0>, "rationale_short": "<one short clause>"}

    #{bootstrap_layer ? "== ALWAYS-ON ENTRY ROUTING LAYER (injected into every session; takes precedence for entry routing) ==\n#{bootstrap_layer}\n" : ""}
    == SKILL CATALOG ==
    #{catalog}

    == UTTERANCE ==
    #{utterance}
  PROMPT
end

# Extract the first BALANCED top-level JSON object (string/escape aware) so extra
# braces, markdown fences, or trailing prose after the object do not corrupt it.
def extract_json(text)
  start = text.index("{")
  return nil unless start
  depth = 0
  in_str = false
  esc = false
  text[start..-1].each_char.with_index do |c, i|
    if in_str
      if esc then esc = false
      elsif c == "\\" then esc = true
      elsif c == '"' then in_str = false
      end
    elsif c == '"' then in_str = true
    elsif c == "{" then depth += 1
    elsif c == "}"
      depth -= 1
      if depth.zero?
        return (JSON.parse(text[start, i + 1]) rescue nil)
      end
    end
  end
  nil
end

# Run the grader with a portable hard timeout (pure Ruby — does not depend on a
# GNU `timeout` binary being present).
def grade(model, timeout_s, prompt)
  cmd = ["claude", "--print", "--tools", "", "--model", model]
  out = +""
  err = +""
  status = nil
  Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
    # Drain stdout/stderr in threads BEFORE writing so claude can never block on a
    # full output pipe; keep the write+close+wait all under one hard timeout so a
    # stalled or early-exited grader cannot hang or crash the runner.
    #
    # The readers must absorb their own pipe being closed: the timeout path below
    # closes these pipes underneath them on purpose, and a reader that dies of
    # that IOError gets it re-raised by join/value — aborting the whole eval
    # (exit 1, no JSON report) at the exact moment the guard is supposed to
    # report grader_timeout_Ns.
    drain = lambda do |io|
      Thread.new do
        Thread.current.report_on_exception = false
        begin
          io.read
        rescue IOError, SystemCallError
          nil
        end
      end
    end
    out_t = drain.call(stdout)
    err_t = drain.call(stderr)
    begin
      Timeout.timeout(timeout_s) do
        begin
          stdin.write(prompt)
        rescue Errno::EPIPE, IOError
          # claude closed stdin early; its exit status / stderr will explain
        ensure
          stdin.close rescue nil
        end
        status = wait_thr.value
        # Collect reader output INSIDE the timeout: a grader that exits while a
        # child/grandchild still holds the pipe open keeps stdout from reaching
        # EOF, so out_t.value would otherwise hang forever past the guard.
        out = out_t.value.to_s
        err = err_t.value.to_s
      end
    rescue Timeout::Error
      Process.kill("KILL", wait_thr.pid) rescue nil
      stdout.close rescue nil # force the blocked readers to unblock
      stderr.close rescue nil
      out_t.join(1)
      err_t.join(1)
      return [nil, "grader_timeout_#{timeout_s}s"]
    end
  end
  diagnostic = err.strip.empty? ? out.strip : err.strip
  return [nil, "grader_exit_#{status.exitstatus}: #{diagnostic[0, 200]}"] unless status&.success?
  obj = extract_json(out)
  return [nil, "no_json_in_output: #{out.strip[0, 120]}"] unless obj
  [obj, nil]
rescue Errno::ENOENT
  [nil, "claude_not_found"]
end


# --- run ---------------------------------------------------------------------
if dry_run
  puts build_prompt(catalog, tasks.first["utterance"], bootstrap_layer)
  exit 0
end

# Grader availability is decided up front (not via a mid-loop exit code, which a
# `timeout` wrapper would mask as 127). claude missing => advisory skip, exit 0.
if (`command -v claude 2>/dev/null`.strip rescue "").empty?
  puts "eval-routing-bank: grader unavailable (claude CLI not found) — skipped (advisory)"
  exit 0
end

results = []
grader_available = true
tasks.each do |t|
  exp = t["expected_skill"]
  must_not = t["must_not_route_to"] || []
  frozen_ref = t["frozen_at_sha"] == "root" ? `git -C #{Shellwords.escape(root)} rev-list --max-parents=0 HEAD`.lines.first.to_s.strip : t["frozen_at_sha"]
  frozen_ok = ancestor?(root, frozen_ref)
  prompt = build_prompt(catalog, t["utterance"], bootstrap_layer)
  parsed, error = grade(model, timeout_s, prompt)
  # A task that produced no observation contributes nothing to the totals, and an
  # unmeasured task is indistinguishable from a routing failure in the numbers
  # this bank reports. Both recoverable causes are sampling accidents rather than
  # verdicts — a hard timeout is usually machine load, and unparseable output is
  # usually one stray quote in a generated rationale — so each gets one retry.
  # Repairing malformed output instead of re-asking for it was tried and removed:
  # interpreting text that is by definition malformed has no natural boundary,
  # and three review rounds each found a different shape that a repair would read
  # as a verdict. Re-asking needs no such interpretation. Nothing else is retried:
  # an auth failure and a missing CLI do reproduce on a second call.
  if error&.start_with?("grader_timeout_") || error&.start_with?("no_json_in_output")
    parsed, retry_error = grade(model, timeout_s, prompt)
    error = parsed ? nil : retry_error
  end
  if error == "claude_not_found"
    grader_available = false
    break
  end
  selected = parsed && parsed["selected_skill"]
  confidence = parsed && parsed["confidence"]
  status =
    if error then "ERROR"
    elsif selected == exp && !must_not.include?(selected) then "PASS"
    else "FAIL"
    end
  results << {
    id: t["id"], utterance: t["utterance"], expected: exp, selected: selected,
    confidence: confidence, must_not_route_to: must_not, status: status,
    error: error, frozen_at_sha_is_ancestor: frozen_ok
  }
end

unless grader_available
  puts "eval-routing-bank: grader unavailable (claude CLI not found) — skipped (advisory)"
  exit 0
end

passes = results.count { |r| r[:status] == "PASS" }
fails = results.select { |r| r[:status] == "FAIL" }
errors = results.select { |r| r[:status] == "ERROR" }
drift = results.reject { |r| r[:frozen_at_sha_is_ancestor] }

# baseline diff (newly failed / newly passed). The baseline is a prior report
# (a hash with a "results" array) or a bare results array.
newly_failed = []
newly_passed = []
if baseline_path && File.file?(baseline_path)
  base_json = JSON.parse(File.read(baseline_path))
  base_results = base_json.is_a?(Hash) ? (base_json["results"] || []) : base_json
  base_status = base_results.to_h { |r| [r["id"], r["status"]] }
  results.each do |r|
    was = base_status[r[:id]]
    newly_failed << r[:id] if was == "PASS" && r[:status] == "FAIL"
    newly_passed << r[:id] if was == "FAIL" && r[:status] == "PASS"
  end
end

report = {
  model: model, tasks: results.size, pass: passes, fail: fails.size, error: errors.size,
  desc_budget_chars: desc_budget, routing_surface: routing_surface,
  co_change_bank_and_descriptions: co_change, co_change_check_available: co_change_check_ok,
  frozen_drift: drift.map { |r| r[:id] },
  newly_failed: newly_failed, newly_passed: newly_passed, results: results
}
File.write(json_path, JSON.pretty_generate(report)) if json_path

puts "eval-routing-bank (#{model}): #{passes}/#{results.size} pass, #{fails.size} fail, #{errors.size} grader-error"
puts "  arm: desc-budget-chars=#{desc_budget}" if desc_budget
puts "  ⚠ co-change check unavailable: base ref #{base.inspect} not resolvable — could not verify bank/description co-change" unless co_change_check_ok
puts "  ⚠ co-change: this change touches BOTH the bank and a SKILL.md description (verify the bank was not edited to pass)" if co_change
puts "  ⚠ frozen-drift (not ancestor of HEAD, excluded from regression judgment): #{drift.map { |r| r[:id] }.join(', ')}" unless drift.empty?
unless fails.empty?
  puts "  FAIL:"
  fails.each { |r| puts "    - #{r[:id]}: expected #{r[:expected]} got #{r[:selected].inspect} (conf #{r[:confidence]})" }
end
unless errors.empty?
  puts "  GRADER-ERROR:"
  errors.each { |r| puts "    - #{r[:id]}: #{r[:error]}" }
end
unless newly_failed.empty? && newly_passed.empty?
  puts "  vs baseline: newly_failed=#{newly_failed.join(',')} newly_passed=#{newly_passed.join(',')}"
end

# Advisory: never block on a routing miss. Only signal grader-infra breakage.
exit 3 if !results.empty? && errors.size == results.size
exit 0
