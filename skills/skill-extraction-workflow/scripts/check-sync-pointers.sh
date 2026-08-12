#!/usr/bin/env bash
# Semantic sync pointer gate (blocking since 2026-08-02, C-1 family).
#
# The always-on layer (agent-context/session-start.md) points into canonical sections by section
# name / capability name and carries COMPRESSED resident reflections declared
# to be subsets of their canonical predicate sets. The syntactic tier (route
# existence, <pkg>/references/*.md existence) is owned by the two checks in
# check-ccl-skills.sh; this gate owns the semantic tier — but only its
# mechanically decidable part: a DECLARED registry of pinned pairs and subset
# relations, never open-ended pointer discovery (diverse pointer prose forms
# would false-positive, which is why the syntactic tier left this out).
#
# Two registries:
#   1. Pinned pairs (declared below): (source literal in agent-context/session-start.md) AND
#      (target literal in the canonical file/dir). Drift on EITHER side —
#      reworded pointer, renamed/removed canonical section — blocks.
#   2. The security-four-questions subset registry (declared in the canonical
#      file itself as an HTML comment `sync-registry:v1` holding the CANONICAL
#      predicate/trigger sets plus declared aliases). The bootstrap side is
#      EXTRACTED from the live text through anchored phrases (触及 … 时 /
#      若某值被…爆炸半径 / 写一条…负向用例), never trusted from a declared
#      value: an extracted set that escapes the canonical set blocks, and an
#      extraction that no longer matches its anchor blocks too (reword the
#      resident reflection and these anchors together). On the canonical side
#      each registered token must appear inside its ANCHORED REGION (the 触发
#      section, the numbered 问题本体 item line), not anywhere in the prose —
#      narrative text cannot satisfy the check.
#
# agent-context/session-start.md missing is a legal repo state (the route check's
# skipped-missing and the size gate's advisory-partial treat it the same):
# pairs and bootstrap-side subset assertions are skipped with a marker, while
# the canonical-side registry/prose checks still run. A wholesale-missing
# PACKAGE (partial checkout) skips its pairs the same way; a package that is
# PRESENT but lost its target file is a broken registered invariant and
# BLOCKS; a present-but-unreadable file is infra (rc 2). The ok token is only
# printed when everything was evaluated and clean (any skip suppresses it).
#
# What this gate deliberately does NOT decide: full semantic equivalence of
# paraphrased prose (grep-class criteria cannot prove semantic governance —
# that stays with the adversarial-review lane).
#
# Exit codes: 0 = clean (or a marked skip), 1 = a registry violation
# (blocks the gate), 2 = infra (fail-closed).
#
# The subset tier runs in an embedded ruby; a DECLARED violation there exits 3,
# never 1. Ruby exits 1 on any uncaught exception too (a crashed interpreter, a
# non-UTF-8 locale, a missing binary), and rc 1 is what the caller folds into
# the deferred "reword both sides of a registered pair" verdict — so an
# interpreter that never evaluated a single rule would be reported as a policy
# violation. Reserving 3 for declared violations keeps every unexpected rc on
# the infra path, which is fail-closed AND correctly diagnosed.
set -uo pipefail

root="${1:-.}"

bootstrap="$root/agent-context/session-start.md"
wt="$root/skills/worktree-isolation/SKILL.md"
prd="$root/skills/product-rd-workflow/SKILL.md"
se="$root/skills/skill-extraction-workflow/SKILL.md"
sec4="$root/skills/requirement-doc-writer/references/security-four-questions.md"
llm_dir="$root/skills/llm-inference-integration"
td="$root/skills/tighten-doc/SKILL.md"
dtref="$root/skills/skill-extraction-workflow/references/dual-track-review-gate.md"

