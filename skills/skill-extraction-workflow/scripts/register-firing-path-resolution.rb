#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

#
# Register firing-path RESOLUTION gate: every `firing-path:` locator recorded in
# `references/source-register.md` must still resolve, for the WHOLE ledger — not
# only for rows added in the current diff.
#
# Why this exists as a separate gate from impact-chain-gate.rb: that gate is
# diff-scoped by design (it adjudicates whether an ADDED row earns its landing),
# so a historical row is validated exactly once, at the commit that wrote it.
# Nothing re-checks it afterwards. The ledger is append-only while the prose it
# anchors into is living text, so any later edit that MOVES or REWORDS an
# anchored sentence silently voids that row's firing evidence: the row keeps
# asserting a mechanical firing path that no longer exists, and every gate stays
# green because no gate looks. Observed shape: an entrypoint-slimming change
# relocated an anchored rule out of a `SKILL.md` into a reference and reworded it
# in the same commit; the full checker passed, and the break was found only by a
# human reading the register by hand.
#
# Contract: exits 1 and names every unresolved locator; exits 0 when all resolve.
# Invoked by check-ccl-skills.sh with the target repo root as ARGV[0].
#
# Locator forms accepted (mirroring the impact-chain gate's vocabulary):
#   command:<repo-relative path>          -> must exist and be executable
#   file:<repo-relative path>#<anchor>    -> file must exist and carry the anchor
#
# An anchor resolves EITHER as literal text in the file (the convention the
# impact-chain gate enforces on added rows) OR as a GitHub-style heading slug
# naming a real heading. The slug form is accepted because the ledger is
# append-only: a historical row that spelled its anchor as `#some-heading-slug`
# cannot be rewritten to the literal form, and the section it names genuinely
# exists, so failing it would be a false red with no legal repair.
#
# One declaration may carry several comma-separated locators; each is resolved
# independently. The split is on a comma that INTRODUCES another locator
# (`,` followed by `file:`/`command:`), never on every comma: literal anchors are
# natural-language rule text and three in this ledger already contain a comma
# ("...before landing it, not after challenge rounds"). Splitting naively would
# validate only the fragment before the comma, so deleting the rest of the
# anchored sentence would still pass — a false negative in exactly the direction
# this gate exists to close.

root = ARGV.fetch(0) { abort "usage: register-firing-path-resolution.rb <repo-root>" }

REGISTER = "skills/skill-extraction-workflow/references/source-register.md"

register_path = File.join(root, REGISTER)
unless File.file?(register_path)
  warn "register_firing_path_gate_failed: #{REGISTER} not found under #{root}"
  exit 1
end

# Waivers are intentionally empty in the distributed repository. A repository
# that adopts an append-only register may add reviewed, row-bound waivers here.
EXEMPT = {}.freeze

# `\p{Word}` rather than `[a-z0-9]`: GitHub keeps non-ASCII characters in a slug,
# and most headings in this repository are Chinese. Stripping them would collapse
# a CJK heading to an empty slug and permanently false-red a locator that names
# it — unrepairable, because the ledger row cannot be edited.
def slugify(heading)
  heading.downcase.gsub(/[^[[:word:]]\s-]/, "").strip.gsub(/\s+/, "-")
end

