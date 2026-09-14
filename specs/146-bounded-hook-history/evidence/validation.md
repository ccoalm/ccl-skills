# Bounded Stop check verification

Runtime candidate: `56b45e16b7703e85ae62d54bb367de3c780b9af2`.
Base: `ae0367985eb790d462eab0ace1e95ff3d53f3112`.
The final review candidate digest is
`426f712e4f1551ea73d4fa49ca3d539e22e5c3e1553f629ce3570bd47768fcb4`.
The evidence-only follow-up preserves those runtime bytes.

## Review dispositions

| Result | Findings and disposition |
| --- | --- |
| [Review](review.json) | P1 release verification: retained as a pre-tag gate; package and artifact checks below now pass. P2 wrong extraction error message: fixed with malformed-input regression. |
| [Challenge](challenge.json) | P1 pending Claude invocation: source-refuted by the existing extraction contract in `hooks/skill-extraction-gate-stop.sh`; native Skill requests count as invocation. Added pending/failed Claude compatibility cases and clarified the plan. P2 broken optional helper: fixed with RuntimeError and syntax-error regressions. P1 release verification: same pre-tag gate. |
| [Delta 1](delta-1.json) | P2 mismatched transcript paths: reproduced, then fixed by deriving notice identity from the transcript actually scanned. |
| [Delta 2](delta-2.json) | P2 inode reuse: documented as an advisory-suppression limitation. Adding ctime or mtime would repeat notices after normal appends; a local filesystem probe confirmed both timestamps change while device/inode remain stable. Scans continue under inode reuse. |
| [Delta 3](delta-3.json) | Final review passed with no findings after the file-identity boundary was documented. |

All five results are the controller's original JSON. Gate fireability applies:
the frozen packets included complete helper and caller source plus subprocess
regressions, allowing inspection of the positive, negative and unknown paths.
Private alias audit reported `private-ok`; public sanitization passed.

## Executed checks

| Check | Observed result |
| --- | --- |
| Baseline focused hook regressions | 14 assertion failures before the initial repair |
| `python3 hooks/test_host_input.py` | Final runtime: 40 passed |
| Controlled mutations in disposable runtime copies | Six controls passed; all six guard mutations failed with attributable assertions |
| `make npm-publish-dry` | 356 package tests and 11 tarball tests passed; pack dry run completed |
| Final `npm run build` and `npm run test:pack` | Rebuilt after the runtime fixes; 11 tarball tests passed |
| Eight hook regressions against the final extracted tarball | Passed; hook bytes also matched the source candidate |
| `make npm-host-smoke` with the final tarball | Three-host install/update/uninstall smoke passed |
| Repository checks in `make test` | All reached checks passed after the environment and focused retries described below |
| `make test-regressions-fast` | Passed |
| Review regression shards | Both shards passed after the process-state helper was rerun in a compatible environment |
| `make test-code-review-abort-leak` | All four client/leg combinations passed |
| Public sanitization, spec references, shared Git surface, whitespace | Passed |

Initial local runs were not clean full-lane passes. A stripped environment
omitted UTF-8 locale and HOME; the sandbox denied npm's default cache and
macOS's setuid `ps`. These were corrected with explicit locale/HOME, an isolated
npm cache, and a credential-free environment for the inspected process tests.
An inherited self-update-disable flag was removed for its dedicated negative
test. A timing-sensitive FIFO case and one calibration sample failed under
load and passed on retry. No test or threshold was weakened.

The initial CI run passed the seven regression/package jobs but rejected the
repository job because review JSON had not yet been committed. This follow-up
adds the original results and this verification record. The refreshed CI run
must pass before integration. Local heavy regressions were delegated to the
blocking CI job, which passed for the runtime candidate.

## Publication boundary

Promotion, tag creation, npm publication and registry/provenance readback remain
pending. The version is 0.18.4 and publication uses the existing protected tag
workflow. These local artifacts are verification builds, not published releases.
