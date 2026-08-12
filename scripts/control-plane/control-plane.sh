#!/usr/bin/env bash
# control-plane.sh — deterministic control-plane change detector (mechanical-gate backlog ①).
#
# Classifies each file changed between a base ref and a head ref as CONTROL-PLANE or product.
# "Control plane" = anything that decides how future changes are verified, gated, installed,
# resolved, configured, or executed: CI/pipeline files, Makefiles/build recipes, hooks, agent
# contracts (AGENTS.md/CLAUDE.md/CODEOWNERS), gate engines and their configs, plugin manifests,
# and the toolchain-capture surface (Dockerfiles, lockfiles, go.mod/go.sum, package manifests,
# test-runner plugins). A verify gate cannot protect itself from a diff that edits the gate —
# such diffs must be routed to explicit human authorization instead of any auto path.
#
# SUBCOMMANDS
#   check   --base REF [--head REF] [--repo DIR] [--json]   report classification; exit 0
#   enforce --base REF [--head REF] [--repo DIR] [--json]   exit 2 if any control-plane file
#   ci      --base REF [--enforce]                          CI backstop (check by default)
#   classify [--config FILE] PATH...                        classify literal paths (no git)
#
# EXIT CODES: 0 = ok/product-only · 2 = control-plane touched (enforce/ci --enforce only)
#             3 = usage or config error (fail-closed: a malformed config never passes silently)
#
# CONFIG (.control-plane.json at the repo top level — optional; defaults apply without it)
#   { "extend_globs": ["deploy/**"], "product_overrides": ["scripts/product-cli/**"] }
#   - extend_globs: additional control-plane patterns for this repo.
#   - product_overrides: default matches this repo deliberately treats as product code.
#   TRUST ROOT: the config is read from the MERGE-BASE (pre-candidate) tree, never from the
#   candidate diff — a candidate cannot declassify itself. The config file and this engine's
#   own path are hard-pinned control-plane and can never be overridden.
#   CANDIDATE GATE: a .control-plane.json in the HEAD tree is additionally syntax-validated
#   (same fail-closed schema) whenever its bytes differ from the merge-base config, or no
#   merge-base config exists: malformed -> exit 3 ("candidate config malformed").
#   Classification still uses ONLY the merge-base config (trust root unchanged).
#   NON-BLOB ENTRIES: in BOTH trees the config entry must be a regular blob (mode
#   100644/100755). A gitlink/submodule, tree, or symlink at that path is exit 3
#   ("config entry is not a regular blob"), never "absent": a foreign gitlink makes
#   `git show` fail (which used to read as absent -> silent default-rules fallback),
#   and a symlink could point outside the tree — both are indirect-rewrite vectors.
set -u

SELF="$0"
die() { printf 'control-plane: %s\n' "$*" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || die "python3 required"

usage() { sed -n '2,30p' "$SELF" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

CMD="${1:-}"; [ -n "$CMD" ] && shift || usage 3
BASE=""; HEAD_REF="HEAD"; REPO="."; REPO_EXPLICIT=0; JSON=0; ENFORCE=0; CONFIG_OVERRIDE=""
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || die "--base requires a value"; BASE="$2"; shift 2 ;;
    --head) [ $# -ge 2 ] || die "--head requires a value"; HEAD_REF="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || die "--repo requires a value"; REPO="$2"; REPO_EXPLICIT=1; shift 2 ;;
    --config) [ $# -ge 2 ] || die "--config requires a value"; CONFIG_OVERRIDE="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --enforce) ENFORCE=1; shift ;;
    -h|--help) usage 0 ;;
    --*) die "unknown option: $1" ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

case "$CMD" in
  check) ENFORCE=0 ;;
  enforce) ENFORCE=1 ;;
  ci) : ;;                       # ENFORCE from --enforce flag (default warn-only)
  classify) : ;;
  -h|--help) usage 0 ;;
  *) die "unknown subcommand: $CMD (check|enforce|ci|classify)" ;;
esac

