# 012 — Derive `--challenge-index` instead of defaulting it to an always-illegal value

## Artifact classification

`gate implementation` (per `product-rd-workflow/references/shared-gate-artifact-classification.md`).

The stop *rules* are unchanged: every existing validation still runs, and every
explicitly-supplied value is checked exactly as before. What changes is the
failure semantics of one input shape — a challenge invocation that omits
`--challenge-index` currently always fails, and will instead resolve to the only
value that invocation could legally carry. That is shared-gate semantics, so this
plan exists before any edit.

Risk tags (`feature-risk-router`): `shared-gate`, `api-contract` (the flag
contract and the exit code a caller observes both change for one input shape).
`security-review`: change-triggered arm is `not-applicable` — `security posture
unchanged`. Ruling out each blocker: no trust boundary, untrusted-input surface,
sensitive sink, secret handling, or data-visibility change; the round ceiling
stays owned by `--challenge-budget`; the tracked-chain cross-check
`autonomous_review_index == challenge_index + 1` still binds; no
authority/authorization semantics are touched.
`visible surface: no` — the gate renders no product UI.

## Defect

`build_parser` gives `--challenge-index` `default=0`, but challenge mode requires
`1 <= challenge_index <= challenge_budget`. Zero is therefore never legal in the
mode the flag exists for, so a challenge invocation that does not pass the flag
explicitly fails before any provider runs:

```
$ review_gate.py --mode challenge --cwd <repo> --base HEAD \
    --implementer-family claude --focus probe --challenge-budget 1
{"status": "inconclusive", "reason_code": "invalid_input",
 "reason": "--challenge-index must be within the challenge budget"}   # exit 2
```

The same invocation with `--challenge-index 1` succeeds. The failure is
indistinguishable at a glance from a real reviewer-lane failure, which is what
makes it expensive: `docs/reviewer-lane-bootstrap-hijack.md` recorded it as a
real defect and left it open, and every caller since has had to pass the flag by
hand.

## Why a default is derivable rather than guessed

In both challenge shapes the legal value is already fully determined, so nothing
is being invented:

- **Untracked challenge** — `review_gate.py` rejects any index other than 1 with
  `review_chain_required` ("later challenges require --review-chain-id and the
  complete --prior-review-result-file chain"). The only legal value is 1.
- **Tracked challenge** — the chain requires
  `autonomous_review_index == challenge_index + 1`, and
  `--autonomous-review-index` is mandatory for a tracked chain. The only legal
  value is `autonomous_review_index - 1`.
- **Non-challenge modes** — the index must be 0, and remains 0.

A derived value that lands out of range still fails the existing range check, so
a tracked challenge declared as Agent round 1 continues to be rejected.

## Scope

In scope: resolve `--challenge-index` at the parser boundary when the caller did
not supply it — inside the gate's own `ArgumentParser` subclass, so what leaves
the parser always carries an int for every caller, not only for `main` — leaving
every downstream use site and every validation untouched.

Out of scope: the validations themselves, the challenge budget ceiling, the
chain-contiguity rules, and any change to what an explicitly-supplied value
means. An explicit `--challenge-index 0` in challenge mode must keep failing.

## Acceptance matrix

Named inputs to one verdict. Every row gets an executed trace by closeout.

| mode | `--challenge-index` | `--review-chain-id` | `--autonomous-review-index` | verdict |
| --- | --- | --- | --- | --- |
| challenge | omitted | absent | absent | resolves to 1; runs (previously `invalid_input`) |
| challenge | omitted | present | 2 | resolves to 1; runs |
| challenge | omitted | present | 3 | resolves to 2; runs |
| challenge | omitted | present | 1 | `invalid_input` — derived 0 is out of range |
| challenge | `1` | absent | absent | runs (unchanged) |
| challenge | `0` | absent | absent | `invalid_input` (unchanged — explicit value still validated) |
| challenge | `2` (budget 2) | absent | absent | `review_chain_required` (unchanged) — with budget 1 the range check fires first and the verdict is `invalid_input` |
| review | omitted | any | any | index 0; runs (unchanged) |
| review | `1` | any | any | `invalid_input` — only valid in challenge mode (unchanged) |
| review | `0` | any | any | the index guard does not fire (unchanged) — it reads `challenge_index != 0`, so it rejects a *nonzero* index outside challenge mode, and an explicit 0 was indistinguishable from an omitted flag before this change. Verified by reading that condition and by running the invocation against both the pre-change and post-change gate: neither rejected it on the index. Tightening it into a rejection is now possible, but is a new restriction and deliberately out of scope |
| complete | omitted | absent | absent | index 0; runs (unchanged) |

## Test / register coverage

Owner: `testing-strategy`. Layer: the existing deterministic gate suite
`skills/code-review/scripts/test_review_gate.sh` (stub wrappers, no live
reviewer). Each acceptance row above becomes a case there.

RED before implementation is already recorded: the reproduction above was run
against the unmodified gate and produced `invalid_input`.

Executed traces at closeout — suite green at 149 ok / 0 FAIL, and three applied
mutations in disposable copies, each restored and byte-compared against pristine:

| mutation | what it breaks | result |
| --- | --- | --- |
| restore `default=0` | the derivation itself | 3 FAIL, all omitted-flag rows; every explicit-value row stays green, so the mutation did not simply break the suite |
| non-challenge resolution returns 1 | the index-0 guarantee outside challenge mode | flips both non-challenge rows, review and complete, since the unchanged `mode != "challenge" && challenge_index != 0` guard then rejects each; 74 total FAIL, because that default is load-bearing across the suite — the evidence here is the owning flip, not containment. The explicit-`0` row stays green, which is correct: an explicitly supplied value never reaches the resolver |
| tracked range check accepts 0 | the rejection of a chain declared as Agent round 1 | kills only that row, 1 total FAIL |

The first mutation leaves two rows green on purpose: they guard the opposite
direction (a future change that defaults to 1 everywhere, or that stops rejecting
a derived 0), which is what the second and third mutations exercise.

## Status-sync target

`docs/reviewer-lane-bootstrap-hijack.md` records this defect as open
("尚未修复，单独立项"). That line is the status source and is updated in the same
slice once the fix lands.

## Review / challenge gate

`shared-gate` requires both lanes before shared-branch push or MR merge:
independent review and adversarial challenge via `code-review`'s
`review_gate.sh`, with the implementer family declared so a same-family reviewer
is excluded. Local passing gate output is required evidence but does not
discharge review of the rule/scope/failure semantics.

Verifier discovery (repo agent contract + Makefile + CI): `check-ccl-skills.sh`,
`check-agent-contract-coverage.sh --enforce`, `check-public-sanitization.py`,
`check-markdown-links.py`, `make test`, `git diff --check`. All are authoritative
and all run before the slice is claimed complete.
