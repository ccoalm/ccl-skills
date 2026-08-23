set -uo pipefail
SKILL="$1"; ORIG="$(mktemp)"; cp "$SKILL" "$ORIG"
MUTATED=""
SKILL_REL="skills/skill-extraction-workflow/SKILL.md"
restore() {
  [ -f "$ORIG" ] || return 0
  if [ -n "$MUTATED" ]; then
    local now; now="$(shasum -a 256 "$SKILL" 2>/dev/null | cut -d' ' -f1)"
    if [ "$now" != "$MUTATED" ]; then echo "REFUSED_OVERWRITE"; return 1; fi
  fi
  cp "$ORIG" "$SKILL" || return 1
  MUTATED=""
}
printf '\nMUTATION\n' >> "$SKILL"; MUTATED="$(shasum -a 256 "$SKILL" | cut -d' ' -f1)"
printf '\nTHIRD_PARTY_EDIT\n' >> "$SKILL"      # 并发编辑
restore || echo "restore returned nonzero (expected)"
grep -q THIRD_PARTY_EDIT "$SKILL" && echo "并发编辑保住了: YES" || echo "并发编辑被吞: NO"
cp "$ORIG" "$SKILL"; rm -f "$ORIG"