# Per-target availability: a wholesale-missing PACKAGE is a legal partial
# checkout (same family shape as the route check's File.file? guards and the
# size gate's missing-skills partial) — its pairs skip with a marker. A
# package PRESENT but missing the target file is a broken registered
# invariant and blocks. Present-but-unreadable is infra (rc 2).
target_state() { # <file> <package-dir> -> 1 evaluate / 0 skip / 2 block / 3 infra
  if [ ! -d "$2" ]; then
    echo 0
  elif [ ! -e "$1" ]; then
    echo 2
  elif [ ! -r "$1" ]; then
    echo 3
  else
    echo 1
  fi
}

if [ -e "$bootstrap" ] && [ ! -r "$bootstrap" ]; then
  echo "sync_pointer_infra: agent-context/session-start.md exists but is unreadable" >&2
  exit 2
fi

fail=0
block() { echo "sync_pointer_block: $1" >&2; fail=1; }

if [ -e "$bootstrap" ]; then
  bootstrap_present=1
else
  bootstrap_present=0
  any_pinned=0
  for pkg in worktree-isolation product-rd-workflow skill-extraction-workflow llm-inference-integration tighten-doc requirement-doc-writer; do
    [ -d "$root/skills/$pkg" ] && { any_pinned=1; break; }
  done
  if [ "$any_pinned" -eq 1 ]; then
    # agent-context/session-start.md gone while ANY pinned package remains: the always-on layer
    # was deleted (possibly together with some packages) while its sync
    # registry lives — that omission bypasses every pin, so it blocks. The
    # marked skip exists only for a tree with NO pinned package at all.
    block "agent-context/session-start.md missing while pinned canonical packages are present — the always-on layer was deleted while its sync registry lives; remove the layer AND this gate registry in the same MR, or restore the file"
  else
    echo "sync_pointer_check_skipped: agent-context/session-start.md missing — no always-on pointers to evaluate (canonical-side registry checks still run)"
  fi
fi

# Pinned-pair registry. Each row: name | literal that must survive in
# agent-context/session-start.md | canonical target (file, or file-exists:<path>) | literal that
# must survive in the target. A pair pins BOTH sides and BOTH sides are always
# reported (no early return): a two-sided drift must surface both diagnostics
# in one run, not cost two red cycles. Each literal must occur EXACTLY ONCE on
# its side (all current entries do): a zero count is drift, a >1 count is a
# decoy/duplicate that makes the pointer unverifiable — both block. (A
# relocated decoy reproducing the directive prefix verbatim is textually the
# directive itself; intent there is review-owned, not mechanical.)
check_pair() { # <name> <bootstrap literal> <target> <target literal>
  local bcount
  bcount="$(grep -oF -- "$2" "$bootstrap" | wc -l | tr -d ' ')"
  if [ "$bcount" -eq 0 ]; then
    block "$1: agent-context/session-start.md lost the registered pointer literal \`$2\` — reword the pointer AND this registry together"
  elif [ "$bcount" -ne 1 ]; then
    block "$1: agent-context/session-start.md carries the registered pointer literal \`$2\` ${bcount} times — a decoy/duplicate makes the pointer unverifiable"
  fi
  case "$3" in
    file-exists:*)
      [ -f "${3#file-exists:}" ] ||
        block "$1: canonical file ${3#file-exists:} missing — the always-on pointer would dangle"
      ;;
    *)
      local tcount
      tcount="$(grep -oF -- "$4" "$3" 2>/dev/null | wc -l | tr -d ' ')"
      if [ "$tcount" -eq 0 ]; then
        block "$1: canonical target $3 lost \`$4\` — the always-on pointer would dangle"
      elif [ "$tcount" -ne 1 ]; then
        block "$1: canonical target $3 carries \`$4\` ${tcount} times — a decoy/duplicate makes the anchor unverifiable"
      fi
      ;;
  esac
}

