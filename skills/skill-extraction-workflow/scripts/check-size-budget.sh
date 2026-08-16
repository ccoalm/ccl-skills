#!/usr/bin/env bash
# Entrypoint size gate: machine-readable anti-regrowth signal PLUS delta-blocking.
#
# Blocking (delta-scoped, per changed skills/*/SKILL.md):
#   - a changed entrypoint that is NEW or CROSSES over 50000 bytes (base was not
#     severe)                => block ("new severe entrypoint")
#   - a changed entrypoint already over 50000 bytes in base that GREW
#     (head_bytes > base_bytes) => block ("severe entrypoint grew")
# Existing severe files may be edited and shrunk — only growth blocks. Files at or
# under 50000 bytes may grow freely up to the threshold. This delta shape stops
# the monotonic-growth bleeding without retroactively gating every edit of the
# three legacy mega-entrypoints, and without rewarding a rush to pre-shrink.
#
# Blocking (delta-scoped, agent-context/session-start.md — the every-session injection):
#   - a CHANGED agent-context/session-start.md whose head_bytes > base_bytes => block ("agent-context/session-start.md
#     grew"); it may always shrink or be edited at the same size. The always-on
#     layer is permanently in the severe class: every net growth must be offset by
#     equal compression, and a fixed byte tripwire cannot express that (the layer
#     already exceeds any achievable fixed number at its zero-loss floor, so a
#     fixed tripwire either false-reds or degrades to a permanently-firing
#     advisory = no signal). A agent-context/session-start.md absent from base is treated as a NEW
#     every-session injection and blocks like a new severe entrypoint.
#
# Advisory (never blocks on its own): the recommended-band body-char debt
# counters, severe-debt counters, per-file deltas, and the agent-context/session-start.md 13000B
# byte tripwire BAND remain VISIBILITY / DEBT-MANAGEMENT only (the band flags the
# zero-loss floor overshoot; the NET-GROWTH delta above is what blocks), and the
# legacy ok markers are printed on clean verdicts (on a block/partial the last
# token is always the failure marker, never an ok). Exceeding the recommended
# band is NOT a clean-landing waiver and NOT authorization to keep growing an
# entrypoint; a new/expanded large entrypoint must still record its rationale
# and a split plan.
#
# Two metrics, two thresholds (kept distinct on purpose):
#   - entrypoint body CHARS  > 5000  => "debt" (over the recommended 1k–5k body band)
#   - whole-file BYTES       > 50000 => "severe debt" (historical mega-entrypoint)
# A third metric is blocking for changed entrypoints:
#   - entrypoint body WORDS  > 5000  => block for new/within-limit files; a
#     historical over-limit file may stay level or shrink, but may not grow.
# The word metric excludes YAML frontmatter. It counts Unicode letter/number
# runs as words and each Han ideograph as one deterministic word-equivalent unit.
# The anti-bypass guarantee is therefore calibrated for space-delimited scripts
# plus Han; other unspaced scripts remain one Unicode letter/number run.
# The canonical validator separately parses frontmatter as YAML and rejects a
# description longer than 800 chars. Other frontmatter keys are outside this
# body-word gate and are not claimed to have a length cap here.
# Body chars are measured after stripping YAML frontmatter (the recommended-band
# metric the B0 checklist uses); whole-file bytes are the LC_ALL=C-equivalent size
# (Ruby File.size returns bytes), matching the legacy `wc -c` 50KB advisory.
#
# agent-context/session-start.md (the every-session injection) keeps its own BYTE tripwire band
# (advisory) PLUS the net-growth delta block above; other always-injected
# surfaces (AGENTS.md, hooks) are NOT claimed here. The trailing
# `size_budget_advisory_(ok|partial)` marker is stateful — `_partial` if bootstrap
# was missing/unreadable — so it is never false "complete" evidence; the legacy
# markers (`size_budget_advisory_*`, `size_budget_info:`) are preserved for existing
# consumers on clean verdicts, and the machine tokens are added alongside them.
#
# Base requirement: the delta gate evaluates files changed vs a resolvable base
# (CCL_SKILL_BASE_REF, upstream, origin/main, or main — CI always exports it
# for pull requests). Uncommitted changes are always covered; a
# committed-only change with NO resolvable base is invisible by design — in that
# state an uncommitted severe file still fails closed (partial), and committed
# state is the caller's pipeline responsibility. Because that state evaluates
# nothing, it prints `entrypoint_size_blocking_unevaluated` rather than
# `entrypoint_size_blocking_ok`: a base-less run is never a pass, and a consumer
# that gates on the ok token must not be able to earn it by losing its base.
#
# Invoked by check-ccl-skills.sh (which fails the gate when this script exits
# non-zero) and exercised directly by test_check_ccl_size_budget.sh.
set -uo pipefail

