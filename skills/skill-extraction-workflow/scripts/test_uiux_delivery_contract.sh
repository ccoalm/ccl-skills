#!/usr/bin/env bash
# Contract test for the shared design -> test -> producer/client implementation loop.
# The canonical reference owns the protocol; each participating skill keeps
# only its local responsibility and a pointer to that reference.
set -euo pipefail

ROOT="${UIUX_CONTRACT_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
CONTRACT="$ROOT/skills/product-ui-ux-design/references/delivery-contract.md"
ROUTER="$ROOT/skills/product-ui-ux-design/references/design-execution-checklist.md"
LEDGER="$ROOT/skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md"
SOURCE_MAP="$ROOT/skills/product-ui-ux-design/references/source-map.md"
INTERACTION="$ROOT/skills/product-ui-ux-design/references/interaction-design-patterns.md"
TEST_MATRIX="$ROOT/skills/testing-strategy/references/client-runtime-test-matrices.md"
APP_OWNER="$ROOT/skills/app-cross-platform-dev/SKILL.md"
PRODUCT_DESIGN_ROUTE="$ROOT/skills/product-rd-workflow/references/design-routing-and-readiness.md"
OPERATIONAL="$ROOT/skills/product-ui-ux-design/references/operational-processing-workflows.md"
fail=0

active_markdown() {
  ruby -e '
    in_comment = false
    fence = nil
    ARGF.each_line.with_index(1) do |raw, line_number|
      line = raw.chomp
      # Inside a fenced block, HTML-comment markers are literal code. Resolve
      # only a valid CommonMark closing fence before any comment parsing;
      # otherwise `<!--` in an example can swallow the real close and every
      # operative line that follows it.
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
      # Top-level four-space/tab indentation is a CommonMark code block, not
      # operative prose. Normative carriers in this contract must remain
      # unindented or use an explicit list marker, which also keeps the oracle
      # from certifying an obligation shown only as a code example.
      next if line.match?(/\A(?:\t| {4})/)
      puts "#{line_number}\t#{line}" unless line.empty?
    end
  ' "$1"
}

active_text() {
  active_markdown "$1" | cut -f2-
}

outside_fence_contains() {
  local file="$1" needle="$2"
  [ -f "$file" ] || return 1
  active_markdown "$file" | ruby -e '
    needle = ARGV.shift
    rows = ARGF.each_line.filter_map do |raw|
      number, text = raw.chomp.split("\t", 2)
      [Integer(number, 10), text || ""]
    rescue ArgumentError
      nil
    end

    segments = []
    current = []
    previous = nil
    rows.each do |number, text|
      if previous && number != previous + 1
        segments << current unless current.empty?
        current = []
      end
      current << text
      previous = number
    end
    segments << current unless current.empty?

    escaped = lambda do |chars, index|
      count = 0
      cursor = index - 1
      while cursor >= 0 && chars[cursor] == "\\"
        count += 1
        cursor -= 1
      end
      count.odd?
    end

    token_only = needle.match?(/\A[[:alnum:]_][[:alnum:]_.:\/-]*\z/)
    segments.each do |lines|
      text = lines.join("\n")
      chars = text.each_char.to_a
      spans = []
      cursor = 0
      while cursor < chars.length
        unless chars[cursor] == "`" && !escaped.call(chars, cursor)
          cursor += 1
          next
        end
        opener_start = cursor
        cursor += 1 while cursor < chars.length && chars[cursor] == "`"
        opener_end = cursor
        run_length = opener_end - opener_start
        probe = opener_end
        closer_start = nil
        closer_end = nil
        while probe < chars.length
          unless chars[probe] == "`" && !escaped.call(chars, probe)
            probe += 1
            next
          end
          run_start = probe
          probe += 1 while probe < chars.length && chars[probe] == "`"
          if probe - run_start == run_length
            closer_start = run_start
            closer_end = probe
            break
          end
        end
        if closer_start
          spans << [opener_end, closer_start]
          cursor = closer_end
        else
          cursor = opener_end
        end
      end

      offset = 0
      while (match_at = text.index(needle, offset))
        match_end = match_at + needle.length
        code_only = spans.any? { |start_at, end_at| match_at >= start_at && match_end <= end_at }
        exit 0 unless code_only && !token_only
        offset = match_at + 1
      end
    end
    exit 1
  ' "$needle"
}

check() {
  local file="$1" needle="$2" label="$3"
  if [ ! -f "$file" ]; then
    echo "FAIL: $label target missing ($file)" >&2
    fail=1
  elif ! outside_fence_contains "$file" "$needle"; then
    echo "FAIL: $label missing: $needle" >&2
    fail=1
  fi
}

check_absent() {
  local pattern="$1" label="$2"; shift 2
  local hits
  hits=$(grep -Erin -- "$pattern" "$@" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL: $label" >&2
    printf '%s\n' "$hits" >&2
    fail=1
  fi
}

client_entry_valid() {
  local line
  line=$(active_text "$1" | grep -F 'Before the first implementation edit, add the canonical `client_entry` defined there:' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'local rule identifier or short quote and implementation decision'*'target surface/runtime'*'planned run/capture command'*'behavior that must remain unchanged'*) return 0 ;;
    *) return 1 ;;
  esac
}

client_return_valid() {
  local file="$1" line field
  line=$(active_text "$file" | grep -F 'Return the complete canonical client-record member defined in `../product-ui-ux-design/references/delivery-contract.md` for testing Phase 1 and the design verdict.' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  for field in "applied rule/decision" "affected files/components" "preserved behavior" "exact command" "immutable candidate binding" "producer member/version actually exercised" "artifacts" "tested" "criterion-mapped observations" "coverage boundary" "gaps"; do
    case "$line" in
      *"$field"*) ;;
      *) return 1 ;;
    esac
  done
}

check_client_return() {
  local file="$1" owner="$2"
  if ! client_return_valid "$file"; then
    echo "FAIL: $owner complete canonical client-record return is missing or incomplete" >&2
    fail=1
  fi
}

resolved_markdown_reference_valid() {
  local file="$1" relative="$2" base="${3:-$(dirname "$1")}"
  active_text "$file" | grep -F "\`$relative\`" >/dev/null &&
    [ -f "$base/$relative" ]
}

stage_order_valid() {
  local file="$1" last=0 line lines heading
  [ -f "$file" ] || return 1
  for heading in \
    "## 1. Design brief" \
    "## 2. Test Phase 0 — layer selection" \
    "## 3. Producer/client execution" \
    "## 4. Test Phase 1 — execution result and sufficiency" \
    "## 5. Design verdict"; do
    lines=$(active_markdown "$file" | awk -v heading="$heading" '
      {
        separator = index($0, "\t")
        line_number = substr($0, 1, separator - 1)
        content = substr($0, separator + 1)
        if (content == heading) print line_number
      }
    ')
    [ "$(printf '%s\n' "$lines" | awk 'NF { n++ } END { print n + 0 }')" -eq 1 ] || return 1
    line="$lines"
    [ -n "$line" ] && [ "$line" -gt "$last" ] || return 1
    last="$line"
  done
}

producer_route_valid() {
  local route delta
  if active_text "$1" | grep -E 'pre-runtime-test-ready|pending \+|unknown-consumers|classify that member|have every affected client owner|required design/test/producer/client' >/dev/null; then
    return 1
  fi
  route=$(active_text "$1" | grep -F "When a change can alter what a client renders or which state, action, or decision path it offers" || true)
  delta=$(active_text "$1" | grep -F 'returns only its `producer_record` delta:' || true)
  [ "$(printf '%s\n' "$route" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  [ "$(printf '%s\n' "$delta" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$route" in
    *'API/event/schema fields'*'load `../product-ui-ux-design/references/delivery-contract.md`'*'create the applicable full or lightweight record in that contract'*'follow its canonical consumer-universe classification, design/test/client handoffs, and terminal-status rules'*) ;;
    *) return 1 ;;
  esac
  case "$delta" in
    *'immutable binding'*'exact command/environment'*'API/event/log/output observation'*) ;;
    *) return 1 ;;
  esac
  ! printf '%s\n' "$route" | grep -F '`producer_record` delta' >/dev/null
}

router_composition_valid() {
  local file="$1"
  active_text "$file" | grep -F 'choose one delivery-depth profile, then add every work-mode and risk lens whose trigger is present' >/dev/null &&
    active_text "$file" | grep -F 'Load the union of their references; one lens never cancels another' >/dev/null &&
    active_text "$file" | grep -F 'a source-led systemic redesign or a shared-system redesign loads both sets' >/dev/null &&
    active_text "$file" | grep -F '../../skill-extraction-workflow/references/two-source-extraction-pattern.md' >/dev/null
}

router_mode_reachability_valid() {
  local file="$1" mode="$2" trigger="$3" reference="$4" line
  line=$(active_text "$file" | grep -F "| $mode |" || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *"$trigger"*"$reference"*) return 0 ;;
    *) return 1 ;;
  esac
}

router_lens_reachability_valid() {
  local file="$1" trigger="$2" reference="$3" line
  line=$(active_text "$file" | grep -F "| $trigger |" || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *"$reference"*) return 0 ;;
    *) return 1 ;;
  esac
}

router_lens_terms_valid() {
  local file="$1" reference="$2" line term
  shift 2
  line=$(active_text "$file" | grep -F "$reference" || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  for term in "$@"; do
    case "$line" in
      *"$term"*) ;;
      *) return 1 ;;
    esac
  done
}

entrypoint_router_valid() {
  local entry="$1" router="$2"
  [ -f "$router" ] &&
    active_text "$entry" | grep -F 'A runtime-visible task enters `references/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path.' >/dev/null &&
    active_text "$entry" | grep -F 'Load `references/design-execution-checklist.md` only when the task needs one or more specialized work-mode, platform, risk, or evidence references whose route is not already unambiguous below.' >/dev/null &&
    active_text "$entry" | grep -F 'Do not load the router solely to reach `references/delivery-contract.md` or another unambiguous common route.' >/dev/null &&
    active_text "$entry" | grep -F 'When the router applies, select one delivery-depth profile for runtime work, then add every triggered work-mode and risk lens and load the union of their required references.' >/dev/null &&
    active_text "$router" | grep -F 'This router is conditional context, not an always-loaded prerequisite.' >/dev/null
}

app_design_closeout_valid() {
  local file="$1" line
  line=$(active_text "$file" | grep -F 'A missing or absent design verdict remains' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'remains `pending`'*'blocks the canonical contract'*'`complete`, MR-ready, merge-ready'*'screenshot proves only that the app rendered'*'never design acceptance'*'the design owner applies `delivery-contract.md`'*'rejected-candidate path'*'fresh runtime evidence for the revised candidate'*) return 0 ;;
    *) return 1 ;;
  esac
}

testing_phase0_inputs_valid() {
  local file="$1" line
  line=$(active_text "$file" | grep -F 'For a full UI/UX slice, Test selection Phase 0 derives its case set' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *"Design brief's state/adaptation matrix"*'criterion IDs/outcomes'*'RED baseline'*'testing owns verifier type, assertion/rendered-evidence layers, commands/targets, independent oracles, and gaps'*'do not silently replace or narrow the recorded design obligations'*) return 0 ;;
    *) return 1 ;;
  esac
}

testing_incomplete_branches_valid() {
  local file="$1" line
  line=$(active_text "$file" | grep -F 'Phase 0 is incomplete when' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'applicable full/lightweight design inputs are missing, or when'*'DOM/component existence, a build pass, or an unreviewed screenshot is used in place of required rendered, interaction, accessibility, recovery, or design evidence'*) return 0 ;;
    *) return 1 ;;
  esac
}

composite_owner_valid() {
  local file="$1"
  active_text "$file" | grep -F 'A composite host has multiple owner-set members' >/dev/null &&
    active_text "$file" | grep -F 'React inside a native WebView uses `web-react-dev` for content and `app-cross-platform-dev` for the native container/bridge' >/dev/null &&
    active_text "$file" | grep -F 'A mini-program `web-view` uses the actual web-content owner plus `miniapp-product-dev`' >/dev/null &&
    active_text "$file" | grep -F 'Electron uses the actual web-content owner plus the installed desktop-shell owner or project client convention' >/dev/null &&
    active_text "$file" | grep -F 'Vue, Svelte, static, vendor, or another renderer routes to its installed owner or the fail-closed project-convention lookup below, never to React by container name alone' >/dev/null &&
    active_text "$file" | grep -F 'An unchanged host member still records the integration contract and proof that the change cannot affect it' >/dev/null
}