# resolve_tree_config <ref> <dest>: fail-closed three-state resolution of
# <ref>:.control-plane.json. Sets CFG_STATE=blob (regular blob; exact bytes written to
# <dest>) or CFG_STATE=absent (no entry at that path — defaults apply). ANY other entry
# kind — gitlink/submodule (whose commit may not even exist in this repo, making a naive
# `git show` read as absent), tree, or symlink (a special-mode blob that can point outside
# the tree) — exits 3. Mode allowlist, not type: a symlink's ls-tree TYPE is also "blob".
# NOTE: sets a global (no command substitution) — an `exit 3` inside $(...) would only
# kill the subshell and read as an empty result in the parent.
CFG_STATE=""
resolve_tree_config() {
  local ref="$1" dest="$2" line mode sha
  line="$(git -C "$REPO" ls-tree "$ref" -- .control-plane.json 2>/dev/null)" \
    || die "cannot inspect ${ref}:.control-plane.json"
  if [ -z "$line" ]; then CFG_STATE=absent; return 0; fi
  mode="${line%% *}"
  case "$mode" in
    100644|100755) : ;;
    *) printf 'control-plane: config entry is not a regular blob (%s:.control-plane.json, mode %s — gitlink/tree/symlink refused)\n' "$ref" "$mode" >&2
       CFG_STATE=nonblob; return 0 ;;
  esac
  sha="$(printf '%s' "$line" | awk '{print $3}')"
  git -C "$REPO" cat-file blob "$sha" > "$dest" 2>/dev/null \
    || die "cannot read config blob ${ref}:.control-plane.json"
  CFG_STATE=blob
}

# ----- collect changed files + baseline config --------------------------------
# Paths travel as a NUL-delimited stream in a temp file: `--name-only` C-quotes paths with
# special characters (a quoted literal would then MISS its glob — an enforce bypass), and
# neither bash variables nor env vars can carry NUL bytes.
FILES_TMP="$(mktemp "${TMPDIR:-/tmp}/cp-files.XXXXXX")" || die "mktemp failed"
CFG_TMP="$(mktemp "${TMPDIR:-/tmp}/cp-cfg.XXXXXX")" || die "mktemp failed"
CAND_CFG_TMP="$(mktemp "${TMPDIR:-/tmp}/cp-cand-cfg.XXXXXX")" || die "mktemp failed"
trap 'rm -f "$FILES_TMP" "$CFG_TMP" "$CAND_CFG_TMP"' EXIT
# Config ALSO travels as raw bytes in a temp file: bash command substitution drops NUL
# bytes, which would let a config with a valid-JSON prefix + NUL tail parse as valid —
# python reads the exact bytes and fail-closes on anything that is not clean UTF-8 JSON.
CONFIG_PRESENT=0     # 1 = a config FILE exists (even if empty — empty is malformed, fail closed)
CAND_CONFIG_PRESENT=0  # 1 = HEAD-tree config needs the candidate syntax gate (differs from baseline)
CAND_CFG_STATE=""      # blob | absent (nonblob dies before reaching the python core)
if [ "$CMD" = "classify" ]; then
  [ "${#PATHS[@]}" -gt 0 ] || die "classify: no paths given"
  if [ -n "$CONFIG_OVERRIDE" ]; then
    [ -f "$CONFIG_OVERRIDE" ] || die "config not found: $CONFIG_OVERRIDE"
    cat "$CONFIG_OVERRIDE" > "$CFG_TMP" || die "cannot read config: $CONFIG_OVERRIDE"
    CONFIG_PRESENT=1
  fi
  printf '%s\0' "${PATHS[@]}" > "$FILES_TMP" || die "cannot write path list"
