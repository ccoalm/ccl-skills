#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "rbconfig"
require "tempfile"

EVIDENCE_DIR = File.expand_path(__dir__)
REPO_ROOT = File.expand_path("../../..", EVIDENCE_DIR)
PRESERVATION_RUNNER = File.join(EVIDENCE_DIR, "red-baseline-023-c3-preservation.rb")
REGRADER = File.join(EVIDENCE_DIR, "red-baseline-023-c3-regrade.rb")
CANONICAL_RAW = File.join(EVIDENCE_DIR, "red-baseline-023-c3-worktree-safe-r8.json")
CANONICAL_TIGHTEN_RAW = File.join(EVIDENCE_DIR, "red-baseline-023-c3-tighten-current-r9.json")
CANONICAL_CASES = [
  ["red-baseline-023-c3-tighten-current-r9.json", "red-baseline-023-c3-tighten-current-r9-regrade.json", ["tighten-eight-class-walk"]],
  ["red-baseline-023-c3-worktree-safe-r8.json", "red-baseline-023-c3-worktree-safe-r8-regrade.json", ["worktree-one-fetch-order"]]
].freeze
CANONICAL_FILE_SHA256 = {
  "red-baseline-023-c3-tighten-current-r9.json" => "7140b7993f8953ec7c9672b3b1659a814da8b54f0c5670f453eb166837be897f",
  "red-baseline-023-c3-tighten-current-r9-regrade.json" => "b07296773870f6969ecc571db7d2344362bcb38b0710bea1476088c81e0f9ebe",
  "red-baseline-023-c3-worktree-safe-r8.json" => "24afe65299c1174c1945635226eca0ebd78ffaf89a104fbdcb30af85f2be1bc1",
  "red-baseline-023-c3-worktree-safe-r8-regrade.json" => "bfb218da2a31783cc1d81babb1c180df30c306f75b8d4df7f024bd707fd8ee76"
}.freeze
AUDIT_ONLY_MANIFEST = File.join(EVIDENCE_DIR, "audit-only-evidence.json")
AUDIT_ONLY_MANIFEST_SHA256 = "7f2837877ac4115d38cd4c549267185d7be8851a26f9bdd9280c69e287cc34b5"
REJECTION = "refusing non-canonical partial replay"
OWNER_BODY_BINDINGS = [
  ["red-baseline-023-c3-tighten-current-r9.json", "tighten-eight-class-walk", "skills/tighten-doc/SKILL.md", "skills/tighten-doc/references/session-vantage-leakage.md"],
  ["red-baseline-023-c3-worktree-safe-r8.json", "worktree-one-fetch-order", "skills/worktree-isolation/SKILL.md", "skills/worktree-isolation/references/shared-branch-rebase.md"]
].freeze
AUDIT_FILE_SHA256 = {
  "red-baseline-023-c3-safe-mode-r6.json" => "562c0fb130e631cd1ffa1f56dc28ab89b46f42fe96a164a7a2e65444a07516da",
  "red-baseline-023-c3-safe-mode-r6-regrade.json" => "d1fe811bf0f55f01c4c98309c40740feecf82cfbb32554ed352a505bc985e36d",
  "red-baseline-023-c3-tighten-strict-r5.json" => "cde706996bf1a32c6334848011171dadebdedbcd958d4dc8df01cfd44bdb0e8b",
  "red-baseline-023-c3-tighten-strict-r5-regrade.json" => "016d0d8b87671d200ef0b0e8365823e312f1228ea9904f7e1d719700069dae43",
  "red-baseline-023-c3-worktree-strict-r4.json" => "afd02d08b8c9c4521725c472a7ad0137072c7e4e8d4ad52622ee01cbf0663fb8",
  "red-baseline-023-c3-worktree-strict-r4-regrade.json" => "6e49926ab2334cd52e09b8ba7905d290df703945b5b4491bfe4bc2a22a11ae65"
}.freeze
R8_ADVISORY_REASON = "The pre-repair runner rendered the absent base reference as a named empty block, so this arm does not support a base-to-head claim."
CANONICAL_ARM_STATUS_ALLOWLIST = {
  "red-baseline-023-c3-worktree-safe-r8.json" => {
    ["worktree-one-fetch-order", "base"] => { "status" => "advisory", "reason" => R8_ADVISORY_REASON }
  }
}.freeze
CANONICAL_MISSED_DRIFT_ALLOWLIST = {
  ["red-baseline-023-c3-worktree-safe-r8.json", "worktree-one-fetch-order", "base", 1] => {
    "runner_time" => %w[exact-topology-command no-malformed-topology-command review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor],
    "current_regrade" => %w[exact-topology-command no-malformed-topology-command rebase-after-check review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor]
  },
  ["red-baseline-023-c3-worktree-safe-r8.json", "worktree-one-fetch-order", "mutant", 1] => {
    "runner_time" => %w[target-refresh exact-topology-command right-zero-stop review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor],
    "current_regrade" => %w[exact-topology-command right-zero-stop rebase-after-check review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor]
  },
  ["red-baseline-023-c3-worktree-safe-r8.json", "worktree-one-fetch-order", "mutant", 2] => {
    "runner_time" => %w[one-branch-fetch-before-push literal-fetch-head-oid exact-topology-command no-malformed-topology-command right-zero-stop review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor],
    "current_regrade" => %w[one-branch-fetch-before-push literal-fetch-head-oid exact-topology-command no-malformed-topology-command right-zero-stop rebase-after-check review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor]
  }
}.freeze
C3_LANDING_PATH = "specs/023-agent-native-repo-borrowing/c3-release-gate-repair.md"
C3_GATE_ENTRYPOINT = "Makefile"
C3_EVIDENCE_DIR_PATH = "specs/023-agent-native-repo-borrowing/evidence"
C3_EVIDENCE_PREFIX = "#{C3_EVIDENCE_DIR_PATH}/red-baseline-023-c3-"
C3_EVIDENCE_JSON_PREFIXES = %w[red-baseline-023-c3- c3-].freeze
C3_AUDIT_MANIFEST = "#{C3_EVIDENCE_DIR_PATH}/audit-only-evidence.json"
C3_CONTRACT_PATH = "#{C3_EVIDENCE_DIR_PATH}/test_red_baseline_023_c3_regrade.rb"
C3_REGISTER_CONTROL_PATHS = [
  "skills/skill-extraction-workflow/references/source-register.md",
  "skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb",
  "skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh"
].freeze
C3_CONTROL_WORKTREE_PATHS = [
  C3_LANDING_PATH,
  C3_AUDIT_MANIFEST,
  C3_CONTRACT_PATH,
  *C3_REGISTER_CONTROL_PATHS,
  ":(glob)#{C3_EVIDENCE_PREFIX}*",
  ":(glob)#{C3_EVIDENCE_DIR_PATH}/c3-*.json"
].freeze
C3_MAKE_TEST_COMMAND = "ruby #{C3_CONTRACT_PATH} --candidate"
C3_MEASURED_OWNER_PATHS = OWNER_BODY_BINDINGS.flat_map { |_raw, _task, skill_path, reference_path| [skill_path, reference_path] }.freeze
C3_STRICT_EVIDENCE_ENV = "CCL_C3_STRICT_EVIDENCE"
C3_REFRESH_GUIDANCE = <<~GUIDANCE.strip
  Refresh requires a clean committed candidate and explicit provider authorization. From the repository root run:
    CCL_C3_ALLOW_MODEL_REFRESH=1 ONLY=tighten-eight-class-walk ARMS=base,head,mutant ruby specs/023-agent-native-repo-borrowing/evidence/red-baseline-023-c3-preservation.rb . 2 claude-haiku-4-5 dev HEAD > /tmp/c3-tighten-refresh.json
    ruby specs/023-agent-native-repo-borrowing/evidence/red-baseline-023-c3-regrade.rb /tmp/c3-tighten-refresh.json > /tmp/c3-tighten-refresh-regrade.json
    CCL_C3_ALLOW_MODEL_REFRESH=1 ONLY=worktree-one-fetch-order ARMS=base,head,mutant ruby specs/023-agent-native-repo-borrowing/evidence/red-baseline-023-c3-preservation.rb . 2 claude-haiku-4-5 dev HEAD > /tmp/c3-worktree-refresh.json
    ruby specs/023-agent-native-repo-borrowing/evidence/red-baseline-023-c3-regrade.rb /tmp/c3-worktree-refresh.json > /tmp/c3-worktree-refresh-regrade.json
  If local dev is unavailable, substitute the trusted origin/dev ref; if neither resolves, restore a trusted fixed base before refreshing. Land new versioned raw/regrade files, update CANONICAL_CASES, CANONICAL_FILE_SHA256, OWNER_BODY_BINDINGS, AUDIT_FILE_SHA256, and AUDIT_ONLY_MANIFEST_SHA256, classify superseded files in audit-only-evidence.json, then rerun this contract with --candidate. Never overwrite the historical raw records.
