# Review authentication fallback

## Artifact classification

`gate implementation`

## Scope

Normalize an explicit Claude authentication failure from the envelope classifier through the wrapper's existing one-host-remediation path. If the same path still cannot authenticate after that bounded rerun, the existing candidate-local fallback chain may continue. Do not change credential access, egress, tool boundaries, reviewer verdict parsing, concern-evidence handling, or non-authentication local failures.

## Acceptance matrix

| Input | Wrapper verdict | Controller verdict |
|---|---|---|
| Claude error envelope contains an explicit 401 or authentication failure, before host remediation | `auth_path_unavailable`, not fallback eligible | Requests one host-path rerun |
| The same explicit authentication failure remains after the marked host rerun | `auth_unavailable_after_host_retry`, fallback eligible | Attempts the next eligible independent client |
| Claude error envelope is malformed or an unknown local failure | `local_tool_failure`, not candidate-local | Stops the reviewer lane |
| Output carries concern evidence or violates packet, binding, or tool boundaries | Existing terminal reason | Stops the reviewer lane |

## Test and register coverage

- Add a deterministic regression that reproduces the error envelope seen in the live review and classifies it as `auth`, which the wrapper already maps to the bounded host-remediation contract.
- Run the named assertion RED on the unmodified classifier before changing implementation.
- Run the focused classifier, Claude-wrapper, and review-controller suites, then the complete code-review regression lane.
- Run a guarded scratch mutation that reverts the classifier and proves the named fallback property turns RED.
- Record the final mechanism and evidence in `skills/skill-extraction-workflow/references/source-register.md`.

## Status sync target

The implementation, regression tests, this frozen plan, and the source-register row. No reader Wiki change is required unless the public contract changes.

## Review and challenge gate

After any candidate edit, refresh the implementer self-review plan and run a fresh full-diff tracked review plus challenge. The failed authentication run is evidence of the defect, not review approval.

## Observed baseline

An exact-candidate review received Claude `401 OAuth access token has expired`. The wrapper returned `fallback_eligible=true` and `next_action=fallback` but also `reason_code=local_tool_failure`; the controller therefore returned `stop_reviewer_lane` without attempting the next client. A separate local status check reported the configured Claude account as logged in, so the first correct classification is the existing auth-path false-negative branch, not immediate provider fallback.

## Review finding disposition

Round 1 found that a broad search for authentication phrases inside model-controlled result text could misclassify review content as a transport failure. The candidate now accepts only the observed line-start transport shape `Failed to authenticate. API Error: 401`; structured `api_error_status=401` remains the vocabulary-independent path. Two benign near-miss fixtures stay generic errors, and broadening the expression in a scratch mutant turns the named precision case RED.

The next review suggested `re.MULTILINE` so the same phrase could match after a preamble. That is rejected on first-hand code evidence: `result_text()` returns only the model-controlled `result` string and does not concatenate transport fields, while multiline matching would let a later payload line select an auth/fallback decision. A pass-existing fixture now pins a preamble plus the exact 401 phrase as a generic error; enabling multiline matching in scratch turns that precision case RED. Future CLI wording that lacks both structured 401 and the exact string-start fallback remains fail-closed until separately evidenced.

The challenge correctly found that transport serialization may leave leading spaces or line breaks before the observed error. A regression first reproduced that miss against the candidate. The text fallback now permits only leading whitespace before the exact 401 transport phrase; it still rejects a textual preamble and does not enable multiline search. Removing the whitespace allowance in a scratch mutant turns the named regression RED.

The challenge also asked whether `api_error_status=401` could discard an otherwise valid completed review. No implementation change is needed, but the earlier wording of this paragraph described the wrong mechanism and is corrected here. `parse_review_json.py` refuses **any** envelope carrying a non-null `api_error_status`, structured verdict or not, so such an envelope was never a clean verdict for this round to discard; parse precedence does not protect it. What the new auth arm changes is only the reason token the already-refused envelope is given — `auth` with the bounded host-remediation path instead of a generic `error:`. Pinning this by prose alone left it unenforced for the status this round adds, so a `run_fail` twin of the existing 429 row now pins `api_error_status=401` plus a valid `structured_output` as refused. Gating 401 on `is_error` would also diverge from the existing authoritative-status treatment of 429.

A later independent round found the structured arm compared `api_error_status` to a Python int only, so a `"401"` string serialization missed it and — the pinned text arm missing too — fell back to the generic `error:success` token this round exists to remove. The comparison now normalizes through a local `api_status_int`, mirroring the sibling normalizer already in `parse_probe_result.py` (whose accepted set carries `"0"`, so a string status is an observed shape here, not a hypothetical). String `401`/`429` and a non-numeric `"unauthorized"` status are pinned; reverting the normalization in a scratch mutant turns the string-401 fixture RED.

A later round argued the text arm's `errored` guard reproduces the observed defect for an envelope with `subtype:"success"`, `is_error:false`, no structured status, and the 401 phrase in `result`. Rejected on first-hand evidence: that shape exits **3** ("envelope present, nothing classifiable"), not the `error:success` token the wrapper maps to `local_tool_failure`, so it is a different path and not the observed defect. The asymmetry is deliberate and is now pinned by an `expect_clean` fixture: `api_error_status` is a transport field and needs no second signal, while `result` is model-controlled and does.

The same round argued the text arm should tolerate a missing space, control-character prefixes, or `API Error (401)`. That is rejected on the decision already recorded above: the arm was deliberately narrowed after round 1 to stop model-controlled review payload text from selecting a transport decision, and widening it again on speculation rather than an observed transport shape would re-open exactly that. Wording that carries neither a structured status nor the pinned string-start phrase stays fail-closed until a real occurrence evidences it.
