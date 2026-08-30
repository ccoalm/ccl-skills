#!/usr/bin/env bash
# Killing-mutation contract for the obligation ledger generator/auditor.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TOOL="$SCRIPT_DIR/obligation-ledger.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/obligation-ledger-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/fixture"
mkdir -p "$FIXTURE/skills/source" "$FIXTURE/skills/destination" \
  "$FIXTURE/skills/extra" "$FIXTURE/skills/matrix" \
  "$FIXTURE/skills/meta/references" "$FIXTURE/specs"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name "Obligation Fixture"
git -C "$FIXTURE" config user.email "fixture@example.invalid"

cat >"$FIXTURE/skills/source/SKILL.md" <<'EOF'
# Source
## Rules
- The owner MUST retain the release token before final approval.
- Every reviewer MUST reject a build with a missing audit record.
- Every client MUST preserve the table-bound release record.
- Every maintainer MUST preserve the immutable release record.
- The release record MUST preserve these clauses:owner context must remain visible, every client must expose recovery, and final approval must block unsafe retry.
- The final skill MUST stay generic.
- Use only provenance sources.
- Shared i18n packages remain in scope.
- For mobile/H5, safe-area behavior MUST be covered.
- A component library is only rendering vocabulary, not design judgment.
- User-facing copy uses plain language.
- Supported actions include post, reply, block, and mute.
- Remove unused first-screen dead area.
- Do not use Error 500 as primary copy.
- Sequence the message as (1) what happened, (2) why, and (3) next action.
- The request MUST finish within 500 ms.
- The release MUST remain `pending` until verification.
- The guide lives at `references/pending-state.md`.
- Final approval MUST block unsafe retry.
- Loading MUST keep the geometry of final content.
- The user MUST confirm the destructive action.
- The latest design MUST remain accessible.
- The final artifact MUST retain its audit trail.
- The failure rate MUST stay below 5%.
- The retry rate MUST stay under 5%.
EOF
cat >"$FIXTURE/skills/destination/SKILL.md" <<'EOF'
# Destination
## Current
- Existing stable contract remains unchanged for the fixture.
EOF
cat >"$FIXTURE/skills/extra/SKILL.md" <<'EOF'
# Extra
## Stable
- Every client MUST preserve the unchanged comparison-domain contract.
EOF
cat >"$FIXTURE/skills/matrix/SKILL.md" <<'EOF'
# Matrix
## Contract table
| Rule \| identity | Boundary `A|B` |
| --- | --- |
| Every owner MUST keep the stable table audit. | Stable boundary. |
EOF
cat >"$FIXTURE/skills/meta/references/source-register.md" <<'EOF'
# Source register
## Provenance only
- External references are evidence inputs and are never the sole normative carrier.
EOF
git -C "$FIXTURE" add skills
git -C "$FIXTURE" commit -qm base
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"

