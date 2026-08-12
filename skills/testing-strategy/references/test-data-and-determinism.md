# Test Data And Determinism

Use this when tests need realistic data or must be repeatable run to run.

## Test Data Strategy

- Build data with named factories or builders that default to valid and override per scenario.
- Derive test data from intent, such as "expired token" or "over limit", not from production identifiers.
- If production-shaped data is required, anonymize structurally: replace identifiers, redact PII/secrets, preserve shape and edge distribution.
- Keep one canonical minimal fixture per scenario; do not grow a shared mega-fixture.
- Commit only data that is safe, readable, and needed for the assertion.

## Determinism Controls

Make these injectable, pinned, or normalized in tests:

- Clock/time: use a fake or fixed clock; avoid wall-clock `now()` assertions.
- Randomness: seed RNG or assert on invariants when output is sampled.
- IDs/UUIDs: inject a generator or assert shape instead of exact value.
- Ordering: sort or compare as sets when order is not contractual.
- Locale, timezone, currency, and number/date formatting: pin explicitly.
- Concurrency: use synchronization, deterministic schedulers, channels, latches, or condition polling instead of sleeps.
- Network, DNS, and filesystem: isolate by default; keep them out of fast tests unless the behavior itself is the boundary.
- Generated integrity manifests verified by regenerate-and-diff (a committed `sha256` list, a lockfile-like sorted artifact, a content-digest drift gate): the **generating sort must be byte-stable, not locale-collated** — use `LC_ALL=C sort` (and a fixed field/key order) so the manifest written by `gen` on the author's machine matches the `verify` regeneration on a differently-localed CI runner. A locale-dependent sort makes the gate false-positive ("DRIFT") on identical content across machines. This is the artifact-generation analogue of pinning `TZ`/`LANG` for test runs: pin the collation wherever a sort feeds a comparison or an integrity check, not only in fixtures.

## Property-Based And Fuzz Testing

- Use property-based tests for parsers, serializers, encoders, normalizers, math, and round-trip invariants.
- Use fuzzing for untrusted input boundaries such as public payloads, protocol decoders, and file parsers.
- Pin or record the seed and persist a failing case as a named regression fixture.
- Property tests complement named scenario tests; they do not replace high-risk examples.
- **Per-stack mature library baseline**: Python → **Hypothesis** (`hypothesis.readthedocs.io`, strategy-based generators, automatic shrinking, stateful via `RuleBasedStateMachine`); JavaScript/TypeScript → **fast-check** (`fast-check.dev`, integrates with Vitest/Jest/Mocha/`node:test`); Java/Kotlin → **jqwik** (`jqwik.net`); Go → built-in `testing.F` fuzz target (Go 1.18+ stdlib, coverage-guided, persists failing inputs to `testdata/fuzz/<name>/`); Rust → **proptest** + cargo-fuzz. **Decision rule for "when to actually reach for it"**: the cost of a property-based test is teaching the team to read shrunk counterexamples and to write generators that explore the input space; the value is finding edge cases the example-based suite missed. Pull in property-based when: (a) the function under test has an algebraic invariant (round-trip `decode(encode(x)) == x`, idempotence `f(f(x)) == f(x)`, commutativity, associativity, ordering preservation); (b) the input space is large and bug history shows edge cases the team keeps re-discovering by hand; (c) the function is high-risk (parser / encoder / auth / billing / quota math). Skip property-based when the function is straight-line business logic with few branches and named examples already cover the contract — the maintenance overhead doesn't pay back. **High-risk domains override the skip default**: for auth (token validation, signature verification, scope resolution), billing / money / quota math, parsers / serializers / encoders / decoders, and any function where wrong output silently corrupts downstream state, default to writing a property-based test alongside named examples — the team cannot enumerate every edge case the input grammar admits, and these are precisely the domains where the bug the team didn't think of becomes the production incident. Treat "named examples cover" as a self-audit prompt ("can I write down the equivalence classes I think I covered?") not as a license to skip. Per-stack implementation lives in the owning stack-dev skill; this skill owns the use-or-don't-use decision and the algebraic-invariant trigger.

## Avoid

- Time, locale, or timezone-dependent assertions without pinning.
- Tests that pass only on first run, in one timezone, or in serial order.
- Snapshotting nondeterministic output without normalization.
- Raw production dumps, secrets, or private user data.
