# Vendored Contract Drift Checklist

Use this table before reporting a vendored external contract or conformance drift gate result.

**Scope (what counts as an external contract/conformance artifact):** API/schema/protobuf/wire-format definitions, envelope/rule catalogs, validators, or conformance fixtures vendored from an upstream source. Exclude routine dependency lockfile or digest-pin checks only when they do not vendor that content; ambiguous vendored upstream artifacts default to in-scope.

## Procedure

1. Enumerate scope from authoritative committed catalog, local hash/digest manifest, CI config, build/provisioning scripts, and pinned tracked-file lists; lockfiles are enumeration input only after an external contract/conformance artifact is already in scope, never a standalone trigger. A local hash/digest manifest is enough to enumerate enrolled files for a self-contained local-drift layout, but it cannot prove omitted artifacts do not exist unless paired with an exhaustive root scan whose extra/missing set is empty. If authoritative non-manifest sources prove no contract/conformance artifact and no upstream marker, mark the gate `inapplicable` with evidence pointers. Heuristic or bounded artifact-like searches may find extra candidates but never prove absence. If a catalog/pin/source marker exists but cannot be resolved, mark it `inconclusive/non-pass`.
2. Fill an applicability ledger in the format `row | status | evidence pointer`; every row below must be `pass`, `inconclusive`, `fail`, or `inapplicable` with evidence (`fail` records a defective gate, e.g. a RED mutation that does not trigger the expected failure). An omitted applicable row is non-pass.
3. Aggregate only from the ledger: emit an explicit `pass`, `non-pass`, or `inapplicable` verdict first; scope labels are qualifiers, never standalone results. A row may be green only when its clean pass and required RED failure evidence are both recorded. When a vendored copy exists, `local verify` and `root enumeration` must be green, while `local verify scope` must be green or inapplicable with evidence that no sibling/source path is referenced; every other applicable row must also be green. `Inconclusive` is not green; one passing row is never the overall result. An aggregate with no applicable rows is non-pass unless Step 1 proved top-level inapplicability from authoritative absence evidence. If upstream rows are inapplicable, the aggregate must include both `local-drift only` and `upstream freshness unverified`. If upstream rows are applicable but inconclusive, the aggregate must say `upstream authenticity inconclusive` and the gate is non-pass. An unlabeled or comprehensive green is non-pass.
4. For a self-contained local-drift verify with no upstream pin, no wrapper, and no semantic layer, use a short ledger: scope, local `verify`, local `verify` scope, root enumeration, semantic layer, recipe integrity, wrapper identity, sync/setup boundary, and RED cleanup. Mark upstream compare and pin authority inapplicable by construction with evidence. The sync/setup boundary is NOT inapplicable by construction — it still applies to every verify/review run (assert the run did not fetch/install/exec-beyond-the-canonical-script/delete); only its *separate sync gate* sub-part is inapplicable when no sync gate ran.

## Row guidance

- local `verify`: clean pass plus RED mutation failure;
- local `verify` scope: if the recipe references a sibling/source path, run `verify` with that path deliberately absent and record that it still passes on the vendored copy; if it fails because the source path is missing, mark this row non-pass and route as a fail-closed gate defect, not drift. If no sibling/source path is referenced, mark this sub-check inapplicable with evidence. A pass proves local copy-vs-manifest drift only, not upstream authenticity;
- root enumeration: derive candidate roots from an authoritative committed catalog, local hash/digest manifest, or pinned upstream tracked-file list; record included, excluded, missing, extra, and outside artifact-like path dispositions. A local manifest proves enrolled-file consistency only; if it is the only source, corroborate completeness from an independent committed catalog or pinned tracked-file list, OR from an exhaustive root scan whose extra/missing set is empty; otherwise mark completeness inconclusive/non-pass;
- semantic layer: inspect artifacts under confirmed contract roots or catalog membership; record valid+invalid evidence for semantic artifacts, or per-artifact no-semantic notes that cite the artifact format/parser checked and why no schema/semantics apply;
- upstream compare, when an actionable committed upstream pin exists: provision the pinned upstream ref/tag, never a copied local tree; prove clean pass, RED vendored-copy mutation failure, RED changed-upstream-ref failure, and RED compare-set membership failure;
- pin authority, when an actionable committed upstream pin exists: use a signed upstream tag, upstream-hosted protected ref that the consumer cannot write, or a distinct-owner second source; otherwise mark upstream authenticity inconclusive;
- recipe integrity: first determine from authoritative committed metadata whether a distinct canonical producer exists; if producer existence is unresolved, mark this row inconclusive/non-pass. When a distinct canonical producer exists, cite already-committed or out-of-band producer provenance proving `LC_ALL=C` byte-stable ordering, self-containment, and exit semantics; do not fetch during verify/review to establish it. `Local recipe only` may pass only when authoritative metadata explicitly states no external canonical producer exists, plus local `LC_ALL=C` byte-stable ordering, self-containment, exit semantics, digest clean pass, and RED script mutation failure; label the row `pass (local-recipe-only)` and do not claim cross-consumer recipe provenance. If provenance needs a fetch, route it through the separate sync gate;
- wrapper integrity: prove the resolved verify entrypoint from traced invocation, resolved-command evidence, or static review evidence showing a single committed entrypoint with no CI/build wrapper indirection, then compare that entrypoint digest to the vendored canonical script digest. If entrypoint identity is unproven, mark this row inconclusive/non-pass. If the invoked entrypoint differs, treat a wrapper as present; prove wrapper digest clean+RED, prove it is network-free, exec-free (beyond invoking the canonical script), delete-free, and install-free, and prove it does not override canonical locale, `PATH`, `IFS`, shell options, or exit handling. Any fetch/toolchain bootstrap must route through the separate sync gate, never the verify-invoked wrapper;
- sync/setup boundary (always applies to a verify/review run; only the separate-sync-gate sub-part is inapplicable when no sync gate ran): this verify/review procedure never authorizes fetch, install, toolchain exec, or deletes — assert that the run did none of these even on the local-only path. `verify`, recipe, and wrapper rows stay network-free, exec-free except for invoking the canonical script, and delete-free. A separate sync gate requires explicit human authorization for that run and must carry its own allowlist, out-of-band digest/signature, distinct-owner/protected provenance, no-unexpected-files check, and clean+RED evidence outside this verify checklist.
- Cross-language conformance/parity fixtures: every language's suite loads the ONE shared external single-source fixture set (the vendored/pinned artifact), never per-language inline literals — a language's own literal can silently encode the very drift the suite exists to catch (a stale test using the wrong value as its own example passes against itself). The runner fails closed on fixture-schema mismatch in BOTH directions: unknown/extra key = untested upstream addition, missing key = silent coverage loss; neither is skipped or defaulted.
- RED cleanup: confirm the audited working tree is clean before any RED step, perform RED mutations only in a disposable copy or scratch checkout, then confirm both scratch cleanup and audited working tree cleanliness before recording the aggregate result.