cat >"$FIXTURE/skills/source/SKILL.md" <<'EOF'
# Source
## Rules
- The release protocol now delegates token retention to the delivery owner.
- Review policy now delegates missing-audit rejection to the gate owner.
- The release protocol now delegates the table-bound record to a delivery client.
- Genericity now follows the reusable skill contract.
- Provenance selection now follows the source boundary.
- Localization package scope now follows the rendered-content boundary.
- Mobile-web safe-area coverage now follows the adaptation matrix.
- Component-library authority now follows the design-judgment boundary.
- Visible interface copy now follows the content standard.
- Moderation actions now follow the interaction vocabulary.
- Above-the-fold density now follows the visual-craft rule.
- Raw server-status copy now follows the error-copy rule.
- Error-message order now follows the recovery-copy pattern.
- Request timing now follows the runtime threshold.
- Release status now follows verification state.
- The pending-state guide path now follows the documentation index.
- Unsafe retry now follows the approval gate.
- Loading geometry now follows the terminal-content layout rule.
- Destructive confirmation now follows the acting-user contract.
- Current-design accessibility now follows the design baseline.
- Artifact audit retention now follows the delivery baseline.
- Failure-rate direction now follows the quality threshold.
- Retry-rate direction now follows the reliability threshold.
EOF
cat >"$FIXTURE/skills/destination/SKILL.md" <<'EOF'
# Destination
## Current
- Existing stable contract remains unchanged for the fixture.
## Delivery contract
- Legacy first-screen note remains in destination.
- The delivery owner MUST retain the release token before final approval.
- Every gate reviewer MUST reject a build with a missing audit record.
- Every maintainer MUST preserve the immutable release record.
- The release record MUST preserve these clauses:owner context must remain visible.
- Every client must expose recovery.
- Final approval must block unsafe retry.
- Owner context MUST remain visible.
- The resulting skill MUST stay generic.
- None of the non-provenance sources may be used.
- Shared localization packages remain in scope.
- For mobile web, safe-area behavior MUST be covered.
- A component library is rendering vocabulary, not a substitute for design judgment.
- Visible interface copy uses plain language.
- Supported actions include posting, replying, blocking, and muting.
- Remove unused above-the-fold dead area.
- Do not use raw server status as primary copy.
- State what happened, why it happened, and the next action.
- The runtime request MUST complete within 500 ms.
- The release MUST stay `pending` until verification.
- Use the guide at `references/pending-state.md`.
- Final approval MUST block unsafe retry.
- Loading MUST preserve the geometry of final content.
- The user MUST confirm the irreversible action.
- The latest design MUST remain accessible.
- The final artifact MUST retain its audit trail.
- The failure rate MUST stay below 5%.
- The retry rate MUST stay under 5%.
EOF
# Same sentence under a different path/chain is legal: the carrier identity is
# the manifest's exact (path, chain, text) tuple, not a corpus-wide text ban.
cat >"$FIXTURE/skills/extra/SKILL.md" <<'EOF'
# Extra
## Stable
- Every client MUST preserve the unchanged comparison-domain contract.
- The delivery owner MUST retain the release token before final approval.
EOF
cat >"$FIXTURE/skills/matrix/SKILL.md" <<'EOF'
# Matrix
## Contract table
| Rule \| identity | Boundary `A|B` |
| --- | --- |
| Every owner MUST keep the stable table audit. | Stable boundary. |
| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |
EOF
cat >"$FIXTURE/specs/mapping.jsonl" <<'EOF'
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":1,"reason":"left-a-rewritten-line","before_text":"The owner MUST retain the release token before final approval.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"strengthened","carrier_path":"skills/destination/SKILL.md","carrier_text":"The delivery owner MUST retain the release token before final approval.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"recency","before":["before","final"],"after":["before","final"],"same_immediate_host":true},{"kind":"actor","before":["owner"],"after":["owner"],"same_immediate_host":true}],"review_note":"Old Rules host loses token retention; new Delivery contract host gains a stricter named delivery owner."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":2,"reason":"left-a-rewritten-line","before_text":"Every reviewer MUST reject a build with a missing audit record.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"strengthened","carrier_path":"skills/destination/SKILL.md","carrier_text":"Every gate reviewer MUST reject a build with a missing audit record.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"scope","before":["Every"],"after":["Every"],"same_immediate_host":true},{"kind":"actor","before":["reviewer"],"after":["reviewer"],"same_immediate_host":true},{"kind":"consequence","before":["reject"],"after":["reject"],"same_immediate_host":true}],"review_note":"Old Rules host loses audit rejection; new Delivery contract host gains a gate-specific reviewer."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":3,"reason":"left-a-rewritten-line","before_text":"Every client MUST preserve the table-bound release record.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"strengthened","carrier_path":"skills/matrix/SKILL.md","carrier_text":"Every delivery client MUST preserve the table-bound release record.","carrier_chain":["Matrix","Contract table","table:Rule \\| identity | Boundary `A|B`","column:Rule \\| identity"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"scope","before":["Every"],"after":["Every"],"same_immediate_host":true},{"kind":"actor","before":["client"],"after":["client"],"same_immediate_host":true}],"review_note":"Old Rules host loses the table-bound record; new Contract table Rule column gains the delivery-client contract."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":4,"reason":"left-a-rewritten-line","before_text":"Every maintainer MUST preserve the immutable release record.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Every maintainer MUST preserve the immutable release record.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The exact obligation moves verbatim from old Rules to the Delivery contract host."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":5,"reason":"left-a-rewritten-line","before_text":"The release record MUST preserve these clauses:owner context must remain visible, every client must expose recovery, and final approval must block unsafe retry.","before_chain":["Source","Rules"],"disposition":"subsumed","effect":"preserved","carrier_path":null,"carrier_text":null,"carrier_chain":null,"carrier_bundle":[{"carrier_path":"skills/destination/SKILL.md","carrier_text":"The release record MUST preserve these clauses:owner context must remain visible.","carrier_chain":["Destination","Delivery contract"],"covers":["c1"],"clause_qualifiers":[{"clause_id":"c1","qualifiers":[{"kind":"modality","before":["MUST","must"],"after":["MUST","must"],"same_immediate_host":true},{"kind":"actor","before":["owner"],"after":["owner"],"same_immediate_host":true}]}]},{"carrier_path":"skills/destination/SKILL.md","carrier_text":"Every client must expose recovery.","carrier_chain":["Destination","Delivery contract"],"covers":["c2"],"clause_qualifiers":[{"clause_id":"c2","qualifiers":[{"kind":"modality","before":["must"],"after":["must"],"same_immediate_host":true},{"kind":"scope","before":["every"],"after":["Every"],"same_immediate_host":true},{"kind":"actor","before":["client"],"after":["client"],"same_immediate_host":true}]}]},{"carrier_path":"skills/destination/SKILL.md","carrier_text":"Final approval must block unsafe retry.","carrier_chain":["Destination","Delivery contract"],"covers":["c3"],"clause_qualifiers":[{"clause_id":"c3","qualifiers":[{"kind":"modality","before":["must"],"after":["must"],"same_immediate_host":true},{"kind":"recency","before":["final"],"after":["Final"],"same_immediate_host":true},{"kind":"consequence","before":["block"],"after":["block"],"same_immediate_host":true}]}]}],"compound_clauses":[{"id":"c1","text":"The release record MUST preserve these clauses: owner context must remain visible"},{"id":"c2","text":"every client must expose recovery"},{"id":"c3","text":"final approval must block unsafe retry."}],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST","must"],"after":["MUST","must"],"same_immediate_host":true},{"kind":"recency","before":["final"],"after":["Final"],"same_immediate_host":true},{"kind":"scope","before":["every"],"after":["Every"],"same_immediate_host":true},{"kind":"actor","before":["owner","client"],"after":["owner","client"],"same_immediate_host":true},{"kind":"consequence","before":["block"],"after":["block"],"same_immediate_host":true}],"review_note":"Manual clause coverage: c1 preserves owner context, c2 preserves client recovery, and c3 preserves the final unsafe-retry block."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":6,"reason":"left-a-rewritten-line","before_text":"The final skill MUST stay generic.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"strengthened","carrier_path":"skills/destination/SKILL.md","carrier_text":"The resulting skill MUST stay generic.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true}],"qualifier_relations":[{"kind":"recency","term":"final","occurrence":1,"source_excerpt":"final skill","resolution":"carrier-applies-unconditionally","same_immediate_host":true}],"review_note":"Manual review recorded for the exact final-to-resulting rewrite."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":7,"reason":"left-a-rewritten-line","before_text":"Use only provenance sources.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"None of the non-provenance sources may be used.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"scope","before":["only"],"after":["None"],"same_immediate_host":true}],"review_note":"The exclusive provenance-source boundary is preserved by the negative universal form."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":8,"reason":"left-a-rewritten-line","before_text":"Shared i18n packages remain in scope.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Shared localization packages remain in scope.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"The localization-package scope is rephrased without treating identifier digits as a threshold."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":9,"reason":"left-a-rewritten-line","before_text":"For mobile/H5, safe-area behavior MUST be covered.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"For mobile web, safe-area behavior MUST be covered.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true}],"review_note":"The mobile-web safe-area obligation is preserved without treating the H5 identifier as a threshold."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":10,"reason":"left-a-rewritten-line","before_text":"A component library is only rendering vocabulary, not design judgment.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"A component library is rendering vocabulary, not a substitute for design judgment.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"scope","before":["only"],"after":["not a substitute"],"same_immediate_host":true}],"review_note":"The exclusive rendering-vocabulary boundary is preserved by the explicit not-a-substitute expression."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":11,"reason":"left-a-rewritten-line","before_text":"User-facing copy uses plain language.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Visible interface copy uses plain language.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"User-facing is an audience modifier here, not an acting-role qualifier."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":12,"reason":"left-a-rewritten-line","before_text":"Supported actions include post, reply, block, and mute.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Supported actions include posting, replying, blocking, and muting.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"Block is an enumerated product action noun here, not a completion consequence."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":13,"reason":"left-a-rewritten-line","before_text":"Remove unused first-screen dead area.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Remove unused above-the-fold dead area.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"First-screen is a visual-region compound here, not a temporal ordering qualifier."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":14,"reason":"left-a-rewritten-line","before_text":"Do not use Error 500 as primary copy.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Do not use raw server status as primary copy.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["Do not"],"after":["Do not"],"same_immediate_host":true}],"review_note":"The error-copy prohibition is preserved without treating a status code as a threshold."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":15,"reason":"left-a-rewritten-line","before_text":"Sequence the message as (1) what happened, (2) why, and (3) next action.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"State what happened, why it happened, and the next action.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"Parenthesized list ordinals are structural markers, not numeric thresholds."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":16,"reason":"left-a-rewritten-line","before_text":"The request MUST finish within 500 ms.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The runtime request MUST complete within 500 ms.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"threshold","before":["within","500 ms"],"after":["within","500 ms"],"same_immediate_host":true}],"review_note":"The real bounded runtime threshold is preserved with its unit."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":17,"reason":"left-a-rewritten-line","before_text":"The release MUST remain `pending` until verification.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The release MUST stay `pending` until verification.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"consequence","before":["pending"],"after":["pending"],"same_immediate_host":true}],"review_note":"The true pending terminal status remains explicit."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":18,"reason":"left-a-rewritten-line","before_text":"The guide lives at `references/pending-state.md`.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Use the guide at `references/pending-state.md`.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[],"review_note":"Pending inside a path identifier is not a terminal-status qualifier."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":19,"reason":"left-a-rewritten-line","before_text":"Final approval MUST block unsafe retry.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Final approval MUST block unsafe retry.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The true final approval blocker is preserved verbatim under the delivery contract."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":20,"reason":"left-a-rewritten-line","before_text":"Loading MUST keep the geometry of final content.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"Loading MUST preserve the geometry of final content.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"recency","before":["final"],"after":["final"],"same_immediate_host":true}],"review_note":"Final content is a true terminal-state comparison and remains explicit."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":21,"reason":"left-a-rewritten-line","before_text":"The user MUST confirm the destructive action.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The user MUST confirm the irreversible action.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":true,"qualifiers":[{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":true},{"kind":"actor","before":["user"],"after":["user"],"same_immediate_host":true}],"review_note":"The acting user and mandatory confirmation remain explicit."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":22,"reason":"left-a-rewritten-line","before_text":"The latest design MUST remain accessible.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The latest design MUST remain accessible.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The latest-design recency constraint moves verbatim."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":23,"reason":"left-a-rewritten-line","before_text":"The final artifact MUST retain its audit trail.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The final artifact MUST retain its audit trail.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The final-artifact terminal constraint moves verbatim."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":24,"reason":"left-a-rewritten-line","before_text":"The failure rate MUST stay below 5%.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The failure rate MUST stay below 5%.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The lower failure-rate bound moves verbatim."}
{"schema_version":2,"source_path":"skills/source/SKILL.md","source_ordinal":25,"reason":"left-a-rewritten-line","before_text":"The retry rate MUST stay under 5%.","before_chain":["Source","Rules"],"disposition":"rehosted","effect":"preserved","carrier_path":"skills/destination/SKILL.md","carrier_text":"The retry rate MUST stay under 5%.","carrier_chain":["Destination","Delivery contract"],"manual_reviewed":false,"qualifiers":[],"review_note":"The lower retry-rate bound moves verbatim."}
EOF

# Schema 3 makes semantic review evidence explicit. Rephrased scalar carriers
# need one reviewed decision; each bundle clause needs its own reviewed decision.
python3 - "$FIXTURE/specs/mapping.jsonl" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
for row in rows:
    row["schema_version"] = 3
    row["semantic_review"] = None
    row["semantic_rationale"] = None
    bundle = row.get("carrier_bundle")
    if bundle:
        for member in bundle:
            for proof in member["clause_qualifiers"]:
                proof["semantic_review"] = "reviewed"
                proof["semantic_rationale"] = (
                    f"Reviewed clause {proof['clause_id']} against its one assigned carrier."
                )
    elif row.get("carrier_text") is not None and row["before_text"] != row["carrier_text"]:
        row["semantic_review"] = "reviewed"
        row["semantic_rationale"] = "Reviewed the non-verbatim scalar carrier against the source obligation."