multistack_owner_valid() {
  local file="$1"
  active_text "$file" | grep -F '| **native-mobile** | Flutter, React Native, native iOS, or native Android app | `app-cross-platform-dev` |' >/dev/null &&
    active_text "$file" | grep -F 'Electron renderer → actual web-content owner; Electron shell → installed desktop-shell owner or project client convention' >/dev/null &&
    active_text "$file" | grep -F 'Other desktop/TV runtimes → their installed owner or the same fail-closed project-convention lookup' >/dev/null &&
    active_text "$file" | grep -F 'Actual web-content owner: enforces the web renderer' >/dev/null &&
    active_text "$file" | grep -F '`terminal-cli-dev`: enforces terminal/TUI' >/dev/null &&
    active_text "$file" | grep -F 'Installed desktop-shell owner or project client convention: owns Electron shell and other desktop/TV layers' >/dev/null &&
    active_text "$file" | grep -F '`terminal-tui` / `desktop-tv-shell`' >/dev/null &&
    active_text "$file" | grep -F '| **terminal-tui** | Command tree, help/output contract, terminal workflow, ANSI renderer, or full-screen TUI | `terminal-cli-dev`' >/dev/null &&
    active_text "$file" | grep -F 'Route every affected consumer: React web → `web-react-dev`; other web → its installed owner or project convention; native mobile → `app-cross-platform-dev`; mini-app → `miniapp-product-dev`; terminal/TUI → `terminal-cli-dev`; desktop/TV shell → its installed owner or fail-closed project convention' >/dev/null &&
    ! active_text "$file" | grep -F 'Mobile / desktop / TV client (Flutter, native iOS, native Android, RN, Electron) | `app-cross-platform-dev`' >/dev/null
}

design_mode_owner_valid() {
  local development="$1" source_map="$2" frontend_map="$3" multistack="$4"
  active_text "$development" | grep -F 'Vue/Svelte/static/vendor/other web → its installed web-content owner or fail-closed project-convention lookup' >/dev/null &&
    active_text "$development" | grep -F 'Composite hosts keep separate content and shell members' >/dev/null &&
    active_text "$source_map" | grep -F 'Implementation rules follow the complete affected client-owner set in `delivery-contract.md`' >/dev/null &&
    active_text "$source_map" | grep -F 'a missing owner is never silently treated as Web or React' >/dev/null &&
    active_text "$frontend_map" | grep -F 'React browser implementation ownership → `web-react-dev`; Vue/Svelte/static/vendor/other browser implementation → its installed web-content owner or the fail-closed project-convention lookup' >/dev/null &&
    active_text "$multistack" | grep -F '| **web** | Browser-targeted application' | grep -F 'React → `web-react-dev`; Vue/Svelte/static/vendor/other web → its installed web-content owner or the fail-closed project-convention lookup' >/dev/null
}

restored_reference_owner_valid() {
  local naming="$1" tokens="$2" source_truth="$3"
  active_text "$naming" | grep -F 'follows every affected client owner in `delivery-contract.md`' >/dev/null &&
    active_text "$naming" | grep -F 'mini-app → `miniapp-product-dev`; terminal/TUI → `terminal-cli-dev`' >/dev/null &&
    active_text "$naming" | grep -F 'Electron shell, desktop, TV, or another runtime → its installed owner or the fail-closed project-convention lookup' >/dev/null &&
    active_text "$naming" | grep -F 'code gating follows every affected client owner in `delivery-contract.md`: React web → `web-react-dev`; other web → its installed owner or project convention; native mobile → `app-cross-platform-dev`; mini-app → `miniapp-product-dev`; terminal/TUI → `terminal-cli-dev`; Electron/desktop/TV → its installed owner or fail-closed project convention' >/dev/null &&
    active_text "$tokens" | grep -F 'React or other web, web H5, native app, mini-program, terminal/TUI, Electron/desktop, TV, or another rendered client' >/dev/null &&
    active_text "$tokens" | grep -F 'The complete affected client-owner set in `delivery-contract.md` owns the concrete prop / option names for each component set' >/dev/null &&
    active_text "$tokens" | grep -F 'follow the complete affected client-owner set in `delivery-contract.md`' >/dev/null &&
    active_text "$tokens" | grep -F 'Vue/Svelte/other web → its installed owner or project convention' >/dev/null &&
    active_text "$tokens" | grep -F 'terminal/TUI theme/color behavior → `terminal-cli-dev`' >/dev/null &&
    active_text "$tokens" | grep -F 'A shared theme package never becomes React-owned merely because one consumer uses React' >/dev/null &&
    active_text "$source_truth" | grep -F 'follows every affected client owner in `delivery-contract.md`' >/dev/null &&
    active_text "$source_truth" | grep -F 'a Web-only tool is not evidence for a native, terminal, or desktop client' >/dev/null
}

binding_contract_valid() {
  local file="$1"
  active_text "$file" | grep -F 'Each binding value has a non-empty, exact payload' >/dev/null &&
    active_text "$file" | grep -F '`dirty-bundle-v1:<full-base-commit-hex>:<64-hex-bundle-digest>`' >/dev/null &&
    active_text "$file" | grep -F 'the byte-exact binary tracked diff' >/dev/null &&
    active_text "$file" | grep -F 'every untracked member, and every result-affecting ignored member, all in sorted path order with path, file mode/type, and raw content or symlink target' >/dev/null &&
    active_text "$file" | grep -F 'one keyed member per design/test/producer/client repository or artifact' >/dev/null &&
    active_text "$file" | grep -F 'A `commit` or `tree` binding is valid for an executed member only when the command ran from that exact materialized commit/tree' >/dev/null &&
    active_text "$file" | grep -F 'Do not relabel a dirty execution as a clean commit after the fact' >/dev/null &&
    active_text "$file" | grep -F 'Branches, tags, abbreviated SHAs, empty suffixes, mutable external version labels or artifact paths, and prose such as “current working tree” are locators, not immutable bindings' >/dev/null &&
    active_text "$file" | grep -F 'covered by an `artifact-sha256` member over the exact reviewed bytes plus its locator' >/dev/null &&
    active_text "$file" | grep -F 'a result-affecting input outside the checkout must have its own `artifact-sha256` member over the exact bytes' >/dev/null &&
    active_text "$file" | grep -F 'Result-affecting external inputs always use a separate content-addressed member and locator' >/dev/null
}

candidate_member_contract_valid() {
  local file="$1"
  active_text "$file" | grep -F 'every changed or claim-bearing producer first adds one member to `producer_record_set`' >/dev/null &&
    active_text "$file" | grep -F 'Each client execution must name which producer member/version it actually exercised' >/dev/null &&
    active_text "$file" | grep -F '`design_record_ids`' >/dev/null &&
    active_text "$file" | grep -F '`test_record_ids`' >/dev/null &&
    active_text "$file" | grep -F '`producer_record_ids`' >/dev/null &&
    active_text "$file" | grep -F '`client_record_ids`' >/dev/null &&
    active_text "$file" | grep -F 'which producer observation, client observation, or test artifact supports it' >/dev/null &&
    active_text "$file" | grep -F 'Each design, test, producer, and client owner writes its own facts once' >/dev/null &&
    active_text "$file" | grep -F 'Missing, mismatched, stale, changed-after-run, or unexercised required design/test/producer/client owner or binding members make sufficiency `blocked`' >/dev/null
}

lightweight_all_role_valid() {
  local file="$1"
  active_text "$file" | grep -F 'same component, rendering slot, or output field' >/dev/null &&
    active_text "$file" | grep -F 'the design/test owners, every changed or claim-bearing producer owner, and every affected client owner' >/dev/null &&
    active_text "$file" | grep -F 'The lightweight design record, test definitions/executions, and producer/client returns still form the complete immutable candidate-binding set' >/dev/null &&
    active_text "$file" | grep -F 'Phase 1 binds and cites the complete design/test/producer/client record sets' >/dev/null
}

copy_only_misclassification_valid() {
  local file="$1" line
  line=$(active_text "$file" | grep -F 'If later evidence proves the `copy-only` classification wrong' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'the lightweight record is invalid from that discovery point, and you must apply **Missed pre-edit record** to the existing diff by stopping implementation edits'*'rebuilding the full Design brief, obtaining full Phase 0 and every affected producer/client owner entry'*'auditing the whole existing diff against them'*'rerunning producer/client execution, Phase 1, and the design verdict'*'the slice is `pending + blocked`'*'the old lightweight result cannot support completion'*) return 0 ;;
    *) return 1 ;;
  esac
}

trigger_class_set_valid() {
  local file="$1" line
  line=$(active_text "$file" | grep -F '| `trigger_class` |' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'`copy-only`, `narrow-visible`, `new-or-reshaped-screen`, or `systemic-redesign`'*'`shared-system`, `source-code-evidence`, `design-to-code`, `audit/review`, `naming-version-sync`, `same-stack-multi-project`, and `multi-stack`'*) return 0 ;;
    *) return 1 ;;
  esac
}

terminal_cli_contract_valid() {
  local terminal="$1" go="$2" python="$3" product_route="$4"
  active_text "$terminal" | grep -F 'command/subcommand/flag/default/help/output/exit/action/confirmation/progress/recovery contract' >/dev/null &&
    active_text "$terminal" | grep -F 'Skip only parser/library/tooling internals' >/dev/null &&
    active_text "$terminal" | grep -F 'provably preserve every user-facing command tree, default/action path, help/output/exit behavior, confirmation, progress, and recovery path' >/dev/null &&
    active_text "$terminal" | grep -F 'even when it emits only plain text and never enters an alternate screen' >/dev/null &&
    active_text "$terminal" | grep -F 'For every user-facing terminal/CLI contract change—including command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, or recovery' >/dev/null &&
    active_text "$terminal" | grep -F 'Only parser/library internals that preserve all of those user-visible semantics may mark UI/UX `not-applicable`' >/dev/null &&
    active_text "$go" | grep -F 'Any change to a user-facing command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, or recovery path also loads `terminal-cli-dev`' >/dev/null &&
    active_text "$python" | grep -F 'Any change to a user-facing command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, or recovery path also loads `terminal-cli-dev`' >/dev/null &&
    active_text "$product_route" | grep -F 'Any changed command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, recovery' >/dev/null
}

reachable_reference_scope_valid() {
  local multistack="$1" source_truth="$2" multiproject="$3" tokens="$4" layout="$5" lifecycle="$6"
  active_text "$multistack" | grep -F 'React and other web, H5, native mobile, mini-app, terminal/TUI, Electron/desktop, and TV consumers' >/dev/null &&
    active_text "$multistack" | grep -F 'React or other web, H5, native mobile, mini-app, terminal/TUI, Electron/desktop, TV, or another client' >/dev/null &&
    active_text "$multistack" | grep -F 'React web, other web, H5, native, mini-app, terminal/TUI, Electron/desktop/TV shell, and any additional client' >/dev/null &&
    active_text "$source_truth" | grep -F 'React and other web, H5, native mobile, mini-app, terminal/TUI, Electron/desktop, TV, and any additional client' >/dev/null &&
    active_text "$source_truth" | grep -F 'map every rendered stack in the authoritative consumer inventory' >/dev/null &&
    active_text "$multiproject" | grep -F 'every same-stack subproject uses the same canonical UI-kit/component family for that rendered stack' >/dev/null &&
    active_text "$multiproject" | grep -F 'find the actual theme injection or token-consumption point' >/dev/null &&
    active_text "$multiproject" | grep -F 'terminal palette/style registry' >/dev/null &&
    active_text "$tokens" | grep -F '## Complete Consumer Set' >/dev/null &&
    active_text "$tokens" | grep -F 'absence from the desktop/mobile examples is never `not-applicable` proof' >/dev/null &&
    active_text "$layout" | grep -F 'ordinary CLI or full-screen terminal/TUI, Electron/desktop/TV shell' >/dev/null &&
    active_text "$layout" | grep -F 'TTY and non-TTY/plain modes as applicable' >/dev/null &&
    active_text "$lifecycle" | grep -F 'the canonical prerequisite and acceptance path is `delivery-contract.md`: Design brief → Test Phase 0 → producer/client execution → Test Phase 1/sufficiency → design verdict' >/dev/null &&
    active_text "$lifecycle" | grep -F 'Every runtime-ready or launch-ready claim cites the complete immutable design/test/producer/client binding set and an allowed verdict' >/dev/null &&
    active_text "$lifecycle" | grep -F 'Start these launch gates only after the exact candidate is `accepted + complete`' >/dev/null
}