# run_pair wraps check_pair with the target-availability ladder. It is only
# ever reached with the always-on layer PRESENT (the no-bootstrap tree either
# blocked above or has no pinned package at all), so an absent package here is
# always the wholesale-bypass shape — there is no reachable skip branch to
# write, and inventing one would advertise a legal state that the r17
# tightening removed.
run_pair() { # <name> <bootstrap literal> <target> <target literal> <package-dir>
  local raw="$3"
  case "$raw" in
    file-exists:*) raw="${raw#*:}" ;;
  esac
  local state
  state="$(target_state "$raw" "$5")"
  case "$state" in
    0)
      # The always-on layer is alive while its pinned target is wholesale
      # deleted — the same bypass as deleting agent-context/session-start.md itself.
      block "$1: canonical package ${5##*/} missing while the always-on layer is present — its pins are bypassed wholesale"
      ;;
    2) block "$1: canonical target $raw missing inside a present package — the registered invariant is broken" ;;
    3) echo "sync_pointer_infra: $raw exists but is unreadable" >&2; exit 2 ;;
    1) check_pair "$1" "$2" "$3" "$4" ;;
  esac
}

if [ "$bootstrap_present" -eq 1 ]; then
  run_pair "merge-exec-protocol-section" \
    "「合并执行协议」（canonical" "$wt" "**合并执行协议（canonical——" "$root/skills/worktree-isolation"
  run_pair "merge-exec-citation-token" \
    "「依据: worktree-isolation 合并执行协议」" "$wt" "**合并执行协议（canonical——" "$root/skills/worktree-isolation"
  run_pair "worktree-teardown-section" \
    "在 \`worktree-isolation\` 收尾节" "$wt" "## 收尾：" "$root/skills/worktree-isolation"
  run_pair "owner-dispatch-firing-gate" \
    "product-rd \`Implementation entry / re-entry gate\` + \`Owner-dispatch firing gate\`" "$prd" "- **Owner-dispatch firing gate (" "$root/skills/product-rd-workflow"
  run_pair "implementation-entry-reentry-gate" \
    "product-rd \`Implementation entry / re-entry gate\` + \`Owner-dispatch firing gate\`" "$prd" "- **Implementation entry / re-entry gate (" "$root/skills/product-rd-workflow"
  run_pair "firing-point-placement-corollary" \
    "skill-extraction \`Firing-point-placement corollary\`" "$se" "- **Firing-point-placement corollary:**" "$root/skills/skill-extraction-workflow"
  # dtref existence is this pair's own assertion; this block only runs with
  # bootstrap present, so a wholesale-missing package here is always a bypass.
  if [ -d "$root/skills/skill-extraction-workflow" ]; then
    check_pair "dual-track-review-gate-ref" \
      "详见 product-rd 验证门 + skill-extraction \`dual-track-review-gate.md\`" "file-exists:$dtref" ""
  else
    block "dual-track-review-gate-ref: canonical package skill-extraction-workflow missing while the always-on layer is present — its pins are bypassed wholesale"
  fi
  run_pair "agent-command-sandbox" \
    "细则归 \`llm-inference-integration\` agent-command-sandbox" "file-exists:$root/skills/llm-inference-integration/references/agent-command-sandbox.md" "" "$llm_dir"
  run_pair "cross-model-caveat" \
    "详见 tighten-doc cross-model caveat" "$td" "CROSS-MODEL / CODEX CO-REVIEW CAVEAT" "$root/skills/tighten-doc"
  echo "sync_pointer_check_done"
fi

# --- security-four-questions subset registry ---------------------------------
sec4_state="$(target_state "$sec4" "$root/skills/requirement-doc-writer")"
[ "$sec4_state" = "0" ] && skipped_any=1
subset_out_tmp="$(mktemp "${TMPDIR:-/tmp}/sync-subset-out.XXXXXX")" ||
  { echo "sync_subset_infra: mktemp failed" >&2; exit 2; }
subset_err_tmp="$(mktemp "${TMPDIR:-/tmp}/sync-subset-err.XXXXXX")" ||
  { rm -f "$subset_out_tmp"; echo "sync_subset_infra: mktemp failed" >&2; exit 2; }