def digest(path, chain, text):
    payload = json.dumps(
        [path, chain, text], ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def member(text, bridges):
    path = "skills/destination/SKILL.md"
    chain = ["Destination", "Delivery contract"]
    return {
        "carrier_path": path,
        "carrier_text": text,
        "carrier_chain": chain,
        "carrier_sha256": digest(path, chain, text),
        "bridge_terms": bridges,
    }

def partition_row(row, spans):
    cursor = 0
    parts = []
    for index, spec in enumerate(spans, 1):
        text = spec[1]
        start = cursor
        end = start + len(text)
        cursor = end
        if spec[0] == "retired":
            parts.append({
                "id": f"p{index}", "status": "retired",
                "source_start": start, "source_end": end, "source_text": text,
                "authority": "Independent fixture review of the obsolete source-specific literal.",
                "scope": "Only this exact retired span in this source obligation.",
                "reason": "The fixed source-specific literal is invalid under the current generic contract.",
                "semantic_review": "reviewed",
                "semantic_rationale": "Reviewed this exact span as retired while adjacent behavior survives.",
            })
        else:
            carrier_text, bridges, qualifiers = spec[2], spec[3], spec[4]
            parts.append({
                "id": f"p{index}", "status": "survives",
                "source_start": start, "source_end": end, "source_text": text,
                "effect": "preserved", "carriers": [member(carrier_text, bridges)],
                "qualifiers": qualifiers,
                "qualifier_resolutions": [],
                "semantic_review": "reviewed",
                "semantic_rationale": "Reviewed this exact live span against the exact current carrier.",
            })
    assert cursor == len(row["before_text"]), (cursor, row["before_text"])
    return {
        "schema_version": 4,
        "source_path": row["source_path"],
        "source_ordinal": row["source_ordinal"],
        "reason": row["reason"],
        "before_text": row["before_text"],
        "before_chain": row["before_chain"],
        "disposition": "partial-retirement",
        "effect": "strengthened",
        "parts": parts,
        "manual_reviewed": True,
        "semantic_review": "reviewed",
        "semantic_rationale": "Reviewed the complete exact-span partition and its live/dead boundary.",
        "review_note": "Schema4 fixture partition with exact carriers and authority-scoped retirement.",
    }

rows[12] = partition_row(rows[12], [
    ("survives", "Remove unused ", "Remove unused above-the-fold dead area.", ["Remove", "unused"], []),
    ("retired", "first-screen"),
    ("survives", " dead area.", "Remove unused above-the-fold dead area.", ["dead area"], []),
])
rows[13] = partition_row(rows[13], [
    (
        "survives", "Do not use ", "Do not use raw server status as primary copy.",
        ["Do not", "use"],
        [{"kind":"modality","before":["Do not"],"after":["Do not"],"same_immediate_host":True}],
    ),
    ("retired", "Error 500"),
    (
        "survives", " as primary copy.", "Do not use raw server status as primary copy.",
        ["primary copy"], [],
    ),
])
path.write_text(
    "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows),
    encoding="utf-8",
)
PY

python3 - "$TOOL" <<'PY'
import importlib.util
import sys
from pathlib import Path

tool = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("obligation_ledger_under_test", tool)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

cases = [
    ("only-is-exclusive-scope", "Use only provenance sources.", {"scope": ["only"]}),
    ("only-chinese-is-exclusive-scope", "该来源仅用于证据。", {"scope": ["仅"]}),
    ("not-only-is-additive", "This is not only a layout concern.", {}),
    ("not-markdown-only-is-additive", "This is not **only** a layout concern.", {}),
    ("chinese-not-only-is-additive", "这不仅是布局问题。", {}),
    ("chinese-not-only-emphatic-is-additive", "这不仅仅是布局问题。", {}),
    ("exclusive-cross-expression", "A library is not a substitute for design judgment.", {"scope": ["not a substitute"]}),
    ("i18n-is-identifier", "Shared i18n packages remain in scope.", {}),
    ("h5-is-identifier", "For mobile/H5, safe-area behavior MUST be covered.", {"modality": ["MUST"]}),
    ("user-facing-is-modifier", "User-facing copy uses plain language.", {}),
    ("user-copy-is-modifier", "User copy uses plain language.", {}),
    ("user-needs-is-noun-modifier", "User needs guide prioritization.", {}),
    ("users-possessive-needs-is-noun", "Users' needs guide prioritization.", {}),
    ("user-experience-research-is-modifier", "User experience research informs the design.", {}),
    ("user-research-is-noun-modifier", "User research informs the design.", {}),
    ("chinese-user-recipient", "让用户知道下一步。", {}),
    ("chinese-user-needs-is-noun", "用户需求影响设计方向。", {}),
    ("chinese-possessive-user-needs-is-noun", "用户的需求影响设计方向。", {}),
    ("real-user-actor", "The user MUST confirm.", {"modality": ["MUST"], "actor": ["user"]}),
    ("real-users-actor", "Users MUST confirm.", {"modality": ["MUST"], "actor": ["Users"]}),
    ("agent-contract-is-modifier", "Inspect agent-contract files before use.", {"recency": ["before"]}),
    ("reviewer-check-is-modifier", "Reviewer checks remain enumerable.", {}),
    ("real-user-needs-to-actor", "The user needs to confirm.", {"actor": ["user"]}),
    ("real-chinese-user-actor", "用户必须确认。", {"modality": ["必须"], "actor": ["用户"]}),
    ("real-chinese-user-actor-after-let", "让用户确认操作。", {"actor": ["用户"]}),
    ("chinese-test-is-verb", "必须测试错误状态。", {"modality": ["必须"]}),
    ("chinese-tester-is-actor", "测试人员必须确认结果。", {"modality": ["必须"], "actor": ["测试人员"]}),
    ("block-is-action-noun", "Actions include post, reply, block, and mute.", {}),
    ("code-block-is-noun", "Render the sample in a code block.", {}),
    ("code-blocks-is-noun", "Render samples in code blocks.", {}),
    ("block-is-consequence", "The gate MUST block completion.", {"modality": ["MUST"], "consequence": ["block"]}),
    ("blocks-is-consequence", "The gate blocks completion.", {"consequence": ["blocks"]}),
    ("blocked-is-consequence", "The release is blocked.", {"consequence": ["blocked"]}),
    ("reviewer-block-is-consequence", "A reviewer can directly block the change.", {"actor": ["reviewer"], "consequence": ["block"]}),
    ("pass-fail-is-label", "Do not use a pass/fail summary.", {"modality": ["Do not"]}),
    ("fail-is-consequence", "The gate MUST fail closed.", {"modality": ["MUST"], "consequence": ["fail"]}),
    ("failed-is-consequence", "The verification failed.", {"consequence": ["failed"]}),
    ("red-text-is-color", "Use red text for the error.", {}),
    ("red-colored-border-is-color", "Use a red-colored border for the error.", {}),
    ("red-first-is-baseline-label", "Record a RED-first focused assertion.", {"recency": ["first"]}),
    ("red-baseline-is-label", "The RED baseline names its provenance.", {}),
    ("red-gate-is-consequence", "The gate is red.", {"consequence": ["red"]}),
    ("first-screen-is-region", "Remove unused first-screen dead area.", {}),
    ("final-skill-remains-reviewed-recency", "The final skill MUST stay generic.", {"modality": ["MUST"], "recency": ["final"]}),
    ("final-content-remains-terminal", "Keep the geometry of final content.", {"recency": ["final"]}),
    ("error-status-is-not-threshold", "Do not use Error 500 as primary copy.", {"modality": ["Do not"]}),
    ("http-status-is-not-threshold", "HTTP 500 is not primary copy.", {}),
    ("numbered-list-is-not-threshold", "Use (1) what happened, (2) why, and (3) next action.", {}),
    ("identifier-path-is-not-terminal", "Read `references/pending-state.md`.", {}),
    ("pending-is-terminal", "The release MUST remain `pending`.", {"modality": ["MUST"], "consequence": ["pending"]}),
    ("within-unit-is-threshold", "Finish within 500 ms.", {"threshold": ["within", "500 ms"]}),
    ("within-compact-unit-is-threshold", "Finish within 500ms.", {"threshold": ["within", "500ms"]}),
    ("within-word-unit-is-threshold", "Finish within five seconds.", {"threshold": ["within"]}),
    ("within-product-is-not-threshold", "Keep tokens aligned within one product.", {}),
    ("percent-is-threshold", "Keep failures below 5%.", {"threshold": ["below", "5%"]}),
    ("under-percent-is-threshold", "Keep failures under 5%.", {"threshold": ["under", "5%"]}),
    ("above-percent-is-threshold", "Keep success above 5%.", {"threshold": ["above", "5%"]}),
    ("over-percent-is-threshold", "Keep success over 5%.", {"threshold": ["over", "5%"]}),
    ("under-review-is-not-threshold", "The proposal is under review.", {}),
    ("over-time-is-not-threshold", "Improve the design over time.", {}),
    ("per-the-is-cross-reference", "Handle it per the classes above.", {}),
    ("above-the-fold-is-not-threshold", "Remove unused above-the-fold area.", {}),
    ("comparator-is-threshold", "Keep at least 3 samples.", {"threshold": ["at least"]}),
    ("dimension-is-threshold", "Use a 44×44 dp target.", {"threshold": ["44×44 dp"]}),
    ("ratio-is-threshold", "Keep contrast at 4.5:1.", {"threshold": ["4.5:1"]}),
    ("inline-code-number-is-literal", "Use `500ms` as the example literal.", {}),
    ("path-number-is-literal", "Read references/500ms.md for details.", {}),
    ("parenthesized-path-number-is-literal", "Read (references/500ms.md) for details.", {}),
    ("quoted-percent-is-literal", "The sample literal is \"5%\".", {}),
]

failures = []
for name, text, expected in cases:
    actual = module.qualifier_terms(text)
    if actual != expected:
        failures.append(f"{name}: expected={expected!r} actual={actual!r}")

bundle_cases = [
    (
        "bundle-clause-action-is-local",
        "Preserve the audit record.",
        "Expose the audit record.",
        [],
        "BUNDLE_CLAUSE_ACTION_MISSING",
    ),
    (
        "bundle-clause-actor-is-local",
        "Every client MUST expose recovery.",
        "Every owner MUST expose recovery.",
        [
            {"kind": "modality", "before": ["MUST"], "after": ["MUST"], "same_immediate_host": True},
            {"kind": "scope", "before": ["Every"], "after": ["Every"], "same_immediate_host": True},
            {"kind": "actor", "before": ["client"], "after": ["owner"], "same_immediate_host": True},
        ],
        "BUNDLE_CLAUSE_ACTOR_MISSING",
    ),
    (
        "bundle-clause-modality-is-local",
        "The client MUST expose recovery.",
        "The client may expose recovery.",
        [
            {"kind": "modality", "before": ["MUST"], "after": ["may"], "same_immediate_host": True},
            {"kind": "actor", "before": ["client"], "after": ["client"], "same_immediate_host": True},
        ],
        "BUNDLE_CLAUSE_MODALITY_MISSING",
    ),
    (
        "bundle-clause-consequence-is-local",
        "The release remains pending.",
        "The release remains queued.",
        [
            {"kind": "consequence", "before": ["pending"], "after": [], "same_immediate_host": True},
        ],
        "BUNDLE_CLAUSE_CONSEQUENCE_MISSING",
    ),
]
for name, before, after, claimed, expected_code in bundle_cases:
    try:
        module.validate_bundle_clause_proof(before, after, claimed, name)
    except module.AuditError as exc:
        if exc.code != expected_code:
            failures.append(f"{name}: expected_code={expected_code} actual_code={exc.code}")
    else:
        failures.append(f"{name}: expected_code={expected_code} but proof passed")

threshold_direction_cases = [
    ("below-to-above-is-reversed", "Keep failures below 5%.", "Keep failures above 5%."),
    ("under-to-over-is-reversed", "Keep failures under 5%.", "Keep failures over 5%."),
]
for name, before, after in threshold_direction_cases:
    try:
        module.ensure_qualifier_strength(before, after, name)
    except module.AuditError as exc:
        if exc.code != "BUNDLE_QUALIFIER_REVERSED":
            failures.append(
                f"{name}: expected_code=BUNDLE_QUALIFIER_REVERSED actual_code={exc.code}"
            )
    else:
        failures.append(f"{name}: reversed threshold direction passed")
if module.HARD_MODALITY.search("Use only provenance sources."):
    failures.append("only-is-hard-modality: unexpected HARD_MODALITY match")
if module.HARD_MODALITY.search("该来源仅用于证据。"):
    failures.append("only-chinese-is-hard-modality: unexpected HARD_MODALITY match")

def resolution_probe(name, before, after, resolution, chain=("Delivery Contract",)):
    carrier = module.Carrier("skills/destination/SKILL.md", after, chain, 1, 1)
    try:
        module.ensure_partition_qualifier_strength(
            before, after, name, [resolution], [carrier]
        )
    except module.AuditError as exc:
        failures.append(f"{name}: unexpected {exc.code}: {exc.detail}")

resolution_probe(
    "implicit-hard-normative",
    "The baseline must name its provenance type.",
    "Every slice records a falsifiable baseline.",
    {"kind":"modality","before":"must","resolution":"implicit-normative"},
)
resolution_probe(
    "per-to-each",
    "Handle per class.",
    "Classify each difference.",
    {"kind":"scope","before":"per","resolution":"universal-member"},
)
resolution_probe(
    "actor-number",
    "Users know the result.",
    "The user knows the result.",
    {"kind":"actor","before":"Users","resolution":"singular-plural"},
)
resolution_probe(
    "square-dimension",
    "Use a 44pt target.",
    "Use a 44×44pt target.",
    {"kind":"threshold","before":"44pt","resolution":"square-dimension"},
)
resolution_probe(
    "precondition-completion-boundary",
    "Run the recorded consumer check before closing on API evidence.",
    "A value may leave this contract only after consumer proof establishes the universe and every member is checked.",
    {"kind":"recency","before":"before","resolution":"precondition-completion-boundary"},
)
resolution_probe(
    "invalid-closure-hard-prohibition",
    "Backend-only closure without the recorded consumer check is invalid.",
    "A value is outside this contract only after the consumer universe is checked or proves it cannot affect any client.",
    {"kind":"consequence","before":"invalid","resolution":"hard-prohibition"},
)
try:
    module.ensure_partition_qualifier_strength(
        "The baseline must name its provenance type.",
        "The baseline should name its provenance type.",
        "soft-is-not-hard",
        [{"kind":"modality","before":"must","resolution":"implicit-normative"}],
        [module.Carrier("skills/destination/SKILL.md", "The baseline should name its provenance type.", ("Delivery Contract",), 1, 1)],
    )
    failures.append("soft-is-not-hard: weakened modality passed")
except module.AuditError as exc:
    if exc.code != "PART_QUALIFIER_RESOLUTION_INVALID":
        failures.append(f"soft-is-not-hard: wrong error {exc.code}")
for name, before, after, resolution in [
    (
        "after-without-checked-proof-is-not-precondition",
        "Run the recorded consumer check before closing on API evidence.",
        "The change may close after a repository search.",
        {"kind":"recency","before":"before","resolution":"precondition-completion-boundary"},
    ),
    (
        "advisory-close-is-not-invalid-prohibition",
        "Backend-only closure without the recorded consumer check is invalid.",
        "Only a backend value may leave the contract.",
        {"kind":"consequence","before":"invalid","resolution":"hard-prohibition"},
    ),
]:
    try:
        module.ensure_partition_qualifier_strength(
            before,
            after,
            name,
            [resolution],
            [module.Carrier("skills/destination/SKILL.md", after, ("Delivery Contract",), 1, 1)],
        )
        failures.append(f"{name}: invalid semantic relation passed")
    except module.AuditError as exc:
        if exc.code != "PART_QUALIFIER_RESOLUTION_INVALID":
            failures.append(f"{name}: wrong error {exc.code}")
if failures:
    print("FAIL qualifier tokenizer context contract", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print(
    "PASS qualifier tokenizer/context, threshold direction, and clause lexical guards "
    f"({len(cases)} tokenizer cases, {len(threshold_direction_cases)} direction probes, "
    f"{len(bundle_cases)} clause probes)"
)
PY

python3 "$TOOL" render --repo "$FIXTURE" --base "$BASE" \
  --mapping "$FIXTURE/specs/mapping.jsonl" --output "$FIXTURE/specs/ledger.md"
grep -Fq 'The sibling `obligation-mapping.jsonl` is the canonical proof source' \
  "$FIXTURE/specs/ledger.md"
grep -Fq '[c1]' "$FIXTURE/specs/ledger.md"
grep -Fq 'relations=1' "$FIXTURE/specs/ledger.md"
grep -Fq 'proof_mode=exact-mechanical' "$FIXTURE/specs/ledger.md"
grep -Fq 'proof_mode=reviewed-semantic' "$FIXTURE/specs/ledger.md"
grep -Fq 'validates review evidence presence and shape, not the truth' \
  "$FIXTURE/specs/ledger.md"
if grep -Fq 'The owner MUST retain the release token before final approval.' \
  "$FIXTURE/specs/ledger.md"; then
  echo "FAIL: compact ledger duplicated canonical before/carrier text" >&2
  exit 1
fi
audit_output="$(python3 "$TOOL" audit --repo "$FIXTURE" --base "$BASE" \
  --mapping "$FIXTURE/specs/mapping.jsonl" --ledger "$FIXTURE/specs/ledger.md" 2>&1)"
printf '%s\n' "$audit_output" | grep -Fq 'exact_mechanical='
printf '%s\n' "$audit_output" | grep -Fq 'reviewed_semantic='
git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm candidate

mutate_jsonl() {
  local file="$1" expression="$2"
  python3 - "$file" "$expression" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
expression = sys.argv[2]
rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
exec(expression, {"rows": rows})
path.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")
PY
}

mutation_error_matches() {
  local expected_code="$1" expected_target="$2" output="$3"
  printf '%s\n' "$output" | grep -q "^ERROR $expected_code:" && \
    printf '%s\n' "$output" | grep -Fq "$expected_target"
}

if mutation_error_matches \
  QUALIFIER_REVERSED 'skills/source/SKILL.md#24' \
  'ERROR QUALIFIER_REVERSED: skills/source/SKILL.md#25: threshold'; then
  echo "FAIL mutation target attribution: unrelated same-code target was accepted" >&2
  exit 1
fi
echo "PASS mutation target attribution rejects unrelated same-code failures"

run_mutant() {
  local name="$1" expected_code="$2" expected_target="$3" expected_delta="$4"
  shift 4
  local case_dir="$TMP_ROOT/$name" control_output output status actual_delta
  git clone -q "$FIXTURE" "$case_dir"
  control_output="$(python3 "$TOOL" audit --repo "$case_dir" --base "$BASE" \
    --mapping "$case_dir/specs/mapping.jsonl" --ledger "$case_dir/specs/ledger.md" 2>&1)" || {
    echo "FAIL $name: unmutated control was not green: $control_output" >&2
    exit 1
  }
  "$@" "$case_dir"
  if git -C "$case_dir" diff --quiet; then
    echo "FAIL $name: mutation precondition produced no tracked delta" >&2
    exit 1
  fi
  actual_delta="$(git -C "$case_dir" diff --name-only | LC_ALL=C sort | paste -sd, -)"
  if [ "$actual_delta" != "$expected_delta" ]; then
    echo "FAIL $name: expected exact delta $expected_delta, got $actual_delta" >&2
    exit 1
  fi
  if printf '%s\n' "$actual_delta" | grep -Fq 'specs/mapping.jsonl' && \
    printf '%s\n' "$expected_target" | grep -q '^skills/source/.*#[0-9]'; then
    local changed_rows expected_row
    expected_row="${expected_target%%/member-*}"
    expected_row="${expected_row%%/part-*}"
    changed_rows="$(python3 - "$case_dir" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
before = subprocess.run(
    ["git", "-C", str(repo), "show", "HEAD:specs/mapping.jsonl"],
    check=True,
    capture_output=True,
    text=True,
).stdout
after = (repo / "specs/mapping.jsonl").read_text(encoding="utf-8")

def keyed(raw):
    rows = [json.loads(line) for line in raw.splitlines() if line]
    return {
        f"{row['source_path']}#{row['source_ordinal']}": row
        for row in rows
    }

old = keyed(before)
new = keyed(after)
print(",".join(sorted(key for key in old.keys() | new.keys() if old.get(key) != new.get(key))))
PY
)"
    if [ "$changed_rows" != "$expected_row" ]; then
      echo "FAIL $name: expected single mapping-row delta $expected_row, got $changed_rows" >&2
      exit 1
    fi
  fi
  set +e
  output="$(python3 "$TOOL" audit --repo "$case_dir" --base "$BASE" \
    --mapping "$case_dir/specs/mapping.jsonl" --ledger "$case_dir/specs/ledger.md" 2>&1)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "FAIL $name: mutant survived" >&2
    exit 1
  fi
  if ! mutation_error_matches "$expected_code" "$expected_target" "$output"; then
    echo "FAIL $name: expected first code $expected_code at $expected_target, got: $output" >&2
    exit 1
  fi
  echo "PASS $name -> first_error=$expected_code target=$expected_target delta=$actual_delta"
}

mutation_missing_row() {
  sed -i.bak '2d' "$1/specs/mapping.jsonl"
  rm "$1/specs/mapping.jsonl.bak"
}

mutation_duplicate_carrier() {
  mutate_jsonl "$1/specs/mapping.jsonl" \
    'rows[0]["carriers"] = [{"path": rows[0]["carrier_path"], "text": rows[0]["carrier_text"], "chain": rows[0]["carrier_chain"]}, {"path": "skills/extra/SKILL.md", "text": "Every client MUST preserve the unchanged comparison-domain contract.", "chain": ["Extra", "Stable"]}]'
}

mutation_weaken_modality() {
  sed -i.bak 's/delivery owner MUST retain/delivery owner may retain/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" \
    'rows[0]["carrier_text"] = rows[0]["carrier_text"].replace("MUST", "may"); rows[0]["qualifiers"][0]["after"] = ["may"]'
}

mutation_wrong_parent() {
  sed -i.bak 's/## Delivery contract/## Advisory delivery notes/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
}

mutation_reverse_recency() {
  sed -i.bak 's/before final approval/after initial approval/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" \
    'rows[0]["carrier_text"] = rows[0]["carrier_text"].replace("before final", "after initial"); rows[0]["qualifiers"][1]["after"] = ["after", "initial"]'
}

mutation_stale_locator() {
  sed -E -i.bak 's#skills/destination/SKILL.md:[0-9]+-[0-9]+#skills/destination/SKILL.md:999-999#g' "$1/specs/ledger.md"
  rm "$1/specs/ledger.md.bak"
}

mutation_invalid_status() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[0]["disposition"] = "superseded"'
}

