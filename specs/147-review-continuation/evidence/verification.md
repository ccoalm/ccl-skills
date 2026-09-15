# Review continuation verification

Implementation candidate: `b14c3ffd9974694996414dca2850998714b4850c`.

## Independent passes

| Pass | Candidate | Result |
| --- | --- | --- |
| Review | `e74ed4d2c3a828c64c682c1dc66688a7a158b319` | One P2; readiness assertions added |
| Challenge | `1a8a33661835ae237c9c6a384de08cfe7a361801` | One P1 and three P2; dispositions below |
| Delta review | `b14c3ffd9974694996414dca2850998714b4850c`, against the challenge candidate | Passed; no findings |

The first two local commits were consolidated before publication to keep one
source-register round. The challenged tree remained byte-identical
(`238a3e4c88841aa0a4266af6a5e7eaf1621ae55e`). The only subsequent implementation
delta points the register locator at the numbered normative rule instead of its
heading. The last pass covers that delta. Controller envelopes are recorded
beside this file; each pass used the extraction lane at release depth with the
shared-gate risk tag.

### Finding dispositions

- Review P2, readiness coverage: fixed. The regression now checks both the
  completion missing-pass/P0/P1 rule and extraction's unreviewed-delta rule.
- Challenge P1, unlimited no-progress loops: source-refuted. The checkpoint's
  progress requirement applies to every later pass, independently of whether a
  tracked chain exists. Its second step requires different evidence or method
  before another call; its final paragraph requires reusing valid review and
  finishing. The extraction lane also forbids repeating a pass merely to reach
  zero findings. A cosmetic change establishes neither necessity nor new
  evidence. A numeric task-wide ceiling or new budget ledger would change the
  intended continuation policy. These are instruction contracts, not a claim
  of mechanical enforcement against an agent that ignores them.
- Challenge P2, another unreviewed-candidate assertion: source-refuted.
  Completion steps 1–3 already invalidate review after any candidate change and
  require renewed review. The checkpoint's tested missing-conclusive-pass rule
  preserves that obligation. Deleting the redundant clause in step 4 does not
  permit an unreviewed candidate to become ready.
- Challenge P2, unavailable mutation-probe evidence: resolved by the direct
  resolver probe below. The existing 59-assertion suite covers the mechanism;
  the additional probe checks this exact configured historical row.
- Challenge P2, publication before checks finish: retained as a release
  prerequisite, not a code defect. A version bump does not publish. The existing
  tag-driven workflow runs package tests and exact-artifact verification before
  publishing; the tag is held until required checks are conclusive.

## Deterministic evidence

- `test_extraction_review_gate.sh`: the new policy assertions failed against
  the former policy, then passed after correction; the final readiness
  assertions also passed.
- `test_register_firing_path_resolution.sh`: passed, 59 assertions.
- Direct resolver probe on a disposable archive of `e74ed4d`: the exact row
  passed (exit 0); a modified row, duplicate row and missing row each failed
  (exit 1). The resolver configuration and historical row are unchanged in the
  implementation candidate.
- `impact-chain-gate.rb`: passed after the register locator was bound to the
  normative numbered rule and the local ledger round was consolidated.
- `check-ccl-skills.sh`: passed with `r0_status=private-ok` on the implementation
  candidate. The real private alias audit ran; no audit stub was used.
- Public sanitization, Markdown links, spec references and whitespace checks
  passed.

Final local verification covers the implementation candidate and its
non-executable evidence records through
`5ccda2a3a512036946ac5393dba9d02415c99001`:

| Command or lane | Result |
| --- | --- |
| `make test-repo-gates` | Passed after environment and locator repairs |
| `make test-regressions-fast` recipe in the aggregate run | Passed; 43 suites |
| `make test-code-review-1` recipe in the aggregate run | Passed; 9 suites |
| `make -j3 test-code-review-2 test-code-review-abort-leak` | Passed; 8 suites and both abort-leak legs for primary and fallback |
| `test_register_firing_path_wiring.sh` | Passed; 21 assertions |
| `make npm-publish-dry` | Passed; 356 package tests, 11 pack tests, no skips |
| Rebuild plus `npm run test:pack` with `EXPECT_SOURCE_COMMIT` and `REQUIRE_CLEAN_RELEASE=1` | Passed; exact tarball bound to the commit above |
| `TGZ_PATH=<verified artifact> bash scripts/host-smoke.sh` | Passed; actual artifact CLI and real Codex, Claude and OpenCode lifecycle checks |

The original `make -j3 test` aggregate exited nonzero before the repairs.
Its passing fast lane and first review shard were retained; the failed
repository lane and not-yet-run review recipes were then completed separately.
Together these cover every `make test` recipe; no successful aggregate exit is
claimed. The separate heavy regression lane is required in CI. Current pipeline
and release state are tracked by the pull request and tag workflow.

The direct resolver probe extracts `git archive <candidate>` into a disposable
directory, finds the unique row containing the retired five-pass locator, and
runs the candidate's `register-firing-path-resolution.rb` against four copies:
original; original row plus ` changed`; original plus a second identical row;
original with that row removed. Each exit code is asserted as listed above.

## Test environment and claim boundary

Initial test attempts exposed environment failures: the minimal environment
omitted UTF-8 locale and `HOME`, the sandbox denied process inspection and npm
cache writes, and `/private/tmp` did not satisfy a macOS alias fixture's expected
temporary-path shape. Corrected runs preserve the normal `HOME`, use UTF-8 and
`/tmp`, and give npm a dedicated writable cache. Failed and interrupted attempts
are not passes. The committed-register check additionally required a normative
rule locator and a single consistent ledger round.

The evidence proves policy consistency, regression controls and package
integrity. It does not measure future agents' task-completion rate or reduction
in manual intervention. Explicit authority limits and required review remain.

## Document readback

Read back the entire completion reference, the extraction entrypoint obligation,
delta-review section, quickstart step, source-register rows and plan. The
continuation decision has one canonical owner; extraction retains its separate
single-shot mechanics. No decision loss, terminology drift or duplicated
task-wide ceiling remained. No document-family rewrite or UI change applies.