GUIDANCE

def run_regrader(path)
  Open3.capture3(RbConfig.ruby, REGRADER, path)
end

def regrade_payload(payload)
  Tempfile.create(["c3-regrade-", ".json"]) do |file|
    file.write(JSON.generate(payload))
    file.flush
    stdout, stderr, status = run_regrader(file.path)
    abort "synthetic regrade rejected: #{stderr}" unless status.success?
    return JSON.parse(stdout)
  end
end

def replace_answer(detail, answer)
  detail["raw"] = answer
  detail["answer_sha256"] = Digest::SHA256.hexdigest(answer)
end

def git_blob(rev, path)
  stdout, stderr, status = Open3.capture3("git", "show", "#{rev}:#{path}", chdir: REPO_ROOT)
  abort "cannot read #{rev}:#{path}: #{stderr}" unless status.success?
  stdout
end

def strip_frontmatter(text)
  match = text.match(/\A---\n.*?\n---\n/m)
  match ? text[match.end(0)..] : text
end

def resolvable_commit(ref)
  stdout, _stderr, status = Open3.capture3(
    "git", "rev-parse", "--verify", "#{ref}^{commit}", chdir: REPO_ROOT
  )
  status.success? ? stdout.strip : nil
end

def c3_landing_path?(path)
  c3_json_path = File.dirname(path) == C3_EVIDENCE_DIR_PATH &&
    File.extname(path) == ".json" && c3_evidence_json_name?(File.basename(path))
  path == C3_GATE_ENTRYPOINT ||
    path == C3_LANDING_PATH ||
    path == C3_AUDIT_MANIFEST ||
    path == C3_CONTRACT_PATH ||
    C3_REGISTER_CONTROL_PATHS.include?(path) ||
    path.start_with?(C3_EVIDENCE_PREFIX) ||
    c3_json_path ||
    C3_MEASURED_OWNER_PATHS.include?(path)
