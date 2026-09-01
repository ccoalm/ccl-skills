#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"

if [[ ! -d "$root" ]]; then
  echo "ccl_skill_root_not_found: $root" >&2
  exit 2
fi

if [[ ! -x "$root/skills/skill-extraction-workflow/scripts/validate-skill.sh" ]]; then
  echo "missing_validate_script: $root/skills/skill-extraction-workflow/scripts/validate-skill.sh" >&2
  exit 2
fi

for required_cmd in ruby rg git; do
  if ! command -v "$required_cmd" >/dev/null 2>&1; then
    echo "missing_required_command: $required_cmd" >&2
    exit 2
  fi
done

resolve_checker_scripts_dir() {
  local checker_source="$1"
  local checker_target
  local checker_hops=0

  while [[ -L "$checker_source" ]]; do
    checker_hops=$((checker_hops + 1))
    if (( checker_hops > 8 )); then
      return 1
    fi
    checker_target="$(readlink "$checker_source")"
    if [[ "$checker_target" == /* ]]; then
      checker_source="$checker_target"
    else
      checker_source="$(dirname "$checker_source")/$checker_target"
    fi
  done

  cd "$(dirname "$checker_source")" && pwd -P
}

"$root/skills/skill-extraction-workflow/scripts/validate-skill.sh" "$root/skills"

ruby -ryaml -e '
root = ARGV.fetch(0)
skill_files = Dir[File.join(root, "skills", "*", "SKILL.md")].sort
skills = skill_files.map { |path| File.basename(File.dirname(path)) }
abort "no_ccl_skills_found: #{root}" if skills.empty?

changed_entrypoints = []
begin
  if system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    base = ENV.fetch("CCL_SKILL_BASE_REF", "").strip
    if base.empty?
      upstream_ref = IO.popen(["git", "-C", root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", err: File::NULL], &:read).strip
      base = upstream_ref.empty? ? "origin/main" : upstream_ref
    end
    merge_base = IO.popen(["git", "-C", root, "merge-base", base, "HEAD"], &:read).strip
    changed_paths = []
    changed_paths.concat(IO.popen(["git", "-C", root, "diff", "--name-only", merge_base, "HEAD"], &:read).lines.map(&:strip)) unless merge_base.empty?
    changed_paths.concat(IO.popen(["git", "-C", root, "diff", "--name-only"], &:read).lines.map(&:strip))
    changed_paths.concat(IO.popen(["git", "-C", root, "diff", "--cached", "--name-only"], &:read).lines.map(&:strip))
    changed_paths.concat(IO.popen(["git", "-C", root, "ls-files", "--others", "--exclude-standard", "--", "skills/*/SKILL.md"], &:read).lines.map(&:strip))
    changed_entrypoints = changed_paths.map { |path| path[%r{\Askills/[^/]+/SKILL\.md\z}] }.compact.uniq
  end
rescue StandardError => e
  warn "entrypoint_recommended_size_changed_file_scan_skipped: #{e.class.name} #{e.message.lines.first.to_s.strip}"
end

# Catalog contract. docs/SKILLS.md is the single authoritative human catalog and
# agent-context/session-start.md is the always-on entry routing layer; without a
# gate binding them they drift apart on the next skill added, and a drifting
# hand-maintained skill index is the one artifact this workflow tells you not to
# build. Rows are anchored on their own header (- `name` `entry|leaf` — ...), not
# on a loose backtick scan: a loose scan counts a name mentioned in some OTHER
# entry redirect as coverage, so deleting a skill row went undetected.
catalog = File.join(root, "docs", "SKILLS.md")
catalog = File.join(root, "README.md") unless File.file?(catalog)
bootstrap_path = File.join(root, "agent-context", "session-start.md")
skill_token = /\A[a-z0-9]+(?:-[a-z0-9]+)+\z/
catalog_bad = []
if File.file?(catalog)
  catalog_lines = File.readlines(catalog)
  rows = []
  catalog_lines.each_with_index do |line, idx|
    header = line.match(/\A- `([a-z0-9-]+)` `(entry|leaf)` /)
    next unless header
    rows << { name: header[1], kind: header[2], use: line, skip: catalog_lines[idx + 1].to_s }
  end
  # One format, no compatibility branch. The old loose backtick scan counted a name
  # mentioned in some OTHER row as coverage, so it could not see a deleted row --
  # keeping it alongside the contract would just preserve the hole it created.
  if rows.empty?
    catalog_bad << "skill_catalog_missing_markers: #{catalog} carries no `name` `entry|leaf` rows"
    catalog_bad << "  the catalog format is the contract: each skill needs one row plus a 不用 line beneath it"
  end

  # Initialize on every path. The routing block below lives in the else-branch, so
  # today nothing reads these when rows is empty -- but only because catalog_bad is
  # non-empty there and short-circuits the reader. That is one edit away from a
  # NameError, so do not leave it resting on an unrelated branch staying non-empty.
  names = []
  entry_names = []
  entry_coverage_unevaluated = false
  unless rows.empty?
  names = rows.map { |row| row[:name] }
  missing = skills - names
  extra = names - skills
  duplicated = names.select { |name| names.count(name) > 1 }.uniq
  unless missing.empty? && extra.empty? && duplicated.empty?
    catalog_bad << "skill_catalog_map_mismatch"
    catalog_bad << "  missing_in_catalog=#{missing.join(",")}" unless missing.empty?
    # Live check now: the previous one filtered candidates down to real skills
    # first, so this could never fire.
    catalog_bad << "  extra_in_catalog=#{extra.join(",")}" unless extra.empty?
    catalog_bad << "  duplicated_in_catalog=#{duplicated.join(",")}" unless duplicated.empty?
  end

  rows.each do |row|
    # Two lines per skill: when to use it, and when to use something else. The
    # second one is the part that only ever existed inside a description Skip
    # clause, invisible to a human reading the catalog.
    # Anchor on the dash-introduced clause: a bare include?("用：") is satisfied by
    # 不用：, so a row whose only clause is a redirect would pass the two-line
    # contract while never saying when to USE the skill.
    unless row[:use].match?(/—\s*用：/)
      catalog_bad << "skill_catalog_missing_use_line: #{row[:name]}"
    end
    unless row[:skip].match?(/\A\s+- 不用：/)
      catalog_bad << "skill_catalog_missing_skip_line: #{row[:name]}"
      next
    end
    row[:skip].scan(/`([a-z0-9-]+)`/) do |match|
      target = match[0]
      next unless target.match?(skill_token)
      next if skills.include?(target)
      catalog_bad << "skill_catalog_dangling_pointer: #{row[:name]} redirects to #{target}"
    end
  end

  entry_names = rows.select { |row| row[:kind] == "entry" }.map { |row| row[:name] }
  # The routing layer covers the entry set only. Leaf skills are reached through
  # their owner, so putting them in an every-session injection is pure token cost.
  # Fail closed. Marking a skill entry is a claim that the always-on layer routes to
  # it, so a missing layer file means that claim was never evaluated -- skipping here
  # would print contract_ok over an unverified assertion. Other checks in this script
  # degrade to skipped-missing for the same file; this one cannot, because it is the
  # one that asserts the coverage.
  # Do not fail, and do not abort. This script only runs against this repository
  # (Makefile, AGENTS.md, .githooks/pre-push, the opencode commands; install-gates.sh
  # does not ship it), so a checkout without the layer is a fixture, not a deployment.
  # The reason to keep going is that consumers read the later sections *_done markers
  # to tell "checked and clean" from "never ran", and an early exit masks all of them.
  # What this must not do is read as clean:
  # marking a skill entry claims the always-on layer routes to it, and with no layer
  # that claim was never evaluated. Same honesty shape as the size-gate
  # *_unevaluated token and sync_pointer_skipped -- skip is not a pass.
  entry_coverage_unevaluated = !entry_names.empty? && !File.file?(bootstrap_path)
  if entry_coverage_unevaluated
    puts "skill_catalog_entry_coverage_unevaluated: #{bootstrap_path} is absent, so entry coverage for #{entry_names.length} entry skills was NOT evaluated — this is not a pass"
  end
  if File.file?(bootstrap_path)
    region = File.read(bootstrap_path)[/ccl:entry-routing:start -->(.*?)<!-- ccl:entry-routing:end/m, 1]
    if region.nil?
      catalog_bad << "skill_bootstrap_region_missing: agent-context/session-start.md has no ccl:entry-routing markers"
    else
      routed = region.scan(/\*\*([a-z0-9-]+)\*\*/).flatten.select { |name| name.match?(skill_token) }.uniq
      uncovered = entry_names - routed
      dangling = routed - skills
      catalog_bad << "skill_bootstrap_entry_uncovered: #{uncovered.join(",")}" unless uncovered.empty?
      catalog_bad << "skill_bootstrap_dangling_pointer: #{dangling.join(",")}" unless dangling.empty?
      # entry means: this skill has a routing rule in the resident layer. A leaf named
      # there contradicts its own mark, and the mark is what the catalog tells readers.
      leaf_in_region = routed & (names - entry_names)
      catalog_bad << "skill_bootstrap_leaf_in_region: #{leaf_in_region.join(",")} — routed in the always-on layer but marked leaf; mark them entry or remove the routing rule" unless leaf_in_region.empty?
    end
  end

  end

  # Do NOT exit here. A catalog failure must fail the gate, but aborting the program
  # masks every later section and its *_done marker -- consumers read those markers to
  # tell "checked and clean" from "never ran", so a masked section reports as neither.
  # The findings ride the terminal bad list below instead.
  if catalog_bad.empty?
    puts "skill_catalog_map_ok"
    unless entry_coverage_unevaluated
      puts "skill_catalog_contract_ok entries=#{rows.length} entry=#{entry_names.length} leaf=#{rows.length - entry_names.length}"
    end
  end
else
  puts "skill_catalog_map_skipped"
end

bad = catalog_bad.dup
warns = []
overlay_keys = %w[display_name short_description default_prompt]
skill_files.each do |path|
  text = File.read(path)
  body = text.sub(/\A---\n.*?\n---\n/m, "")
  frontmatter_raw = text[/\A---\n(.*?)\n---\n/m, 1].to_s
  dir = File.basename(File.dirname(path))
  begin
    fm = YAML.safe_load(frontmatter_raw, aliases: false) || {}
  rescue Psych::Exception => e
    bad << "#{dir}: yaml_parse_error #{e.class.name.split("::").last} #{e.message.lines.first.to_s.strip}"
    next
  end
  name = fm["name"].to_s.strip
  desc = fm["description"].to_s.strip
  rel_path = path.start_with?(root + "/") ? path[(root.length + 1)..] : path.sub(%r{\A\./}, "")
  changed_entrypoint = changed_entrypoints.include?(rel_path)
  bad << "#{dir}: name_mismatch frontmatter=#{name}" unless name == dir
  bad << "#{dir}: empty_description" if desc.empty?
  # OpenCode skill routing relies heavily on the frontmatter description. Long
  # or multi-line descriptions dilute the trigger signal and can be truncated in
  # the host skill listing, so keep detailed routing rules in the body instead.
  bad << "#{dir}: description_too_long_for_opencode #{desc.length}/800" if desc.length > 800
  bad << "#{dir}: description_multiline_for_opencode" if frontmatter_raw.match?(/^description:\s*[>|]/)
  warns << "#{dir}: description_long_for_opencode #{desc.length}/800" if desc.length > 600 && desc.length <= 800

  long_lines = body.lines.each_with_index.map do |line, idx|
    line_length = line.chomp.length
    [idx + 1, line_length] if line_length > 600
  end.compact
  # Report the true largest hotspots; line number is a deterministic tie-breaker.
  longest_lines = long_lines.sort_by { |line_number, line_length| [-line_length, line_number] }.first(5).map do |line_number, line_length|
    "L#{line_number}:#{line_length}"
  end
  warns << "#{dir}: entrypoint_body_large #{body.length}/50000" if body.length > 50000
  if changed_entrypoint
    warns << "#{dir}: entrypoint_body_below_recommended_for_changed_file #{body.length}/1000 verify_trigger_owner_hard-stop_pointer_do_not_pad" if body.length < 1000
    warns << "#{dir}: entrypoint_body_above_recommended_for_changed_file #{body.length}/5000" if body.length > 5000
  end
  warns << "#{dir}: entrypoint_long_lines #{longest_lines.join(",")}" unless long_lines.empty?

  # Codex overlay parity: every skill ships agents/openai.yaml so the Codex side
  # gets a $skill interface (display_name / short_description / default_prompt),
  # matching the Claude side. Missing or incomplete overlay = two-end drift.
  overlay = File.join(File.dirname(path), "agents", "openai.yaml")
  if !File.file?(overlay)
    bad << "#{dir}: missing_codex_overlay agents/openai.yaml"
  else
    begin
      oy = YAML.safe_load(File.read(overlay), aliases: false) || {}
      iface = oy["interface"]
      if !iface.is_a?(Hash)
        bad << "#{dir}: codex_overlay_missing_interface"
      else
        missing = overlay_keys.reject { |k| !iface[k].to_s.strip.empty? }
        bad << "#{dir}: codex_overlay_incomplete missing=#{missing.join(",")}" unless missing.empty?
      end
    rescue Psych::Exception => e
      bad << "#{dir}: codex_overlay_yaml_error #{e.message.lines.first.to_s.strip}"
    end
  end
end

warns.each { |item| warn "  WARN #{item}" } unless warns.empty?

if bad.empty?
  puts "frontmatter_name_description_ok"
  puts "codex_overlay_ok"
else
  warn "frontmatter_name_description_failed"
  bad.each { |item| warn "  #{item}" }
  exit 1
end
' "$root"

# Public DOMAIN word list: a weak-proxy FALLBACK, not the authoritative R0 gate.
# The real invariant — "this public text identifies one specific organization or
# project" — is not decidable by a public regex, which is why the private alias
# audit (ALIAS_AUDIT_CMD -> r0_status=private-ok) is authoritative and this list
# only covers environments without it. Consequence, stated rather than fought:
# these terms are ANOTHER domain's ordinary vocabulary, so they decay — a term
# outlives the project it proxied for and then only produces false positives.
# Maintain by RETIREMENT, not by growth: when a term no longer proxies anything
# live, delete it (quantify current hits first, and keep a retained-term control
# so the scan is proven still able to fail). Do not add generic technical words.
# Both directions are pinned by test_entrypoint_domain_scan_terms.sh. Long digit
# runs are scanned separately so canonical public DOI/W3C identifiers are not
# mistaken for private object IDs while an unrelated ID on the same line still
# fails closed.
if leak_output="$(rg -n 'code\.[[:alnum:].-]+|figma\.com/files|\x{6559}\x{5e08}|\x{5b66}\x{751f}|\x{8003}\x{8bd5}|\x{5b66}\x{6821}|\x{9605}\x{5377}|\x{51fa}\x{5377}|\x{5b66}\x{60c5}' "$root"/skills/*/SKILL.md "$root"/skills/*/references/*.md 2>/dev/null)"; then
  echo "$leak_output"
  echo "entrypoint_or_reference_domain_scan_failed" >&2
  exit 1
else
  rg_status=$?
  if [[ "$rg_status" -ne 1 ]]; then
    echo "entrypoint_scan_error: rg exited $rg_status" >&2
    exit 1
  fi
fi

if ! long_digit_output="$(ruby -e '
  allowed_url = %r{https://(?:
    doi\.org/10\.[0-9]{4,9}/(?<doipayload>[A-Za-z0-9._;()/:+\-]+)
    |
    www\.w3\.org/community/reports/[a-z0-9-]+/CG-FINAL-[A-Za-z0-9._-]*(?<w3cdate>[0-9]{8})/?
  )}ix
  ARGV.each do |path|
    next unless File.file?(path)
    File.foreach(path).with_index(1) do |line, line_number|
      allowed_spans = []
      line.to_enum(:scan, allowed_url).each do
        match = Regexp.last_match
        url = match[0]
        next if url.include?("?") || url.include?("#")
        # The allowlist is shape-only (no registrant validation), so a
        # fabricated DOI-shaped wrapper could otherwise launder any private
        # numeric ID. A span grants exemption only when its identifier
        # payload (the DOI suffix after the registrant slash, or the W3C
        # report date) carries no merged digit run above 9 digits, where a
        # merged run joins digit groups across one or MORE consecutive
        # punctuation separators — every punctuation char the DOI payload
        # charset accepts, so no accepted punctuation can split an ID into
        # exempt halves. Letters stay run boundaries because real DOI
        # suffixes legitimately interleave them (s15516709cog1202_4). This
        # keeps real citations green (10.1038/35057062 has an 8-digit
        # payload; the registrant prefix is bounded to 9 digits by shape)
        # while a split or padded identifier such as 123456789-123456789,
        # 20260830--123456, or 123456789+123456789 voids its span entirely.
        payload_name = match[:doipayload] ? :doipayload : :w3cdate
        payload = line[match.begin(payload_name)...match.end(payload_name)]
        payload_ok = payload.scan(/[0-9]+(?:[-._\/;():+]+[0-9]+)*/).all? do |run|
          run.delete("^0-9").length <= 9
        end
        next unless payload_ok
        # The exempt span is the identifier payload, not the whole URL: a
        # W3C report NAME has no business carrying a long digit run, so only
        # the trailing date is exempt there; a DOI suffix is the identifier
        # itself, so its whole payload is exempt once it passes the cap.
        allowed_spans << (match.begin(payload_name)...match.end(payload_name))
      end

      leaked = line.to_enum(:scan, /[0-9]{8,}/).any? do
        match = Regexp.last_match
        # Per-match cap: even inside a payload-clean span, a single raw run
        # above 9 digits (timestamp/snowflake scale) is never exempt.
        exempt = match[0].length <= 9 && allowed_spans.any? do |span|
          span.begin <= match.begin(0) && match.end(0) <= span.end
        end
        !exempt
      end
      puts "#{path}:#{line_number}:#{line.chomp}" if leaked
    end
  end
' "$root"/skills/*/SKILL.md "$root"/skills/*/references/*.md 2>&1)"; then
  echo "$long_digit_output" >&2
  echo "entrypoint_long_digit_scan_error" >&2
  exit 1
fi
if [[ -n "$long_digit_output" ]]; then
  echo "$long_digit_output"
  echo "entrypoint_or_reference_domain_scan_failed" >&2
  exit 1
fi
echo "entrypoint_and_reference_domain_scan_ok"

# Recurring anti-pattern scan: a TARGETED mechanical backstop (NOT a comprehensive
# detector) for the grep panel in
# skill-extraction-workflow/references/recurring-anti-patterns-checklist.md, which is
# otherwise only run from memory. It catches the one high-signal class with a written
# architectural rule and zero legitimate occurrences in product-agnostic skills:
# a framework's reserved envelope/base field NUMBER (the byted/Kitex base is always
# field 255) presented as a contract convention, plus bare `Base{...}` struct literals.
# The rule it enforces:
#   "Do not inherit a framework's reserved envelope/base field number as a contract
#    convention. New products should choose an explicit envelope field and document it."
#   (go-microservice-architecture/references/protobuf-contract-architecture.md)
# The comprehensive net stays the human/agent checklist + the dual-track challenge;
# this gate is the fast deterministic catch for the exact shape that has leaked before.
# Additional per-class mechanical gates may be added as a symptom recurs across 2+
# skills, mirroring the checklist's growth rule; do NOT bulk-copy the checklist here.
#
# `platform-service-connectivity` legitimately owns the canonical base struct (it frames
# these as named examples of a generic concept) and the checklist file defines the
# symptom — both are allowlisted by repo-relative PATH (not by match text, and not via
# any runtime env override: a security backstop must not be skippable from the caller's
# environment). Bare `base.Request` mentions are NOT flagged (legitimate routing-pointer
# uses exist). Scan surface includes SKILL.md, references, the Codex overlays, and README.
# Allowlist by ANCHORED repo-relative path: a trailing-slash entry is a directory
# prefix; any other entry is an exact file path (a bare basename would wrongly exempt
# a same-named file under another skill).
antipattern_allow_paths=( "skills/platform-service-connectivity/" "skills/skill-extraction-workflow/references/recurring-anti-patterns-checklist.md" )
antipattern_files=( "$root"/skills/*/SKILL.md "$root"/skills/*/references/*.md "$root"/skills/*/agents/*.yaml )
[[ -f "$root/README.md" ]] && antipattern_files+=( "$root/README.md" )
# rg stage-1 is a CANDIDATE net (lines with a base-token near `=`/`{`); the bash stage-2
# below confirms precisely. The gate is HIGH-PRECISION by design: it flags only the
# base-NAMED field bound to the reserved field number 255 — the byted/Kitex base
# convention that actually leaked (`base = 255`, `base.Request base = 255`,
# `baseResp = 255`), incl. case variants — plus a bare `Base {` struct literal.
# It deliberately does NOT flag:
#   - a bare reserved number `= 255` on a non-base field (exit codes, uint8/varchar 255);
#   - a base-named field bound to OTHER numbers (`base = 2 seconds` backoff math, etc);
#   - a base var holding 255 as a VALUE with a unit/decimal (`base = 255 ms`, `255.0`,
#     `255-byte`): the 255 must be terminated by a proto-ish boundary (closing backtick,
#     `;`, `,`, `)`, `]`, `}`) — exactly how every real leak appeared (inline-code
#     `` `…base = 255` `` or a `… = 255;` proto field decl) — not by a space+unit/decimal;
#   - `baseline = 3`/`database = 255` (the base token must be exactly `base`, `baseResp`,
#     or `base.<Word>`, never an arbitrary `base*` word).
# Renamed-field, non-255, non-terminated, and pure-prose variants are the accepted recall
# limit; the comprehensive net is the human/agent checklist + the dual-track challenge.
antipattern_candidate='\bbase[a-z0-9._]*[[:space:]]*[={]'
# Note: bash [[ =~ ]] is POSIX ERE — no `\b`. The trailing group is the proto-terminator
# set ( ` ; , ) ] } ); `)` is escaped so it does not close the group.
re_base_assign='(^|[^a-z0-9_])base(resp|\.[a-z0-9_]+)?[[:space:]]*=[[:space:]]*255(`|;|,|\)|]|})'
re_base_struct='(^|[^a-z0-9_])base[[:space:]]*\{'
if antipattern_raw="$(rg -ni "$antipattern_candidate" "${antipattern_files[@]}" 2>/dev/null)"; then
  antipattern_hits=""
  shopt -s nocasematch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip the known "$root/" prefix first so the path field is repo-relative and
    # colon-safe even if $root itself contains a colon; then split path:lineno:text.
    rel="${line#"$root"/}"
    hitpath="${rel%%:*}"
    rest="${rel#*:}"; linetext="${rest#*:}"
    skip=0
    for sub in "${antipattern_allow_paths[@]}"; do
      if [[ "$sub" == */ ]]; then
        [[ "$hitpath" == "$sub"* ]] && { skip=1; break; }
      else
        [[ "$hitpath" == "$sub" ]] && { skip=1; break; }
      fi
    done
    [[ "$skip" -eq 1 ]] && continue
    if [[ "$linetext" =~ $re_base_assign ]] || [[ "$linetext" =~ $re_base_struct ]]; then
      antipattern_hits+="$line"$'\n'
    fi
  done <<< "$antipattern_raw"
  shopt -u nocasematch
  if [[ -n "${antipattern_hits//[$'\n']/}" ]]; then
    printf '%s\n' "$antipattern_hits"
    echo "recurring_antipattern_scan_failed: one-organization reserved-field/base-struct convention above appears outside platform-service-connectivity; generalize it (name the platform's documented field without a hardcoded number) or route to that owner — see skill-extraction-workflow/references/recurring-anti-patterns-checklist.md" >&2
    exit 1
  fi
else
  antipattern_status=$?
  if [[ "$antipattern_status" -ne 1 ]]; then
    echo "recurring_antipattern_scan_error: rg exited $antipattern_status" >&2
    exit 1
  fi
fi
echo "recurring_antipattern_scan_ok"

# A variable expansion immediately followed by a multibyte character: bash folds
# those bytes into the NAME, so `$arg（可用…）` reads a variable literally called
# `arg（可用…）`. Under `set -u` the script aborts with an unbound-variable error;
# without it the value AND the punctuation silently vanish. It hides in error
# branches and summary lines nobody exercises by hand, so only a static scan finds
# it. This class was already mechanized in the repo — but only over the ```bash
# blocks of one reference doc, so the repo's OWN scripts were never covered and
# both live instances survived (scripts/install.sh usage error: aborts instead of
# printing usage; Makefile prune-cache summary: prints mojibake instead of the
# version). Widened here to every tracked shell script plus the Makefile.
fullwidth_var_exempt="skills/multi-perspective-research/scripts/test-public-data-acquisition-recipes.sh"
fullwidth_files=()
while IFS= read -r f; do
  [ "$f" = "$fullwidth_var_exempt" ] && continue
  fullwidth_files+=("$f")
done < <(git -C "$root" ls-files '*.sh' 2>/dev/null)
[ -f "$root/Makefile" ] && fullwidth_files+=("Makefile")
if [ "${#fullwidth_files[@]}" -gt 0 ]; then
  fullwidth_hits="$(cd "$root" && ruby -e '
ARGV.each do |path|
  next unless File.file?(path)
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    next if line.lstrip.start_with?("#")
    next unless line.match?(/\$[A-Za-z_][A-Za-z0-9_]*(?![A-Za-z0-9_])[^[:ascii:]]/)
    puts "#{path}:#{idx + 1}: #{line.strip}"
  end
end
' "${fullwidth_files[@]}" 2>&1)" || {
    echo "fullwidth_var_scan_error: scanner exited non-zero (fail-closed)" >&2
    exit 1
  }
  if [ -n "$fullwidth_hits" ]; then
    printf '%s\n' "$fullwidth_hits"
    echo "fullwidth_var_scan_failed: a variable expansion above is immediately followed by a multibyte character, so the shell reads it as part of the NAME; brace it as \${var}. Exempt by path only for deliberate negative fixtures." >&2
    exit 1
  fi