# Fenced blocks are examples, not operative text. Both the anchor search and the
# heading scan run against the stripped body: a rule that was deleted but still
# appears inside a code sample is NOT a living carrier, and a `## Heading` inside
# a fence is not a real heading. Fence matching follows CommonMark — a fence
# closes only on a run of the SAME character at least as long as the opener — so
# a shorter inner run cannot terminate a longer outer fence.
def strip_fences(body)
  out = []
  opener = nil
  body.each_line do |line|
    if (m = line.match(/\A\s{0,3}(`{3,}|~{3,})/))
      run = m[1]
      if opener.nil?
        opener = run
        next
      elsif run[0] == opener[0] && run.length >= opener.length
        opener = nil
        next
      end
    end
    out << line if opener.nil?
  end
  out.join
end

# GitHub's own duplicate-heading disambiguation: the first `## Setup` is `setup`,
# the second `setup-1`, the third `setup-2`. Reproduced exactly rather than by
# stripping a trailing `-N`, because stripping accepts `#setup-99` when no such
# anchor exists — trading a false positive for a false negative in a gate whose
# whole job is detecting dead anchors.
def heading_slugs(body)
  seen = Hash.new(0)
  body.scan(/^\#+\s+(.+?)\s*$/).flatten.map do |h|
    base = slugify(h)
    n = seen[base]
    seen[base] += 1
    n.zero? ? base : "#{base}-#{n}"
  end
end

# Repo-relative containment. A locator that escapes the repository would resolve
# against content this gate does not govern, so a dead in-repo anchor could be
# "satisfied" from outside. Rejects absolute paths, `..` traversal, and symlinked
# targets that land outside the root.
# Split deliberately in two so a MISSING target reports "not found" rather than
# a misleading containment error: the two failures need different fixes.
def syntactically_contained?(rel)
  !rel.start_with?("/") && !rel.split("/").include?("..")
end

def resolves_inside?(root, rel)
  real_root = File.realpath(root)
  real = File.realpath(File.join(root, rel))
  real == real_root || real.start_with?(real_root + File::SEPARATOR)
rescue Errno::ENOENT, Errno::ELOOP, Errno::ENAMETOOLONG
  false
end

unresolved = []
malformed = []
locator_count = 0
# Where each EXEMPT locator was actually cited. A waiver is written for ONE
# historical row that can no longer be repaired; a second row quoting the same
# retired locator is a new claim, not that row, and must not inherit the waiver.
# Counting uses is what makes that decidable without a row identity — the ledger
# is append-only and its line numbers shift, so nothing else is stable.
exempt_uses = {}
EXEMPT_USE_ALLOWANCE = 1
EXEMPT_ROW_DIGESTS = {}.freeze
# TRUST BOUNDARY. The count answers "one row"; it cannot answer "WHICH row", so
# it is paired with the digest of the citing row in EXEMPT_ROW_DIGESTS below.
# An earlier version of this comment argued the opposite — that no stable
# identity exists because any candidate drifts or must be regenerated by the
# author it constrains. That was wrong for a digest specifically: the ledger is
# append-only, so rows added elsewhere do not change this line, and the failure
# this defends against is an accidental reflow or a repurposed row, which reds
# without anyone touching code.
# What it does NOT defend against is an author who edits EXEMPT and its digest
# together — a visible code change under normal review, the same posture the two
# legacy anchorless entries have carried since they landed.
fence = nil

File.foreach(register_path).with_index(1) do |line, lineno|
  # Same CommonMark rule as strip_fences: a naive boolean toggle would close a
  # ```` fence on an inner ``` run and then treat the REAL closing run as an
  # opener, silently skipping every live row after it.
  if (m = line.match(/\A\s{0,3}(`{3,}|~{3,})/))
    run = m[1]
    if fence.nil?
      fence = run
      next
    elsif run[0] == fence[0] && run.length >= fence.length
      fence = nil
      next
    end
  end
  # Only table rows carry declarations; fenced examples and narrative prose do
  # not, and treating a documentation example as a live locator would be an
  # unrepairable false positive.
  next unless fence.nil?
  next unless line.start_with?("|")

  # `(?<!`)` skips an inline-code mention such as `` `firing-path:` `` — that is
  # prose ABOUT the key (this file's own methodology rows do it), not a
  # declaration, and must not be demanded to yield a locator.
  line.scan(/(?<!`)firing-path:\s*([^|;]*)/) do |(value)|
    locators = value.split(/,(?=\s*(?:file|command):)/)
                    .map(&:strip)
                    .select { |l| l.start_with?("file:", "command:") }

    # A declaration that parses to nothing is not "clean" — it is a row whose
    # firing evidence this gate silently failed to check.
    if locators.empty?
      malformed << [lineno, value.strip]
      next
    end

    locators.each do |locator|
      locator_count += 1
      anchor_waived = EXEMPT.key?(locator)
      if anchor_waived
        exempt_uses[locator] ||= []
        exempt_uses[locator] << lineno
      end

      kind, _, rest = locator.partition(":")
      if kind == "command"
        rel = rest.strip
        target = File.join(root, rel)
        if !syntactically_contained?(rel)
          unresolved << [lineno, locator, "path escapes the repository"]
        elsif !File.file?(target)
          unresolved << [lineno, locator, "executable not found"]
        elsif !resolves_inside?(root, rel)
          unresolved << [lineno, locator, "path escapes the repository"]
        elsif !File.executable?(target)
          unresolved << [lineno, locator, "not executable"]
        end
      else
        rel, _, anchor = rest.partition("#")
        rel = rel.strip
        anchor = anchor.strip
        if anchor.empty? && !anchor_waived
          unresolved << [lineno, locator, "file locator carries no #anchor"]
          next
        end
        target = File.join(root, rel)
        if !syntactically_contained?(rel)
          unresolved << [lineno, locator, "path escapes the repository"]
          next
        end
        if !File.file?(target)
          unresolved << [lineno, locator, "file not found"]
          next
        end
        if !resolves_inside?(root, rel)
          unresolved << [lineno, locator, "path escapes the repository"]
          next
        end

        next if anchor.empty? # exempt legacy locator: existence checked above
        # An EXEMPT entry that names the anchor waives the anchor-CONTENT check
        # as well: the rule was deliberately relocated, so the recorded text
        # will never sit at this path again and the append-only row cannot be
        # repaired. File existence (checked above) still applies, so deleting or
        # renaming the target still reds, and the use-count check below stops a
        # NEW row from inheriting the waiver by quoting the retired locator.
        next if anchor_waived

        body = strip_fences(File.read(target))
        next if body.include?(anchor)
        next if heading_slugs(body).include?(anchor.downcase)

        unresolved << [lineno, locator, "anchor text absent from target"]
      end
    end
  end
end

# Over-use of a waiver is a violation, reported against the EXTRA citations only
# (the first use is the historical row the waiver was written for). Reporting
# every use would red the legitimate row and leave no repair path in an
# append-only ledger.
# Over-use of a waiver is a violation, reported against the EXTRA rows only
# (the first row is the historical one the waiver was written for). Reporting
# every use would red the legitimate row and leave no repair path in an
# append-only ledger. Distinct ROWS, not raw citations: one row that happens to
# name the same retired locator twice is still that one unrepairable row, and
# counting citations would false-red it.
register_lines = File.readlines(register_path)
# The digest table is INJECTED, not self-calibrated. An earlier version enabled
# the layer only once some recorded row still matched, so that a synthetic
# fixture ledger would not red — but that made "rewrite every waived row at
# once" disable the whole layer, which is precisely the case it should catch.
# Production takes the built-in table and enforces it unconditionally; a test or
# a repository vendoring this gate supplies its own table (an empty one means it
# binds no waivers). Injection is a declared seam, visible in the environment and
# never set in CI, rather than an inference the gate makes about which ledger it
# is looking at.
digest_table_path = ENV["REGISTER_FIRING_PATH_EXEMPT_DIGESTS"].to_s
exempt_row_digests =
  if digest_table_path.empty?
    EXEMPT_ROW_DIGESTS
  else
    begin
      parsed = JSON.parse(File.read(digest_table_path))
      raise TypeError, "not an object" unless parsed.is_a?(Hash)
      parsed
    rescue StandardError => e
      warn "register_firing_path_exempt_digest_table_unreadable: #{digest_table_path}: #{e.message}"
      exit 2
    end
  end
# The seam is usable but never silent: an injected table can only ever be weaker
# than the built-in one for this ledger, so a run that used it is not a clean
# landing — including the case where a test environment leaks into a real run.
# The caller keys off this line and downgrades to interim; without it the seam
# would be a quiet bypass of the digest and missing-row layers.
unless digest_table_path.empty?
  puts "register_firing_path_exempt_digests_injected: #{digest_table_path} " \
       "(built-in waiver-row bindings not enforced; this run is interim, not clean-landing)"
end
# Iterate the EXPECTED entries, not only the ones still cited: a waived row that
# was DELETED leaves its locator out of `exempt_uses` entirely, so a loop over
# observed uses would never look at it and the run would report success while a
# recorded historical row silently vanished. Only meaningful once the digest
# layer is calibrated to this ledger; on a foreign register every entry is
# legitimately uncited.
exempt_row_digests.each_key do |locator|
  next unless (exempt_uses[locator] || []).empty?
  unresolved << [1, locator,
                 "EXEMPT entry has no citing row in the ledger; the waived historical row was deleted " \
                 "or its locator was edited, so the waiver now covers nothing — restore the row, or " \
                 "retire the EXEMPT entry and its digest in the same change"]
end

exempt_uses.each do |locator, linenos|
  rows = linenos.uniq.sort
  if rows.length > EXEMPT_USE_ALLOWANCE
    rows.drop(EXEMPT_USE_ALLOWANCE).each do |lineno|
      unresolved << [lineno, locator,
                     "EXEMPT locator cited by #{rows.length} rows (allowance #{EXEMPT_USE_ALLOWANCE}); " \
                     "a waiver covers the one unrepairable historical row at line #{rows.first}, " \
                     "not a new row quoting the same retired locator"]
    end
    next
  end
  # The count says "one row"; the digest says WHICH row. Without it, deleting the
  # historical row and writing a different claim that cites the same locator keeps
  # the count at 1 and silently inherits the waiver.
  expected = exempt_row_digests[locator]
  unless expected
    # A waiver with no recorded row identity keeps only the use-count layer,
    # which cannot tell a rewritten or repurposed row from the one that was
    # waived. On the BUILT-IN table that is a silent downgrade, so a new EXEMPT
    # entry added without its digest fails here rather than quietly landing
    # weaker than its siblings. An INJECTED table is the injector's declaration
    # about its own ledger — the missing binding is the point, and that run is
    # already downgraded to interim by the announcement above.
    if digest_table_path.empty?
      unresolved << [rows.first, locator,
                     "EXEMPT entry has no recorded citing-row digest; every waiver must bind the row it " \
                     "covers — add the row's SHA-256 to EXEMPT_ROW_DIGESTS in the same change"]
    end
    next
  end
  lineno = rows.first
  actual = Digest::SHA256.hexdigest(register_lines[lineno - 1].to_s.rstrip)
  next if actual == expected
  unresolved << [lineno, locator,
                 "EXEMPT citing row does not match the waived row (digest #{actual[0, 12]} != #{expected[0, 12]}); " \
                 "a waiver covers one specific unrepairable historical row, so a rewritten or replaced row " \
                 "does not inherit it — restore the row, or land a new waiver entry with its own digest and reason"]
end

# Both groups print before exiting. Bailing out on `malformed` alone would hide
# every unresolved locator and every EXEMPT over-use in the same run, so a fixer
# would have to rerun the gate once per class to discover them.
unless malformed.empty?
  warn "register_firing_path_malformed: a firing-path declaration parsed to zero locators"
  warn "  cause: the value is not `file:<repo-relative path>#<anchor>` or `command:<repo-relative path>`."
  warn "         An anchor containing `;` or `|` is truncated by the cell grammar — reword it."
  malformed.each { |lineno, value| warn "  #{REGISTER}:#{lineno}: #{value.inspect}" }
end

unless unresolved.empty?
  warn "register_firing_path_unresolved: a recorded firing path no longer resolves"
  warn "  cause: the anchored rule was moved, reworded, or deleted after its row landed,"
  warn "         so that row now asserts firing evidence that does not exist."
  warn "  fix: restore the anchored text at its recorded location, or (when the move was"
  warn "       intended) append a superseding row and add the old locator to EXEMPT with a reason."
  unresolved.each do |lineno, locator, why|
    warn "  #{REGISTER}:#{lineno}: #{why}: #{locator}"
  end
end

exit 1 unless malformed.empty? && unresolved.empty?

# NO zero-locator self-check here, deliberately. Two rounds of it each shipped a
# false RED: as a caller-side non-zero floor it red a legitimately
# declaration-free register, and as a marker count here it red a register whose
# only declaration-looking row was a fenced example — because any oracle cheap
# enough to be independent of the row/cell parser is also too cheap to tell a
# live declaration from an illustration of one, and any oracle that CAN tell
# them apart has re-implemented the parser it was meant to check.
# The threat it chased is "the parser stopped recognizing the ledger", which is
# a code defect in this file, caught by the resolution suite's own RED cases
# (an anchor mutation must turn the gate red) rather than by the gate grading
# its own eyesight at runtime.

puts "register_firing_path_resolution_ok (#{locator_count} locators resolved)"
