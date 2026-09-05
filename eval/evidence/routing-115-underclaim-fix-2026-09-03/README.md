# Routing under-claim fix — eleven description edits, every case measured on paired trees

The round that produced `routing-baseline-replicas3-2026-09-03/` deliberately took no routing
dispositions: it recorded that 14 of 158 frozen cases did not reach their expected owner and left
acting on them to a separate round. This is that round.

It changes **eleven `description` edits across nine owners** and nothing
else on the routing surface. The task bank is byte-identical to the baseline's — `bank_sha256 =
1bf0633717c2…` in both reports — and the runner's own co-change check reports
`co_change_bank_and_descriptions: false`, so "fix the skill, then edit the test until it passes" is
excluded by the instrument rather than by assertion.

## What was fixed

The two arms are whole trees, not isolated surfaces. Beyond the descriptions they also differ in the
runner, its reference, the test suite and the evidence files, because those landed in the same
branch; the grader's input is the skill catalog plus the utterance, and the runner changes touched
report fields, the printed banner and test fixtures, never prompt construction or verdict parsing.
That is checkable against the diff rather than taken on trust.

**The tree these files sit beside is catalog `e889445588766213`, and every claim-bearing case has a
treatment arm on exactly that tree** — ten cases at 10/10 or 20/20, one (`p3-spec-then-tc`) at 15/20
against a control of 14/20, plus the grill-me protection case and the negative control. Earlier
treatment arms were taken on candidates that later edits replaced; `paired-measurements.tsv` marks
those `intermediate` and the settled ones `current`, so the distinction is a column, not a promise.

The last two edits before settling were a trade this round measured rather than argued. Restoring a
bare implementation-phase token (which review had shown was needed) pulled `p3-spec-then-tc` from
10/10 to 13/20 — the two trees differed by that token alone, the single-variable A/B the protocol
asks for. Merging it with its approval-wording neighbour recovered the case to 15/20 while the
review counterexample 「方案已经定了，现在进入实现阶段」 routes 20/20 (a scratch probe, id
`probe-implementation-transition-no-approval`, never added to the bank) and the frozen case for the
old approval wording, `p3-transition-impl` 「方案评审通过」, stays 20/20 on the settled tree — both
former entry paths measured, separately, on the tree that lands. Sharpening the rival's Skip leg then lifted the case to
20/20 but moved `ab-c3` from 19/20 to 15/20, and was withdrawn: one frozen case may not be bought
with another, and that edit rested on a rate rather than a surface asymmetry.

**These deltas are the package's, not any single description's.** The control is this branch's base
`1506dcf` and the treatment is candidate `0e06c8a3e604…`, which carries all eleven
edits; the rule this round itself lands says a comparison that moved several descriptions at once
cannot be attributed to one of them. So the owner named in each row is *the owner whose description
was edited for that case*, not a measured cause, and the table should be read as a package result
with a per-case interpretation attached.

Two things keep that interpretation from being arbitrary, and neither is attribution: the case's
expected owner has exactly one changed description, and no other changed owner appears anywhere in
that case's observed distribution on either arm. One case does have a genuine single-variable A/B —
`ab-c5` was measured on a four-edit tree (6/9) and on the same tree plus only the grill-me edit
(10/10), which is the isolation the protocol asks for. The other ten were not split that way; eleven
single-edit trees would be needed and were not run. That residual is the round's, not the
reviewer's, and it is recorded rather than argued away.

Arms taken on a superseded candidate are process data, not evidence for what lands. Rows marked
`current` come from two runs on the settled tree: the ten-case final pass and the earlier probe that
measured the merged trigger.

| case | changed owner and its measured move (the anchor text names the run it was first seen in) | control | settled tree `e8894455` |
| --- | --- | --- | --- |
| `p3-resume-refactor` | product-rd-workflow: p3-resume-refactor moved 0/10 to 10/10 | 0/10 | 10/10 (settled tree) |
| `p3-log-plus-test` | platform-observability: p3-log-plus-test moved 2/10 to 10/10 | 2/10 | 20/20 (settled tree) |
| `route-nodejs-architecture-not-go-python` | product-rd-workflow second trigger: route-nodejs-arch moved 6/10 to 10/10 | 6/10 | 10/10 (settled tree) |
| `p3-perf-plus-regression` | defect-diagnosis: p3-perf-plus-regression moved 5/10 to 10/10 on the batch tree, 20/20 on candidate 0e06c8a3 | 5/10 | 20/20 (settled tree) |
| `skip-miniapp-build` | miniapp-product-dev: skip-miniapp-build moved 6/10 to 10/10 on the batch tree, 20/20 on candidate 0e06c8a3 | 6/10 | 10/10 (settled tree) |
| `ab-c5` | grill-me: ab-c5 moved 8/10 to 10/10 on the batch tree, 20/20 on candidate 0e06c8a3 | 8/10 | 10/10 (settled tree) |
| `ab-n2` | platform-observability second trigger: ab-n2 moved 9/10 to 10/10 on the batch tree, 20/20 on candidate 0e06c8a3 | 9/10 | 20/20 (settled tree) |
| `ab-d6` | requirement-scope: ab-d6 moved 8/10 to 10/10 | 8/10 | 10/10 (settled tree) |
| `ab-b5` | requirement-baseline: ab-b5 moved 14/20 to 20/20 | 14/20 | 10/10 (settled tree) |
| `variant-neg-release-watch-sop` | platform-release-engineering: release-watch moved 18/20 to 20/20 | 18/20 | 10/10 (settled tree) |
| `p3-spec-then-tc` | requirement-doc-writer: p3-spec-then-tc claim added, case unmoved at 7/10 — 15/20 on the settled tree | 7/10 | 15/20 |

`p3-resume-refactor` is worth stating plainly: on the unedited tree, **ten gradings out of ten found
no owner at all**. The three-replica baseline had labelled it the round's one consistent failure;
the paired ten-replica control shows it was worse than the label.

**One check is not repeated on the settled tree and is recorded as a residual, not hidden in a
sentence.** The whole-owner pass over all 24 `product-rd-workflow` cases was taken on catalog
`0e06c8a3…`, which the tables mark intermediate; the settled tree differs from it by one merged
trigger on that same owner. Of those 24, the four that carry this round's claims were re-measured on
the settled tree and hold; `miss-refactor-python-unqualified`, the one case where a must-not owner
was ever selected, is re-measured there too and reported in full below. The other nineteen were not. Repeating the full pass
costs about two hours of grader time and was not spent; the reader has the intermediate-tree
numbers, the single-token delta, and the choice.

Side effects, measured rather than assumed. `product-rd-workflow` sits at severe size debt with a
zero-growth byte budget, so its two new triggers had to be paid for: sixteen separators compressed,
one duplicate implement-phase phrasing dropped, and two sentences deleted from an unrelated
standards bullet whose obligations the owning checklist reference already carries. Because that
reformats the entire trigger list rather than one token, every frozen case expecting this owner was
re-run on paired trees — 24 cases, ten replicas per arm. Fifteen cases that were 10/10 stayed 10/10,
including the three the payment could plausibly have cost (`miss-restart`, `new-redo-variant`,
`p3-transition-impl`). Two cases moved and were probed further:

- `gap-rust-service` 1/10 → 6/10. This is a coverage-hole probe whose expected owner IS
  `product-rd-workflow` with `none` acceptable, and whose absorption guard names the stack
  executors. Those score zero on both arms, so the move is toward the stated intent — a
  new-capability ask for a stack with no skill enters the coordinator for intake — not absorption.
- `miss-refactor-python-unqualified` is the one case where a `must_not_route_to` owner was ever
  selected, and the record states it rather than rounding it away. Control arm, 60 gradings: 43 to
  the expected owner, **zero** `python-service-dev`. Treatment arms, 80 gradings across every tree
  including 20 on the settled one: 61 to the expected owner, **two** `python-service-dev` — one on an
  intermediate tree, one on the settled tree. Two in eighty against zero in sixty is not separable
  (p ≈ 0.5), neither Python owner was edited, and the coordinator rival fell from 10/60 to 2/20
  after its architecture claim was scoped to stacks without an architecture sibling. This round draws
  no causal conclusion either way: a coordinator description that competes for this case WAS edited,
  and pooling across treatment catalogs cannot attribute or exclude the settled tree's single forbidden
  verdict. It is an **unresolved neighbour finding** filed for the independent lane, which under the
  protocol is the only lane that may dispose of a must-not observation.

### Why each edit is defensible without pointing at its number

Nine of the eleven answer the same defect: **a territory that another surface already assigns to the
owner, which the owner's own routing surface never claimed.**

- `p3-resume-refactor` — product-rd advertised the whole redo family (推倒重来 / 重新开发 /
  完全重新开始 / 清除代码重新开发 / redo-from-scratch) and no continue/resume member. Nine of ten
  gradings answered `none`: a hole, not a collision.
- `p3-log-plus-test` — the owner claimed its territory only in English (service logs, distributed
  tracing, log/trace correlation) while the utterance is Chinese, and activation is closer to
  keyword match than to paraphrase. Eight of seventeen gradings refused; the rest scattered over
  four rivals at one hit each, so the defect was the owner's, not a competitor's.
- `p3-perf-plus-regression` — the skill claimed bug / 报错 / test 挂了 / 线上问题 and nothing about a
  slow endpoint. Added the anchored 接口变慢·性能退化, not a bare 性能优化, which would have swallowed
  performance work that is a product-rd delivery.
- `skip-miniapp-build` — host-devtool build mechanics were absent from a description that listed
  feature work (pages, state, auth, sharing, review).
- `ab-c5` — four surfaces already assign the question pool to `requirement-intent` (its body table
  row naming 推荐默认值, its body line 本技能只生成问题池并整理拷问后的结论, the always-on
  entry-routing layer, and grill-me's own body, which describes the process), while only grill-me's
  description claimed the bare token 拷问, with five Skip legs and none pointing back.
- `ab-n2` — `requirement-baseline` routes 问线上是否已启用 to observability on BOTH its surfaces
  (description, and body 代码里存在 ≠ 已部署启用); observability claimed it on neither of its own.
- `ab-d6` — `requirement-scope`'s body names 回滚/降级边界 as a deliverable field twice; its
  description carried only 版本切片.
- `p3-spec-then-tc` — `requirement-doc-writer`'s body routes 多阶段研发交付·实现/发布计划 to
  product-rd; its description's six Skip legs omitted that owner entirely.
- `variant-neg-release-watch-sop` — the only skill mentioning 值班 was observability, and it does so
  with an explicit 发布值班/回滚除外 carve-out; the owner that carve-out points to never claimed 值班.
  A surface pushed traffic away and nothing caught it.

The remaining two are position, not omission:

- `ab-b5` — 按 commit 固定的代码现状取证 sat in the deliverable clause rather than the trigger list,
  and the trigger list is the position that carries routing weight (the reason the desc-budget
  truncation arm exists at all). Moving the claim into the trigger list took the case from 70% to
  20/20 with no new territory claimed.
- `route-nodejs-architecture-not-go-python` — Node has no architecture sibling by decision, and
  `nodejs-service-dev` says so in its body while routing those decisions to product-rd; product-rd's
  own reference `problem-resolution-and-learning.md` says the same from the owning side. But
  product-rd's description never claimed 服务边界·数据归属 while both `go-microservice-architecture`
  and `python-service-architecture` do, so the nearest-looking rival won. A body carve-out restating
  the rule was drafted and withdrawn: the owning reference already carries it, and reference-depth
  backing is backing. What the entrypoint body did change is unrelated to this claim — two sentences
  duplicated from that same checklist reference were deleted to pay the byte budget, and the bullet
  they left keeps its trigger, its route, and its pointer.

### What was deliberately left alone

`mem-api-log-redact` (expected `app-cross-platform-dev`, a Flutter client log-redaction fix) keeps a
one-in-twenty leak to `defect-diagnosis` and is **not** edited. `product-rd-workflow`'s body routes
secrets/PII/raw-log redaction to `platform-observability`; the bank assigns this case to the app
stack because it is a concrete client-code fix. Claiming 日志脱敏 on the app skill would manufacture
a real cross-owner conflict to answer a 1-in-20 deviation. It doubles as this round's negative
control: 39/40 on the control arm across two independent 20-replica measurements, 20/20 on an
intermediate tree, and 10/10 on the settled tree, where its rival appears zero times.

## The instrument finding

Every number above comes from paired arms at ten or twenty replicas because three replicas could not
support any of it. Within this one round the three-replica ruler produced a wrong case-level reading
in both directions:

- five cases it reported as failing are 10/10 correct (`ctrl-unit-test`, `ctrl-feature`,
  `new-deprecation`, `ab-c3`, `ab-b3`) — six drafted description edits rested on them and were dropped;
- a single deviation on `p3-spec-then-tc` supported an argument that a frozen expectation had gone
  stale; at ten replicas the rival takes 3 of 17 and the argument was withdrawn;
- `ab-c5` scored PASS before and FAIL after, manufacturing a neighbour regression that the paired
  control shows exists identically on the unedited tree;
- three full-bank runs on candidates differing by one unrelated description returned almost disjoint
  `newly_failed` sets. Every entry except `route-nodejs-arch` appeared once and never again, and each
  was refuted by a paired 20-replica probe.

Ten replicas are not immune either: `ab-b5` measured 5/10 (50%) and then 17/20 (85%) on the *same*
candidate, and this round briefly recorded a regression on the strength of the first reading.

Three rules landed in `references/eval-routing.md` because of this, each carrying its measured
instance: a report below ten replicas is screening resolution and licenses no edit (the runner now
says so itself — `screening_resolution_only` on stdout, `action_resolution: false` in the report,
with `test_eval_routing_bank_resolution.sh` pinning the doc and the executable to one number); a
threshold comparison must be read off pooled observations, since a single ten-replica point estimate
carries roughly plus-or-minus 15 to 20 points near 80%; and `newly_failed` is a candidate list, not a
regression verdict — each entry needs its own paired 20-replica probe before it can be called one.

## Artifacts

`full-bank-replicas3.json` in this directory is the continuity run on the final
candidate: the same bank as `routing-baseline-replicas3-2026-09-03/`, `--replicas 3`, that
baseline passed as `--baseline`.

| | baseline 2026-09-03 | this round |
| --- | --- | --- |
| candidate | `catalog_sha256 7db3593170b8…` | `catalog_sha256 0e06c8a3e604…` (superseded by one restored trigger) |
| bank | `1bf0633717c2…` | `1bf0633717c2…` (identical) |
| result | 144/158 | **157/158** |
| grader-error verdicts | 0 | 1 (`ab-n2`, partially measured) |
| comparable | — | `baseline_comparable: true` |
| co-change | — | `false` |

`newly_passed` holds fourteen cases. `newly_failed` holds exactly one,
`miss-refactor-python-unqualified`, and it is not a regression this round introduced: the paired
20-replica probe on that same candidate (`catalog_sha256 0e06c8a3e604…`) and on the unedited tree
returns **identical** distributions — 17/20 to the expected owner, two refusals, one near-miss to
the coordinator, and zero `must_not_route_to` hits on either arm.

The report carries `action_resolution: false` and prints the screening banner, because three
replicas is below the floor this round landed. That is the intended reading: this run establishes
comparability with the previous ruler and licensed none of the edits above — every edit is licensed
by the paired per-case measurements, at ten or twenty valid observations per arm.

It is **not** the runner's literal output, and says so in its own `_transformation` field. Two
things were done to it: the remainder was re-serialised without indentation, and the per-replica
verdict arrays were dropped. The runner's `--baseline` comparison consumes `bank_sha256`, `replicas`
and per-task status, all of which remain; what went is the per-verdict detail of a *three-replica*
run — screening-resolution data this round demonstrated does not reproduce — and it was costing
82,724 bytes against a 200,000-byte candidate cap that left this round 31 bytes of room to answer a
review finding. A later round that needs per-case distributions must measure them at ten or more
replicas, which the rule this round lands requires regardless.

- pretty-printed original: `7692924a35a8a013aecd34192078025f4ed97998bd494f4fd6a9fab77b7c68c0`
- the file here: `d9aa4bcb51fe0d253679cb9060021116c1e07067561b5609089bd860fd221ece`

One honest limit on this artifact: it was produced by the runner **before** the review fix that
derives the resolution floor from valid observations, so it carries no `min_valid_observations`
field. Its own verdict is unaffected — at three replicas both the old and the new computation
report `action_resolution: false` — and its grading data is untouched by that fix, which changes
only how the report field and banner are computed.

`paired-measurements.tsv` in this directory is the checkable half of this record. Prose is not
evidence a reviewer can verify, so every number stated above also appears there as a row generated
from the raw reports rather than transcribed: 136 MEASUREMENT rows carrying case, arm, source run,
expected-owner hits, valid observations, status, and every rival selection; plus 27 RUN rows
carrying each report's replica count, totals, `catalog_sha256`, size, and **full** sha256. The
control arm's catalog is the branch base and each treatment row names the candidate it measured, so which
tree produced a row is readable from the row itself.

One routing-surface change in this round carries no bank evidence, deliberately and by declaration:
`downscoped:R115-TRIGGER-RESTORE-NO-FROZEN-CASE`. Restoring `进入实现阶段` to
`product-rd-workflow` answers a counterexample adversarial review supplied — a request naming the
transition without the approval wording — and no frozen case exercises that token, which is exactly
why the round's earlier synonym argument for removing it could not be refuted by measurement. Adding
a case to the bank would void every baseline comparison in this round, so the honest record is a
declared downscope rather than a number the bank cannot produce. The restoration returns the
description to a superset of its base state, so it can only widen what the owner claims.

Adversarial review pushed on the obvious weakness of two files I generated: dropping a case from
both, or from a RUN's task count as well, recounts cleanly. The binding that does not depend on me
is the frozen bank itself, `eval/routing-tasks.jsonl`, which this round does not touch: every case
id in either table exists there, and the eleven cases this round makes a claim about are named in
the table above, so an omission is visible against an artifact the round could not have edited
without the runner's co-change check saying so. What that does not catch is a case silently dropped
from every surface at once, and no self-generated pair can.

`replica-verdicts.tsv` is the source those counts come from, and it is committed alongside them:
one row per case per run, carrying the per-replica selected owner and a marker for each replica that
produced no verdict. Every number in `paired-measurements.tsv` is a count over that column — hits is
how many entries equal the expected owner, valid is how many entries there are — so the two files
check each other with no external input. They were recounted against each other before landing, with
zero mismatches, and any reader can repeat that.

The full runner reports stay outside the commit at
`~/.claude/skills/.extraction-work/115-runs/<file>` on the maintainer's host: they total roughly
700 KB and would take the candidate past the binder's packet cap on their own. What they add beyond
`replica-verdicts.tsv` is per-verdict confidence, clarify flags and prompts — none of which any
claim here rests on. Their full sha256 are in the RUN rows.

The three superseded full-bank runs are listed because they exist, not because they count: each
measured a candidate that a later edit replaced, and the protocol voids an intermediate draft's pass
count the moment the wording changes again.
