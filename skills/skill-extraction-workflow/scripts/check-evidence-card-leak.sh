#!/usr/bin/env bash
set -euo pipefail

# Best-effort, high-signal PREFLIGHT for the obvious case of an evidence / L0 card being
# committed as markdown into the shared skill tree. Per the L0 storage rule
# (skill-extraction-workflow/references/l0-l1-l2-routing.md), evidence/L0 cards live in
# per-host scratch / a private alias and never under skills/**.
#
# THIS IS NOT THE GATE OF RECORD. It does not enforce the L0 storage / leakage rule —
# **R0 (the leakage audit, actually run and not skipped) is the L0-storage / leak gate of
# record**, together with the dual-track challenge. This script only catches obvious,
# accidental card-shaped markdown so it surfaces in changed files before review. An
# adversary who renames fields, splits a card across files, hides it in a non-markdown
# file, or shouts labels in all-caps can evade it; that is the accepted recall limit.
#
# SCAN SCOPE (default): only CHANGED markdown — the new/modified `skills/**/*.md` between an
# integration BASE and the current worktree, plus untracked / intent-to-add files. The base
# is `CCL_SKILL_BASE_REF` if set and valid, else `merge-base origin/main HEAD`, else
# `origin/main`; this covers branch COMMITS (not just worktree-vs-HEAD), so the check still
# bites post-commit / in CI. The root may be any subdirectory: the git TOPLEVEL is resolved
# first so toplevel-relative paths join correctly. When the root is a git repo with history
# but no base resolves, the scan is clean-but-DEGRADED: it reports the distinct status
# `evidence_card_leak_scan_degraded` (NOT a plain `scan_ok`) and scans worktree-vs-HEAD only.
# Degraded is WARNING-PASS (exit 0) by default so shallow / detached-HEAD / no-origin CI is not
# overblocked (this is a best-effort preflight and R0 is the gate of record; degraded-clean is
# NOT proof). Set `CCL_SKILL_BASE_REF` for full branch coverage, or opt IN to strict failure
# with `CCL_SKILL_EVIDENCE_CARD_STRICT_BASE=1` for CI that requires branch coverage. Unchanged
# historical docs are never re-policed because only changed files are scanned. (`--all <root>`
# does a best-effort full-tree pass for manual audits.) When the root is not a git work tree, the
# default falls back to a full-tree pass.
#
# Lines inside fenced code blocks (``` or ~~~) are stripped before matching, so a card quoted as
# a documentation EXAMPLE inside a fence does not false-trigger.
#
# A card HEADING is REQUIRED to flag. A markdown file is flagged only when it has a card
# HEADING (`#{1,6} Evidence Card | Captured Evidence | Lesson Card`, case-insensitive,
# optional trailing qualifier text) AND either:
#   (a) a concrete conclusion (Recommended path / Disposition / Tier = a whole-token tier); OR
#   (b) >= 2 CORE fields.
# Deliberately NO heading-less branch: a real card written WITHOUT a recognizable heading
# (e.g. just `Tier: L2` + `Trigger / context:`, or `Disposition: L1` + `Reusable pattern:`)
# is the ACCEPTED RECALL LIMIT — it passes here so scattered field labels in teaching / retro /
# definitional / risk docs never false-block. R0 (run, not skipped) + dual-track challenge are
# the comprehensive net for those.
#
# CORE fields: Trigger / context, Observed failure (or opportunity), First-hand evidence,
# Reusable pattern, Proposed skill effect (colon- or table-cell form, bullet/bold tolerant).
#
# A concrete CONCLUSION = a field `Recommended path` / `Disposition` / `Tier` whose VALUE,
# after stripping markdown bold / backticks / whitespace, BEGINS with a whole tier verdict
# token (`L0` / `L1` / `L2` / `upgrade-to-L1/L2` / `upgrade-to-L1` / `upgrade-to-L2`)
# terminated by end-of-value, whitespace, or a justification separator — so
# `Recommended path: L1 — routing risk` and `Tier: L2 (escalate)` count, while a glued
# continuation like `L2-cache` / `L2/foo` does NOT. The placeholder menu `L0 / L1 / L2` is
# not a conclusion. Bare `Path` is intentionally NOT a conclusion label (too broad).
#
# The blank template that DEFINES the card shape is exempt by EXACT anchored repo-relative
# path. No in-file opt-out marker is supported on purpose.
#
# POSIX `grep -E` / `sed -E` only — no ripgrep, and no GNU-only flags (no `sed` `I`).