root="${1:-.}"

if [[ ! -d "$root/skills" ]]; then
  echo "size_budget_advisory: no skills/ directory under $root — size check skipped (advisory, not blocking)" >&2
  echo "size_budget_advisory_partial"
  echo "entrypoint_size_budget_advisory_ok"
  exit 0
fi

ruby -e '# encoding: UTF-8
begin
root = ARGV.fetch(0)
size_state = "ok"

# --- agent-context/session-start.md every-session-injection byte tripwire band (advisory) -----
budget_raw = ENV.fetch("BOOTSTRAP_BYTE_TRIPWIRE", "").strip
if budget_raw.empty?
  budget = 13000
elsif budget_raw.match?(/\A\d+\z/)
  budget = budget_raw.to_i
else
  warn "size_budget_advisory: BOOTSTRAP_BYTE_TRIPWIRE not numeric — using 13000"
  budget = 13000
end
bootstrap = File.join(root, "agent-context/session-start.md")
if File.readable?(bootstrap) && File.file?(bootstrap)
  bb = File.size(bootstrap)
  if bb > budget
    warn "size_budget_advisory: agent-context/session-start.md is #{bb}B (> #{budget}B advisory tripwire band) — it injects into EVERY session; the band is visibility only, the blocking rule is NET GROWTH vs base (delta verdict below): before adding, consolidate an existing rule or move detail into an owner skill"
  end
else
  size_state = "partial"
  warn "size_budget_advisory: agent-context/session-start.md missing or unreadable — size check skipped (advisory, not blocking)"
end

# --- entrypoint body-char/word debt + whole-file byte severe-debt -----------
def strip_frontmatter(text)
  text.sub(/\A---\r?\n.*?\r?\n---\r?\n/m, "")
end

WORD_BUDGET_MAX = 5000
WORD_TOKEN_PATTERN = /\p{Han}|\uFFFD|(?:(?!\p{Han})[\p{L}\p{N}])+(?:[\u0027\u2019_-](?:(?!\p{Han})[\p{L}\p{N}])+)*/u

Metric = Struct.new(:body_chars, :body_words, :bytes, keyword_init: true)

def metric_for_text(text)
  raw = text.b
  text = raw.dup.force_encoding(Encoding::UTF_8).scrub { |invalid| "\uFFFD" * invalid.bytesize }
  body = strip_frontmatter(text)
  Metric.new(body_chars: body.length, body_words: body.scan(WORD_TOKEN_PATTERN).length, bytes: raw.bytesize)
end

def metric_for_file(path)
  metric_for_text(File.binread(path))
end

def debt_count(metrics)
  metrics.count { |m| m.body_chars > 5000 }
end

def severe_count(metrics)
  metrics.count { |m| m.bytes > 50000 }
end

def word_over_limit_count(metrics)
  metrics.count { |m| m.body_words > WORD_BUDGET_MAX }
end

def git_success?(*args, root:)
  system("git", "-C", root, *args, out: File::NULL, err: File::NULL)
end

def git_lines(*args, root:)
  IO.popen(["git", "-C", root, *args], err: File::NULL, &:read).lines.map(&:strip).reject(&:empty?)
end

def git_text(*args, root:)
  IO.popen(["git", "-C", root, *args], err: File::NULL, &:read)