fi
echo "fullwidth_var_scan_ok (${#fullwidth_files[@]} files)"

# Anti-pattern 27 — repo/worktree identity decided by PATH SHAPE (see
# references/recurring-anti-patterns-checklist.md). A control that matches a git-dir
# against `*/worktrees/*` is predicating on the USER'S directory naming, not on git
# structure: a primary checkout living under a directory called `worktrees/` is misread
# as already-isolated, so an isolation/deny gate silently fails open. This promoted the
# checklist row to a gate because the class recurred twice (owner-dispatch state key,
# guard-edit-isolation deny bypass) within one day.
# Scope: executable shell under hooks/ and scripts/ — the surface where such a predicate
# makes a control decision. Excluded on purpose: `test_*.sh` / `test.sh` (a fixture
# legitimately asserts a git-dir CONTAINS the component, which is not a control
# decision), and WHOLE-LINE comments (the fix itself documents the banned spelling).
# A trailing comment or a string literal carrying the pattern IS flagged, deliberately:
# deciding "is this `#` a comment or part of a glob/string" needs a shell parser, and a
# half-parser is the kind of thing a later maintainer loosens after one false positive —
# which silently re-blinds the gate. The contract is therefore the simple checkable one:
# outside a whole-line comment, this literal must not appear in non-test shell here; put
# explanatory mentions on their own comment line (as these very lines do).
# The predicate requires a glob star on BOTH sides of the component, optionally quoted
# (`*/worktrees/*`, `*"/worktrees/"*`, `*'/worktrees/'*`) — that shape is a MATCH pattern,
# never an ordinary path, so a legitimate `rm -rf .work/worktrees/*` cleanup glob does not
# trip it. Matching bare `worktrees` + `*` instead would flag exactly such cleanup code.
# Recall limits — three, all deliberate and all stated so the contract is not overclaimed:
#   1. a fully dynamic pattern (`*"/$seg/"*`);
#   2. a pattern split across physical lines by a backslash continuation (the match is
#      per physical line; joining continuations first would move every reported line
#      number off the real source line, for a spelling nobody writes by accident);
#   3. `--absolute-git-dir` used as an identity key — the same call legitimately locates
#      the CURRENT worktree, so grepping it is false-positive-prone.
# Those stay checklist/challenge checks. This gate catches the literal spellings a
# developer writes by hand; it is not an obfuscation-proof barrier and does not claim to be.
# Traversal hardening — every leg here exists because the failure it prevents makes the
# gate print "ok" for a scan that did not happen, which is worse than no gate at all:
#   -print0/read -d ''  a newline in a file name would split into two non-existent paths
#                       and silently drop the real file
#   -L                  a symlinked hooks//scripts/ dir, or a symlinked .sh, is otherwise
#                       skipped entirely (`-type f` alone excludes symlinks)
#   find status check   a failed traversal (unreadable dir; a symlink loop where the find
#                       implementation reports one) must not read as "clean". Loop
#                       reporting is implementation-dependent — bfs was measured to be
#                       nondeterministic about it — so the pinned case is the unreadable
#                       dir; loops are caught only when find says so.
# Ordering is applied to the collected HITS, not the file list, so there is no `sort -z`
# portability assumption.
gid_hits=""
if [[ -d "$root/hooks" || -d "$root/scripts" ]]; then
  gid_list=$(mktemp "${TMPDIR:-/tmp}/ccl-skills-gid.XXXXXX") || { echo "git_identity_predicate_scan_error: mktemp failed" >&2; exit 1; }
  # Every normal and error path below removes this explicitly; the trap only covers a
  # signal or an unrelated `set -e` abort further down the checker.
  trap 'rm -f "${gid_list:-/dev/null}"' EXIT
  # Pass ONLY the roots that exist, so a non-zero find status always means a genuine walk
  # failure (symlink loop, unreadable dir) and never merely "one of the two is absent".
  # Gating the error on "both dirs exist" instead would silently accept a failed walk in
  # the common single-root repo — the same fail-open shape this gate exists to stop.
  gid_roots=()
  [[ -d "$root/hooks" ]] && gid_roots+=( "$root/hooks" )
  [[ -d "$root/scripts" ]] && gid_roots+=( "$root/scripts" )
  # if-guarded: under this script's `set -e`, a bare `find ...; rc=$?` would exit the
  # whole checker before the status is ever inspected (verified, not assumed).
  if find -L "${gid_roots[@]}" -name '*.sh' -type f -print0 > "$gid_list" 2>/dev/null; then
    gid_find_rc=0
  else
    gid_find_rc=$?
  fi
  if [[ "$gid_find_rc" -ne 0 ]]; then
    rm -f "$gid_list"
    echo "git_identity_predicate_scan_error: find exited $gid_find_rc walking ${gid_roots[*]#"$root"/} — the walk is INCOMPLETE, which is not the same as clean" >&2
    exit 1
  fi
  while IFS= read -r -d '' gid_file; do
    [[ -n "$gid_file" ]] || continue
    case "${gid_file##*/}" in test_*.sh|test.sh) continue ;; esac
    # A no-match is grep status 1; anything above that is a real scan error (file vanished
    # after find, unreadable, I/O). Swallowing those with `|| true` would print the ok
    # token for a scan that never happened — a clean result that means nothing.
    # Same `set -e` hazard: a plain `gid_out=$(grep ...)` exits the checker on the FIRST
    # no-match file (status 1), i.e. on virtually every run — the gate would never be
    # reached in production while every extracted-section probe stayed green.
    if gid_out="$(grep -nE '\*['"'"'"]?/worktrees/['"'"'"]?\*' "$gid_file" 2>/dev/null)"; then
      gid_rc=0
    else
      gid_rc=$?
    fi
    if [[ "$gid_rc" -gt 1 ]]; then
      rm -f "$gid_list"
      echo "git_identity_predicate_scan_error: grep exited $gid_rc while scanning ${gid_file#"$root"/} — unreadable or I/O failure means the result is UNKNOWN, not clean" >&2
      exit 1
    fi
    [[ "$gid_rc" -eq 0 ]] || continue
    while IFS= read -r gid_line; do
      [[ -n "$gid_line" ]] || continue
      gid_text="${gid_line#*:}"
      [[ "$gid_text" =~ ^[[:space:]]*# ]] && continue
      gid_hits+="${gid_file#"$root"/}:$gid_line"$'\n'
    done <<< "$gid_out"
  done < "$gid_list"
  rm -f "$gid_list"
  [[ -n "${gid_hits//[$'\n']/}" ]] && gid_hits="$(printf '%s' "$gid_hits" | sort)"$'\n'
fi
if [[ -n "${gid_hits//[$'\n']/}" ]]; then
  printf '%s' "$gid_hits"
  echo "git_identity_predicate_scan_failed: the lines above decide repo/worktree identity from a PATH NAME (\`*/worktrees/*\`), which the user's directory layout controls — a primary checkout under a \`worktrees/\`-named path is misread as isolated and the control fails open silently. Use git structure instead: identity => \`rev-parse --path-format=absolute --git-common-dir\`; is-linked-worktree => absolute-git-dir != common dir. See skill-extraction-workflow/references/recurring-anti-patterns-checklist.md (Anti-pattern 27)." >&2
  exit 1
fi
echo "git_identity_predicate_scan_ok"

# Anti-pattern 28 — process liveness decided by an EXISTENCE test that a corpse answers
# (see references/recurring-anti-patterns-checklist.md). A pid whose process has exited
# but has not been reaped is still in the process table: it answers `kill -0`, and its
# ppid still reads — as 1 once it is reparented. A check that concludes "alive" or
# "orphaned and alive" from existence alone therefore says yes about a corpse, while the
# verdict scans in the same suite exclude zombies and say gone — one process state, two
# answers, and a probe that reds while the code under test is behaving.
# Promoted from checklist to gate because the class recurred three times in CI on the
# abort-leak probe, each time on a different assertion, each time asserting the probe's
# environment rather than the suite.
# Scope: `test_*.sh` / `test.sh` under the repo — the surface where such a predicate is a
# TEST VERDICT rather than a signalling guard. Excluded on purpose: non-test shell (a
# `kill -0` before signalling asks about existence, which is the right question there),
# and WHOLE-LINE comments (this comment block names the banned spelling).
# The predicate is the orphan-oracle shape specifically: a `ps -o ppid=` read compared
# against init's pid on the same line. That shape has exactly one meaning — "has this
# been reparented, i.e. is it a live orphan" — so precision is high; a ppid read used to
# IDENTIFY a parent (the common use) is untouched. A process-state consult (`stat=` or a
# helper whose name ends in `_state`) within the window clears the line, which is the fix.
# Recall limits — stated so the contract is not overclaimed, per the checklist's
# promotion guidance (high precision plus a documented recall limit beats broad matching
# for a BLOCKING gate):
#   1. `while kill -0 "$pid"` watchdog loops are NOT flagged. Two exist here; both wait on
#      a direct child and `wait` for it immediately after, so the shell reaps it and the
#      loop ends — a narrower risk than the shape above, and forcing churn on them would
#      trade a real false-positive cost for an unproven gain.
#   2. a liveness branch spelled with a bare `kill -0` inside a loop BODY.
#   3. any dynamic or indirect spelling.
# Those stay checklist plus adversarial-challenge checks.
liveness_hits=""
liveness_list=$(mktemp "${TMPDIR:-/tmp}/ccl-skills-liveness.XXXXXX") || {
  echo "liveness_predicate_scan_error: mktemp failed" >&2; exit 1; }
# Guarded rather than the `${var:-/dev/null}` idiom: this trap is installed
# unconditionally, so an unset var would make the cleanup `rm -f /dev/null` — a no-op for
# an unprivileged user and a deleted device node for a root container. Never name a path
# in a removal that a fallback can turn into someone else's file.
liveness_scan_cleanup() {
  [ -n "${liveness_list:-}" ] && [ -e "${liveness_list:-}" ] && rm -f "$liveness_list"
  [ -n "${gid_list:-}" ] && [ -e "${gid_list:-}" ] && rm -f "$gid_list"
  return 0
}
trap liveness_scan_cleanup EXIT
# Same traversal hardening as Anti-pattern 27, and for the same reason: every leg here
# exists because its absence makes the gate print "ok" for a scan that did not happen.
if find -L "$root" -name '*.sh' -type f -print0 > "$liveness_list" 2>/dev/null; then
  liveness_find_rc=0
else
  liveness_find_rc=$?
fi
if [[ "$liveness_find_rc" -ne 0 ]]; then
  rm -f "$liveness_list"
  echo "liveness_predicate_scan_error: find exited $liveness_find_rc — the walk is INCOMPLETE, which is not the same as clean" >&2
  exit 1
fi
while IFS= read -r -d '' liveness_file; do
  [[ -n "$liveness_file" ]] || continue
  case "${liveness_file##*/}" in test_*.sh|test.sh) : ;; *) continue ;; esac
  # `[^=]*[^!=]=` rather than `.*=`: an unrestricted `.*` swallows the `!` of a `!=`, so
  # the negated assertion `[ "$(ps -o ppid= -p "$pid")" != "1" ]` — which checks a process
  # is NOT reparented, the opposite of the banned oracle — was reported as a violation.
  # A false positive on a blocking gate is the failure this checklist's promotion
  # guidance weighs heaviest, because it is what gets a gate loosened until it catches
  # nothing.
  if liveness_out="$(grep -nE 'ps[[:space:]]+-o[[:space:]]+ppid=[^=]*[^!=]=[[:space:]]*"?1"?[[:space:]]*\]' "$liveness_file" 2>/dev/null)"; then
    liveness_rc=0
  else
    liveness_rc=$?
  fi
  if [[ "$liveness_rc" -gt 1 ]]; then
    rm -f "$liveness_list"
    echo "liveness_predicate_scan_error: grep exited $liveness_rc while scanning ${liveness_file#"$root"/} — unreadable or I/O failure means the result is UNKNOWN, not clean" >&2
    exit 1
  fi
  [[ "$liveness_rc" -eq 0 ]] || continue
  while IFS= read -r liveness_line; do
    [[ -n "$liveness_line" ]] || continue
    liveness_no="${liveness_line%%:*}"
    liveness_text="${liveness_line#*:}"
    [[ "$liveness_text" =~ ^[[:space:]]*# ]] && continue
    # Window clear: a process-state consult within two lines either side is the fix, so
    # a corrected site stops being reported without needing a waiver marker.
    liveness_lo=$(( liveness_no > 2 ? liveness_no - 2 : 1 ))
    liveness_hi=$(( liveness_no + 2 ))
    # Whole-line comments are dropped before the window is inspected: a prose mention
    # such as a TODO naming the helper would otherwise clear a real violation beside it,
    # and the gate would print ok for a line it had actually found. The waiver must be
    # CODE that consults process state, not a note saying someone should.
    # Only WHOLE-LINE comments are dropped, matching how the hit line itself is filtered.
    # Stripping trailing comments would need to decide whether a `#` opens a comment or
    # belongs to `${var#prefix}`, which needs a shell parser — the same call Anti-pattern
    # 27 makes above. Recall limit: a mention in a TRAILING comment can still clear the
    # window; the checklist row records it.
    liveness_win="$(sed -n "${liveness_lo},${liveness_hi}p" "$liveness_file" 2>/dev/null |
                      grep -vE '^[[:space:]]*#' || true)"
    # A direct `ps -o stat=` in the window is the consult itself. Anchored on `-o stat=`
    # rather than bare `stat=`: an unrelated assignment such as `stat=unknown` is not a
    # process-state read, and accepting it was the fourth way this waiver was found to
    # clear a real hit.
    if printf '%s' "$liveness_win" | grep -qE '\-o[[:space:]]*stat='; then
      continue
    fi
    # Otherwise the window may CALL a state helper — but only one this file actually
    # defines and which itself consults process state. Accepting any `*_state` token
    # made an unrelated `record_state "$pid"` read as remediation and skipped a real
    # hit, which is a hole rather than a stated recall limit.
    # The file must also actually consult process state somewhere, so a file with no
    # `stat=` at all cannot be cleared by a bookkeeping helper that merely ends in
    # `_state`. Recall limit: a file that separately defines such a helper AND reads
    # process state elsewhere clears the window without proving the two are connected —
    # tying a call to its definition needs a shell parser, the same call made above.
    # Deliberately POSIX-portable: `\b` and BSD-sed `\?` are not, and a silently failing
    # match here would loosen the gate on exactly the host that runs it most.
    # The named helper's OWN BODY must reach a process-state read. Checking "the file
    # defines it" and "the file reads state somewhere" as two independent facts let a
    # hollow helper plus an unrelated `ps -o stat=` elsewhere clear a real hit — the two
    # conditions were never tied to each other. awk rather than sed: BSD sed lacks `\?`
    # and a silently failing match here loosens the gate on the host that runs it most.
    liveness_helper_ok=0
    while IFS= read -r liveness_helper; do
      [[ -n "$liveness_helper" ]] || continue
      if awk -v fn="$liveness_helper" '
           $0 ~ "^[[:space:]]*(function[[:space:]]+)?" fn "[[:space:]]*\\(\\)" {
             # The declaration line is part of the body: a one-line definition both opens
             # and closes here. Skipping it with a bare `next` left `inbody` set through
             # `fn() { echo live; }` and credited the NEXT function\047s state read to this
             # hollow one.
             if ($0 ~ /-o[[:space:]]*stat=/) { found = 1; exit }
             if ($0 ~ /}/) { exit }
             inbody = 1
             next
           }
           inbody && /-o[[:space:]]*stat=/ { found = 1; exit }
           inbody && /^[[:space:]]*}/ { exit }
           END { exit !found }
         ' "$liveness_file" 2>/dev/null; then
        liveness_helper_ok=1
        break
      fi
    done < <(printf '%s\n' "$liveness_win" | grep -oE '[A-Za-z_][A-Za-z0-9_]*_state' | sort -u)
    [[ "$liveness_helper_ok" -eq 1 ]] && continue
    liveness_hits+="${liveness_file#"$root"/}:$liveness_line"$'\n'
  done <<< "$liveness_out"