end

def c3_evidence_json_name?(name)
  C3_EVIDENCE_JSON_PREFIXES.any? { |prefix| name.start_with?(prefix) }
end

def c3_binding_required?(fixed_base_ref:, override_matches_head:, worktree_changed:, changed_paths:)
  fixed_base_ref.nil? || override_matches_head || worktree_changed || changed_paths.any? do |path|
    c3_landing_path?(path)
  end
end

def dirty_owner_blocking?(candidate_mode:, strict:)
  candidate_mode || strict
end

def make_test_candidate_invocation?(text)
  lines = text.lines
  target_indexes = lines.each_index.select do |index|
    line = lines[index]
    next false if line.start_with?("\t") || line.lstrip.start_with?("#") || !line.include?(":")

    line.split(":", 2).first.split.include?("test")
  end
  return false unless target_indexes.length == 1

  recipe = lines.drop(target_indexes.first + 1).take_while { |line| line.start_with?("\t") || line.strip.empty? }
  recipe.any? { |line| line.chomp == "\t#{C3_MAKE_TEST_COMMAND}" }
end

class EvidenceIntegrityError < StandardError; end

def verify_sha256!(path, expected, label)
  actual = Digest::SHA256.file(path).hexdigest
  raise EvidenceIntegrityError, "#{label} drifted: #{actual}" unless actual == expected

  true
end

def assert_same_size_mutations_rejected!(path, expected, label)
  bytes = File.binread(path)
  abort "#{label} is empty" if bytes.empty?

  [0, bytes.bytesize / 2, bytes.bytesize - 1].uniq.each do |offset|
    Tempfile.create(["c3-evidence-mutant-", ".json"]) do |file|
      mutant = bytes.dup
      mutant.setbyte(offset, mutant.getbyte(offset) ^ 1)
      file.binmode
      file.write(mutant)
      file.flush
      begin
        verify_sha256!(file.path, expected, "#{label} mutant")
        abort "same-size #{label} mutation was accepted at byte #{offset}"
      rescue EvidenceIntegrityError
        # Expected: exercise the same fail-closed verifier used for the real file.
      end
    end
  end
end

def abort_stale_evidence(reason)
  abort "#{reason}\n#{C3_REFRESH_GUIDANCE}"
end