reachable_finish_paths_valid() {
  local entry="$1" intake="$2" development="$3" lifecycle="$4" source_map="$5"
  local interaction="$6" visual="$7" audit="$8" surface="$9" external="${10}"
  active_text "$entry" | grep -F 'The complete affected client-owner set owns implementation and runtime evidence' >/dev/null &&
    active_text "$entry" | grep -F 'Vue/Svelte/static/vendor/other web → its installed owner or fail-closed project-convention lookup' >/dev/null &&
    active_text "$entry" | grep -F 'Electron/desktop/TV shell → its installed owner or the same lookup' >/dev/null &&
    active_text "$intake" | grep -F 'It supplies design-owned intake and criteria to the five top-level stages in `delivery-contract.md`' >/dev/null &&
    active_text "$intake" | grep -F 'Passing them locally is not completion' >/dev/null &&
    active_text "$intake" | grep -F 'complete five-stage contract, immutable design/test/producer/client binding set' >/dev/null &&
    active_text "$intake" | grep -F 'absence from the Web/mobile examples is not `not-applicable` proof' >/dev/null &&
    active_text "$development" | grep -F 'Build the complete affected client-owner set from `delivery-contract.md`' >/dev/null &&
    active_text "$development" | grep -F 'It cannot by itself finish the slice; completion requires bound design and test records, every changed producer and affected client return, Test Phase 1 sufficiency, and an allowed design verdict' >/dev/null &&
    active_text "$lifecycle" | grep -F 'do not invent a second design-readiness status' >/dev/null &&
    active_text "$lifecycle" | grep -F 'cannot override the canonical design verdict' >/dev/null &&
    active_text "$source_map" | grep -F '`react-web` / `other-web`' >/dev/null &&
    active_text "$source_map" | grep -F '`desktop-tv-shell` / `mixed-host` / `other-client`' >/dev/null &&
    active_text "$interaction" | grep -F 'it cannot issue ready/complete' >/dev/null &&
    active_text "$interaction" | grep -F 'complete design/test/producer/client binding set' >/dev/null &&
    active_text "$visual" | grep -F 'they cannot mark a runtime slice ready or complete' >/dev/null &&
    active_text "$visual" | grep -F 'complete design/test/producer/client set' >/dev/null &&
    active_text "$audit" | grep -F 'not an independent acceptance path' >/dev/null &&
    active_text "$audit" | grep -F 'React/other-Web, H5, native, mini-app, terminal/CLI/TUI, Electron/desktop/TV, other-client, and composite-host layer' >/dev/null &&
    active_text "$surface" | grep -F 'Ordinary CLI or terminal/TUI' >/dev/null &&
    active_text "$surface" | grep -F 'Vue/Svelte/static/vendor/other content and shell layers route to their installed owner or the fail-closed project-convention lookup' >/dev/null &&
    active_text "$external" | grep -F 'Windows/Linux native desktop, Electron, TV, and any other rendered client' >/dev/null &&
    active_text "$external" | grep -F 'An embedded renderer and its shell remain separate owner/evidence members' >/dev/null
}

parallel_completion_claims_absent() {
  local file
  for file in "$@"; do
    if active_text "$file" | grep -Eiq \
      'Passing .*(marks|makes|finishes|completes).*(ready|complete)|marks? (the )?(runtime )?slice complete without|Launch readiness:[[:space:]]*(pass|conditional pass|block)|(^|[.;] )(may|can|does) issue (its own|an independent|a second) .*verdict|(may|can) override the canonical design verdict|implementation is considered ready:|this checklist (is|becomes) sufficient'; then
      return 1
    fi
  done
}

