# Review sequence continuation — `continuation_basis=existing-task-scope`

The round's receipt sequence continued past its first bounded sequence. This file is the
caller-owned record that continuation requires. It names no receipt hash on purpose: every
non-JSON file here is part of the reviewed candidate, so it has to be final before the
rounds run, and a hash it quoted would be one the rounds could not yet have produced.

- **Basis**: `existing-task-scope`. The authorized task is landing this round — the two
  registered deferrals named in the register row — and an authorized task includes its
  necessary fixes, tests and review by default. A sequence limit is a checkpoint, not a
  new permission request; nothing here broadens the task's scope or authority.
- **Why the first sequence could not close it.** Adding a required self-review concern is a
  repository-wide compatibility event: five suites carried review-plan fixtures that
  omitted the new concern. Only the complete lane finds them, because the suite runner
  aborts at its first failing target and never reaches the later shards, so four of the
  five surfaced after the first sequence had already closed. Their fix touches the
  `code-review` owner package, which moves the candidate and voids every receipt bound to
  the previous one; a succession cannot itself be succeeded, so the remaining work needed a
  fresh bounded sequence rather than another succession.
- **Why a further sequence was owed after that one.** The merge-side binding excludes only
  added JSON carrying a `candidate_sha256`. The base attestations and this record are not
  that, so committing them moved the candidate out from under the receipts that had just
  been minted. They are committed first now, and the sequence that binds the landing
  candidate runs against a tree that already contains them.
- **Changed method**, both defects being ordering defects of the same shape — verify and
  freeze everything the candidate will carry, then open the chain:
  1. the complete lane (`make test` **and** the heavy-only regressions) is run to green on
     the exact candidate **before** a chain opens, not after; and
  2. every non-JSON evidence file the round will ship — base attestations, this record — is
     committed **before** the first round, never after.
- **Cumulative rounds retained.** Every receipt this round produced is in this directory,
  including the closed sequences: `chain1-round1-review.json` (findings: one P2, fixed),
  `chain1-round2-challenge.json` (passed), `chain2-succession-challenge.json` (passed), and
  the superseded continuation attempt in `chain3-*.json`. `closeout.json` binds the final
  sequence — `round1-review.json`, `round2-challenge.json`, `complete.json` — to the
  landing candidate.
- **Disposition of the one finding raised**: `fixed`. The first review found that the
  entrypoint had delegated the cumulative lane-budget numbers to a reference with nothing
  pinning them there. Three contract anchors now pin them; an applied deletion mutation on
  one turns the anchor gate red with the unmutated control green.
- **Transport note**: one challenge was first returned infrastructure-inconclusive with
  every lane failing (quota, timeout, and an unparseable reply). The retry used the same
  candidate, plan, scope and focus with the wrapper's maximum timeouts; that is transport
  remediation inside the wrapper's budget, not an extra review round.
