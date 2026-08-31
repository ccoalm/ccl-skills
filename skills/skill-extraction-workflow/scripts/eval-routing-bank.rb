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
#                        [--desc-budget-chars N] [--with-bootstrap] [--replicas N]
#
# --desc-budget-chars N simulates a consumer that truncates each skill description
# to its first N characters before routing (e.g. Codex compresses the skill listing
# under a ~2%-of-context budget, 8000 chars when the window is unknown, shortening
# descriptions first). Run the bank once plain and once with a budget to see which
# routes only survive on the description tail — those triggers need front-loading.
#
# expected_skill "none" marks negative controls (out-of-library utterances) and
# coverage-gap probes (in-domain utterances no skill owns): the correct outcome
# is rejection, and a catalog skill claiming them is labeled "absorbed".
# --replicas N grades each task N times: task status is the conservative
# consensus (every observed replica must PASS), replica top1 agreement is
# reported, and disagreeing replicas label the task "ownership_split". clarify
# and low-confidence counts are first-class report fields either way.
# Reports from different (bank, replicas) configurations are different rulers —
# do not diff them as a regression signal.
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
  warn "usage: eval-routing-bank.rb <repo-root> [--bank p] [--model m] [--limit N] [--dry-run] [--json p] [--baseline p] [--timeout S] [--desc-budget-chars N] [--replicas N]"
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
replicas = 1
if ARGV.include?("--replicas")
  r = arg("--replicas")
  # Same strictness as --desc-budget-chars: a silent to_i coercion would turn a
  # typo into "1 replica" and the agreement metric would quietly measure nothing.
  unless r && r =~ /\A[1-9]\d*\z/
    warn "--replicas requires a positive integer value, got #{r.inspect}"
    exit 2
  end
  replicas = r.to_i
end

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
# expected_skill "none" is the negative-control / coverage-gap sentinel: the
# correct routing outcome is that NO catalog skill claims the utterance.
all_outcomes = Dir[File.join(root, "skills", "*", "SKILL.md")]
               .map { |p| File.basename(File.dirname(p)) } + ["none"]