mutation_retired_preserved() {
  mutate_jsonl "$1/specs/mapping.jsonl" \
    'rows[0]["disposition"] = "retired-dead"; rows[0]["effect"] = "preserved"; rows[0]["carrier_path"] = None; rows[0]["carrier_text"] = None; rows[0]["carrier_chain"] = None; rows[0]["qualifiers"] = []; rows[0]["review_note"] = "authority: fixture authority; scope: this obsolete row"'
}

mutation_unreviewed_strengthening() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[3]["effect"] = "strengthened"; rows[3]["manual_reviewed"] = False'
}

mutation_provenance_only() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[0]["carrier_path"] = "skills/meta/references/source-register.md"'
}

mutation_new_domain_file() {
  sed -i.bak 's/unchanged comparison-domain contract/rewritten comparison-domain contract/' "$1/skills/extra/SKILL.md"
  rm "$1/skills/extra/SKILL.md.bak"
}

mutation_lost_baseline_table_cell() {
  sed -i.bak 's/stable table audit/rewritten table audit/' "$1/skills/matrix/SKILL.md"
  rm "$1/skills/matrix/SKILL.md.bak"
}

mutation_table_carrier_to_fence() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |\n', '')
text += '\n```text\nEvery delivery client MUST preserve the table-bound release record.\n```\n'
path.write_text(text)
PY
}