else
  command -v git >/dev/null 2>&1 || die "git required"
  [ -n "$BASE" ] || die "$CMD: --base REF required"
  # True objects only, for every git call below. Both vars are load-bearing and neither
  # substitutes for the other (same finding as the sibling owner-dispatch engine, verified
  # on git 2.50): `git replace` refs and the legacy `.git/info/grafts` file each rewrite what
  # a commit OID resolves to. Pinning OIDs alone would NOT close the classification race —
  # a replace ref updated between the diff and the config lookup makes one OID mean two
  # different trees within a single run.
  export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null
  # ONE source of repository identity: --repo. Every ambient repo-ROUTING variable is
  # UNSET for the whole run rather than reconciled with it.
  #
  # Three consecutive adversarial rounds each found a new hole in the reconcile approach —
  # relative values re-resolving against a different -C target, an anchor choice that let a
  # stray GIT_DIR redirect the run to the caller's own repository, then absolute/`..` values
  # that survive any prefixing — because the premise is unsound: `--repo` and an ambient
  # GIT_DIR are two answers to "which repository", and every fix only moved which one wins.
  # Whatever survives, a wrong answer is a product-only verdict authorizing an unrelated
  # control-plane change. Deleting the ambient answer removes the class: git then discovers
  # the repository from `-C "$REPO"` alone, exactly as the caller asked. GIT_NAMESPACE and
  # the object-store overrides go too — they redirect refs/objects without changing the repo
  # path, which is the same failure wearing a different variable name.
  #
  # Cost of the deletion, stated plainly: a caller who pointed the gate at a repository
  # THROUGH the environment (GIT_DIR set, --repo left at ".") while standing somewhere else
  # must now pass --repo. That call now fails LOUDLY ("not a git repository") instead of
  # classifying something; a git hook, which runs with cwd inside the repository, is
  # unaffected.
  # The clearing is scoped to an EXPLICIT --repo, because that is the only case with two
  # competing answers. Without --repo the gate has stated no repository of its own, so git's
  # normal discovery (environment included) is the caller's intent — that is how a git hook
  # invokes it. Clearing unconditionally would not make such a run safer; it would just
  # silently move it from the caller's repository to whatever lies under cwd.
  if [ "$REPO_EXPLICIT" = 1 ]; then
    # git's CONFIG-injection channels are deliberately LEFT ALONE. A review round claimed
    # injected `core.worktree` replaces --repo after it validated; measured on git 2.50.1 it
    # does not (--show-toplevel still returns the discovery root), so clearing them defended
    # nothing measurable — while `git -c safe.directory=...` (which travels in exactly those
    # variables) is how a foreign-owned CI checkout stays usable, so clearing them CAN kill
    # the gate in the environment it must run in. Trading a real operational failure for an
    # unreproduced one is a bad trade; the trust boundary in README already says a caller who
    # can set these can also delete the gate job. The suite keeps two injection cases as
    # canaries: if a future git honours core.worktree here, they go red and this decision is
    # revisited with evidence.
    # receive-pack QUARANTINE is the one legitimate object-store redirection: during a
    # pre-receive hook the pushed objects exist ONLY in GIT_OBJECT_DIRECTORY, with the main
    # store reachable through GIT_ALTERNATE_OBJECT_DIRECTORIES. Clearing those two would
    # make the candidate commit unresolvable and reject every push. Keep them exactly when
    # git says we are in that hook (GIT_QUARANTINE_PATH), and only then.
    if [ -z "${GIT_QUARANTINE_PATH:-}" ]; then
      unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    fi
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_NAMESPACE \
          GIT_CEILING_DIRECTORIES
  fi
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $REPO"
  # Normalize --repo to the worktree ROOT. ls-tree pathspecs resolve relative to -C's cwd,
  # so a subdirectory --repo would read <subdir>/.control-plane.json — the ROOT
  # baseline/candidate config silently reads as absent (default-rules fallback) or a
  # same-named decoy config in the subdirectory gets read instead: both bypass the exit-3
  # gates. Normalizing also pins `git diff --name-only` output to root-relative paths (the
  # assumption every glob below relies on) even under `diff.relative=true` user config,
  # since cwd == root makes relative == root-relative. A BARE repo has no worktree root and
  # also has no subdirectory --repo to be confused by: every path it can produce is already
  # root-relative, so it skips normalization instead of dying (server-side hooks and mirror
  # CI classify from bare repos — refusing them would drop a working consumer class).
  if [ "$(git -C "$REPO" rev-parse --is-bare-repository 2>/dev/null)" != true ]; then
    # Sentinel capture: `$(...)` strips ALL trailing newlines, so a worktree root whose
    # directory name ends in one (legal on Unix) would silently collapse to the ADJACENT
    # path — and if that neighbour is also a repository, the run classifies it instead.
    # Append a sentinel, drop it, then drop exactly git's own one record newline.
    _top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null; printf X)" \
      || die "cannot resolve worktree root of --repo"
    _top="${_top%X}"; _top="${_top%$'\n'}"
    [ -n "$_top" ] && [ -d "$_top" ] || die "cannot resolve worktree root of --repo"
    REPO="$_top"
  fi
  # Pin BASE/HEAD to commit OIDs ONCE. Both are used three times below (merge-base, diff,
  # candidate-config lookup); a MUTABLE ref re-read at each call can move between them, so
  # the classified diff and the validated candidate config could come from different commits
  # — pointing a branch at a clean-config commit only for the duration of the config lookup
  # would let a malformed config in the diffed commit walk past the fail-closed gate.
  BASE="$(git -C "$REPO" rev-parse --verify --quiet "${BASE}^{commit}")" \
    || die "cannot resolve --base to a commit"
  HEAD_REF="$(git -C "$REPO" rev-parse --verify --quiet "${HEAD_REF}^{commit}")" \
    || die "cannot resolve --head to a commit"
  MB="$(git -C "$REPO" merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || die "cannot resolve merge-base of $BASE and $HEAD_REF"
  # --no-renames: a rename of a gated file must show as delete+add so a move-out cannot
  # smuggle a control-plane file below the classifier. -z: exact bytes, no C-quoting.
  git -C "$REPO" diff --no-renames --name-only -z "$MB" "$HEAD_REF" > "$FILES_TMP" 2>/dev/null || die "git diff failed"
  # TRUST ROOT: config from the merge-base tree (pre-candidate), never the working tree/head.
  # Distinguish ABSENT (defaults apply) from PRESENT-but-empty (malformed -> fail closed);
  # a non-blob entry (gitlink/tree/symlink) exits 3 inside the resolver — it must never
  # silently fall back to default rules (dropping the repo's extend/override globs).
  resolve_tree_config "$MB" "$CFG_TMP"
  if [ "$CFG_STATE" = blob ]; then
    CONFIG_PRESENT=1
  elif [ "$CFG_STATE" = nonblob ]; then
    # A non-blob BASELINE would otherwise be unrecoverable: every later MR — including the
    # one that repairs the entry — reads the same broken merge-base and exits 3, so CI can
    # only be unstuck out of band. Allow exactly the repair: if the candidate turns the
    # entry back into a regular blob (or removes it), classify with DEFAULT rules. That is
    # safe because `.control-plane.json` is hard-pinned, so the repairing diff is itself
    # CONTROL-PLANE and still needs review. A candidate that does NOT repair it fails closed.
    resolve_tree_config "$HEAD_REF" "$CAND_CFG_TMP"
    if [ "$CFG_STATE" = nonblob ]; then
      die "baseline config entry is not a regular blob and the candidate does not repair it; refusing to classify"
    fi
    printf 'control-plane: baseline config entry is not a regular blob; candidate repairs it — classifying with default rules\n' >&2
  fi
  # CANDIDATE GATE: the HEAD tree's config is NEVER used for classification (trust root
  # stays the merge-base), but a syntactically broken candidate config must not green-light
  # itself in via check mode — once merged it becomes the baseline, and the fail-closed
  # baseline parse then exit-3s EVERY later MR (including the fix MR, whose merge-base is
  # the broken config): pipeline bricked. Validate the candidate bytes whenever they differ
  # from the baseline (or no baseline config exists). A non-blob CANDIDATE entry fails closed
  # here (a foreign gitlink would otherwise read as absent and skip this gate).
  resolve_tree_config "$HEAD_REF" "$CAND_CFG_TMP"
  if [ "$CFG_STATE" = nonblob ]; then
    die "candidate config entry is not a regular blob; refusing to classify"
  fi
  CAND_CFG_STATE="$CFG_STATE"    # blob | absent — the repair hatches below need to tell them apart
  if [ "$CFG_STATE" = blob ]; then
    if [ "$CONFIG_PRESENT" = 0 ] || ! cmp -s "$CFG_TMP" "$CAND_CFG_TMP"; then
      CAND_CONFIG_PRESENT=1
    fi
  fi
