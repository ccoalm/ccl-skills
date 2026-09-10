# Owner-generalization map — 125

| Owner | Direction | Status | Diff or reason |
| --- | --- | --- | --- |
| `tighten-doc` | subject | updated | `skills/tighten-doc/SKILL.md` (closeout trigger + register drift), `skills/tighten-doc/references/closeout-reread.md` (new detail reference) |
| `skill-extraction-workflow` | upstream ledger owner | updated | `references/source-register.md` impact-chain rows (one per pinned rule, plus one for the guard's own test), and `scripts/test_register_firing_path_resolution.sh` — two cases covering the mutation classes this round's rows rely on |
| `requirement-doc-writer` | sibling | unchanged | Owns PRD substance assembly only; wording and finalization stay with `tighten-doc`, which this round changed |
| `release-doc-writer` | sibling | unchanged | Same split for release documents: substance there, wording here |
| `test-artifact-management` | sibling | unchanged | Owns test-case documents' structure and Bitable lifecycle, not editing register |
| `testing-strategy` | test-layer owner | updated | Two executable cases added to the guard's suite: one RED (anchored rule deleted) with its GREEN control, one asserting the declared non-detection. Assertion count guard raised 57 → 59 so a skipped case still fails closed |
| `terminal-cli-dev` | shell surface | updated | The added shell reuses the file's existing helpers and idioms; no new command, flag, or output contract, and every fixture write stays inside the per-test temp directory |
| `product-rd-workflow` | upstream lifecycle | unchanged | Its share/publish gate only requires that `tighten-doc` ran; refining that skill's internal trigger needs no coordinating change |
| `multi-perspective-research` | sibling | not-applicable | Owns research-brief status output, no document-editing surface |
| `code-review` | review owner | routed | Dual-track review and challenge run through the extraction review gate; receipts land in this round's `evidence/` |

Lifecycle stages with no output: release and observability. Testing DOES have
output this round — the two cases above — which an earlier revision of this map
wrongly denied; implementation output is limited to that test file, since the
document rules themselves ship as prose.