# Exact, anchored, repo-relative allowlist of paths permitted to carry card shape (the blank
# template that DEFINES the shape). This array is the ONLY escape hatch and it is review-visible:
# any additional intentionally card-shaped teaching/reference doc must be added HERE in code,
# together with a self-test fixture and review / R0 evidence. There is deliberately NO in-file
# opt-out marker (a hidden bypass channel).
ALLOW_PATHS=(
  "skills/skill-extraction-workflow/references/evidence-card-template.md"
)
is_allowlisted() { # $1 repo-relative path
  local rel="$1" a
  for a in "${ALLOW_PATHS[@]}"; do
    if [ "$rel" = "$a" ]; then return 0; fi
  done
  return 1
}
HEADING_RE='^#{1,6}[[:space:]]*(Evidence Card|Captured Evidence|Lesson Card)([[:space:]].*)?$'
CONCLUSION_FEED_RE='(Recommended[[:space:]]+path|Disposition|Tier)'
# label match uses first-letter classes for case tolerance without GNU sed's `I` flag
CONCLUSION_LABEL_RE='^([Rr]ecommended[[:space:]]+[Pp]ath|[Dd]isposition|[Tt]ier)[[:space:]]*[:|][[:space:]]*'
PLACEHOLDER_RE='^L0 / L1 / L2$'
# A verdict is a leading whole token followed by end-of-value, whitespace, or a
# justification punctuation separator (`:`, `,`, `;`, `.`, `(`, `)`, em-dash). A glued
# alnum or `-`/`/` continuation (e.g. `L2-cache`, `L2/foo`) is NOT a verdict — only the
# explicit `upgrade-to-L1/L2` form carries an internal slash.
VERDICT_RE='^(upgrade-to-L1/L2|upgrade-to-L1|upgrade-to-L2|L0|L1|L2)([[:space:]:,;.()]|—|$)'

CORE_FIELD_RES=(
  'Trigger[[:space:]]*/[[:space:]]*context'
  'Observed failure([[:space:]]+or[[:space:]]+opportunity)?'
  'First-hand evidence'
  'Reusable pattern'
  'Proposed skill effect'
)

count_core_fields() {
  local f="$1" n=0 lbl
  for lbl in "${CORE_FIELD_RES[@]}"; do
    if grep -Eiq "^[[:space:]]*([-*|][[:space:]]*)?(\*\*)?${lbl}(\*\*)?[[:space:]]*[:|]" "$f"; then
      n=$((n + 1))
    fi
  done
  printf '%s' "$n"
}

# Echo "filled" (a whole-value tier verdict), "placeholder" (only the menu), or "none".
classify_conclusion() {
  local f="$1" line stripped val val_norm seen_placeholder=0
  while IFS= read -r line; do
    stripped="$(printf '%s' "$line" | sed -E 's/`//g; s/\*\*//g; s/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|[[:space:]]*$//')"
    val="$(printf '%s' "$stripped" | sed -E "s/${CONCLUSION_LABEL_RE}//")"
    if [ "$val" = "$stripped" ]; then continue; fi
    val_norm="$(printf '%s' "$val" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    if printf '%s' "$val_norm" | grep -Eq "$PLACEHOLDER_RE"; then seen_placeholder=1; continue; fi
    if printf '%s' "$val_norm" | grep -Eq "$VERDICT_RE"; then printf 'filled'; return 0; fi
  done < <(grep -Ei "$CONCLUSION_FEED_RE" "$f" || true)
  if [ "$seen_placeholder" -eq 1 ]; then printf 'placeholder'; else printf 'none'; fi
}

