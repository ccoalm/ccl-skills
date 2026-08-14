#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Impact-chain firing gate: every added source-register row for a changed
# upstream-owner skill must declare a behavioral-evidence status and an
# observed-failure state, and (for non-wording changes) name an owner-scoped
# FIRING PATH that resolves to this diff — an anchor on a changed normative
# rule line, or a changed owner executable. The statuses are required author
# declarations; the firing path and the wording-only classification are the
# machine-verified core. Extracted from the former inline `ruby -e` block in
# check-ccl-skills.sh so the program gets normal Ruby tooling and no
# single-quote embedding constraint. Invoked by check-ccl-skills.sh (same
# scripts/ directory) with the target repo root as ARGV[0]; exits 1 on gate
# failure, 0 otherwise.

require "yaml"

root = ARGV.fetch(0)
# Diff reads FAIL CLOSED: a git failure that returned empty output would
# otherwise make the gate see no changed owners and silently pass.
git_read = lambda do |*args|
  out = IO.popen(["git", "-C", root, *args], &:read)
  unless $?.success?
    warn "impact_chain_git_failed: git #{args.join(" ")} exited #{$?.exitstatus}"
    exit 1
  end
  out
end
base = ENV["CCL_SKILL_BASE_REF"].to_s.strip
if base.empty?
  upstream_ref = IO.popen(["git", "-C", root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", err: File::NULL], &:read).strip
  base = upstream_ref.empty? ? "origin/main" : upstream_ref
end
merge_base = IO.popen(["git", "-C", root, "merge-base", base, "HEAD"], &:read).strip
if merge_base.empty?
  warn "impact_chain_merge_base_missing: #{base}"
  exit 1
end
base_ref = merge_base
LEDGER_PATH = "skills/skill-extraction-workflow/references/source-register.md"
# ROUND SCOPING. An evidence row is authored against ONE round's diff, but every
# classifier below used to read the whole base..HEAD range. The two are different
# units, so a row's verdict moved after it landed: an already-gated row turned red
# once a LATER round touched the same owner, and a description-only round lost its
# locator because an EARLIER round had edited that owner's body. Both are the same
# defect — the predicate was scoped to the RANGE instead of to the round the row
# belongs to — and patching the symptoms one at a time (the retarget tolerance in
# the routing-surface class below was one such patch) only re-instantiates it on
# the next input. The predicate now reads the round.
#
# Rounds are cut at the commits that touch the ledger itself, walked first-parent
# so one merged worktree round collapses to one boundary. The partition comes from
# git alone: an author cannot widen, move, or nominate their own scope.
round_heads = git_read.call("rev-list", "--first-parent", "--reverse", "#{base_ref}..HEAD", "--", LEDGER_PATH)
                      .split("\n").map(&:strip).reject(&:empty?)
# Each round spans (previous ledger boundary, this one] so the work commits that
# precede a ledger append are inside the round they belong to — landing the change
# and appending the row in separate commits is the normal shape, not an evasion.
round_bounds = ([base_ref] + round_heads).each_cons(2).to_a
# The trailing span — owner changes committed after the last ledger append — is a
# round too. It holds no rows, so its owners fall through to the presence check
# and the gate still fails closed on undeclared work.
round_bounds << [round_heads.last || base_ref, "HEAD"]
# Everything a predicate needs to judge one span. Built lazily per span and
# memoized: a round whose rows are all RED-baseline never pays for the rename
# derivation.
scope_struct = Struct.new(:base, :head, :changed_paths, :rename_pairs, :rename_pattern)
scope_cache = {}
scope_at = lambda do |span_base, span_head|
  scope_cache[[span_base, span_head]] ||= begin
    # --no-renames so a moved-out/renamed upstream reference or script surfaces its
    # OLD path (as a delete) instead of collapsing to a destination outside skills/;
    # otherwise `git mv skills/<owner>/references/x.md docs/x.md` would drop the
    # owner entirely and slip past the row requirement.
    # -z + NUL split so a path containing newline/tab bytes cannot hide from the
    # owner and subject-set enumeration behind Git's line-oriented quoting.
    paths = git_read.call("diff", "--no-renames", "-z", span_base, span_head, "--name-only")
                    .split("\0").reject(&:empty?)
    # Rename pairs come from git's own tree state — which owner packages disappeared
    # and which appeared — never from an author declaration. How the pairs are derived
    # does not have to be trustworthy: every consumer below only ever gets stricter
    # when a pair is wrong, and nothing here lets a diff be measured against a
    # DIFFERENT file.
    pairs = git_read.call("diff", "--find-renames", "--diff-filter=R", "-z", "--name-status",
                          span_base, span_head, "--", "skills/*/SKILL.md")
                    .split("\0").reject(&:empty?).each_slice(3).filter_map do |_status, from, to|
      from_owner = from.to_s[%r{\Askills/([^/]+)/SKILL\.md\z}, 1]
      to_owner = to.to_s[%r{\Askills/([^/]+)/SKILL\.md\z}, 1]
      [from_owner, to_owner] if from_owner && to_owner && from_owner != to_owner
    end.to_h
    # Single-pass alternation so one pair's output can never be re-matched by another
    # pair (a chained gsub would let old -> new -> newer cascade).
    pattern = pairs.empty? ? nil : Regexp.union(pairs.keys.sort_by { |k| -k.length }.map { |k| k.dup.force_encoding(Encoding::BINARY) })
    scope_struct.new(span_base, span_head, paths, pairs, pattern)
  end
end
# The CUMULATIVE scope still owns everything that asks "was this owner touched at
# all between base and HEAD" — subject selection and the presence check. Narrowing
# those to a round would let an owner changed in one round be declared in another,
# so they deliberately keep reading the whole range.
cumulative = scope_at.call(base_ref, "HEAD")
changed_paths = cumulative.changed_paths
# Normalize every changed path to the owning "<skill>/SKILL.md" identity (the
# prefix-free form the select rules and source-register evidence convention both
# use). ANY path inside an owner package maps to the owner — SKILL.md,
# references/, scripts/, and every other shipped file (agents/ overlays,
# templates, assets): the whole package is behavior-bearing, and enumerating
# "behavioral" subdirectories is how the agents/ overlay slipped through.
# Scoping to exactly one path segment under skills/ (via [^/]+) is what makes
# the gate fire without letting stray paths like docs/<x>-architecture/SKILL.md
# trip it.
# The source-register itself is the impact-chain LEDGER; appending rows to it is a
# routine, self-referential operation, so it never counts as an upstream change
# (otherwise every ledger append would demand a row about editing the ledger).
changed = changed_paths.map do |path|
  next nil if path == "skills/skill-extraction-workflow/references/source-register.md"
  if (m = path.match(%r{\Askills/([^/]+)/.+\z}m))
    "#{m[1]}/SKILL.md"
  end
end.compact.uniq
# Curated upstream-owner list for the automated impact-chain gate.
# When a new skill becomes an upstream decision owner, add it here in the same
# change that introduces that responsibility.
upstream_owner_skills = %w[
  code-review
  defect-diagnosis
  feature-risk-router
  llm-inference-integration
  multi-agent-delegation
  multi-perspective-research
  platform-observability
  platform-release-engineering
  platform-service-connectivity
  product-rd-workflow
  product-ui-ux-design
  skill-extraction-workflow
  test-artifact-management
  testing-strategy
  tighten-doc
]
# Name-level selection predicate, shared by the cumulative subject filter and
# the per-round rename-away suppression below: whether a NAME is a decision
# owner is a property of the name, independent of whether it exists at the
# range endpoints.
selectable_path = lambda do |path|
  path.end_with?("-architecture/SKILL.md") ||
    path.start_with?("platform-") && path.end_with?("/SKILL.md") ||
    upstream_owner_skills.any? { |skill| path == "#{skill}/SKILL.md" }
end
upstream = changed.select { |path| selectable_path.call(path) }
# Subject selection reasons about the whole range, so it reads the cumulative
# pairs; the per-round classifiers take their pairs from their own scope.
rename_pairs = cumulative.rename_pairs
rename_pattern = cumulative.rename_pattern
# Blob and package readers, hoisted because BOTH the subject filter below and the
# no-behaviour classifier need them. Binary, because a package may legitimately
# track a blob that is not valid UTF-8 and comparing bytes must not depend on
# decoding them; slugs are ASCII so the substitution is unaffected.
raw_blob_at = lambda do |ref, relative|
  out = IO.popen(["git", "-C", root, "show", "#{ref}:#{relative}", err: File::NULL], &:read)
  $?.success? ? out.force_encoding(Encoding::BINARY) : nil
end
# Existence at a ref must mean A REGULAR FILE. `git show ref:path` also succeeds
# for a TREE, so a directory named SKILL.md would read as "present" and let a
# row vouch for an owner whose entrypoint was effectively deleted (the
# extension-challenge P1). ls-tree exposes the entry's mode; only a regular
# blob counts, so symlinks, submodules, and directories all read as absent and
# fall through to the deletion fail-closed path.
regular_blob_at = lambda do |ref, relative|
  out = IO.popen(["git", "-C", root, "ls-tree", "-z", ref, "--", relative], err: File::NULL, &:read)
  next false unless $?.success?
  entry = out.split("\0").reject(&:empty?).first
  next false unless entry
  mode = entry.split(/\s+/, 2).first
  mode == "100644" || mode == "100755"
end
# Every tracked entry in an owner package at one ref, as "<mode> <path>". The MODE
# is part of the identity: names and contents alone would let a diff drop the
# executable bit from a script and still reproduce byte-for-byte.
package_files = lambda do |ref, owner|
  out = IO.popen(["git", "-C", root, "ls-tree", "-r", "-z", ref, "--", "skills/#{owner}/"],
                 err: File::NULL, &:read)
  next nil unless $?.success?
  out.split("\0").reject(&:empty?).map do |entry|
    meta, path = entry.split("\t", 2)
    "#{meta.to_s.split(/\s+/, 2).first} #{path}"
  end
end
# Canonical form of a package path for comparison. The directory moves, and the
# substitution is applied to BOTH sides so a FILENAME carrying the old slug — a
# renamed skill's own playbook reference is exactly that case — compares equal
# whether or not the author also renamed the file. Normalizing rather than
# rewriting one side keeps the gate from quietly demanding filename renames it has
# no business requiring.
canonical_package_path = lambda do |scope, path, base_owner, owner|
  moved = path.sub("skills/#{base_owner}/", "skills/#{owner}/")
  scope.rename_pattern ? moved.gsub(scope.rename_pattern) { |hit| scope.rename_pairs.fetch(hit) } : moved
end
# True when HEAD's `owner` package is base's `base_owner` package MOVED: the same
# file set, one-to-one. Deliberately structural and content-blind, because a real
# rename normally also edits a heading or a display name — requiring byte equality
# here would reject every honest rename. It is still far harder to satisfy than
# git's similarity score, which pairs two SKILL.md files and can therefore mistake
# "delete one skill, add a similar one" for a move.
package_moved = lambda do |scope, base_owner, owner|
  base_files = package_files.call(scope.base, base_owner)
  head_files = package_files.call(scope.head, owner)
  return false if base_files.nil? || head_files.nil? || base_files.empty?
  strip = ->(entries) { entries.map { |e| e.split(" ", 2).last } }
  expected = strip.call(base_files).map { |f| canonical_package_path.call(scope, f, base_owner, owner) }
  actual = strip.call(head_files).map { |f| canonical_package_path.call(scope, f, owner, owner) }
  expected.sort == actual.sort
end
# True when HEAD's `owner` package is exactly base's `base_owner` package with the
# identifiers rewritten: one-to-one entries including mode, and byte-exact content
# under the substitution.
package_reproduces = lambda do |scope, base_owner, owner|
  return false if scope.rename_pattern.nil?
  base_files = package_files.call(scope.base, base_owner)
  head_files = package_files.call(scope.head, owner)
  return false if base_files.nil? || head_files.nil? || base_files.empty?
  expected = base_files.map do |entry|
    mode, path = entry.split(" ", 2)
    "#{mode} #{canonical_package_path.call(scope, path, base_owner, owner)}"
  end
  return false unless expected.sort == head_files.sort
  base_lookup = base_files.to_h do |entry|
    path = entry.split(" ", 2).last
    [canonical_package_path.call(scope, path, base_owner, owner), path]
  end
  head_files.map { |entry| entry.split(" ", 2).last }
            .reject { |f| f == LEDGER_PATH }
            .all? do |changed|
    base_path = base_lookup.fetch(canonical_package_path.call(scope, changed, owner, owner))
    base_bytes = raw_blob_at.call(scope.base, base_path)
    head_bytes = raw_blob_at.call(scope.head, changed)
    !base_bytes.nil? && !head_bytes.nil? &&
      base_bytes.gsub(scope.rename_pattern) { |hit| scope.rename_pairs.fetch(hit) } == head_bytes
  end
end
# A RENAMED-AWAY owner is excused from the CUMULATIVE subject set: for the
# rename round itself its successor is in `changed` and carries the declaration,
# so the rename is declared once, against the surviving name. The excuse is
# cumulative only — a round BEFORE the rename that substantively changed the
# owner still owes a row under the old name, and the evidence check reads each
# row against its own round head, so that row is writable and stays valid after
# the rename. The per-round subject set below re-admits the excused owner for
# exactly those rounds.
#
# A DELETED owner is not that case and stays a subject. Excluding every missing
# path would let removing a decision owner outright — the larger change of the
# two — pass with no declaration at all, which is a hole the pre-existing
# contradiction did not have (it failed closed). Deletions therefore keep failing
# until the ledger accounts for them, and only a git-confirmed rename whose
# destination actually survives is dropped here.
# --no-renames deliberately surfaces the OLD path so a reference or script moved
# out of a still-live owner cannot slip past; that intent is untouched, because a
# live owner still has its SKILL.md.
# Dropping the old path is only sound when the SUCCESSOR is itself a selected
# subject. Rename a curated owner to a slug nobody added to the list above and
# neither name is selected: the old one is dropped here and the new one was never
# picked, so the rename of a decision owner escapes entirely — worse than the
# contradiction this replaced, which at least failed closed. The destination must
# already be in the selected set for the declaration to have somewhere to land.
selected_paths = upstream.to_h { |path| [path, true] }
# Owners dropped here are remembered: the per-round subject set and the row
# recognition below re-admit them for the rounds where their SKILL.md still
# existed, so the cumulative excuse cannot leak backwards onto pre-rename work.
rename_excused = {}
upstream = upstream.reject do |path|
  owner = path.sub(%r{/SKILL\.md\z}, "")
  destination = rename_pairs[owner]
  # git --find-renames is a SIMILARITY heuristic: it can pair a deleted SKILL.md
  # with an unrelated new one. For the classifier a wrong pair is harmless — it
  # only makes reproduction fail — but dropping a subject on a wrong pair is the
  # opposite, so this drop is tied to hard evidence instead: the destination
  # package must actually be the source package with the identifiers rewritten.
  excused = !File.file?(File.join(root, "skills", path)) &&
    destination && File.file?(File.join(root, "skills", destination, "SKILL.md")) &&
    selected_paths["#{destination}/SKILL.md"] &&
    package_moved.call(cumulative, owner, destination) &&
    # The cumulative endpoints also pair a round-A DELETE with a round-B ADD of
    # a lookalike — a laundering shape, not a rename. An honest rename is atomic
    # inside one round, so the excuse additionally requires some single round's
    # OWN pairs to contain the source; a cross-round delete/recreate split has
    # no such pair and stays a deletion, which fails closed.
    round_bounds.any? { |span_base, span_head| scope_at.call(span_base, span_head).rename_pairs.key?(owner) }
  rename_excused[path] = true if excused
  excused
end
if upstream.any?
  # Rows are collected PER ROUND and carry the scope they were authored against,
  # so the classifiers below judge a row against its own round's diff. Reading the
  # cumulative register diff instead would re-judge every earlier round's rows
  # against a range that keeps growing — the defect this partition removes.
  rows = []
  round_bounds.each do |span_base, span_head|
    round_scope = scope_at.call(span_base, span_head)
    register_diff = git_read.call("diff", span_base, span_head, "--", LEDGER_PATH)
    register_diff.lines.each do |line|
    next unless line.start_with?("+")
    # Strip the diff "+" and any surrounding whitespace so an indented markdown row
    # (up to 3 leading spaces is valid Markdown) parses the same as a column-0 row;
    # the pending-status scan below normalizes identically, keeping the two
    # consistent (previously "+|" alone falsely blocked a valid indented row).
    stripped = line.sub(/\A\+/, "").strip
    next unless stripped.start_with?("|") && stripped.end_with?("|")
    raw = stripped[1..-2]
    # Honor markdown-escaped pipes (\|) so a literal | inside a cell does not
    # split into spurious columns and silently drop the whole row (which would
    # later surface as a misleading "missing evidence path" for a row that is
    # actually present). Split only on UNescaped |, then unescape each cell.
    # Split on column delimiters with correct backslash parity: protect escaped
    # backslashes (\\) then escaped pipes (\|) behind control-char sentinels,
    # split on the remaining bare |, then restore. This way a | escaped by an ODD
    # number of backslashes is literal, but an even count (e.g. \\ before |) is a
    # real delimiter — so a structurally-malformed row is not silently accepted.
    esc_bs = "\u0001"; esc_pipe = "\u0002"
    cells = raw.gsub("\\\\", esc_bs).gsub("\\|", esc_pipe).split("|").map { |c| c.gsub(esc_pipe, "|").gsub(esc_bs, "\\\\").strip }
    if cells.length != 5
      # A line that otherwise looks like an impact-chain data row (cites a
      # SKILL.md and a valid status word) but has the wrong column count is
      # almost always an unescaped literal | inside a cell. Warn (advisory; does
      # not change exit code): the register carries many OTHER legitimate table
      # shapes whose prose can contain a status word and a SKILL.md citation,
      # so hard-blocking here would false-positive on unrelated ledger rows.
      # A deliberately mangled row evading per-row completeness is dishonest
      # authorship — outside this gate's trust model; the warning plus the
      # mandatory independent review own that residual.
      if raw.include?("SKILL.md") && raw.match?(/(updated|unchanged|routed|not-applicable)/)
        warn "impact_chain_row_malformed: likely an unescaped pipe inside a cell (escape it as backslash-pipe): #{line.strip}"
      end
      next
    end
    next unless !cells.any?(&:empty?) && cells[4] != "---" && cells[1] != "Downstream owner"
    status = cells[3].delete("`").strip
    next unless status.match?(/\A(updated|unchanged|routed|not-applicable)\z/)
    rows << { line: line, status: status, evidence: cells[4], behavior: cells[2], scope: round_scope }
    end
  end
  # A row counts only if it SURVIVES at HEAD. Round scoping alone would accept a
  # row added in one round and deleted in a later one: the cumulative read this
  # replaces saw that as a net zero and failed closed, and losing it would make
  # "append the row, drop it next round" a laundering route. The ledger is
  # append-only, so requiring survival costs an honest author nothing. A missing or
  # undecodable register leaves the set empty and every subject falls through to
  # the presence check, which fails closed.
  # Survival is counted as a MULTISET, not a set. A boolean "this text exists at
  # HEAD" is forgeable when the text ALREADY existed at base: append a duplicate in
  # the round that needs a row, drop one copy in a later ledger-only round, and the
  # ledger ends byte-identical while the transient row still reads as surviving.
  # The budget is therefore how many occurrences the round span ADDED — HEAD's count
  # minus base's — and each accepted row consumes one. That also subsumes the
  # first-round-wins rule: a text re-added by a later round finds the budget spent,
  # so an old row's verdict is never re-litigated against a newer round.
  register_row_counts = lambda do |ref|
    bytes = raw_blob_at.call(ref, LEDGER_PATH).to_s.dup.force_encoding(Encoding::UTF_8)
    next Hash.new(0) unless bytes.valid_encoding?
    bytes.lines.each_with_object(Hash.new(0)) { |l, counts| counts[l.strip] += 1 }
  end
  base_row_counts = register_row_counts.call(base_ref)
  head_row_counts = register_row_counts.call("HEAD")
  row_budget = Hash.new(0)
  head_row_counts.each { |text, count| row_budget[text] = count - base_row_counts[text] }
  rows.select! do |row|
    key = row[:line].sub(/\A\+/, "").strip
    next false unless row_budget[key].positive?
    row_budget[key] -= 1
    true
  end
  bad_evidence_files = []
  ambiguous_evidence_rows = []
  evidence_rows_by_upstream_path = Hash.new(0)
  rows_by_upstream_path = Hash.new { |h, k| h[k] = [] }
  declared_in_round = {}
  upstream_set = upstream.to_h { |path| [path, true] }
  # Selected-owner rename LINEAGE. A transient intermediate name — X renamed to
  # Y in one round, Y to Z in a later one — appears in neither the cumulative
  # diff (which pairs X with Z directly) nor the excused set, yet a round that
  # substantively changed Y owes its row like any other selected owner (both
  # review lanes independently found this laundering path). Walk the rounds in
  # order and propagate selection through each round's OWN rename pairs; every
  # name reached this way is treated exactly like the directly-excused source
  # name: demanded and recognized wherever it exists at a round head. Pairs come
  # from git per span, never from an author declaration, and a name outside the
  # selected lineage can never join, so this only ever adds obligations.
  lineage_extra = rename_excused.dup
  round_bounds.each do |span_base, span_head|
    scope_at.call(span_base, span_head).rename_pairs.each do |from_owner, to_owner|
      from_path = "#{from_owner}/SKILL.md"
      to_path = "#{to_owner}/SKILL.md"
      next unless upstream_set[from_path] || lineage_extra[from_path]
      lineage_extra[to_path] = true unless upstream_set[to_path]
    end
  end
  # One round's subject set: the same normalization the cumulative pass uses,
  # intersected with the cumulative selection — so a round can never demand a row
  # for an owner the curated-list filter never picked. A lineage name (the
  # rename-excused source or a transient intermediate hop) is admitted for
  # exactly the rounds where its SKILL.md still exists at the round head: those
  # rounds' rows cite a name that was real when the round landed and stays
  # checkable against that round's head. In the round that renames it away the
  # SKILL.md is gone at the head, so the old name is not demanded there and the
  # successor carries that round's declaration — which is the whole cumulative
  # excuse, now scoped to the one round it is sound for. A DELETED owner was
  # never excused and is unaffected.
  upstream_for_round = lambda do |scope|
    scope.changed_paths.filter_map do |path|
      next nil if path == LEDGER_PATH
      m = path.match(%r{\Askills/([^/]+)/.+\z}m)
      "#{m[1]}/SKILL.md" if m
    end.uniq.select do |candidate|
      next false unless upstream_set[candidate] || lineage_extra[candidate]
      next true if regular_blob_at.call(scope.head, "skills/#{candidate}")
      # Absent at this round's head. The demand is suppressed ONLY when this
      # round's own git-verified pairs rename the name to a SELECTED successor —
      # that successor carries this round's declaration, and a rename CYCLE
      # (A to B, then B back to A) stays fully declarable without ever asking
      # for a row the evidence check must refuse. Everything else stays
      # demanded: a deletion has no pair and fails closed, and a rename to an
      # unselected slug keeps the curated source bound as the named subject.
      owner = candidate.sub(%r{/SKILL\.md\z}, "")
      destination = scope.rename_pairs[owner]
      !(destination && selectable_path.call("#{destination}/SKILL.md"))
    end
  end
  rows.each do |row|
    paths = row[:evidence].scan(/(?<![\w\/.-])([a-z][a-z0-9_-]+\/SKILL\.md)(?![\w\/.-])/).flatten.uniq
    # A lineage name's rows are recognized as declarations, matching the
    # per-round subject set above — demanding a row the mapping then ignored
    # would be the same contradiction the excuse used to justify.
    upstream_paths_in_row = paths.select { |path| upstream_set[path] || lineage_extra[path] }
    if upstream_paths_in_row.length > 1
      ambiguous_evidence_rows << { line: row[:line].sub(/^\+/, "").strip, paths: upstream_paths_in_row }
    end
    if upstream_paths_in_row.length == 1
      evidence_rows_by_upstream_path[upstream_paths_in_row.first] += 1
      rows_by_upstream_path[upstream_paths_in_row.first] << row
      declared_in_round[[row[:scope].base, row[:scope].head, upstream_paths_in_row.first]] = true
    end
  end
  unless ambiguous_evidence_rows.empty?
    warn "impact_chain_row_ambiguous: source-register evidence row cites multiple changed upstream SKILL.md paths; split into one row per changed upstream SKILL.md"
    ambiguous_evidence_rows.each do |row|
      warn "  paths: #{row[:paths].join(", ")}"
      warn "  row: #{row[:line]}"
    end
  end
  # Existence is checked against the ROW'S OWN ROUND HEAD, not the working tree.
  # A row is authored against one round's diff, so the name it cites only has to
  # be real when that round landed: reading the working tree instead made a later
  # rename retroactively invalidate honest pre-rename rows — and that impossible
  # row was the stated excuse for dropping renamed-away owners from every round's
  # subject set, which let their pre-rename work escape undeclared. A row citing
  # a name its own round never had stays rejected.
  rows.each do |row|
    row[:evidence].scan(/(?<![\w\/.-])([a-z][a-z0-9_-]+\/SKILL\.md)(?![\w\/.-])/).flatten.each do |path|
      bad_evidence_files << path unless regular_blob_at.call(row[:scope].head, "skills/#{path}")
    end
  end
  if bad_evidence_files.any?
    warn "impact_chain_evidence_missing_file: evidence cites a SKILL.md missing at its round head"
    bad_evidence_files.uniq.each { |path| warn "  missing: #{path}" }
    exit 1
  end
  # Presence is checked PER ROUND, not across the range. Cumulative presence let
  # owner work committed after a ledger append ride on an EARLIER round's row —
  # the row said nothing about those bytes. Now that classification is round-scoped
  # this is the matching obligation on the other side: the round that changed an
  # owner is the round that owes the row. Work and its ledger append land in the
  # same round whenever no other append separates them, so the ordinary
  # "commit the change, then append the row" shape is unaffected.
  missing_paths = round_bounds.flat_map do |span_base, span_head|
    round_scope = scope_at.call(span_base, span_head)
    upstream_for_round.call(round_scope).reject do |path|
      declared_in_round[[span_base, span_head, path]]
    end
  end.uniq
  unless missing_paths.empty?
    warn "impact_chain_gate_missing: upstream-owner skill changed without a matching source-register impact-chain row"
    warn "  note: for an upstream owner, its references/ and scripts/ count as a change too (they ship decision-surface/operational behavior); cite the owning <skill>/SKILL.md in the row evidence cell"
    warn "  fix: add one row per changed upstream owner in skill-extraction-workflow/references/source-register.md"
    warn "  row shape: | <upstream rule> | `<downstream owner>` | <expected executable behavior> | `updated|unchanged|routed|not-applicable` | <owning `<skill>/SKILL.md` is the machine key; add any changed reference/script path as supporting evidence> | (escape any literal pipe inside a cell as backslash-pipe)"
    upstream.each { |path| warn "  changed: #{path}" }
    missing_paths.each { |path| warn "  missing evidence path: #{path}" }
    exit 1
  end

  # A matching owner path proves only that a ledger row exists. It does not
  # prove the changed rule can fire, or that an observed failure now has a
  # firing path. Require the behavioral-evidence declaration and firing path in
  # the SAME added row so a content-only "already covered" disposition cannot
  # satisfy the impact-chain gate. Intentionally diff-scoped: historical rows
  # are not retrofitted.
  behavior_failures = []
  firing_path_failures = []
  # Lazily computed and memoized per owner: most rows are RED-baseline /
  # semantic-control and never consult the wording-only classification, so the
  # per-owner diff subprocess only runs when a row actually declares
  # `not-required wording-only` (or the owner-level RED floor needs it).
  wording_only_diff_cache = {}
  wording_only_diff_for = lambda do |scope, path|
    cache_key = [scope.base, scope.head, path]
    return wording_only_diff_cache[cache_key] if wording_only_diff_cache.key?(cache_key)
    owner = path.sub(%r{/SKILL\.md\z}, "")
    # The letters/digits bar is a PROSE heuristic: in runnable content,
    # punctuation-only edits (`:` -> `! :`, a deleted `)`) change behavior.
    # The class therefore applies only when EVERY changed owner file is
    # Markdown prose; any non-.md file (script, runnable reference, overlay)
    # disqualifies it outright.
    non_prose_changed = scope.changed_paths.any? do |changed|
      next false unless changed.start_with?("skills/#{owner}/")
      next false if changed == LEDGER_PATH
      changed.start_with?("skills/#{owner}/scripts/") || !changed.end_with?(".md")
    end
    owner_diff = git_read.call("diff", "--no-ext-diff", "--unified=0", scope.base, scope.head, "--",
                               "skills/#{owner}", ":(exclude)#{LEDGER_PATH}")
    changed_content = owner_diff.lines.filter_map do |line|
      next if line.start_with?("+++", "---")
      line[1..] if line.start_with?("+", "-")
    end
    wording_only_diff_cache[cache_key] = !non_prose_changed && !changed_content.empty? && changed_content.none? { |line| line.match?(/[\p{L}\p{N}]/) }
  end
  # Rename pairs come from git's own tree state — which owner packages
  # disappeared and which appeared — never from an author declaration. How the
  # pairs are derived does not have to be trustworthy, because a wrong pair can
  # only make the reproduction below fail: the class is granted solely when
  # rewriting the BASE bytes with the pairs reproduces the HEAD bytes exactly,
  # so smuggled content of any size breaks equality and falls back to the normal
  # evidence bar. Every derivation error is therefore strictly conservative.
  # This is not the baseline-nomination mechanism removed from the size budget:
  # nothing here lets a diff be measured against a DIFFERENT file — the
  # comparison is always the same path against a mechanical transform of itself.
  # `rename_pairs` / `rename_pattern` are computed before the subject filter above,
  # which needs them to tell a rename apart from a deletion.
  # Named apart from the `blob_at` defined further down: that one returns entry
  # metadata for the firing-path anchors, and sharing the name would silently
  # rebind this closure to it.
  identifier_rename_cache = {}
  identifier_rename_diff_for = lambda do |scope, path|
    cache_key = [scope.base, scope.head, path]
    return identifier_rename_cache[cache_key] if identifier_rename_cache.key?(cache_key)
    owner = path.sub(%r{/SKILL\.md\z}, "")
    identifier_rename_cache[cache_key] = begin
      # The class is for owners that merely RETARGET a pointer. The renamed owner
      # itself never qualifies: its package bytes may reproduce, but the name is
      # how hosts and callers resolve it, so changing it IS the behaviour change —
      # every caller still saying the old name now resolves to nothing. A
      # destination therefore owes the normal RED evidence and firing path, the
      # same bar its own rename record has to meet.
      if scope.rename_pattern.nil? || scope.rename_pairs.value?(owner)
        false
      else
        owner_changed = scope.changed_paths.select do |changed|
          changed.start_with?("skills/#{owner}/") && changed != LEDGER_PATH
        end
        source_owner = scope.rename_pairs.key(owner)
        !owner_changed.empty? && package_reproduces.call(scope, source_owner || owner, owner)
      end
    end
  end
  # A routing-surface-only change edits the frontmatter `description` and nothing
  # else. The firing path must anchor on a CHANGED numbered/list rule carrying a
  # normative verb; a one-line YAML scalar is neither, so such an owner has no
  # anchor to point at and would otherwise be forced to pad its body with a
  # restatement purely to satisfy the anchor — on entrypoints that a separate
  # zero-growth budget forbids from growing at all.
  #
  # The safety argument is the INVERSE of the identifier-rename class and has to
  # be, because a wrong judgement here is LOOSER than the normal bar rather than
  # stricter: nothing is derived or guessed, so there is no derivation that could
  # err conservatively. Instead the class is granted only when the owner's whole
  # change is accounted for byte-for-byte — one changed file, identical body,
  # identical frontmatter apart from the single description entry. Every shape the
  # split cannot fully account for refuses the class.
  routing_surface_cache = {}
  # The file MODE is part of the entrypoint's identity, exactly as it is for the
  # package comparison above: bytes alone would let `chmod +x` on SKILL.md ride
  # along with a description edit and still read as description-only.
  entry_mode = lambda do |ref, relative|
    out = IO.popen(["git", "-C", root, "ls-tree", "-z", ref, "--", relative], err: File::NULL, &:read)
    next nil unless $?.success?
    entry = out.split("\0").reject(&:empty?).first
    entry && entry.split(/\s+/, 2).first
  end
  # "---\n<frontmatter>\n---\n<body>" -> [frontmatter, body] as BYTES, or nil when
  # the delimiters are not exactly where the format requires.
  split_frontmatter = lambda do |bytes|
    m = bytes.match(/\A---\n(.*?\n)---\n/m)
    next nil unless m
    [m[1], m.post_match]
  end
  # Split the frontmatter into [everything that is not the description entry, the
  # description entry itself]. The entry is its `description:` line plus any
  # indented continuation lines, so a block or folded scalar is one entry rather
  # than a first line and some orphans. Absent or repeated keys return nil, which
  # refuses the class rather than picking one.
  split_description_entry = lambda do |frontmatter|
    lines = frontmatter.lines
    # YAML allows the key quoted or spaced before the colon; refusing those forms
    # would block a legitimate description-only change with no satisfiable anchor.
    key = /\A(?:"description"|'description'|description)[ \t]*:/
    starts = lines.each_index.select { |i| lines[i].match?(key) }
    next nil unless starts.length == 1
    first = starts.first
    # The entry runs to the next TOP-LEVEL key, not to the first unindented line:
    # a folded scalar may contain blank lines between paragraphs, and stopping at
    # one would move the later paragraphs into the "other keys" set and refuse a
    # perfectly ordinary description edit. Indentation is a shape proxy; "where the
    # next top-level key starts" is the structure YAML itself uses.
    last = first + 1
    last += 1 while last < lines.length && !lines[last].match?(/\A\S/)
    [lines[0...first] + lines[last..], lines[first...last]]
  end
  # Whatever the line split decides, the value must still BE a description: a
  # string. Widening the entry to the next top-level key means a nested mapping
  # (`description:` followed by indented `key: value` pairs) would otherwise ride
  # inside the entry, letting arbitrary frontmatter through and even carrying the
  # anchor. Parsing settles it with the format's own rules rather than another
  # shape heuristic; anything that fails to parse, or whose description is not a
  # string, refuses the class.
  # Whatever the line split decides, the value must still BE a description: a
  # string. Widening the entry to the next top-level key means a nested mapping
  # (`description:` followed by indented `key: value` pairs) would otherwise ride
  # inside the entry, letting arbitrary frontmatter through and even carrying the
  # locator. Parse ONLY the entry, never the whole frontmatter: a sibling key that
  # deserializes to a Date or uses an alias makes `safe_load` raise, and rescuing
  # that to nil would refuse a legitimate owner for a key this class does not care
  # about. Anything that still fails to parse, or whose description is not a
  # string, refuses the class.
  description_is_scalar = lambda do |frontmatter|
    text = frontmatter.dup.force_encoding(Encoding::UTF_8)
    next false unless text.valid_encoding?
    parsed = begin
      YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
    rescue StandardError
      nil
    end
    parsed.is_a?(Hash) && parsed["description"].is_a?(String)
  end
  routing_surface_diff_for = lambda do |scope, path|
    cache_key = [scope.base, scope.head, path]
    return routing_surface_cache[cache_key] if routing_surface_cache.key?(cache_key)
    owner = path.sub(%r{/SKILL\.md\z}, "")
    routing_surface_cache[cache_key] = begin
      # NO register exclusion here, unlike the classifiers above. The ledger lives
      # inside one owner's package, and for that owner "the entire change is the
      # description" would otherwise be satisfiable while arbitrary normative
      # ledger content rode along. Dropping the exclusion costs the other owners
      # nothing (the ledger is not under their package) and correctly makes the
      # class unavailable to the owner that ships it.
      owner_changed = scope.changed_paths.select { |changed| changed.start_with?("skills/#{owner}/") }
      entrypoint = "skills/#{owner}/SKILL.md"
      # The rest of the package may differ ONLY by a rename retarget — the same
      # class the gate already machine-proves carries no obligation. This tolerance
      # was added when the classifier still read the whole accumulating range and an
      # owner whose only behaviour was its description got refused for retargets
      # already declared no-behaviour; the round scoping now removes that pressure
      # at the source, and the tolerance stays only because a retarget landing in
      # the SAME round is still genuinely no-behaviour. The bound is the identical
      # byte-exact reproduction used there: apply git's own rename pairs to the base
      # bytes and require the head bytes exactly, mode included. A file that cannot
      # be accounted for that way — one real byte of content — takes the locator away.
      # One normalizer for both halves: the entrypoint's own body and non-description
      # keys mention renamed slugs too, so comparing them raw would refuse the very
      # shape this composition exists for. The description entry is exempt because
      # it is the change being evidenced.
      retarget = lambda do |bytes|
        next bytes unless scope.rename_pattern
        bytes.gsub(scope.rename_pattern) { |hit| scope.rename_pairs.fetch(hit).dup.force_encoding(Encoding::BINARY) }
      end
      others_reproduce = (owner_changed - [entrypoint]).all? do |other|
        # Prose only, for the same reason the wording-only class refuses non-.md
        # files: a substitution reproducing a SCRIPT's bytes says nothing about
        # whether rewriting that identifier was safe there. Some occurrences of an
        # old slug are deliberately kept — a persisted key, an uninstall manifest —
        # and rewriting one is a behaviour change the normalizer would wave through.
        next false if other.start_with?("skills/#{owner}/scripts/") || !other.end_with?(".md")
        # Regular files only, on BOTH sides. A symlink's blob is its TARGET, so a
        # `.md` symlink whose target carries an old slug reproduces under the
        # substitution while what the path resolves to changes — a filesystem
        # behaviour the normalizer has no business clearing. Same for a mode flip.
        next false unless entry_mode.call(scope.base, other) == "100644"
        next false unless entry_mode.call(scope.head, other) == "100644"
        base_bytes = raw_blob_at.call(scope.base, other)
        head_bytes = raw_blob_at.call(scope.head, other)
        next false if base_bytes.nil? || head_bytes.nil?
        retarget.call(base_bytes) == head_bytes
      end
      if !owner_changed.include?(entrypoint) || !others_reproduce
        false
      else
        # `path` is owner-relative in this loop; blob reads need the repo path.
        base_bytes = raw_blob_at.call(scope.base, entrypoint)
        head_bytes = raw_blob_at.call(scope.head, entrypoint)
        base_parts = base_bytes && split_frontmatter.call(base_bytes)
        head_parts = head_bytes && split_frontmatter.call(head_bytes)
        if base_parts.nil? || head_parts.nil?
          false
        else
          base_split = split_description_entry.call(base_parts[0])
          head_split = split_description_entry.call(head_parts[0])
          !base_split.nil? && !head_split.nil? &&
            base_split[0].map { |l| retarget.call(l) } == head_split[0] &&
            retarget.call(base_parts[1]) == head_parts[1] &&
            base_split[1].map { |l| retarget.call(l) } != head_split[1] &&
            description_is_scalar.call(base_parts[0]) && description_is_scalar.call(head_parts[0]) &&
            entry_mode.call(scope.base, entrypoint) == entry_mode.call(scope.head, entrypoint) &&
            !entry_mode.call(scope.head, entrypoint).nil?
        end
      end
    end
  end
  added_lines_cache = {}
  added_lines_for = lambda do |scope, relative|
    rel = relative.to_s.strip
    added_lines_cache[[scope.base, scope.head, rel]] ||=
      git_read.call("diff", "--no-ext-diff", "--unified=0", scope.base, scope.head, "--", rel).lines.filter_map do |line|
        next if line.start_with?("+++")
        line[1..]&.chomp if line.start_with?("+")
      end
  end
  # Raw tree entry at a path (memoized, including nil): `mode type oid\tpath`,
  # or nil when no entry of ANY type exists. `-z` keeps the path raw so entries
  # for paths with unusual bytes still compare equal to the requested rel
  # instead of failing on git's line-oriented quoting.
  tree_entry_cache = {}
  tree_entry_at = lambda do |treeish, relative|
    rel = relative.to_s.strip
    next nil if rel.empty? || rel.start_with?("/") || rel.include?(":") || rel.split("/").include?("..")
    key = [treeish, rel]
    next tree_entry_cache[key] if tree_entry_cache.key?(key)
    entry = IO.popen(["git", "-C", root, "ls-tree", "-z", treeish, "--", rel], &:read).split("\0").first.to_s
    tree_entry_cache[key] = entry.empty? ? nil : entry
  end
  # Memoized (including nil results): the same (treeish, path) blob can be
  # fetched by several locator checks; without the cache each fetch costs git
  # subprocesses. Only a regular blob (100644/100755) resolves; symlinks,
  # submodules, and trees return nil.
  blob_cache = {}
  blob_at = lambda do |treeish, relative|
    rel = relative.to_s.strip
    key = [treeish, rel]
    next blob_cache[key] if blob_cache.key?(key)
    entry = tree_entry_at.call(treeish, rel)
    blob_cache[key] = if entry
      meta, listed = entry.split("\t", 2)
      mode, type, _oid = meta.to_s.split(/\s+/, 3)
      if %w[100644 100755].include?(mode) && type == "blob" && listed == rel
        content = IO.popen(["git", "-C", root, "show", "#{treeish}:#{rel}"], &:read)
        { path: rel, mode: mode, content: content }
      end
    end
  end
  # The locator must resolve in the round's own head, not the branch tip: a later
  # round that deletes or rewrites the anchored file must not retroactively
  # invalidate — or silently re-validate — an earlier round's locator.
  head_blob = ->(scope, relative) { blob_at.call(scope.head, relative) }
  locator_parts = lambda do |raw|
    locator = raw.to_s.strip
    if (m = locator.match(/\Acommand:([^\s;]+)\z/))
      { kind: "command", path: m[1] }
    elsif (m = locator.match(/\Afile:([^#\s;]+)#(.+)\z/))
      anchor = m[2].strip
      { kind: "file", path: m[1], anchor: anchor } unless anchor.empty?
    end
  end
  locator_valid = lambda do |scope, raw|
    parts = locator_parts.call(raw)
    next false unless parts
    blob = head_blob.call(scope, parts[:path])
    added = added_lines_for.call(scope, parts[:path])
    next false unless blob && !added.empty?
    if parts[:kind] == "command"
      # An executable firing surface must actually be a script: mode 100755
      # AND a shebang. Without this, any changed file with the executable bit
      # (even a chmod'ed Markdown file) satisfies a command locator.
      blob[:mode] == "100755" && blob[:content].start_with?("#!")
    else
      anchor = parts[:anchor]
      anchor.length >= 16 &&
        added.count { |line| line.include?(anchor) } == 1 &&
        blob[:content].scan(Regexp.new(Regexp.escape(anchor))).length == 1
    end
  end
  enforcing_file_locator_valid = lambda do |scope, parts|
    next false unless parts && parts[:kind] == "file"
    next false unless parts[:path].end_with?(".md")
    next false unless locator_valid.call(scope, "file:#{parts[:path]}##{parts[:anchor]}")
    line = added_lines_for.call(scope, parts[:path]).find { |added| added.include?(parts[:anchor]) }
    next false unless line
    # A non-rendered HTML comment can smuggle normative vocabulary past the
    # heuristic (`- <!-- must ... -->`); an anchor line carrying a comment
    # marker is never an enforcing rule surface.
    next false if line.include?("<!--")
    list_rule = line.lstrip.match?(/\A(?:[-*+]\s+|\d+[.)]\s+)/)
    # Normative-action vocabulary. This is a recall heuristic, not a semantic
    # parser: it accepts common imperative/prohibitive phrasings in English and
    # Chinese (never/do not/应当/务必/不能 included so a genuinely normative
    # rule is not rejected for its verb choice) while still refusing anchors on
    # purely descriptive prose. Deliberately excluded for precision: "always"
    # and "does not" (dominant descriptive uses — "the host always exposes",
    # "the adapter does not support"), and single characters with broad
    # compounds (应/只/别 — 应用/只是/区别).
    normative = line.match?(/(?:\b(?:must|shall|never|do\s+not|don'?t|required?|requires?|block(?:s|ed)?|reject(?:s|ed)?|deny|denied|invalidates?|forbid(?:s|den)?|cannot|enforcement)\b|必须|不得|禁止|拒绝|作废|仅限|只能|应当|应该|务必|不能|不允许|不可)/i)
    list_rule && normative
  end
  # A routing-surface-only owner has no changed rule line to anchor on: its whole
  # change is one YAML scalar. The answer is NOT to exempt it — a description edit
  # IS a routing behaviour change (it decides which requests reach the skill), so
  # exempting it would drop the evidence requirement from the class that carries
  # the most behaviour, and its evidence exists anyway as a measured routing delta.
  # Instead the anchor may land on the changed description entry itself. Every other
  # requirement is unchanged — owner-scoped path, minimum length, unique in the
  # file, present in this diff's added lines — and only the "numbered/list rule with
  # a normative verb" SHAPE is lifted, because a YAML scalar can never take it.
  # The widening is bounded by the same byte-exact predicate: an owner that changed
  # anything besides the description keeps the ordinary anchor bar.
  routing_surface_anchor_valid = lambda do |scope, parts, owner|
    next false unless parts[:kind] == "file"
    next false unless parts[:path] == "skills/#{owner}/SKILL.md"
    # A CANONICAL FIELD LOCATOR, not a text search. Three designs tried to make a
    # substring anchor prove which bytes changed — a numbered/list rule shape, then
    # the `description:` line, then any line of the entry — and each was refuted in
    # turn, the last because a substring that merely SURVIVES the edit identifies
    # nothing. Same class three times is the signal to drop the proxy rather than
    # patch it again: the predicate below already proves the entire owner diff IS
    # the description entry, so the locator's only job is to name that field. The
    # length/uniqueness rules that guard a free-text anchor have nothing to guard
    # here, and applying them to a constant would be ceremony dressed as evidence.
    next false unless parts[:anchor] == "description"
    routing_surface_diff_for.call(scope, "#{owner}/SKILL.md")
  end
  firing_locator_valid = lambda do |scope, parts, owner|
    next false unless parts && parts[:path].start_with?("skills/#{owner}/")
    if parts[:kind] == "command"
      locator_valid.call(scope, "command:#{parts[:path]}")
    else
      routing_surface_anchor_valid.call(scope, parts, owner) ||
        enforcing_file_locator_valid.call(scope, parts)
    end
  end
  # Lineage names join the walk: their recognized rows must clear the same
  # behavior-evidence and firing-path bar as everyone else's (each row judged
  # against its own round, where its anchors resolve), or the admission above
  # would accept rows it never validates.
  (upstream + lineage_extra.keys).each do |path|
    owner_rows = rows_by_upstream_path[path]
    next if owner_rows.empty? # reported by impact_chain_gate_missing above
    owner = path.sub(%r{/SKILL\.md\z}, "")

    # Parse and validate each row exactly once; both the pass/fail decision and
    # the failure-bucket classification below consume these structs, so the row
    # grammar lives in one place and a failing owner does not pay a second full
    # validation walk (each walk costs git subprocesses via the blob lookups).
    evaluated = owner_rows.map do |row|
      # Every predicate below reads the row's OWN round. This is what makes a
      # verdict stable: the span it is judged against is fixed when the row lands
      # and cannot grow afterwards.
      row_scope = row[:scope]
      text = row[:behavior]
      # Declarations parse from semicolon-delimited fragments, each field
      # anchored at its fragment start: a key embedded mid-prose ("no
      # behavioral-evidence: ...") or carrying a suffixed value never counts.
      declarations = {}
      text.split(";").each do |fragment|
        if (m = fragment.match(/\A\s*(behavioral-evidence|observed-failure|firing-path):\s*(.+?)\s*\z/i))
          declarations[m[1].downcase] ||= m[2]
        end
      end
      status = declarations["behavioral-evidence"]&.[](/\A(RED-baseline|semantic-control|not-required\s+wording-only|not-required\s+identifier-rename)\z/i, 1)
      normalized_status = status&.downcase&.gsub(/\s+/, " ")
      declared_wording_only = normalized_status == "not-required wording-only"
      wording_only = declared_wording_only && wording_only_diff_for.call(row_scope, path)
      declared_identifier_rename = normalized_status == "not-required identifier-rename"
      identifier_rename = declared_identifier_rename && identifier_rename_diff_for.call(row_scope, path)
      # Both no-behavior classes are machine-verified, so they share a branch. A
      # routing-surface-only change is NOT one of them: it carries behaviour, so it
      # keeps the RED-baseline bar and only gains a place its anchor can bind.
      no_behavior_class = wording_only || identifier_rename
      observed = declarations["observed-failure"]&.[](/\A(yes|no)\z/i, 1)&.downcase
      semantic_control = normalized_status == "semantic-control" && observed == "no"
      status_allowed = no_behavior_class || normalized_status == "red-baseline" || semantic_control
      firing_path = declarations["firing-path"]&.[](/\A((?:command|file):.+)\z/i, 1)&.strip
      firing_parts = locator_parts.call(firing_path)
      firing_path_valid = firing_locator_valid.call(row_scope, firing_parts, owner)
      # The machine-checked core is the FIRING PATH (an owner-scoped anchor on a
      # changed normative rule, or a changed owner executable) plus the
      # deterministic wording-only classification. The behavioral-evidence
      # status and observed-failure fields are required author declarations —
      # honest labels, not digest-verified artifacts: a digest-bound evidence
      # apparatus was evaluated here and removed because its per-iteration
      # regeneration cost (full-suite reruns on every owner-script byte change)
      # far outweighed the staleness detection it added under the
      # unsigned-repository-local trust model.
      row_valid = if no_behavior_class
        # Neither `not-required` class is an author-controlled waiver: each is
        # accepted only when the owner diff itself passes the matching
        # deterministic classifier — letters/digits-free for wording-only,
        # byte-exact reproduction under the git-derived rename pairs for
        # identifier-rename. Both record no observed failure, and neither can
        # carry a firing path, because a retarget changes no normative rule to
        # anchor one on.
        status_allowed && observed == "no"
      else
        status_allowed && firing_path_valid &&
          (observed == "no" || (observed == "yes" && status&.casecmp?("RED-baseline")))
      end
      {
        red_declared: normalized_status == "red-baseline",
        row_valid: row_valid,
        firing_path_valid: firing_path_valid
      }
    end

    # A stable-control label can say one named behavior did not change, but it
    # cannot vouch for the rest of a non-wording owner diff. Require at least
    # one RED-baseline row per non-wording owner so a package cannot self-clear
    # on semantic-control labels alone. The floor is lifted only for the two
    # machine-verified no-behavior classes, whose whole point is that there is
    # nothing left for a label to hide: an owner whose bytes are reproduced by
    # rewriting identifiers has no unvouched-for remainder, so demanding an
    # observed delta there would only be satisfiable by inventing one.
    # The floor deliberately reads the CUMULATIVE diff, not a round. It asks
    # whether anything in this owner's whole change is left unvouched-for, so
    # narrowing it to one round would let a package self-clear on the one round
    # that happened to be punctuation-only. Cumulative is the strictly stricter
    # reading of the two, so the round scoping cannot loosen this floor.
    valid = evaluated.all? { |entry| entry[:row_valid] }
    valid &&= evaluated.any? { |entry| entry[:red_declared] } ||
              wording_only_diff_for.call(cumulative, path) ||
              identifier_rename_diff_for.call(cumulative, path)
    next if valid

    # Bucket the failure for the diagnostic: a declared RED row whose firing
    # path is broken gets the firing-path message; every other failure shape
    # gets the behavior-evidence message. (A declared wording-only row can
    # never be a RED row, so no exclusion is needed here.)
    firing_path_incomplete = evaluated.any? do |entry|
      entry[:red_declared] && !entry[:firing_path_valid]
    end
    if firing_path_incomplete
      firing_path_failures << path
    else
      behavior_failures << path
    end
  end
  unless firing_path_failures.empty?
    warn "impact_chain_firing_path_missing: RED-baseline row has no owner-scoped firing path in this committed diff"
    warn "  fix: point to this owner with `firing-path: command:<changed repo executable>` or `firing-path: file:<changed markdown>#<unique token on a changed numbered/list rule with a normative action>`"
    firing_path_failures.each { |path| warn "  incomplete: #{path}" }
    exit 1
  end
  unless behavior_failures.empty?
    warn "impact_chain_behavior_evidence_missing: at least one added upstream-owner row lacks a complete behavioral-evidence declaration"
    warn "  fix: every added row for a changed upstream owner needs `behavioral-evidence: RED-baseline` (observed deltas; observed-failure: yes requires it) or `semantic-control` (only with observed-failure: no), plus `observed-failure: yes/no` and an owner-scoped `firing-path:`; a non-wording owner package needs at least one RED-baseline row; only deterministically wording-only diffs (no letters or digits changed) may use `not-required wording-only`, and only diffs whose base bytes are reproduced exactly by applying git-derived skill-rename pairs may use `not-required identifier-rename` (both drop the firing-path requirement and require observed-failure: no); an owner whose ENTIRE change is the SKILL.md frontmatter description entry keeps the RED-baseline bar and may anchor its firing path on that changed description line"
    behavior_failures.each { |path| warn "  incomplete: #{path}" }
    exit 1
  end
end
