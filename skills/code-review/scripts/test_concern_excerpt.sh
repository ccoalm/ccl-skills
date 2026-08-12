#!/usr/bin/env bash
# Behavior tests for the bounded concern-evidence excerpt carried on the
# `stop_reviewer_lane` path. Rows map 1:1 to the acceptance matrix in
# specs/010-review-concern-excerpt/plan.md.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fails=0

check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

# Evaluate a python expression against the helper and the parser, printing a
# bare `True`/`False`. Anything else (import error, traceback) fails the row.
py() {
  DIR="$DIR" python3 - "$1" <<'PY' 2>/dev/null
import os
import sys

sys.path.insert(0, os.environ["DIR"])
import concern_excerpt as ce  # noqa: E402

MAX_LINES = ce.MAX_EXCERPT_LINES
MAX_CHARS = ce.MAX_EXCERPT_LINE_CHARS
excerpt = ce.concern_excerpt
print(bool(eval(sys.argv[1])))
PY
}

row() { check "$1" "[ \"\$(py '$2')\" = True ]"; }

# --- helper contract ------------------------------------------------------
check "helper module exists" '[ -f "$DIR/concern_excerpt.py" ]'
check "helper is the single source of the concern pattern" \
  'grep -q "^CONCERN_RE" "$DIR/concern_excerpt.py"'

# Row 1: no concern-shaped line -> no evidence, no excerpt.
row "row1 plain refusal carries no concern evidence" \
  'excerpt("I am unable to comply with that request.") == ([], False)'

# Row 2: empty / unreadable verdict -> no evidence.
row "row2 empty verdict carries no concern evidence" \
  'excerpt("") == ([], False)'

# Rows 3-8: UNSTRUCTURED output. After five rounds of credential shapes escaping
# the redaction denylist (and one of benign prose being over-redacted), the
# free-text relay was removed: report only tokens this module matched itself.
row "row3 severity is reported without the surrounding text" \
  'excerpt("P1 in the retry path")[0] == ["1 concern-shaped line(s), text withheld; severities: P1"]'

row "row4 locator is reported without the surrounding text" \
  '"locators: scripts/foo.py:42" in excerpt("scripts/foo.py:42 leaks a handle")[0][0] and "leaks a handle" not in excerpt("scripts/foo.py:42 leaks a handle")[0][0]'

row "row5 concern_results key still counts as evidence" \
  'excerpt("\"concern_results\": [")[0] == ["1 concern-shaped line(s), text withheld"]'

row "row6 the summary counts every matched line" \
  'excerpt("\n".join("P1 finding %d" % i for i in range(MAX_LINES + 5)))[0][0].startswith("%d concern-shaped line(s)" % (MAX_LINES + 5))'

row "row7 no unstructured text can reach the excerpt at any length" \
  '"word" not in excerpt("P1 " + "word " * 200)[0][0]'

row "row8 the summary aggregates severities and locators" \
  'excerpt("I read the supplied packet.\nP0 auth bypass\nNothing else to add.\nsrc/a.go:7 races")[0] == ["2 concern-shaped line(s), text withheld; severities: P0; locators: src/a.go:7"]'

# The whole point of the redesign: nothing the model wrote rides out on the
# unstructured path, so no denylist has to be complete.
row "unstructured relay carries no model prose at all" \
  '"supplied packet" not in excerpt("I read the supplied packet.\nP0 auth bypass")[0][0] and "auth bypass" not in excerpt("I read the supplied packet.\nP0 auth bypass")[0][0]'
row "unstructured relay leaks no credential of any shape" \
  'all(secret not in excerpt("P1 Bearer %s exposed" % secret)[0][0] for secret in ("hunter2", "secretsecret", "abc123def456"))'
row "unstructured relay is flagged as reduced" \
  'excerpt("P1 in the retry path")[1] is True'

# Row 9: a one-line JSON verdict splits per concern instead of clipping mid-word.
# Found by the first real gate run this helper instrumented: the reviewer answered
# in one line of JSON and the excerpt came back as a single 200-char fragment.
row "row9 json verdict splits per concern" \
  'excerpt("{\"status\":\"findings\",\"concern_results\":[{\"concern\":\"correctness\",\"conclusion\":\"first conclusion here\"},{\"concern\":\"safety\",\"conclusion\":\"second conclusion here\"}],\"findings\":[]}") == (["correctness: first conclusion here", "safety: second conclusion here"], False)'

row "row9b json findings become their own lines" \
  'excerpt("{\"status\":\"findings\",\"findings\":[{\"severity\":\"P0\",\"file\":\"a.py\",\"line\":3,\"failure_path\":\"boom\",\"smallest_fix\":\"x\"}]}") == (["P0 a.py 3 boom"], False)'

row "row9c malformed json falls back to the withheld summary" \
  'excerpt("{not json at all P1 here")[0] == ["1 concern-shaped line(s), text withheld; severities: P1"]'

