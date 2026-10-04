# Finding dispositions

## Pass 1 — review (`pass1-review.json`)

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | The firing-point table sent MR creation only to the pre-merge reference, while the rule that `remove-source-branch` must never be set for permanent/integration or release-named source branches applies when the MR is created and lives in the teardown reference. | Fixed. The push/MR/merge row now names `merge-and-teardown.md`「远端分支」 for that decision and states the obligation: only temporary feature branches get `remove-source-branch`. |
| 2 | P2 | The table turned the protocol's recommended head-SHA guard into a mandatory condition. | Fixed. The merge row keeps only the binding obligations and points to protocol item 3 for the execution recommendations, which it calls recommendations. |
| 3 | P2 | The "scan before removal" assertion checked presence, not order; moving the scan below the removal left every assertion green. | Fixed. An order assertion requires the scan line before the removal line; moving the removal above the scan fails only that assertion. |
| 4 | P2 | The packet did not show that the ledger anchors on `attention-budget-ratchet.md` survive the edit. | Refuted after checking the candidate: all 11 anchors on that file and both on `external-practice-controls.md` occur exactly once, and `register_firing_path_resolution_ok (609 locators resolved)`. The packet lacked context; the candidate had no defect. Recorded in `validation.md`. |
| 5 | P2 | The packet could not show that the new source rows match their primary sources. | Fixed with evidence. `source-excerpts.md` quotes the sentence or table cell behind every figure; no row changed. |
| 6 | P2 | The full lane ran before the final fix commit and no heavy-lane result was supplied. | Fixed. The full lane and the heavy lane ran on the final candidate; results are in `validation.md`. |