ruby -e '
# (This block runs inside a single-quoted ruby -e: keep it apostrophe-free.)
root = ARGV.fetch(0)
bootstrap_present = ARGV.fetch(1) == "1"
sec4_state = ARGV.fetch(2)
sec4 = File.join(root, "skills/requirement-doc-writer/references/security-four-questions.md")
if sec4_state == "0"
  if bootstrap_present
    warn "sync_subset_block: canonical package requirement-doc-writer missing while the always-on layer is present — the subset pins are bypassed wholesale"
    exit 3
  end
  puts "sync_subset_check_skipped: requirement-doc-writer package missing — subset registry not evaluated"
  exit 0
end
if sec4_state == "2"
  warn "sync_subset_block: canonical registry file missing inside a present package: #{sec4} — the registered invariant is broken"
  exit 3
end
if sec4_state != "1"
  warn "sync_subset_infra: #{sec4} exists but is unreadable"
  exit 2
end
bootstrap = File.join(root, "agent-context/session-start.md")
text = File.read(sec4)
blocks = text.scan(/<!--\s*sync-registry:v1\s*.*?-->/m)
if blocks.empty?
  warn "sync_subset_infra: sync-registry:v1 block missing in #{sec4}"
  exit 2
end
if blocks.length > 1
  warn "sync_subset_infra: #{blocks.length} sync-registry:v1 blocks in #{sec4} — exactly one is allowed (a second block could shadow the real registry)"
  exit 2
end
registry = {}
blocks.first.match(/<!--\s*sync-registry:v1\s*(.*?)-->/m)[1].each_line do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")
  key, value = line.split(":", 2)
  unless value
    warn "sync_subset_infra: unparseable registry line: #{line}"
    exit 2
  end
  key = key.strip
  if registry.key?(key)
    warn "sync_subset_infra: duplicate registry key #{key} — a last-wins override would be invisible"
    exit 2
  end
  registry[key] = value.strip
end
%w[trigger-canonical q2-canonical q4-canonical q2-bootstrap-min q4-bootstrap-min].each do |key|
  unless registry[key]
    warn "sync_subset_infra: registry missing key #{key}"
    exit 2
  end
end
split_list = ->(s) { s.split(",").map(&:strip).reject(&:empty?) }
canon = {
  "trigger" => split_list.call(registry["trigger-canonical"]),
  "q2" => split_list.call(registry["q2-canonical"]),
  "q4" => split_list.call(registry["q4-canonical"]),
}
aliases = {}
split_list.call(registry.fetch("alias", "")).each do |pair|
  left, right = pair.split("=", 2).map { |part| part.to_s.strip }
  if left.empty? || right.empty?
    warn "sync_subset_infra: unparseable alias pair: #{pair}"
    exit 2
  end
  aliases[left] = right
end
prose = text.sub(/<!--\s*sync-registry:v1\s*.*?-->/m, "")
failures = []
# Alias hygiene: the right side must be a real canonical trigger token (an
# alias must not map INTO a token the canonical set does not carry); the left
# side is validated against the extracted bootstrap list further down.
aliases.each do |left, right|
  failures << "alias right side \`#{right}\` is not in the canonical trigger set — an alias cannot map into a token the canonical set does not carry" unless canon["trigger"].include?(right)
end