end

def resolve_base(root)
  return [nil, "not-a-git-worktree"] unless git_success?("rev-parse", "--is-inside-work-tree", root: root)

  candidates = []
  env_base = ENV.fetch("CCL_SKILL_BASE_REF", "").strip
  candidates << [env_base, "CCL_SKILL_BASE_REF"] unless env_base.empty?
  if env_base.empty?
    upstream_ref = git_text("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", root: root).strip
    candidates << [upstream_ref, "upstream"] unless upstream_ref.empty?
    candidates << ["origin/main", "origin/main"]
    candidates << ["main", "main"]
  end

  candidates.each do |candidate, source|
    merge_base = git_text("merge-base", candidate, "HEAD", root: root).strip
    return [merge_base, source] unless merge_base.empty?
  end
  [nil, env_base.empty? ? "merge-base-unavailable" : "CCL_SKILL_BASE_REF-unavailable"]
rescue StandardError => e
  [nil, "#{e.class.name}:#{e.message.lines.first.to_s.strip}"]
end

def base_skill_metrics(root, base)
  paths = git_lines("ls-tree", "-r", "--name-only", base, "--", "skills", root: root).grep(%r{\Askills/[^/]+/SKILL\.md\z})
  metrics = {}
  paths.each do |rel|
    text = git_text("show", "#{base}:#{rel}", root: root)
    next if text.empty? && !git_success?("cat-file", "-e", "#{base}:#{rel}", root: root)
    metrics[rel] = metric_for_text(text)
  end
  metrics
end

def base_metric_for_path(root, base, rel)
  return :unknown if base.nil?
  return :missing unless git_success?("cat-file", "-e", "#{base}:#{rel}", root: root)
  metric_for_text(git_text("show", "#{base}:#{rel}", root: root))
end

def head_metric_for_path(root, rel)
  full = File.join(root, rel)
  return :missing unless File.file?(full)
  metric_for_file(full)
end

def fmt_metric_value(metric, field)
  case metric
  when :unknown then "unknown"
  when :missing then "missing"
  else metric.public_send(field).to_s
  end
end

def fmt_delta(base_metric, head_metric, field)
  return "unknown" unless base_metric.is_a?(Metric) && head_metric.is_a?(Metric)
  delta = head_metric.public_send(field) - base_metric.public_send(field)
  format("%+d", delta)
end

skill_files = Dir[File.join(root, "skills", "*", "SKILL.md")].sort
severe_lines = []
head_metrics = {}
skill_files.each do |path|
  rel = path.start_with?(root + "/") ? path[(root.length + 1)..] : path.sub(%r{\A\./}, "")
  metric = metric_for_file(path)
  head_metrics[rel] = metric
  if metric.bytes > 50000
    severe_lines << "  entrypoint_size_severe_debt: #{rel} bytes=#{metric.bytes} hard_advisory_max=50000"
  end
end
head_debt_count = debt_count(head_metrics.values)
head_severe_count = severe_count(head_metrics.values)
head_word_over_limit_count = word_over_limit_count(head_metrics.values)

base, base_source = resolve_base(root)
base_metrics = nil
if base
  begin
    base_metrics = base_skill_metrics(root, base)
  rescue StandardError => e
    warn "entrypoint_size_trend_partial: base=unknown reason=#{e.class.name} #{e.message.lines.first.to_s.strip}"
  end
else
  puts "entrypoint_size_trend_partial: base=unknown reason=#{base_source}"
end

base_debt_count = base_metrics ? debt_count(base_metrics.values) : nil
base_severe_count = base_metrics ? severe_count(base_metrics.values) : nil
base_word_over_limit_count = base_metrics ? word_over_limit_count(base_metrics.values) : nil