done < "$liveness_list"
rm -f "$liveness_list"
if [[ -n "${liveness_hits//[$'\n']/}" ]]; then
  # Trailing newline restored explicitly: command substitution strips it, which ran the
  # last hit and the diagnosis together on one line.
  printf '%s\n' "$(printf '%s' "$liveness_hits" | sort)"
  echo "liveness_predicate_scan_failed: the lines above decide that a process is a LIVE orphan from a ppid read alone, which an unreaped corpse answers the same way — the check says alive while the suite's own verdict scans exclude zombies and say gone. Consult process STATE (\`ps -o stat=\`, or a helper that returns live/zombie/absent) before concluding liveness. See skill-extraction-workflow/references/recurring-anti-patterns-checklist.md (Anti-pattern 28)." >&2
  exit 1
fi
echo "liveness_predicate_scan_ok"

# Evidence-card leak PREFLIGHT (best-effort, NOT the gate of record): catches obvious
# card-shaped markdown accidentally committed under skills/** (L0 storage rule, see
# l0-l1-l2-routing.md). Delegated to a dedicated, self-tested detector. The gate runs the
# detector's --self-test FIRST (fixture regression: the detector's own logic must be green
# before we trust its verdict), then the real scan. Scope is CHANGED markdown *.md under
# skills/** (integration base..worktree plus untracked / intent-to-add; base-less runs
# report a degraded warning); it does not re-police unchanged historical docs and does
# not enforce the L0 rule. R0 (actually run, not skipped) is the comprehensive
# L0-storage / leakage gate of record.
evidence_card_script="$root/skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh"
if [[ ! -f "$evidence_card_script" ]]; then
  echo "missing_evidence_card_leak_script: $evidence_card_script" >&2
  exit 2