## Ledger

Aggregate rule: every result starts with `pass`, `non-pass`, or `inapplicable`; scope labels are qualifiers only. Green requires the local-drift row to be applicable+green and every other applicable row to be green. Any applicable `inconclusive`, `fail`, or non-pass row makes the overall gate non-pass. Zero applicable rows is non-pass unless Step 1 proved top-level inapplicability from authoritative absence evidence; then report the gate as `inapplicable`. If upstream compare and pin authority are inapplicable, the result must include `local-drift only; upstream freshness unverified`. If upstream rows are applicable but inconclusive, the result must include `upstream authenticity inconclusive` and is non-pass. An unlabeled or comprehensive green is non-pass.

| row | status | evidence pointer |
| --- | --- | --- |
| scope | pass / inconclusive / inapplicable | committed catalog or pinned tracked-file list; local digest manifest needs exhaustive root scan with empty extra/missing set |
| local verify | pass / inconclusive / fail | clean verify output; RED vendored-copy mutation failure |
| local verify scope | pass / inconclusive / fail / inapplicable | source path absent run, or evidence recipe has no source path |
| root enumeration | pass / inconclusive / fail | catalog or pinned list plus included/excluded/missing/extra disposition; manifest-only layout needs exhaustive root scan with empty extra/missing set |
| semantic layer | pass / inconclusive / fail / inapplicable | valid+invalid semantic evidence, or no-semantic note naming the artifact's actual declared format/parser and why no parser/schema exists |
| upstream compare | pass / inconclusive / fail / inapplicable | clean upstream check; RED vendored mutation; RED upstream-ref change; RED compare-set membership failure |
| pin authority | pass / inconclusive / fail / inapplicable | signed tag, protected ref, or distinct-owner source |
| recipe integrity | pass / inconclusive / fail | local digest clean+RED; producer proof or local-recipe-only label |
| wrapper integrity | pass / inconclusive / fail / inapplicable | CI/command entrypoint; digest comparison; wrapper clean+RED if present |
| sync boundary | pass / inconclusive / fail | verify/review did not fetch/install/exec-beyond-canonical-script/delete; separate sync authorization if a sync gate ran |
| RED cleanup | pass / inconclusive / fail | scratch checkout used; audited working tree clean before and after |

Minimal local-only example:

| row | status | evidence pointer |
| --- | --- | --- |
| scope | pass | local digest manifest plus independent catalog covers vendored artifact |
| local verify | pass | clean verify; RED artifact mutation fails verify |
| local verify scope | inapplicable | recipe has no sibling/source path |
| root enumeration | pass | local digest manifest plus independent catalog covers artifact file list |
| semantic layer | inapplicable | no-semantic note: the vendored artifact is opaque digest content with no declared schema/parser (a semantic-bearing artifact would instead record valid+invalid fixture evidence) |
| upstream compare | inapplicable | no upstream marker in committed metadata/build/CI |
| pin authority | inapplicable | no upstream marker in committed metadata/build/CI |
| recipe integrity | pass | authoritative metadata states no external canonical producer; local-recipe-only; local digest clean+RED; LC_ALL=C ordering, self-containment, and exit semantics proved |
| wrapper integrity | pass | traced/resolved invocation proves committed local verify script entrypoint directly; digest matches local script; no wrapper |
| sync boundary | pass | verify/review did not fetch/install/exec-beyond-canonical-script/delete; no separate sync gate used |
| RED cleanup | pass | RED ran in scratch checkout; audited tree clean |

Result: `pass` (local-drift only; upstream freshness unverified; local-recipe-only). Note the verdict starts with `pass` per the aggregate rule, and — because upstream compare and pin authority are inapplicable — includes `local-drift only` and `upstream freshness unverified`.

If any applicable row lacks its clean evidence, or lacks required RED/negative evidence where a meaningful/safe RED applies (rows with no meaningful/safe RED instead record an explicit N/A rationale), mark that row `inconclusive` or non-pass; do not aggregate it as green. If a RED mutation does not trigger the expected failure, mark the row `fail` because the gate is defective.
