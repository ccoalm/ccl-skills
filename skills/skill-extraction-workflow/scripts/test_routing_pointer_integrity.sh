#!/usr/bin/env bash
# Contract test: the routing pointers and doc-vs-executor consistency landed by
# the deep-review-fix round must stay in place. Each grep targets the landed
# RULE TEXT (not a bare skill name), so deleting the rule while leaving the
# name elsewhere in the file still turns the lane red — these are the RED
# oracles cited by the corresponding source-register impact-chain rows (the
# Python arch/dev boundary's RED oracle is the eval bank fixture
# miss-refactor-python-unqualified, replayed in the same round, not this suite —
# and that replay is a one-time MANUAL advisory run: the bank grader needs a live
# `claude` CLI, so no registered lane re-runs it. This suite pins TEXT, never
# routing behaviour; see test_routing_bank_integrity.sh for the structural half.)
# Accepted-maintenance note: this is a literal-phrase anchor check over text the
# repo owns (same class as the anchor gates inside check-ccl-skills.sh);
# when one of these rules is intentionally reworded, update the token in the
# same diff.
set -u
# POINTER_ROOT overrides the tree under test (used by the RED-baseline proof
# and fixture tests); default is the repo this script is installed in.
ROOT="${POINTER_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
# A redirected lane must be loud: env-injected POINTER_ROOT (CI/dev shell) makes
# the suite test a different tree than the caller expects.
[ -n "${POINTER_ROOT:-}" ] && echo "NOTICE: POINTER_ROOT set — testing tree: $ROOT" >&2
fail=0
check() { # <file> <token> <label>
  if ! grep -qF "$2" "$1"; then
    echo "FAIL: $3 missing ($1 :: $2)" >&2
    fail=1
  fi
}
check_frontmatter_present() { # <file> <token> <label> — token present in the
  # YAML frontmatter block.
  if [ ! -f "$1" ]; then
    echo "FAIL: $3 target file missing ($1)" >&2
    fail=1
    return
  fi
  awk '/^---$/{c++; next} c==1' "$1" | grep -qF "$2"     || { echo "FAIL: $3 missing from frontmatter ($1 :: $2)" >&2; fail=1; }
}

check_frontmatter_absent() { # <file> <token> <label> — token absent from the
  # YAML frontmatter block (body may legitimately discuss the same words).
  if [ ! -f "$1" ]; then
    echo "FAIL: $3 target file missing ($1)" >&2
    fail=1
    return
  fi
  if awk '/^---$/{c++; next} c==1' "$1" | grep -qF "$2"; then
    echo "FAIL: $3 present in frontmatter ($1 :: $2)" >&2
    fail=1
  fi
}

