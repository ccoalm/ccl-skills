#!/bin/bash
# Regression test for run-bound-round.sh's fail-closed guards, inherited from the
# p3 round's 4 cases and extended for this round's embedded-surface cross-check:
# a structurally valid report must ALSO embed the correct descriptions_sha256
# (missing or wrong -> binding_valid=false, nonzero exit). Stubs the ruby
# evaluator via PATH; no model call.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
WRAP="$HERE/run-bound-round.sh"
BANK="$HERE/bank-single.jsonl"
WT="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
fail=0

# Resolve the real ruby BEFORE the fake one shadows PATH: the wrapper also uses
# ruby for its independent catalog recomputation, and the stub must intercept
# ONLY the evaluator invocation (first arg = script path), or it would blind the
# very cross-check under test.
REAL_RUBY="$(command -v ruby)" || { echo "FAIL: no real ruby found" >&2; exit 1; }

run() { PATH="$TMP/bin:$PATH" bash "$WRAP" "$1" "$BANK" "$2"; }

# The correct surface and catalog hashes, computed exactly like the wrapper
# does, so the "valid" stub can embed them (and the "wrong" stubs can corrupt
# each independently).
GOOD_SURFACE="$(
  {
    for f in "$WT"/skills/*/SKILL.md; do
      d=$(basename "$(dirname "$f")")
      printf '%s\t' "$d"
      grep -m1 '^description:' "$f"
    done
    cat "$BANK"
  } | shasum -a 256 | awk '{print $1}'
)"
GOOD_CATALOG="$(cd "$WT" && ruby -ryaml -rdigest -e '
  catalog = Dir[File.join("skills", "*", "SKILL.md")].sort.map do |path|
    name = File.basename(File.dirname(path))
    m = File.read(path).match(/\A---\s*\n(.*?)\n---\s*\n/m)
    next unless m
    desc = (YAML.safe_load(m[1]) rescue {})["description"].to_s.strip
    next if desc.empty?
    "### #{name}\n#{desc}"
  end.compact.join("\n\n")
  puts Digest::SHA256.hexdigest(catalog)
')"
# Result-set variants for the completeness check: full coverage of the bank ids
# (valid), a subset (missing), a duplicated id, and an extra unexpected id.
results_json() { # $1 = full|subset|duplicate|extra
  "$REAL_RUBY" -rjson -e '
    ids = File.readlines(ARGV[0]).map(&:strip).reject(&:empty?).map { |l| JSON.parse(l)["id"] }
    case ARGV[1]
    when "subset" then ids = ids[0..-2]
    when "duplicate" then ids << ids[0]   # append (not overwrite): overwrite degenerates to a valid full set on a single-case bank, silently blinding this probe
    when "extra" then ids << "zz-unexpected-case"
    end
    results = ids.map { |i| { "id" => i, "status" => "PASS", "selected" => "y" } }
    puts JSON.generate({ "tasks" => results.length, "pass" => results.length, "fail" => 0, "error" => 0, "results" => results })
  ' "$BANK" "$1"
}
report_body() { # $1 = descriptions sha, $2 = catalog sha, $3 = results variant
  body="$(results_json "$3")"
  printf '%s' "$body" | "$REAL_RUBY" -rjson -e '
    d = JSON.parse(STDIN.read)
    d["routing_surface"] = { "descriptions_sha256" => ARGV[0], "catalog_sha256" => ARGV[1] }
    puts JSON.generate(d)
  ' "$1" "$2"
}

write_stub() { # $1 = report JSON body to write at the --json path
  cat > "$TMP/bin/ruby" <<EOF
#!/bin/bash
case "\$1" in
  -*) exec "$REAL_RUBY" "\$@";;   # helper invocations (catalog hash) pass through
esac
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--json" ]; then printf '%s' '$1' > "\$a"; fi
  prev="\$a"
done
exit 0
EOF
  chmod +x "$TMP/bin/ruby"
}

write_silent_stub() { # evaluator exits 0 writing nothing; helpers pass through
  cat > "$TMP/bin/ruby" <<EOF
#!/bin/bash
case "\$1" in
  -*) exec "$REAL_RUBY" "\$@";;
esac
exit 0
EOF
  chmod +x "$TMP/bin/ruby"
}

# case 1: evaluator exits 0, writes nothing -> must fail closed
write_silent_stub
run 1 "$TMP/out-c1" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": false' "$TMP/out-c1/round-1.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case1: rc=$rc (missing evaluator output must not be accepted)"; fail=1
fi

# case 2: evaluator exits 0, writes malformed JSON -> must fail closed
write_stub '{not json'
run 2 "$TMP/out-c2" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": false' "$TMP/out-c2/round-2.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case2: rc=$rc (malformed evaluator output must not be accepted)"; fail=1
fi

# case 3: structurally valid report covering EVERY bank id WITH the correct
# embedded surface AND catalog -> passes
write_stub "$(report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full)"
run 3 "$TMP/out-c3" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": true' "$TMP/out-c3/round-3.json.binding.json" && [ "$rc" = "0" ]; then :; else
  echo "FAIL case3: rc=$rc (valid full-coverage output with matching bindings must pass)"; fail=1
fi

# case 4: outdir pre-seeded with an existing round file -> the wrapper refuses
# UP FRONT and leaves the artifact byte-identical with no sidecar written
# (immutability: the old flow could destroy valid concluded evidence by moving
# an invalid rerun over it before the validity legs ran — extension P1)
write_silent_stub
mkdir -p "$TMP/out-c4"
report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full > "$TMP/out-c4/round-4.json"
cp "$TMP/out-c4/round-4.json" "$TMP/c4-original.json"
run 4 "$TMP/out-c4" >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ] && cmp -s "$TMP/out-c4/round-4.json" "$TMP/c4-original.json" && [ ! -e "$TMP/out-c4/round-4.json.binding.json" ]; then :; else
  echo "FAIL case4: rc=$rc (a pre-existing round artifact must be refused untouched, with no sidecar)"; fail=1
fi

# case 5: full-coverage report but NO routing_surface -> must fail closed
write_stub "$(results_json full)"
run 5 "$TMP/out-c5" >/dev/null 2>&1; rc=$?
if grep -q '"embedded_matches_surface": false' "$TMP/out-c5/round-5.json.binding.json" \
   && grep -q '"binding_valid": false' "$TMP/out-c5/round-5.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case5: rc=$rc (a report without routing_surface must not be accepted)"; fail=1
fi

# case 6: full-coverage report with the WRONG embedded surface -> must fail
# closed (a report graded against different wording cannot bind to this round)
write_stub "$(report_body "0000000000000000000000000000000000000000000000000000000000000000" "$GOOD_CATALOG" full)"
run 6 "$TMP/out-c6" >/dev/null 2>&1; rc=$?
if grep -q '"embedded_matches_surface": false' "$TMP/out-c6/round-6.json.binding.json" \
   && grep -q '"binding_valid": false' "$TMP/out-c6/round-6.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case6: rc=$rc (a wrong embedded surface must not be accepted)"; fail=1
fi

# case 7: correct raw surface but WRONG graded-catalog hash -> must fail closed
# (the multiline-description hole both r1 lanes found: the raw first-line
# surface can agree while the graded catalog differs, so the catalog binding is
# load-bearing on its own)
write_stub "$(report_body "$GOOD_SURFACE" "0000000000000000000000000000000000000000000000000000000000000000" full)"
run 7 "$TMP/out-c7" >/dev/null 2>&1; rc=$?
if grep -q '"embedded_matches_catalog": false' "$TMP/out-c7/round-7.json.binding.json" \
   && grep -q '"binding_valid": false' "$TMP/out-c7/round-7.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case7: rc=$rc (a wrong embedded graded-catalog hash must not be accepted)"; fail=1
fi

# cases 8-10: the completeness check (r2 challenge P1) — a report whose result
# set is a SUBSET of the bank, carries a DUPLICATE id, or an UNEXPECTED id must
# fail closed even though every hash binding is correct.
for variant in subset duplicate extra; do
  case "$variant" in
    subset) n=8;; duplicate) n=9;; extra) n=10;;
  esac
  write_stub "$(report_body "$GOOD_SURFACE" "$GOOD_CATALOG" "$variant")"
  run "$n" "$TMP/out-c$n" >/dev/null 2>&1; rc=$?
  if grep -q '"results_match_bank": false' "$TMP/out-c$n/round-$n.json.binding.json" \
     && grep -q '"binding_valid": false' "$TMP/out-c$n/round-$n.json.binding.json" && [ "$rc" != "0" ]; then :; else
    echo "FAIL case$n: rc=$rc ($variant result set must not be accepted)"; fail=1
  fi
done

# case 11: round reservation already held -> the wrapper refuses before touching
# any artifact (chain r1a review P1: existence check + final mv are not atomic;
# mkdir-based reservation makes exactly one same-round invocation win). The
# pre-created lock simulates the losing side of the race deterministically.
write_stub "$(report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full)"
mkdir -p "$TMP/out-c11/.round-11.lock"
run 11 "$TMP/out-c11" >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ] && [ ! -e "$TMP/out-c11/round-11.json" ] && [ ! -e "$TMP/out-c11/round-11.json.binding.json" ]; then :; else
  echo "FAIL case11: rc=$rc (a held reservation must refuse with no round file and no sidecar)"; fail=1
fi

# case 12: sidecar write failure after the round file landed -> the wrapper
# must UN-LAND the round file and exit nonzero (chain r2 review P1: an
# unchecked redirection under set -uo pipefail without errexit reported
# success while leaving a sidecar-less concluded artifact). The sidecar heredoc
# is the wrapper's only NO-ARGUMENT cat; stub cat to fail exactly there while
# passing argument forms through (surface_hash pipes the bank snapshot by path).
write_stub "$(report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full)"
cat > "$TMP/bin/cat" <<EOF
#!/bin/bash
if [ "\$#" -eq 0 ]; then exit 1; fi
exec /bin/cat "\$@"
EOF
chmod +x "$TMP/bin/cat"
run 12 "$TMP/out-c12" >/dev/null 2>&1; rc=$?
rm -f "$TMP/bin/cat"
if [ "$rc" != "0" ] && [ ! -e "$TMP/out-c12/round-12.json" ] && [ ! -e "$TMP/out-c12/round-12.json.binding.json" ]; then :; else
  echo "FAIL case12: rc=$rc (a failed sidecar write must un-land the round file and exit nonzero)"; fail=1
fi

# case 13: partial pair (round file present, sidecar absent — the SIGKILL
# window shape) -> the wrapper refuses with the recovery message, touches
# nothing, and writes no sidecar (chain r3 review P2)
write_stub "$(report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full)"
mkdir -p "$TMP/out-c13"
report_body "$GOOD_SURFACE" "$GOOD_CATALOG" full > "$TMP/out-c13/round-13.json"
cp "$TMP/out-c13/round-13.json" "$TMP/c13-original.json"
out13="$(run 13 "$TMP/out-c13" 2>&1)"; rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out13" | grep -q "partial pair" \
   && cmp -s "$TMP/out-c13/round-13.json" "$TMP/c13-original.json" && [ ! -e "$TMP/out-c13/round-13.json.binding.json" ]; then :; else
  echo "FAIL case13: rc=$rc (a partial pair must be refused untouched with the recovery message)"; fail=1
fi

if [ "$fail" = "0" ]; then echo "PASS: all 13 cases"; else echo "FAILURES present"; fi
exit $fail
