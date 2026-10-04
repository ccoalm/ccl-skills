# Round 163 review dispositions

Review (independent, codex, release depth) and challenge (adversarial, codex,
release depth), both on candidate `7574e97`, the branch before the fixes and
before the history was reordered to keep the register row last. The fixes
landed together in the commit "Harden paired-eval validity, isolation and
recovery"; the records were regraded with it (no record changed) and the
write-up corrected. 24 findings were fixed; one is an accepted limitation.

| Pass | # | Severity | Finding | Disposition |
| --- | --- | --- | --- | --- |
| challenge | 1 | P1 | canary seen only in a tool result left the run valid | fixed: the canary is checked against the whole stream (`instruction_file_canary_seen`); isolation and batch tests |
| review | 2 | P1 | same as challenge 1 | fixed with it |
| challenge | 2 | P1 | success, then more activity and a crash still counted | fixed: `activity_after_last_result`; isolation and batch tests |
| review | 1 | P1 | same as challenge 2 | fixed with it |
| challenge | 3 | P1 | regrade read the canary from an agent-writable world file | fixed: records keep the token, snapshot and plugin path; legacy records regrade only from an untouched canary file; class sweep also moved grading off the sample's own git config |
| challenge | 4 | P1 | exports left without a frozen plan were reused under new refs | fixed: with no plan.json, exports are rebuilt |
| review | 4 | P1 | same as challenge 4 | fixed with it |
| challenge | 5 | P1 | reports counted any record.json | fixed: records must match the plan hash, the frozen inventory and their own path |
| review | 5 | P1 | shared exports let one run change the treatment of later runs | fixed: each run gets a private copy; a run that edits it is invalid (`plugin_export_changed`) |
| review | 6 | P1 | two invocations could share one output root | fixed: exclusive lock on the output root |
| challenge | 6 | P1 | a detached descendant outlives the process-group kill | accepted limitation, now stated in the tool header (no defence against a hostile agent); no process from the first batch survived it; sandboxing stays a follow-up |
| challenge | 7 | P2 | output inside a sibling linked worktree was not refused | fixed: every registered worktree root is refused |
| review | 3 | P1 | same as challenge 7 | fixed with it |
| challenge | 8 | P2 | trace segmentation split inside quotes and comments and skipped substitutions | fixed: shell-aware segmentation (quotes, comments, substitutions, a hash inside a word) with the reported near-miss cases as tests |
| review | 8 | P2 | same as challenge 8 | fixed with it |
| challenge | 9 | P2 | integrity list truncated, directory symlinks missed | fixed: full list stored, report truncates only its display; directory symlinks in manifests |
| review | 11 | P2 | same as challenge 9 | fixed with it |
| review | 7 | P2 | a calibration that did not fire still let samples count | fixed: the batch runs no sample unless the calibration finished and fired |
| review | 9 | P2 | JSON written in place could tear | fixed: atomic writes for plan, records, snapshots, calibration, integrity, results and report |
| review | 10 | P2 | an interrupt during setup could still launch a run | fixed: spawning happens under a lock and is refused once shutdown begins |
| review | 12 | P2 | source-repo reads and the version probe kept CLAUDE* variables | fixed: one inherited-environment sanitizer for every child |
| challenge | 10 | P2 | no per-sample evidence for the post-batch readings | fixed: `batch-records.json` with both readings per sample |
| challenge | 11 | P2 | "neither helped nor hurt" treated no separation as equivalence | fixed in the write-up, the PR text and the register row |
| review | 13 | P2 | same as challenge 11 | fixed with it |
| review | 14 | P2 | lanes still pending in the committed record | closed by the final lanes on the final candidate |