# --- changed skills/*/SKILL.md (diff-scoped; same detection shape the validator
#     uses elsewhere) get a STABLE per-file token at edit time ----------------
changed = []
begin
  if system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    paths = []
    paths.concat(git_lines("diff", "--name-only", base, "HEAD", "--", "skills/*/SKILL.md", root: root)) if base
    paths.concat(git_lines("diff", "--name-only", "--", "skills/*/SKILL.md", root: root))
    paths.concat(git_lines("diff", "--cached", "--name-only", "--", "skills/*/SKILL.md", root: root))
    paths.concat(git_lines("ls-files", "--others", "--exclude-standard", "--", "skills/*/SKILL.md", root: root))
    changed = paths.map { |p| p[%r{\Askills/[^/]+/SKILL\.md\z}] }.compact.uniq
  end
rescue StandardError => e
  warn "changed_entrypoint_size_scan_skipped: #{e.class.name} #{e.message.lines.first.to_s.strip}"
end
# agent-context/session-start.md gets the same changed-detection shape (committed vs base, staged,
# unstaged, untracked) for its own net-growth delta verdict below. A probe
# failure must not silently read as "unchanged" — that would false-green a real
# growth on the newly-blocking rule, so it fails closed as a partial below.
bootstrap_changed = false
bootstrap_scan_error = nil
begin
  if system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    bpaths = []
    bpaths.concat(git_lines("diff", "--name-only", base, "HEAD", "--", "agent-context/session-start.md", root: root)) if base
    bpaths.concat(git_lines("diff", "--name-only", "--", "agent-context/session-start.md", root: root))
    bpaths.concat(git_lines("diff", "--cached", "--name-only", "--", "agent-context/session-start.md", root: root))
    bpaths.concat(git_lines("ls-files", "--others", "--exclude-standard", "--", "agent-context/session-start.md", root: root))
    bootstrap_changed = bpaths.include?("agent-context/session-start.md")
  end
rescue StandardError => e
  bootstrap_scan_error = "#{e.class.name} #{e.message.lines.first.to_s.strip}"
  warn "changed_bootstrap_size_scan_skipped: #{bootstrap_scan_error}"
end
changed.sort.each do |rel|
  full = File.join(root, rel)
  head_metric = head_metric_for_path(root, rel)
  if head_metric.is_a?(Metric)
    if head_metric.body_chars > 5000
      puts "changed_entrypoint_above_recommended: #{rel} body_chars=#{head_metric.body_chars} recommended_max=5000"
    elsif head_metric.body_chars < 1000
      puts "changed_entrypoint_below_recommended: #{rel} body_chars=#{head_metric.body_chars} recommended_min=1000 verify_trigger_owner_hardstop_pointer_do_not_pad"
    end
  end
  base_metric = base_metric_for_path(root, base, rel)
  puts "changed_entrypoint_size_delta: #{rel} base_body_chars=#{fmt_metric_value(base_metric, :body_chars)} head_body_chars=#{fmt_metric_value(head_metric, :body_chars)} delta_body_chars=#{fmt_delta(base_metric, head_metric, :body_chars)} base_bytes=#{fmt_metric_value(base_metric, :bytes)} head_bytes=#{fmt_metric_value(head_metric, :bytes)} delta_bytes=#{fmt_delta(base_metric, head_metric, :bytes)}"
  puts "changed_entrypoint_word_delta: #{rel} base_body_words=#{fmt_metric_value(base_metric, :body_words)} head_body_words=#{fmt_metric_value(head_metric, :body_words)} delta_body_words=#{fmt_delta(base_metric, head_metric, :body_words)}"
end

unless severe_lines.empty?
  puts "size_budget_info: SKILL.md over 50KB (advisory — obligation-bound gate registries; collapse ONLY verified reference-duplication, never inline-only gates):"
  severe_lines.each { |l| puts l }
end

