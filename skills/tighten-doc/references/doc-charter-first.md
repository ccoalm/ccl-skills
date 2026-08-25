# Doc Charter First — multi-round deliverable docs

For a multi-round deliverable doc (several revision rounds with the reader-owner in the loop — a share doc, a team handbook page, launch material), lock a **doc charter** BEFORE drafting:

| Field | Question it answers |
| --- | --- |
| Audience | Who reads this, and what do they already know? Multiple reader classes → per-class reading paths, not one blended doc. |
| Purpose | What should the reader be able to do or decide after reading? |
| Venue | Presented (talk outline: one figure + one claim per section) vs self-read (narrative entry page)? Collaborative platform vs repo file? |
| Length budget | A hard cap for the entry surface; overflow goes to child pages/appendices, the entry gains only a navigation line. |
| Genre | Which genre leads here? A doc may sit on both axes at once — a delivery genre (方案/架构, 调研, 现状梳理, 评审, 计划) and a user-facing documentation mode (tutorial / how-to / reference / explanation); record the leading one, and let §0 of the linked file settle precedence rather than forcing an either/or. The genre drives the first-draft section list and the 正文/证据 split, and narrows which diagram forms are candidates — it never mandates a fixed set of diagrams. `deliverable-doc-genre-skeletons.md` owns genre classification, the cross-genre form rules, and the 方案/架构 skeleton, and routes 调研/现状 to their own owners; take all of that from there rather than restating it here (调研 executes under `multi-perspective-research`, 现状 under `requirement-baseline`). |

Rules:

- **Classify each mid-stream ask against the charter instead of appending reactively.** A new request is either in-charter (edit in place), a charter change (re-confirm the charter first, then restructure once), or out-of-scope (park it). Appending every ask as a new section is how a deliverable doc accretes into an unreadable monolith.
- **A second direction-level correction within one doc effort is the charter-not-locked signal**: stop drafting, lock the charter with the reader-owner (one short structured question), then restructure once against it. Continuing to patch per-correction after that signal produces compliant-but-shapeless output — the same failure class as the premise-rejection guard in `SKILL.md`, one level earlier.
- **Global revision precedes local polish; the order is not reversible.** 判据是本轮在改「说什么」（命题、结构、证据、分册归属）还是「怎么说」（措辞、格式）——只要还在改前者，就不进润色轮：命题或分册未定时做的润色会被下一次结构变更整段推翻，账上记成润色轮，实际是修订轮。这也是 charter 与 Genre 两格必须先锁的原因。**反过来不成立：润色本身就是多轮收敛的，反复润色不等于实质未定。**一致性与口径漂移、跨节重复、密块、元语自证等是**逐位置**缺陷，每一遍改动都可能重新引入前一遍已清掉的类；类目、判法与多轮节拍归 `SKILL.md`（DELETE / FORM / closeout），此处不复述。判据是**实质的状态**，不是本轮请求的措辞：命题 / 结构 / 分册归属尚未定 → 仍不进润色轮，回 charter/Genre（即使本轮只被要求改措辞）；实质已定而同类缺陷仍有残留 → 那是执行覆盖问题，按 closeout 补，不因为「又要润色一遍」退回 charter。
- The charter is a drafting gate, not a substance owner: substantive decisions still come from the user or the owning skill; the charter only fixes who/what/where/how-long so later asks can be classified.
- Without a budget, growth restraint does not survive multi-round pressure — set the length budget at charter time and enforce it at each round's closeout, splitting overflow to child pages instead of raising the cap. Splitting stays inside the doc-set authority rule in `SKILL.md`: for a no-owner deliverable doc the reader-owner agrees the split (structure decision, not self-authorized); for spec/standards/guideline families the doc set is owner-settled — flag a split candidate, do not split.
