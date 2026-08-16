# evidence Agent Contract

Frozen measurement artifacts for round 023: the differential probe runners and their raw outputs, committed so the `RED-baseline` claims in `skill-extraction-workflow/references/source-register.md` can be independently checked instead of taken on the author's word.

Rules:

- **Frozen after the round lands.** Do not edit, re-grade, prune, or regenerate these files to make a later claim look better. A superseding measurement is a new file in a new round's evidence directory, and the register row that cites it says so.
- **These runners are evidence tools, not repository gates.** They call a live model, so they are non-deterministic and are never wired into `make test` or any blocking check. A green run here proves nothing about the repository; it records what two pinned skill revisions produced on one task set.
- **Read the runner before citing its numbers.** Each one resolves both arms to immutable commit SHAs before any model call, aborts on any failed git read or dirty skills tree, and records the sha256 of every prompt input beside the score, so a cited base/head pair is verifiable. Grading is a keyword contract: a compliant paraphrase can read as a miss, which is why every raw answer is kept in the JSON except machine-only host paths or credentials, which are replaced by neutral placeholders with an explicit `redactions` field; redaction must not intersect the grading patterns, and `len` records the retained text.
- **Numbers are reported as measured.** Weak or absent deltas stay in the record with the rule they failed to move; a candidate that measured 4/4 on both arms was withdrawn rather than relabelled.
- **No credentials, no host paths, no third-party content.** The runners take a worktree path as an argument and read only committed blobs from it.