abort "HEAD override could suppress C3 candidate binding" unless c3_binding_required?(
  fixed_base_ref: "dev", override_matches_head: true, worktree_changed: false, changed_paths: []
)
abort "missing fixed base did not fail closed" unless c3_binding_required?(
  fixed_base_ref: nil, override_matches_head: false, worktree_changed: false, changed_paths: []
)
abort "measured owner drift did not trigger C3 candidate binding" unless c3_binding_required?(
  fixed_base_ref: "dev", override_matches_head: false, worktree_changed: false,
  changed_paths: ["skills/tighten-doc/SKILL.md"]
)
abort "measured owner carrier inventory drifted" unless C3_MEASURED_OWNER_PATHS.length == 4
abort "measured owner carrier escaped the C3 surface" unless C3_MEASURED_OWNER_PATHS.all? { |path| c3_landing_path?(path) }
abort "unmeasured owner-package path entered the C3 surface" if c3_landing_path?("skills/worktree-isolation/references/unrelated.md")
abort "Makefile escaped the C3 surface" unless c3_landing_path?(C3_GATE_ENTRYPOINT)
abort "C3 contract escaped the C3 surface" unless c3_landing_path?(C3_CONTRACT_PATH)
abort "register control inventory drifted" unless C3_REGISTER_CONTROL_PATHS.length == 3
abort "register control escaped the C3 surface" unless C3_REGISTER_CONTROL_PATHS.all? { |path| c3_landing_path?(path) }
abort "unrelated extraction script entered the C3 surface" if c3_landing_path?("skills/skill-extraction-workflow/scripts/unrelated.rb")
abort "non-prefix C3 evidence escaped classification" unless c3_evidence_json_name?("c3-extra-evidence.json")
abort "c3- evidence path escaped the C3 surface" unless c3_landing_path?("#{C3_EVIDENCE_DIR_PATH}/c3-extra-evidence.json")
abort "sibling round evidence entered C3 classification" if c3_evidence_json_name?("red-baseline-023-II.json")
abort "sibling round evidence entered the C3 surface" if c3_landing_path?("#{C3_EVIDENCE_DIR_PATH}/red-baseline-023-II.json")
abort "unchanged non-C3 candidate forced historical binding" if c3_binding_required?(
  fixed_base_ref: "dev", override_matches_head: false, worktree_changed: false, changed_paths: []
)
abort "candidate mode allowed dirty measured owners" unless dirty_owner_blocking?(candidate_mode: true, strict: false)
abort "strict evidence mode allowed dirty measured owners" unless dirty_owner_blocking?(candidate_mode: false, strict: true)
abort "ordinary in-progress owner edit blocked the repository suite" if dirty_owner_blocking?(candidate_mode: false, strict: false)
_blocked_stdout, blocked_stderr, blocked_status = Open3.capture3(
  { "CCL_C3_ALLOW_MODEL_REFRESH" => nil }, RbConfig.ruby, PRESERVATION_RUNNER
)
abort "preservation runner allowed an unapproved model refresh" if blocked_status.success?
abort "preservation runner lacks the provider opt-in diagnostic" unless blocked_stderr.include?("CCL_C3_ALLOW_MODEL_REFRESH=1")
_enabled_stdout, enabled_stderr, enabled_status = Open3.capture3(
  { "CCL_C3_ALLOW_MODEL_REFRESH" => "1" }, RbConfig.ruby, PRESERVATION_RUNNER
)
abort "preservation runner opt-in did not reach argument validation" if enabled_status.success?
abort "preservation runner opt-in produced the wrong validation" unless enabled_stderr.include?("usage: red-baseline-023-c3-preservation.rb")

makefile_head = git_blob("HEAD", C3_GATE_ENTRYPOINT)
abort "committed make test no longer forces C3 candidate mode" unless make_test_candidate_invocation?(makefile_head)
makefile_without_candidate = makefile_head.sub("\t#{C3_MAKE_TEST_COMMAND}\n", "\t#{C3_MAKE_TEST_COMMAND.delete_suffix(" --candidate")}\n")
abort "make test accepted a C3 invocation without --candidate" if make_test_candidate_invocation?(makefile_without_candidate)
makefile_decoy = "other:\n\t#{C3_MAKE_TEST_COMMAND}\n\ntest:\n\t@true\n"
abort "C3 candidate command outside test target was accepted" if make_test_candidate_invocation?(makefile_decoy)
makefile_duplicate_target = "#{makefile_head}\ntest:\n\t@true\n"
abort "duplicate test target could replace the C3 candidate recipe" if make_test_candidate_invocation?(makefile_duplicate_target)
makefile_multi_target = "#{makefile_head}\nfoo test:\n\t@true\n"
abort "multi-target test rule could replace the C3 candidate recipe" if make_test_candidate_invocation?(makefile_multi_target)
abort "unrelated Makefile target broke the C3 invocation" unless make_test_candidate_invocation?("#{makefile_head}\nother:\n\t@true\n")
makefile_path = File.join(REPO_ROOT, C3_GATE_ENTRYPOINT)
abort "worktree make test no longer forces C3 candidate mode" unless File.file?(makefile_path) &&
  make_test_candidate_invocation?(File.read(makefile_path))
make_probe_parent_env = %w[MAKEFLAGS MFLAGS GNUMAKEFLAGS].to_h { |key| [key, ENV[key]] }
begin
  # Exercise the real probe under a hostile inherited flag on every run. GNU Make
  # propagates MAKEFLAGS through recipes; `q` or `t` would otherwise suppress the
  # dry-run command or change its status and make an unchanged candidate false-red.
  # Keep this poison list independently spelled from the child deletion map: if a
  # deletion key erodes, the retained poison makes this same production call red.
  %w[MAKEFLAGS MFLAGS GNUMAKEFLAGS].each { |key| ENV[key] = "-q" }
  abort "make probe parent poison inactive" unless %w[MAKEFLAGS MFLAGS GNUMAKEFLAGS].all? { |key| ENV[key] == "-q" }
  make_dry_stdout, make_dry_stderr, make_dry_status = Open3.capture3(
    { "MAKEFLAGS" => nil, "MFLAGS" => nil, "GNUMAKEFLAGS" => nil },
    "make", "--no-print-directory", "-n", "test", chdir: REPO_ROOT
  )
