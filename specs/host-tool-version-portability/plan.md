# Portability across older git and jq

Three suites fail on a host with git 2.39.5 and jq 1.6. The probes behind each cause give the expected result on git 2.50.1 and jq 1.7.1; the exact versions where git and jq changed were not bisected. Each failure has its own cause in a version difference, and one of them is a product defect: the edit-isolation guard's fallback drops every path on jq 1.6, so with Python or its helper missing, isolation is not enforced at all.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Make the guard enforce isolation on jq 1.6, and make two test suites judge the same way on old and new git and jq, so a local `make test` on such a host is green when the code is correct. |
| Scope | In: `hooks/guard-edit-isolation.sh` (fallback NUL check), `hooks/skill-extraction-gate-stop.sh` (helper-failure message on empty output), `skills/skill-extraction-workflow/scripts/test_check_ccl_skill_catalog.sh` (fixture ref cleanup), `hooks/test_remind_unverified_cli_flag.sh` (probe output check). Out: the `jq -e` uses with possibly empty input in owner-dispatch, a strict enforcement surface where changing the empty-output meaning can flip a deny either way; recorded below as follow-ups without failing evidence. No iterative-program watermark. |
| Depth | Two test-helper fixes and one hook fix, each with its cause verified by a paired probe on both tool versions. |
| Result classification | Failure/correction. The three suites fail identically on unmodified `main` on a git 2.39.5 / jq 1.6 host. |
| Matching analysis | (1) git 2.39.5 does not list a nested annotated tag under `for-each-ref --points-at <commit>`; the catalog fixture removes aliases through that list, so the nested alias survives. (2) jq 1.6 `contains("\u0000")` is true for every string, because its string search stops at NUL; the guard's fallback filter drops every path. (3) jq 1.6 `-e` exits 0 on empty input; the probe reads an empty hook output as a reminder, and the extraction stop hook reads a failed helper's empty output as `truncated`, so it reports "history too large" instead of "could not be read". Counterfactual: on git 2.50.1 and jq 1.7.1 the same probes give the expected results, so the version is the cause in each. Prevention: each check is rewritten in a form both versions evaluate the same way, and the suites that failed are the regression evidence on old-tool hosts. |
| Failure mode or success boundary | A fix that changes what the guard denies on new jq, or that weakens a test assertion, fails this round. |
| Lifecycle impact | Implementation and verification (local lanes on older hosts); the guard fix changes runtime behavior only where jq 1.6 and the fallback path meet. |
| Evidence plan | First-hand probes on this host (git 2.39.5, jq 1.6) and on a git 2.50.1 / jq 1.7.1 host, the failing suites before and after, and the hook suites. External grounding: not applicable, this is tool-version behavior verified by direct probes. |
| Completion standard | The three suites pass on this host; guard, hook and catalog suites still pass; `check-ccl-skills.sh` passes; review and challenge on the diff. |

## Follow-ups without failing evidence

- `scripts/owner-dispatch/owner-dispatch.sh` pipes `python3 host-input.py transcript` into `jq -e '.verifiable'`; if Python fails and prints nothing, jq 1.6 reports success.
- `cfg_schema_ok` in the same script runs `jq -e` on a config string that could be empty.