check_threshold_consistency() { # <root> <label> — the description-length numbers
  # the authoring doc STATES must equal the ones check-ccl-skills.sh
  # ENFORCES. This replaces four literal-value anchors (doc says "800", doc must
  # not say "1024", script says 800, script says 600) with the property those
  # anchors were standing in for. It is strictly stronger AND cheaper to keep:
  #   - stronger: any doc/executor disagreement fails, including numbers nobody
  #     hardcoded here, so a NEW stale value cannot slip in the way "1024" did;
  #   - cheaper: an intentional threshold change (e.g. 800 -> 700 on both sides
  #     in one diff) now passes instead of red-lining a correct change and
  #     forcing an unrelated edit to this file.
  local root="$1" label="$2"
  local doc="$root/skills/skill-extraction-workflow/references/description-authoring.md"
  local exe="$root/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
  for f in "$doc" "$exe"; do
    if [ ! -f "$f" ]; then
      echo "FAIL: $label target file missing ($f)" >&2; fail=1; return
    fi
  done
  local doc_hdr doc_max doc_warn exe_max exe_warn
  # Each number is parsed via ITS OWN marker. A bare `above [0-9]+` is wrong:
  # the doc states both thresholds in one sentence ("... above 800 chars and
  # warns ... above 600"), so a first-match parse silently reads the block
  # number as the warn number. (`description_long_for_opencode` cannot match
  # inside `description_too_long_for_opencode` — that one reads "too_long".)
  # `.` stands in for the doc's backtick to avoid shell command substitution.
  doc_hdr=$(grep -oE '[0-9]+-character maximum' "$doc" | grep -oE '[0-9]+' | head -1)
  doc_max=$(grep -oE 'description_too_long_for_opencode. above [0-9]+' "$doc" | grep -oE '[0-9]+$' | head -1)
  doc_warn=$(grep -oE 'description_long_for_opencode. above [0-9]+' "$doc" | grep -oE '[0-9]+$' | head -1)
  # Each executor threshold is read from the LINE carrying its own diagnostic
  # name, not inferred as the max/min of every `desc.length >` in the file.
  # Inferring by extreme is wrong in both directions: an unrelated comparison
  # with a bigger/smaller bound false-reds a valid change, and an unrelated
  # occurrence of the old value masks real drift in the one that matters.
  # (`description_long_for_opencode` cannot match the block line, which reads
  # `description_too_long_for_opencode`.)
  # Collect EVERY threshold carrying each diagnostic name and require exactly one
  # distinct value. `head -1` was wrong: a dead/older line for the same diagnostic
  # sitting above the active one would be picked, so changing the ACTIVE threshold
  # left this equal to the doc and false-greened real drift.
  local exe_max_all exe_warn_all exe_max_n exe_warn_n
  exe_max_all=$(grep 'description_too_long_for_opencode' "$exe" | grep -oE 'desc\.length > [0-9]+' | grep -oE '[0-9]+' | sort -u)
  exe_warn_all=$(grep 'description_long_for_opencode' "$exe" | grep -oE 'desc\.length > [0-9]+' | grep -oE '[0-9]+' | sort -u)
  exe_max_n=$(printf '%s\n' "$exe_max_all" | grep -c '[0-9]')
  exe_warn_n=$(printf '%s\n' "$exe_warn_all" | grep -c '[0-9]')
  if [ "$exe_max_n" -gt 1 ] || [ "$exe_warn_n" -gt 1 ]; then
    echo "FAIL: $label executor declares conflicting thresholds for one diagnostic (max: $(echo $exe_max_all), warn: $(echo $exe_warn_all)) — a stale duplicate line would mask real drift" >&2
    fail=1; return
  fi
  exe_max="$exe_max_all"
  exe_warn="$exe_warn_all"
  # An unparsed side must fail: an empty capture comparing equal to another
  # empty capture is the silent-pass this whole check exists to prevent.
  if [ -z "$doc_hdr" ] || [ -z "$doc_max" ] || [ -z "$doc_warn" ] || [ -z "$exe_max" ] || [ -z "$exe_warn" ]; then
    echo "FAIL: $label could not parse thresholds (doc_hdr='$doc_hdr' doc_max='$doc_max' doc_warn='$doc_warn' exe_max='$exe_max' exe_warn='$exe_warn')" >&2
    fail=1; return
  fi
  # The doc's own section heading must agree with its body sentence, or a reader
  # who stops at the heading gets the stale number — the exact shape of the
  # 1024-vs-800 drift this replaced.
  if [ "$doc_hdr" != "$doc_max" ]; then
    echo "FAIL: $label doc heading says $doc_hdr but its body says $doc_max" >&2; fail=1
  fi
  if [ "$doc_max" != "$exe_max" ]; then
    echo "FAIL: $label doc states max=$doc_max but executor enforces max=$exe_max" >&2; fail=1
  fi
  if [ "$doc_warn" != "$exe_warn" ]; then
    echo "FAIL: $label doc states warn=$doc_warn but executor warns at $exe_warn" >&2; fail=1
  fi
}

check_absent() { # <file> <token> <label> — file must exist AND token absent;
  # a missing/renamed target is a failure, never a pass.
  if [ ! -f "$1" ]; then
    echo "FAIL: $3 target file missing ($1)" >&2
    fail=1
    return
  fi
  if grep -qF "$2" "$1"; then
    echo "FAIL: $3 must not be present ($1 :: $2)" >&2
    fail=1
  fi
}

# Self-pin: an emptied or truncated suite must fail, not pass. Update EXPECTED
# when adding/removing checks deliberately (same diff). Runs FIRST: a truncated
# tail removes real checks and the count goes red.
EXPECTED_CHECKS=19
actual_checks=$(grep -cE '^check([_a-z]+)? ' "$0")
if [ "$actual_checks" -ne "$EXPECTED_CHECKS" ]; then
  echo "FAIL: suite self-pin: expected $EXPECTED_CHECKS checks, found $actual_checks" >&2
  exit 1
fi

