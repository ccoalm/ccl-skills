#!/usr/bin/env bash
# Behavioral + adversarial suite for the control-plane change detector.
# Proves the classification semantics AND the trust-root invariants:
# baseline-config authority (a candidate cannot self-declassify), hard-pinned
# enforcement chain, fail-closed malformed config, rename move-out capture.
set -u
ENGINE="$(cd "$(dirname "$0")" && pwd)/control-plane.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

WORK=$(mktemp -d) || { echo "FATAL: mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO/src"
git -C "$WORK" init -q repo
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo "package x" > "$REPO/src/foo.go"
printf 'check:\n\ttrue\n' > "$REPO/Makefile"
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
BASE=$(git -C "$REPO" rev-parse HEAD)

branch() { git -C "$REPO" checkout -q -B t-branch "$BASE"; }
commit_all() { git -C "$REPO" add -A && git -C "$REPO" commit -qm "$1"; }
run() { bash "$ENGINE" "$@" --repo "$REPO" --base "$BASE" --head t-branch; }

echo "control-plane suite"

# 1. product-only diff -> enforce exits 0, verdict product-only
branch; echo "// more" >> "$REPO/src/foo.go"; commit_all p1
out=$(run enforce); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^verdict: product-only' \
  && ok "product-only diff passes enforce" || bad "product-only diff" "rc=$rc out=$out"

# 2. Makefile edit -> control-plane; enforce exits 2; check exits 0 but reports
branch; printf '\nverify:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p2
out=$(run enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "Makefile edit -> enforce exit 2" || bad "Makefile enforce" "rc=$rc out=$out"
out=$(run check); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^verdict: CONTROL-PLANE' \
  && ok "check reports but exits 0 (warn-only)" || bad "Makefile check" "rc=$rc out=$out"

# 3. nested AGENTS.md + go.sum + ci/** -> control-plane
branch; mkdir -p "$REPO/pkg/sub" "$REPO/ci"
echo c > "$REPO/pkg/sub/AGENTS.md"; echo m > "$REPO/go.sum"; echo y > "$REPO/ci/x.yml"
commit_all p3
out=$(run enforce --json); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q '"pkg/sub/AGENTS.md"' \
  && printf '%s' "$out" | grep -q '"go.sum"' && printf '%s' "$out" | grep -q '"ci/x.yml"' \
  && ok "nested AGENTS.md / go.sum / ci/** all flagged (json)" || bad "nested flags" "rc=$rc out=$out"

# 4. rename move-out: Makefile -> renamed.txt still flags the Makefile deletion
branch; git -C "$REPO" mv Makefile renamed.txt; commit_all p4
out=$(run enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "rename of gated file still flagged (--no-renames)" || bad "rename move-out" "rc=$rc out=$out"

# 5. product_overrides declassifies a scripts/ product tool (config committed at BASE)
git -C "$REPO" checkout -q -B base2 "$BASE"
cat > "$REPO/.control-plane.json" <<'EOF'
{ "extend_globs": ["deploy/**"], "product_overrides": ["scripts/product-cli/**"] }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm cfg
BASE2=$(git -C "$REPO" rev-parse HEAD)
run2() { bash "$ENGINE" "$@" --repo "$REPO" --base "$BASE2" --head t-branch; }
git -C "$REPO" checkout -q -B t-branch "$BASE2"
mkdir -p "$REPO/scripts/product-cli"; echo s > "$REPO/scripts/product-cli/run.sh"; commit_all p5
out=$(run2 enforce); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'override:scripts/product-cli' \
  && ok "product_overrides declassifies repo product tool" || bad "override declassify" "rc=$rc out=$out"

# 6. extend_globs adds deploy/** -> flagged
git -C "$REPO" checkout -q -B t-branch "$BASE2"
mkdir -p "$REPO/deploy"; echo d > "$REPO/deploy/prod.yaml"; commit_all p6
out=$(run2 enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  deploy/prod.yaml' \
  && ok "extend_globs flags repo-specific path" || bad "extend_globs" "rc=$rc out=$out"

# 7. ADVERSARIAL: overrides can never declassify the enforcement chain (hard-pinned)
git -C "$REPO" checkout -q -B base3 "$BASE"
cat > "$REPO/.control-plane.json" <<'EOF'
{ "product_overrides": [".control-plane.json", "scripts/control-plane/**", "scripts/verify-sandbox/**", "ci/**", ".gitlab-ci.yml"] }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm evilcfg
BASE3=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE3"
mkdir -p "$REPO/scripts/control-plane" "$REPO/scripts/verify-sandbox" "$REPO/ci"
echo x > "$REPO/scripts/control-plane/control-plane.sh"; echo y > "$REPO/ci/pipe.yml"
echo z > "$REPO/scripts/verify-sandbox/verify-sandbox.sh"
echo '{}' > "$REPO/.control-plane.json"
commit_all p7
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE3" --head t-branch); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'pinned:scripts/control-plane' \
  && printf '%s' "$out" | grep -q 'pinned:scripts/verify-sandbox' \
  && printf '%s' "$out" | grep -q 'pinned:.control-plane.json' \
  && printf '%s' "$out" | grep -q 'pinned:ci/' \
  && ok "hard-pinned chain immune to product_overrides" || bad "hard-pin immunity" "rc=$rc out=$out"

# 8. ADVERSARIAL: candidate adds a config declassifying Makefile -> baseline config rules;
#    Makefile still flagged AND the new config file itself flagged
branch
cat > "$REPO/.control-plane.json" <<'EOF'
{ "product_overrides": ["Makefile"] }
EOF
printf '\nevil:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p8
out=$(run enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && printf '%s' "$out" | grep -q 'pinned:.control-plane.json' \
  && ok "candidate cannot self-declassify (config read from merge-base)" || bad "self-declassify" "rc=$rc out=$out"

# 8b. ADVERSARIAL: even a BASELINE-committed override cannot declassify the verify recipe
#     (root Makefile) or the secret-scan config — they are hard-pinned enforcement chain
git -C "$REPO" checkout -q -B base8b "$BASE"
cat > "$REPO/.control-plane.json" <<'EOF'
{ "product_overrides": ["Makefile", ".gitleaksignore", "tools/check-agent-contract-coverage.sh"] }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm pincfg
BASE8B=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE8B"
mkdir -p "$REPO/tools"
printf '\nevil:\n\ttrue\n' >> "$REPO/Makefile"
echo "fp:1" > "$REPO/.gitleaksignore"
echo x > "$REPO/tools/check-agent-contract-coverage.sh"
commit_all p8b
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE8B" --head t-branch); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'pinned:Makefile' \
  && printf '%s' "$out" | grep -q 'pinned:.gitleaksignore' \
  && printf '%s' "$out" | grep -q 'pinned:tools/check-agent-contract-coverage.sh' \
  && ok "verify recipe + secret-scan config + contract engine hard-pinned" || bad "pin core chain" "rc=$rc out=$out"

# 9. FAIL-CLOSED: malformed config at base -> exit 3, never a silent pass
git -C "$REPO" checkout -q -B base4 "$BASE"
echo '{ not json' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm badcfg
BASE4=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE4"
echo "// x" >> "$REPO/src/foo.go"; commit_all p9
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE4" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -qi 'malformed' \
  && ok "malformed config fail-closed (exit 3)" || bad "malformed config" "rc=$rc out=$out"

# 10. FAIL-CLOSED: unknown config key -> exit 3 (typo'd override key must not silently no-op)
git -C "$REPO" checkout -q -B base5 "$BASE"
echo '{ "product_override": ["Makefile"] }' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm typocfg
BASE5=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE5"
echo "// y" >> "$REPO/src/foo.go"; commit_all p10
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE5" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "unknown config key fail-closed (exit 3)" || bad "unknown key" "rc=$rc out=$out"

# 10b. FAIL-CLOSED: PRESENT-but-empty config file -> exit 3 (absence != empty file)
git -C "$REPO" checkout -q -B base10b "$BASE"
: > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm emptycfg
BASE10B=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE10B"
echo "// z" >> "$REPO/src/foo.go"; commit_all p10b
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE10B" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "empty config file fail-closed (exit 3)" || bad "empty config" "rc=$rc out=$out"

# 10c. precedence: a broad product_override cannot cancel an extend_globs entry
git -C "$REPO" checkout -q -B base10c "$BASE"
cat > "$REPO/.control-plane.json" <<'EOF'
{ "extend_globs": ["deploy/**"], "product_overrides": ["**"] }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm widecfg
BASE10C=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE10C"
mkdir -p "$REPO/deploy" "$REPO/.github/workflows"
echo d > "$REPO/deploy/prod.yaml"; echo w > "$REPO/.github/workflows/x.yml"; echo m > "$REPO/go.sum"
commit_all p10c
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE10C" --head t-branch); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'extend:deploy/' \
  && printf '%s' "$out" | grep -q 'pinned:.github/' \
  && printf '%s' "$out" | grep -q 'override:\*\*.*go.sum\|go.sum.*override' \
  && ok "override never cancels extend_globs; .github pinned; defaults overridable" \
  || { printf '%s' "$out" | grep -q 'extend:deploy/' && printf '%s' "$out" | grep -q 'pinned:.github/' && [ "$rc" = 2 ] \
       && ok "override never cancels extend_globs; .github pinned" || bad "precedence" "rc=$rc out=$out"; }

# 10d. ADVERSARIAL: a control-plane path with a newline (git C-quotes it in non-z output)
#      must still match its glob via the NUL stream — no quoted-literal bypass
branch; mkdir -p "$REPO/ci"
evil="$REPO/ci/$(printf 'a\nb').yml" 2>/dev/null || evil=""
if [ -n "$evil" ] && printf 'x\n' > "$evil" 2>/dev/null; then
  commit_all p10d
  out=$(run enforce); rc=$?
  [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'pinned:ci/' \
    && ok "newline-in-path still matches ci/** (NUL stream, no C-quote bypass)" \
    || bad "newline path bypass" "rc=$rc out=$out"
  git -C "$REPO" checkout -q -B t-branch "$BASE"   # drop the weird file from later cases
else
  ok "newline-in-path case skipped (filesystem refuses newline filenames)"
fi

# 10e. ADVERSARIAL: a gitlink/submodule committed AT a gated directory path ('ci', not
#      'ci/x') must still classify control-plane — a dir-entry replace is a tree replace
branch
git -C "$REPO" update-index --add --cacheinfo 160000,"$BASE",ci 2>/dev/null \
  && git -C "$REPO" commit -qm p10e
out=$(run enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'pinned:ci' \
  && ok "gitlink at gated dir path flagged (dir/** matches bare dir)" || bad "gitlink dir bypass" "rc=$rc out=$out"
git -C "$REPO" checkout -q -B t-branch "$BASE"

# 10f. test-runner config surface: pytest.ini (can silently drop test dirs) -> control-plane
branch; printf '[pytest]\naddopts = -q\n' > "$REPO/pytest.ini"; commit_all p10f
out=$(run enforce); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  pytest.ini' \
  && ok "pytest.ini flagged (test-runner config surface)" || bad "pytest.ini" "rc=$rc out=$out"

# 10g. FAIL-CLOSED: malformed baseline config + EMPTY diff still exits 3 (no early-return pass)
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE4" --head "$BASE4" 2>&1); rc=$?
[ "$rc" = 3 ] && ok "malformed config + empty diff fail-closed (exit 3)" || bad "empty-diff config bypass" "rc=$rc out=$out"

# 10h. enumeration-completeness regressions (challenge R2): lowercase nested makefile,
#      compose .yaml variants, docs/CODEOWNERS
out=$(bash "$ENGINE" classify sub/makefile compose.yaml docker-compose.yaml docs/CODEOWNERS services/api/compose.override.yaml .gitmodules npm-shrinkwrap.json sub/npm-shrinkwrap.json pnpm-workspace.yaml bun.lock 2>&1); rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q '^  product' \
  && ok "nested makefile / compose.yaml / CODEOWNERS / shrinkwrap / .gitmodules / workspace all control-plane" \
  || bad "enumeration gaps" "rc=$rc out=$out"

# 10i. FAIL-CLOSED: config with a valid-JSON prefix + NUL tail is malformed (exact-bytes
#      parse — bash command substitution would have silently dropped the NUL)
git -C "$REPO" checkout -q -B base10i "$BASE"
printf '{ "product_overrides": ["**"] }\0' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm nulcfg
BASE10I=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -B t-branch "$BASE10I"
echo m > "$REPO/go.sum"; commit_all p10i
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE10I" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "NUL-tail config fail-closed (exact-bytes parse, exit 3)" || bad "NUL config bypass" "rc=$rc out=$out"

# 11. empty diff -> clean, exit 0
git -C "$REPO" checkout -q -B t-branch "$BASE"
out=$(run enforce); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'clean' \
  && ok "empty diff clean" || bad "empty diff" "rc=$rc out=$out"

# 12. classify (no git) + --config override for unit-style checks
out=$(bash "$ENGINE" classify Makefile src/a.go 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && printf '%s' "$out" | grep -q 'product        src/a.go' \
  && ok "classify literal paths" || bad "classify" "rc=$rc out=$out"

# 13. ci subcommand: warn-only by default (exit 0), --enforce exits 2
branch; printf '\nz:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p13
out=$(bash "$ENGINE" ci --repo "$REPO" --base "$BASE" --head t-branch); rc=$?
[ "$rc" = 0 ] && ok "ci default warn-only" || bad "ci warn-only" "rc=$rc"
out=$(bash "$ENGINE" ci --enforce --repo "$REPO" --base "$BASE" --head t-branch); rc=$?
[ "$rc" = 2 ] && ok "ci --enforce blocks" || bad "ci enforce" "rc=$rc"

# 14. json verdict machine-parses
branch; echo "// j" >> "$REPO/src/foo.go"; commit_all p14
out=$(run check --json)
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"]=="product-only", d' \
  && ok "json output parses" || bad "json parse" "$out"

# 15. FAIL-CLOSED: a gitlink at .control-plane.json in the BASELINE tree must not read as
#     "absent" (git show fails on a foreign gitlink -> silent default-rules fallback)
git -C "$REPO" checkout -q -B base15 "$BASE"
git -C "$REPO" update-index --add --cacheinfo 160000,"$BASE",.control-plane.json
git -C "$REPO" commit -qm cfg-gitlink
BASE15=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -f -B t-branch "$BASE15" 2>/dev/null
echo m > "$REPO/go.sum"; commit_all p15 >/dev/null 2>&1
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE15" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'not a regular blob' \
  && ok "gitlink at baseline .control-plane.json fail-closed (exit 3)" || bad "gitlink config read as absent" "rc=$rc out=$out"
git -C "$REPO" checkout -q -f -B t-branch "$BASE"

# 16. FAIL-CLOSED: a symlink at .control-plane.json (special-mode blob — ls-tree TYPE is
#     still "blob", so the mode allowlist is what refuses it) in the CANDIDATE tree
git -C "$REPO" checkout -q -f -B base16 "$BASE"
sha=$(printf '/etc/passwd' | git -C "$REPO" hash-object -w --stdin)
git -C "$REPO" update-index --add --cacheinfo 120000,"$sha",.control-plane.json
git -C "$REPO" commit -qm cfg-symlink
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head base16 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'not a regular blob' \
  && ok "symlink at candidate .control-plane.json fail-closed (exit 3)" || bad "symlink config accepted" "rc=$rc out=$out"

# 17. CANDIDATE GATE: a malformed config in the HEAD tree is refused even though
#     classification authority stays with the merge-base config
git -C "$REPO" checkout -q -f -B base17 "$BASE"
printf '{ "extend_globs": ["deploy/**"] }\n' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm cfg-ok
BASE17=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -f -B t-branch "$BASE17"
printf '{ "extend_globs": [ }\n' > "$REPO/.control-plane.json"; echo "// c" >> "$REPO/src/foo.go"
commit_all p17 >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE17" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "malformed CANDIDATE config fail-closed (exit 3)" || bad "candidate config ungated" "rc=$rc out=$out"
#     …and a well-formed candidate that tries to self-declassify still cannot: the verdict
#     comes from the baseline config only
git -C "$REPO" checkout -q -f -B t-branch "$BASE17"
printf '{ "product_overrides": ["**"] }\n' > "$REPO/.control-plane.json"; echo m > "$REPO/go.sum"
commit_all p17b >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE17" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && ok "well-formed candidate cannot self-declassify (baseline authority)" || bad "candidate self-declassify" "rc=$rc out=$out"
#     …and two non-JSON shapes Python's decoder would otherwise wave through: the NaN /
#     Infinity extension, and duplicate keys (last-wins silently discards the reviewed value)
for bad in '{ "_comment": NaN }' '{ "extend_globs": ["a/**"], "extend_globs": ["b/**"] }'; do
  git -C "$REPO" checkout -q -f -B t-branch "$BASE17"
  printf '%s\n' "$bad" > "$REPO/.control-plane.json"; echo "// x" >> "$REPO/src/foo.go"
  commit_all p17c >/dev/null
  out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE17" --head t-branch 2>&1); rc=$?
  [ "$rc" = 3 ] || { bad "non-JSON candidate accepted: $bad" "rc=$rc out=$out"; json_bad=1; }
done
[ -z "${json_bad:-}" ] && ok "NaN/Infinity and duplicate keys rejected (JSON, not Python literals)"
git -C "$REPO" checkout -q -f -B t-branch "$BASE"

# 18. --repo given a SUBDIRECTORY normalizes to the worktree root (paths stay root-relative)
branch; printf '\ny:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p18 >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO/src" --base "$BASE" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "--repo subdirectory normalized to worktree root" || bad "--repo subdir" "rc=$rc out=$out"

# 19. --repo is the ONLY source of repository identity: ambient repo-routing variables are
#     unset, so no GIT_DIR/GIT_COMMON_DIR/GIT_NAMESPACE form — relative, absolute, or `..` —
#     can make the run read a different repository than the one named by --repo.
branch; echo "// g" >> "$REPO/src/foo.go"; commit_all p19 >/dev/null
rm -rf "$WORK/decoy"; git -C "$WORK" init -q decoy
git -C "$WORK/decoy" config user.email t@t; git -C "$WORK/decoy" config user.name t
printf 'check:\n\ttrue\n' > "$WORK/decoy/Makefile"; git -C "$WORK/decoy" add -A
git -C "$WORK/decoy" commit -qm decoy-init
for form in ".git" "$WORK/decoy/.git" "../decoy/.git"; do
  out=$(cd "$WORK" && GIT_DIR="$form" GIT_COMMON_DIR="$form" bash "$ENGINE" \
          enforce --repo "$REPO" --base "$BASE" --head t-branch 2>&1); rc=$?
  [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^verdict: product-only' \
    || { bad "ambient GIT_DIR form '$form' changed the classified repo" "rc=$rc out=$out"; form_bad=1; }
done
[ -z "${form_bad:-}" ] && ok "ambient GIT_DIR/GIT_COMMON_DIR (relative, absolute, ..) cannot redirect the run"
out=$(cd "$WORK" && GIT_NAMESPACE=decoy bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head t-branch 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^verdict: product-only' \
  && ok "ambient GIT_NAMESPACE cannot redirect ref resolution" || bad "GIT_NAMESPACE honoured" "rc=$rc out=$out"

# 23b. CONFIG injection: core.worktree pushed in through GIT_CONFIG_COUNT/KEY_n/VALUE_n (or
#      GIT_CONFIG_PARAMETERS) must not replace the repository named by --repo. In an MR
#      pipeline the CI definition is candidate-controlled, so this channel is reachable by
#      the party being gated.
branch; printf '\nc:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p23b >/dev/null
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$WORK/decoy" \
      bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "GIT_CONFIG_* core.worktree injection cannot replace --repo" || bad "config injection" "rc=$rc out=$out"
out=$(GIT_CONFIG_PARAMETERS="'core.worktree=$WORK/decoy'" \
      bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && ok "GIT_CONFIG_PARAMETERS injection cannot replace --repo" || bad "config parameters injection" "rc=$rc out=$out"

# 23c. a non-blob BASELINE config must be REPAIRABLE through normal CI: the candidate that
#      turns it back into a regular blob classifies (conservatively, as control-plane —
#      the config file is hard-pinned), instead of every later MR exiting 3 forever.
git -C "$REPO" checkout -q -f -B base23c "$BASE"
git -C "$REPO" update-index --add --cacheinfo 160000,"$BASE",.control-plane.json
git -C "$REPO" commit -qm cfg-broken; BASE23C=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -f -B t-branch "$BASE23C" 2>/dev/null
git -C "$REPO" rm -q --cached .control-plane.json >/dev/null 2>&1
rm -rf "$REPO/.control-plane.json"   # gitlink checkout leaves a DIRECTORY at that path
printf '{ "extend_globs": ["deploy/**"] }\n' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm repair >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23C" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'candidate repairs it' \
  && ok "broken baseline config is repairable (not a permanent brick)" || bad "baseline brick" "rc=$rc out=$out"
#      …a repair that is not valid JSON does not slip through the relaxed baseline path:
#      the candidate gate still parses it and fails closed
git -C "$REPO" checkout -q -f -B t-branch "$BASE23C" 2>/dev/null
git -C "$REPO" rm -q --cached .control-plane.json >/dev/null 2>&1
rm -rf "$REPO/.control-plane.json"   # same: the path is a directory after the gitlink checkout
printf '{ "extend_globs": [ }\n' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm repair-malformed >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23C" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'candidate config malformed' \
  && ok "malformed repair of a broken baseline still fails closed" || bad "repair path fail-open" "rc=$rc out=$out"
#      …but a candidate that does NOT repair it still fails closed
git -C "$REPO" checkout -q -f -B t-branch "$BASE23C" 2>/dev/null
echo m > "$REPO/go.sum"; commit_all p23c2 >/dev/null 2>&1
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23C" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "broken baseline without repair still fails closed" || bad "baseline brick fail-open" "rc=$rc out=$out"
git -C "$REPO" checkout -q -f -B t-branch "$BASE"

# 23d. a MALFORMED baseline config gets the same repair hatch as a non-blob one — the gate's
#      rules tighten over time (NaN/Infinity, duplicate keys), so a config that was legal when
#      committed can become malformed later and brick every MR, including its own fix.
git -C "$REPO" checkout -q -f -B base23d "$BASE"
printf '{ "_comment": NaN }\n' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm cfg-nan >/dev/null
BASE23D=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -f -B t-branch "$BASE23D"
printf '{ "extend_globs": ["deploy/**"] }\n' > "$REPO/.control-plane.json"
git -C "$REPO" add -A && git -C "$REPO" commit -qm repair-json >/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23D" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'candidate repairs it' \
  && ok "malformed baseline config is repairable (not a permanent brick)" || bad "malformed baseline brick" "rc=$rc out=$out"
#      …and DELETING the config counts as a repair too (absent = defaults; the sibling
#      non-blob hatch already accepts removal, so both hatches must agree)
git -C "$REPO" checkout -q -f -B t-branch "$BASE23D"
git -C "$REPO" rm -q .control-plane.json >/dev/null 2>&1
git -C "$REPO" commit -qm drop-cfg >/dev/null 2>&1
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23D" --head t-branch 2>&1); rc=$?
[ "$rc" = 2 ] && ok "removing a malformed baseline config counts as repair" || bad "removal not accepted as repair" "rc=$rc out=$out"
#      …and without a repair it still fails closed
git -C "$REPO" checkout -q -f -B t-branch "$BASE23D"
echo m > "$REPO/go.sum"; commit_all p23d2 >/dev/null 2>&1
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE23D" --head t-branch 2>&1); rc=$?
[ "$rc" = 3 ] && ok "malformed baseline without repair still fails closed" || bad "malformed baseline fail-open" "rc=$rc out=$out"
git -C "$REPO" checkout -q -f -B t-branch "$BASE"

# 23e. a worktree root whose directory name ends in a NEWLINE must not collapse to the
#      adjacent path — `$(...)` strips trailing newlines, and if the neighbour is also a
#      repository the run would classify the wrong one
NLDIR="$WORK/nlrepo
"
mkdir -p "$WORK/nlrepo" 2>/dev/null   # the neighbour that the stripped path would hit
git -C "$WORK/nlrepo" init -q 2>/dev/null
if mkdir -p "$NLDIR" 2>/dev/null && git -C "$NLDIR" init -q 2>/dev/null; then
  git -C "$NLDIR" config user.email t@t; git -C "$NLDIR" config user.name t
  printf 'check:\n\ttrue\n' > "$NLDIR/Makefile"
  git -C "$NLDIR" add -A >/dev/null 2>&1; git -C "$NLDIR" commit -qm init >/dev/null 2>&1
  NLBASE=$(git -C "$NLDIR" rev-parse HEAD)
  git -C "$NLDIR" checkout -q -b t 2>/dev/null
  printf '\nz:\n\ttrue\n' >> "$NLDIR/Makefile"; git -C "$NLDIR" commit -qam cp >/dev/null 2>&1
  out=$(bash "$ENGINE" enforce --repo "$NLDIR" --base "$NLBASE" --head t 2>&1); rc=$?
  [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
    && ok "newline-terminated worktree root is not collapsed to its neighbour" \
    || bad "newline root collapse" "rc=$rc out=$out"
else
  ok "newline-in-directory-name case skipped (filesystem refuses it)"
fi

# 24. receive-pack QUARANTINE: in a pre-receive hook the pushed commit exists ONLY in
#     GIT_OBJECT_DIRECTORY (main store reachable via GIT_ALTERNATE_OBJECT_DIRECTORIES).
#     Clearing those two would make the candidate unresolvable and reject every push, so
#     they survive exactly when git marks the hook with GIT_QUARANTINE_PATH.
QDIR="$WORK/quarantine"; rm -rf "$QDIR"; mkdir -p "$QDIR"
git -C "$REPO" checkout -q -B t-branch "$BASE"
printf '\nq:\n\ttrue\n' >> "$REPO/Makefile"
# (the object write is redirected here; GIT_QUARANTINE_PATH is set only for the ENGINE run
#  below — with it set, git refuses the ref update and the fixture would build nothing)
GIT_OBJECT_DIRECTORY="$QDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$REPO/.git/objects" \
  git -C "$REPO" add -A >/dev/null 2>&1
GIT_OBJECT_DIRECTORY="$QDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$REPO/.git/objects" \
  git -C "$REPO" commit -qm quarantined >/dev/null 2>&1
QOID=$(git -C "$REPO" rev-parse HEAD)
# the commit object must genuinely live only in the quarantine dir
in_main=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO" cat-file -e "$QOID" 2>/dev/null && echo yes || echo no)
out=$(GIT_OBJECT_DIRECTORY="$QDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$REPO/.git/objects" \
      GIT_QUARANTINE_PATH="$QDIR" bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head "$QOID" 2>&1); rc=$?
if [ "$in_main" = no ]; then
  [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
    && ok "quarantined head object still resolvable (pre-receive hook shape)" \
    || bad "quarantine object store cleared" "rc=$rc out=$out"
else
  bad "quarantine fixture invalid" "commit landed in the main store; test proves nothing"
fi
git -C "$REPO" checkout -q -f -B t-branch "$BASE"

# 22. TRUE OBJECTS ONLY: a `git replace` ref must not decide the verdict. Without
#     GIT_NO_REPLACE_OBJECTS the diff would follow the replacement commit, so a decoy that
#     touches only product files declassifies a real control-plane change.
branch; printf '\nr:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p22 >/dev/null
REAL=$(git -C "$REPO" rev-parse t-branch)
git -C "$REPO" checkout -q -B decoy "$BASE"; echo "// decoy" >> "$REPO/src/foo.go"
git -C "$REPO" add -A && git -C "$REPO" commit -qm decoy
DECOY=$(git -C "$REPO" rev-parse decoy)
git -C "$REPO" replace -f "$REAL" "$DECOY" 2>/dev/null
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head "$REAL" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "replace ref cannot declassify a control-plane change" || bad "replace-ref bypass" "rc=$rc out=$out"
git -C "$REPO" replace -d "$REAL" >/dev/null 2>&1

# 23. TRUE OBJECTS ONLY: the legacy .git/info/grafts file must not decide the verdict — a
#     graft making the base a descendant of head collapses the merge-base to head, and the
#     empty diff then reads as clean.
printf '%s %s\n' "$BASE" "$REAL" > "$REPO/.git/info/grafts"
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head "$REAL" 2>&1); rc=$?
rm -f "$REPO/.git/info/grafts"
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "legacy grafts file cannot collapse the diff range" || bad "grafts bypass" "rc=$rc out=$out"
git -C "$REPO" checkout -q -B t-branch "$BASE"

# 20. BARE repo: no worktree root, but every path it produces is already root-relative —
#     server-side hooks and mirror CI classify from bare clones, so it must still work
branch; printf '\nb:\n\ttrue\n' >> "$REPO/Makefile"; commit_all p20 >/dev/null
BARE="$WORK/bare.git"; rm -rf "$BARE"; git clone -q --bare "$REPO" "$BARE"
out=$(bash "$ENGINE" ci --repo "$BARE" --base "$BASE" --head t-branch 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'CONTROL-PLANE  Makefile' \
  && ok "bare repo classifies (no worktree-root normalization)" || bad "bare repo refused" "rc=$rc out=$out"

# 21. --base/--head are pinned to commit OIDs once (they are read three times below: the
#     merge-base, the diff, and the candidate-config lookup — a mutable ref moving between
#     those reads would let a clean-config commit vouch for a different, diffed commit).
#     Observable proxies: a ref and its OID give identical verdicts, and a non-commit ref
#     is refused up front rather than reaching one of the three call sites.
out_ref=$(run enforce 2>&1); rc_ref=$?
HEADOID=$(git -C "$REPO" rev-parse t-branch)
out_oid=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head "$HEADOID" 2>&1); rc_oid=$?
[ "$rc_ref" = "$rc_oid" ] && [ "$out_ref" = "$out_oid" ] \
  && ok "ref and OID --head give identical verdicts (single pinned resolution)" || bad "ref/OID mismatch" "rc=$rc_ref/$rc_oid"
treeish=$(git -C "$REPO" rev-parse t-branch^{tree})
out=$(bash "$ENGINE" enforce --repo "$REPO" --base "$BASE" --head "$treeish" 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'cannot resolve --head to a commit' \
  && ok "non-commit --head refused at the single resolution point" || bad "non-commit head" "rc=$rc out=$out"

echo
echo "control-plane: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
