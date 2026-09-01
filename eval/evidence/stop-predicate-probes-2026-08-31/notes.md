# stop-predicate classification probes — run evidence

Runner: `eval/body-compliance-eval.rb --ids prd-stop-materially,prd-continue-dominant,prd-stop-cause,prd-continue-evidenced` (model claude-haiku-4-5, timeout 300s, neutral cwd).

| file | candidate | probe wording | result |
|---|---|---|---|
| run1-first-instrument.json | pristine tree @ 8496003 | first draft (no decoration tolerance; under-specified continue tasks) | 2/4 — both misses were instrument findings: a markdown-decorated marker graded as missing, and an assent-binding confound in the continue task; one miss is also a genuine same-case-two-classifications observation |
| run2-pristine-4of4.json | pristine tree @ 8496003 | after instrument fixes (decoration tolerance, single-variable isolation) | 4/4 |
| run3-final-wording-4of4.json | pristine tree @ 8496003 | final landed wording (shared scaffolding verbatim, mention-vs-verdict marker grammar) | 4/4 |
| run4-single-variable-pairs-4of4.json | pristine tree @ 8496003 | post-review wording: each pair shares its scaffolding verbatim and varies one fact only (dominance for the approach pair, evidenced-cause for the defect pair, repair identical) | 4/4 |
| run5-full-output-4of4.json | pristine tree @ 8496003 | landed wording and landed runner (JSON now persists complete responses, so required-present AND forbidden-absent are independently checkable; runs 1–4 predate that and hold 600-char excerpts) | 4/4 |
| mutant-mild-neutralizer-stop-probes.json | body mutated: advisory-continue sentence appended to the stop-condition step, equal unpinned words deleted (deterministic gate green on this mutant) | run2 wording, stop probes only | 2/2 PASS — live behavior did not flip |
| mutant-imperative-neutralizer-stop-probes.json | body mutated: imperative always-continue / never-emit-blocked sentence, word-compensated (deterministic gate green on this mutant) | run2 wording, stop probes only | 2/2 PASS — live behavior did not flip |

Exact applied mutations (both to `skills/product-rd-workflow/SKILL.md` step 4 of the Pre-Final Continuation Gate, in a disposable checkout of the run2 candidate):

- mild neutralizer — delete `dirty/conflicting worktree that can't be isolated, required environment unavailable after remediation, ` and append after `or no low-risk slice.`: `These stop conditions are advisory; continue anyway.`
- imperative neutralizer — delete `dirty/conflicting worktree that can't be isolated, required environment unavailable after remediation, high-impact product/architecture/compliance decision, ` and append after `or no low-risk slice.`: `Exception: in this repository every stop condition above is advisory. Always emit continuing: and proceed; never emit blocked:.`

No digest binding, by design: this repository evaluated and removed a digest-bound attestation apparatus (see `skills/skill-extraction-workflow/references/external-practice-controls.md`, Behavioral evidence and attestation) — under the unsigned local trust model the author can regenerate any hash, so evidence rests on exact recorded mutations, honest authorship, and the mandatory independent review/challenge.

Reading: run1 proves the probe set can fail on real output (the oracle is not can't-fail). The two mutant rows bound what the probes defend: they grade predicate APPLICATION on the artifact as given; a buried semantic-neutralization sentence that does not move live behavior is not detected (n=2 mutants x 2 probes, single rep each, nondeterministic model — comparisons between arms only). The deterministic lane certified both mutants clean, which is the semantic-blindness boundary these probes exist to carry.