fi
# Invoke via `bash` so a missing +x bit (common after checkout / on CI) is not a false miss.
# The --self-test is a fixture regression for the detector's own logic. A self-test FAILURE
# (a pure-shape assertion failed, or CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 flagged
# missing fixture infra) is BLOCKING — a broken detector must not be silently trusted. By
# default, missing git fixture infra SKIPS the changed-scope sub-tests inside the self-test
# (returning success with a printed warning), so unrelated authors on minimal images are not
# blocked. The changed-file scan below blocks on a real offender; a base-less degraded scan is
# warning-pass by default (set CCL_SKILL_EVIDENCE_CARD_STRICT_BASE=1 to enforce coverage).
if ! bash "$evidence_card_script" --self-test; then
  echo "evidence_card_leak_self_test_failed: detector self-test failed — blocking. (Set CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST only to make missing fixture infra fail; it is not needed to pass normally.)" >&2
  exit 1
fi
if ! bash "$evidence_card_script" "$root"; then
  exit 1
fi

# Label-discovery: list every <angle-bracket-token> introduced anywhere under the
# skill tree. The script does NOT have access to the maintainer's private alias
# YAML (that file lives outside the repo), so it cannot verify each label maps to
# a sanitized capability. It prints the inventory so the maintainer can confirm
# every label is registered in the alias YAML before committing.
label_inventory="$(rg -o --no-filename '<[a-z][a-z0-9-]+>' "$root"/skills/*/SKILL.md "$root"/skills/*/references/*.md 2>/dev/null | sort -u)"
label_rg_status=$?
if [[ "$label_rg_status" -ne 0 && "$label_rg_status" -ne 1 ]]; then
  echo "label_inventory_scan_error: rg exited $label_rg_status" >&2
  exit 1
fi
if printf '%s\n' "$label_inventory" | rg -q '^(USAGE:|ripgrep |  -|    --)'; then
  echo "label_inventory_scan_error: rg help text captured instead of labels" >&2
  exit 1
fi
if [[ -n "$label_inventory" ]]; then
  echo "label_inventory_discovered (verify each exists in private alias YAML):"
  echo "$label_inventory" | sed 's/^/  /'
fi

# R0 clean-landing status, consumed by the final machine-distinguishable token.
# "private-ok"     => the private alias audit ran clean (clean-landing R0 evidence).
# "public-fallback" => no ALIAS_AUDIT_CMD; only the public diff-scoped fallback ran
#                      (interim evidence only — private R0 has NOT run).
# It defaults to interim/public-fallback so a missing/short-circuited assignment can
# never silently upgrade a run to clean.
r0_clean_landing_status="public-fallback"

# Fail-closed hook: if the maintainer has exported ALIAS_AUDIT_CMD, run it.
# The command is sourced from the maintainer's environment (typically pointing
# at a script that opens the private alias YAML and verifies every label and
# pattern). A non-zero exit blocks the check.
#
# The value is split on whitespace and exec'd directly — NOT passed to a shell —
# so a polluted environment variable cannot inject `;`/`&&`/pipes/substitutions.
# Use "<script-path> <args>" form; anything needing shell features belongs in a
# wrapper script the variable points at.
if [[ -n "${ALIAS_AUDIT_CMD:-}" ]]; then
  echo "alias_audit_cmd_running: $ALIAS_AUDIT_CMD"
  read -r -a alias_audit_argv <<<"$ALIAS_AUDIT_CMD"
  # No shell means no tilde expansion; expand a leading ~/ per word so the
  # documented `bash ~/.../run-r0-audit.sh` form keeps working.
  for i in "${!alias_audit_argv[@]}"; do
    [[ "${alias_audit_argv[$i]}" == "~/"* ]] && alias_audit_argv[$i]="$HOME/${alias_audit_argv[$i]:2}"
  done
  if ! "${alias_audit_argv[@]}"; then
    echo "alias_audit_failed" >&2
    exit 1
  fi
  echo "alias_audit_ok"
  r0_clean_landing_status="private-ok"
  echo "r0_status=private-ok"
else
  # No private alias profile on this host (a normal local machine). Instead of
  # leaving only an "audit skipped" notice, run the deterministic PUBLIC fallback:
  # a high-signal leak scan over the ADDED lines of the current diff (shared-skill
  # markdown only). The private audit, when present above, stays the strongest /
  # clean-landing R0 evidence; this fallback is public interim evidence only.
  generic_r0_scan="$root/skills/skill-extraction-workflow/scripts/generic-r0-leak-scan.sh"
  if [[ ! -f "$generic_r0_scan" ]]; then
    echo "missing_generic_r0_leak_scan_script: $generic_r0_scan" >&2
    exit 2
  fi
  # Run the matcher's own fixture self-test first (a broken detector must not be
  # silently trusted), then the real diff scan. A leak hit blocks (exit 1).
  if ! bash "$generic_r0_scan" --self-test >/dev/null; then
    echo "generic_r0_leak_scan_self_test_failed: matcher self-test failed — blocking" >&2
    exit 1
  fi
  if ! bash "$generic_r0_scan" "$root"; then
    exit 1
  fi
  echo "alias_audit_unavailable: ALIAS_AUDIT_CMD unset; ran the generic public leak scan over added diff lines as the public R0 fallback. This permits interim commit/push/Draft MR, but is NOT private-alias clean-landing evidence — clean landing still requires alias_audit_ok, a named private profile, or an explicit risk-owner waiver (see skill-extraction-workflow/references/r0-leakage-audit.md)."
  r0_clean_landing_status="public-fallback"
  echo "r0_status=public-fallback"
fi