# Machine-readable debt counters (visibility/debt-management, NOT a clean-landing
# waiver and NOT authorization to keep growing entrypoints).
puts "entrypoint_size_debt_count=#{head_debt_count}"
puts "entrypoint_size_severe_debt_count=#{head_severe_count}"
puts "entrypoint_size_debt_count_base=#{base_debt_count.nil? ? "unknown" : base_debt_count}"
puts "entrypoint_size_debt_count_head=#{head_debt_count}"
puts "entrypoint_size_debt_count_delta=#{base_debt_count.nil? ? "unknown" : format("%+d", head_debt_count - base_debt_count)}"
puts "entrypoint_size_severe_debt_count_base=#{base_severe_count.nil? ? "unknown" : base_severe_count}"
puts "entrypoint_size_severe_debt_count_head=#{head_severe_count}"
puts "entrypoint_size_severe_debt_count_delta=#{base_severe_count.nil? ? "unknown" : format("%+d", head_severe_count - base_severe_count)}"
puts "entrypoint_word_budget_over_limit_count_base=#{base_word_over_limit_count.nil? ? "unknown" : base_word_over_limit_count}"
puts "entrypoint_word_budget_over_limit_count_head=#{head_word_over_limit_count}"
puts "entrypoint_word_budget_over_limit_count_delta=#{base_word_over_limit_count.nil? ? "unknown" : format("%+d", head_word_over_limit_count - base_word_over_limit_count)}"
puts "size_budget_visibility_note: counts above are visibility/debt-management only — NOT a clean-landing waiver and NOT authorization to keep growing entrypoints; a new or expanded large entrypoint must record its rationale and split plan."

# --- delta-blocking verdict ---------------------------------------------------
# Word-over-limit entrypoints follow the baseline-freeze rule described above.
# New/crossing severe entrypoints and growth of existing severe entrypoints block.
# Base unknown => the growth check is unavailable; say so (partial), never silent.
# Move map: a git-detected RENAME (R with similarity >= 90) from a severe old
# path covers its OWN new path — never a sibling file, and never when the new
# file also grew (move+growth blocks as severe growth). `changed` collapses
# renames into the new path only, so R pairs are gathered from --name-status.
move_map = {}
begin
  if system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    status_args = []
    status_args << ["diff", "--name-status", base, "HEAD"] if base
    status_args << ["diff", "--name-status", "--cached"]
    status_args << ["diff", "--name-status"]
    status_args.each do |cmd|
      git_lines(*cmd, "--", "skills/*/SKILL.md", root: root).each do |line|
        status, *paths = line.split("	")
        next unless status.start_with?("R") && paths.length >= 2
        next unless status[1..].to_i >= 90
        old_rel = paths[0][%r{\Askills/[^/]+/SKILL\.md\z}]
        new_rel = paths[1][%r{\Askills/[^/]+/SKILL\.md\z}]
        move_map[new_rel] = old_rel if old_rel && new_rel
      end
    end
  end
rescue StandardError => e
  warn "move_pair_scan_skipped: #{e.class.name}"
end