mutation_table_carrier_to_comment() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |', '<!-- Every delivery client MUST preserve the table-bound release record. -->')
path.write_text(text)
PY
}

mutation_table_carrier_to_header() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |\n', '')
text += '\n| Every delivery client MUST preserve the table-bound release record. | Other |\n| --- | --- |\n'
path.write_text(text)
PY
}

mutation_table_inside_long_fence() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |\n', '')
text += '\n````markdown\n```text\n| Rule | Boundary |\n| --- | --- |\n| Every delivery client MUST preserve the table-bound release record. | inert |\n```\n````\n'
path.write_text(text)
PY
}

mutation_table_inside_mismatched_fence() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |\n', '')
text += '\n```markdown\n~~~\n| Rule | Boundary |\n| --- | --- |\n| Every delivery client MUST preserve the table-bound release record. | inert |\n~~~\n```\n'
path.write_text(text)
PY
}

mutation_table_after_nonblank_fence_suffix() {
  python3 - "$1/skills/matrix/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace('| Every delivery client MUST preserve the table-bound release record. | Runtime-visible contract. |\n', '')
text += '\n```markdown\n```not-a-closer\n| Rule | Boundary |\n| --- | --- |\n| Every delivery client MUST preserve the table-bound release record. | inert |\n```\n'
path.write_text(text)
PY
}

mutation_inline_code_only_table_cell() {
  sed -i.bak 's/| Every delivery client MUST preserve the table-bound release record. |/| `Every delivery client MUST preserve the table-bound release record.` |/' "$1/skills/matrix/SKILL.md"
  rm "$1/skills/matrix/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" \
    'rows[2]["carrier_text"] = "`Every delivery client MUST preserve the table-bound release record.`"'
}


mutation_bundle_noncompound() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[3]["carrier_path"] = None; rows[3]["carrier_text"] = None; rows[3]["carrier_chain"] = None; rows[3]["carrier_bundle"] = rows[4]["carrier_bundle"]; rows[3]["compound_clauses"] = rows[4]["compound_clauses"]; rows[3]["disposition"] = "subsumed"; rows[3]["manual_reviewed"] = True; rows[3]["qualifiers"] = rows[4]["qualifiers"]'
}

mutation_bundle_size_one() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"] = rows[4]["carrier_bundle"][:1]'
}

mutation_scalar_and_bundle() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_path"] = "skills/destination/SKILL.md"'
}

mutation_duplicate_bundle_member() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"].append(rows[4]["carrier_bundle"][0].copy())'
}

mutation_empty_bundle_covers() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"][0]["covers"] = []'
}

mutation_uncovered_bundle_clause() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"] = rows[4]["carrier_bundle"][:2]'
}

mutation_duplicate_clause_coverage() {
  python3 - "$1/skills/destination/SKILL.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(
    path.read_text()
    + "- The release record MUST preserve these clauses:owner context must remain fully visible.\n"
)
PY
  mutate_jsonl "$1/specs/mapping.jsonl" 'm = rows[4]["carrier_bundle"][2]; m["carrier_text"] = "The release record MUST preserve these clauses:owner context must remain fully visible."; m["covers"] = ["c1"]; m["clause_qualifiers"] = [{"clause_id":"c1","qualifiers":[{"kind":"modality","before":["MUST","must"],"after":["MUST","must"],"same_immediate_host":True},{"kind":"actor","before":["owner"],"after":["owner"],"same_immediate_host":True}],"semantic_review":"reviewed","semantic_rationale":"Reviewed duplicate-coverage mutant clause."}]'
}

mutation_stale_bundle_member() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"][0]["carrier_text"] += " stale"'
}