tasks.each do |t|
  id = t["id"] || "(no id)"
  if t["utterance"].to_s.strip.empty? || t["expected_skill"].to_s.strip.empty?
    warn "eval_bank_invalid_task: #{id}: utterance and expected_skill are required"
    exit 2
  end
  # Type-check the ORIGINAL values FIRST: a present-but-non-list field (e.g. ""
  # or a bare string or a number) must fail as a usage error before any
  # membership check touches it — Ruby strings are truthy and respond to
  # include? (substring semantics), and non-strings would raise a bare
  # NoMethodError instead of the documented invalid-bank diagnostic.
  %w[must_not_route_to acceptable].each do |f|
    next unless t.key?(f)
    unless t[f].is_a?(Array)
      warn "eval_bank_invalid_task: #{id}: #{f} must be a list, got #{t[f].inspect}"
      exit 2
    end
  end
  if (t["must_not_route_to"] || []).include?(t["expected_skill"])
    warn "eval_bank_invalid_task: #{id}: expected_skill is also in must_not_route_to (impossible)"
    exit 2
  end
  if (t["must_not_route_to"] || []).include?("none")
    warn "eval_bank_invalid_task: #{id}: \"none\" is a sentinel outcome, not a routable target for must_not_route_to"
    exit 2
  end
  # Optional acceptable[] names defensible alternate outcomes (a skill name or
  # "none") for utterances with more than one correct route — e.g. a coverage-gap
  # ask where both coordinator intake and rejection are right. It must not
  # restate expected_skill or contradict must_not_route_to.
  acc = t["acceptable"] || []
  if acc.include?(t["expected_skill"])
    warn "eval_bank_invalid_task: #{id}: acceptable restates expected_skill"
    exit 2
  end
  unless (acc & (t["must_not_route_to"] || [])).empty?
    warn "eval_bank_invalid_task: #{id}: acceptable and must_not_route_to overlap (contradictory)"
    exit 2
  end
  # Anti-gaming: expected + acceptable must leave at least one outcome that
  # would FAIL the row. A row covering the complete catalog-and-none outcome
  # space passes on every valid grader selection — a vacuous fixture that fakes
  # green regardless of description behavior.
  if (all_outcomes - ([t["expected_skill"]] + acc)).empty?
    warn "eval_bank_invalid_task: #{id}: expected_skill plus acceptable cover every possible outcome (vacuous row)"
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
    If NO skill's description covers the utterance, answer "none" — do not
    force-fit the nearest neighbor. Set "clarify" to true only when you would
    need to ask the user a clarifying question before committing to a route.

    Output ONLY a JSON object on one line, no other text:
    {"selected_skill": "<exact skill name from the catalog, or none>", "clarify": <true|false>, "confidence": <0.0-1.0>, "rationale_short": "<one short clause>"}

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
  acceptable = t["acceptable"] || []
  frozen_ref = t["frozen_at_sha"] == "root" ? `git -C #{Shellwords.escape(root)} rev-list --max-parents=0 HEAD`.lines.first.to_s.strip : t["frozen_at_sha"]
  frozen_ok = ancestor?(root, frozen_ref)
  prompt = build_prompt(catalog, t["utterance"], bootstrap_layer)
  verdicts = []
  replicas.times do |ri|
    parsed, error = grade(model, timeout_s, prompt)
    # A verdict that produced no observation contributes nothing to the totals,
    # and an unmeasured task is indistinguishable from a routing failure in the
    # numbers this bank reports. Both recoverable causes are sampling accidents
    # rather than verdicts — a hard timeout is usually machine load, and
    # unparseable output is usually one stray quote in a generated rationale —
    # so each gets one retry.
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
    clarify = parsed && parsed["clarify"] == true
    confidence = parsed && parsed["confidence"]
    v_status =
      if error then "ERROR"
      elsif (selected == exp || acceptable.include?(selected)) && !must_not.include?(selected) then "PASS"
      else "FAIL"
      end
    verdicts << { replica: ri + 1, selected: selected, clarify: clarify,
                  confidence: confidence, status: v_status, error: error }
  end
  break unless grader_available
  # Task-level consensus over replicas (replicas=1 reproduces the old per-task
  # semantics exactly). Conservative: one failing replica fails the task —
  # a route that only sometimes lands is not a stable route.
  observed = verdicts.reject { |v| v[:status] == "ERROR" }
  status =
    if observed.empty? then "ERROR"
    elsif observed.all? { |v| v[:status] == "PASS" } then "PASS"
    else "FAIL"
    end
  selections = observed.map { |v| v[:selected] }.uniq
  # Failure-mode labels (vocabulary in references/eval-routing.md):
  #   absorbed        — an utterance that should be rejected (expected "none")
  #                     or kept away from named bait neighbors (must_not_route_to)
  #                     was claimed by such a skill anyway
  #   ownership_split — replicas disagreed on the top pick (unstable ownership)
  labels = []
  absorbed = (exp == "none" && observed.any? { |v| v[:selected] && v[:selected] != "none" }) ||
             observed.any? { |v| must_not.include?(v[:selected]) }
  labels << "absorbed" if absorbed
  labels << "ownership_split" if selections.size > 1
  # A task where some replicas erred but others graded is PARTIALLY measured:
  # the consensus above sees only the observed verdicts, so without this label
  # a PASS+ERROR pair would read as a clean PASS and the run as fully sampled.
  labels << "partial_error" if verdicts.any? { |v| v[:status] == "ERROR" } && !observed.empty?
  results << {
    id: t["id"], utterance: t["utterance"], expected: exp, acceptable: acceptable,
    selected: observed.first && observed.first[:selected],
    confidence: observed.first && observed.first[:confidence],
    clarify: observed.any? { |v| v[:clarify] },
    acceptable_hit: observed.any? { |v| acceptable.include?(v[:selected]) },
    must_not_route_to: must_not, status: status, labels: labels,
    verdicts: verdicts, error: (verdicts.find { |v| v[:error] } || {})[:error],
    frozen_at_sha_is_ancestor: frozen_ok
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

# First-class routing-quality metrics beyond pass/fail (counted over observed,
# non-ERROR verdicts): clarify rate, low-confidence rate, and — when replicas
# >= 2 — how often all replicas of one task picked the same top skill.
all_observed = results.flat_map { |r| r[:verdicts].reject { |v| v[:status] == "ERROR" } }
clarify_count = all_observed.count { |v| v[:clarify] }
low_conf_count = all_observed.count { |v| v[:confidence].is_a?(Numeric) && v[:confidence] < 0.5 }
# Replica-level error accounting: task-level `error` counts only fully
# unmeasured tasks, so a PASS+ERROR pair would otherwise report zero
# grader-errors while a replica silently went missing.
error_verdicts = results.sum { |r| r[:verdicts].count { |v| v[:status] == "ERROR" } }
partial_error_ids = results.select { |r| r[:labels].include?("partial_error") }.map { |r| r[:id] }
agreement_measured = 0
agreement_agree = 0
if replicas >= 2
  results.each do |r|
    obs = r[:verdicts].reject { |v| v[:status] == "ERROR" }
    next if obs.size < 2
    agreement_measured += 1
    agreement_agree += 1 if obs.map { |v| v[:selected] }.uniq.size == 1
  end
end

# baseline diff (newly failed / newly passed). The baseline is a prior report
# (a hash with a "results" array) or a bare results array. Reports from a
# different bank content or replica count are DIFFERENT RULERS (documented
# above): comparing them emits false regressions/improvements, so a
# demonstrated mismatch suppresses the diff instead of computing it. A bare
# results array carries no fingerprint — its comparability is unverifiable and
# is flagged as such rather than silently trusted.
newly_failed = []
newly_passed = []
baseline_comparable = nil
baseline_incomparable_reason = nil
if baseline_path && File.file?(baseline_path)
  base_json = JSON.parse(File.read(baseline_path))
  if base_json.is_a?(Hash)
    base_bank_sha = base_json.dig("routing_surface", "bank_sha256")
    base_replicas = base_json["replicas"] || 1 # legacy reports predate --replicas
    if base_bank_sha && base_bank_sha != routing_surface[:bank_sha256]
      baseline_comparable = false
      baseline_incomparable_reason = "bank content differs (baseline #{base_bank_sha[0, 12]}… vs current #{routing_surface[:bank_sha256][0, 12]}…)"
    elsif base_replicas != replicas
      baseline_comparable = false
      baseline_incomparable_reason = "replica count differs (baseline #{base_replicas} vs current #{replicas})"
    else
      baseline_comparable = base_bank_sha ? true : "unverified (baseline carries no bank fingerprint)"
    end
  else
    baseline_comparable = "unverified (bare results array carries no fingerprint)"
  end
  unless baseline_comparable == false
    base_results = base_json.is_a?(Hash) ? (base_json["results"] || []) : base_json
    base_status = base_results.to_h { |r| [r["id"], r["status"]] }
    results.each do |r|
      was = base_status[r[:id]]
      newly_failed << r[:id] if was == "PASS" && r[:status] == "FAIL"
      newly_passed << r[:id] if was == "FAIL" && r[:status] == "PASS"
    end
  end
end

report = {
  model: model, tasks: results.size, pass: passes, fail: fails.size, error: errors.size,
  replicas: replicas, verdicts: all_observed.size,
  error_verdicts: error_verdicts, partial_error_tasks: partial_error_ids,
  clarify_count: clarify_count, low_confidence_count: low_conf_count,
  replica_agreement: (replicas >= 2 ? { agree: agreement_agree, measured: agreement_measured } : nil),
  desc_budget_chars: desc_budget, routing_surface: routing_surface,
  co_change_bank_and_descriptions: co_change, co_change_check_available: co_change_check_ok,
  frozen_drift: drift.map { |r| r[:id] },
  baseline_comparable: baseline_comparable,
  baseline_incomparable_reason: baseline_incomparable_reason,
  newly_failed: newly_failed, newly_passed: newly_passed, results: results
}
File.write(json_path, JSON.pretty_generate(report)) if json_path

puts "eval-routing-bank (#{model}): #{passes}/#{results.size} pass, #{fails.size} fail, #{errors.size} grader-error"
puts "  arm: desc-budget-chars=#{desc_budget}" if desc_budget
unless all_observed.empty?
  line = "  clarify: #{clarify_count}/#{all_observed.size} verdicts, low-confidence(<0.5): #{low_conf_count}/#{all_observed.size}"
  line += ", replica top1 agreement: #{agreement_agree}/#{agreement_measured}" if replicas >= 2
  puts line
end
if error_verdicts.positive?
  puts "  ⚠ grader-error verdicts: #{error_verdicts}#{partial_error_ids.empty? ? '' : " (partially measured tasks: #{partial_error_ids.join(', ')})"}"
end
puts "  ⚠ co-change check unavailable: base ref #{base.inspect} not resolvable — could not verify bank/description co-change" unless co_change_check_ok
puts "  ⚠ co-change: this change touches BOTH the bank and a SKILL.md description (verify the bank was not edited to pass)" if co_change
puts "  ⚠ frozen-drift (not ancestor of HEAD, excluded from regression judgment): #{drift.map { |r| r[:id] }.join(', ')}" unless drift.empty?
unless fails.empty?
  puts "  FAIL:"
  fails.each do |r|
    tag = r[:labels].empty? ? "" : " [#{r[:labels].join(',')}]"
    obs = r[:verdicts].reject { |v| v[:status] == "ERROR" }
    got = obs.map { |v| v[:selected].inspect }.uniq.join(" | ")
    conf = obs.map { |v| v[:confidence] }.join(",")
    puts "    - #{r[:id]}: expected #{r[:expected]} got #{got} (conf #{conf})#{tag}"
  end
end
unless errors.empty?
  puts "  GRADER-ERROR:"
  errors.each { |r| puts "    - #{r[:id]}: #{r[:error]}" }
end
if baseline_comparable == false
  puts "  ⚠ baseline not compared — different ruler: #{baseline_incomparable_reason}"
elsif baseline_comparable.is_a?(String)
  puts "  ⚠ baseline comparability #{baseline_comparable}"
end
unless newly_failed.empty? && newly_passed.empty?
  puts "  vs baseline: newly_failed=#{newly_failed.join(',')} newly_passed=#{newly_passed.join(',')}"
end

# Advisory: never block on a routing miss. Only signal grader-infra breakage.
exit 3 if !results.empty? && errors.size == results.size
exit 0
