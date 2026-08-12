#!/usr/bin/env ruby
# frozen_string_literal: true

# F4 Tier-3 golden-trace behavioral replay (real headless agent + structural asserts).
#
# Runs each golden trace's trigger through a headless `claude -p` (stream-json) with
# DESTRUCTIVE tools disabled, captures which skills the REAL agent invokes, and makes
# STRUCTURAL assertions only (skill invoked / forbidden absent / no destructive
# command) — never exact wording, ordering, or tool count.
#
# This is a HIGHER-FIDELITY-but-stochastic signal than Tier-2 (it observes the actual
# agent, not a cheap model's opinion on descriptions). It is ADVISORY with a HUMAN
# verdict: the runner reports drift, it does NOT block a merge and is not wired into
# check-ccl-skills.sh. Run it manually / nightly until it has stability history.
#
# Usage:
#   eval-golden-trace.rb <repo-root> [--traces <dir>] [--max-turns N] [--timeout S]
#                        [--only <id>] [--limit N] [--json <path>] [--dry-run]
# Exit: 0 = ran (advisory); 2 = usage error; 3 = agent entirely unavailable.

require "json"
require "open3"
require "shellwords"
require "timeout"

def arg(flag, default = nil)
  i = ARGV.index(flag)
  i ? ARGV[i + 1] : default
end

root = ARGV[0]
if root.nil? || root.start_with?("-")
  warn "usage: eval-golden-trace.rb <repo-root> [--traces d] [--max-turns N] [--timeout S] [--only id] [--limit N] [--json p] [--dry-run]"
  exit 2
end
traces_dir = arg("--traces", File.join(root, "eval", "golden-traces"))
max_turns = (arg("--max-turns") || "4").to_i
timeout_s = (arg("--timeout") || "180").to_i
only = arg("--only")
limit = (l = arg("--limit")) ? l.to_i : nil
json_path = arg("--json")
dry_run = ARGV.include?("--dry-run")

OTHER_DESTRUCTIVE = [
  /\bgit\s+push\b.*(--force|\s-f\b)/, /\bgit\s+reset\s+--hard/,
  /\bdrop\s+table\b/i, /\bchmod\s+-R\s+777/, /:\(\)\s*\{.*\};/, /\bmkfs\b/, /\bgit\s+clean\s+-[a-z]*f/i
].freeze

# True if a shell command contains a destructive action. The rm check requires a
# recursive AND a force flag in the SAME rm segment (up to a command separator), so
# a benign `rm -r tmp && grep -f x` is not falsely flagged.
def destructive_command?(cmd)
  rm_hit = cmd.scan(/\brm\b[^;&|\n]*/i).any? do |seg|
    opts = seg.split(/\s--(?:\s|\z)/, 2).first.to_s # flags only; stop at the `--` terminator
    opts.match?(/(?:\A|\s)-[a-z]*r|--recursive/i) && opts.match?(/(?:\A|\s)-[a-z]*f|--force/i)
  end
  rm_hit || OTHER_DESTRUCTIVE.any? { |re| cmd =~ re }
end

trace_files = Dir[File.join(traces_dir, "*.json")].sort
if trace_files.empty?
  warn "eval_golden_no_traces: no *.json under #{traces_dir}"
  exit 2
end
traces = trace_files.map { |f| JSON.parse(File.read(f)) rescue (warn("eval_golden_parse_error: #{f}"); exit 2) }
if only
  traces.select! { |t| t["id"] == only }
  if traces.empty?
    warn "eval_golden_no_match: --only #{only.inspect} matched no trace id"
    exit 2
  end
end
traces = traces.first(limit) if limit

def ancestor?(root, sha)
  return false if sha.nil? || sha.to_s.empty?
  system("git", "-C", root, "merge-base", "--is-ancestor", sha, "HEAD", out: File::NULL, err: File::NULL)
end

# Robust subprocess run: readers start before write; write + wait + read collection
# all under ONE hard timeout; on timeout kill the pid and close pipes to unblock
# readers. (Same vetted pattern as eval-routing-bank.rb.)
def run_agent(root, max_turns, timeout_s, prompt)
  # Allowlist (not denylist): only read-only + Skill tools, so the replay can route
  # and inspect but cannot mutate anything (Bash/Edit/Write/NotebookEdit/cron/task
  # are all excluded by omission) — truly side-effect-free.
  cmd = ["claude", "-p", "--output-format", "stream-json", "--verbose",
         "--max-turns", max_turns.to_s, "--allowedTools", "Skill", "Read", "Grep", "Glob"]
  out = +""
  err = +""
  status = nil
  Open3.popen3(*cmd, chdir: root) do |stdin, stdout, stderr, wait_thr|
    out_t = Thread.new { stdout.read }
    err_t = Thread.new { stderr.read }
    begin
      Timeout.timeout(timeout_s) do
        begin
          stdin.write(prompt)
        rescue Errno::EPIPE, IOError
          # agent closed stdin early; exit status / stderr explains
        ensure
          stdin.close rescue nil
        end
        status = wait_thr.value
        out = out_t.value.to_s
        err = err_t.value.to_s
      end
    rescue Timeout::Error
      Process.kill("KILL", wait_thr.pid) rescue nil
      stdout.close rescue nil
      stderr.close rescue nil
      out_t.join(1)
      err_t.join(1)
      return [nil, "agent_timeout_#{timeout_s}s"]
    end
  end
  return [nil, "agent_exit_#{status.exitstatus}: #{err.strip[0, 200]}"] unless status&.success?
  [out, nil]