mutation_bundle_actor_wrong_member() {
  sed -i.bak 's/The release record MUST preserve these clauses:owner context must remain visible\./Every owner MUST preserve these clauses:context must remain visible./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'a = rows[4]["carrier_bundle"][0]; b = rows[4]["carrier_bundle"][1]; a["carrier_text"] = "Every owner MUST preserve these clauses:context must remain visible."; a["covers"] = ["c2"]; a["clause_qualifiers"] = [{"clause_id":"c2","qualifiers":[{"kind":"modality","before":["must"],"after":["MUST","must"],"same_immediate_host":True},{"kind":"scope","before":["every"],"after":["Every"],"same_immediate_host":True},{"kind":"actor","before":["client"],"after":["owner"],"same_immediate_host":True}],"semantic_review":"reviewed","semantic_rationale":"Reviewed wrong-member mutant clause c2."}]; b["covers"] = ["c1"]; b["clause_qualifiers"] = [{"clause_id":"c1","qualifiers":[{"kind":"modality","before":["MUST","must"],"after":["must"],"same_immediate_host":True},{"kind":"actor","before":["owner"],"after":["client"],"same_immediate_host":True}],"semantic_review":"reviewed","semantic_rationale":"Reviewed wrong-member mutant clause c1."}]'
}

mutation_bundle_recency_reversed() {
  sed -i.bak 's/Final approval must block unsafe retry\./Initial approval must block unsafe retry./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'm = rows[4]["carrier_bundle"][2]; m["carrier_text"] = "Initial approval must block unsafe retry."; m["clause_qualifiers"][0]["qualifiers"][1]["after"] = ["Initial"]; rows[4]["qualifiers"][1]["after"] = ["Initial"]'
}

mutation_bundle_must_to_may() {
  sed -i.bak 's/Every client must expose recovery\./Every client may expose recovery./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'm = rows[4]["carrier_bundle"][1]; m["carrier_text"] = "Every client may expose recovery."; m["clause_qualifiers"][0]["qualifiers"][0]["after"] = ["may"]'
}

mutation_bundle_swap_clause_actions() {
  sed -i.bak \
    -e 's/The release record MUST preserve these clauses:owner context must remain visible\./The release record MUST expose these clauses:owner context must remain visible./' \
    -e 's/Every client must expose recovery\./Every client must preserve recovery./' \
    "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'b = rows[4]["carrier_bundle"]; b[0]["carrier_text"] = "The release record MUST expose these clauses:owner context must remain visible."; b[1]["carrier_text"] = "Every client must preserve recovery."'
}

mutation_bundle_multi_clause_carrier() {
  python3 - "$1/skills/destination/SKILL.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "- The release record MUST preserve these clauses:owner context must remain visible.\n"
    "- Every client must expose recovery.\n",
    "- The release record MUST preserve these clauses:owner context must remain visible; "
    "Every client must expose recovery.\n",
)
path.write_text(text)
PY
  mutate_jsonl "$1/specs/mapping.jsonl" 'b = rows[4]["carrier_bundle"]; b[0]["carrier_text"] = "The release record MUST preserve these clauses:owner context must remain visible; Every client must expose recovery."; b[0]["covers"] = ["c1", "c2"]; b[0]["clause_qualifiers"] = [{"clause_id":"c1","qualifiers":[{"kind":"modality","before":["MUST","must"],"after":["MUST","must"],"same_immediate_host":True},{"kind":"actor","before":["owner"],"after":["owner","client"],"same_immediate_host":True}],"semantic_review":"reviewed","semantic_rationale":"Reviewed compound-member mutant clause c1."},{"clause_id":"c2","qualifiers":[{"kind":"modality","before":["must"],"after":["MUST","must"],"same_immediate_host":True},{"kind":"scope","before":["every"],"after":["Every"],"same_immediate_host":True},{"kind":"actor","before":["client"],"after":["owner","client"],"same_immediate_host":True}],"semantic_review":"reviewed","semantic_rationale":"Reviewed compound-member mutant clause c2."}]; del b[1]'
}

mutation_bundle_compound_member_single_cover() {
  python3 - "$1/skills/destination/SKILL.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text += (
    "- The release record MUST preserve these clauses:owner context must remain visible; "
    "Every client must expose recovery.\n"
)
path.write_text(text)
PY
  mutate_jsonl "$1/specs/mapping.jsonl" 'm = rows[4]["carrier_bundle"][0]; m["carrier_text"] = "The release record MUST preserve these clauses:owner context must remain visible; Every client must expose recovery."; m["clause_qualifiers"][0]["qualifiers"] = [{"kind":"modality","before":["MUST","must"],"after":["MUST","must"],"same_immediate_host":True},{"kind":"actor","before":["owner"],"after":["owner","client"],"same_immediate_host":True}]'
}

mutation_only_to_any() {
  sed -i.bak 's/None of the non-provenance sources may be used\./Any non-provenance source may be used./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[6]["carrier_text"] = "Any non-provenance source may be used."; rows[6]["qualifiers"][0]["after"] = ["Any"]'
}

mutation_every_to_any() {
  sed -i.bak 's/Every gate reviewer MUST reject/Any gate reviewer MUST reject/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[1]["carrier_text"] = rows[1]["carrier_text"].replace("Every", "Any"); rows[1]["qualifiers"][1]["after"] = ["Any"]'
}

mutation_remove_exclusive_expression() {
  sed -i.bak 's/not a substitute for design judgment/a substitute for design judgment/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[9]["carrier_text"] = rows[9]["carrier_text"].replace("not a substitute", "a substitute"); rows[9]["qualifiers"] = []'
}

mutation_drop_true_threshold() {
  sed -i.bak 's/MUST complete within 500 ms/MUST complete eventually/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[15]["carrier_text"] = rows[15]["carrier_text"].replace("within 500 ms", "eventually"); rows[15]["qualifiers"] = rows[15]["qualifiers"][:1]'
}

mutation_drop_pending_status() {
  sed -i.bak 's/MUST stay `pending`/MUST stay queued/' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[16]["carrier_text"] = rows[16]["carrier_text"].replace("`pending`", "queued"); rows[16]["qualifiers"] = rows[16]["qualifiers"][:1]'
}

mutation_drop_true_blocker() {
  sed -i.bak 's/Final approval MUST block unsafe retry\./Final approval MUST allow unsafe retry./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[18]; r["carrier_text"] = "Final approval MUST allow unsafe retry."; r["manual_reviewed"] = True; r["semantic_review"] = "reviewed"; r["semantic_rationale"] = "Reviewed the blocker-removal mutant."; r["qualifiers"] = [{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":True},{"kind":"recency","before":["Final"],"after":["Final"],"same_immediate_host":True}]'
}

mutation_drop_true_actor() {
  sed -i.bak 's/The user MUST confirm the irreversible action\./The workflow MUST confirm the irreversible action./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[20]; r["carrier_text"] = "The workflow MUST confirm the irreversible action."; r["qualifiers"] = r["qualifiers"][:1]'
}

mutation_reverse_below_threshold() {
  sed -i.bak 's/The failure rate MUST stay below 5%\./The failure rate MUST stay above 5%./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[23]; r["carrier_text"] = "The failure rate MUST stay above 5%."; r["manual_reviewed"] = True; r["semantic_review"] = "reviewed"; r["semantic_rationale"] = "Reviewed the changed threshold direction."; r["qualifiers"] = [{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":True},{"kind":"threshold","before":["below","5%"],"after":["above","5%"],"same_immediate_host":True}]'
}

mutation_reverse_under_threshold() {
  sed -i.bak 's/The retry rate MUST stay under 5%\./The retry rate MUST stay over 5%./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[24]; r["carrier_text"] = "The retry rate MUST stay over 5%."; r["manual_reviewed"] = True; r["semantic_review"] = "reviewed"; r["semantic_rationale"] = "Reviewed the changed threshold direction."; r["qualifiers"] = [{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":True},{"kind":"threshold","before":["under","5%"],"after":["over","5%"],"same_immediate_host":True}]'
}

mutation_scalar_semantic_review_missing() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[0]["semantic_review"] = None'
}

mutation_scalar_semantic_rationale_missing() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[0]["semantic_rationale"] = ""'
}

mutation_bundle_clause_semantic_review_missing() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"][0]["clause_qualifiers"][0]["semantic_review"] = None'
}

mutation_bundle_clause_semantic_rationale_missing() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[4]["carrier_bundle"][0]["clause_qualifiers"][0]["semantic_rationale"] = ""'
}

mutation_relation_on_modality() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[5]["qualifier_relations"][0]; r["kind"] = "modality"; r["term"] = "MUST"; r["source_excerpt"] = "MUST"'
}

