#!/usr/bin/env ruby
# frozen_string_literal: true

# F4 Tier-1 static routing analyzer (deterministic, no LLM).
#
# Parses every skills/*/SKILL.md FRONTMATTER `description` (never the body — the
# `->`/`→` arrow also appears in prose) and flags routing-surface defects:
#
#   BLOCKING (objective, deterministic):
#     - dangling redirect: a backticked `skill-ref` redirect target that is not an installed skill
#     - exact trigger collision: an identical normalized trigger claimed by >=2 skills with
#       no mutual skip/redirect disambiguation between them
#
#   ADVISORY (fuzzy / not ground truth — never blocks):
#     - fuzzy collision: one skill's full trigger is a substring of another skill's trigger
#     - asymmetric redirect: A redirects to B but B neither redirects back nor shares the trigger
#     - prose redirect target: a Skip redirect that names an "owner"/"reviewer" but resolves
#       to no backticked installed skill (an unresolvable prose dead-end an agent can't route)
#
# Usage:
#   eval-routing.rb <repo-root> [--json <path>] [--quiet]
# Exit: 0 = no blocking findings; 1 = blocking findings; 2 = usage/parse error.

require "yaml"
require "json"
require "set"

root = ARGV[0]
if root.nil? || root.empty?
  warn "usage: eval-routing.rb <repo-root> [--json <path>] [--quiet]"
  exit 2
end
json_path = nil
if (i = ARGV.index("--json"))
  json_path = ARGV[i + 1]
  if json_path.nil? || json_path.start_with?("-")
    warn "usage: --json requires a following path"
    exit 2
  end
end
quiet = ARGV.include?("--quiet")

skill_files = Dir[File.join(root, "skills", "*", "SKILL.md")].sort
if skill_files.empty?
  warn "eval_routing_no_skills: no skills/*/SKILL.md under #{root}"
  exit 2
end

installed = skill_files.map { |p| File.basename(File.dirname(p)) }.to_set

# --- parse each skill's routing surface -------------------------------------
# claims[skill]   => [{trigger:, norm:, kind: use|proactive}]
# redirects[skill]=> [{target:, backticked:, in_skip:}]
claims = Hash.new { |h, k| h[k] = [] }
redirects = Hash.new { |h, k| h[k] = [] }
parse_errors = []
prose_findings = []