# Rollout routing pointers: the landed bullets, not the skill names alone.
check "$ROOT/skills/platform-release-engineering/SKILL.md" "must not own that coordination lifecycle" "rollout -> release-coordination boundary rule"
check "$ROOT/skills/platform-release-engineering/SKILL.md" "release document's substance and evidence discipline" "rollout -> release-doc-writer routing pointer"
# product-rd callback rule: the landed rule opening, not the skill name alone.
check "$ROOT/skills/product-rd-workflow/SKILL.md" "For research groundwork behind a selection or assessment decision" "product-rd -> multi-perspective-research callback rule"
# Doc-vs-executor consistency: the doc claims 800/600 and the executor enforces
# exactly those numbers — pin BOTH sides so a threshold change on either side
# turns the lane red instead of re-opening the doc-vs-script drift.
check_threshold_consistency "$ROOT" "doc-vs-executor description thresholds"
check "$ROOT/skills/skill-extraction-workflow/SKILL.md" "within the 800-char cap" "skill-extraction utterance-variant 800-cap rule (firing-path of the register row)"

# Routing-surface landings from the same round (description edits): pin the key
# trigger/skip tokens so a revert of any of them turns the lane red. Behavior
# oracle for these is the eval bank replay; these anchors are the cheap always-on guard.
check_frontmatter_present "$ROOT/skills/python-service-dev/SKILL.md" "重构 Python 服务里的某文件/某类(局部)" "python-service-dev localized-refactor trigger"
check_frontmatter_present "$ROOT/skills/python-service-dev/SKILL.md" "用 Python 写个命令行工具" "python-service-dev CLI trigger"
# description-scoped: the bare trigger must be gone from the frontmatter
# description line (body may legitimately discuss the boundary).
check_frontmatter_absent "$ROOT/skills/python-service-dev/SKILL.md" "Python 服务重构" "python-service-dev unqualified refactor trigger"
check_frontmatter_present "$ROOT/skills/python-service-architecture/SKILL.md" "Python 服务重构" "python-service-architecture unqualified refactor trigger"
check_frontmatter_present "$ROOT/skills/miniapp-product-dev/SKILL.md" "重构这个小程序页面/组件(局部)" "miniapp localized-refactor trigger"
check_frontmatter_present "$ROOT/skills/terminal-cli-dev/SKILL.md" "用 Python 写个命令行工具\" → python-service-dev" "terminal-cli-dev language-stack CLI skip"
# Both legs of that skip clause must be reciprocated by the named stack owner,
# or the pointer sends the request to a skill that never advertises the work.
check_frontmatter_present "$ROOT/skills/go-microservice-dev/SKILL.md" "用 Go 写个命令行工具" "go-microservice-dev CLI trigger (reciprocal of terminal-cli-dev skip)"
# The coordinator surface must carry the same carve-out, or product-rd keeps
# advertising terminal-cli-dev for language-stack CLI implementation.
check "$ROOT/skills/product-rd-workflow/SKILL.md" "must go to that language's dev skill when one owns it" "product-rd coordinator CLI carve-out (owner branch)"
# Both branches are pinned separately: anchoring only the owner branch lets the
# no-owner fallback be deleted while the suite stays green, which is exactly the
# routing hole (a CLI in a language with no dev owner) this rule closes.
check "$ROOT/skills/product-rd-workflow/SKILL.md" "no such dev owner stays with \`terminal-cli-dev\` as the default CLI owner" "product-rd coordinator CLI carve-out (no-owner fallback branch, incl. destination)"
# Both legs of the skip clause are pinned: an unanchored leg can be deleted while
# the reciprocal trigger anchor above stays green, and the eval fixtures assert
# terminal-cli-dev must NOT receive either request.
check_frontmatter_present "$ROOT/skills/terminal-cli-dev/SKILL.md" "Go CLI → go-microservice-dev" "terminal-cli-dev Go skip leg"
# CLI interface design ownership: both surfaces must say terminal-cli-dev owns the
# command/flag/help contract even with nothing rendered, or non-rendered CLI design
# goes back to having no owner (terminal skipped it, the stack skills scope to
# implementation) — the gap two independent reviewer lanes hit.
check_frontmatter_present "$ROOT/skills/terminal-cli-dev/SKILL.md" "command/subcommand/flag/help contract (owned here even when nothing is rendered)" "terminal-cli-dev owns the non-rendered CLI contract"
check "$ROOT/skills/product-rd-workflow/SKILL.md" "command/subcommand/flag/help contract, which it owns even when nothing is rendered" "product-rd mirrors CLI-contract ownership"
check_frontmatter_present "$ROOT/skills/platform-release-engineering/SKILL.md" "上线范围确认 / 合并 main / 打 tag" "rollout description prod-release skip"
check "$ROOT/skills/app-cross-platform-dev/agents/openai.yaml" "React Native" "app-cross-platform-dev openai overlay RN parity"

if [ "$fail" -eq 0 ]; then
  echo "routing_pointer_integrity_ok"
fi
exit "$fail"