ensure
  make_probe_parent_env.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end
abort "cannot resolve effective make test recipe: #{make_dry_stderr}" unless make_dry_status.success?
effective_c3_invocations = make_dry_stdout.lines.count { |line| line.chomp == C3_MAKE_TEST_COMMAND }
abort "effective make test must invoke C3 candidate mode exactly once" unless effective_c3_invocations == 1

canonical_files = CANONICAL_CASES.flat_map { |raw_name, regrade_name, _tasks| [raw_name, regrade_name] }.sort
abort "canonical digest inventory drifted" unless CANONICAL_FILE_SHA256.keys.sort == canonical_files
CANONICAL_FILE_SHA256.each do |file_name, expected_sha256|
  path = File.join(EVIDENCE_DIR, file_name)
  verify_sha256!(path, expected_sha256, "canonical evidence #{file_name}")
  assert_same_size_mutations_rejected!(path, expected_sha256, "canonical evidence #{file_name}")
end

force_candidate = ARGV.delete("--candidate")
abort "usage: #{File.basename(__FILE__)} [--candidate]" unless ARGV.empty?
# Fixed discovery decides whether this C3 landing changed. CCL_SKILL_BASE_REF
# may add a comparison range, but it never replaces fixed discovery and cannot
# suppress binding. A checkout lacking both dev and origin/dev therefore enters
# the unconditional fail-closed path even when an override is present.
override_ref = ENV["CCL_SKILL_BASE_REF"].to_s.strip
fixed_base_ref = %w[dev origin/dev].find { |candidate| resolvable_commit(candidate) }
head_oid = resolvable_commit("HEAD")
abort "cannot resolve C3 landing HEAD" if head_oid.nil?
override_oid = if override_ref.empty?
                 nil
               else
                 resolvable_commit(override_ref) || abort("cannot resolve CCL_SKILL_BASE_REF #{override_ref}")
               end
comparison_refs = [fixed_base_ref, (override_ref unless override_ref.empty?)].compact.uniq
changed_paths = comparison_refs.flat_map do |base_ref|
  changed_output, changed_error, changed_status = Open3.capture3(
    "git", "diff", "--no-renames", "--name-only", "#{base_ref}...HEAD", chdir: REPO_ROOT
  )
  abort "cannot compare C3 landing base #{base_ref}: #{changed_error}" unless changed_status.success?
  changed_output.lines.map(&:strip)
end
control_status, control_status_error, control_status_result = Open3.capture3(
  "git", "status", "--porcelain=v1", "--untracked-files=all", "--",
  *C3_CONTROL_WORKTREE_PATHS, chdir: REPO_ROOT
)
abort "cannot inspect C3 control worktree: #{control_status_error}" unless control_status_result.success?
c3_landing_changed = c3_binding_required?(
  fixed_base_ref: fixed_base_ref,
  override_matches_head: !override_oid.nil? && override_oid == head_oid,
  worktree_changed: !control_status.empty?,
  changed_paths: changed_paths.uniq
)
candidate_mode = force_candidate || c3_landing_changed
unless control_status.empty?
  abort "C3 gate/evidence control paths are dirty:\n#{control_status}\nCommit or discard these control-plane edits before using the clean C3 verdict."
end

# Evidence freshness is unconditional. After a measured carrier change lands on
# dev, dev...HEAD is empty; gating only on that diff would silently accept a
# later dev snapshot whose model-visible body no longer matches the evidence.
owner_status, owner_status_err, owner_status_result = Open3.capture3(
  "git", "status", "--porcelain=v1", "--", *C3_MEASURED_OWNER_PATHS, chdir: REPO_ROOT
)
abort "cannot inspect C3 measured evidence carrier paths: #{owner_status_err}" unless owner_status_result.success?
owner_dirty = !owner_status.empty?
strict_evidence = ENV[C3_STRICT_EVIDENCE_ENV] == "1"
if owner_dirty && dirty_owner_blocking?(candidate_mode: candidate_mode, strict: strict_evidence)
  abort_stale_evidence("C3 measured evidence carrier paths are dirty:\n#{owner_status}")
end
OWNER_BODY_BINDINGS.each do |raw_name, task, skill_path, reference_path|
  reference = File.basename(reference_path)
  skill_body = strip_frontmatter(git_blob("HEAD", skill_path))
  reference_body = git_blob("HEAD", reference_path)
  assembled_body = "#{skill_body}\n\n---\n# reference: #{reference}\n#{reference_body}"
  expected_body_sha256 = JSON.parse(File.read(File.join(EVIDENCE_DIR, raw_name))).fetch("results").fetch(task).fetch("head").fetch("body_sha256")
  actual_body_sha256 = Digest::SHA256.hexdigest(assembled_body)
  abort_stale_evidence("#{raw_name}: current owner body makes C3 evidence stale: #{actual_body_sha256}") unless actual_body_sha256 == expected_body_sha256