mutation_relation_on_scope() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[6]; r["effect"] = "strengthened"; r["qualifier_relations"] = [{"kind":"scope","term":"only","occurrence":1,"source_excerpt":"only provenance","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted scope suppression."'
}

mutation_relation_on_consequence() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[16]; r["effect"] = "strengthened"; r["qualifier_relations"] = [{"kind":"consequence","term":"pending","occurrence":1,"source_excerpt":"`pending`","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted terminal suppression."'
}

mutation_relation_on_threshold() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[15]; r["effect"] = "strengthened"; r["qualifier_relations"] = [{"kind":"threshold","term":"within","occurrence":1,"source_excerpt":"within 500 ms","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted threshold suppression."'
}

mutation_relation_stale_occurrence() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["qualifier_relations"][0]["occurrence"] = 2'
}

mutation_relation_stale_excerpt() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["qualifier_relations"][0]["source_excerpt"] = "final artifact"'
}

mutation_duplicate_relation() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["qualifier_relations"].append(rows[5]["qualifier_relations"][0].copy())'
}

mutation_relation_without_strengthening() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["effect"] = "preserved"'
}

mutation_relation_without_review() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["manual_reviewed"] = False'
}

mutation_relation_without_review_note() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["review_note"] = ""'
}

mutation_relation_without_closed_final_rewrite() {
  sed -i.bak 's/The resulting skill MUST stay generic\./The skill MUST stay generic./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[5]["carrier_text"] = "The skill MUST stay generic."'
}

mutation_relation_on_latest_design() {
  sed -i.bak 's/The latest design MUST remain accessible\./The design MUST remain accessible./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[21]; r["effect"] = "strengthened"; r["carrier_text"] = "The design MUST remain accessible."; r["manual_reviewed"] = True; r["semantic_review"] = "reviewed"; r["semantic_rationale"] = "Reviewed the attempted latest-design rewrite."; r["qualifiers"] = [{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":True}]; r["qualifier_relations"] = [{"kind":"recency","term":"latest","occurrence":1,"source_excerpt":"latest design","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: reviewer claims latest is non-temporal."'
}

mutation_relation_on_final_artifact() {
  sed -i.bak 's/The final artifact MUST retain its audit trail\./The artifact MUST retain its audit trail./' "$1/skills/destination/SKILL.md"
  rm "$1/skills/destination/SKILL.md.bak"
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[22]; r["effect"] = "strengthened"; r["carrier_text"] = "The artifact MUST retain its audit trail."; r["manual_reviewed"] = True; r["semantic_review"] = "reviewed"; r["semantic_rationale"] = "Reviewed the attempted final-artifact rewrite."; r["qualifiers"] = [{"kind":"modality","before":["MUST"],"after":["MUST"],"same_immediate_host":True}]; r["qualifier_relations"] = [{"kind":"recency","term":"final","occurrence":1,"source_excerpt":"final artifact","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: reviewer claims artifact finality is implicit."'
}

mutation_relation_on_ordered_final() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[0]; r["qualifier_relations"] = [{"kind":"recency","term":"final","occurrence":1,"source_excerpt":"final approval","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted final-approval suppression."'
}

mutation_relation_on_final_content() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[19]; r["effect"] = "strengthened"; r["qualifier_relations"] = [{"kind":"recency","term":"final","occurrence":1,"source_excerpt":"final content","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted terminal-content suppression."'
}

mutation_relation_on_bundle() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'r = rows[4]; r["effect"] = "strengthened"; r["qualifier_relations"] = [{"kind":"recency","term":"final","occurrence":1,"source_excerpt":"final approval","resolution":"carrier-applies-unconditionally","same_immediate_host":True}]; r["review_note"] = "Qualifier relation: attempted bundle suppression."'
}

mutation_schema4_missing_part() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'del rows[12]["parts"][1]'
}

mutation_schema4_overlap() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][1]["source_start"] -= 1'
}

mutation_schema4_source_text() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][0]["source_text"] = "Remove used "'
}

mutation_schema4_before_text() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["before_text"] += " stale"'
}

mutation_schema4_empty_carrier() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][0]["carriers"] = []'
}

mutation_schema4_generic_neighbor() {
  python3 - "$1/specs/mapping.jsonl" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text().splitlines() if line]
member = rows[12]["parts"][0]["carriers"][0]
member["carrier_text"] = "Existing stable contract remains unchanged for the fixture."
member["carrier_chain"] = ["Destination", "Current"]
member["bridge_terms"] = ["stable"]
payload = json.dumps(
    [member["carrier_path"], member["carrier_chain"], member["carrier_text"]],
    ensure_ascii=False,
    separators=(",", ":"),
).encode()
member["carrier_sha256"] = hashlib.sha256(payload).hexdigest()
path.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows))
PY
}

mutation_schema4_retired_only_bridge() {
  python3 - "$1/specs/mapping.jsonl" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text().splitlines() if line]
member = rows[12]["parts"][0]["carriers"][0]
member["carrier_text"] = "Legacy first-screen note remains in destination."
member["carrier_chain"] = ["Destination", "Delivery contract"]
member["bridge_terms"] = ["first-screen"]
payload = json.dumps(
    [member["carrier_path"], member["carrier_chain"], member["carrier_text"]],
    ensure_ascii=False,
    separators=(",", ":"),
).encode()
member["carrier_sha256"] = hashlib.sha256(payload).hexdigest()
path.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows))
PY
}

mutation_schema4_hash() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][0]["carriers"][0]["carrier_sha256"] = "0" * 64'
}

mutation_schema4_authority() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][1]["authority"] = ""'
}

mutation_schema4_scope() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][1]["scope"] = ""'
}

mutation_schema4_reason() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][1]["reason"] = ""'
}

mutation_schema4_qualifier() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[13]["parts"][0]["qualifiers"] = []'
}

mutation_schema4_duplicate_carrier() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["parts"][0]["carriers"].append(rows[12]["parts"][0]["carriers"][0].copy())'
}

mutation_schema4_wrong_disposition() {
  mutate_jsonl "$1/specs/mapping.jsonl" 'rows[12]["disposition"] = "partitioned"'
}

DELTA_MAPPING='specs/mapping.jsonl'
DELTA_DEST='skills/destination/SKILL.md'
DELTA_DEST_MAPPING='skills/destination/SKILL.md,specs/mapping.jsonl'
DELTA_MATRIX='skills/matrix/SKILL.md'
DELTA_MATRIX_MAPPING='skills/matrix/SKILL.md,specs/mapping.jsonl'

run_mutant missing_row ROW_SET_MISMATCH 'skills/source/SKILL.md#2' "$DELTA_MAPPING" mutation_missing_row
run_mutant duplicate_carrier MULTIPLE_CARRIERS 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_duplicate_carrier
run_mutant must_to_may QUALIFIER_WEAKENED 'skills/source/SKILL.md#1' "$DELTA_DEST_MAPPING" mutation_weaken_modality
run_mutant wrong_parent CARRIER_CHAIN_MISMATCH 'skills/source/SKILL.md#1' "$DELTA_DEST" mutation_wrong_parent
run_mutant recency_direction_reversal QUALIFIER_REVERSED 'skills/source/SKILL.md#1' "$DELTA_DEST_MAPPING" mutation_reverse_recency
run_mutant stale_locator STALE_LEDGER 'specs/ledger.md' 'specs/ledger.md' mutation_stale_locator
run_mutant invalid_status INVALID_DISPOSITION 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_invalid_status
run_mutant retired_dead_preserved RETIRED_EFFECT_INVALID 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_retired_preserved
run_mutant unreviewed_verbatim_strengthening STRENGTHENED_REVIEW_REQUIRED 'skills/source/SKILL.md#4' "$DELTA_MAPPING" mutation_unreviewed_strengthening
run_mutant provenance_only PROVENANCE_ONLY_CARRIER 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_provenance_only
run_mutant comparison_domain_new_file ROW_SET_MISMATCH 'skills/extra/SKILL.md#1' 'skills/extra/SKILL.md' mutation_new_domain_file
run_mutant lost_baseline_table_cell ROW_SET_MISMATCH 'skills/matrix/SKILL.md#1' "$DELTA_MATRIX" mutation_lost_baseline_table_cell
run_mutant table_carrier_moved_to_fence CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_carrier_to_fence
run_mutant table_carrier_moved_to_comment CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_carrier_to_comment
run_mutant table_carrier_moved_to_header CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_carrier_to_header
run_mutant table_inside_long_outer_fence CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_inside_long_fence
run_mutant table_inside_mismatched_fence CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_inside_mismatched_fence
run_mutant table_after_nonblank_fence_suffix CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX" mutation_table_after_nonblank_fence_suffix
run_mutant inline_code_only_table_cell CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#3' "$DELTA_MATRIX_MAPPING" mutation_inline_code_only_table_cell