fi

# NO empty-diff early return here: a malformed baseline config must fail closed (exit 3)
# even when base..head is empty, so config validation (in the python core) always runs.

# ----- classify (python3 core: config parse + ** glob matching) ---------------
# Top-level heredoc (NOT inside $(...)): macOS ships bash 3.2, whose parser chokes on
# heredocs nested in command substitution. The python core prints the report to stdout and
# signals the verdict via exit code: 0 = product-only, 2 = control-plane, 3 = config error.
CP_CONFIG_FILE="$CFG_TMP" CP_CONFIG_PRESENT="$CONFIG_PRESENT" \
CP_CAND_CONFIG_FILE="$CAND_CFG_TMP" CP_CAND_CONFIG_PRESENT="$CAND_CONFIG_PRESENT" \
CP_CAND_CONFIG_STATE="$CAND_CFG_STATE" \
CP_FILES_FILE="$FILES_TMP" python3 - "$JSON" <<'PY'
import json, os, re, sys

DEFAULT_GLOBS = [
    # CI / pipeline
    ".gitlab-ci.yml", ".gitlab/**", "ci/**", ".github/**",
    # build / verify recipes
    "Makefile", "GNUmakefile", "makefile", "**/Makefile", "**/GNUmakefile", "**/makefile",
    "*.mk", "**/*.mk", "Justfile", "justfile", "**/Justfile", "**/justfile",
    "Taskfile.yml", "Taskfile.yaml", "**/Taskfile.yml", "**/Taskfile.yaml",
    # hooks / plugins / agent-host manifests
    "hooks/**", ".githooks/**", ".husky/**",
    "plugin/**", "plugins/**", ".claude/**", ".claude-plugin/**", ".agents/**",
    ".codex-plugin/**", "opencode.json",
    # agent contracts / routing / ownership (CODEOWNERS: all platform-recognized locations;
    # .github/ and .gitlab/ variants are covered by the pinned dir globs)
    "AGENTS.md", "**/AGENTS.md", "CLAUDE.md", "**/CLAUDE.md",
    "CODEOWNERS", "docs/CODEOWNERS", "bootstrap.md", "agent-context/**",
    # gate engines + gate configs
    "tools/**", "scripts/**",
    ".owner-dispatch.json", ".control-plane.json", ".gitleaks.toml", ".gitleaksignore",
    ".pre-commit-config.yaml",
    # toolchain capture surface (how tools install/resolve/execute)
    "Dockerfile", "Dockerfile.*", "**/Dockerfile", "**/Dockerfile.*",
    ".devcontainer/**",
    "docker-compose*.yml", "docker-compose*.yaml", "compose*.yml", "compose*.yaml",
    "**/docker-compose*.yml", "**/docker-compose*.yaml", "**/compose*.yml", "**/compose*.yaml",
    ".tool-versions", "mise.toml", ".mise.toml",
    ".gitmodules",
    "go.mod", "go.sum", "**/go.mod", "**/go.sum",
    "package.json", "**/package.json", "package-lock.json", "**/package-lock.json",
    "npm-shrinkwrap.json", "**/npm-shrinkwrap.json",
    "pnpm-lock.yaml", "**/pnpm-lock.yaml", "pnpm-workspace.yaml", "**/pnpm-workspace.yaml",
    "yarn.lock", "**/yarn.lock",
    "bun.lockb", "**/bun.lockb", "bun.lock", "**/bun.lock",
    "pyproject.toml", "**/pyproject.toml", "setup.py", "**/setup.py",
    "setup.cfg", "**/setup.cfg", "requirements*.txt", "**/requirements*.txt",
    "Pipfile", "**/Pipfile", "Pipfile.lock", "**/Pipfile.lock",
    "poetry.lock", "**/poetry.lock", "uv.lock", "**/uv.lock",
    "Gemfile", "**/Gemfile", "Gemfile.lock", "**/Gemfile.lock",
    "Cargo.toml", "**/Cargo.toml", "Cargo.lock", "**/Cargo.lock",
    # test-runner plugin/config surface (decides WHAT the verify suite even runs)
    "conftest.py", "**/conftest.py",
    "pytest.ini", "**/pytest.ini", "tox.ini", "**/tox.ini",
    "noxfile.py", "**/noxfile.py",
    ".npmrc", "**/.npmrc", ".yarnrc", ".yarnrc.yml", "**/.yarnrc", "**/.yarnrc.yml",
    "jest.config.*", "**/jest.config.*", "vitest.config.*", "**/vitest.config.*",
    "playwright.config.*", "**/playwright.config.*",
]
# Never overridable: the enforcement chain itself. A repo may declassify e.g.
# scripts/product-cli/**, but never the machinery that decides what future diffs are allowed
# to do: this gate's config + engine, sibling gate engines/configs (owner-dispatch, the
# vendored agent-contract engine, secret-scan config — an overridden .gitleaksignore would let
# a candidate silently pin new fingerprint exemptions under an auto path), CI pipeline files,
# hooks, and the ROOT make recipe (the family's `make verify` entry point).
HARD_PINNED = [
    ".control-plane.json", "scripts/control-plane/**",
    ".owner-dispatch.json", "scripts/owner-dispatch/**",
    "scripts/verify-sandbox/**",
    "tools/check-agent-contract-coverage.sh",
    ".gitleaks.toml", ".gitleaksignore",
    ".gitlab-ci.yml", ".gitlab/**", ".github/**", "ci/**",
    "hooks/**", ".githooks/**", ".husky/**",
    "Makefile", "GNUmakefile", "makefile",
]

