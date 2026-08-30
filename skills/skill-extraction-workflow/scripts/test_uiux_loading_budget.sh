#!/usr/bin/env bash
# Deterministic context-loading proxy for the UI/UX skill split.
#
# This test counts source bytes, not provider tokens or task quality. It proves
# exact byte cost of three documented loading profiles versus the immutable
# origin/dev entry+router path, while keeping the full contract one hop from the
# entry and every routed reference local and resolvable. Real provider load,
# token, latency, correction, and task-quality claims still require task trials.
set -euo pipefail

ROOT="${UIUX_LOADING_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
DEFAULT_BASE_REF="e322db47abe5736e6e1fdf0e73e2ed3eb32c006b"
BASE_REF="${UIUX_LOADING_BASE_REF:-$DEFAULT_BASE_REF}"
ENTRY_REL="skills/product-ui-ux-design/SKILL.md"
ROUTER_REL="skills/product-ui-ux-design/references/design-execution-checklist.md"
CONTRACT_REL="skills/product-ui-ux-design/references/delivery-contract.md"
ENTRY="$ROOT/$ENTRY_REL"
ROUTER="$ROOT/$ROUTER_REL"
CONTRACT="$ROOT/$CONTRACT_REL"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for file in "$ENTRY" "$ROUTER" "$CONTRACT"; do
  [ -s "$file" ] || fail "required loading-profile file missing or empty: ${file#$ROOT/}"
done

if [ "$BASE_REF" != "$DEFAULT_BASE_REF" ] && [ "${UIUX_LOADING_FIXTURE_MODE:-}" != "1" ]; then
  fail "UIUX_LOADING_BASE_REF override requires UIUX_LOADING_FIXTURE_MODE=1"
fi

resolved_base_sha=$(git -C "$ROOT" rev-parse --verify "$BASE_REF^{commit}" 2>/dev/null) ||
  fail "immutable loading-budget base is unavailable: $BASE_REF"
base_entry_blob=$(git -C "$ROOT" rev-parse "$resolved_base_sha:$ENTRY_REL")
base_router_blob=$(git -C "$ROOT" rev-parse "$resolved_base_sha:$ROUTER_REL")

base_bytes() {
  git -C "$ROOT" show "$BASE_REF:$1" | wc -c | tr -d ' '
}

file_bytes() {
  wc -c < "$1" | tr -d ' '
}

active_markdown() {
  ruby -e '
    in_comment = false
    fence = nil
    ARGF.each_line do |raw|
      line = raw.chomp
      if fence
        if (m = line.match(/\A {0,3}(`{3,}|~{3,})[ \t]*\z/))
          run = m[1]
          fence = nil if run[0] == fence[0] && run.length >= fence.length
        end
        next
      end
      loop do
        if in_comment
          close_at = line.index("-->")
          if close_at
            line = line[(close_at + 3)..] || ""
            in_comment = false
          else
            line = ""
            break
          end
        else
          open_at = line.index("<!--")
          break unless open_at
          close_at = line.index("-->", open_at + 4)
          if close_at
            line = line[0...open_at] + (line[(close_at + 3)..] || "")
          else
            line = line[0...open_at]
            in_comment = true
            break
          end
        end
      end
      if (m = line.match(/\A {0,3}(`{3,}|~{3,})(.*)\z/))
        run = m[1]
        info = m[2]
        unless run[0] == "`" && info.include?("`")
          fence = run
          next
        end
      end
      next if line.match?(/\A(?:\t| {4})/)
      puts line unless line.empty?
    end
  ' "$1"
}

active_literal_count() {
  local file="$1" needle="$2"
  active_markdown "$file" | ruby -e '
    needle = ARGV.fetch(0)
    print STDIN.read.scan(Regexp.new(Regexp.escape(needle))).length
  ' "$needle"
}

active_loading_contradiction() {
  active_markdown "$1" | ruby -e '
    text = STDIN.read.downcase
    allowed = [
      "a runtime-visible task enters `references/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path.",
      "load `references/design-execution-checklist.md` only when the task needs one or more specialized work-mode, platform, risk, or evidence references whose route is not already unambiguous below.",
      "do not load the router solely to reach `references/delivery-contract.md` or another unambiguous common route.",
      "this router is conditional context, not an always-loaded prerequisite.",
      "load this router when delivery depth must be composed with specialized work-mode, platform, risk, or evidence lenses.",
      "when the router applies, select one delivery-depth profile for runtime work, then add every triggered work-mode and risk lens and load the union of their required references."
    ]
    allowed.each { |sentence| text = text.gsub(sentence, "") }
    text = text.gsub("feature-risk-router", "")
               .gsub("# design execution router", "")
    unapproved_router_language = /(?:design-execution-checklist\.md|router|routing\s+(?:reference|checklist)|路由|分流(?:参考|清单))/
    exit(text.match?(unapproved_router_language) ? 0 : 1)
  '
}