# Echo the path of a temp copy of $1 with fenced code blocks (``` or ~~~) removed, so a card
# quoted INSIDE a code fence (docs/examples) is not matched. Only matching fence families
# close a block. POSIX awk; macOS compatible. Caller must rm the returned temp file.
sanitized_file() {
  local f="$1" tmp
  tmp="$(mktemp)" || return 1
  awk '
    {
      if (infence) {
        if ($0 ~ ("^[[:space:]]*" fence)) { infence = 0 }
        next
      }
      if ($0 ~ /^[[:space:]]*```/)  { infence = 1; fence = "```"; next }
      if ($0 ~ /^[[:space:]]*~~~/)  { infence = 1; fence = "~~~"; next }
      print
    }
  ' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s' "$tmp"
}

file_is_card() {
  local f="$1" san h core concl k
  [ -f "$f" ] || return 1
  san="$(sanitized_file "$f")" || return 1   # match on a fence-stripped copy
  if grep -Eiq "$HEADING_RE" "$san"; then h=1; else h=0; fi
  core="$(count_core_fields "$san")"
  concl="$(classify_conclusion "$san")"
  rm -f "$san"
  if [ "$concl" = filled ]; then k=1; else k=0; fi
  # A card heading is REQUIRED. (a) heading + concrete conclusion, OR (b) heading + >=2 core.
  # No heading-less branch: heading-less cards are the accepted recall limit (see header).
  if [ "$h" -eq 1 ] && [ "$k" -eq 1 ]; then return 0; fi
  if [ "$h" -eq 1 ] && [ "$core" -ge 2 ]; then return 0; fi
  return 1
}

# Given a root and a NUL stream of repo-relative md paths on stdin, print offenders.
# Returns 0 clean, 1 offenders found.
scan_list() {
  local root="$1" rel hits="" seen=""
  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    case "$rel" in *.md) ;; *) continue ;; esac
    if is_allowlisted "$rel"; then continue; fi
    case "$seen" in *"|$rel|"*) continue ;; esac
    seen="$seen|$rel|"
    if file_is_card "$root/$rel"; then hits+="$rel"$'\n'; fi
  done
  if [ -n "${hits//[$'\n']/}" ]; then printf '%s\n' "$hits"; return 1; fi
  return 0
}

# Resolve an integration base ref to diff against; prints the ref/sha, or empty if none.
resolve_base_ref() {
  local root="$1" ref
  if [ -n "${CCL_SKILL_BASE_REF:-}" ]; then
    if git -C "$root" rev-parse --verify -q "${CCL_SKILL_BASE_REF}^{commit}" >/dev/null 2>&1; then
      printf '%s' "$CCL_SKILL_BASE_REF"; return 0
    fi
    echo "evidence_card_leak_base_ref_invalid: CCL_SKILL_BASE_REF='${CCL_SKILL_BASE_REF}' does not resolve to a commit; ignoring it" >&2
  fi
  if git -C "$root" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    if ref="$(git -C "$root" merge-base origin/main HEAD 2>/dev/null)" && [ -n "$ref" ]; then
      printf '%s' "$ref"; return 0
    fi
    printf '%s' "origin/main"; return 0
  fi
  return 0
}

# NUL stream of changed skills/**/*.md for the given base ($2): base..worktree (covers branch
# commits + uncommitted modifications) plus untracked / intent-to-add. With an empty base it
# degrades to worktree-vs-HEAD, and to all-tracked when there is no HEAD. (The caller decides
# whether an empty base is an inconclusive result — see scan_changed.)
collect_changed_md() {
  local root="$1" base="${2:-}"
  if [ -n "$base" ]; then
    git -C "$root" diff -z --name-only --diff-filter=d "$base" -- skills 2>/dev/null || true
  elif git -C "$root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    git -C "$root" diff -z --name-only --diff-filter=d HEAD -- skills 2>/dev/null || true
  else
    git -C "$root" ls-files -z -- skills 2>/dev/null || true
  fi
  git -C "$root" ls-files -z --others --exclude-standard -- skills 2>/dev/null || true
}

# NUL stream of every skills/**/*.md under root (best-effort full-tree fallback / --all).
collect_all_md() {
  local root="$1"
  [ -d "$root/skills" ] || return 0
  ( cd "$root" && find skills -type f -name '*.md' -print0 2>/dev/null ) || true
}

