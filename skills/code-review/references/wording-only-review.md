# Proof-bound wording-only single review

The wording-only exception to `staged-review-contract.md`: when one review may
stand in for the review-plus-challenge pair, what the controller re-derives
before it will say so, and how to produce the packet and proof it accepts.

## The exception and its depth limits

The wording-only exception is one untracked `review` with
`challenge_budget=0`; it is not a chain, challenge, or `complete` checkpoint.
Supply `--wording-only-proof-file` to bind the exception to the exact packet.
Without that proof, an explore/build budget-zero review remains an ordinary
single review and cannot be recorded as the wording-only exception;
release/high-risk budget zero fails before inference.

At release depth, including depth raised by a high-risk tag, only a
controller-proved `markdown-punctuation-only` check may use this exception.
`markdown-token-replacement` remains available for explore/build budget-zero
review, but it cannot waive the release/high-risk challenge: byte-exact token
replacement does not prove that the old and new tokens have the same meaning.

## The proof

The proof is a single-link regular UTF-8 JSON file of at most 16,000 bytes:

```json
{"schema_version":1,"candidate_sha256":"<packet-sha256>","check":{"kind":"markdown-punctuation-only"}}
```

The other fixed check is
`markdown-token-replacement`, whose `check` also contains `old_token`,
`new_token`, and integer `expected_count` (1..100). The controller never trusts
a caller-supplied pass result. It reparses the frozen packet and derives the
status, files, changed-line count, replacement count, and scope SHA-256.

## The accepted packet

The accepted packet is deliberately narrow: a canonical full-context unified
Git diff, LF-terminated, at most 200,000 bytes, changing existing regular
Markdown files inside exactly one existing non-linked skill package. Every
file's first hunk starts at line 1 so frontmatter is inspectable. Adds,
deletes, renames, multi-skill changes, frontmatter or `description` edits,
non-regular Git modes, custom/compact packets, extra context outside the diff,
and files without a final newline fail closed. `markdown-punctuation-only`
accepts only one-for-one plain-prose line replacements whose non-punctuation
characters remain identical; numeric tokens must additionally survive
byte-for-byte (deleting the dot in `5.5` is a threshold change, not
punctuation), and a question mark may not be added or removed (a statement
turned into a question is a meaning change). Lines must start at column zero
and contain prose; line adds/deletes, Markdown headings, lists, block quotes,
links, tables, inline code, fenced or indented code, and raw HTML `pre`/`code`
containers fail closed. `markdown-token-replacement` requires every changed
line pair to differ only by the named whole-token replacement, with the exact
total count, and rejects packets whose changed lines touch a Markdown or HTML
code container.

## Producing the packet and proof

This recipe produces the exact packet and proof without a second parser or a
pretend verifier command. Set `WORDING_KIND=markdown-punctuation-only`, or set
`WORDING_KIND=markdown-token-replacement` plus `WORDING_OLD`, `WORDING_NEW`, and
`WORDING_COUNT`:

```bash
: "${CODE_REVIEW_SKILL_DIR:?set the installed code-review skill directory}"
: "${REPO_ROOT:?set the absolute repository root}"
: "${REVIEW_BASE:?set the exact base ref}"
: "${SKILL_NAME:?set the one existing skill package name}"
: "${REVIEW_STAGE:?set explore, build, or release}"
: "${IMPLEMENTER_FAMILY:?set the implementer model family}"
: "${REVIEW_PLAN_FILE:?set the absolute review-plan JSON path}"
: "${REVIEW_EVIDENCE_DIR:?set an existing durable private evidence directory}"
: "${WORDING_KIND:?set one supported wording-only check kind}"

umask 077
WORDING_RUN_DIR="$(mktemp -d "$REVIEW_EVIDENCE_DIR/wording-review.XXXXXX")" || exit 1
WORDING_DIFF="$WORDING_RUN_DIR/candidate.diff"
WORDING_PROOF="$WORDING_RUN_DIR/proof.json"
WORDING_RESULT="$WORDING_RUN_DIR/review.json"

git -C "$REPO_ROOT" diff --no-color --no-ext-diff --no-textconv --full-index \
  --src-prefix=a/ --dst-prefix=b/ --unified=1000000 \
  "$REVIEW_BASE" -- "skills/$SKILL_NAME" >"$WORDING_DIFF" || exit 1

python3 - "$WORDING_DIFF" "$WORDING_PROOF" "$WORDING_KIND" \
  "${WORDING_OLD:-}" "${WORDING_NEW:-}" "${WORDING_COUNT:-0}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

diff_path, proof_path = map(Path, sys.argv[1:3])
kind, old, new, count = sys.argv[3:]
check = {"kind": kind}
if kind == "markdown-token-replacement":
    check.update(old_token=old, new_token=new, expected_count=int(count))
elif kind != "markdown-punctuation-only":
    raise SystemExit("unsupported WORDING_KIND")
payload = {
    "schema_version": 1,
    "candidate_sha256": hashlib.sha256(diff_path.read_bytes()).hexdigest(),
    "check": check,
}
proof_path.write_text(
    json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY

WORDING_RISK_ARGS=()
for tag in ${REVIEW_RISK_TAGS:-}; do WORDING_RISK_ARGS+=(--risk-tag "$tag"); done
if ! bash "$CODE_REVIEW_SKILL_DIR/scripts/review_gate.sh" \
  --mode review --stage "$REVIEW_STAGE" --challenge-budget 0 \
  --cwd "$REPO_ROOT" --diff-file "$WORDING_DIFF" \
  --review-plan-file "$REVIEW_PLAN_FILE" \
  --wording-only-proof-file "$WORDING_PROOF" \
  ${WORDING_RISK_ARGS[@]+"${WORDING_RISK_ARGS[@]}"} \
  --implementer-family "$IMPLEMENTER_FAMILY" >"$WORDING_RESULT"; then
  cat "$WORDING_RESULT" >&2
  exit 1
fi
cat "$WORDING_RESULT"
```

## Validating the result

A valid result carries `wording_only_proof_sha256`, controller-derived
`wording_only_scope.status=passed`, and a reviewed
`wording_only_boundary` concern. That concern independently confirms the edit
changes no trigger, scope, routing, validation, acceptance, rule, threshold,
boundary, frontmatter, description, or other meaning. If it is missing,
inconclusive, or reports a possible semantic change, the wording-only exception
does not apply: use the normal challenge and behavioral-evidence path. Any
candidate edit regenerates the packet and proof and requires a new review.
Keep the diff, proof, and result together; a digest whose source artifact was
deleted is not independently auditable evidence.