all_design_references_no_parallel_completion() {
  parallel_completion_claims_absent \
    "$ROOT/skills/product-ui-ux-design/SKILL.md" \
    "$ROOT"/skills/product-ui-ux-design/references/*.md \
    "$ROOT/docs/uiux-design-handbook.md" \
    "$ROOT/docs/client-dev-handbook.md" \
    "$ROOT/docs/testing-handbook.md" \
    "$ROOT/docs/feature-delivery-handbook.md" \
    "$ROOT/docs/backend-dev-handbook.md" \
    "$ROOT/docs/llm-algorithm-handbook.md" \
    "$@"
}

unknown_handoff_valid() {
  local line
  line=$(active_text "$1" | grep -F "An incomplete universe or inaccessible member remains" || true)
  line=${line%%$'\n'*}
  case "$line" in
    *'blocks a complete claim'*'terminal state remains `pending + blocked`'*'acceptance of the handoff is not design acceptance or completion'*) return 0 ;;
    *) return 1 ;;
  esac
}

contract_status_pairs() {
  active_markdown "$1" | awk '
    {
      separator = index($0, "\t")
      line = substr($0, separator + 1)
    }
    line == "| Verdict | Next state | Required condition |" { table = 1; next }
    table && line ~ /^\| ---/ { next }
    table && line ~ /^\|/ {
      split(line, cell, "|")
      verdict = cell[2]
      state = cell[3]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", verdict)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", state)
      gsub(/`/, "", verdict)
      gsub(/`/, "", state)
      print verdict ":" state
      next
    }
    table { exit }
  '
}

status_pair_valid() {
  local file="$1" verdict="$2" state="$3"
  contract_status_pairs "$file" | grep -Fx -- "$verdict:$state" >/dev/null
}

status_pair_set_valid() {
  local file="$1" actual expected
  actual=$(contract_status_pairs "$file" | LC_ALL=C sort)
  expected=$(printf '%s\n' \
    accepted:complete \
    candidate:blocked \
    pending:blocked \
    pending:pre-runtime-test-ready \
    rejected:design-rejected | LC_ALL=C sort)
  [ "$actual" = "$expected" ]
}

accepted_completion_valid() {
  local line
  line=$(active_text "$1" | grep -F '| `accepted` | `complete` |' || true)
  [ "$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || return 1
  case "$line" in
    *'The bound Phase 1 `sufficiency` is `sufficient` and no required evidence gap remains'*'every required design/test/producer/client owner, record, exercised-version link, and binding-set member is present and verified'*) return 0 ;;
    *) return 1 ;;
  esac
}

contract_binding_specs() {
  active_markdown "$1" | awk '
    {
      separator = index($0, "\t")
      line = substr($0, separator + 1)
    }
    line == "| Binding kind | Exact payload |" { table = 1; next }
    table && line ~ /^\| ---/ { next }
    table && line ~ /^\|/ {
      split(line, cell, "|")
      kind = cell[2]
      payload = cell[3]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", kind)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", payload)
      gsub(/`/, "", kind)
      gsub(/`/, "", payload)
      print kind ":" payload
      next
    }
    table { exit }
  '
}

binding_spec_set_valid() {
  local file="$1" actual expected
  actual=$(contract_binding_specs "$file" | LC_ALL=C sort)
  expected=$(printf '%s\n' \
    'artifact-sha256:artifact-sha256:<64-hex>' \
    'commit:commit:<full-40-or-64-hex>' \
    'dirty-bundle-v1:dirty-bundle-v1:<full-base-commit-hex>:<64-hex-bundle-digest>' \
    'tree:tree:<full-40-or-64-hex>' | LC_ALL=C sort)
  [ "$actual" = "$expected" ]
}

immutable_binding_kind() {
  local value="$1"
  [[ "$value" =~ ^commit:([[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]] ||
    [[ "$value" =~ ^tree:([[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]] ||
    [[ "$value" =~ ^artifact-sha256:[[:xdigit:]]{64}$ ]] ||
    [[ "$value" =~ ^dirty-bundle-v1:([[:xdigit:]]{40}|[[:xdigit:]]{64}):[[:xdigit:]]{64}$ ]]
}

check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "references/delivery-contract.md" \
  "design owner canonical delivery-contract pointer"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "acceptance is conformance" \
  "specified-state source conformance obligation"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "sweep detection across them" \
  "repeatable defect-class sibling sweep obligation"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "performance, adaptation, launch acceptance, iteration signals, AI-assistant patterns" \
  "full design capability scope remains explicit"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "obtain the source's required review before code follows" \
  "specified treatment changes design source before code"
check "$ROOT/skills/product-ui-ux-design/references/design-execution-checklist.md" \
  "delivery-contract.md" \
  "design routing checklist delivery-contract pointer"
check "$ROOT/docs/uiux-design-handbook.md" \
  "../skills/product-ui-ux-design/references/delivery-contract.md" \
  "reader handbook canonical delivery-contract pointer"
check "$ROOT/docs/client-dev-handbook.md" \
  "../skills/product-ui-ux-design/references/delivery-contract.md" \
  "client handbook canonical delivery-contract pointer"
check "$ROOT/docs/testing-handbook.md" \
  "../skills/product-ui-ux-design/references/delivery-contract.md" \
  "testing handbook canonical delivery-contract pointer"
check "$ROOT/docs/feature-delivery-handbook.md" \
  "../skills/product-ui-ux-design/references/delivery-contract.md" \
  "feature delivery handbook canonical delivery-contract pointer"
check "$ROOT/docs/feature-delivery-handbook.md" \
  '后端 `python-service-dev` 记录导出 API 的 `producer_record`、不可变 binding' \
  "feature example returns the producer member"
check "$ROOT/docs/feature-delivery-handbook.md" \
  '测试 Phase 1：`testing-strategy` 引用完整 design/test/producer/client record 与 binding set' \
  "feature example runs testing Phase 1"
check "$ROOT/docs/feature-delivery-handbook.md" \
  '只有满足 canonical contract 的 `accepted + complete` 才能写完成' \
  "feature example closes through the design verdict"
check "$ROOT/docs/backend-dev-handbook.md" \
  '../skills/product-ui-ux-design/references/delivery-contract.md' \
  "backend handbook canonical delivery-contract pointer"
check "$ROOT/docs/backend-dev-handbook.md" \
  'Go/Python owner 回传自己的 `producer_record` 和不可变 binding' \
  "backend handbook producer/client return"
check "$ROOT/docs/backend-dev-handbook.md" \
  '记 `unknown-consumers`、缺口 owner/动作，只能 `pending + blocked`' \
  "backend handbook unknown consumer fail-closed path"
check "$ROOT/docs/backend-dev-handbook.md" \
  'Phase 1 聚合集合判充分性，最后由设计 owner 给 verdict' \
  "backend handbook Phase 1 and design verdict"
check "$ROOT/docs/llm-algorithm-handbook.md" \
  '../skills/product-ui-ux-design/references/delivery-contract.md' \
  "LLM handbook canonical delivery-contract pointer"
check "$ROOT/docs/llm-algorithm-handbook.md" \
  '`llm-inference-integration` 回传 prompt/model/tool 等 `producer_record` 与不可变 binding' \
  "LLM handbook producer/client return"
check "$ROOT/docs/llm-algorithm-handbook.md" \
  '记 `unknown-consumers`、缺口 owner/动作，保持 `pending + blocked`' \
  "LLM handbook unknown consumer fail-closed path"
check "$ROOT/docs/llm-algorithm-handbook.md" \
  'Phase 1 聚合 design/test/producer/client 集合判充分性，设计 owner 再给 verdict' \
  "LLM handbook Phase 1 and design verdict"

for owner in testing-strategy web-react-dev app-cross-platform-dev miniapp-product-dev terminal-cli-dev; do
  check "$ROOT/skills/$owner/SKILL.md" \
    '`../product-ui-ux-design/references/delivery-contract.md`' \
    "$owner reciprocal delivery-contract pointer"
done

for owner in web-react-dev app-cross-platform-dev miniapp-product-dev terminal-cli-dev; do
  if ! client_entry_valid "$ROOT/skills/$owner/SKILL.md"; then
    echo "FAIL: $owner canonical pre-edit client_entry is incomplete" >&2
    fail=1
  fi
  check_client_return "$ROOT/skills/$owner/SKILL.md" "$owner"
  check "$ROOT/skills/$owner/SKILL.md" \
    "valid low-risk copy-only record + lightweight Phase 0" \
    "$owner reachable copy-only path"
done

for producer in go-microservice-dev python-service-dev llm-inference-integration; do
  check "$ROOT/skills/$producer/SKILL.md" \
    '`../product-ui-ux-design/references/delivery-contract.md`' \
    "$producer visible-consumer delivery-contract pointer"
  if ! producer_route_valid "$ROOT/skills/$producer/SKILL.md"; then
    echo "FAIL: $producer must delegate canonical routing/status and return only its producer delta" >&2
    fail=1
  fi
done

if ! resolved_markdown_reference_valid "$TEST_MATRIX" '../../product-ui-ux-design/references/delivery-contract.md'; then
  echo "FAIL: testing matrix canonical delivery-contract reference does not resolve" >&2
  fail=1
fi
for relative in \
  '../../product-ui-ux-design/references/delivery-contract.md' \
  '../../product-ui-ux-design/references/multi-project-token-consistency.md' \
  '../../product-ui-ux-design/references/design-execution-checklist.md'; do
  if ! resolved_markdown_reference_valid "$PRODUCT_DESIGN_ROUTE" "$relative"; then
    echo "FAIL: product design-routing reference does not resolve: $relative" >&2
    fail=1
  fi
done

check_absent \
  'If any client renders the value, or the universe/member is incomplete, use `unknown-consumers`' \
  "known visible consumer is incorrectly classified unknown" \
  "$ROOT/skills/go-microservice-dev/SKILL.md" \
  "$ROOT/skills/python-service-dev/SKILL.md" \
  "$ROOT/skills/llm-inference-integration/SKILL.md"

check "$ROOT/skills/product-rd-workflow/SKILL.md" \
  '`../product-ui-ux-design/references/delivery-contract.md`' \
  "product lifecycle delivery-contract pointer"
check "$ROOT/skills/product-rd-workflow/references/design-routing-and-readiness.md" \
  "design brief → test Phase 0 → producer/client execution → test Phase 1/sufficiency → design verdict" \
  "product lifecycle names the full producer/client stage"
check "$ROOT/docs/uiux-design-handbook.md" \
  '`design/test/producer/client-record set`' \
  "reader handbook names all execution record sets"
check "$ROOT/docs/uiux-design-handbook.md" \
  'reference 相对路径能实际解析、客户端首笔实现前的 `client_entry` 与完整回传，以及 producer 是否只指向 canonical universe/status' \
  "reader handbook explains the cross-owner static gate"
check "$ROOT/docs/client-dev-handbook.md" \
  '先按 [`delivery-contract.md`](../skills/product-ui-ux-design/references/delivery-contract.md) 写 `client_entry`' \
  "client handbook requires the pre-edit client entry"
check "$ROOT/docs/client-dev-handbook.md" \
  '实跑后回传完整 canonical client member' \
  "client handbook requires the complete client return"
check "$ROOT/docs/uiux-design-handbook.md" \
  "所有影响结果的 ignored path/mode/type/content" \
  "reader handbook binds ignored result-affecting inputs"
check "$ROOT/docs/uiux-design-handbook.md" \
  'Phase 1 明确为 `sufficient`、没有 required evidence gap' \
  "reader handbook prevents insufficient accepted+complete"
check "$ROOT/docs/testing-handbook.md" \
  'Phase 1 为 `sufficient` 且没有 required evidence gap' \
  "testing handbook prevents insufficient accepted+complete"
check "$ROOT/docs/testing-handbook.md" \
  '缺 `client_entry`、client member 不完整' \
  "testing handbook blocks an incomplete client handoff"

if ! stage_order_valid "$CONTRACT"; then
  echo "FAIL: delivery stages are missing, duplicated, or out of order" >&2
  fail=1
fi

check "$CONTRACT" "Phase 0 — layer selection" "non-circular pre-implementation test selection"
check "$CONTRACT" "Phase 1 — execution result and sufficiency" "post-client test result and sufficiency"
check "$CONTRACT" '`Design brief → Test Phase 0 → Producer/client execution → Test Phase 1/sufficiency → Design verdict`' "canonical owner/pass sequence"
check "$CONTRACT" '`client_record_ids`' "Phase 1 references every client execution member"
check "$CONTRACT" '`producer_record_ids`' "Phase 1 references every producer execution member"
check "$CONTRACT" "instead of copying them" "single-write runtime evidence ownership"
check "$CONTRACT" "visible-UI, page-slice, design-checkpoint, or rendered-evidence rule plus the decision it produced" "client-entry rule evidence closed set"
check "$CONTRACT" "Arbitrary skill text, a file path, runtime name, or vague anchor alone is not evidence" "client-entry vague-anchor rejection"
check "$CONTRACT" "A project-convention owner must quote the specific surface/interaction/evidence convention applied" "project convention entry evidence"
check "$CONTRACT" "The design brief does not select verifier type" "test-layer ownership stays out of design criteria"
check "$CONTRACT" "missing test-owned fields cannot make the brief incomplete" "non-circular brief completeness"
check "$CONTRACT" "criterion_results" "criterion-level design verdict"
check "$CONTRACT" "candidate_binding" "verdict candidate binding"
check "$CONTRACT" "Branches, tags, abbreviated SHAs, empty suffixes" "immutable evidence binding"
check "$CONTRACT" "candidate_binding_set" "multi-owner immutable evidence binding"
check "$CONTRACT" 'Missing, mismatched, stale, changed-after-run, or unexercised required design/test/producer/client owner or binding members make sufficiency `blocked`' "all-role member aggregation fails closed"
if ! composite_owner_valid "$CONTRACT"; then
  echo "FAIL: composite-host client owner set is incomplete" >&2
  fail=1
fi
if ! binding_contract_valid "$CONTRACT"; then
  echo "FAIL: candidate binding-set contract is incomplete" >&2
  fail=1
fi
if ! binding_spec_set_valid "$CONTRACT"; then
  echo "FAIL: candidate binding-kind table is not the exact closed allowed set" >&2
  fail=1
fi
if ! candidate_member_contract_valid "$CONTRACT"; then
  echo "FAIL: design/test/producer/client record, binding, or exercised-version linkage is incomplete" >&2
  fail=1
fi
if ! trigger_class_set_valid "$CONTRACT"; then
  echo "FAIL: delivery-depth and composable work-mode trigger classes are not synchronized" >&2
  fail=1
fi
check "$CONTRACT" "coverage boundary" "deterministic gate coverage boundary"
check "$CONTRACT" "authoritative consumer universe" "complete consumer-universe requirement"
check "$CONTRACT" "Only a value or contract change proven not to render on or alter any client may leave this contract" "proven backend-only routing boundary"
check "$CONTRACT" "using API/log/output evidence plus the recorded consumer-universe proof" "backend-only evidence handoff"
check "$CONTRACT" 'Classify a consumer as `out-of-scope` only when evidence shows that stack cannot ship the value' "out-of-scope closed proof boundary"
check "$CONTRACT" "owner-lookup-unavailable" "no-installed-owner fail-closed lookup"
check "$CONTRACT" "every screen remains its own full design slice" "systemic redesign per-screen slice"
check "$CONTRACT" "grouping content and actions by user intent and consequence" "systemic redesign IA re-derivation"
check "$CONTRACT" "A bare ownership declaration does not authorize a behavior change" "silent IA behavior change is a defect"
check "$CONTRACT" '`reference_surface`' "reference surface or explicit fallback"
check "$CONTRACT" "Before editing a design artifact, UI copy, visual rule, design-system guidance, or code-facing acceptance criterion" "design planning precedes edits and approval"
check "$CONTRACT" "named producer/test/client handoff before edit or approval" "design brief names all execution owners"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "Each changed or claim-bearing backend/config/content/inference owner owns its producer artifact or version identity" \
  "design entrypoint exposes producer ownership"
check "$CONTRACT" "surface type, and density mode" "design brief density mode"
check "$CONTRACT" "return context, and component semantics" "design brief component semantics"
check "$CONTRACT" "behavioral logic, aesthetic/visual hierarchy and craft, interaction, and component-semantics criteria" "design brief quality criteria"
check "$CONTRACT" "A retroactive brief without the diff audit cannot bless" "missed-record remediation"
check "$CONTRACT" "remove it before commit and before completion" "temporary helper cleanup boundary"
check "$CONTRACT" "does not repeatedly interrupt the operator" "batched evidence collection avoids prompt churn"
check "$CONTRACT" "lightweight record is complete with" "copy-only minimal record"
if ! lightweight_all_role_valid "$CONTRACT"; then
  echo "FAIL: copy-only path omits a design/test/producer/client owner, record, or binding obligation" >&2
  fail=1
fi
if ! copy_only_misclassification_valid "$CONTRACT"; then
  echo "FAIL: copy-only misclassification lost full remediation or blocking semantics" >&2
  fail=1
fi
check "$CONTRACT" "All other terminal combinations are invalid" "closed verdict-state algebra"
check "$CONTRACT" 'terminal state remains `pending + blocked`' "unknown-consumers handoff remains blocked"
if ! unknown_handoff_valid "$CONTRACT"; then
  echo "FAIL: user-accepted unknown-consumers handoff can escape blocked state" >&2
  fail=1
fi
check "$CONTRACT" '`rejection_basis`' "rejection basis classification"
check "$CONTRACT" 'A `deterministic-conformance` rejection may be repaired by a targeted change' "deterministic rejection repair path"
check "$CONTRACT" 'A `design-judgment` or `mixed` rejection requires a revised design target' "judgment rejection independent-review path"
check "$CONTRACT" "the rejected render or screenshot is negative evidence and cannot be reused as acceptance evidence" "rejected evidence cannot launder acceptance"
check "$CONTRACT" "every normal or ordinary draft MR" "rejected design blocks normal draft handoff"
check "$CONTRACT" "every attempted capture command, its observed failure, the residual risk, and the next unblock action" "unavailable rendered evidence requires attempted capture"
check "$CONTRACT" "A hand-authored or echoed transcript is fabricated evidence" "fabricated rendered evidence severity"
check "$CONTRACT" '`planned` includes the exact capture command/step and must resolve before a final design verdict' "planned evidence final boundary"
check "$CONTRACT" "residual risk and explicitly accepts proceeding without that evidence for this specific change in the current thread" "specific current-thread evidence-gap acceptance"
check "$CONTRACT" "re-renders the actual artifact set at review time" "aggregate final review fresh render"
check "$CONTRACT" "intentionally replaces the blanket rule that an author can never accept any slice" "bounded deterministic author-acceptance decision is explicit"
check "$CONTRACT" 'A missing or absent design verdict is `pending` and blocks `complete`, MR-ready' "missing verdict blocks completion and MR readiness"
check "$CONTRACT" "Before landing executable design guidance that affects multiple client stacks" "cross-stack owner naming before landing"
check "$CONTRACT" "mirror its executable form into every affected owner" "cross-stack design rule propagation"
check "$CONTRACT" "streaming/background progress, focus/modal state, and jump/new-output affordance evidence" "terminal design evidence completeness"
check "$CONTRACT" "any rendered layer without an installed client owner" "project convention fallback covers every runtime"
check "$TEST_MATRIX" \
  "Do not copy role-owned raw fields into a second record" \
  "testing Phase 1 single-write rule"
check "$TEST_MATRIX" \
  'A missing canonical `client_entry`, incomplete client-record member' \
  "testing Phase 1 blocks an incomplete client handoff"
check "$ROOT/skills/testing-strategy/SKILL.md" \
  "a UI/UX Design brief with a stable slice/surface" \
  "current design brief confirms bounded test scope"
check "$ROOT/skills/testing-strategy/SKILL.md" \
  'confirms every affected client wrote its canonical pre-edit `client_entry` and complete client-record member' \
  "testing owner checks the complete client handoff"
check "$ROOT/skills/testing-strategy/SKILL.md" \
  "two or more plausible scopes remain and choosing among them would materially change the test plan" \
  "ambiguous test scope still asks"
check "$ROOT/skills/testing-strategy/SKILL.md" \
  "A current, resolvable Design brief or accepted scope artifact is evidence, not inference" \
  "scope artifact is not mistaken for unsupported inference"
check "$ROUTER" \
  "This router is conditional context, not an always-loaded prerequisite." \
  "router conditional-loading contract"
if ! entrypoint_router_valid "$ROOT/skills/product-ui-ux-design/SKILL.md" "$ROUTER"; then
  echo "FAIL: product-ui-ux-design entrypoint lost its direct runtime route or conditional one-hop router route" >&2
  fail=1
fi
if ! router_composition_valid "$ROUTER"; then
  echo "FAIL: delivery-depth/work-mode reference union is incomplete" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Audit/review" "at any delivery depth" "ui-ux-audit.md"; then
  echo "FAIL: narrow audit/review tasks cannot reliably reach the audit procedure" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Naming/version synchronization" "Figma↔code naming drift" "design-impl-naming-and-versioning.md"; then
  echo "FAIL: naming/version drift tasks cannot reach their focused reference" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Source/code evidence" "local frontend implementation evidence" "frontend-code-evidence-map.md"; then
  echo "FAIL: code-evidence audits cannot reach the frontend evidence map" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Design-to-code" "Applying design decisions to client code" "ui-ux-design-development.md"; then
  echo "FAIL: design-to-client implementation cannot reach the primitive catalog" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Same-stack multi-project" "same end/stack" "multi-project-token-consistency.md"; then
  echo "FAIL: same-stack multi-subproject theme work cannot reach its consistency procedure" >&2
  fail=1
fi
if ! router_mode_reachability_valid "$ROUTER" "Multi-stack" "spans multiple client stacks" "multi-stack-strategy.md"; then
  echo "FAIL: multi-stack/composite-host tasks cannot reach their focused reference" >&2
  fail=1
fi
check "$ROUTER" \
  'also load `multi-project-token-consistency.md` when the same framework spans different ends and shares brand/theme infrastructure' \
  "same-framework cross-end tasks compose multi-stack and shared-theme references"
if ! router_lens_reachability_valid "$ROUTER" \
  "Layout recipe, component density, workbench structure, empty/loading/error geometry, or screenshot/render acceptance" \
  "layout-recipes-and-screenshot-acceptance.md"; then
  echo "FAIL: narrow state/layout/screenshot work cannot reach its recipe and acceptance reference" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "platform-web-desktop-patterns.md" "admin"; then
  echo "FAIL: Web platform lens lost its admin trigger" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "platform-mobile-patterns.md" "App/app-hosted"; then
  echo "FAIL: mobile platform lens lost its App/app-hosted trigger" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "operational-processing-workflows.md" \
  "capture" "upload/import" "queue" "progress monitoring" "assignment/ownership" "exception handling" "quality-control" "moderation"; then
  echo "FAIL: operational lens lost one or more established triggers" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "trust-sensitive-ai-and-data-patterns.md" \
  "upload" "citation" "analytics" "moderation decision" "long-running workflow" "instrumentation"; then
  echo "FAIL: trust lens lost one or more established triggers" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "resource-management-interactions.md" "content-pack"; then
  echo "FAIL: resource lens lost its content-pack trigger" >&2
  fail=1
fi
if ! router_lens_terms_valid "$ROUTER" "scenario-community-patterns.md" \
  "Community/social/feed/creator/topic/profile/notification/moderation/AI-social"; then
  echo "FAIL: community lens lost one or more established triggers" >&2
  fail=1
fi
if ! router_lens_reachability_valid "$ROUTER" \
  "Generic surface/loop taxonomy, account/settings, decision/review, AI-assisted or workflow-extension pattern, or no focused scenario lens fits" \
  "product-surface-patterns.md"; then
  echo "FAIL: generic non-scenario surface work cannot reach the surface/loop taxonomy" >&2
  fail=1
fi
if ! router_lens_reachability_valid "$ROUTER" \
  "Visual polish, brand feel, anti-slop, typography/hierarchy, iconography, or material treatment" \
  "visual-craft.md"; then
  echo "FAIL: narrow visual-polish work cannot reach visual craft guidance" >&2
  fail=1
fi
if ! router_lens_reachability_valid "$ROUTER" \
  "Attention, motivation, perceived effort, trust psychology, habit loop, or behavioral/aesthetic judgment" \
  "behavioral-aesthetic-logic.md"; then
  echo "FAIL: narrow behavioral/aesthetic work cannot reach its judgment reference" >&2
  fail=1
fi
if ! router_lens_reachability_valid "$ROUTER" \
  "Design-system source authority, third-party mirror detection, brand-token ownership, or wrong design-source comments in code/theme files" \
  "design-system-source-of-truth.md"; then
  echo "FAIL: design-system authority audits cannot reach the source-of-truth procedure" >&2
  fail=1
fi
check "$ROUTER" \
  "Which producer, test, and client owners must return which evidence before a verdict?" \
  "router closeout includes producer/test/client owners"
if [ ! -f "$ROOT/skills/skill-extraction-workflow/references/two-source-extraction-pattern.md" ]; then
  echo "FAIL: source-pair extraction reference target is missing" >&2
  fail=1
fi
for routed_reference in \
  ui-ux-audit.md \
  ui-ux-design-development.md \
  frontend-code-evidence-map.md \
  layout-recipes-and-screenshot-acceptance.md \
  product-surface-patterns.md \
  design-impl-naming-and-versioning.md \
  multi-stack-strategy.md \
  multi-project-token-consistency.md; do
  if [ ! -f "$ROOT/skills/product-ui-ux-design/references/$routed_reference" ]; then
    echo "FAIL: routed design reference is missing: $routed_reference" >&2
    fail=1
  fi
done
if ! multistack_owner_valid "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md"; then
  echo "FAIL: reachable multi-stack guidance contradicts canonical client ownership" >&2
  fail=1
fi
if ! design_mode_owner_valid \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/frontend-code-evidence-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md"; then
  echo "FAIL: design-to-code/source-code-evidence guidance narrows the actual Web or composite-host owner set" >&2
  fail=1
fi
if ! restored_reference_owner_valid \
  "$ROOT/skills/product-ui-ux-design/references/design-impl-naming-and-versioning.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md"; then
  echo "FAIL: restored naming/theme references narrow the canonical client-owner set" >&2
  fail=1
fi
if ! terminal_cli_contract_valid \
  "$ROOT/skills/terminal-cli-dev/SKILL.md" \
  "$ROOT/skills/go-microservice-dev/SKILL.md" \
  "$ROOT/skills/python-service-dev/SKILL.md" \
  "$ROOT/skills/product-rd-workflow/references/design-routing-and-readiness.md"; then
  echo "FAIL: ordinary user-facing CLI changes can escape terminal UI/UX/testing ownership" >&2
  fail=1
fi
if ! reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: a reachable design reference narrows the canonical consumer set or opens a parallel completion path" >&2
  fail=1
fi
if ! reachable_finish_paths_valid \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-intake-and-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/interaction-design-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/visual-craft.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-surface-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md"; then
  echo "FAIL: a reachable design lens narrows the owner set or opens an independent ready/complete path" >&2
  fail=1
fi
if ! all_design_references_no_parallel_completion; then
  echo "FAIL: a reachable design reference contains a parallel ready/complete/verdict path" >&2
  fail=1
fi
check "$ROOT/docs/client-dev-handbook.md" \
  "组件语义、无障碍/焦点/键盘" \
  "non-rendered classification includes interaction semantics"
check "$PRODUCT_DESIGN_ROUTE" \
  "A clearly labeled review-only draft MR may carry the revised bound candidate" \
  "rejected design review-only handoff"
for pair in \
  '| `accepted` | `complete` |' \
  '| `rejected` | `design-rejected` |' \
  '| `pending` | `pre-runtime-test-ready` |' \
  '| `pending` | `blocked` |' \
  '| `candidate` | `blocked` |'; do
  check "$CONTRACT" "$pair" "allowed verdict/next-state pair"
done

for valid in "accepted complete" "rejected design-rejected" "pending pre-runtime-test-ready" "pending blocked" "candidate blocked"; do
  set -- $valid
  status_pair_valid "$CONTRACT" "$1" "$2" || { echo "FAIL: valid contract status rejected: $valid" >&2; fail=1; }
done
for invalid in "accepted pre-runtime-test-ready" "accepted blocked" "pending complete" "candidate complete" "rejected complete"; do
  set -- $invalid
  if status_pair_valid "$CONTRACT" "$1" "$2"; then
    echo "FAIL: contradictory contract status accepted: $invalid" >&2
    fail=1
  fi
done
if ! status_pair_set_valid "$CONTRACT"; then
  echo "FAIL: contract status table is not the exact closed allowed set" >&2
  fail=1
fi
if ! accepted_completion_valid "$CONTRACT"; then
  echo "FAIL: accepted+complete does not require sufficient bound Phase 1 evidence" >&2
  fail=1
fi
for binding in \
  "commit:0123456789abcdef0123456789abcdef01234567" \
  "tree:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" \
  "artifact-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" \
  "dirty-bundle-v1:0123456789abcdef0123456789abcdef01234567:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; do
  immutable_binding_kind "$binding" || { echo "FAIL: immutable binding fixture rejected: $binding" >&2; fail=1; }
done
for invalid_binding in \
  "branch:feature/ui" \
  "commit:" \
  "commit:abc" \
  "tree:" \
  "artifact-sha256:" \
  "base+dirty-sha256:" \
  "dirty-bundle-v1::" \
  "dirty-bundle-v1:0123456789abcdef0123456789abcdef01234567:"; do
  if immutable_binding_kind "$invalid_binding"; then
    echo "FAIL: incomplete or mutable binding fixture accepted: $invalid_binding" >&2
    fail=1
  fi
done

for owner in testing-strategy web-react-dev app-cross-platform-dev miniapp-product-dev terminal-cli-dev; do
  check "$CONTRACT" "\`$owner\`" "delivery-contract owner coverage"
done

for state in candidate accepted rejected pending complete pre-runtime-test-ready design-rejected blocked; do
  check "$CONTRACT" "\`$state\`" "delivery-contract status vocabulary"
done

check "$CONTRACT" "Heuristic review is risk discovery, not acceptance proof" \
  "heuristic evidence boundary"
check "$CONTRACT" "rendered evidence" "runtime evidence requirement"
check "$CONTRACT" "unknown-consumers" "multi-consumer honesty state"
check "$CONTRACT" "Copy acceptance is semantic" "copy-only semantic acceptance guardrails"
check "$INTERACTION" "hidden when disclosure would be unsafe" \
  "disabled-state disclosure boundary"
check "$INTERACTION" "placeholder text cannot be the only label" \
  "form-label accessibility boundary"
check "$INTERACTION" "Backend logs alone do not satisfy this user-facing contract" \
  "dangerous-operation accountability is visible"
check "$INTERACTION" "reserved or non-rebindable key combinations and actions" \
  "shortcut reserved-key contract"
check "$INTERACTION" "text-input, IME/composition, and editable-content safety" \
  "shortcut composition safety"
check "$INTERACTION" "a visible reset-to-defaults recovery path" \
  "shortcut recovery contract"
check "$OPERATIONAL" "do not use a marketing-style hero banner, decorative gradient as the design, oversized empty illustration, heavy visual drama" \
  "operational workspace anti-marketing prohibition"
check "$SOURCE_MAP" "terminal-tui" "terminal source classification"
check "$SOURCE_MAP" "other-web" "other-Web source classification"
check "$SOURCE_MAP" "desktop-tv-shell" "desktop/TV shell source classification"
check "$SOURCE_MAP" "fully extract every non-excluded file" "formal source re-extraction completeness"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "render classes such as overflow" \
  "render-class sibling sweep requires re-render"
check "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "retroactive brief cannot bless" \
  "design entry missed-record remediation"
check "$TEST_MATRIX" \
  "valid low-risk copy-only record" \
  "testing lightweight copy path"
check "$TEST_MATRIX" \
  "candidate_binding_set" \
  "testing immutable Phase 1 binding"
if ! app_design_closeout_valid "$APP_OWNER"; then
  echo "FAIL: app design closeout lost verdict blocking, screenshot boundary, or rejected-candidate recapture" >&2
  fail=1
fi
if ! testing_phase0_inputs_valid "$TEST_MATRIX"; then
  echo "FAIL: testing Phase 0 lost a design input, no-narrowing rule, or test-owned layer" >&2
  fail=1
fi
if ! testing_incomplete_branches_valid "$TEST_MATRIX"; then
  echo "FAIL: testing Phase 0 incomplete rule lost a top-level branch or named evidence substitution" >&2
  fail=1
fi

for profile in \
  "Copy-only" \
  "Narrow visible change" \
  "New or reshaped screen" \
  "Systemic redesign" \
  "Shared system" \
  "Source/code evidence" \
  "Design-to-code" \
  "Audit/review" \
  "Naming/version synchronization" \
  "Same-stack multi-project" \
  "Multi-stack"; do
  check "$ROUTER" "| $profile |" "design execution profile"
done

for source in \
  "https://www.iso.org/standard/77520.html" \
  "https://www.iso.org/standard/63500.html" \
  "https://www.w3.org/TR/WCAG22/" \
  "https://www.w3.org/TR/WCAG22/#target-size-minimum" \
  "https://www.w3.org/TR/WCAG22/#animation-from-interactions" \
  "https://www.w3.org/TR/WCAG22/#error-prevention-legal-financial-data" \
  "https://www.w3.org/WAI/ARIA/apg/about/introduction/" \
  "https://developer.apple.com/design/human-interface-guidelines/buttons" \
  "https://developer.android.com/guide/topics/ui/accessibility/apps" \
  "https://doi.org/10.3758/BF03195514" \
  "https://doi.org/10.1006/ijhc.2002.1017" \
  "https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/"; do
  check "$LEDGER" "$source" "primary theory/source ledger entry"
done

check "$LEDGER" "not a W3C Standard" "design-token authority boundary"
check "$LEDGER" "not a complete design system or production-ready code" \
  "ARIA pattern authority boundary"
check "$LEDGER" "55%–99%" "five-user empirical range boundary"
check "$LEDGER" "The Understanding document is informative" \
  "normative criterion versus informative explanation boundary"
check "$LEDGER" "Retain the source's publication status" \
  "web specification maturity boundary"
check "$LEDGER" "Apple-platform guidance for button hit regions, not a universal touch-target constant" \
  "Apple button hit-region authority boundary"
check "$ROOT/skills/skill-extraction-workflow/references/uiux-judgment-extraction.md" \
  "Apple HIG's general-rule hit region of at least 44×44pt" \
  "extraction guidance keeps Apple hit-region strength and scope"
check "$ROOT/skills/product-ui-ux-design/references/platform-mobile-patterns.md" \
  "Keep both platform-scoped; do not average them into a universal number" \
  "mobile reference keeps Apple and Android target guidance scoped"
check "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" \
  "map applicable criteria into \`delivery-contract.md\`" \
  "platform audit uses the authority-classed contract path"

check_absent \
  'canonical four-phase|Its four phases|phase order|before Phase [234]|Phase 2 and Phase 3' \
  "stage/pass terminology drift remains" \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "$ROOT/skills/product-ui-ux-design/references/delivery-contract.md" \
  "$ROOT/skills/testing-strategy/SKILL.md"

check_absent \
  'within (five|5) seconds|five[- ]second|5[- ]second' \
  "arbitrary five-second acceptance threshold remains" \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "$ROOT/skills/product-ui-ux-design/references"

check_absent \
  '^- (Hick|Fitts|Miller|Doherty)[/:]' \
  "unbounded eponym shorthand remains in UI/UX extraction guidance" \
  "$ROOT/skills/skill-extraction-workflow/references/uiux-judgment-extraction.md"

check_absent \
  '\[\[[^]]+\.md\]\]' \
  "non-resolvable double-bracket Markdown reference remains" \
  "$ROOT/skills/product-ui-ux-design/references"

check_absent \
  'Platform Convention Walkthrough' \
  "retired combined vendor walkthrough reference remains" \
  "$ROOT/skills/product-ui-ux-design"

check_absent \
  '^## Universal Layout Recipe' \
  "unbounded universal layout recipe remains" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md"

check_absent \
  'pre-runtime-test ready' \
  "legacy split spelling of the canonical handoff state remains" \
  "$ROOT/skills/product-ui-ux-design" \
  "$ROOT/skills/testing-strategy/SKILL.md" \
  "$ROOT/skills/web-react-dev/SKILL.md" \
  "$ROOT/skills/app-cross-platform-dev/SKILL.md" \
  "$ROOT/skills/miniapp-product-dev/SKILL.md" \
  "$ROOT/skills/terminal-cli-dev/SKILL.md" \
  "$ROOT/skills/product-rd-workflow/SKILL.md" \
  "$ROOT/skills/product-rd-workflow/references/verify-developer-experience.md" \
  "$ROOT/skills/testing-strategy/references/client-runtime-test-matrices.md" \
  "$ROOT/skills/web-react-dev/references/complex-workspace-patterns.md" \
  "$ROOT/skills/app-cross-platform-dev/references/mobile-quality-release.md" \
  "$ROOT/docs/testing-handbook.md"

MUTATION_TMP=$(mktemp -d "${TMPDIR:-/tmp}/uiux-contract-mutations.XXXXXX")
trap 'rm -rf "$MUTATION_TMP"' EXIT

mutate_exact_once() {
  local source="$1" output="$2" needle="$3" replacement="$4"
  ruby -e '
    needle, replacement, source = ARGV
    text = File.binread(source)
    count = text.scan(needle).length
    abort "mutation source count=#{count}, expected=1: #{needle}" unless count == 1
    STDOUT.write(text.sub(needle, replacement))
  ' "$needle" "$replacement" "$source" > "$output"
}

run_rule_mutation() {
  local name="$1" source="$2" validator="$3" needle="$4" replacement="$5"
  local output="$MUTATION_TMP/$name.md"
  mutate_exact_once "$source" "$output" "$needle" "$replacement"
  if "$validator" "$output"; then
    echo "FAIL: $name mutation survived the live-rule validator" >&2
    fail=1
  fi
}

run_rule_mutation app-verdict-nonblocking "$APP_OWNER" app_design_closeout_valid \
  'remains `pending` and blocks the canonical contract' \
  'may remain unspecified and does not block the canonical contract'
run_rule_mutation app-screenshot-acceptance "$APP_OWNER" app_design_closeout_valid \
  'a mobile screenshot proves only that the app rendered and is never design acceptance' \
  'a mobile screenshot is sufficient design acceptance'
run_rule_mutation app-rejected-no-recapture "$APP_OWNER" app_design_closeout_valid \
  "the design owner applies \`delivery-contract.md\`'s rejected-candidate path and requires fresh runtime evidence for the revised candidate" \
  'the client owner may patch the rejected candidate without fresh runtime evidence'

run_rule_mutation phase0-state-adaptation-dropped "$TEST_MATRIX" testing_phase0_inputs_valid \
  'state/adaptation matrix' 'state notes'
run_rule_mutation phase0-criteria-dropped "$TEST_MATRIX" testing_phase0_inputs_valid \
  'criterion IDs/outcomes' 'visual notes'
run_rule_mutation phase0-red-dropped "$TEST_MATRIX" testing_phase0_inputs_valid \
  'RED baseline' 'current green result'
run_rule_mutation phase0-narrowing-allowed "$TEST_MATRIX" testing_phase0_inputs_valid \
  'do not silently replace or narrow the recorded design obligations' \
  'may replace or narrow the recorded design obligations'
run_rule_mutation phase0-layer-owner-moved "$TEST_MATRIX" testing_phase0_inputs_valid \
  'testing owns verifier type, assertion/rendered-evidence layers, commands/targets, independent oracles, and gaps' \
  'design owns verifier type and test layers'

run_rule_mutation phase0-missing-input-branch-dropped "$TEST_MATRIX" testing_incomplete_branches_valid \
  'the applicable full/lightweight design inputs are missing, or when ' ''
run_rule_mutation phase0-evidence-substitution-branch-dropped "$TEST_MATRIX" testing_incomplete_branches_valid \
  'DOM/component existence, a build pass, or an unreviewed screenshot is used in place of required rendered, interaction, accessibility, recovery, or design evidence' \
  'a build pass is accepted as sufficient evidence'

run_rule_mutation copy-only-misclassification-branch-dropped "$CONTRACT" copy_only_misclassification_valid \
  'If later evidence proves the `copy-only` classification wrong, the lightweight record is invalid from that discovery point, and you must apply **Missed pre-edit record** to the existing diff by stopping implementation edits, rebuilding the full Design brief, obtaining full Phase 0 and every affected producer/client owner entry, auditing the whole existing diff against them, then rerunning producer/client execution, Phase 1, and the design verdict. Until that remediation closes, the slice is `pending + blocked`; the old lightweight result cannot support completion.' \
  ''
run_rule_mutation copy-only-misclassification-false-complete "$CONTRACT" copy_only_misclassification_valid \
  'If later evidence proves the `copy-only` classification wrong, the lightweight record is invalid from that discovery point, and you must apply **Missed pre-edit record** to the existing diff by stopping implementation edits, rebuilding the full Design brief, obtaining full Phase 0 and every affected producer/client owner entry, auditing the whole existing diff against them, then rerunning producer/client execution, Phase 1, and the design verdict. Until that remediation closes, the slice is `pending + blocked`; the old lightweight result cannot support completion.' \
  'If later evidence proves the `copy-only` classification wrong, the lightweight record is invalid from that discovery point, and you must apply **Missed pre-edit record** to the existing diff by stopping implementation edits, rebuilding the full Design brief, obtaining full Phase 0 and every affected producer/client owner entry, auditing the whole existing diff against them, then rerunning producer/client execution, Phase 1, and the design verdict. The prior lightweight result is `accepted + complete` and needs no remediation.'

if [ -f "$CONTRACT" ]; then
  awk '
    $0 == "## 2. Test Phase 0 — layer selection" { print "## 3. Producer/client execution"; next }
    $0 == "## 3. Producer/client execution" { print "## 2. Test Phase 0 — layer selection"; next }
    { print }
  ' "$CONTRACT" > "$MUTATION_TMP/stage-order.md"
  if stage_order_valid "$MUTATION_TMP/stage-order.md"; then
    echo "FAIL: stage-order mutation survived the contract oracle" >&2
    fail=1
  fi

  awk '
    { print }
    $0 == "## 2. Test Phase 0 — layer selection" { print "## 2. Test Phase 0 — layer selection" }
  ' "$CONTRACT" > "$MUTATION_TMP/duplicate-stage.md"
  if stage_order_valid "$MUTATION_TMP/duplicate-stage.md"; then
    echo "FAIL: duplicate-stage mutation survived the contract oracle" >&2
    fail=1
  fi
fi

sed 's/Return the complete canonical client-record member/Return a partial client-record member/' \
  "$ROOT/skills/web-react-dev/SKILL.md" > "$MUTATION_TMP/partial-client-return.md"
if client_return_valid "$MUTATION_TMP/partial-client-return.md"; then
  echo "FAIL: partial client-return mutation survived the contract oracle" >&2
  fail=1
fi

sed 's/, affected files\/components//' \
  "$ROOT/skills/web-react-dev/SKILL.md" > "$MUTATION_TMP/client-return-member-dropped.md"
if client_return_valid "$MUTATION_TMP/client-return-member-dropped.md"; then
  echo "FAIL: incomplete client-return member mutation survived the contract oracle" >&2
  fail=1
fi

sed 's/, planned run\/capture command//' \
  "$ROOT/skills/web-react-dev/SKILL.md" > "$MUTATION_TMP/client-entry-command-dropped.md"
if client_entry_valid "$MUTATION_TMP/client-entry-command-dropped.md"; then
  echo "FAIL: incomplete client_entry mutation survived the contract oracle" >&2
  fail=1
fi

sed 's/API\/event\/schema fields/API fields omitted/' \
  "$ROOT/skills/go-microservice-dev/SKILL.md" > "$MUTATION_TMP/producer-trigger.md"
if producer_route_valid "$MUTATION_TMP/producer-trigger.md"; then
  echo "FAIL: narrowed producer-trigger mutation survived the producer-routing oracle" >&2
  fail=1
fi

sed 's/returns only its `producer_record` delta: immutable binding/returns no producer delta/' \
  "$ROOT/skills/go-microservice-dev/SKILL.md" > "$MUTATION_TMP/producer-record-dropped.md"
if producer_route_valid "$MUTATION_TMP/producer-record-dropped.md"; then
  echo "FAIL: dropped producer-record delta survived the producer-routing oracle" >&2
  fail=1
fi

awk '{ print } END { print "- A missing record may use `pending + pre-runtime-test-ready`." }' \
  "$ROOT/skills/go-microservice-dev/SKILL.md" > "$MUTATION_TMP/producer-wrong-preruntime.md"
if producer_route_valid "$MUTATION_TMP/producer-wrong-preruntime.md"; then
  echo "FAIL: producer-local pre-runtime status mutation survived the canonical-pointer oracle" >&2
  fail=1
fi

sed 's#../../product-ui-ux-design/references/delivery-contract.md#../product-ui-ux-design/references/delivery-contract.md#' \
  "$TEST_MATRIX" > "$MUTATION_TMP/testing-wrong-relative-path.md"
if resolved_markdown_reference_valid "$MUTATION_TMP/testing-wrong-relative-path.md" '../../product-ui-ux-design/references/delivery-contract.md' "$(dirname "$TEST_MATRIX")"; then
  echo "FAIL: wrong testing relative path survived the reference-resolution oracle" >&2
  fail=1
fi

sed 's#../../product-ui-ux-design/references/#product-ui-ux-design/references/#g' \
  "$PRODUCT_DESIGN_ROUTE" > "$MUTATION_TMP/product-wrong-relative-path.md"
if resolved_markdown_reference_valid "$MUTATION_TMP/product-wrong-relative-path.md" '../../product-ui-ux-design/references/delivery-contract.md' "$(dirname "$PRODUCT_DESIGN_ROUTE")"; then
  echo "FAIL: wrong product-routing relative path survived the reference-resolution oracle" >&2
  fail=1
fi

sed 's/terminal state remains `pending + blocked`/terminal state becomes `accepted + complete`/' \
  "$CONTRACT" > "$MUTATION_TMP/unknown-handoff.md"
if unknown_handoff_valid "$MUTATION_TMP/unknown-handoff.md"; then
  echo "FAIL: unknown-consumers complete mutation survived the terminal-state oracle" >&2
  fail=1
fi

awk '
  { print }
  $0 ~ /^\| `candidate` \| `blocked` \|/ {
    print "| `accepted` | `blocked` | injected contradictory row |"
  }
' "$CONTRACT" > "$MUTATION_TMP/extra-status-pair.md"
if status_pair_set_valid "$MUTATION_TMP/extra-status-pair.md"; then
  echo "FAIL: extra contradictory status pair survived the table-derived oracle" >&2
  fail=1
fi

sed 's/Load the union of their references; one lens never cancels another/Load only the deepest profile/' \
  "$ROUTER" > "$MUTATION_TMP/router-single-choice.md"
if router_composition_valid "$MUTATION_TMP/router-single-choice.md"; then
  echo "FAIL: single-choice profile mutation survived the router oracle" >&2
  fail=1
fi

sed 's#../../skill-extraction-workflow/references/two-source-extraction-pattern.md#../skill-extraction-workflow/references/two-source-extraction-pattern.md#' \
  "$ROUTER" > "$MUTATION_TMP/router-dangling-pointer.md"
if router_composition_valid "$MUTATION_TMP/router-dangling-pointer.md"; then
  echo "FAIL: dangling cross-skill pointer mutation survived the router oracle" >&2
  fail=1
fi

sed 's#references/design-execution-checklist\.md#references/missing-design-router.md#' \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" > "$MUTATION_TMP/entrypoint-router-orphan.md"
if entrypoint_router_valid "$MUTATION_TMP/entrypoint-router-orphan.md" "$ROUTER"; then
  echo "FAIL: orphaned entrypoint-to-router mutation survived the reachability oracle" >&2
  fail=1
fi

sed 's/A runtime-visible task enters `references\/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path./A runtime-visible task enters `references\/delivery-contract.md` only after the specialized router./' \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" > "$MUTATION_TMP/entrypoint-runtime-through-router.md"
if entrypoint_router_valid "$MUTATION_TMP/entrypoint-runtime-through-router.md" "$ROUTER"; then
  echo "FAIL: forced-router runtime mutation survived the direct-route oracle" >&2
  fail=1
fi

sed 's/This router is conditional context, not an always-loaded prerequisite./This router is the always-loaded prerequisite./' \
  "$ROUTER" > "$MUTATION_TMP/router-always-loaded.md"
if entrypoint_router_valid "$ROOT/skills/product-ui-ux-design/SKILL.md" "$MUTATION_TMP/router-always-loaded.md"; then
  echo "FAIL: always-loaded router mutation survived the conditional-loading oracle" >&2
  fail=1
fi

sed 's/auth\/admin surface/auth surface/' "$ROUTER" > "$MUTATION_TMP/router-web-admin-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-web-admin-dropped.md" "platform-web-desktop-patterns.md" "admin"; then
  echo "FAIL: dropped Web admin trigger survived the router oracle" >&2
  fail=1
fi

sed 's/App\/app-hosted\///' "$ROUTER" > "$MUTATION_TMP/router-app-hosted-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-app-hosted-dropped.md" "platform-mobile-patterns.md" "App/app-hosted"; then
  echo "FAIL: dropped App/app-hosted trigger survived the router oracle" >&2
  fail=1
fi

sed 's/capture, upload\/import, queue/capture omitted/' "$ROUTER" > "$MUTATION_TMP/router-operational-triggers-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-operational-triggers-dropped.md" "operational-processing-workflows.md" \
  "capture" "upload/import" "queue" "progress monitoring" "assignment/ownership" "exception handling" "quality-control" "moderation"; then
  echo "FAIL: narrowed operational triggers survived the router oracle" >&2
  fail=1
fi

sed 's/, or instrumentation//' "$ROUTER" > "$MUTATION_TMP/router-trust-instrumentation-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-trust-instrumentation-dropped.md" "trust-sensitive-ai-and-data-patterns.md" \
  "upload" "citation" "analytics" "moderation decision" "long-running workflow" "instrumentation"; then
  echo "FAIL: dropped trust instrumentation trigger survived the router oracle" >&2
  fail=1
fi

sed 's/content-pack/content collection/' "$ROUTER" > "$MUTATION_TMP/router-content-pack-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-content-pack-dropped.md" "resource-management-interactions.md" "content-pack"; then
  echo "FAIL: dropped content-pack trigger survived the router oracle" >&2
  fail=1
fi

sed 's/Community\/social\/feed\/creator\/topic\/profile\/notification\/moderation\/AI-social/Community\/feed\/creator\/profile\/notification/' \
  "$ROUTER" > "$MUTATION_TMP/router-community-triggers-dropped.md"
if router_lens_terms_valid "$MUTATION_TMP/router-community-triggers-dropped.md" "scenario-community-patterns.md" \
  "Community/social/feed/creator/topic/profile/notification/moderation/AI-social"; then
  echo "FAIL: narrowed community triggers survived the router oracle" >&2
  fail=1
fi

sed 's/at any delivery depth/only for systemic redesign/' \
  "$ROUTER" > "$MUTATION_TMP/router-narrow-audit-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-narrow-audit-orphan.md" "Audit/review" "at any delivery depth" "ui-ux-audit.md"; then
  echo "FAIL: systemic-only audit mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/design-impl-naming-and-versioning\.md/design-impl-naming-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-naming-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-naming-orphan.md" "Naming/version synchronization" "Figma↔code naming drift" "design-impl-naming-and-versioning.md"; then
  echo "FAIL: naming/version orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/multi-stack-strategy\.md/multi-stack-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-multistack-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-multistack-orphan.md" "Multi-stack" "spans multiple client stacks" "multi-stack-strategy.md"; then
  echo "FAIL: multi-stack orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/frontend-code-evidence-map\.md/frontend-code-evidence-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-code-evidence-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-code-evidence-orphan.md" "Source/code evidence" "local frontend implementation evidence" "frontend-code-evidence-map.md"; then
  echo "FAIL: code-evidence orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/ui-ux-design-development\.md/ui-ux-design-development-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-design-to-code-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-design-to-code-orphan.md" "Design-to-code" "Applying design decisions to client code" "ui-ux-design-development.md"; then
  echo "FAIL: design-to-code orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/multi-project-token-consistency\.md/multi-project-token-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-same-stack-orphan.md"
if router_mode_reachability_valid "$MUTATION_TMP/router-same-stack-orphan.md" "Same-stack multi-project" "same end/stack" "multi-project-token-consistency.md"; then
  echo "FAIL: same-stack theme orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/layout-recipes-and-screenshot-acceptance\.md/layout-recipes-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-layout-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-layout-orphan.md" \
  "Layout recipe, component density, workbench structure, empty/loading/error geometry, or screenshot/render acceptance" \
  "layout-recipes-and-screenshot-acceptance.md"; then
  echo "FAIL: narrow layout/state recipe orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/product-surface-patterns\.md/product-surface-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-generic-surface-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-generic-surface-orphan.md" \
  "Generic surface/loop taxonomy, account/settings, decision/review, AI-assisted or workflow-extension pattern, or no focused scenario lens fits" \
  "product-surface-patterns.md"; then
  echo "FAIL: generic surface/loop orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/visual-craft\.md/visual-craft-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-visual-craft-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-visual-craft-orphan.md" \
  "Visual polish, brand feel, anti-slop, typography/hierarchy, iconography, or material treatment" \
  "visual-craft.md"; then
  echo "FAIL: narrow visual-craft orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/behavioral-aesthetic-logic\.md/behavioral-aesthetic-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-behavioral-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-behavioral-orphan.md" \
  "Attention, motivation, perceived effort, trust psychology, habit loop, or behavioral/aesthetic judgment" \
  "behavioral-aesthetic-logic.md"; then
  echo "FAIL: behavioral/aesthetic orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/design-system-source-of-truth\.md/design-system-source-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-source-authority-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-source-authority-orphan.md" \
  "Design-system source authority, third-party mirror detection, brand-token ownership, or wrong design-source comments in code/theme files" \
  "design-system-source-of-truth.md"; then
  echo "FAIL: design-source authority orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/analytics-visualization-interactions\.md/analytics-visualization-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-analytics-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-analytics-orphan.md" \
  "Analytics, charts, comparison, drill-down, metric explanation, creator/topic health, retention, or AI-quality metric" \
  "analytics-visualization-interactions.md"; then
  echo "FAIL: analytics lens orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/complex-creation-interactions\.md/complex-creation-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-complex-creation-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-complex-creation-orphan.md" \
  "Complex creation, upload/import, AI draft extraction, structured editing, matching/manual correction, preview/publish/export flow" \
  "complex-creation-interactions.md"; then
  echo "FAIL: complex-creation lens orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/interaction-design-patterns\.md/interaction-design-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-detailed-interaction-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-detailed-interaction-orphan.md" \
  "Detailed interaction, feedback strength, error/recovery, gesture, generated state, motion, or shortcut behavior" \
  "interaction-design-patterns.md"; then
  echo "FAIL: detailed-interaction lens orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/external-ui-ux-quality-benchmarks\.md/external-quality-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-external-theory-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-external-theory-orphan.md" \
  "External theory, WCAG, platform recommendation, benchmark claim" \
  "external-ui-ux-quality-benchmarks.md"; then
  echo "FAIL: external-theory lens orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/product-lifecycle-acceptance-and-iteration\.md/product-lifecycle-orphaned.md/' \
  "$ROUTER" > "$MUTATION_TMP/router-lifecycle-orphan.md"
if router_lens_reachability_valid "$MUTATION_TMP/router-lifecycle-orphan.md" \
  "Launch/post-launch measurement and iteration" \
  "product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: launch/post-launch lens orphan mutation survived the task-reachability oracle" >&2
  fail=1
fi

sed 's/Electron shell → installed desktop-shell owner or project client convention/Electron shell → `app-cross-platform-dev`/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" > "$MUTATION_TMP/multistack-electron-owner.md"
if multistack_owner_valid "$MUTATION_TMP/multistack-electron-owner.md"; then
  echo "FAIL: Electron-shell wrong-owner mutation survived the multi-stack owner oracle" >&2
  fail=1
fi

sed 's/`terminal-tui` \/ `desktop-tv-shell`/`legacy`/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" > "$MUTATION_TMP/multistack-tags-narrowed.md"
if multistack_owner_valid "$MUTATION_TMP/multistack-tags-narrowed.md"; then
  echo "FAIL: terminal/desktop stack-tag narrowing survived the owner-set oracle" >&2
  fail=1
fi

sed 's/Route every affected consumer:/Route React consumers only:/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" > "$MUTATION_TMP/multistack-shared-owner-narrowed.md"
if multistack_owner_valid "$MUTATION_TMP/multistack-shared-owner-narrowed.md"; then
  echo "FAIL: shared-package owner narrowing survived the owner-set oracle" >&2
  fail=1
fi

sed 's/React browser implementation ownership → `web-react-dev`; Vue\/Svelte\/static\/vendor\/other browser implementation → its installed web-content owner or the fail-closed project-convention lookup/Browser implementation ownership → `web-react-dev`/' \
  "$ROOT/skills/product-ui-ux-design/references/frontend-code-evidence-map.md" > "$MUTATION_TMP/frontend-map-react-only.md"
if design_mode_owner_valid \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$MUTATION_TMP/frontend-map-react-only.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md"; then
  echo "FAIL: React-only source-evidence routing mutation survived the owner-set oracle" >&2
  fail=1
fi

sed 's/mini-app → `miniapp-product-dev`; terminal\/TUI → `terminal-cli-dev`/mini-app and terminal → `web-react-dev`/' \
  "$ROOT/skills/product-ui-ux-design/references/design-impl-naming-and-versioning.md" > "$MUTATION_TMP/naming-owner-narrowed.md"
if restored_reference_owner_valid \
  "$MUTATION_TMP/naming-owner-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md"; then
  echo "FAIL: restored-reference owner-narrowing mutation survived the owner-set oracle" >&2
  fail=1
fi

sed 's/follows every affected client owner in `delivery-contract.md`/routes to `web-react-dev` only/' \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" > "$MUTATION_TMP/source-truth-owner-narrowed.md"
if restored_reference_owner_valid \
  "$ROOT/skills/product-ui-ux-design/references/design-impl-naming-and-versioning.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$MUTATION_TMP/source-truth-owner-narrowed.md"; then
  echo "FAIL: design-source enforcement owner narrowing survived the owner-set oracle" >&2
  fail=1
fi

sed 's/React or other web, web H5, native app, mini-program, terminal\/TUI, Electron\/desktop, TV, or another rendered client/web, native app, or mini-program/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" > "$MUTATION_TMP/token-consumer-set-narrowed.md"
if restored_reference_owner_valid \
  "$ROOT/skills/product-ui-ux-design/references/design-impl-naming-and-versioning.md" \
  "$MUTATION_TMP/token-consumer-set-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md"; then
  echo "FAIL: token pre-consumption owner narrowing survived the owner-set oracle" >&2
  fail=1
fi

sed 's/A mini-program `web-view` uses the actual web-content owner plus `miniapp-product-dev`/A mini-program `web-view` uses `web-react-dev` plus `miniapp-product-dev`/' \
  "$CONTRACT" > "$MUTATION_TMP/composite-owner.md"
if composite_owner_valid "$MUTATION_TMP/composite-owner.md"; then
  echo "FAIL: hard-coded React composite-host mutation survived the owner-set oracle" >&2
  fail=1
fi

sed 's/every changed or claim-bearing producer owner, and every affected client owner/every affected client owner/' \
  "$CONTRACT" > "$MUTATION_TMP/copy-producer-owner-dropped.md"
if lightweight_all_role_valid "$MUTATION_TMP/copy-producer-owner-dropped.md"; then
  echo "FAIL: copy-only dropped-producer-owner mutation survived the lightweight-set oracle" >&2
  fail=1
fi

sed 's/, `audit\/review`//' \
  "$CONTRACT" > "$MUTATION_TMP/trigger-class-audit-dropped.md"
if trigger_class_set_valid "$MUTATION_TMP/trigger-class-audit-dropped.md"; then
  echo "FAIL: dropped work-mode trigger class survived the closed-set oracle" >&2
  fail=1
fi

sed 's/Each binding value has a non-empty, exact payload/Each binding value may have an empty payload/' \
  "$CONTRACT" > "$MUTATION_TMP/empty-binding-contract.md"
if binding_contract_valid "$MUTATION_TMP/empty-binding-contract.md"; then
  echo "FAIL: empty-binding contract mutation survived the binding oracle" >&2
  fail=1
fi

sed 's/`producer_record_ids`/`producer_records_omitted`/' \
  "$CONTRACT" > "$MUTATION_TMP/producer-member-dropped.md"
if candidate_member_contract_valid "$MUTATION_TMP/producer-member-dropped.md"; then
  echo "FAIL: dropped producer member survived the all-role set oracle" >&2
  fail=1
fi

sed 's/`design_record_ids`/`design_records_omitted`/' \
  "$CONTRACT" > "$MUTATION_TMP/design-member-dropped.md"
if candidate_member_contract_valid "$MUTATION_TMP/design-member-dropped.md"; then
  echo "FAIL: dropped design member survived the all-role set oracle" >&2
  fail=1
fi

sed 's/`test_record_ids`/`test_records_omitted`/' \
  "$CONTRACT" > "$MUTATION_TMP/test-member-dropped.md"
if candidate_member_contract_valid "$MUTATION_TMP/test-member-dropped.md"; then
  echo "FAIL: dropped test member survived the all-role set oracle" >&2
  fail=1
fi

sed 's/`client_record_ids`/`client_records_omitted`/' \
  "$CONTRACT" > "$MUTATION_TMP/client-member-dropped.md"
if candidate_member_contract_valid "$MUTATION_TMP/client-member-dropped.md"; then
  echo "FAIL: dropped client member survived the all-role set oracle" >&2
  fail=1
fi

sed 's/Do not relabel a dirty execution as a clean commit after the fact/A dirty execution may be recorded as the current commit/' \
  "$CONTRACT" > "$MUTATION_TMP/dirty-as-commit.md"
if binding_contract_valid "$MUTATION_TMP/dirty-as-commit.md"; then
  echo "FAIL: dirty-as-commit mutation survived the binding oracle" >&2
  fail=1
fi

sed 's/, and every result-affecting ignored member//' \
  "$CONTRACT" > "$MUTATION_TMP/ignored-input-dropped.md"
if binding_contract_valid "$MUTATION_TMP/ignored-input-dropped.md"; then
  echo "FAIL: ignored result-affecting input mutation survived the binding oracle" >&2
  fail=1
fi

sed 's/Result-affecting external inputs always use a separate content-addressed member and locator/External inputs need no binding/' \
  "$CONTRACT" > "$MUTATION_TMP/external-input-unbound.md"
if binding_contract_valid "$MUTATION_TMP/external-input-unbound.md"; then
  echo "FAIL: unbound external input mutation survived the binding oracle" >&2
  fail=1
fi

sed 's/mutable external version labels or artifact paths/mutable external version labels or artifact paths are immutable bindings; branches/' \
  "$CONTRACT" > "$MUTATION_TMP/mutable-external-binding.md"
if binding_contract_valid "$MUTATION_TMP/mutable-external-binding.md"; then
  echo "FAIL: mutable external artifact mutation survived the binding oracle" >&2
  fail=1
fi

sed 's/The bound Phase 1 `sufficiency` is `sufficient` and no required evidence gap remains/The bound Phase 1 `sufficiency` may be `insufficient`/' \
  "$CONTRACT" > "$MUTATION_TMP/insufficient-complete.md"
if accepted_completion_valid "$MUTATION_TMP/insufficient-complete.md"; then
  echo "FAIL: insufficient Phase 1 accepted as complete by the verdict oracle" >&2
  fail=1
fi

sed 's/even when it emits only plain text and never enters an alternate screen/only when it emits ANSI and enters an alternate screen/' \
  "$ROOT/skills/terminal-cli-dev/SKILL.md" > "$MUTATION_TMP/ordinary-cli-escaped.md"
if terminal_cli_contract_valid \
  "$MUTATION_TMP/ordinary-cli-escaped.md" \
  "$ROOT/skills/go-microservice-dev/SKILL.md" \
  "$ROOT/skills/python-service-dev/SKILL.md" \
  "$ROOT/skills/product-rd-workflow/references/design-routing-and-readiness.md"; then
  echo "FAIL: ordinary CLI escape mutation survived the terminal owner oracle" >&2
  fail=1
fi

sed 's/Any changed command tree, subcommand, flag\/default\/action path, help\/output\/exit behavior, confirmation, progress, recovery/Only a full-screen TUI/' \
  "$ROOT/skills/product-rd-workflow/references/design-routing-and-readiness.md" > "$MUTATION_TMP/product-route-cli-escaped.md"
if terminal_cli_contract_valid \
  "$ROOT/skills/terminal-cli-dev/SKILL.md" \
  "$ROOT/skills/go-microservice-dev/SKILL.md" \
  "$ROOT/skills/python-service-dev/SKILL.md" \
  "$MUTATION_TMP/product-route-cli-escaped.md"; then
  echo "FAIL: product-readiness ordinary CLI escape survived the terminal owner oracle" >&2
  fail=1
fi

sed 's/React and other web, H5, native mobile, mini-app, terminal\/TUI, Electron\/desktop, and TV consumers/desktop and mobile consumers/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" > "$MUTATION_TMP/reachable-multistack-narrowed.md"
if reachable_reference_scope_valid \
  "$MUTATION_TMP/reachable-multistack-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: narrowed multi-stack inner consumer set survived the reference oracle" >&2
  fail=1
fi

sed 's/map every rendered stack in the authoritative consumer inventory/map desktop and mobile only/' \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" > "$MUTATION_TMP/reachable-source-truth-narrowed.md"
if reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$MUTATION_TMP/reachable-source-truth-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: narrowed source-of-truth stack set survived the reference oracle" >&2
  fail=1
fi

sed 's/every same-stack subproject uses the same canonical UI-kit\/component family for that rendered stack/all desktop subprojects use the same desktop UI-kit/' \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" > "$MUTATION_TMP/reachable-token-scope-narrowed.md"
if reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$MUTATION_TMP/reachable-token-scope-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: Web-only multi-project token mutation survived the reference oracle" >&2
  fail=1
fi

sed 's/## Complete Consumer Set/## Desktop And Mobile Only/' \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" > "$MUTATION_TMP/reachable-token-component-narrowed.md"
if reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$MUTATION_TMP/reachable-token-component-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: narrowed token/component consumer map survived the reference oracle" >&2
  fail=1
fi

sed 's/ordinary CLI or full-screen terminal\/TUI, Electron\/desktop\/TV shell/desktop workbench/' \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" > "$MUTATION_TMP/reachable-layout-family-narrowed.md"
if reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$MUTATION_TMP/reachable-layout-family-narrowed.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md"; then
  echo "FAIL: narrowed layout-family mutation survived the reference oracle" >&2
  fail=1
fi

sed 's/the canonical prerequisite and acceptance path is `delivery-contract.md`/the lifecycle below is sufficient/' \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" > "$MUTATION_TMP/reachable-lifecycle-parallel.md"
if reachable_reference_scope_valid \
  "$ROOT/skills/product-ui-ux-design/references/multi-stack-strategy.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-system-source-of-truth.md" \
  "$ROOT/skills/product-ui-ux-design/references/multi-project-token-consistency.md" \
  "$ROOT/skills/product-ui-ux-design/references/tokens-and-components.md" \
  "$ROOT/skills/product-ui-ux-design/references/layout-recipes-and-screenshot-acceptance.md" \
  "$MUTATION_TMP/reachable-lifecycle-parallel.md"; then
  echo "FAIL: parallel lifecycle completion mutation survived the reference oracle" >&2
  fail=1
fi

sed 's/The complete affected client-owner set owns implementation and runtime evidence/The four built-in client skills own implementation and runtime evidence/' \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" > "$MUTATION_TMP/entry-owner-fallback-dropped.md"
if reachable_finish_paths_valid \
  "$MUTATION_TMP/entry-owner-fallback-dropped.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-intake-and-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/interaction-design-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/visual-craft.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-surface-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md"; then
  echo "FAIL: dropped entrypoint owner fallback survived the finish-path oracle" >&2
  fail=1
fi

sed 's/It cannot by itself finish the slice; completion requires bound design and test records, every changed producer and affected client return, Test Phase 1 sufficiency, and an allowed design verdict/Passing this client checklist finishes the slice/' \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" > "$MUTATION_TMP/development-parallel-finish.md"
if reachable_finish_paths_valid \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-intake-and-acceptance.md" \
  "$MUTATION_TMP/development-parallel-finish.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/interaction-design-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/visual-craft.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-surface-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md"; then
  echo "FAIL: Web/Mobile-only client finish mutation survived the finish-path oracle" >&2
  fail=1
fi

sed 's/Canonical `delivery-contract.md` verdict\/next state plus the complete design\/test\/producer\/client binding-set IDs; do not invent a second design-readiness status/Launch readiness: pass, conditional pass, or block/' \
  "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" > "$MUTATION_TMP/lifecycle-second-status.md"
if reachable_finish_paths_valid \
  "$ROOT/skills/product-ui-ux-design/SKILL.md" \
  "$ROOT/skills/product-ui-ux-design/references/design-intake-and-acceptance.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-design-development.md" \
  "$MUTATION_TMP/lifecycle-second-status.md" \
  "$ROOT/skills/product-ui-ux-design/references/source-map.md" \
  "$ROOT/skills/product-ui-ux-design/references/interaction-design-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/visual-craft.md" \
  "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" \
  "$ROOT/skills/product-ui-ux-design/references/product-surface-patterns.md" \
  "$ROOT/skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md"; then
  echo "FAIL: second lifecycle readiness status survived the finish-path oracle" >&2
  fail=1
fi

awk '
  { print }
  END { print "Passing this audit marks the slice complete without delivery-contract.md." }
' "$ROOT/skills/product-ui-ux-design/references/ui-ux-audit.md" > "$MUTATION_TMP/audit-appended-parallel-finish.md"
if all_design_references_no_parallel_completion \
  "$MUTATION_TMP/audit-appended-parallel-finish.md"; then
  echo "FAIL: appended parallel audit completion survived the contradiction oracle" >&2
  fail=1
fi

awk '
  { print }
  END { print "- Launch readiness: pass, conditional pass, or block." }
' "$ROOT/skills/product-ui-ux-design/references/product-lifecycle-acceptance-and-iteration.md" > "$MUTATION_TMP/lifecycle-appended-second-status.md"
if all_design_references_no_parallel_completion \
  "$MUTATION_TMP/lifecycle-appended-second-status.md"; then
  echo "FAIL: appended second lifecycle status survived the contradiction oracle" >&2
  fail=1
fi

awk '
  { print }
  END { print "Passing this surface checklist marks the slice complete without delivery-contract.md." }
' "$ROOT/skills/product-ui-ux-design/references/product-surface-patterns.md" > "$MUTATION_TMP/surface-appended-parallel-finish.md"
if all_design_references_no_parallel_completion \
  "$MUTATION_TMP/surface-appended-parallel-finish.md"; then
  echo "FAIL: appended product-surface completion survived the contradiction oracle" >&2
  fail=1
fi

awk '
  { print }
  $0 ~ /^\| `dirty-bundle-v1` \|/ {
    print "| `branch` | `branch:<mutable-name>` |"
  }
' "$CONTRACT" > "$MUTATION_TMP/extra-binding-kind.md"
if binding_spec_set_valid "$MUTATION_TMP/extra-binding-kind.md"; then
  echo "FAIL: extra mutable binding kind survived the table-derived oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "```text"
    print
    print "```"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/fenced-obligation.md"
if outside_fence_contains "$MUTATION_TMP/fenced-obligation.md" "All other terminal combinations are invalid"; then
  echo "FAIL: fenced obligation survived the active-Markdown oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "````text"
    print "```"
    print
    print "```"
    print "````"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/long-outer-short-inner-fence.md"
if outside_fence_contains "$MUTATION_TMP/long-outer-short-inner-fence.md" "All other terminal combinations are invalid"; then
  echo "FAIL: shorter inner fence closed a longer outer fence in the active-Markdown oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "~~~~text"
    print "```"
    print
    print "```"
    print "~~~~"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/mismatched-fence-marker.md"
if outside_fence_contains "$MUTATION_TMP/mismatched-fence-marker.md" "All other terminal combinations are invalid"; then
  echo "FAIL: mismatched fence marker escaped the active-Markdown oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print ""
    print "    " $0
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/indented-code-obligation.md"
if outside_fence_contains "$MUTATION_TMP/indented-code-obligation.md" "All other terminal combinations are invalid"; then
  echo "FAIL: indented-code obligation survived the active-Markdown oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "````text"
    print "````not-a-close"
    print
    print "````"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/fence-suffix-not-close.md"
if outside_fence_contains "$MUTATION_TMP/fence-suffix-not-close.md" "All other terminal combinations are invalid"; then
  echo "FAIL: nonblank fence suffix closed a fenced example in the active-Markdown oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "```text"
    print "<!--"
    print "```"
    print
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/fenced-comment-before-active-obligation.md"
if ! outside_fence_contains "$MUTATION_TMP/fenced-comment-before-active-obligation.md" "All other terminal combinations are invalid"; then
  echo "FAIL: an HTML-comment marker inside fenced code swallowed a later active obligation" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "`" $0 "`"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/inline-code-only-obligation.md"
if outside_fence_contains "$MUTATION_TMP/inline-code-only-obligation.md" "All other terminal combinations are invalid"; then
  echo "FAIL: inline-code-only obligation survived the active-prose oracle" >&2
  fail=1
fi

awk '
  index($0, "All other terminal combinations are invalid") {
    print "<!-- " $0 " -->"
    next
  }
  { print }
' "$CONTRACT" > "$MUTATION_TMP/commented-obligation.md"
if outside_fence_contains "$MUTATION_TMP/commented-obligation.md" "All other terminal combinations are invalid"; then
  echo "FAIL: HTML-commented obligation survived the active-Markdown oracle" >&2
  fail=1
fi

awk '
  $0 == "| Verdict | Next state | Required condition |" {
    print "```text"
    fenced_table = 1
  }
  { print }
  fenced_table && $0 ~ /^\| `candidate` \| `blocked` \|/ {
    print "```"
    fenced_table = 0
  }
' "$CONTRACT" > "$MUTATION_TMP/fenced-status-table.md"
if status_pair_set_valid "$MUTATION_TMP/fenced-status-table.md"; then
  echo "FAIL: fenced status table survived the table-derived oracle" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "uiux_delivery_contract_ok"
fi
exit "$fail"