end

if owner_dirty
  puts "c3_owner_worktree_dirty_evidence_pending"
elsif candidate_mode
  puts "c3_candidate_binding_enforced"
else
  puts "c3_evidence_binding_current_no_c3_surface_changes"
end

CANONICAL_CASES.each do |raw_name, regrade_name, _canonical_tasks|
  raw_path = File.join(EVIDENCE_DIR, raw_name)
  stdout, stderr, status = run_regrader(raw_path)
  abort "canonical fixture #{raw_name} rejected: #{stderr}" unless status.success?
  actual = JSON.parse(stdout)
  expected = JSON.parse(File.read(File.join(EVIDENCE_DIR, regrade_name)))
  regeneration = "ruby #{REGRADER} #{raw_path} > #{File.join(EVIDENCE_DIR, regrade_name)}"
  abort "#{regrade_name}: committed regrade is stale; regenerate with: #{regeneration}" unless actual == expected

  raw_results = JSON.parse(File.read(raw_path)).fetch("results")
  declared_arm_statuses = {}
  declared_missed_drifts = {}
  raw_results.each do |task, runner_result|
    regraded_result = expected.fetch("results").fetch(task)
    %w[base head mutant].each do |arm|
      runner_score = { "pass" => runner_result.fetch(arm).fetch("pass"), "of" => runner_result.fetch(arm).fetch("of") }
      abort "#{regrade_name}: runner-time score missing for #{task}/#{arm}" unless regraded_result.fetch("runner_time_scores").fetch(arm) == runner_score
      runner_details = runner_result.fetch(arm).fetch("details")
      regraded_details = regraded_result.fetch("arms").fetch(arm).fetch("details")
      abort "#{regrade_name}: round count drifted for #{task}/#{arm}" unless runner_details.length == regraded_details.length
      runner_details.each_with_index do |runner_detail, index|
        regraded_detail = regraded_details.fetch(index)
        abort "#{regrade_name}: round identity drifted for #{task}/#{arm}" unless runner_detail.fetch("round") == regraded_detail.fetch("round")
        next if runner_detail.fetch("missed") == regraded_detail.fetch("missed")

        declared_missed_drifts[[raw_name, task, arm, index + 1]] = {
          "runner_time" => runner_detail.fetch("missed"),
          "current_regrade" => regraded_detail.fetch("missed")
        }
      end
      %w[status reason].each do |field|
        abort "#{regrade_name}: arm #{field} drifted for #{task}/#{arm}" unless regraded_result.fetch("arms").fetch(arm)[field] == runner_result.fetch(arm)[field]
      end
      if runner_result.fetch(arm).key?("status") || runner_result.fetch(arm).key?("reason")
        declared_arm_statuses[[task, arm]] = {
          "status" => runner_result.fetch(arm)["status"],
          "reason" => runner_result.fetch(arm)["reason"]
        }
      end
    end
    pass_count_changed = %w[base head mutant].any? do |arm|
      runner_result.fetch(arm).fetch("pass") != regraded_result.fetch("arms").fetch(arm).fetch("pass")
    end
    abort "#{regrade_name}: canonical pass counts drifted for #{task}" if pass_count_changed
  end
  expected_arm_statuses = CANONICAL_ARM_STATUS_ALLOWLIST.fetch(raw_name, {})
  abort "#{raw_name}: canonical arm status is not allowlisted" unless declared_arm_statuses == expected_arm_statuses
  expected_missed_drifts = CANONICAL_MISSED_DRIFT_ALLOWLIST.select { |(file_name, _task, _arm, _round), _value| file_name == raw_name }
  abort "#{raw_name}: canonical runner/regrade missed-detail drift is not allowlisted" unless declared_missed_drifts == expected_missed_drifts
  attestation = expected.fetch("provider_attestation")
  abort "#{regrade_name}: provider attestation status drifted" unless attestation == {
    "status" => "unavailable",
    "reason" => "Claude CLI did not expose a signed provider request/response attestation."
  }
end

verify_sha256!(AUDIT_ONLY_MANIFEST, AUDIT_ONLY_MANIFEST_SHA256, "audit-only manifest")
assert_same_size_mutations_rejected!(AUDIT_ONLY_MANIFEST, AUDIT_ONLY_MANIFEST_SHA256, "audit-only manifest")
audit_only = JSON.parse(File.read(AUDIT_ONLY_MANIFEST))
abort "audit-only manifest status changed" unless audit_only["status"] == "audit-only"
listed_audit_files = audit_only.fetch("records").flat_map { |record| record.fetch("files") }.sort
canonical_tasks_by_file = CANONICAL_CASES.each_with_object({}) do |(raw_name, regrade_name, tasks), index|
  index[raw_name] = tasks
  index[regrade_name] = tasks