loading_contract_valid() {
  local entry="$1" router="$2"
  [ "$(active_literal_count "$entry" 'A runtime-visible task enters `references/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path.')" = "1" ] &&
    [ "$(active_literal_count "$entry" 'Load `references/design-execution-checklist.md` only when the task needs one or more specialized work-mode, platform, risk, or evidence references whose route is not already unambiguous below.')" = "1" ] &&
    [ "$(active_literal_count "$entry" 'Do not load the router solely to reach `references/delivery-contract.md` or another unambiguous common route.')" = "1" ] &&
    [ "$(active_literal_count "$router" 'This router is conditional context, not an always-loaded prerequisite.')" = "1" ] &&
    [ "$(active_literal_count "$router" 'Load this router when delivery depth must be composed with specialized work-mode, platform, risk, or evidence lenses.')" = "1" ] &&
    ! active_loading_contradiction "$entry" &&
    ! active_loading_contradiction "$router"
}

extract_active_references() {
  local file="$1"
  active_markdown "$file" | ruby -e '
    source = ARGV.fetch(0)
    refs = []
    STDIN.read.each_line do |line|
      line = line.gsub(/\[[^\]]*\]\(([^)\s]+\.md(?:#[^)\s]+)?)\)/) do
        refs << Regexp.last_match(1)
        ""
      end
      line = line.gsub(/`([^`\n]+\.md(?:#[^`\n]+)?)`/) do
        refs << Regexp.last_match(1)
        ""
      end
      line.scan(/(?:\.\.?\/)?(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+\.md(?:#[^\s,;)\]}]+)?/) do |match|
        refs << match
      end
    end
    refs.uniq.sort.each { |ref| puts "#{source}\t#{ref}" }
  ' "$file"
}

reference_integrity_valid() {
  local root="$1" entry="$2" router="$3" source ref
  while IFS=$'\t' read -r source ref; do
    [ -n "$ref" ] || continue
    ruby -e '
      root, source, ref = ARGV
      ref = ref.split("#", 2).first
      exit 1 if ref.nil? || ref.empty? || ref.start_with?("/")
      source_dir = File.dirname(File.expand_path(source))
      candidate = if ref.start_with?("references/")
        File.expand_path(ref, source_dir)
      else
        File.expand_path(ref, source_dir)
      end
      skills_root = File.expand_path("skills", root) + File::SEPARATOR
      exit 1 unless candidate.start_with?(skills_root)
      stat = File.lstat(candidate) rescue exit(1)
      exit 1 unless stat.file? && !stat.symlink?
      real = File.realpath(candidate) rescue exit(1)
      exit 1 unless real.start_with?(skills_root)
    ' "$root" "$source" "$ref" || return 1
  done < <(
    extract_active_references "$entry"
    extract_active_references "$router"
  )
}

loading_contract_valid "$ENTRY" "$ROUTER" ||
  fail "entry/router still make the routing reference unconditional or hide the direct runtime path"
reference_integrity_valid "$ROOT" "$ENTRY" "$ROUTER" ||
  fail "an active entry/router Markdown reference is missing, a symlink, external, or outside skills/"

base_entry_bytes=$(base_bytes "$ENTRY_REL")
base_router_bytes=$(base_bytes "$ROUTER_REL")
base_mandatory_bytes=$((base_entry_bytes + base_router_bytes))
candidate_entry_bytes=$(file_bytes "$ENTRY")
candidate_router_bytes=$(file_bytes "$ROUTER")
candidate_contract_bytes=$(file_bytes "$CONTRACT")
candidate_routing_proxy_bytes=$((candidate_entry_bytes + candidate_router_bytes))
candidate_direct_runtime_bytes=$((candidate_entry_bytes + candidate_contract_bytes))
candidate_specialized_runtime_bytes=$((candidate_entry_bytes + candidate_router_bytes + candidate_contract_bytes))

# The old entry explicitly required the router for every task. The new direct
# routing/source-audit proxy must use at most half that deterministic byte
# proxy; the direct runtime path at most 90%. Complex runtime work loads all
# three files and may pay a bounded quality-contract cost, capped at 110%.
# These are migration budgets, not provider token or task-effect claims.
(( candidate_routing_proxy_bytes * 100 <= base_mandatory_bytes * 50 )) ||
  fail "routing/source-audit proxy exceeds 50% of origin/dev mandatory bytes ($candidate_routing_proxy_bytes > 50% of $base_mandatory_bytes)"
(( candidate_direct_runtime_bytes * 100 <= base_mandatory_bytes * 90 )) ||
  fail "direct-runtime proxy exceeds 90% of origin/dev mandatory bytes ($candidate_direct_runtime_bytes > 90% of $base_mandatory_bytes)"
(( candidate_specialized_runtime_bytes * 100 <= base_mandatory_bytes * 110 )) ||
  fail "specialized-runtime proxy exceeds 110% of origin/dev mandatory bytes ($candidate_specialized_runtime_bytes > 110% of $base_mandatory_bytes)"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/uiux-loading-budget.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

sed 's/A runtime-visible task enters `references\/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path./A runtime-visible task enters `references\/delivery-contract.md` only after the specialized router./' \
  "$ENTRY" > "$tmp_dir/runtime-through-router.md"
if loading_contract_valid "$tmp_dir/runtime-through-router.md" "$ROUTER"; then
  fail "direct-runtime-route deletion mutation survived"
fi

sed 's/This router is conditional context, not an always-loaded prerequisite./This router is the always-loaded prerequisite./' \
  "$ROUTER" > "$tmp_dir/always-loaded-router.md"
if loading_contract_valid "$ENTRY" "$tmp_dir/always-loaded-router.md"; then
  fail "conditional-router deletion mutation survived"
fi

cp "$ENTRY" "$tmp_dir/contradictory-entry.md"
printf '\nAlways load `references/design-execution-checklist.md` before `references/delivery-contract.md`.\n' >> "$tmp_dir/contradictory-entry.md"
if loading_contract_valid "$tmp_dir/contradictory-entry.md" "$ROUTER"; then
  fail "contradictory always-load instruction survived"
fi

cp "$ENTRY" "$tmp_dir/synonym-always-load-entry.md"
printf '\nEvery task must load the specialized router.\n' >> "$tmp_dir/synonym-always-load-entry.md"
if loading_contract_valid "$tmp_dir/synonym-always-load-entry.md" "$ROUTER"; then
  fail "synonym always-load instruction survived"
fi

cp "$ENTRY" "$tmp_dir/routing-reference-always-load-entry.md"
printf '\nEvery task starts by consulting the specialized routing reference.\n' >> "$tmp_dir/routing-reference-always-load-entry.md"
if loading_contract_valid "$tmp_dir/routing-reference-always-load-entry.md" "$ROUTER"; then
  fail "routing-reference always-load instruction survived"
fi

cp "$ENTRY" "$tmp_dir/chinese-always-load-entry.md"
printf '\n所有任务都必须先加载专用路由。\n' >> "$tmp_dir/chinese-always-load-entry.md"
if loading_contract_valid "$tmp_dir/chinese-always-load-entry.md" "$ROUTER"; then
  fail "Chinese always-load instruction survived"
fi

sed 's/A runtime-visible task enters `references\/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path./<!-- A runtime-visible task enters `references\/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path. -->/' \
  "$ENTRY" > "$tmp_dir/comment-only-direct-route.md"
if loading_contract_valid "$tmp_dir/comment-only-direct-route.md" "$ROUTER"; then
  fail "comment-only direct-runtime carrier survived"
fi

fixture_root="$tmp_dir/reference-fixture"
mkdir -p "$fixture_root/skills" "$fixture_root/skills/skill-extraction-workflow/references"
cp -R "$ROOT/skills/product-ui-ux-design" "$fixture_root/skills/product-ui-ux-design"
cp "$ROOT/skills/skill-extraction-workflow/references/two-source-extraction-pattern.md" \
  "$fixture_root/skills/skill-extraction-workflow/references/two-source-extraction-pattern.md"
fixture_entry="$fixture_root/$ENTRY_REL"
fixture_router="$fixture_root/$ROUTER_REL"
fixture_analytics="$fixture_root/skills/product-ui-ux-design/references/analytics-visualization-interactions.md"
mv "$fixture_analytics" "$fixture_analytics.absent"
if reference_integrity_valid "$fixture_root" "$fixture_entry" "$fixture_router"; then
  fail "missing routed reference survived"
fi
mv "$fixture_analytics.absent" "$fixture_analytics"
printf '\nFor every design task, load missing-runtime-guidance.md before proceeding.\n' >> "$fixture_entry"
if reference_integrity_valid "$fixture_root" "$fixture_entry" "$fixture_router"; then
  fail "missing bare-path reference survived"
fi
cp "$ROOT/$ENTRY_REL" "$fixture_entry"
fixture_contract="$fixture_root/$CONTRACT_REL"
mv "$fixture_contract" "$fixture_contract.regular"
ln -s /etc/hosts "$fixture_contract"
if reference_integrity_valid "$fixture_root" "$fixture_entry" "$fixture_router"; then
  fail "external symlink reference survived"
fi

candidate_entry_sha256=$(shasum -a 256 "$ENTRY" | awk '{print $1}')
candidate_router_sha256=$(shasum -a 256 "$ROUTER" | awk '{print $1}')
candidate_contract_sha256=$(shasum -a 256 "$CONTRACT" | awk '{print $1}')
printf 'uiux_loading_budget_ok base_sha=%s base_entry_blob=%s base_router_blob=%s base_mandatory_bytes=%s routing_proxy_bytes=%s direct_runtime_bytes=%s specialized_runtime_bytes=%s candidate_sha256=%s,%s,%s\n' \
  "$resolved_base_sha" "$base_entry_blob" "$base_router_blob" "$base_mandatory_bytes" \
  "$candidate_routing_proxy_bytes" "$candidate_direct_runtime_bytes" "$candidate_specialized_runtime_bytes" \
  "$candidate_entry_sha256" "$candidate_router_sha256" "$candidate_contract_sha256"
