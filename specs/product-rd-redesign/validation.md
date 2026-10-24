# Validation

Candidate: branch `feat/product-rd-redesign`, base fd3e8b8 for the implementation diff.

## RED baseline

| Check | Base result |
| --- | --- |
| Size ratchet in `test_ai_coding_implementation_gates.sh` | fails on the 75,741-byte base entrypoint: "over the 32768-byte ratchet" |
| `register-firing-path-resolution.rb` | after the rewrite and before the exemption, `source-register.md:598` fails: anchor text absent from target |
| specs/065 `obligation-ledger.py render` | after the rewrite and before rebinding, `CARRIER_COMPOSITE_NOT_UNIQUE` on `product-rd-workflow/SKILL.md#1` |

## GREEN

| Check | Result |
| --- | --- |
| `check-ccl-skills.sh` | `ccl_skill_check_interim_ok` (R0 pending maintainer audit; the private alias audit is not configured on this host) |
| `test_ai_coding_implementation_gates.sh`, `test_pinned_phrase_mutation_walk.sh`, `test_routing_pointer_integrity.sh` | ok |
| `test_register_firing_path_resolution.sh`, `test_register_firing_path_wiring.sh` | ok (59 and 21 assertions) |
| `hooks/test_proposed_next.py`, `test_skill_loading.py`, `test_task_entry.py` | OK |
| `obligation-ledger.py render`, `test_obligation_ledger_repo_audit.sh` | `render_ok ... unresolved=0`; audit ok. 40 carriers rehosted by exact text, eight dispositions changed from merged/subsumed to `rehosted`, one composite carrier digest recomputed; untouched rows keep their original bytes |
| `check-markdown-links.py`, `check-public-sanitization.py` | ok |
| `make test-regressions-fast` | all suites ok except `test_check_ccl_skill_catalog.sh`, which fails the same way on unmodified `main` on this host |

## Review (`evidence/impl-review-p1.json`, `evidence/impl-review-p2.json`)

The diff is over the 200 KB packet cap with the obligation mapping, so it ran as two partitions: P1 the entrypoint with the design and the hook readers, P2 the references, the register rows, the exemption and the ratchet.

| Finding | Disposition |
| --- | --- |
| P1 Stage-Entry State Checklist trigger lost | Applied: the stage-boundary sentence is back under Hard gates. |
| P1 completeness trigger narrowed (exemption claims, load before implementation) | Applied: the line covers exemption claims and loads before implementation. |
| P1 user-visible notices destination missing | Source-refuted: the text moved verbatim to `design-routing-and-readiness.md:45`, outside the P1 partition. |
| P1 spec sync no longer names contract layers or directory-local rules | Applied: the line names the active contract layers before implementation, includes directory-local rules, and loads the reference. |
| P1 G4 makes every shared-gate change require a technical design | Applied: shared gates are a separate bullet with their own classification, review and `interim` rule. |
| P1 standalone non-PRD artifacts lost their direct return | Applied: the routing row keeps the exception. |
| P1 DX trigger broadened to any developer surface | Applied: the original qualifier is restored. |
| P1, P2 evidence gaps (no test results; old text, hooks or digest logic outside the partition) | Disposed by the GREEN table above: the exemption is bound to the row digest of line 598, and the resolution suite covers digest matching. |