end
actual_evidence_files = Dir.glob(File.join(EVIDENCE_DIR, "*.json")).map { |path| File.basename(path) }.select { |name| c3_evidence_json_name?(name) }.sort
classified_evidence_files = (canonical_files + listed_audit_files).sort
abort "C3 evidence classification is incomplete" unless classified_evidence_files == actual_evidence_files
abort "audit-only evidence entered canonical cases" unless (listed_audit_files & canonical_files).empty?
abort "audit-only file set changed" unless listed_audit_files == AUDIT_FILE_SHA256.keys.sort
AUDIT_FILE_SHA256.each do |file_name, expected_sha256|
  actual_sha256 = Digest::SHA256.file(File.join(EVIDENCE_DIR, file_name)).hexdigest
  abort "audit-only file drifted: #{file_name}" unless actual_sha256 == expected_sha256
end

audit_only.fetch("records").each do |record|
  demotion_reason = record.fetch("demotion_reason")
  allowed_demotion_reasons = %w[superseded-noncanonical-grader post-hoc-rubric-drift]
  abort "audit-only record has an unknown demotion reason" unless allowed_demotion_reasons.include?(demotion_reason)
  reproducibility = record.fetch("reproducibility")
  abort "audit-only record overclaims reproducibility" unless reproducibility.fetch("status") == "unavailable" && !reproducibility.fetch("reason").empty?
  if demotion_reason == "post-hoc-rubric-drift"
    regrades = record.fetch("files").grep(/-regrade\.json\z/).map do |evidence_name|
      JSON.parse(File.read(File.join(EVIDENCE_DIR, evidence_name)))
    end
    has_declared_drift = regrades.any? do |regrade|
      regrade.fetch("results").values.any? do |result|
        %w[base head mutant].any? do |arm|
          result.fetch("runner_time_scores").fetch(arm).fetch("pass") != result.fetch("arms").fetch(arm).fetch("pass")
        end
      end
    end
    abort "post-hoc audit record no longer contains its declared score drift" unless has_declared_drift
  end
  record_tasks = record.fetch("tasks").sort
  record.fetch("files").each do |evidence_name|
    actual_tasks = JSON.parse(File.read(File.join(EVIDENCE_DIR, evidence_name))).fetch("results").keys.sort
    abort "audit-only task coverage drifted for #{evidence_name}" unless actual_tasks == record_tasks
  end
  superseded_tasks = record.fetch("superseded_by").map do |superseder|
    canonical_tasks = canonical_tasks_by_file.fetch(superseder.fetch("file"), [])
    abort "audit-only record lacks a canonical superseder" unless canonical_tasks.include?(superseder.fetch("task"))
    superseder.fetch("task")
  end.sort
  abort "audit-only tasks lack per-task superseders" unless superseded_tasks == record_tasks
end

CANONICAL_CASES.each do |raw_name, regrade_name, canonical_tasks|
  [raw_name, regrade_name].each do |evidence_name|
    evidence_results = JSON.parse(File.read(File.join(EVIDENCE_DIR, evidence_name))).fetch("results")
    actual_tasks = evidence_results.keys.sort
    abort "canonical task classification drifted for #{evidence_name}" unless canonical_tasks.sort == actual_tasks
    canonical_tasks.each do |task|
      abort "#{evidence_name}: canonical task marked audit-only" if evidence_results.fetch(task)["status"] == "audit-only"
    end
  end
end

source = JSON.parse(File.read(CANONICAL_RAW))
mutations = {
  "missing canonical" => ->(payload) { payload.delete("canonical") },
  "missing selected_arms" => ->(payload) { payload.delete("selected_arms") },
  "partial selected_arms" => ->(payload) { payload["selected_arms"] = %w[head mutant] }
}

mutations.each do |name, mutate|
  payload = Marshal.load(Marshal.dump(source))
  mutate.call(payload)
  Tempfile.create(["c3-regrade-", ".json"]) do |file|
    file.write(JSON.generate(payload))
    file.flush
    _stdout, case_stderr, case_status = run_regrader(file.path)
    abort "#{name}: non-canonical raw unexpectedly accepted" if case_status.success?
    abort "#{name}: wrong rejection: #{case_stderr}" unless case_stderr.include?(REJECTION)
  end
end

unknown_task = Marshal.load(Marshal.dump(source))
renamed_task = unknown_task.fetch("results").delete("worktree-one-fetch-order")
unknown_task.fetch("results")["renamed-worktree-task"] = renamed_task
Tempfile.create(["c3-regrade-", ".json"]) do |file|
  file.write(JSON.generate(unknown_task))
  file.flush
  _stdout, case_stderr, case_status = run_regrader(file.path)
  abort "unknown task id was accepted" if case_status.success?
  abort "unknown task id produced wrong rejection: #{case_stderr}" unless case_stderr.include?("unknown task id renamed-worktree-task")
end