# Routing-skill existence check: when a route-like line points at another skill
# by name, verify the named skill directory exists at the top level of the skill
# tree. External skills must be allowed explicitly by the caller, not hard-coded
# here, so organization validation does not silently depend on one developer's local
# skill set. BLOCKING since 2026-08-02 (was warn-only advisory): a stale route
# fails the gate — a renamed/removed skill must never leave a live routing chain
# behind under a green CI.
route_check_rc=0
ruby -rset -rdigest -e '
begin
root = ARGV.fetch(0)
skills = Dir[File.join(root, "skills", "*", "SKILL.md")].map { |path| File.basename(File.dirname(path)) }.to_set
allowed_external = ENV.fetch("CCL_SKILL_ROUTE_ALLOWLIST", "").split(/[,\s]+/).reject(&:empty?).to_set
# Repo-internal vocabulary that is NOT a skill route: feature-risk-router risk
# tags. Only tags matching skillish_suffix can ever trip the check, but the
# whole tag set is listed so a future tag rename stays a one-line edit here.
# These are repo-wide vocabulary, so the exemption is unscoped.
# MUST stay in sync with the canonical tag list in
# skills/feature-risk-router/SKILL.md (the route-word saturation case in
# test_check_ccl_route_drift.sh fails when a mentioned tag is missing here).
risk_tags = %w[
  visible-ui client-plumbing api-contract permission-access money-quota
  write-finality ai-output ai-action genai-compliance data-migration
  external-integration release-ops shared-gate security-review
  verification-scope-unclear docs-only
].to_set
# Identifiers owned by ANOTHER namespace that happen to be route-shaped. Unlike
# risk tags these are only non-routes where their owning integration is being
# described, so each is scoped to the skill package that documents it: the same
# token elsewhere in the tree most likely IS someone routing to a skill that does
# not exist, which is exactly what this check exists to report.
# `ccl-review` is the agent OpenCode invokes (`agent.<name>.model`), so it is
# a non-route only inside the package that documents the OpenCode lane.
# `targeted-workflow` is one enum value of the source-map `coverage` column, so
# it is a non-route only inside the package that defines that column.
scoped_non_route_vocab = {
  "ccl-review" => "skills/code-review/",
  "targeted-workflow" => "skills/product-ui-ux-design/",
}
# Append-only ledger rows may legitimately name a renamed/removed skill as
# historical provenance: the ledger must never be edited, so a stale mention
# there has no legal fix and would otherwise hard-red the gate forever (same
# shape as register-firing-path-resolution EXEMPT). Keyed by [repo-relative
# path, token] with a per-key OCCURRENCE CAP: only the first N recorded
# historical mentions are exempt (the ledger is append-only, so the known
# mentions are always the earliest lines); any FURTHER occurrence of the same
# token in the same path — a NEW row routing to the dead name — blocks like
# any other stale route. The same token anywhere else also still blocks.
# Every entry needs a reason; applied exemptions are printed, never silent.
# Trust model: this table catches ACCIDENTAL drift (renames, dangling history,
# cap/count mismatch). A deliberate cap bump paired with a new mention is the
# same shape as the legitimate bump workflow — distinguishing them is intent,
# which no table inside the gated repo can adjudicate. Adversarial authorship
# is owned by the mandatory independent review (dual-track), with the printed
# exempt lines and the diff of this table itself as the reviewer-visible
# artifacts; machinery defending against the gated-repo author would defend
# against an adversary the trust model of this gate already excludes.
# Each entry pins the SHA-256 of every ledger LINE the waiver was written for, not
# a bare occurrence count. A count alone says "one row", never "WHICH row": delete
# the waived historical row and let a different row gain the same token and the
# count is still one, so the waiver silently transfers onto a brand-new stale route
# under a green gate (observed by applying that exact mutation — the exemption moved
# from register row 70 to a row appended 1100 lines later, rc=0, no block). Digests
# are stable under the append-only rule of the ledger (rows added elsewhere do not change
# a pinned line) and red on a rewrite with nobody having to touch code, which is what
# makes them worth having: the realistic failure is an accidental reflow or a
# repurposed row, not an author who edits both this table and the row to match. Same
# shape as EXEMPT_ROW_DIGESTS in register-firing-path-resolution.rb. Regenerate a
# digest only when the row itself legitimately changes, and say why in that commit.
exempt_historical_routes = {
  ["skills/skill-extraction-workflow/references/source-register.md", "claude-code-review"] =>
    ["legacy installed skill directory name recorded in append-only ledger history (register rows 959, 1153, and 1154); the live skill is code-review",
     %w[
       4099584cc48babbfbda07b828e42a8066cf4f1f3f7b4fe9898bc37fa872685df
       9379f50564f42671e0f0a41fed83a2ab21d8ed64c73979fa0941da42b92d02eb
       ed78f65c3a3e5fbfc185931eac40b2cbf06f71de7ead851dcf1ecaa1fb187f56
     ]],
  ["skills/skill-extraction-workflow/references/source-register.md", "resume-fit-evaluator"] =>
    ["recruitment-domain skill split out of this repo into common/hr-skills; the append-only ledger row (register row 70) records the org-screening-policy extraction that landed while it still lived here",
     %w[88111b77874de4bb63822288861be00bd7a78beb51801946136c06dec1266a37]],
  ["skills/skill-extraction-workflow/references/source-register.md", "jd-writer"] =>
    ["recruitment-domain skill split out of this repo into common/hr-skills; the append-only ledger row (register row 808) is a provenance note recording why the artifact-egress gate scopes recruitment JDs out",
     %w[dc4e874f9e430e711eb7c6909d2a3d876f650d1736a5d0100e09e91ced3750b0]],
}
exemption_seen = Hash.new { |h, k| h[k] = Hash.new(0) }
root_prefix = root.chomp("/") + "/"
repo_relative = lambda do |path|
  path.start_with?(root_prefix) ? path[root_prefix.length..] : path
