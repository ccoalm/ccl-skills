# Diagnostic Spec-Match Gate

Use this reference before any current-state/spec-match judgment or change recommendation when the request combines:

- A diagnostic verb, such as 检查, 评估, 审视, 是否满足, 对不对, check, evaluate, does this match, is this correct, or audit.
- A spec-match semantic, such as 是否满足, 对齐, 符合, 按需求, 当前逻辑是否, matches the requirement, or per the spec.

Standalone "看看 / look at this" without spec-match wording is ordinary code reading, not this gate.

## Required Checks

1. **Identify the evaluation baseline source** — ask explicitly "对应的产品文档 / PRD / wiki / issue 在哪里？" unless one of these applies:
   - The user already provided the link in this message.
   - The user explicitly said "没有文档 / 我临时定的".
   - The request is pure technical refactor with no business rule semantics.
   - The user explicitly directed "按我这句话做 / 不要查外部文档".

   When using the user's statement as the baseline, record it as `user-provided baseline` with a one-line risk note.

2. **Numeric threshold dimension check** — when the diagnostic mentions a numeric threshold such as N items, X%, or Y seconds, verify the business-entity dimension it binds to in the authoritative source. Similar-looking thresholds can bind to different entities, such as result-count, input-count, or display-count. Compare against any existing same-named constant in code before assuming reuse.

3. **Reverse-trace intentional-design signals** — when code comments, test descriptions, or variable naming carry product-domain semantics such as domain fallback, carry-forward fallback, or domain-specific thresholds, reverse-trace to the authoritative spec before treating them as implementation complexity. Do not delete or simplify such signals until traced, or until explicitly marked unverified with the user.

4. **Option neutrality when proposing changes** — label a "Recommended" option only when tied to a named baseline, risk, or cost. Do not rank options by the agent's own simplicity bias when one alternative aligns with the authoritative spec.

## Failure Shape Prevented

This gate prevents an agent from reading code, comparing it against the user's single-utterance description, silently substituting one business-entity dimension for another, deleting a spec-mandated fallback as "implementation complexity", presenting an option matrix where the spec-aligned choice is labeled the most complex, and shipping a regression that contradicts the authoritative product spec.

## Closeout Evidence

Record the baseline source in working notes before the diff lands:

- `link`
- `user-provided baseline`
- `none-confirmed`