# --- reason detail bound --------------------------------------------------
row "reason detail flattens and bounds client text" \
  'ce.bounded_reason_detail("a\nb  c") == "a b c" and ce.bounded_reason_detail("") == "(no message)" and len(ce.bounded_reason_detail("word " * 300)) == ce.MAX_REASON_DETAIL_CHARS + 1'

# An error item can quote the frozen packet, so relayed text is redacted before
# it reaches a durable evidence row (reviewer finding on this change).
row "reason detail redacts urls" \
  '"https" not in ce.bounded_reason_detail("failed calling https://internal.example/api/x?k=1")'
row "reason detail redacts credential assignments" \
  '"hunter2" not in ce.bounded_reason_detail("config had password=hunter2 set")'
row "reason detail redacts long opaque tokens" \
  '"AKIAIOSFODNN7EXAMPLEQQQQQQQQQQQQQQQQ" not in ce.bounded_reason_detail("key AKIAIOSFODNN7EXAMPLEQQQQQQQQQQQQQQQQ rejected")'
row "reason detail redacts deep filesystem paths" \
  '"/opt/example/nested" not in ce.bounded_reason_detail("cannot read /opt/example/nested/deep/thing")'
row "reason detail keeps the class name readable" \
  '"skills context budget" in ce.bounded_reason_detail("Skill descriptions were shortened to fit the skills context budget.")'

# The excerpt is the larger relayed channel and gets the same redaction as the
# diagnostic field (reviewer finding on this change). Both plain matched lines
# and structure-derived lines go through it.
row "excerpt redacts credentials on a plain matched line" \
  '"hunter2" not in excerpt("P1 password=hunter2 leaked here")[0][0]'
row "excerpt keeps the severity and locator readable" \
  '"P1" in excerpt("P1 src/a.py:3 password=hunter2")[0][0]'
row "excerpt redacts urls on a matched line" \
  '"internal.example" not in excerpt("P2 see https://internal.example/x for detail")[0][0]'
row "excerpt redacts inside structured concern lines" \
  '"hunter2" not in excerpt("{\"status\":\"findings\",\"concern_results\":[{\"concern\":\"safety\",\"conclusion\":\"packet had password=hunter2 inline\"}]}")[0][0]'
row "excerpt redacts inside structured finding lines" \
  '"hunter2" not in excerpt("{\"status\":\"findings\",\"findings\":[{\"severity\":\"P0\",\"file\":\"a.py\",\"line\":1,\"failure_path\":\"password=hunter2\",\"smallest_fix\":\"x\"}]}")[0][0]'

# --- CLI contract used by the shell wrappers ------------------------------
cli_out="$(printf 'I read it.\nP2 stale cache at src/x.py:9\n' | python3 "$DIR/concern_excerpt.py" 2>/dev/null)"
check "CLI reports concern evidence on stdin input" \
  '[ -n "$cli_out" ] && python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d[\"concern_evidence\"] is True and d[\"concern_excerpt\"] == [\"1 concern-shaped line(s), text withheld; severities: P2; locators: src/x.py:9\"] else 1)" "$cli_out"'

clean_out="$(printf 'I am unable to comply.\n' | python3 "$DIR/concern_excerpt.py" 2>/dev/null)"
check "CLI reports no concern evidence on clean refusal" \
  '[ -n "$clean_out" ] && python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d[\"concern_evidence\"] is False and d[\"concern_excerpt\"] == [] else 1)" "$clean_out"'

# --- parser payload wiring ------------------------------------------------
payload_probe() {
  DIR="$DIR" python3 - "$1" <<'PY' 2>/dev/null
import argparse
import os
import sys

sys.path.insert(0, os.environ["DIR"])
import parse_cli_review as p  # noqa: E402

args = argparse.Namespace(
    client="codex", mode="review", reviewer_family="openai",
    provider="openai", model=None,
)
payload = p.invalid_model_output(args, "review verdict violated the output contract", sys.argv[1])
print(bool(eval(os.environ["EXPR"])))
PY
}

pcheck() {
  local out
  out="$(EXPR="$3" payload_probe "$2")"
  check "$1" "[ \"$out\" = True ]"
}

pcheck "parser stop payload carries the excerpt" \
  'P0 auth bypass at src/a.go:7' \
  'payload["concern_evidence"] is True and payload["concern_excerpt"] == ["1 concern-shaped line(s), text withheld; severities: P0; locators: src/a.go:7"]'

pcheck "parser stop payload still refuses to cascade" \
  'P0 auth bypass at src/a.go:7' \
  'payload["cascade_eligible"] is False and payload["reason_code"] == "invalid_model_output"'

pcheck "parser omits excerpt fields when there is no concern evidence" \
  'I am unable to comply.' \
  'payload["concern_evidence"] is False and "concern_excerpt" not in payload and payload["cascade_eligible"] is True'