blocks = []
partials = []
word_blocks = []
word_partials = []
partials << "agent-context/session-start.md: changed-detection failed (#{bootstrap_scan_error}) — net-growth check unavailable (fail-closed)" if bootstrap_scan_error && File.file?(File.join(root, "agent-context/session-start.md"))
changed.sort.each do |rel|
  begin
    head_metric = head_metric_for_path(root, rel)
  rescue StandardError => e
    partials << "#{rel}: head metric unreadable (#{e.class.name}) — size check unavailable (fail-closed)"
    next
  end
  next if head_metric == :missing # deleted entrypoint: nothing left to size-gate
  unless head_metric.is_a?(Metric)
    partials << "#{rel}: head metric unavailable (#{head_metric}) — size check unavailable (fail-closed)"
    next
  end
  base_metric = base_metric_for_path(root, base, rel)

  if head_metric.body_words > WORD_BUDGET_MAX
    if base_metric == :unknown
      word_partials << "#{rel}: base unknown — historical word allowance unavailable (fail-closed)"
    elsif base_metric == :missing || base_metric.body_words <= WORD_BUDGET_MAX
      source_rel = move_map[rel]
      source_metric = source_rel ? base_metric_for_path(root, base, source_rel) : nil
      if source_metric.is_a?(Metric) && source_metric.body_words > WORD_BUDGET_MAX
        if head_metric.body_words <= source_metric.body_words
          puts "entrypoint_word_budget_move_ok: #{rel} head_body_words=#{head_metric.body_words} allowed_body_words=#{source_metric.body_words} moved_from=#{source_rel}"
        else
          word_blocks << "#{rel}: base_body_words=#{source_metric.body_words} head_body_words=#{head_metric.body_words} allowed_body_words=#{source_metric.body_words} moved_from=#{source_rel} — moved historical over-limit entrypoint grew; keep it level, shrink it, or move detail into references/"
        end
      else
        word_blocks << "#{rel}: base_body_words=#{fmt_metric_value(base_metric, :body_words)} head_body_words=#{head_metric.body_words} allowed_body_words=#{WORD_BUDGET_MAX} — new or within-limit entrypoint exceeds the uniform body-word budget; move detail into references/"
      end
    elsif head_metric.body_words > base_metric.body_words
      word_blocks << "#{rel}: base_body_words=#{base_metric.body_words} head_body_words=#{head_metric.body_words} allowed_body_words=#{base_metric.body_words} — historical over-limit entrypoint grew; keep it level, shrink it, or move detail into references/"
    else
      puts "entrypoint_word_budget_legacy_ok: #{rel} base_body_words=#{base_metric.body_words} head_body_words=#{head_metric.body_words} allowed_body_words=#{base_metric.body_words}"
    end
  end

  if head_metric.bytes > 50000
    if base_metric == :unknown
      partials << "#{rel}: base unknown — severe-growth check unavailable (fail-closed)"
    elsif base_metric == :missing || base_metric.bytes <= 50000
      source_rel = move_map[rel]
      source_metric = source_rel ? base_metric_for_path(root, base, source_rel) : nil
      if source_metric.is_a?(Metric) && source_metric.bytes > 50000 && head_metric.bytes <= source_metric.bytes
        puts "entrypoint_size_move_ok: #{rel} bytes=#{head_metric.bytes} — moved from #{source_rel} without growing"
      else
        blocks << "#{rel}: new severe entrypoint bytes=#{head_metric.bytes} (> 50000) — split into references before landing"
      end
    elsif head_metric.bytes > base_metric.bytes
      blocks << "#{rel}: severe entrypoint grew base_bytes=#{base_metric.bytes} head_bytes=#{head_metric.bytes} — consolidate an existing rule or move detail into references/ (there is no exempt marker or waiver flag); a rule set must not grow monotonically"
    end
  end
end

# agent-context/session-start.md net-growth verdict: the always-on layer is permanently severe —
# ANY net growth blocks; shrink and same-size edits stay landable. Only a
# CHANGED agent-context/session-start.md is evaluated (an untouched over-band file must not
# hard-red unrelated MRs; the advisory band already reports that debt).
if bootstrap_changed
  b_head = begin
    head_metric_for_path(root, "agent-context/session-start.md")
  rescue StandardError => e
    partials << "agent-context/session-start.md: head metric unreadable (#{e.class.name}) — size check unavailable (fail-closed)"
    :unreadable
  end
  if b_head.is_a?(Metric)
    # The baseline is the SAME path at base, and nothing else. There is
    # deliberately no way to nominate a different file as the yardstick: any such
    # mechanism is a way for the candidate to choose its own budget. Relocating
    # the always-on layer therefore reads as a new every-session injection and
    # blocks — that is intended, not a gap. A relocation is a rare, deliberate,
    # human-reviewed event; letting it through automatically costs more than it
    # saves, and two rounds of independent review plus adversarial challenge
    # broke every automatic recogniser tried here: git rename pairing (similarity
    # is not identity, so an unrelated blob can be imported as the baseline), and
    # parsing the BOOTSTRAP assignment out of the hook (export, eval, and
    # same-line overrides defeat any regex; shell is not safely readable by one).
    # NOTE: no apostrophes in this block — the whole program is a single-quoted
    # shell string, so one would terminate it and break the script.
    b_base = base_metric_for_path(root, base, "agent-context/session-start.md")
    puts "changed_bootstrap_size_delta: agent-context/session-start.md base_bytes=#{fmt_metric_value(b_base, :bytes)} head_bytes=#{fmt_metric_value(b_head, :bytes)} delta_bytes=#{fmt_delta(b_base, b_head, :bytes)}"
    if b_base == :unknown
      partials << "agent-context/session-start.md: base unknown — every-session-injection growth check unavailable (fail-closed)"
    elsif b_base == :missing
      blocks << "agent-context/session-start.md: new every-session-injection file bytes=#{b_head.bytes} — it injects into EVERY session; record its rationale and keep it minimal (there is no exempt marker or waiver flag)"
    elsif b_head.bytes > b_base.bytes
      blocks << "agent-context/session-start.md grew base_bytes=#{b_base.bytes} head_bytes=#{b_head.bytes} — it injects into EVERY session; net growth must be offset by equal compression (consolidate an existing rule or move detail into an owner skill; there is no exempt marker or waiver flag)"
    else
      puts "bootstrap_size_delta_ok: agent-context/session-start.md base_bytes=#{b_base.bytes} head_bytes=#{b_head.bytes} — no net growth"
    end
  end
  # :missing (deleted) => nothing left to size-gate, same as a deleted entrypoint