# Changed-scope scan against an already-resolved git TOPLEVEL.
# Returns: 0 clean (full base..worktree coverage), 1 offender found, 3 clean-but-DEGRADED
# (no integration base resolved, so only worktree-vs-HEAD was scanned — branch commits NOT
# covered). Degraded is surfaced distinctly (not a plain ok) but is NOT a hard fail by default
# (best-effort preflight; R0 is the gate of record). An offender (1) always takes precedence.
scan_changed() {
  local top="$1" base degraded=0 rc=0
  base="$(resolve_base_ref "$top")"
  if [ -z "$base" ] && git -C "$top" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    degraded=1
  fi
  scan_list "$top" < <(collect_changed_md "$top" "$base") || rc=$?
  if [ "$rc" -ne 0 ]; then return "$rc"; fi
  if [ "$degraded" -eq 1 ]; then return 3; fi
  return 0
}
scan_all() { scan_list "$1" < <(collect_all_md "$1"); }

# Default entry: resolve the git TOPLEVEL from any root (incl. a subdir) so git-emitted
# toplevel-relative paths join correctly; non-git roots fall back to a best-effort full scan.
scan_default() {
  local root="$1" top
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    scan_changed "$top"
  else
    scan_all "$root"
  fi
}

report() {
  case "$1" in
    0) echo "evidence_card_leak_scan_ok" ;;
    3)
      # Clean, but coverage degraded (no integration base). Distinct status, NOT a plain ok.
      # WARNING-PASS by default (this is a best-effort preflight and R0 is the gate of record, so
      # it must not overblock shallow / detached-HEAD / no-origin CI). Opt-in strict mode makes it
      # a hard failure for CI configs that require full branch coverage.
      echo "evidence_card_leak_scan_degraded: base unavailable (no CCL_SKILL_BASE_REF / origin/main / merge-base); scanned worktree-vs-HEAD only — branch commits NOT covered. Best-effort preflight; degraded-clean is NOT proof, R0 is the gate of record. Set CCL_SKILL_BASE_REF for full coverage." >&2
      if [ -n "${CCL_SKILL_EVIDENCE_CARD_STRICT_BASE:-}" ]; then
        echo "evidence_card_leak_degraded_blocking: CCL_SKILL_EVIDENCE_CARD_STRICT_BASE=1 -> treating degraded coverage as a failure" >&2
        exit 1
      fi
      # default: warning-pass (exit 0)
      ;;
    *)
      echo "evidence_card_leak_scan_failed: a card-shaped markdown file (Evidence Card / Captured Evidence / Lesson Card heading paired with a whole-value tier conclusion or >=2 core fields) is present under skills/**. Evidence/L0 cards live in per-host scratch / a private alias, never the shared tree — move it out (see skill-extraction-workflow/references/l0-l1-l2-routing.md L0 storage rule). This is a best-effort changed-markdown preflight, NOT the gate of record; R0 is the comprehensive L0-storage / leakage gate." >&2
      exit 1
      ;;
  esac
}

