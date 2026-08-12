# scripts/owner-dispatch Agent Contract

Owner-dispatch scripts enforce that agents load the correct owner skill before
editing protected surfaces.

Trust boundary (same as the sibling control-plane engine — see
`scripts/control-plane/README.md`): **the adversary is the actor being gated, not the
environment.** That actor does not own the job environment — the CI files defining it are
themselves gated paths, and anyone who can set the environment can skip the gate outright.
Environment-borne redirection is therefore out of scope, and reviewers should close such
findings as out-of-scope. The environment handling that exists here (disabling replace refs
and the legacy grafts file for ancestry) is accident protection — a repository legitimately
carrying either would otherwise get a silently wrong verdict — not a security control.

Rules:

- Keep policy decisions auditable and fail-closed for strict mode.
- Do not silently broaden write permissions or downgrade a required owner to
  advisory.
- Tests must cover allow, deny, ask, stale state, and generated/vendored
  boundary cases.
- This is a shared enforcement surface; non-wording changes require review,
  challenge, and behavioral evidence.

Validation:

- `bash scripts/owner-dispatch/test.sh`
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
