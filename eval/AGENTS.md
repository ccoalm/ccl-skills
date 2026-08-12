# eval Agent Contract

Measurement surfaces for agent behavior: fixtures consumed by the behavior-eval
harness, plus standing audits that read real host transcripts. Nothing here
enforces repository changes. These produce machine-readable advisory evidence
and next actions that an agent learning loop can consume; human reading or
intervention is optional.

Rules:

- **Advisory by construction.** Nothing in this directory may become a merge
  gate. An automated eval controller may continue, repair, reject or roll back
  an isolated candidate, but it cannot authorize merge, push, release or deploy.
  These tools classify free-text briefs and prompts with heuristics, and
  heuristics over open semantics do not converge reliably.
  Standing measurement tools exit non-zero only when the scan itself broke,
  never because the measured population looked bad. The causal synthetic smoke
  is the explicit exception: contract-complete but provider-unevaluated exits
  `3` so automation cannot promote it as a green gate.
- **`frozen_at_sha` is an ancestry/batch marker, not a "validated at" stamp.**
  Use `root` for fixtures that belong to the initial public snapshot. An
  explicit SHA must resolve to an ancestor of HEAD; otherwise the fixture is
  drifted and excluded from regression judgement. The marker does **not** claim
  that the expected behavior was already implemented at that revision.
  `test_routing_bank_integrity.sh` (registered in the regression runner) is what
  actually enforces the ancestry property at commit time; it deliberately does
  not evaluate routing, because the grader needs a live model and therefore
  cannot be a deterministic lane.
- **State what the number is NOT.** Every tool documents its blind spots at the
  top of the file, in the same place a reader looks before citing it: what it
  cannot classify, what it counts as a proxy for something it cannot measure
  directly, and which conclusions it does not support. A measurement that
  overstates its own scope is worse than no measurement, because it gets quoted.
- **Isolate what you count.** Host transcripts interleave injected context with
  authored content — the routing block itself contains skill names and
  contract field names, so scanning raw transcript text reports fabricated
  numbers. Count structured events (`tool_use` nodes), and isolate the authored
  brief before matching against it. Three separate measurements of one defect
  can otherwise be misleading.
- **Version event topology.** Skill evidence uses a named event contract and a
  field-topology fingerprint. Unknown Skill/tool-result shapes are
  `unverifiable` and visibly degraded; add a sanitized known-answer fixture
  before registering a new shape. `skill-event-fixtures-v1.json` and
  `skill-event-fixtures-v2.json` are separate pinned contracts: v2 adds the
  per-invocation index, `tool_use_id` and completion semantics that matched-call
  evaluation and external extractors bind to. Neither file may be regenerated
  from parser output.
- **Read-only against host state.** Tools here inspect `~/.claude/projects` and
  similar; they never write to, prune, or reshape it.
- **Trial runners write only to explicit private output roots.** Causal-eval
  code may create isolated task checkouts and 0700/0600 artifacts under the
  caller's `--out` path, but it must not write to host transcripts, the runner
  source checkout, the committed fixture tree, or a sibling trial. Every
  causal-core path needs both an allowlisted file-access audit and separate
  session/provider-memory evidence; neither substitutes for the other.
- **Keep held-out truth outside the repository.** Committed held-out manifests
  contain content-addressed `corpus://` references and metadata only. Actual
  prompts, hidden tests, grader truth, arm assignments, model outcomes and
  identity-bearing access events stay in the private corpus/output root.
- **Synthetic smoke is runner evidence only.** Fixture-only E10 completion proves
  deterministic scheduling, artifacts and gate evaluation. It does not prove
  a real provider is isolated, a grader is calibrated, or CCL skills
  improve quality, so the expected not-evaluated result exits `3` rather than
  masquerading as a green gate. Pending active-control arms remain non-runnable
  until the pre-registered independent-candidate and blinded-selection rules are
  met.
- **No project, person, or repository identity in committed output or fixtures.**
  Sample rows printed for diagnosis carry a truncated path and an agent id, never
  brief bodies — a dispatch brief may contain proprietary or personal content.

Validation:

- `python3 -m unittest eval/test_subagent_owner_audit.py`
- `python3 -m unittest eval/test_skill_effectiveness_bridge.py`
- `python3 -m unittest eval/test_skill_effectiveness_trial.py`
- `python3 eval/skill-effectiveness/run.py smoke --fixture
  eval/skill-effectiveness/fixtures/e10-smoke.json --out
  /private/tmp/ccl-skills-e10-smoke` (only exit `3` is expected for the
  contract-complete fixture; exit `0`, `1`, `2` or any other status is a
  validation failure)
- `python3 eval/subagent-owner-audit.py --days 1` (runs clean on any machine;
  prints a no-data line when there are no transcripts)
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
- `git diff --check`