# Canonical side: every registered token must appear inside its ANCHORED
# REGION (the 触发 section / the numbered 问题本体 item line), so narrative
# text elsewhere cannot satisfy the check. An unextractable region means the
# canonical file was restructured — co-update the anchors here.
sections = prose.split(/^## /)
trigger_section = sections.find { |s| s.start_with?("触发") }
body_section = sections.find { |s| s.start_with?("问题本体") }
q2_line = body_section && body_section.each_line.find { |l| l.match?(/\A\s*2\./) }
q4_line = body_section && body_section.each_line.find { |l| l.match?(/\A\s*4\./) }
# Token attestation is by LIST-ITEM EQUALITY inside the anchored region, never
# a substring test: a superstring (权限模型 attesting 权限) must not count. The
# trigger region is bounded to its own line ([^。\n]) so text on following
# lines cannot attest a token the list itself lost.
region_items = {}
region_items["trigger"] = trigger_section && (tm = trigger_section.match(/触及：([^。\n]+)/)) && tm[1].split("、")
region_items["q2"] = q2_line && (qm = q2_line.match(/\A\s*2\.\s*(.+?)这些输入/)) && qm[1].split(/[、或]/)
region_items["q4"] = q4_line && (qm4 = q4_line.match(/\A\s*4\.\s*至少一条(.+?)的负向用例/)) && qm4[1].split("/")
region_items.each do |group, items|
  if items.nil?
    failures << "canonical #{group} region unextractable (section structure changed) — co-update the extraction anchors in check-sync-pointers.sh"
    next
  end
  items = items.map(&:strip)
  canon[group].each do |token|
    failures << "canonical #{group} token \`#{token}\` absent from its list region of security-four-questions.md (registry/prose mismatch)" unless items.include?(token)
  end
end

# Bootstrap side: EXTRACT the compressed tables from the live text through
# anchored phrases. The scan must hit EXACTLY ONCE: a compliant decoy line
# inserted before the real reflection would otherwise satisfy the extraction
# while the real table drifts. Zero hits is anchor loss; both block.
if bootstrap_present
  btext = File.read(bootstrap)
  extractions = {
    "trigger" => [btext.scan(/触及 ([^ ]+) 时/), "·"],
    "q2" => [btext.scan(/若某值被(.+?)爆炸半径/), "/"],
    "q4" => [btext.scan(/写一条(.+?)负向用例/), "/"],
  }
  boot = {}
  extractions.each do |group, (hits, separator)|
    if hits.empty?
      failures << "agent-context/session-start.md compressed #{group} table no longer matches the registered anchor shape — reword the resident reflection AND the extraction anchors together"
    elsif hits.length > 1
      failures << "agent-context/session-start.md compressed #{group} anchor matches #{hits.length} times — a decoy/duplicate anchor makes the extraction ambiguous"
    else
      # Trim stray punctuation/particles at item edges so a legal rewording
      # (伪造/篡改，爆炸半径) does not false-red on a token like 篡改，
      boot[group] = hits.first[0].split(separator).map { |t| t.strip.gsub(/\A[，、。；：,.!? ]+|[，、。；：,.!? ]+\z/, "") }.reject(&:empty?)
    end
  end
  boot.each do |group, tokens|
    if group == "trigger"
      aliases.each_key do |left|
        failures << "alias left side \`#{left}\` is not in the extracted bootstrap trigger list — an unattested alias could map an escaping token back" unless tokens.include?(left)
      end
      aliases.each_value do |right|
        failures << "alias right side \`#{right}\` is also present verbatim in the bootstrap trigger list — an alias must be the sole attestation of its canonical token" if tokens.include?(right)
      end
      mapped = tokens.map { |t| aliases.fetch(t, t) }
      if mapped.uniq.length != mapped.length
        failures << "aliased trigger mapping collides (two tokens map to the same canonical token) — alias laundering shape"
      end
      extra = mapped - canon["trigger"]
      missing = canon["trigger"] - mapped
      failures << "bootstrap trigger table #{extra.inspect} escapes the canonical predicate set" unless extra.empty?
      failures << "canonical trigger tokens not reflected in the bootstrap list: #{missing.inspect} (alias or registry drift)" unless missing.empty?
    else
      extra = tokens - canon[group]
      failures << "bootstrap #{group} table #{extra.inspect} escapes the canonical predicate set" unless extra.empty?
      floor = split_list.call(registry.fetch("#{group}-bootstrap-min", ""))
      shed = floor - tokens
      failures << "bootstrap #{group} table shed required predicate(s) #{shed.inspect} (below the registered #{group}-bootstrap-min floor)" unless shed.empty?
    end
  end
end

if failures.empty?
  if bootstrap_present
    puts "sync_subset_check_done"
  else
    puts "sync_subset_check_skipped: bootstrap side not evaluated (canonical-side registry checks ran)"
  end
  exit 0
end
failures.each { |f| warn "sync_subset_block: #{f}" }
# 3, not 1: rc 1 is what an uncaught ruby exception returns, and the caller
# reports rc 1 as a declared registry violation. Keeping the two apart means a
# crashed interpreter can never masquerade as a policy verdict.
exit 3
' "$root" "$bootstrap_present" "$sec4_state" >"$subset_out_tmp" 2>"$subset_err_tmp"
subset_rc=$?
subset_out="$(cat "$subset_out_tmp")"
subset_err="$(cat "$subset_err_tmp")"
rm -f "$subset_out_tmp" "$subset_err_tmp"
[ -n "$subset_out" ] && printf '%s\n' "$subset_out"
[ -n "$subset_err" ] && printf '%s\n' "$subset_err" >&2

# An exit STATUS is not evidence the subset tier ran: an interpreter that never
# reached a declared exit — a shim, a wrapper, an empty `-e` program — returns
# whatever it likes, and a silent rc 0 would print the clean-landing token for a
# tier that evaluated ZERO rules (gate-did-not-judge read as gate-judged-and-
# passed). So every accepted status must also carry the tier's OWN terminal
# token; a status without its token is infra, never a verdict.
#
# TRUST BOUNDARY (settled; do not re-litigate per round). This is an anti-
# SILENCE control, not an anti-FORGERY one. It catches the accident class — an
# aborted, shimmed, wrapped, or locale-broken interpreter that returns a status
# without doing work. It does NOT defend against an interpreter that actively
# lies, and no in-band scheme can: a hostile `ruby` on PATH reads the same
# files, sees any nonce/digest the parent passes in, and can echo whatever the
# parent would accept — while the same hostile PATH already owns `grep`, `wc`,
# `git`, and the `bash` that runs this gate. Toolchain integrity belongs to the
# runner, not to one interpreter call inside one check; a control here would be
# strictly weaker than the attack it names.
# Attestation decides only whether the status is BELIEVED; an attested infra
# status still propagates as infra. Every branch that does not both match a
# declared outcome AND carry its token falls through to the fail-closed exit.
subset_attested=0
case "$subset_rc" in
  0) case "$subset_out" in *sync_subset_check_done*|*sync_subset_check_skipped*) subset_attested=1 ;; esac ;;
  3) case "$subset_err" in *sync_subset_block:*) subset_attested=1; fail=1 ;; esac ;;
esac
if [ "$subset_attested" -ne 1 ]; then
  echo "sync_subset_infra_failed rc=$subset_rc (subset registry could not be evaluated — fail-closed; a status without its terminal token means the embedded ruby never reached a declared outcome, and rc 1 means it aborted before evaluating any rule, e.g. a missing interpreter or a non-UTF-8 locale)" >&2
  exit 2
fi

if [ "$fail" -ne 0 ]; then
  echo "sync_semantic_blocking_failed: semantic sync registry violation(s) above block the gate (blocking since 2026-08-02); reword both sides of a registered pair/registry together, or drop the pointer" >&2
  exit 1
fi
# The ok token means EVERYTHING was evaluated and clean: any skip (bootstrap
# absent, package absent, subset tier skipped) suppresses it.
if [ "$bootstrap_present" -eq 1 ] && [ "$sec4_state" = "1" ] && [ "${skipped_any:-0}" -eq 0 ]; then
  echo "sync_semantic_check_ok"
fi
exit 0