def glob_to_re(g: str) -> "re.Pattern":
    # A trailing '/**' also matches the bare directory entry itself: a gitlink/submodule
    # committed AT the directory path (git reports exactly 'ci', not 'ci/x') replaces the
    # whole gated tree and must classify like the tree, not slip through as product.
    tail = ""
    if g.endswith("/**"):
        g = g[:-3]
        tail = r"(?:/.*)?"
    out, i = [], 0
    while i < len(g):
        c = g[i]
        if c == "*":
            if g[i:i+3] == "**/":
                out.append(r"(?:.*/)?"); i += 3; continue
            if g[i:i+2] == "**":
                out.append(r".*"); i += 2; continue
            out.append(r"[^/]*"); i += 1; continue
        if c == "?":
            out.append(r"[^/]"); i += 1; continue
        out.append(re.escape(c)); i += 1
    # DOTALL + \Z: paths may legally contain newlines (delivered via the NUL stream);
    # '.' must span them and the anchor must be exact end-of-string, not line-end.
    return re.compile("^" + "".join(out) + tail + r"\Z", re.DOTALL)

def matches(path: str, globs) -> str:
    for g in globs:
        if glob_to_re(g).match(path):
            return g
    return ""

def parse_config(raw_cfg):
    """SHARED fail-closed schema check — the baseline and candidate gates MUST use this one
    implementation (a divergent copy would let one tree pass bytes the other rejects).
    Returns (error, cfg): error is "" only for clean UTF-8 JSON matching the config schema."""
    def _reject_constant(tok):   # NaN / Infinity / -Infinity are a Python extension, NOT JSON
        raise ValueError(f"non-JSON constant {tok}")

    def _reject_dupes(pairs):    # {"extend_globs": [...], "extend_globs": [...]} — last-wins
        seen = set()             # silently discards the reviewed value
        for k, _ in pairs:
            if k in seen:
                raise ValueError(f"duplicate key {k!r}")
            seen.add(k)
        return dict(pairs)

    try:
        cfg = json.loads(raw_cfg.decode("utf-8", "strict"),
                         parse_constant=_reject_constant, object_pairs_hook=_reject_dupes)
    except (UnicodeDecodeError, ValueError) as e:
        return f"not clean UTF-8 JSON ({e})", None
    if not isinstance(cfg, dict):
        return "must be a JSON object", None
    unknown = set(cfg) - {"extend_globs", "product_overrides", "_comment"}
    if unknown:
        return f"unknown config keys {sorted(unknown)}", None
    for field in ("extend_globs", "product_overrides"):
        v = cfg.get(field, [])
        if not isinstance(v, list) or any(not isinstance(x, str) or not x.strip() for x in v):
            return f"config field '{field}' must be a list of non-empty strings", None
    return "", cfg

