# Review Reception

Use this when receiving review feedback from a human reviewer, AI reviewer, CI analysis, or external auditor.

## Rules

- Read all feedback before changing code.
- Understand the requested change before implementing it.
- Verify feedback against the current codebase; do not assume every suggestion is correct.
- Ask when feedback is ambiguous, incomplete, or appears to conflict with requirements.
- Push back with technical evidence when a suggestion is incorrect or harmful.
- If your pushback was wrong, correct it factually and move on: retract only after re-verifying against the codebase or the authority that settles the point (requirement owner, product decision, observed runtime behavior) — state the concrete counter-evidence; reviewer insistence alone is never grounds, and an inconclusive re-check goes to the risk owner rather than holding the pushback — except on a scope-adding finding, which follows the mirror-case procedure below instead. Once re-verification or that risk owner establishes the pushback was wrong, retract and implement — no long apology, no defending the earlier pushback.
- Implement one coherent review item or group at a time, then verify.
- Partition findings before fixing: a mechanical finding (bug, missing check, wrong value) goes on the fix list; a design-level finding — one questioning a mechanism's cost, operability, trust-model fit, or existence — is a risk-owner decision item (keep / delete / narrow / replace) to surface BEFORE investing hardening rounds in the questioned mechanism. Hardening first and deciding later pays the cost twice — once to build, once to tear down. The mirror case — a finding that adds scope or abstraction beyond the agreed deliverable (a new capability or abstraction layer — not a guard, error path, or rollback that a current acceptance point or observed hard constraint already requires for behavior already in scope; a remedy that itself introduces a new capability or abstraction stays scope-adding however it is labelled; an arguable classification is settled by running the test named next, never by defaulting either way) — is never an automatic build: answer it against the structural-minimality test in `implementation-completeness-and-minimality.md` — name the current acceptance point or observed hard constraint that needs it, or state that there is none — and reply with that answer before deciding. No locator means the answer is decline, not build: building it anyway first requires the risk owner to change the governing acceptance requirement. that evidence-backed answer is the receiver's to give and the reviewer's to confirm, and a rejected answer returns the item to the receiver to rebuild the evidence rather than to a risk owner — on this question the risk owner's role is to change the governing acceptance requirement, not to override the reviewer's rejection. When one finding is both design-level and scope-adding — it questions an existing mechanism AND proposes a new capability or abstraction, whether that wraps, supplements, or replaces the mechanism — the two paths govern different objects and both run: the minimality test decides the proposed addition (receiver answers, reviewer confirms), while the questioned mechanism's keep / delete / narrow / replace stays the risk owner's. Neither substitutes for the other, and neither decision alone authorizes the addition.
- Avoid performative agreement. Technical correctness matters more than sounding agreeable: agree only after verifying — the reply shows what you checked and what you found, and praise or thanks offered in place of that evidence is the failure ("you're absolutely right" / "great point" are the common forms).

## Response Pattern

1. Restate the technical requirement if it is not obvious.
2. Check the relevant code, tests, contracts, or docs.
3. Decide: accept, clarify, defer with risk, or reject with evidence.
4. Make the change only after the decision is clear.
5. Run focused verification.
6. Report what changed, what was verified, and any remaining risk.

## When To Stop

Stop before implementation when:

- multiple review items may be related and some are unclear.
- the suggestion would change product behavior or public contract.
- the suggestion conflicts with architecture, security, data integrity, or compatibility constraints.
- the reviewer may not have full codebase context.

