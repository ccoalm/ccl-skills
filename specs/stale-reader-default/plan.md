# A stale reader turns a new value form into the absence default

## Problem

A client editor's alignment control moved a box to the wrong place. It computes the target position from the box's size, which a reader returns as a fraction parsed from a percentage. That reader treats every other form as "not set" and returns the default the renderer applies when no size is declared. Its comment says the writer only produces percentages.

Two later fixes made that comment false:

1. The first fix deliberately stored a content-sized keyword for some boxes. Its commit edited the file that holds the reader, and its plan lists no readers of the field.
2. The second fix added a pixel unit and placement from the opposite edge. It introduced a new geometry model and moved two of the field's three consumers to it. The alignment control, the last consumer of the old numeric size, stayed on the old reader.

The result: a declared keyword or pixel size reads as 100%, so centre, end and far-edge alignment write 0. A size that is not declared is correctly read as the default. Only a declared value the reader could not interpret got that default.

Over the next two days the product's history shows about six follow-up fix commits whose subjects each handle the new forms in one more reading or editing path (counted from commit subjects; the diffs were not all read). One of them fixed this exact class in a sibling panel, which also fell back to the defaults, and did not check the field's other readers. The alignment case is the one that reached acceptance testing.

The two fixes and the sibling-panel fix all went through `defect-diagnosis`, the web stack skill, `testing-strategy` and `code-review`, according to the product's own owner-dispatch record.

## Result class

failure/correction: an escaped defect found in acceptance testing.

Disconfirming observation: the result would be an application gap rather than a missing rule if any ccl rule on that path already required listing readers when a fix widens the values stored in a field whose type does not change. No such rule was found (see Coverage).

## Root cause, widened

| Factor | Category | Counterfactual |
| --- | --- | --- |
| `defect-diagnosis` Phase B says to preserve contracts unless the task requires a change, and says nothing about what is owed when the fix does change one | missing control at the decision point | A required reader list at this point would have listed the alignment control: removes the failure |
| The field's type did not change, so neither the compiler nor a search of the writer's callers reaches a reader that parses the stored value by name | missing mechanical signal | Explains why diligent work missed it; not removable |
| The reader's "writer only produces X" comment recorded an assumption the first fix broke | stale process model | A rule that treats such a comment as a broken contract makes it a search hit |
| The reader returned the absence default for a declared value it could not parse | latent condition | Returning unknown would have turned a wrong write into a no-op: reduces severity |
| The same-class fix in a sibling panel did not check the field's other readers | detection gap | A sibling sweep at that point would have found the alignment control |
| Review sees the diff; the stale reader was outside it | review limit | A review checklist item alone cannot fix this; the obligation belongs to the implementer |

## Lesson verdicts

| Candidate | Verdict | Reason |
| --- | --- | --- |
| 1. A new declared form for a property requires listing and migrating or guarding every reader; a "writer only produces X" comment is a broken contract | Holds; landed | Not covered in-repo for a type-stable widening during fix or feature work. Existing rules cover only cross-repo fields (`testing-strategy` cross-repo field checklist), protobuf enums (`go-microservice-architecture`), and call-site search for refactors (`refactoring-discipline.md`). |
| 2. A reader represents "unknown" for a declared value it cannot interpret and never substitutes the absence default | Holds; merged into the same rule | This is the "guarded" disposition from lesson 1, not a separate firing point. Existing stack-specific instances (unknown enum values, presence semantics, "unset" vs zero in tests) do not state it for readers in general. |
| 3. When a new model replaces an old one for some consumers, track the rest or add a guard test | Rejected as a separate rule; folded into 1 | The old model's remaining consumers are readers of the same field, so the list from lesson 1 includes them. Partial migration outside a value change is already covered by `refactoring-discipline.md` (keep old readers working until migrated; a compatibility shim until every caller moves). |

Recurrence: about six same-class fixes in one product over two days, each found piecemeal. The class is not specific to that stack: any string, number or enum field that gains a keyword, unit or member has the same shape, which none of the compiler, the type checker or writer-side search can see.

## Landing

One rule, two firing points:

| Owner | File | Role |
| --- | --- | --- |
| `product-rd-workflow` | `references/refactoring-discipline.md`, Data Shape Changes | Canonical rule. The scope sentence now says Impact Analysis and Data Shape Changes also apply to fixes and features. |
| `defect-diagnosis` | `SKILL.md`, Phase B step 1 | Hook at the decision point all three escapes passed through, plus a sibling-reader check when the verified cause is one reader. Kept under the entrypoint word budget; detail points to the canonical rule. |

Target-output map:

| Owner | Direction | Status | Reason |
| --- | --- | --- | --- |
| `defect-diagnosis` | fix path | updated | Phase B hook |
| `product-rd-workflow` | data-contract owner | updated | canonical rule in `refactoring-discipline.md`; `SKILL.md` untouched (entrypoint in severe size debt) |
| `product-rd-workflow` `code-review-checklist.md` | review | unchanged | the reviewer sees only the diff; the obligation and its record sit with the implementer |
| `testing-strategy` | tests | unchanged | the canonical rule owns the per-reader test; `testing-strategy` already sweeps tests that pin old behavior and owns the cross-repo field checklist |
| `web-react-dev`, `app-cross-platform-dev`, `miniapp-product-dev`, Go/Python/Node.js dev skills | sibling stacks | unchanged, routed to shared owner | stack-agnostic rule |
| `go-microservice-architecture`, `python-service-architecture` | contract architecture | unchanged | protobuf unknown-enum and presence rules are the wire instances of this class |
| `code-review` | review mechanics | unchanged | no new review dimension |
| `skill-extraction-workflow` | this workflow | unchanged | a product-code lesson from a product defect, not from an extraction, routing or retrospective miss |

Example-domain pre-selection: the new text gives `auto`, unit, enum member and variant as forms, and null, an `unknown` state and a disabled control as unknown representations. Wording from the source's own domain (layout geometry) was rejected. The behavior tasks use a job scheduler.

## Behavior evidence

See `evidence/behavior-eval.md`.
