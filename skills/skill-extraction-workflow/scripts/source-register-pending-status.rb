#!/usr/bin/env ruby
# frozen_string_literal: true

# Reports whether the current diff adds a pending/interim source-register row.
# stdout is exactly 0 or 1; diagnostics go to stderr. The full checker consumes
# this result when choosing its final clean/interim token.

root = ARGV.fetch(0)
base = ENV["CCL_SKILL_BASE_REF"].to_s.strip
if base.empty?
  upstream_ref = IO.popen(["git", "-C", root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", err: File::NULL], &:read).strip
  base = upstream_ref.empty? ? "origin/main" : upstream_ref
end
merge_base = IO.popen(["git", "-C", root, "merge-base", base, "HEAD"], &:read).strip

# The impact-chain gate owns the missing-merge-base failure. This helper stays
# neutral so it cannot independently upgrade or downgrade the final token.
if merge_base.empty?
  puts "0"
  exit 0
end

diff = IO.popen(["git", "-C", root, "diff", merge_base, "HEAD", "--", "skills/skill-extraction-workflow/references/source-register.md"], &:read)
hits = []
diff.lines.each do |line|
  next unless line.start_with?("+")

  body = line.sub(/\A\+/, "").strip
  next unless body.start_with?("|") && body.end_with?("|")

  inner = body[1..-2].to_s
  esc_bs = "\u0001"
  esc_pipe = "\u0002"
  cells = inner.gsub("\\\\", esc_bs).gsub("\\|", esc_pipe).split("|", -1).map do |cell|
    cell.gsub(esc_pipe, "|").gsub(esc_bs, "\\\\").strip
  end
  nonterminal = lambda do |cell|
    status = cell.delete("`").strip.downcase
    status == "pending" || status == "interim"
  end
  if cells.length == 5
    next unless nonterminal.call(cells[3])
  else
    next unless cells.any? { |cell| nonterminal.call(cell) }
  end
  hits << body
end

if hits.empty?
  puts "0"
else
  warn "register_nonterminal_status_added: the changed source-register diff adds #{hits.length} row(s) with a `pending`/`interim` status; a pending/interim ledger row blocks a clean-landing/complete claim, so this run is forced to interim (NOT clean-landing)"
  hits.each { |hit| warn "  row: #{hit}" }
  puts "1"
end