end

# Advisory markers only when the blocking verdict is clean — a consumer reading
# the preserved legacy token must never see ok next to a block.
#
# With no resolvable base the delta gate cannot see committed-only changes at all
# (`changed` then holds only uncommitted/untracked paths, whose severe members
# already fail closed above). A clean tree in that state therefore reaches here
# having evaluated NOTHING, so it must not claim `entrypoint_size_blocking_ok`:
# a consumer grepping for that token would read an un-run gate as a pass. The
# exit code stays 0 — this script is also run outside a git worktree and on
# checkouts without an upstream, and reddening those states is a caller-side
# pipeline decision (CI always exports CCL_SKILL_BASE_REF)
# — but the token says un-evaluated, not ok.
# NOTE: this comment lives inside the single-quoted `ruby -e` program; an
# apostrophe here terminates the shell quote and breaks the script.
if blocks.empty? && partials.empty? && word_blocks.empty? && word_partials.empty?
  puts "size_budget_advisory_#{size_state}"
  puts "entrypoint_size_budget_advisory_ok"
  if base.nil?
    puts "entrypoint_size_blocking_unevaluated: base=unknown — committed changes were NOT delta-checked; this is not a pass"
    puts "entrypoint_word_budget_blocking_unevaluated: base=unknown — committed changes were NOT delta-checked; this is not a pass"
    if File.file?(File.join(root, "agent-context/session-start.md"))
      puts "bootstrap_size_delta_unevaluated: base=unknown — agent-context/session-start.md committed changes were NOT delta-checked; this is not a pass"
    end
  else
    puts "entrypoint_size_blocking_ok"
    puts "entrypoint_word_budget_blocking_ok"
  end
  exit 0
end
blocks.each { |b| warn "entrypoint_size_block: #{b}" }
partials.each { |b| warn "entrypoint_size_block_partial: #{b}" }
word_blocks.each { |b| warn "entrypoint_word_budget_block: #{b}" }
word_partials.each { |b| warn "entrypoint_word_budget_block_partial: #{b}" }
puts "entrypoint_word_budget_blocking_failed" unless word_blocks.empty? && word_partials.empty?
# Legacy aggregate token for every blocking verdict owned by this size-budget
# script, including the body-word rule. Keep it unconditional so existing
# consumers cannot miss a new word-only failure.
puts "entrypoint_size_blocking_failed"
exit 1
rescue StandardError, ScriptError => e
  warn "entrypoint_size_gate_error: #{e.class.name}: #{e.message.lines.first.to_s.strip}"
  exit 3
end
' "$root"

# Verdict contract: 0 = clean, 1 = delta-block/partial (gate fails as blocking),
# 2+/127 = the gate could not run (infra failure, reported separately).
rc=$?
exit "$rc"