rescue Errno::ENOENT
  [nil, "claude_not_found"]
end

# Parse a stream-json transcript: invoked skills + executed shell commands.
def parse_transcript(stream)
  skills = []
  commands = []
  stream.each_line do |line|
    ev = JSON.parse(line) rescue next
    next unless ev["type"] == "assistant"
    (ev.dig("message", "content") || []).each do |c|
      next unless c["type"] == "tool_use"
      if c["name"] == "Skill"
        s = (c.dig("input", "skill") || c.dig("input", "command")).to_s
        skills << s.split(":").last unless s.empty?
      elsif c["name"] == "Bash"
        commands << c.dig("input", "command").to_s
      end
    end
  end
  [skills.uniq, commands]
end

if dry_run
  traces.each { |t| puts "#{t['id']} (#{t['hub_skill']}): #{t['trigger_prompt'][0, 60]}…" }
  exit 0
end

if (`command -v claude 2>/dev/null`.strip rescue "").empty?
  puts "eval-golden-trace: agent unavailable (claude CLI not found) — skipped (advisory)"
  exit 0
end

results = traces.map do |t|
  frozen_ref = t["frozen_at_sha"] == "root" ? `git -C #{Shellwords.escape(root)} rev-list --max-parents=0 HEAD`.lines.first.to_s.strip : t["frozen_at_sha"]
  frozen_ok = ancestor?(root, frozen_ref)
  stream, error = run_agent(root, max_turns, timeout_s, t["trigger_prompt"])
  invoked, commands = error ? [[], []] : parse_transcript(stream)
  a = t["assert"] || {}
  missing = (a["must_invoke_skill"] || []) - invoked
  forbidden_hit = (a["must_not_invoke_skill"] || []) & invoked
  destructive = a["no_destructive_command"] ? commands.select { |c| destructive_command?(c) } : []
  status =
    if !frozen_ok then "DRIFT"                         # frozen_at_sha not in history — excluded from pass/fail
    elsif error then "INCONCLUSIVE"                    # agent could not run
    elsif !destructive.empty? || !forbidden_hit.empty? then "FAIL"  # always fail, even with no routing
    elsif invoked.empty? then "INCONCLUSIVE"           # agent did not route within max-turns
    elsif missing.empty? then "PASS"
    else "FAIL"
    end
  { id: t["id"], hub: t["hub_skill"], status: status, invoked: invoked, error: error,
    missing: missing, forbidden_hit: forbidden_hit, destructive: destructive, frozen_ok: frozen_ok }
end

# Drifted traces are excluded from pass/fail (their expectation was frozen at a
# non-ancestor sha, so they are not a trustworthy baseline).
considered = results.reject { |r| r[:status] == "DRIFT" }
drifted = results.select { |r| r[:status] == "DRIFT" }
passes = considered.count { |r| r[:status] == "PASS" }
fails = considered.select { |r| r[:status] == "FAIL" }
inconclusive = considered.select { |r| r[:status] == "INCONCLUSIVE" }

report = { tasks: results.size, considered: considered.size, pass: passes, fail: fails.size,
           inconclusive: inconclusive.size, frozen_drift: drifted.map { |r| r[:id] }, results: results }
File.write(json_path, JSON.pretty_generate(report)) if json_path

puts "eval-golden-trace: #{passes}/#{considered.size} pass, #{fails.size} fail, #{inconclusive.size} inconclusive" \
     "#{drifted.empty? ? '' : ", #{drifted.size} drift(excluded)"} (HUMAN-VERDICT — advisory)"
puts "  ⚠ frozen-drift (not ancestor of HEAD, excluded): #{drifted.map { |r| r[:id] }.join(', ')}" unless drifted.empty?
results.each do |r|
  next if r[:status] == "PASS"
  detail = r[:error] || "invoked=#{(r[:invoked] || []).inspect} missing=#{(r[:missing] || []).inspect} forbidden=#{(r[:forbidden_hit] || []).inspect} destructive=#{(r[:destructive] || []).inspect}"
  puts "  #{r[:status]} #{r[:id]} (#{r[:hub]}): #{detail}"
end

# Advisory: routing drift never blocks; only signal that the agent could not run at all.
exit 3 if !considered.empty? && inconclusive.size == considered.size && considered.all? { |r| r[:error] }
exit 0