extend, overrides = [], []
present = os.environ.get("CP_CONFIG_PRESENT", "0") == "1"
if present:
    # FAIL-CLOSED: a PRESENT config must parse from its EXACT bytes — empty/whitespace,
    # non-UTF-8, or NUL-carrying content is malformed, never a silent fall-through.
    with open(os.environ["CP_CONFIG_FILE"], "rb") as cfh:
        raw_cfg = cfh.read()
    err, cfg = parse_config(raw_cfg)
    if err:
        # SAME REPAIR HATCH the non-blob baseline gets, for the same reason: a malformed
        # baseline exit-3s every later MR *including the one that fixes it* (its merge-base
        # carries the same broken bytes), so CI can only be unstuck out of band. This gate
        # tightened over time — a config accepted when it was committed can become malformed
        # under a later rule (NaN/Infinity, duplicate keys) — which turns a historical repo
        # into a bricked one. Allow exactly the repair: if the candidate parses clean,
        # classify with DEFAULT rules. Safe because `.control-plane.json` is hard-pinned, so
        # the repairing diff is itself CONTROL-PLANE and still needs review.
        # "Repair" is either a clean rewrite OR removing the file: absent is a fully
        # supported state (defaults apply), and the sibling non-blob hatch already accepts
        # it — accepting it in only one of the two hatches leaves the same permanent brick
        # this hatch exists to remove.
        cand_ok = os.environ.get("CP_CAND_CONFIG_STATE", "") == "absent"
        if not cand_ok and os.environ.get("CP_CAND_CONFIG_PRESENT", "0") == "1":
            with open(os.environ["CP_CAND_CONFIG_FILE"], "rb") as cfh2:
                cand_ok = parse_config(cfh2.read())[0] == ""
        if not cand_ok:
            sys.stderr.write(f"control-plane: malformed .control-plane.json — {err}; refusing to classify\n")
            sys.exit(3)
        sys.stderr.write(f"control-plane: baseline .control-plane.json is malformed ({err}); "
                         "candidate repairs it — classifying with default rules\n")
        cfg = {}
    extend = cfg.get("extend_globs", [])
    overrides = cfg.get("product_overrides", [])