pcheck "parser flags a truncated excerpt" \
  "$(python3 -c 'print("\n".join("P1 finding %d" % i for i in range(40)))')" \
  'payload["concern_excerpt_truncated"] is True and payload["concern_excerpt"][0].startswith("40 concern-shaped line(s)")'

# --- wrapper wiring -------------------------------------------------------
check "claude wrapper feeds its concern stop through the shared helper" \
  'grep -q "concern_excerpt.py" "$DIR/claude_review.sh"'
check "claude wrapper no longer stops without an excerpt" \
  'grep -A8 "Claude returned concern evidence" "$DIR/claude_review.sh" | grep -q "concern_excerpt"'
# Either branch of the Claude stop must be scanned: the reply text (concern regex)
# or the raw output ("concern_results"). Scanning one leaves the other empty.
check "claude wrapper scans both files that can trip its stop" \
  'grep -q "concern_excerpt.py\" \"\$reply_text_file\" \"\$output_file\"" "$DIR/claude_review.sh"'
check "codex item-level error names the underlying message" \
  'grep -q "bounded_reason_detail(message)" "$DIR/parse_cli_review.py"'
# Untrusted client text must not land in `reason`, which consumers display and
# compare; it gets its own labelled field.
check "client diagnostic is a separate field, not the reason string" \
  'grep -q "payload\[\"client_diagnostic\"\] = bounded_reason_detail(message)" "$DIR/parse_cli_review.py"'

# The benign skills-context-budget notice must match by shape. Pinning its exact
# sentence is what took every Codex lane down when upstream dropped "2%".
benign_probe() {
  DIR="$DIR" python3 - "$1" <<'PY' 2>/dev/null
import os
import sys

sys.path.insert(0, os.environ["DIR"])
import parse_cli_review as p  # noqa: E402

print(bool(p.is_benign_codex_error(sys.argv[1])))
PY
}
check "benign notice matches the current CLI wording" \
  '[ "$(benign_probe "Skill descriptions were shortened to fit the skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest.")" = True ]'
check "benign notice still matches the older 2% wording" \
  '[ "$(benign_probe "Skill descriptions were shortened to fit the 2% skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest.")" = True ]'
check "benign matcher does not swallow a real error item" \
  '[ "$(benign_probe "Sandbox denied write to /etc/passwd; skills context budget unaffected")" = False ]'
# Prefix-only matching would let a crafted item append arbitrary content and
# still be waved through as benign (challenge finding on this change).
check "benign matcher rejects an over-long smuggled tail" \
  '[ "$(benign_probe "Skill descriptions were shortened to fit the skills context budget. $(python3 -c "print(\"pad \" * 80)")")" = False ]'

# Scheme-prefixed credentials put a space before the secret; an assignment-only
# pattern redacts the label and leaks the token (challenge finding).
row "redaction covers bearer-scheme credentials" \
  '"hunter2" not in ce.redact_untrusted("Authorization: Bearer hunter2")'
row "excerpt redacts bearer-scheme credentials" \
  '"abc123def456" not in excerpt("P1 Authorization: Bearer abc123def456 rejected")[0][0]'
# Over-redaction is the mirror failure and destroys the diagnostic value the
# excerpt exists for (third-reviewer finding). Both directions are asserted.
row "redaction leaves benign security prose intact" \
  'ce.redact_untrusted("P1 token validation bypassed here") == "P1 token validation bypassed here"'
row "redaction still catches a credential-shaped value" \
  '"abc123def456" not in ce.redact_untrusted("token abc123def456")'
# `\b` does not fire inside `client_secret` (`_` is a word char) — challenge finding.
row "redaction covers underscored key names" \
  '"hunter2" not in ce.redact_untrusted("OAuth client_secret=hunter2")'
row "excerpt redacts underscored key names" \
  '"hunter2" not in excerpt("P1 OAuth client_secret=hunter2 in packet")[0][0]'
# A free tail let a real fault ride along behind the benign prefix — review finding.
check "benign matcher rejects a fault smuggled behind the advisory prefix" \
  '[ "$(benign_probe "Skill descriptions were shortened to fit the skills context budget. Sandbox denied required access")" = False ]'
# Third round on this predicate: any free tail is a smuggling surface, so the
# whole advisory must match. An upstream reword now fails loudly instead.
check "benign matcher rejects a fault smuggled mid-sentence" \
  '[ "$(benign_probe "Skill descriptions were shortened to fit the skills context budget. Codex can still see every skill, but sandbox denied required access")" = False ]'
# A short credential after an auth scheme must not survive on value length.
row "redaction covers a short bearer value" \
  '"hunter2" not in ce.redact_untrusted("Authorization: Bearer hunter2")'
row "excerpt redacts a short bearer value" \
  '"hunter2" not in excerpt("P1 Authorization: Bearer hunter2 accepted")[0][0]'

echo '----'
if [ "$fails" -eq 0 ]; then
  echo concern_excerpt_tests_ok
else
  echo "$fails FAILURES"
  exit 1
fi
