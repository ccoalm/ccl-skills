# Review dispositions

Independent review passed. Adversarial challenge found one P1: moving the global batch-strip/retitle guard behind a card-only loading condition made it unavailable to non-card batch edits. The guard remains verbatim in SKILL.md; only the card skeleton and four card-specific rules move to the required reference. The post-finding review passed without new findings.

Static preservation passed: five moved paragraphs are verbatim, the surrounding entry reconstructs byte for byte, and nine damaged variants are rejected. An independent guard-availability check reproduces the pre-fix entry hash and returns RED before restoration, GREEN after restoration. These checks establish instruction availability, not runtime compliance or task-quality benefit.

Final source hashes:

| Path | SHA-256 |
| --- | --- |
| skills/tighten-doc/SKILL.md | 7419ba2b134f575a1a7c70ddbe9d7142f639d0f5a4ef6b4fc76f64046ee2903a |
| skills/tighten-doc/references/execution-card-patterns.md | 3e4bd24177a2aa8e0a87f143a25d7355d9f6411ba183483f045e811dbdabfa77 |
| specs/166-doc-entry-loading/plan.md | 457a5f23e669e09adb79b16a9025e3ea61fb7efacefbbd006cb41a66d3b588e0 |
| specs/166-doc-entry-loading/obligation-preservation.md | 914a77c69d513844ccc2172c1f30a02f40414f35ccc7f6f1496f9a6ecd546ca0 |

Validation: `SUITE_JOBS=8 make test` exited 0 (46 fast suites, review shards 9 and 8 suites, three abort-leak probes); heavy-only exited 0 (9 suites); public sanitization and whitespace checks exited 0. These records publish the conclusive controller fields unchanged while omitting private caller input and host metadata. Complete receipts remain separately retained.