# CANDIDATE GATE (see the extraction comment in the shell layer): syntax-only, fail-closed;
# the candidate config is validated but NEVER feeds extend/overrides — trust root unchanged.
if os.environ.get("CP_CAND_CONFIG_PRESENT", "0") == "1":
    with open(os.environ["CP_CAND_CONFIG_FILE"], "rb") as cfh:
        raw_cand = cfh.read()
    err, _ = parse_config(raw_cand)
    if err:
        sys.stderr.write(f"control-plane: candidate config malformed — {err} (.control-plane.json in the HEAD tree); refusing to classify\n")
        sys.exit(3)

json_mode = sys.argv[1] == "1"
cp, prod = [], []
with open(os.environ["CP_FILES_FILE"], "rb") as fh:
    raw_paths = fh.read().split(b"\0")
for raw_path in raw_paths:
    path = raw_path.decode("utf-8", "surrogateescape").strip().lstrip("/")
    if not path:
        continue
    # Precedence: hard-pinned > extend_globs > product_overrides > defaults.
    # product_overrides declassifies DEFAULT matches only — a path the repo explicitly
    # listed in extend_globs stays control-plane even under a broad override.
    pinned = matches(path, HARD_PINNED)
    if pinned:
        cp.append((path, "pinned:" + pinned)); continue
    extended = matches(path, extend)
    if extended:
        cp.append((path, "extend:" + extended)); continue
    default_hit = matches(path, DEFAULT_GLOBS)
    if default_hit:
        overridden = matches(path, overrides)
        if overridden:
            prod.append((path, f"override:{overridden}"))
        else:
            cp.append((path, default_hit))
        continue
    prod.append((path, ""))

if not cp and not prod:
    if json_mode:
        print('{"control_plane":[],"product":[],"verdict":"clean"}')
    else:
        print("control-plane: no changed files (clean)")
    sys.stdout.flush()
    sys.exit(0)

if json_mode:
    print(json.dumps({
        "control_plane": [{"path": p, "rule": r} for p, r in cp],
        "product": [p for p, _ in prod],
        "verdict": "control-plane" if cp else "product-only",
    }))
else:
    for p, r in cp:
        print(f"  CONTROL-PLANE  {p}   ({r})")
    for p, r in prod:
        print(f"  product        {p}" + (f"   ({r})" if r else ""))
    if cp:
        print("verdict: CONTROL-PLANE (" + str(len(cp)) + " file(s)) — explicit-authorization review required; never auto-merge")
    else:
        print("verdict: product-only")
sys.stdout.flush()
sys.exit(2 if cp else 0)
PY
RC=$?
case "$RC" in
  0) exit 0 ;;
  2) if [ "$ENFORCE" = 1 ]; then exit 2; else exit 0; fi ;;
  *) exit 3 ;;   # config/parse errors and anything unexpected: fail closed
esac