skill_files.each do |path|
  name = File.basename(File.dirname(path))
  text = File.read(path)
  m = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
  unless m
    parse_errors << "#{name}: no YAML frontmatter"
    next
  end
  begin
    fm = YAML.safe_load(m[1])
  rescue StandardError => e
    parse_errors << "#{name}: #{e.message}"
    next
  end
  desc = fm.is_a?(Hash) ? fm["description"].to_s : ""
  next if desc.strip.empty?

  # Section the description: claim triggers come from the "Use when" and
  # "Proactively invoke" segments; redirects come from the "Skip" segment.
  # The Skip boundary is anchored to a SENTENCE-INITIAL capitalized "Skip" label
  # so a trigger phrase like "skip tests" mid-sentence does not split the section.
  skip_m = desc.match(/(?:\A|[.;。\n])[ \t]*(Skip\b.*)\z/m)
  skip_seg = skip_m ? skip_m[1] : ""
  pre_skip = skip_m ? desc[0...skip_m.begin(1)] : desc
  use_seg = pre_skip[/use\s+when(.*?)(?=proactively\s+invoke|\z)/im, 1].to_s
  proactive_seg = pre_skip[/proactively\s+invoke(.*)\z/im, 1].to_s

  [[use_seg, "use"], [proactive_seg, "proactive"]].each do |seg, kind|
    seg.scan(/"([^"]+)"/).flatten.each do |q|
      norm = q.strip.downcase
      next if norm.empty?
      claims[name] << { trigger: q.strip, norm: norm, kind: kind }
    end
  end

  # Redirect targets: a skill token immediately after an arrow, backticked or bare.
  # Bare targets that are not installed skills are treated as generic English
  # ("-> stack skill") and ignored; only a backticked unknown is a dangling defect.
  # Allow leading whitespace and any opening bracket/quote (ASCII + fullwidth +
  # CJK) after the arrow, e.g. "→ (`missing-skill`)" / "→ ［`x`］" / "→ 「x」".
  skip_seg.scan(/(?:->|→)[\s(（［【「『\[{"']*(`?)([a-z][a-z0-9-]+)\1/).each do |bt, target|
    backticked = bt == "`"
    redirects[name] << { target: target, backticked: backticked, in_skip: true }
  end

  # Prose redirect target (ADVISORY): a Skip redirect whose target clause names a
  # routing "owner"/"reviewer" but contains NO backticked installed skill — an
  # unresolvable prose dead-end an agent cannot deterministically route to
  # (e.g. "→ the adversarial or delete-code review owner"). Clause runs from the
  # arrow to the next arrow / sentence terminator (the tempered `(?!->|→)` stops
  # the clause at the next arrow so a later backticked skill in a CHAINED redirect
  # cannot suppress an earlier prose dead-end). Never blocks.
  skip_seg.scan(/(?:->|→)((?:(?!->|→)[^\n;。.])*)/).each do |clause,|
    clause = clause.to_s
    next unless clause.match?(/\bowner\b|\breviewer\b/i)
    has_installed = clause.scan(/`([a-z][a-z0-9-]+)`/).flatten.any? { |t| installed.include?(t) }
    next if has_installed
    prose_findings << {
      type: "prose_redirect_target",
      detail: "#{name} skip redirect \"→#{clause.strip}\" names an owner/reviewer but no resolvable `skill-name`"
    }
  end
end

# --- build trigger index ----------------------------------------------------
# norm_trigger => {skill => [original phrases]}
index = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
claims.each do |skill, list|
  list.each { |c| index[c[:norm]][skill] << c[:trigger] }
end

def redirects_between?(redirects, from, to)
  # read-only: must not insert a default [] for a missing key (we iterate `redirects`)
  list = redirects.key?(from) ? redirects[from] : []
  list.any? { |r| r[:target] == to }
end

blocking = []
advisory = []

# Dangling redirect (BLOCKING): backticked skill-ref that is not installed.
redirects.each do |skill, list|
  list.each do |r|
    next unless r[:backticked]
    target = r[:target]
    next if target == skill
    next if installed.include?(target)
    blocking << {
      type: "dangling_redirect",
      skill: skill,
      detail: "Skip redirect to `#{target}` but no such installed skill"
    }
  end
end

# Exact trigger collision (BLOCKING unless EVERY claiming pair is disambiguated).
# Pairwise: a pair (a,b) is disambiguated iff a redirects to b or b redirects to a.
# One unrelated redirect must not clear a 3+ collision while a pair stays ambiguous.
index.each do |norm, by_skill|
  skills = by_skill.keys.sort
  next if skills.length < 2
  undisambiguated = skills.combination(2).reject do |a, b|
    redirects_between?(redirects, a, b) || redirects_between?(redirects, b, a)
  end
  if undisambiguated.empty?
    advisory << {
      type: "exact_trigger_collision_disambiguated",
      trigger: norm,
      skills: skills,
      detail: "trigger #{norm.inspect} claimed by #{skills.join(', ')} (all pairs disambiguated)"
    }
  else
    blocking << {
      type: "exact_trigger_collision",
      trigger: norm,
      skills: skills,
      detail: "trigger #{norm.inspect} claimed by #{skills.join(', ')}; " \
              "undisambiguated pair(s): #{undisambiguated.map { |a, b| "#{a}~#{b}" }.join(', ')}"
    }
  end
end

# Fuzzy collision (ADVISORY): one full trigger is a substring of another skill's trigger.
norms = index.keys
norms.each do |a|
  next if a.length < 4 # too short to be meaningful
  norms.each do |b|
    next if a == b
    next unless b.include?(a)
    a_skills = index[a].keys
    b_skills = index[b].keys
    cross = b_skills - a_skills
    next if cross.empty?
    advisory << {
      type: "fuzzy_collision",
      detail: "trigger #{a.inspect} (#{a_skills.sort.join(',')}) is a substring of #{b.inspect} (#{b_skills.sort.join(',')})"
    }
  end
end

# Possible dangling (ADVISORY): a BARE (un-backticked) redirect target that looks
# like a skill name (kebab with a hyphen) but is not installed — likely a renamed
# or removed skill referenced without backticks. Single-word bare targets are
# treated as generic English ("-> stack skill") and ignored. (One-way A->B
# redirects are NOT flagged: hub->leaf routing is correct, not a defect.)
redirects.each do |skill, list|
  list.uniq { |r| r[:target] }.each do |r|
    target = r[:target]
    next if r[:backticked]            # backticked unknowns are BLOCKING above
    next unless target.include?("-")  # hyphen => looks like a skill ref, not English
    next if installed.include?(target)
    advisory << {
      type: "possible_dangling",
      detail: "#{skill} bare redirect to #{target} (hyphenated, not installed — renamed/removed skill?)"
    }
  end
end

advisory.concat(prose_findings)
advisory.uniq!

report = {
  root: root,
  skills_scanned: installed.size,
  parse_errors: parse_errors,
  blocking: blocking,
  advisory: advisory
}
File.write(json_path, JSON.pretty_generate(report)) if json_path

unless quiet
  puts "eval-routing: scanned #{installed.size} skills"
  unless parse_errors.empty?
    puts "  parse errors:"
    parse_errors.each { |e| puts "    - #{e}" }
  end
  if blocking.empty?
    puts "  blocking: none"
  else
    puts "  BLOCKING (#{blocking.size}):"
    blocking.each { |f| puts "    - [#{f[:type]}] #{f[:detail]}" }
  end
  puts "  advisory (#{advisory.size}):"
  advisory.first(50).each { |f| puts "    - [#{f[:type]}] #{f[:detail]}" }
  puts "    … #{advisory.size - 50} more" if advisory.size > 50
end

# Parse failures (bad/absent frontmatter) are a usage/parse error per the contract.
exit 2 unless parse_errors.empty?
exit(blocking.empty? ? 0 : 1)