self_test() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  mkdir -p \
    "$tmp/skills/demo/references/sub/deep" \
    "$tmp/skills/demo/notes" \
    "$tmp/skills/skill-extraction-workflow/references"

  # ---- baseline that must always PASS (full-tree fixture scan) ----
  printf '## Evidence Card\n- Trigger / context: x\n- First-hand evidence: y\n- Recommended path: L2\n' \
    > "$tmp/skills/skill-extraction-workflow/references/evidence-card-template.md"           # allowlisted
  printf '# notes\njust prose, no card here\n' > "$tmp/skills/demo/references/clean.md"
  printf '# walkthrough\n- **Tier** — points toward L2.\n' > "$tmp/skills/demo/references/prose.md"
  printf '## Evidence Card\n- Recommended path: L0 / L1 / L2\n' \
    > "$tmp/skills/demo/references/blank-copy.md"                                             # heading + menu only
  printf '## Evidence Card\n\nExplanatory prose about what an evidence card is.\n' \
    > "$tmp/skills/demo/references/heading-only.md"
  printf '# risk register\n- Risk: high\n- Tier: L2\n' \
    > "$tmp/skills/demo/references/risk-tier.md"                                              # conclusion + only non-core
  printf '# fields explained\n- First-hand evidence: needed first\n- Reusable pattern: the generalization\n' \
    > "$tmp/skills/demo/references/definitional.md"                                           # two core names only
  printf '# fields\n- Trigger / context: what surfaced it\n- Scope: the boundary\n- Risk: axes\n' \
    > "$tmp/skills/demo/references/teaching-fields.md"                                        # core + non-core, no heading/concl
  printf '# cache notes\n- Trigger / context: x\n- Tier: L2-cache/foo\n' \
    > "$tmp/skills/demo/references/tier-cache.md"                                             # L2-cache is NOT a verdict
  printf '# cache map\n- Trigger / context: x\n- Path: L2-cache/foo\n' \
    > "$tmp/skills/demo/references/path-cache.md"                                             # bare Path is not a label
  printf '## Captured Evidence\n- Reusable pattern: the generalization\n' \
    > "$tmp/skills/demo/references/retro-doc.md"                                              # heading + SINGLE core, no conclusion
  printf '# retro notes\n- Reusable pattern: y\n- Disposition: L1\n' \
    > "$tmp/skills/demo/references/disp-noheading.md"                                         # conclusion+core but NO heading -> residual PASS
  printf '# retro notes\n- Trigger / context: x\n- Tier: L2\n' \
    > "$tmp/skills/demo/references/tier-noheading.md"                                         # conclusion+core but NO heading -> residual PASS
  printf '## Evidence Card\n- Trigger / context: x\n- Tier: L2-cache/foo\n' \
    > "$tmp/skills/demo/references/tier-cache-heading.md"                                     # heading present but L2-cache is NOT a verdict, only 1 core
  printf '%b' '# how-to guide\nQuote the template inside a fence:\n```\n## Evidence Card\n- Trigger / context: x\n- First-hand evidence: y\n- Recommended path: L2\n```\nEnd of example.\n' \
    > "$tmp/skills/demo/references/fenced-example.md"                                          # full card shape only INSIDE a ``` fence -> PASS
  printf '%b' '# tilde fence example\n~~~\n## Lesson Card\n- Recommended path: L1\n~~~\n' \
    > "$tmp/skills/demo/references/fenced-tilde.md"                                            # card shape only INSIDE a ~~~ fence -> PASS
  if ! scan_all "$tmp" >/dev/null; then
    echo "self-test FAIL: baseline tripped the gate" >&2; rc=1
  fi

  # ---- offenders that must each BLOCK (create, assert, remove) ----
  block_case() { # $1 label, $2 rel path under $tmp, $3 body (printf %b)
    printf '%b' "$3" > "$tmp/$2"
    if scan_all "$tmp" >/dev/null; then
      echo "self-test FAIL: $1 not detected" >&2; rc=1
    fi
    rm -f "$tmp/$2"
  }

  block_case "shallow classic card" "skills/demo/references/leak.md" \
    '## Evidence Card\n- Recommended path: L2\n'
  block_case "deep-nested card" "skills/demo/references/sub/deep/leak.md" \
    '## Evidence Card\n- Recommended path: L1\n'
  block_case "nested non-references card" "skills/demo/notes/leak.md" \
    '## Evidence Card\n- Recommended path: upgrade-to-L1/L2\n'
  block_case "spaced-filename card" "skills/demo/references/a card.md" \
    '## Evidence Card\n- Recommended path: L2\n'
  block_case "lowercase heading card" "skills/demo/references/lower.md" \
    '## evidence card\n- Recommended path: L1\n'
  block_case "plain-line conclusion card" "skills/demo/references/plain.md" \
    '# Evidence Card\nRecommended path: L2\n'
  block_case "table-row conclusion card" "skills/demo/references/table.md" \
    '## Evidence Card\n| Recommended path | L2 |\n'
  block_case "qualified heading (em-dash suffix) + conclusion" "skills/demo/references/q1.md" \
    '## Evidence Card — routing miss\n- Trigger / context: x\n- Recommended path: L2\n'
  block_case "qualified heading (parenthetical suffix) + 2 core fields" "skills/demo/references/q2.md" \
    '### Captured Evidence (process retro)\n- First-hand evidence: y\n- Reusable pattern: z\n'
  block_case "Captured Evidence heading + two core fields" "skills/demo/references/cap.md" \
    '## Captured Evidence\n- Trigger / context: x\n- First-hand evidence: y\n'
  block_case "unfenced card (same content as the fenced example)" "skills/demo/references/unfenced.md" \
    '# how-to guide\n## Evidence Card\n- Trigger / context: x\n- First-hand evidence: y\n- Recommended path: L2\nEnd of example.\n'
  block_case "heading + verdict with em-dash justification" "skills/demo/references/just.md" \
    '## Evidence Card\n- Recommended path: L1 — routing risk\n'
  block_case "heading + verdict with parenthetical justification" "skills/demo/references/just2.md" \
    '## Lesson Card\n- Tier: L2 (escalate, routing surface)\n'
  block_case "heading + upgrade-to verdict" "skills/demo/references/upg.md" \
    '## Captured Evidence\n- Disposition: upgrade-to-L1/L2\n'

  # ---- allowlist exemption: a fully filled card AT the allow path must PASS ----
  printf '## Evidence Card\n- Trigger / context: x\n- First-hand evidence: y\n- Recommended path: L2\n' \
    > "$tmp/skills/skill-extraction-workflow/references/evidence-card-template.md"
  if ! scan_all "$tmp" >/dev/null; then
    echo "self-test FAIL: allowlisted path not exempted" >&2; rc=1
  fi

  # ---- report() status mapping (no git needed): degraded is distinct + WARNING-PASS by default
  if ! printf '%s' "$(report 0)" | grep -q 'evidence_card_leak_scan_ok'; then
    echo "self-test FAIL: report(0) should print scan_ok" >&2; rc=1
  fi
  if ! printf '%s' "$(report 3 2>&1 || true)" | grep -q 'evidence_card_leak_scan_degraded'; then
    echo "self-test FAIL: report(3) should print scan_degraded (distinct, not ok)" >&2; rc=1
  fi
  if ! ( report 3 >/dev/null 2>&1 ); then
    echo "self-test FAIL: degraded(3) must be WARNING-PASS (exit 0) by default" >&2; rc=1
  fi
  if ( CCL_SKILL_EVIDENCE_CARD_STRICT_BASE=1 report 3 >/dev/null 2>&1 ); then
    echo "self-test FAIL: CCL_SKILL_EVIDENCE_CARD_STRICT_BASE=1 must make degraded(3) BLOCK" >&2; rc=1
  fi

  # ---- changed-scope tests (git-dependent): gated behind a capability probe so missing infra
  #      (no git / mktemp / temp-dir / commit capability) SKIPS them with an explicit warning
  #      instead of blocking the whole gate. The pure shape tests above always run, and any
  #      assertion failure below still sets rc=1 (only infra-unavailability skips, never asserts).
  fgit() { # $1 repo dir, rest git args — isolated from global signing/hooks/system+global config
    local r="$1"; shift
    HOME="$r" GIT_CONFIG_NOSYSTEM=1 git -C "$r" \
      -c user.email=test@example.invalid -c user.name=test \
      -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath="$r/_emptyhooks" "$@"
  }
  git_fixture_capable() { # 0 if a temp repo + commit can be created, else 1
    command -v git >/dev/null 2>&1 || return 1
    command -v mktemp >/dev/null 2>&1 || return 1
    local p; p="$(mktemp -d 2>/dev/null)" || return 1
    [ -n "$p" ] || return 1
    mkdir -p "$p/_emptyhooks"
    local ok=1
    if fgit "$p" init -q >/dev/null 2>&1 \
       && printf 'x\n' > "$p/probe.txt" \
       && fgit "$p" add -A >/dev/null 2>&1 \
       && fgit "$p" commit -q --no-verify -m probe >/dev/null 2>&1; then
      ok=0
    fi
    rm -rf "$p"
    return "$ok"
  }

  if ! git_fixture_capable; then
    # Best-effort preflight: missing fixture infra (git / mktemp / temp commit) SKIPS the
    # git-dependent changed-scope tests with an explicit warning by default, so unrelated authors
    # on minimal images are not blocked. Opt-in strict mode turns the skip into a failure.
    if [ -n "${CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST:-}" ]; then
      echo "evidence_card_leak_self_test_failed: git fixture capability unavailable (git / mktemp / temp-dir / commit) so changed-scope tests could not run; CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 -> failing." >&2
      rc=1
    else
      echo "evidence_card_leak_self_test_skipped: git fixture capability unavailable (git / mktemp / temp-dir / commit) -> skipping changed-scope tests (non-fatal; pure shape tests still ran). Set CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 to fail instead." >&2
    fi
  else
    local gr out base_sha ic
    gr="$(mktemp -d)"
    mkdir -p "$gr/skills/h/references" "$gr/_emptyhooks"
    fgit "$gr" init -q
    printf '## Evidence Card\n- Recommended path: L1\n' > "$gr/skills/h/references/historical.md"  # committed at base
    fgit "$gr" add -A >/dev/null 2>&1
    fgit "$gr" commit -q --no-verify -m base >/dev/null 2>&1
    base_sha="$(fgit "$gr" rev-parse HEAD)"

    # (i) untracked NEW offender caught vs HEAD; committed unchanged historical NOT scanned
    printf '## Evidence Card\n- Recommended path: L2\n' > "$gr/skills/h/references/new-leak.md"
    out="$(scan_default "$gr" 2>/dev/null || true)"
    if ! printf '%s' "$out" | grep -q 'new-leak.md'; then
      echo "self-test FAIL: changed-scope missed a new offending markdown" >&2; rc=1
    fi
    if printf '%s' "$out" | grep -q 'historical.md'; then
      echo "self-test FAIL: changed-scope wrongly scanned an unchanged historical offender" >&2; rc=1
    fi

    # (ii) modifying the historical file brings it INTO worktree-vs-HEAD scope -> caught
    printf '\n- Trigger / context: y\n' >> "$gr/skills/h/references/historical.md"
    out="$(scan_default "$gr" 2>/dev/null || true)"
    if ! printf '%s' "$out" | grep -q 'historical.md'; then
      echo "self-test FAIL: changed-scope missed a now-modified historical card" >&2; rc=1
    fi

    # (iii) a BRANCH-COMMITTED offender relative to the integration base must be caught via
    #       CCL_SKILL_BASE_REF — proves coverage is not just untracked-vs-HEAD (post-commit/CI).
    fgit "$gr" checkout -q -- skills/h/references/historical.md   # isolate: drop the uncommitted mod
    rm -f "$gr/skills/h/references/new-leak.md"
    printf '## Evidence Card\n- Recommended path: L2\n' > "$gr/skills/h/references/branch-leak.md"
    fgit "$gr" add -A >/dev/null 2>&1
    fgit "$gr" commit -q --no-verify -m branch-leak >/dev/null 2>&1
    out="$(CCL_SKILL_BASE_REF="$base_sha" scan_default "$gr" 2>/dev/null || true)"
    if ! printf '%s' "$out" | grep -q 'branch-leak.md'; then
      echo "self-test FAIL: base-ref changed-scope missed a branch-committed offender" >&2; rc=1
    fi

    # (iv) scanning from a SUBDIR root resolves the git toplevel and still catches the offender
    #      (path-join must use the toplevel, not the subdir root).
    printf '## Evidence Card\n- Recommended path: L2\n' > "$gr/skills/h/references/subdir-leak.md"
    out="$(scan_default "$gr/skills/h" 2>/dev/null || true)"
    if ! printf '%s' "$out" | grep -q 'subdir-leak.md'; then
      echo "self-test FAIL: subdir-root scan missed the offender (toplevel/path-join bug)" >&2; rc=1
    fi
    rm -f "$gr/skills/h/references/subdir-leak.md"

    # (v) git repo with history but NO base resolvable + clean worktree -> DEGRADED (code 3):
    #     a distinct status (report prints evidence_card_leak_scan_degraded), NOT a plain
    #     scan_ok and NOT a hard fail. (Fixture has no origin/main; CCL_SKILL_BASE_REF unset.)
    ic=0; scan_default "$gr" >/dev/null 2>&1 || ic=$?
    if [ "$ic" -ne 3 ]; then
      echo "self-test FAIL: no-base clean changed-scope should be degraded(3), got $ic" >&2; rc=1
    fi
    rm -rf "$gr"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "evidence_card_leak_self_test_ok"
  else
    echo "evidence_card_leak_self_test_failed" >&2
  fi
  return "$rc"
}

main() {
  case "${1:-}" in
    --self-test)
      self_test
      ;;
    --all)
      shift
      local root="${1:-.}" rc=0
      scan_all "$root" || rc=$?
      report "$rc"
      ;;
    *)
      local root="${1:-.}" rc=0
      scan_default "$root" || rc=$?
      report "$rc"
      ;;
  esac
}

main "$@"