answer_hash_mutant = Marshal.load(Marshal.dump(source))
answer_hash_mutant.fetch("results").fetch("worktree-one-fetch-order").fetch("head").fetch("details").first["raw"] << "\ncorrupted"
Tempfile.create(["c3-regrade-", ".json"]) do |file|
  file.write(JSON.generate(answer_hash_mutant))
  file.flush
  _stdout, case_stderr, case_status = run_regrader(file.path)
  abort "answer/hash mismatch was accepted" if case_status.success?
  abort "answer/hash mismatch produced wrong rejection: #{case_stderr}" unless case_stderr.include?("answer sha256 mismatch")
end

ordered = <<~ANSWER
  git fetch origin
  git fetch origin mybr
  remote_oid=$(git rev-parse FETCH_HEAD)
  git rev-list --left-right --count mybr...$remote_oid # 右侧 > 0 即停止 rebase
  git rebase origin/main
  git push --force-with-lease=mybr:$remote_oid origin mybr
  git fetch origin mybr
  失效证据：thread / approval / mergeable / CI / commit hash / 行锚
ANSWER

order_mutant = Marshal.load(Marshal.dump(source))
order_detail = order_mutant.fetch("results").fetch("worktree-one-fetch-order").fetch("head").fetch("details").first
replace_answer(
  order_detail,
  ordered.sub("git rev-list --left-right --count mybr...$remote_oid # 右侧 > 0 即停止 rebase\ngit rebase origin/main",
              "git rebase origin/main\ngit rev-list --left-right --count mybr...$remote_oid # 右侧 > 0 即停止 rebase")
)
order_result = regrade_payload(order_mutant)
order_misses = order_result.fetch("results").fetch("worktree-one-fetch-order").fetch("arms").fetch("head").fetch("details").first.fetch("missed")
abort "rebase-before-check mutant was not rejected" unless order_misses.include?("rebase-after-check")

state_mutant = Marshal.load(Marshal.dump(source))
state_detail = state_mutant.fetch("results").fetch("worktree-one-fetch-order").fetch("head").fetch("details").first
replace_answer(
  state_detail,
  ordered.sub("失效证据：thread / approval / mergeable / CI / commit hash / 行锚", "git commit --amend # explicit operation")
)
state_result = regrade_payload(state_mutant)
state_misses = state_result.fetch("results").fetch("worktree-one-fetch-order").fetch("arms").fetch("head").fetch("details").first.fetch("missed")
expected_state_misses = %w[review-state-approval review-state-mergeable review-state-CI review-state-commit review-state-thread review-state-line-anchor]
abort "unscoped state substrings were accepted: #{state_misses}" unless (expected_state_misses - state_misses).empty?

layout_variant = Marshal.load(Marshal.dump(source))
layout_detail = layout_variant.fetch("results").fetch("worktree-one-fetch-order").fetch("head").fetch("details").first
replace_answer(layout_detail, "重审旧状态后仍须执行下面的更新流程\n#{ordered}")
layout_result = regrade_payload(layout_variant)
layout_misses = layout_result.fetch("results").fetch("worktree-one-fetch-order").fetch("arms").fetch("head").fetch("details").first.fetch("missed")
abort "pre-push marker hid the valid post-push revalidation: #{layout_misses}" unless layout_misses.empty?

target_fetch_variant = Marshal.load(Marshal.dump(source))
target_detail = target_fetch_variant.fetch("results").fetch("worktree-one-fetch-order").fetch("head").fetch("details").first
replace_answer(target_detail, ordered.sub("git fetch origin\n", "git fetch -q origin main\n"))
target_result = regrade_payload(target_fetch_variant)
target_misses = target_result.fetch("results").fetch("worktree-one-fetch-order").fetch("arms").fetch("head").fetch("details").first.fetch("missed")
abort "safe target-fetch spelling was rejected: #{target_misses}" if target_misses.include?("target-refresh")

tighten_mutant = JSON.parse(File.read(CANONICAL_TIGHTEN_RAW))
tighten_detail = tighten_mutant.fetch("results").fetch("tighten-eight-class-walk").fetch("head").fetch("details").first
tighten_answer = tighten_detail.fetch("raw").gsub("工作语言", "临时措辞").gsub("p95=120ms", "measurement removed")
replace_answer(tighten_detail, tighten_answer)
tighten_result = regrade_payload(tighten_mutant)
tighten_misses = tighten_result.fetch("results").fetch("tighten-eight-class-walk").fetch("arms").fetch("head").fetch("details").first.fetch("missed")
expected_tighten_misses = %w[working-language measurement]
abort "tighten negative mutation escaped: #{tighten_misses}" unless (expected_tighten_misses - tighten_misses).empty?

if owner_dirty
  puts "c3_regrade_contract_tests_pending_dirty_owners"
  exit 2
else
  puts "c3_regrade_contract_tests_ok_unattested"
end
