# 123 — The reviewed candidate and the reviewer's packet are two objects

## Artifact classification

`gate design` + `gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`), owner
`code-review`. The changed artifact decides which receipts the merge-side
landing binder can accept, so this plan exists before the edits and the round
carries its own review ledger.

Risk tags (`feature-risk-router`): `shared-gate`, `security-review`,
`release-ops`.

`security-review`: **triggered**. Today the reviewer-saw-it property is enforced
by an equality that this change replaces with a containment check. A wrong
containment check would let content land under a receipt whose reviewer never
read it, which is the exact false negative the landing binder exists to prevent,
so the invariant is stated and tested rather than assumed.

`visible surface: no` — a controller flag contract and the hashes it records.

## The defect

`review_gate.py` records two fields and gives them one value:

```python
"packet_sha256": packet_hash,
"candidate_sha256": packet_hash,
```

One byte hash serves two jobs whose requirements are opposed:

| | reviewer input (packet) | merge-side proof (candidate) |
| --- | --- | --- |
| must be | the diff plus whatever context makes the judgment possible, within `MAX_PACKET_BYTES` | exactly the base-derived landing diff, nothing more |
| changes when | context is added | any bound byte changes |

Because they are one object, three consequences follow, and all three were paid
for in delivery time rather than derived on paper:

1. **Widening a packet makes it unbindable.** `code-review/SKILL.md` tells an
   author that a finding of insufficient input "is an input defect, not a
   candidate defect: widen the packet and rerun that lane rather than editing
   the candidate to satisfy it", and `freeze_packet` refuses `--diff-file`
   together with `--base`/`--paths`. So the widened rerun produces a receipt
   whose `candidate_sha256` is the widened packet's hash, and
   `review_ledger_binding.py` — which recomputes the candidate from the
   repository diff — can never match it. Following the contract produces
   evidence the merge side rejects. Round 122 lost a whole chain to this: five
   findings on its first chain were all of the "the code this claim depends on
   is not in the packet" class.
2. **Owner selection and the wording-only changed-file check read the packet**
   rather than the candidate, so they cannot survive a widened packet either.
3. Nothing in the repository says a round therefore needs two review passes over
   two different packets, because nobody wrote down a requirement that only
   exists as a side effect of the aliasing.

## The change

Split the object. `--diff-file` may be combined with `--base`/`--paths`; when it
is:

- **subject** = the base-derived diff over the bound paths, computed exactly as
  the no-`--diff-file` path already computes it, and exactly as the landing
  binder recomputes it. `candidate_sha256` = `sha256(subject)`.
- **packet** = the bytes of `--diff-file`, which the reviewer reads.
  `packet_sha256` = `sha256(packet)`.
- `candidate_paths` derive from the **subject**, not from the packet, so owner
  selection and the wording-only `changed_files` comparison stay bound to what
  lands.

### The invariant that replaces equality

**The subject must appear in the packet as a verbatim contiguous byte
substring.** Nothing weaker: no diff parsing, no per-hunk reconciliation, no
normalization. `SKILL.md` already states the authoring discipline this enforces
— "added context sits on top of the candidate diff and never in place of part of
it" — which today is true for free because the two are the same bytes, and after
this change is checked.

Consequences, stated rather than discovered later:

- An author who **appends** context passes. An author who **interleaves** context
  between the candidate's own hunks fails, and the error says to append instead.
  That is a real restriction on packet composition and it is the price of a
  mechanical check with no false accepts.
- A packet that drops any part of the candidate fails, which is the property the
  gate exists for.

### What is and is not loosened

Per the dual-track gate's loosening check, the exempted class must be named:

- **No class stops owing evidence.** Every receipt that is valid today stays
  valid, byte for byte: with no `--diff-file`, subject and packet are the same
  bytes and both hashes keep their current value. `--diff-file` alone keeps its
  current meaning too, including that its receipt does not bind a landing.
- The accept set widens by exactly one shape: a receipt whose packet provably
  contains the whole landing candidate verbatim. Relative to today, that shape
  could not exist at all; relative to the property the binder protects — nothing
  merges that a reviewer did not see — it is strictly stronger than what a
  narrow packet proves, because the reviewer saw the candidate **and** the
  context needed to judge it.
- **`--diff-file` stays incompatible with `--wording-only-proof-file`.** The
  wording-only proof is a machine check over a full-context base-derived diff and
  has no meaning over an author-assembled packet. Refusing the combination keeps
  that proof's input exactly what it is today.
- The landing binder is **not touched** by this round.

## Acceptance matrix

One independently-failable behavior per row.

| # | Behavior | Observable check |
| --- | --- | --- |
| A1 | `--diff-file` with `--base` is accepted | gate runs; no `--diff-file cannot be combined` error |
| A2 | The receipt's `candidate_sha256` equals the base-derived candidate | receipt hash == `review_ledger_binding.py --print-candidate` for the same base/paths |
| A3 | The receipt's `packet_sha256` is the widened packet's hash | receipt hash == `sha256` of the `--diff-file` bytes, and differs from A2 |
| A4 | A packet not containing the subject verbatim is refused | gate exits non-zero with a containment error naming the failure |
| A5 | A packet that drops part of the candidate is refused | same, on a packet built by deleting one hunk |
| A6 | Interleaved context is refused, appended context is accepted | paired fixtures, one red one green |
| A7 | Without `--diff-file`, both hashes keep today's value | existing receipts and suites unchanged |
| A8 | `--diff-file` alone keeps today's meaning | `candidate_sha256` == packet hash, as now |
| A9 | `--diff-file` with `--wording-only-proof-file` is refused | explicit error |
| A10 | `candidate_paths` derive from the subject | owner selection and `changed_files` match the base-derived file set, not the packet's |

## Verification plan

- **RED baseline (required, applied not hypothesized).** For each protected
  predicate — the containment check (A4/A5/A6), the subject-derived
  `candidate_sha256` (A2), the subject-derived `candidate_paths` (A10), and the
  wording-only refusal (A9) — remove or invert that predicate alone and observe
  the suite turn red **for the right reason**: the owning assertion fails in the
  mutant and passes in the unmutated control, with no non-owning assertion
  failing.
- The five existing landing-binder suites and the review-gate suites pass
  unchanged, which is the evidence for A7/A8.
- `make test`, then `--heavy-only` separately, then the repository gates
  (`check-ccl-skills.sh`, routing analyzer, sanitization).
- Round-level: this round's own review chain binds a candidate the landing
  binder reproduces.

## Release

npm `0.16.0`, bumped in the three sites `check-release-version.py` binds
(`packages/ccl-skills-npm/package.json` and both places the lockfile records it).
Minor rather than patch: the controller's flag contract gains an accepted
combination and the meaning of a recorded field changes for that combination.
The release floor is `max(0.15.4 highest tag, 0.15.5 declared on the merge
target)`, so `0.16.0` clears it. `0.15.5` is prepared on `main` but was never
tagged or published; it ships inside this release rather than as its own.

## Non-goals

- **Charter item 3** — that a late honest wording correction invalidates a whole
  chain exactly as a behavior change does — is a different axis and is out of
  scope by the user's decision. Containment does not address it: correcting a
  sentence still moves the base-derived subject.
- The landing binder's default of binding every tracked path is unchanged.
- No change to `MAX_PACKET_BYTES`, to the partition manifest, or to the egress
  secret scan, all of which keep operating on the packet.