run_mutant bundle_noncompound BUNDLE_SOURCE_NOT_COMPOUND 'skills/source/SKILL.md#4' "$DELTA_MAPPING" mutation_bundle_noncompound
run_mutant bundle_size_one BUNDLE_SIZE 'skills/source/SKILL.md#5' "$DELTA_MAPPING" mutation_bundle_size_one
run_mutant scalar_and_bundle CARRIER_SHAPE_CONFLICT 'skills/source/SKILL.md#5' "$DELTA_MAPPING" mutation_scalar_and_bundle
run_mutant duplicate_bundle_member BUNDLE_DUPLICATE_MEMBER 'skills/source/SKILL.md#5/member-4' "$DELTA_MAPPING" mutation_duplicate_bundle_member
run_mutant empty_bundle_covers BUNDLE_MEMBER_EMPTY 'skills/source/SKILL.md#5/member-1' "$DELTA_MAPPING" mutation_empty_bundle_covers
run_mutant uncovered_bundle_clause BUNDLE_CLAUSE_UNCOVERED 'skills/source/SKILL.md#5' "$DELTA_MAPPING" mutation_uncovered_bundle_clause
run_mutant duplicate_clause_coverage BUNDLE_CLAUSE_DUPLICATE 'skills/source/SKILL.md#5' "$DELTA_DEST_MAPPING" mutation_duplicate_clause_coverage
run_mutant stale_bundle_member CARRIER_COMPOSITE_NOT_UNIQUE 'skills/source/SKILL.md#5/member-1' "$DELTA_MAPPING" mutation_stale_bundle_member
run_mutant bundle_actor_wrong_member BUNDLE_CLAUSE_ACTOR_MISSING 'skills/source/SKILL.md#5/member-1/c2' "$DELTA_DEST_MAPPING" mutation_bundle_actor_wrong_member
run_mutant bundle_must_to_may BUNDLE_CLAUSE_MODALITY_MISSING 'skills/source/SKILL.md#5/member-2/c2' "$DELTA_DEST_MAPPING" mutation_bundle_must_to_may
run_mutant bundle_recency_reversed BUNDLE_QUALIFIER_REVERSED 'skills/source/SKILL.md#5/member-3/c3' "$DELTA_DEST_MAPPING" mutation_bundle_recency_reversed
run_mutant bundle_sibling_action_borrow BUNDLE_CLAUSE_ACTION_MISSING 'skills/source/SKILL.md#5/member-1/c1' "$DELTA_DEST_MAPPING" mutation_bundle_swap_clause_actions
run_mutant bundle_multi_clause_carrier BUNDLE_MEMBER_MULTI_CLAUSE 'skills/source/SKILL.md#5/member-1' "$DELTA_DEST_MAPPING" mutation_bundle_multi_clause_carrier
run_mutant bundle_compound_member_single_cover BUNDLE_MEMBER_COMPOUND 'skills/source/SKILL.md#5/member-1' "$DELTA_DEST_MAPPING" mutation_bundle_compound_member_single_cover

run_mutant only_to_any QUALIFIER_REVERSED 'skills/source/SKILL.md#7' "$DELTA_DEST_MAPPING" mutation_only_to_any
run_mutant every_to_any QUALIFIER_REVERSED 'skills/source/SKILL.md#2' "$DELTA_DEST_MAPPING" mutation_every_to_any
run_mutant exclusive_expression_removed QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#10' "$DELTA_DEST_MAPPING" mutation_remove_exclusive_expression
run_mutant true_threshold_dropped QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#16' "$DELTA_DEST_MAPPING" mutation_drop_true_threshold
run_mutant pending_status_dropped QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#17' "$DELTA_DEST_MAPPING" mutation_drop_pending_status
run_mutant true_blocker_dropped QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#19' "$DELTA_DEST_MAPPING" mutation_drop_true_blocker
run_mutant true_actor_dropped QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#21' "$DELTA_DEST_MAPPING" mutation_drop_true_actor
run_mutant below_to_above QUALIFIER_REVERSED 'skills/source/SKILL.md#24' "$DELTA_DEST_MAPPING" mutation_reverse_below_threshold
run_mutant under_to_over QUALIFIER_REVERSED 'skills/source/SKILL.md#25' "$DELTA_DEST_MAPPING" mutation_reverse_under_threshold
run_mutant scalar_semantic_review_missing SEMANTIC_REVIEW_REQUIRED 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_scalar_semantic_review_missing
run_mutant scalar_semantic_rationale_missing SEMANTIC_RATIONALE_REQUIRED 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_scalar_semantic_rationale_missing
run_mutant bundle_clause_semantic_review_missing SEMANTIC_REVIEW_REQUIRED 'skills/source/SKILL.md#5/member-1/c1' "$DELTA_MAPPING" mutation_bundle_clause_semantic_review_missing
run_mutant bundle_clause_semantic_rationale_missing SEMANTIC_RATIONALE_REQUIRED 'skills/source/SKILL.md#5/member-1/c1' "$DELTA_MAPPING" mutation_bundle_clause_semantic_rationale_missing
run_mutant relation_on_modality QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_on_modality
run_mutant relation_on_scope QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#7' "$DELTA_MAPPING" mutation_relation_on_scope
run_mutant relation_on_consequence QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#17' "$DELTA_MAPPING" mutation_relation_on_consequence
run_mutant relation_on_threshold QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#16' "$DELTA_MAPPING" mutation_relation_on_threshold
run_mutant relation_stale_occurrence QUALIFIER_RELATION_INVALID 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_stale_occurrence
run_mutant relation_stale_excerpt QUALIFIER_RELATION_INVALID 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_stale_excerpt
run_mutant duplicate_relation QUALIFIER_RELATION_INVALID 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_duplicate_relation
run_mutant relation_without_strengthening QUALIFIER_RELATION_REQUIRES_STRENGTHENED 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_without_strengthening
run_mutant relation_without_review STRENGTHENED_REVIEW_REQUIRED 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_without_review
run_mutant relation_without_review_note REVIEW_NOTE_MISSING 'skills/source/SKILL.md#6' "$DELTA_MAPPING" mutation_relation_without_review_note
run_mutant relation_without_closed_final_rewrite QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#6' "$DELTA_DEST_MAPPING" mutation_relation_without_closed_final_rewrite
run_mutant relation_on_latest_design QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#22' "$DELTA_DEST_MAPPING" mutation_relation_on_latest_design
run_mutant relation_on_final_artifact QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#23' "$DELTA_DEST_MAPPING" mutation_relation_on_final_artifact
run_mutant relation_on_ordered_final QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#1' "$DELTA_MAPPING" mutation_relation_on_ordered_final
run_mutant relation_on_final_content QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#20' "$DELTA_MAPPING" mutation_relation_on_final_content
run_mutant relation_on_bundle QUALIFIER_RELATION_FORBIDDEN 'skills/source/SKILL.md#5' "$DELTA_MAPPING" mutation_relation_on_bundle

run_mutant schema4_missing_part PARTITION_GAP_OR_OVERLAP 'skills/source/SKILL.md#13/part-2' "$DELTA_MAPPING" mutation_schema4_missing_part
run_mutant schema4_overlap PARTITION_GAP_OR_OVERLAP 'skills/source/SKILL.md#13/part-2' "$DELTA_MAPPING" mutation_schema4_overlap
run_mutant schema4_source_text PART_SOURCE_MISMATCH 'skills/source/SKILL.md#13/part-1' "$DELTA_MAPPING" mutation_schema4_source_text
run_mutant schema4_before_text ROW_SOURCE_MISMATCH 'skills/source/SKILL.md#13' "$DELTA_MAPPING" mutation_schema4_before_text
run_mutant schema4_empty_carrier PART_CARRIER_REQUIRED 'skills/source/SKILL.md#13/part-1' "$DELTA_MAPPING" mutation_schema4_empty_carrier
run_mutant schema4_generic_neighbor PART_CARRIER_BRIDGE_MISSING 'skills/source/SKILL.md#13/part-1/member-1' "$DELTA_MAPPING" mutation_schema4_generic_neighbor
run_mutant schema4_retired_only_bridge PART_CARRIER_BRIDGE_MISSING 'skills/source/SKILL.md#13/part-1/member-1' "$DELTA_MAPPING" mutation_schema4_retired_only_bridge
run_mutant schema4_hash PART_CARRIER_HASH_MISMATCH 'skills/source/SKILL.md#13/part-1/member-1' "$DELTA_MAPPING" mutation_schema4_hash
run_mutant schema4_authority PART_RETIREMENT_PROOF_MISSING 'skills/source/SKILL.md#13/part-2: authority' "$DELTA_MAPPING" mutation_schema4_authority
run_mutant schema4_scope PART_RETIREMENT_PROOF_MISSING 'skills/source/SKILL.md#13/part-2: scope' "$DELTA_MAPPING" mutation_schema4_scope
run_mutant schema4_reason PART_RETIREMENT_PROOF_MISSING 'skills/source/SKILL.md#13/part-2: reason' "$DELTA_MAPPING" mutation_schema4_reason
run_mutant schema4_qualifier BUNDLE_QUALIFIER_CLASS_MISMATCH 'skills/source/SKILL.md#14/part-1' "$DELTA_MAPPING" mutation_schema4_qualifier
run_mutant schema4_duplicate_carrier PART_CARRIER_DUPLICATE 'skills/source/SKILL.md#13/part-1/member-2' "$DELTA_MAPPING" mutation_schema4_duplicate_carrier
run_mutant schema4_wrong_disposition PARTITION_DISPOSITION_MISMATCH 'skills/source/SKILL.md#13' "$DELTA_MAPPING" mutation_schema4_wrong_disposition

echo "test_obligation_ledger_ok"