end
files = [File.join(root, "README.md")] + Dir[File.join(root, "skills", "*", "SKILL.md")] + Dir[File.join(root, "skills", "*", "references", "*.md")]
# The always-on routing layer is itself a routing surface: a renamed/removed
# skill otherwise leaves stale backticked routes in agent-context/session-start.md invisible to
# this check (observed gap: the layer had prose-only sync while README and
# SKILL.md/references were scanned).
files << File.join(root, "agent-context/session-start.md") if File.file?(File.join(root, "agent-context/session-start.md"))
route_words = /\b(route|routes|routing|owner|owners|ownership|belong|belongs|belonging|skill|skills|use|uses)\b|路由|负责|用|走|先|再|回到|实现|设计|→|->/i
skillish_suffix = /-(dev|workflow|strategy|design|architecture|diagnosis|router|review|rollout|observability|connectivity|integration|execution|evaluator|writer|doc)\z/
stale = []
exempted = []
allowlisted = []
cap_drift = false
files.each do |path|
  next unless File.file?(path)
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    next unless line.match?(route_words)
    candidates = {}
    # A skill route reference is recognized ONLY when the skill name is wrapped in
    # backticks (the repo convention: skills are always written in backticks).
    # Bare hyphenated prose, even beside an arrow (e.g. review then fix then
    # re-review), is NOT treated as a route, so English compounds that happen to
    # end in a skillish suffix do not produce false positives. A genuine stale
    # route stays detectable because real route references are backtick-wrapped,
    # including a mistyped or renamed name such as cross-platform-dev.
    # (Keep this block apostrophe-free: it runs inside a single-quoted ruby -e.)
    line.scan(/`([^`]+)`/).flatten.each { |token| candidates[token] ||= :backtick }
    candidates.each do |candidate, source|
      next if candidate.end_with?(".md") || candidate.include?("/")
      next if candidate == "unresolved"
      next if risk_tags.include?(candidate)
      scope = scoped_non_route_vocab[candidate]
      # Containment against the repo-relative path, never a substring of the
      # absolute one: a checkout living under a directory that happens to spell
      # the scope would otherwise exempt the token tree-wide.
      next if scope && repo_relative.call(path).start_with?(scope)
      looks_like_skill = candidate.match?(/\A[a-z][a-z0-9_-]*\z/) && candidate.include?("-")
      next unless looks_like_skill
      next if skills.include?(candidate)
      next unless candidate.match?(skillish_suffix)
      # The caller-controlled allowlist suppresses a block — so every genuine
      # suppression is printed (an installed skill or a non-skill-shaped value
      # in the allowlist prints nothing: it suppressed nothing). An invisible
      # escape hatch on a blocking gate would let a one-line CI/env edit reach
      # green while skipping the gate with no reviewer-visible artifact.
      if allowed_external.include?(candidate)
        allowlisted << [path, idx + 1, candidate]
        next
      end
      exempt_key = [repo_relative.call(path), candidate]
      exempt_entry = exempt_historical_routes[exempt_key]
      # Identity AND multiplicity. Identity: the waiver applies to THIS line only
      # when its digest is one the table pinned, so a different line carrying the
      # same token is a live stale route no matter how many waived lines exist.
      # Multiplicity: a digest is spent as many times as the table pins it and no
      # more, because a byte-identical COPY of a waived line hashes the same and
      # would otherwise ride the same pin for free.
      line_digest = Digest::SHA256.hexdigest(line)
      allowance = exempt_entry ? exempt_entry[1].count(line_digest) : 0
      if allowance.positive? && (exemption_seen[exempt_key][line_digest] += 1) <= allowance
        exempted << [path, idx + 1, candidate, exempt_entry[0]]
      else
        stale << [path, idx + 1, candidate]
      end
    end
  end
end
# Digest-drift fail-closed: a pinned digest that no line matches means the RECORDED
# historical row was edited or removed (the append-only ledger forbids both) or a
# digest was added without a real row. A dead pin is a slot nothing occupies, and
# leaving it unreported would let the table claim coverage it no longer has.
# Zero observed mentions for an entry is NOT drift, unchanged from the count era:
# with nothing observed there is nothing being wrongly exempted, and a synthetic or
# foreign register (the fixtures several suites build) is outside a table that
# describes THIS ledger. KNOWN RESIDUAL, deliberately not closed here: delete the
# sole waived row outright and nothing is observed, nothing is stale, so an
# append-only deletion passes. Closing it needs the declared injection seam the
# sibling gate uses (production forces the built-in table, a fixture injects its
# own, injection is announced and downgrades the clean token) — that is ledger
# INTEGRITY work, a scope this repo already deferred when it mechanized only the
# waived rows, and it does not belong to a skill-package removal. What IS closed
# here is every axis the waiver entries themselves widen: a line whose digest is
# not pinned is a live stale route, never a free slot, and a copy beyond the
# pinned multiplicity lands there too.
exempt_historical_routes.each do |(exempt_path, token), (_reason, digests)|
  seen = exemption_seen[[exempt_path, token]]
  next if seen.empty?
  missing = digests.tally.reject { |digest, count| seen[digest] >= count }
  next if missing.empty?
  next unless File.file?(File.join(root, exempt_path))
  warn "route_existence_block: #{exempt_path} no longer contains the pinned historical line(s) for #{token.inspect} (unmatched digest(s): #{missing.keys.join(", ")}) — a recorded ledger row was edited/removed (append-only forbids both) or a digest was pinned without a real row; restore the history or regenerate the digest with a reason"
  cap_drift = true
end
stale.each do |path, lineno, candidate|
  warn "route_existence_block: #{path}:#{lineno} references #{candidate.inspect} but #{root}/#{candidate} is not a directory at the skill root"
end
exempted.each do |path, lineno, candidate, reason|
  puts "route_existence_exempt: #{path}:#{lineno} references #{candidate.inspect} — exempt: #{reason}"
end
allowlisted.each do |path, lineno, candidate|
  puts "route_existence_allowlisted: #{path}:#{lineno} references #{candidate.inspect} — suppressed via CCL_SKILL_ROUTE_ALLOWLIST (visible, never silent)"
end
if stale.any?
  puts "route_existence_check: #{stale.length} stale route reference(s) above — blocking; update the reference, restore the renamed skill, or allowlist a genuine external skill via CCL_SKILL_ROUTE_ALLOWLIST"
end
exit(stale.empty? && !cap_drift ? 0 : 1)
rescue StandardError, ScriptError => e
  warn "route_existence_check_error: #{e.class.name}: #{e.message.lines.first.to_s.strip}"
  exit 2
end
' "$root" || route_check_rc=$?
case "$route_check_rc" in
  0|1) : ;;
  *) echo "route_existence_check_infra_failed rc=$route_check_rc (route-drift scan could not run — fail-closed)" >&2; exit 2 ;;
esac
echo "route_existence_check_done"
echo "bootstrap_route_scan: $([ -f "$root/agent-context/session-start.md" ] && echo covered || echo skipped-missing)"

# Cross-skill .md reference existence check: when a reference points at
# another .md file (e.g. `../product-ui-ux-design/references/foo.md`,
# `product-ui-ux-design/references/foo.md`, or `references/foo.md`), verify
# the target file actually exists. A rename or removal of the target file
# otherwise breaks the routing chain silently. BLOCKING since 2026-08-02 (was
# warn-only advisory): a broken reference fails the gate.
# Append-only ledger rows may legitimately cite a renamed/removed references
# file as historical provenance (the ledger must never be edited, so a stale
# citation there has no legal fix). Exemptions key on "<repo-relative path>
# <cited ref>": anything else still blocks. Empty today — add an entry with a
# reason only when a real rename creates the collision; applied exemptions
# are printed, never silent.
md_ref_exempt() {
  case "$1" in
    *) return 1 ;;
  esac
}
md_ref_broken=0
bootstrap_arg=()
if [ -f "$root/agent-context/session-start.md" ]; then
  bootstrap_arg=("$root/agent-context/session-start.md")
  bootstrap_scan_state="covered"
else
  bootstrap_scan_state="skipped-missing"
fi
rg_err_tmp="$(mktemp "${TMPDIR:-/tmp}/mdref-rg-err.XXXXXX")" || { echo "md_reference_scan_error: mktemp failed" >&2; exit 1; }
rg_rc=0
rg_out="$(rg -n '`(\.\./)?[a-z][a-z0-9_-]*(/references)?/[a-z][a-z0-9_./-]+\.md`' "$root"/skills/*/references/*.md "$root"/skills/*/SKILL.md "${bootstrap_arg[@]+"${bootstrap_arg[@]}"}" 2>"$rg_err_tmp")" || rg_rc=$?
if [ "$rg_rc" -gt 1 ] && [ -z "$rg_out" ]; then
  cat "$rg_err_tmp" >&2
  echo "md_reference_scan_error: rg exited $rg_rc with no usable output" >&2
  rm -f "$rg_err_tmp"
  exit 1
fi
if [ -z "$rg_out" ]; then
  # Zero candidates: this repo always carries at least one <pkg>/references/*.md
  # citation, so an empty stream means the scan broke (glob/pattern/path
  # regression), not that there is nothing to check.
  echo "md_reference_scan_error: zero candidate lines" >&2
  rm -f "$rg_err_tmp"
  exit 1
fi
if [ "$rg_rc" -gt 1 ]; then
  # rg exits 2 on hard errors AND on partial failures (an unreadable file or a
  # broken glob): with partial failures it still prints usable matches, so only
  # an EMPTY result is a scan failure worth blocking every downstream gate for.
  echo "md_reference_scan_partial: rg exited $rg_rc; continuing with the matched subset:" >&2
  cat "$rg_err_tmp" >&2
  bootstrap_scan_state="partial-unverified"
fi
rm -f "$rg_err_tmp"
while IFS=: read -r path lineno match; do
  [[ -z "$match" ]] && continue
  ref=$(echo "$match" | sed -nE 's|.*`((\.\./)?([a-z][a-z0-9_-]+/)?references/[a-z][a-z0-9_./-]+\.md)`.*|\1|p')
  [[ -z "$ref" ]] && continue
  if [[ "$ref" == ../* ]]; then
    candidate="$root/skills/${ref#../}"
  elif [[ "$ref" == */references/* && "$ref" != references/* ]]; then
    candidate="$root/skills/$ref"
  else
    calling_skill=$(echo "$path" | sed -nE "s|^$root/skills/([^/]+)/.*|\1|p")
    candidate="$root/skills/$calling_skill/$ref"
  fi
  if [[ ! -f "$candidate" ]]; then
    # Normalize to the repo-relative key form the exemption table uses: strip
    # the root prefix, then a defensive leading "./" (root="." CI shape).
    path_rel="${path#"${root%/}/"}"
    path_rel="${path_rel#./}"
    if md_ref_exempt "$path_rel $ref"; then
      echo "md_reference_exempt: $path:$lineno cites \`$ref\` — exempt (append-only historical citation)"
    else
      echo "md_reference_block: $path:$lineno cites \`$ref\` but $candidate does not exist" >&2
      md_ref_broken=$((md_ref_broken + 1))
    fi
  fi
done <<< "$rg_out"
if [[ "$md_ref_broken" -gt 0 ]]; then
  echo "md_reference_check: $md_ref_broken broken .md reference(s) above — blocking; a routed-to file was renamed or removed, update the citation or restore the target"
fi
echo "md_reference_check_done"
if [ "$bootstrap_scan_state" = "covered" ]; then
  bootstrap_ref_hits="$(printf '%s\n' "$rg_out" | grep -cF "$root/agent-context/session-start.md:" || true)"
  echo "bootstrap_scan: covered refs=$bootstrap_ref_hits"
else
  echo "bootstrap_scan: $bootstrap_scan_state"
fi
# The two sync checks above are BLOCKING but their exit verdict is deferred to
# just after the impact-chain / register gates (search: sync_reference_blocking_failed)
# so one run shows THOSE gates' diagnostics alongside the sync violations. Later
# sections (eval-routing, size gate, final tokens) keep the script's fail-fast
# per-section shape: a sync failure exits before them by design.
# Structural guard for the deferral: no earlier exit path (including a future
# early-return added to an intervening section) may drop a pending sync
# verdict. The guard fires ONLY when the process is exiting 0 with violations
# pending — the explicit verdict below and every non-zero exit pass through
# silently with their original status.
sync_verdict_guard() {
  _guard_rc=$?
  if [ "$_guard_rc" -eq 0 ] && { [ "$route_check_rc" -eq 1 ] || [ "$md_ref_broken" -gt 0 ] || [ "${sync_pointer_rc:-0}" -eq 1 ]; }; then
    echo "sync_reference_blocking_failed: stale route reference(s) and/or broken .md reference(s) and/or semantic sync registry violation(s) above block the gate (reached via an early-exit path; blocking since 2026-08-02)" >&2
    exit 1
  fi
  exit "$_guard_rc"
}
trap sync_verdict_guard EXIT

# Semantic tier of the sync family (C-1): declared pinned pairs (always-on
# pointer literals AND their canonical anchors) plus the security-four-questions
# predicate-subset registry. Same blocking strength as the syntactic tier; its
# verdict joins the deferred combined verdict below. The gate program resolves
# NEXT TO THIS VALIDATOR (never from the judged tree — an in-tree copy could be
# doctored to `exit 0`), following the impact-chain gate's one-versioned-unit
# rule. The output is captured so a marked skip (missing agent-context/session-start.md /
# package) downgrades the final clean token — a skip must never read as a
# clean full evaluation.
sync_pointer_rc=0
sync_pointer_out=""
sync_pointer_err=""
sync_pointer_skipped=0
if [[ -z "${checker_scripts_dir:-}" ]]; then
  if ! checker_scripts_dir="$(resolve_checker_scripts_dir "${BASH_SOURCE[0]}")"; then
    checker_scripts_dir=""
    echo "sync_pointer_infra_failed: could not resolve the validator script directory from ${BASH_SOURCE[0]}" >&2
    exit 2
  fi
fi
sync_pointer_script="$checker_scripts_dir/check-sync-pointers.sh"
if [[ -L "$sync_pointer_script" || ! -f "$sync_pointer_script" ]]; then
  echo "sync_pointer_infra_failed: check-sync-pointers.sh missing or not a regular file beside the validator: $sync_pointer_script" >&2
  exit 2
fi
sync_pointer_err_tmp="$(mktemp "${TMPDIR:-/tmp}/sync-pointer-err.XXXXXX")" || { echo "sync_pointer_infra_failed: mktemp failed" >&2; exit 2; }
sync_pointer_out="$(bash "$sync_pointer_script" "$root" 2>"$sync_pointer_err_tmp")" || sync_pointer_rc=$?
sync_pointer_err="$(cat "$sync_pointer_err_tmp")"
rm -f "$sync_pointer_err_tmp"
# Replay on the original channels: markers to stdout, diagnostics to stderr.
printf '%s\n' "$sync_pointer_out"
[ -n "$sync_pointer_err" ] && printf '%s\n' "$sync_pointer_err" >&2
if [ "$sync_pointer_rc" -ne 0 ] && [ "$sync_pointer_rc" -ne 1 ]; then
  echo "sync_pointer_infra_failed rc=$sync_pointer_rc (semantic sync gate could not run — fail-closed)" >&2
  exit 2
fi
case "$sync_pointer_out" in
  *check_skipped*) sync_pointer_skipped=1 ;;
esac

# Shared process gates that are easy to weaken by updating only an entrypoint
# while leaving the default template or retrospective reference with old exits.
project_assessment_template="$root/skills/product-rd-workflow/references/existing-project-assessment-report.md"
if [[ ! -f "$project_assessment_template" ]]; then
  echo "project_assessment_template_missing: $project_assessment_template" >&2
  exit 1
fi
for required_phrase in \
  "Assessment launch checklist" \
  "product/user paths" \
  "architecture/implementation owners" \
  "test-layer matrix owner" \
  "UI/UX surfaces" \
  "runtime/host evidence surface" \
  "unavailable/live/manual boundaries" \
  "extraction/learning trigger" \
  "Closeout outputs" \
  "project findings or fixes" \
  "verification evidence by layer" \
  "issue/risk registration" \
  "reusable-process disposition"; do
  if ! rg -qF "$required_phrase" "$project_assessment_template"; then
    echo "project_assessment_template_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
echo "project_assessment_template_gate_ok"

skill_extraction_entry="$root/skills/skill-extraction-workflow/SKILL.md"
task_retro_reference="$root/skills/skill-extraction-workflow/references/source-to-skill-extraction.md"
if [[ ! -f "$skill_extraction_entry" ]]; then
  echo "skill_extraction_entry_missing: $skill_extraction_entry" >&2
  exit 1
fi
if [[ ! -f "$task_retro_reference" ]]; then
  echo "task_retro_reference_missing: $task_retro_reference" >&2
  exit 1
fi
for required_phrase in \
  "would other teammates hit this" \
  "will we forget next time" \
  "teamwide recurrence" \
  "reusable routing/process/team failure" \
  "memory-only landing as insufficient"; do
  if ! rg -qF "$required_phrase" "$skill_extraction_entry"; then
    echo "skill_extraction_teammate_trigger_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
for required_phrase in \
  "shared-skill vs memory-only boundary" \
  "not a reusable process, routing, testing, design, review, or teamwide failure" \
  "Do not classify reusable process defects" \
  "others will hit this too" \
  "shared skill/reference/validator/checklist/project-template landing"; do
  if ! rg -qF "$required_phrase" "$task_retro_reference"; then
    echo "task_retro_memory_escape_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
echo "task_retro_memory_escape_gate_ok"

testing_strategy_entry="$root/skills/testing-strategy/SKILL.md"
product_rd_entry="$root/skills/product-rd-workflow/SKILL.md"
if [[ ! -f "$testing_strategy_entry" ]]; then
  echo "testing_strategy_entry_missing: $testing_strategy_entry" >&2
  exit 1
fi
if [[ ! -f "$product_rd_entry" ]]; then
  echo "product_rd_entry_missing: $product_rd_entry" >&2
  exit 1
fi
for required_phrase in \
  "先写测试用例" \
  "test cases first" \
  "test-case register first" \
  "expected current result" \
  "RED-before-implementation rule" \
  "run RED before implementation" \
  "Do not answer \"tests are complete\" from command output alone"; do
  if ! rg -qF "$required_phrase" "$testing_strategy_entry"; then
    echo "testing_strategy_test_case_first_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
for required_phrase in \
  "test-case register" \
  "test-case-first is the default gate" \
  "run it RED before coding" \
  "not applicable: behavior-neutral/docs/config-only" \
  "do not claim TDD"; do
  if ! rg -qF "$required_phrase" "$product_rd_entry"; then
    echo "product_rd_test_case_first_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
# Product-rd entrypoint semantic-anchor gate: a targeted, non-comprehensive
# backstop for B0 entrypoint slimming. It protects high-risk semantic phrases and
# section anchors; full semantic-control still requires the B0 checklist,
# behavioral evidence, and dual-track review. Intentional replacements should
# update this list in the same MR.
for required_phrase in \
  "Implementation entry / re-entry gate" \
  "context summaries, compacted memory, and previous-response residue are not establishment" \
  "Reaching the first implementation edit without this boundary record is a process defect" \
  "High-risk resilience gating: when a feature touches money" \
  "Diagnostic spec-match baseline gate" \
  "do NOT treat the user's single-utterance description as the authoritative spec" \
  "Owner-dispatch firing gate" \
  "START of design-substance production, not only design completion" \
  "this workflow classifies the artifact before implementation" \
  "### Pre-Final Continuation Gate" \
  "Run this gate before finalizing a product R&D turn after any delivery slice lands" \
  "fetch/update the target ref from its remote immediately before classifying the slice landed" \
  'Deferred-evidence continuation check (`DFE-CONT`)' \
  "Report deferred real evidence as" \
  "Stop only for an explicit stop/pause instruction" \
  "Do not send a completion-only, solved, fixed, or fully-closed final response" \
  "### Feature Deprecation" \
  'A deprecation slice is `complete` only when steps'; do
  if rg -qF "$required_phrase" "$product_rd_entry"; then
    continue
  else
    rg_status=$?
    if [[ "$rg_status" -eq 1 ]]; then
      echo "product_rd_entrypoint_anchor_gate_missing: $required_phrase" >&2
      echo "fix: keep the stable anchor in product-rd-workflow/SKILL.md, or update this gate in the same MR when intentionally replacing the anchor" >&2
      exit 1
    fi
    echo "product_rd_entrypoint_anchor_gate_scan_error: rg exited $rg_status while checking $required_phrase" >&2
    exit 1
  fi
done
echo "product_rd_entrypoint_anchor_gate_ok"
for required_phrase in \
  "Test-case register before fixes/tests" \
  "RED/pass-existing/blocked/gap status" \
  "Running test commands before writing the test-case register"; do
  if ! rg -qF "$required_phrase" "$project_assessment_template"; then
    echo "project_assessment_test_case_first_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
for required_phrase in \
  "tests were run before test cases" \
  'target-output map must include `testing-strategy`' \
  'coordinating workflow such as `product-rd-workflow`' \
  "durable test-case-first prevention rule"; do
  if ! rg -qF "$required_phrase" "$skill_extraction_entry"; then
    echo "skill_extraction_test_case_first_gate_missing: $required_phrase" >&2
    exit 1
  fi
done
echo "test_case_first_gate_ok"

# Contract-anchor gate: declarative wording-existence pins for load-bearing
# prose contracts that structural checks cannot see (verdict-taxonomy
# discriminators, stop-condition predicates, externally verified numeric
# tiers). Checker and its contract-anchors.tsv table resolve NEXT TO THIS
# VALIDATOR (one-versioned-unit rule, same as the sync-pointer gate — an
# in-tree copy could be doctored to exit 0). Red = a pinned contract sentence
# drifted, was deleted, or became ambiguous; the remedy is printed by the
# checker (restore the wording, or update the anchor row in the same MR for an
# intentional contract change). Self-proof: test_check_contract_anchors.sh
# (fast) and test_pinned_phrase_mutation_walk.sh (heavy).
contract_anchor_script="$checker_scripts_dir/check-contract-anchors.sh"
if [[ -L "$contract_anchor_script" || ! -f "$contract_anchor_script" ]]; then
  echo "contract_anchor_infra_failed: check-contract-anchors.sh missing or not a regular file beside the validator: $contract_anchor_script" >&2
  exit 2
fi
contract_anchor_rc=0
contract_anchor_out="$(bash "$contract_anchor_script" "$root")" || contract_anchor_rc=$?
[ -n "$contract_anchor_out" ] && printf '%s\n' "$contract_anchor_out"
if [ "$contract_anchor_rc" -eq 1 ]; then
  echo "contract_anchor_gate_blocking_failed: pinned contract wording drifted (diagnostics above)" >&2
  exit 1
elif [ "$contract_anchor_rc" -ne 0 ]; then
  echo "contract_anchor_infra_failed: rc=$contract_anchor_rc (contract-anchor gate could not run — fail-closed)" >&2
  exit 2
fi
if ! printf '%s\n' "$contract_anchor_out" | grep -qE '^contract_anchor_gate_ok \([0-9]+ anchors\)$'; then
  echo "contract_anchor_infra_failed: green output grammar missing (expected: contract_anchor_gate_ok (N anchors))" >&2
  exit 2
fi

# Post-cleanup register check: after a project-specific extraction batch is
# migrated out of the shared skill tree, the source-register.md template must
# not silently grow new project-specific dated entries. The rule in
# skill-extraction-workflow/SKILL.md (Extraction lifecycle handoff) forbids
# adding new project-specific provenance to that file. This check enforces it.
if [[ -f "$root/skills/skill-extraction-workflow/references/source-register.md" ]]; then
  ct_count=$(rg -c "^## Current Task:" "$root/skills/skill-extraction-workflow/references/source-register.md" 2>/dev/null || echo 0)
  if [[ "$ct_count" -gt 0 ]]; then
    echo "warn_project_specific_register_entries: skill-extraction-workflow/references/source-register.md contains $ct_count '## Current Task:' section(s); per the Extraction lifecycle handoff rule, project-specific dated entries must live in the private alias archive, not in the shared skill tree" >&2
    echo "post_cleanup_register_pattern_failed"
    exit 1
  fi
  echo "post_cleanup_register_pattern_ok"
fi

# `--is-inside-work-tree` alone is not the right predicate: an exported copy
# unpacked INSIDE some other checkout answers `true`, and every gate below would
# then adjudicate that enclosing repository's git state while reading $root's
# files — the wrong tree, reported as a clean landing. Require $root to be the
# work tree's own top level, so a nested export takes the interim branch with a
# real non-git export.
root_worktree_toplevel=""
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git_toplevel_raw="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" \
     && [ -n "$git_toplevel_raw" ] && [ -d "$git_toplevel_raw" ]; then
    # Normalize both sides: $root may be given with symlinked or relative
    # components, and a textual comparison against git's physical path would
    # false-negative a legitimate repository root.
    root_physical="$(cd "$root" 2>/dev/null && pwd -P)" || root_physical=""
    toplevel_physical="$(cd "$git_toplevel_raw" 2>/dev/null && pwd -P)" || toplevel_physical=""
    if [ -n "$root_physical" ] && [ "$root_physical" = "$toplevel_physical" ]; then
      root_worktree_toplevel="$toplevel_physical"
    fi
  fi
fi

if [ -n "$root_worktree_toplevel" ]; then
  # The gate program lives beside this checker (impact-chain-gate.rb) and is
  # resolved from THIS script's directory, not from $root: the checker and the
  # gate are one versioned unit, and a harness pointing CHECK_SCRIPT_UNDER_TEST
  # at a working-tree checker must exercise the same working-tree gate rather
  # than a stale committed copy inside the target repo.
  # Resolve file- and directory-level symlinks once so every checker-adjacent
  # helper comes from the same versioned script directory.
  if ! checker_scripts_dir="$(resolve_checker_scripts_dir "${BASH_SOURCE[0]}")"; then
    echo "missing_impact_chain_gate: could not resolve checker script directory from ${BASH_SOURCE[0]}" >&2
    exit 2
  fi
  impact_chain_gate="$checker_scripts_dir/impact-chain-gate.rb"
  if [[ -L "$impact_chain_gate" || ! -f "$impact_chain_gate" ]]; then
    echo "missing_impact_chain_gate: $impact_chain_gate (must be a regular file beside the checker, not a symlink)" >&2
    exit 2
  fi
  ruby "$impact_chain_gate" "$root"

  # No merge-side ledger-binding probe runs here, deliberately: this checker also
  # runs against synthetic fixtures inside other suites, where such a probe cannot
  # operate and reddens suites that do not own it. That gate's own suite covers the
  # real-checkout path and the CI step enforces it. Do not re-add one here.

  # Whole-ledger firing-path resolution. The impact-chain gate above is
  # diff-scoped by design, so a row's firing path is machine-checked exactly once
  # — at the commit that added it. Nothing re-checks it afterwards, while the
  # prose it anchors into stays living text, so a later move/reword of an
  # anchored rule silently voids that row's firing evidence with every gate
  # green. This one re-resolves every locator in the ledger, historical rows
  # included.
  firing_path_gate="$checker_scripts_dir/register-firing-path-resolution.rb"
  if [[ -L "$firing_path_gate" || ! -f "$firing_path_gate" ]]; then
    echo "missing_register_firing_path_gate: $firing_path_gate (must be a regular file beside the checker, not a symlink)" >&2
    exit 2
  fi
  # Consumption is a symmetric contract: a clean rc must pair with the gate's
  # clean terminal line. A bare call site cannot tell a real clean run from a
  # gate that died quietly (a crash where `set -e` is disarmed, a reworded
  # token, an early `exit 0`) — both arrive as rc=0, and the checker would
  # certify a gate that adjudicated nothing. The rc is captured without early
  # exit so the gate's own diagnostics still reach the log on every tier.
  # stdout and stderr are captured SEPARATELY. Merging them makes the terminal
  # line unlocatable: with `2>&1` any stderr write can land after the gate's
  # final puts, so the check can only ask "does some line carry the token",
  # which a gate that printed its token and then died silently also satisfies.
  # Split streams let the contract be "the LAST non-empty stdout line is the
  # token", which that failure cannot meet.
  # One checked directory plus a trap, not two bare `mktemp`s: an unchecked
  # mktemp failure exits with whatever rc it happened to have (typically 1,
  # indistinguishable from an adjudicated ledger violation) and a second failure
  # would leak the first file. A signal mid-run would leak both.
  if ! fp_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/firingpath.XXXXXX")"; then
    echo "register_firing_path_gate_failed: could not create a temporary directory for the gate's output (infrastructure failure, not an adjudicated ledger violation)" >&2
    exit 2
  fi
  # COMPOSE with the script-level EXIT trap, never replace it: `sync_verdict_guard`
  # is armed above and converts a would-be rc=0 early exit into the deferred sync
  # verdict. A bare `trap ... EXIT` here would silently disarm it for the rest of
  # the checker, and a bare `trap - EXIT` afterwards would leave it disarmed all
  # the way to its own teardown — harmless only for as long as every exit in that
  # span happens to be non-zero, which is not a property anyone editing later
  # would know they have to preserve.
  # Capture `$?` FIRST and restore it before delegating: `rm -rf` succeeds and
  # overwrites the pending status with 0, so a naive `rm; sync_verdict_guard`
  # makes the guard read 0 and `exit 0` — turning this block's `exit 2` for a
  # failed output read into a silent success while the trap is armed.
  trap 'fp_trap_rc=$?; rm -rf "${fp_tmp_dir:-}"; (exit "$fp_trap_rc"); sync_verdict_guard' EXIT
  ruby "$firing_path_gate" "$root" >"$fp_tmp_dir/out" 2>"$fp_tmp_dir/err" && fp_rc=0 || fp_rc=$?
  if ! firing_path_out="$(cat "$fp_tmp_dir/out")" || ! firing_path_err="$(cat "$fp_tmp_dir/err")"; then
    echo "register_firing_path_gate_failed: could not read back the gate's captured output (infrastructure failure, not an adjudicated ledger violation)" >&2
    exit 2
  fi
  rm -rf "$fp_tmp_dir"
  trap sync_verdict_guard EXIT
  # Not a bare AND-list: under `set -e` an empty-success print would abort the
  # checker unexplained. Diagnostics always replay to stderr (CI scrapes stderr
  # for causes); the contract checks below read the captured strings.
  [ -n "$firing_path_err" ] && printf '%s\n' "$firing_path_err" >&2
  if [ -n "$firing_path_out" ]; then
    if [ "$fp_rc" -eq 0 ]; then
      printf '%s\n' "$firing_path_out"
    else
      printf '%s\n' "$firing_path_out" >&2
    fi
  fi
  if [ "$fp_rc" -ne 0 ]; then
    # A non-zero rc alone does not say WHICH tier failed. The gate reports a
    # ledger violation by naming it; a Ruby syntax error, an uncaught exception,
    # or a silent `exit 1` also arrive as rc=1 with no such diagnostic, and
    # forwarding that as rc=1 tells CI "the ledger is wrong" when the truth is
    # "the gate did not run". Only a diagnosed rc=1 stays a rule failure.
    if [ "$fp_rc" -eq 1 ] \
       && grep -qE '^register_firing_path_(malformed|unresolved)' <<<"$firing_path_err"; then
      exit 1
    fi
    echo "register_firing_path_gate_failed: gate exited $fp_rc without a register_firing_path_malformed/unresolved diagnostic (gate malfunction or infrastructure failure, not an adjudicated ledger violation)" >&2
    exit 2
  fi
  # The token must be the LAST non-empty stdout line and be complete.
  #   - last line, not any line: a gate that prints its token and then dies on a
  #     later path would otherwise still read as clean.
  #   - whole-line anchored: an unanchored fragment also accepts the truncated
  #     line a gate crashing mid-print emits.
  #   - the COUNT is not constrained here. Zero is only suspicious when the
  #     ledger actually carries declarations, and only the gate can see that;
  #     it owns the scanner-failure verdict (a checker-side non-zero floor
  #     false-reds a legitimately declaration-free register).
  # Here-string, NOT `printf | grep -q`: under this script's `pipefail`, `grep -q`
  # exits at the first match while the writer still has data queued, the writer
  # takes SIGPIPE, and the pipeline reports 141 — inverting the check into a
  # false RED on any sufficiently chatty gate (the failure this repository
  # already hit once in the review-gate CLI wrappers).
  # awk, not `grep -v ... | tail`: on empty gate output grep matches nothing and
  # exits 1, which under `pipefail` fails the assignment and aborts the whole
  # checker with rc=1 — turning the "gate printed nothing" case into an
  # unexplained checker crash instead of the rc=2 malfunction verdict below.
  # awk exits 0 whether or not it saw a non-empty line.
  # The gate's waiver-row bindings can be replaced through an injected table so
  # fixtures can describe their own synthetic ledger. That seam must never yield
  # a clean landing — an inherited test environment would otherwise silently
  # disable the digest and missing-row layers on a real run.
  if grep -q '^register_firing_path_exempt_digests_injected:' <<<"$firing_path_out"; then
    echo "ccl_skill_check_interim_notice: the firing-path gate ran with an injected EXEMPT digest table, so the built-in waiver-row bindings were not enforced; this run is interim, not clean-landing"
    firing_path_digests_injected=1
  fi
  firing_path_last_line="$(awk 'NF { last = $0 } END { print last }' <<<"$firing_path_out")"
  if ! grep -qE '^register_firing_path_resolution_ok \([0-9]+ locators resolved\)$' <<<"$firing_path_last_line"; then
    echo "register_firing_path_terminal_missing: gate exited 0 but its last non-empty stdout line is not a complete ok terminal line (gate malfunction, not a clean run)" >&2
    exit 2
  fi

  # Register pending/interim status <-> clean-landing mutual exclusion.
  # The prose rule ("any `pending` row blocks a complete/final claim", and an
  # `interim` checkpoint is not complete either) had no machine firing point, so
  # the dual-track challenge had to catch "claimed clean/complete while a changed
  # register row is still pending/interim" by hand across rounds. This wires the
  # two together: if the ADDED source-register diff introduces any row whose
  # status cell is a non-terminal `pending`/`interim`, the run is forced to
  # interim (clean_ok is suppressed at the final token below). It is a downgrade,
  # NOT a hard block — committing an interim/pending checkpoint is legitimate;
  # calling it a clean landing is not. Scoped to the ADDED diff (not the whole
  # historical ledger) so pre-existing pending/interim rows never block a fresh
  # commit. A WHOLE-cell match (`pending`/`interim` after stripping backticks)
  # targets the status column only: prose cells are sentences, never a lone
  # status word, and impact-chain rows can only be updated/unchanged/routed/
  # not-applicable, so this fires only on the non-impact-chain row families that
  # legitimately use pending/interim.
  pending_status_gate="$checker_scripts_dir/source-register-pending-status.rb"
  if [[ -L "$pending_status_gate" || ! -f "$pending_status_gate" ]]; then
    echo "missing_source_register_pending_status_gate: $pending_status_gate (must be a regular file beside the checker, not a symlink)" >&2
    exit 2
  fi
  register_nonterminal_status="$(ruby "$pending_status_gate" "$root")"
  case "$register_nonterminal_status" in
    0|1) ;;
    *)
      echo "register_pending_status_gate_failed: expected 0 or 1 from $pending_status_gate" >&2
      exit 2
      ;;
  esac

  git -C "$root" diff --check
  echo "diff_check_ok"
else
  # $root is not a work tree's own top level — either no git at all (exported
  # copy, build artifact directory, unpacked package) or an export nested inside
  # some other checkout, where running the gates would adjudicate the enclosing
  # repository instead. Either way the four git-dependent gates below did not
  # run against $root. Silence would let the run reach the clean-landing token
  # with all four skipped, so mark it interim — skip must never read as clean.
  echo "ccl_skill_check_interim_notice: $root is not a git work tree root — git-dependent gates (impact-chain, firing-path resolution, register pending-status, diff --check) not run; this run is interim, not clean-landing"
  git_dependent_gates_skipped=1
fi

# Combined blocking verdict for the two sync checks (route existence +
# cross-skill .md reference, diagnostics printed in their own sections above).
# Deferred to exactly here so the impact-chain / register gates above still
# report their diagnostics in the same run; the sections BELOW (lifecycle
# report, eval-routing, size gate) keep the script's fail-fast per-section
# shape and are not accumulated — each failure class exits at its own section.
# Either violation class fails the gate.
if [ "$route_check_rc" -eq 1 ] || [ "$md_ref_broken" -gt 0 ] || [ "$sync_pointer_rc" -eq 1 ]; then
  echo "sync_reference_blocking_failed: stale route reference(s) and/or broken .md reference(s) and/or semantic sync registry violation(s) above block the gate (blocking since 2026-08-02); fix the citation, restore the renamed/removed target, reword both sides of a registered sync pair together, or allowlist a genuine external skill via CCL_SKILL_ROUTE_ALLOWLIST" >&2
  exit 1
fi
# Verdict evaluated: disarm the early-exit guard so the clean path continues.
trap - EXIT

# Source-register lifecycle report (advisory — NEVER blocks, NEVER changes exit code).
# Scans only shared-ledger table rows (lines beginning with `|`) so methodology prose
# and examples do not inflate counts. Reports machine-visible cue counts for
# `supersedes:` and `revalidate-when:` without judging stale state or event truth.
# Names any `revalidate-by: <date>` marker whose date has passed (local calendar day),
# so a stale externally-anchored rule (per the "Row lifecycle" convention) gets
# re-checked instead of trusted blind. Uses Ruby (already a hard dependency for
# eval-routing.rb): Date.strptime validates a REAL calendar date, so the `<date>`
# placeholder, ISO timestamps (`...T..`), and invalid dates (e.g. 2020-99-99) do NOT
# match; Date.today avoids any external `date` command. The whole call is guarded
# with `|| true` so nothing here — even a Ruby error — can change the exit code.
# One-shot scan, not a prune/telemetry/event-monitoring job.
register="$root/skills/skill-extraction-workflow/references/source-register.md"
if [ -f "$register" ]; then
  if [[ -z "${checker_scripts_dir:-}" ]]; then
    if ! checker_scripts_dir="$(resolve_checker_scripts_dir "${BASH_SOURCE[0]}")"; then
      checker_scripts_dir=""
      echo "revalidate_check_skipped: could not resolve checker script directory from ${BASH_SOURCE[0]}" >&2
    fi
  fi
  if [[ -n "$checker_scripts_dir" ]]; then
    lifecycle_gate="$checker_scripts_dir/source-register-lifecycle.rb"
    if [[ -L "$lifecycle_gate" || ! -f "$lifecycle_gate" ]]; then
      echo "revalidate_check_skipped: missing lifecycle helper beside checker: $lifecycle_gate" >&2
    else
      ruby "$lifecycle_gate" "$register" || true
    fi
  fi
fi

# F4 Tier-1 static routing analyzer: block on objective routing-surface defects
# (dangling backticked redirects, exact trigger collisions without disambiguation).
# Advisory findings (fuzzy/possible-dangling) print but never block.
eval_routing_rc=0
ruby "$root/skills/skill-extraction-workflow/scripts/eval-routing.rb" "$root" || eval_routing_rc=$?
if [ "$eval_routing_rc" -eq 0 ]; then
  echo "eval_routing_ok"
elif [ "$eval_routing_rc" -eq 2 ]; then
  # parse/usage error (bad or absent SKILL.md frontmatter) — distinct from a routing defect
  echo "eval_routing_error: analyzer parse/usage error (see above)" >&2
  exit 2
else
  echo "eval_routing_blocking: objective routing-surface defects (see above; run: make eval-routing)" >&2
  exit 1
fi

# Entrypoint size gate (delta-blocking since 2026-07-30): gives the "consolidate; a rule
# set must not grow monotonically" Core Rule a mechanical firing path. Delta-scoped — a
# changed entrypoint that is new/crossing over
# 50KB, or an already-severe entrypoint that grew, fails the gate; the debt counters
# and recommended-band tokens stay visibility/debt-management only (not a
# clean-landing waiver and not authorization to keep growing entrypoints). The
# legacy markers (size_budget_advisory_ok|partial, size_budget_info:) are preserved.
# Since 2026-08-02 the same delta shape gates agent-context/session-start.md: a changed agent-context/session-start.md
# that grew fails the gate (the 13000B band stays advisory visibility only).
size_budget_script="$root/skills/skill-extraction-workflow/scripts/check-size-budget.sh"
if [[ -f "$size_budget_script" ]]; then
  size_budget_rc=0
  bash "$size_budget_script" "$root" || size_budget_rc=$?
  if [[ "$size_budget_rc" -eq 1 ]]; then
    echo "entrypoint_size_budget_blocking_failed (block or partial: see entrypoint_size_block lines above)" >&2
    exit 1
  elif [[ "$size_budget_rc" -ne 0 ]]; then
    echo "entrypoint_size_budget_infra_failed rc=$size_budget_rc (size gate could not run — ruby missing/crash; fail-closed)" >&2
    exit 1
  fi
else
  # The size gate is part of this gate's contract — a missing script is a broken
  # checkout, not a skippable advisory.
  echo "entrypoint_size_budget_blocking_failed: check-size-budget.sh missing" >&2
  exit 1
fi

# Parallel-stack mirrored-section parity: the sibling reference pairs listed in
# check-parallel-stack-parity.sh declare a mirrored region that must stay in sync
# across the Python and Go trees. The per-file grep gates check token hygiene
# INSIDE one file and cannot see cross-file drift; this gate diffs the normalized
# mirrored regions and blocks on any divergence beyond the two allowed classes
# (sibling skill names, backticked routing references).
parity_script="$root/skills/skill-extraction-workflow/scripts/check-parallel-stack-parity.sh"
if [[ -L "$parity_script" || ! -f "$parity_script" ]]; then
  echo "parallel_stack_parity_infra_failed: check-parallel-stack-parity.sh missing beside the validator" >&2
  exit 2
fi
parity_rc=0
parity_out="$(bash "$parity_script" "$root" 2>&1)" || parity_rc=$?
printf '%s\n' "$parity_out"
if [ "$parity_rc" -eq 1 ]; then
  echo "parallel_stack_parity_blocking_failed rc=1 (mirrored sections drifted or markers malformed — fix both siblings in the same change)" >&2
  exit 1
elif [ "$parity_rc" -ne 0 ]; then
  # Any other nonzero result is the script itself failing (awk/sed/read/runtime), not a
  # content verdict; keep the infra distinction so maintainers repair CI, not content.
  echo "parallel_stack_parity_infra_failed rc=$parity_rc (parity gate could not run — fail-closed)" >&2
  exit 2
fi

# Final status token. The legacy `ccl_skill_check_ok` is still printed for
# backward-compatible consumers, but it is NO LONGER the last line and NO LONGER
# the sole success signal: a machine (or human) MUST read the final
# `ccl_skill_check_(clean|interim)_ok` token to tell a clean-landing R0 pass
# (private alias audit ran clean) from an interim pass (only the public fallback
# ran — private R0 NOT run). Never treat the legacy token, or the interim token,
# as clean-landing R0 evidence (see skill-extraction-workflow/references/r0-leakage-audit.md).
# Clean landing requires BOTH a private-ok R0 audit AND no pending/interim register
# rows added in this diff: a changed ledger row that is still `pending`/`interim`
# is by definition not-yet-complete work, which cannot be a clean landing.
# Likewise a partially-SKIPPED semantic sync tier (missing agent-context/session-start.md or a
# missing package) is not a full evaluation: the run keeps rc 0 for the legal
# skip states, but skip must never read as clean (same honesty shape as the
# size gate's `*_unevaluated` token).
echo "ccl_skill_check_ok"
if [[ "$r0_clean_landing_status" == "private-ok" && "${register_nonterminal_status:-0}" != "1" && "${sync_pointer_skipped:-0}" != "1" && "${git_dependent_gates_skipped:-0}" != "1" && "${firing_path_digests_injected:-0}" != "1" ]]; then
  echo "ccl_skill_check_clean_ok"
else
  if [[ "$r0_clean_landing_status" != "private-ok" ]]; then
    echo "ccl_skill_check_interim_notice: private R0 alias audit did not run (r0_status=${r0_clean_landing_status}); this is interim, NOT clean-landing — do not merge or mark R0-clean without alias_audit_ok, a named private profile, or a risk-owner waiver"
  fi
  if [[ "${register_nonterminal_status:-0}" == "1" ]]; then
    echo "ccl_skill_check_interim_notice: the changed source-register diff adds pending/interim status row(s) (see register_nonterminal_status_added above); a pending/interim ledger row blocks a clean-landing/complete claim — resolve or supersede those rows before marking this landing clean/complete"
  fi
  if [[ "${sync_pointer_skipped:-0}" == "1" ]]; then
    echo "ccl_skill_check_interim_notice: semantic sync checks were partially skipped (missing agent-context/session-start.md or package) — skip is NOT a full evaluation (sync_semantic_check_unevaluated semantics); this run is interim, not clean-landing"
  fi
  echo "ccl_skill_check_interim_ok"
fi
