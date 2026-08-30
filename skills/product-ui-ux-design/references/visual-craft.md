# Visual Craft

Use this reference when a task involves frontend visual polish, brand feel, anti-slop review, or turning a design-system pattern into a production-quality app/web interface.

## Scope

Visual distinctiveness must live at the product and design-system level, not as one-off screen art. A product should feel recognizable, intentional, and polished across its core surfaces, whether community, finance/data, AI, operational, mobile, or web. Do not make every screen visually different just to be memorable.

This reference complements `tokens-and-components.md` and `design-execution-checklist.md`. It does not override source Figma tokens, component rules, accessibility, density, or trust/safety requirements.

## Aesthetic Direction

Before designing or coding a visible surface, state the intended visual direction in one sentence:

- What should users feel: calm, lively, premium, playful, editorial, utilitarian, intimate, or creator-focused?
- Which product behavior should the visual direction support: browsing, replying, creating, AI co-creation, moderation, or returning?
- What is the memorable product-level trait: recognizable content cards, expressive creator identity, calm AI assistance, refined topic spaces, or trustworthy moderation?

Rules:

- Commit to a coherent product-level visual language and reuse it across surfaces.
- Use boldness intentionally. A consumer feed can be expressive; moderation, settings, analytics, and account surfaces should usually be quieter.
- Distinctiveness should come from typography hierarchy, color rhythm, interaction polish, content treatment, and consistent details, not random decoration.

## Differentiation And Coherence

Coherence is the baseline, not the finish line. A fully coherent system can still look like every other product in its category — every competitor can be internally consistent and mutually interchangeable. Coherence keeps the product category-literate; deliberate risk is what gives it its own face. **Precedence:** design-system tokens, accessibility, semantic status colors, trust/safety, high-risk-flow conventions, and rendered-evidence gates all outrank differentiation — the rules below apply only to what remains after those are satisfied, where "satisfied" means recorded through the owning checkpoint or gate with evidence, not self-asserted. An unknown or unchecked gate is not satisfied; treat it as blocking.

- **Name one product-quality anchor first.** State the single thing a first-time user should take away. For brand or consumer surfaces this is often a memorable visual signature (a feeling, a posture); for utilitarian, internal, or high-trust tools it is more often speed, scannability, confidence, recoverability, or quiet consistency. Every aesthetic decision should serve that anchor without weakening usability. A design that tries to be memorable for everything is memorable for nothing.
- **Differentiate with deliberate, costed risks — never on the safety-critical layer.** Beyond the category-baseline safe choices users already expect, take one or two intentional departures (an unexpected typeface, a non-semantic accent peers underuse, denser or looser spacing, a grid-break, a motion signature), each staying inside the accessibility baseline (readability, target size, focus/reading order, reduced-motion, long-content, responsive stress). For each, state what it gains and what it costs; an unjustified departure is noise, not identity. On any safety-, trust-, privacy-, or compliance-sensitive surface — money/quota, auth/account/session, permissions, user/tenant data, moderation, destructive/public/external-visible actions, AI disclosure, error/retry/recovery, audit, and anything the skill's risk tags (see `feature-risk-router`) flag — convention is the safety mechanism: do not differentiate by altering semantic colors, status treatment, critical control placement, confirmation patterns, readability, or recovery conventions. Differentiate only in surrounding brand tone or non-critical polish.
- **Coherence is a system property: re-validate on every override.** When the user or a later iteration changes one axis, re-check that the others still cohere (an expressive aesthetic paired with timid motion, a bold palette with no supporting decoration, an editorial layout on a data-dense surface). Nudge gently and offer a fitting alternative. For aesthetic-preference tradeoffs the user's final choice wins (recommend, do not decide) — but only among options that already pass the precedence gates above; a preference never converts a failing accessibility, trust/safety, privacy, compliance, semantic-status, or rendered-evidence gate into "accepted" (record blocked / handoff per the owning gate instead).
- **Avoid unreasoned convergence to generic defaults.** Do not re-reach for the same generic safe default across iterations without a reason, and note the subtle trap that the well-known "safe alternative" to an overused default (font, layout, accent) is itself a generic default. A design-system, platform, or accessibility default is itself a sufficient reason — challenge only habit-driven defaults outside those systems, and record the reuse reason rather than invent novelty. Changing established product/design-system tokens or component semantics goes through the design-system source-of-truth path (`tokens-and-components.md`, `design-system-source-of-truth.md`), not front-end-only churn.

## Anti-Slop Checks

Avoid generic AI-looking frontend patterns unless the product's own design system explicitly requires them:

- Purple/blue gradients on white backgrounds as the default visual identity.
- Repeated three-column feature grids with icon-in-circle, bold title, and two-line description.
- Decorative icons inside colored circles used everywhere.
- Decorative blobs, waves, or geometric shapes that are not part of the product's own design language.
- Emoji used as generic UI iconography or section decoration in place of consistent icons — unless emoji are the product content, user-authored or reaction vocabulary, or an established design-system semantic.
- Stock-photo placeholder blocks, generic/fake testimonial sections, or the cookie-cutter left-text / right-image hero used as a default layout — real sourced proof and a deliberate split hero are fine when justified by the design checkpoint.
- Filler CTA labels such as "Get Started" / "Learn More" that do not name the actual action.
- Lorem ipsum or "your text here" as readable user-facing copy in shipped, review, or acceptance surfaces — use real or realistic content from the spec/source. Loading/skeleton states are still required, but use inert skeleton geometry or localized loading text, not lorem; non-user-facing component-demo fixtures are exempt.
- Center-aligning most headings, body text, cards, and action groups.
- Applying the same large border radius to cards, buttons, inputs, tabs, and containers.
- Generic marketing copy such as "unlock the power", "all-in-one solution", "revolutionize", or "streamline your workflow".
- Defaulting to neutral system-like typography without a deliberate brand reason.

Design-system typography roles count as a deliberate brand reason when they already encode the product's intended voice.

If a pattern appears in a Figma source, preserve it only when it has a clear product purpose or established token/component role. Do not amplify source artifacts into a generic template.

## Typography

- Use the design-system typography roles first.
- Give major brand/product surfaces a clear display rhythm, but keep feed body text, comments, notifications, forms, and moderation text highly readable.
- Do not introduce a new font family unless the product needs a brand move and implementation can load it reliably.
- Avoid more than two primary font families in a product surface unless the design system already supports that.
- Keep heading hierarchy meaningful; do not use large type to compensate for weak layout structure.
- **不同字号文字并列时按 baseline 对齐**（不是 center align）— 同行混排数字+标签 / icon+文字时基线对齐让视觉读得整齐；center align 在字号差大时会产生"漂浮"感。
- **Line-height 与 font-size 成比例**（小字 line-height ratio 大、大字 ratio 小）— 通常 body 14-16px 用 1.5、heading 32px+ 用 1.1-1.2；line-height 不该全 product 一个固定 px。
- **彩色背景上默认不用 neutral grey 做 de-emphasis**：层次首选同色系亮度变化（lighter / darker tint of the bg）；neutral grey 在彩色 bg 上常 contrast 失败且失去 grey 的层次语义。例外：token 化的 warm/cool grey 经 contrast 测试通过可用。
- Typographic micro-craft (apply unless the design system already encodes its own): build the size scale on a consistent ratio (a major-third 1.25 or perfect-fourth 1.333 step is a common starting point), not arbitrary per-screen sizes; keep prose/body measure roughly 45–75 characters per line (~66 comfortable) — this targets reading columns, not data tables, code, dense forms, or dashboards; do not skip heading levels for visual size (don't jump `h1`→`h3` — pick the right size for the chosen level); use real typographic characters (curly quotes, a real `…` ellipsis glyph) in human-facing editorial copy, not in code, logs, CLI text, identifiers, or ASCII-constrained files; use proportional numerals in prose and reserve `font-variant-numeric: tabular-nums` for numbers that align in columns, counters/timers, or metrics that update in place.

## Color And Theme

- Use semantic tokens before raw colors.
- Let one primary color family lead and use sharp accents sparingly for interaction, AI, trust/safety, or creation moments.
- Avoid timid, evenly distributed palettes where every module has the same visual weight.
- Preserve Light/Dark mode behavior where the surface supports it.
- Trust, warning, danger, moderation, and AI provenance colors must remain understandable and accessible.
- **Never encode actionable meaning by color alone** — status, error/risk, selection, comparison, or a required category distinction must pair color with a label, icon, shape, position, or pattern so color-blind users (≈8% of men have red-green deficiency) and grayscale contexts still read it; avoid a red-vs-green-only distinction. Purely decorative/brand tint may stand alone when losing the color would not change understanding or action.
- Dark mode is a redesign, not a lightness inversion: resolve text/surface/border/accent/status from tokenized Light + Dark pairs in the design-system source (no Dark pair = no dark-mode claim); separate surfaces by **elevation** (lighter = higher) rather than flipping lightness; prefer softened near-white body text over pure `#FFF` and validate WCAG contrast per surface/elevation (a single fixed near-white can fail on mid-dark surfaces); tune accent saturation per role so saturated colors don't vibrate on dark surfaces, without mechanically desaturating brand/status colors; and declare `color-scheme: dark` (or `light dark`) once the controls/tokens are actually themed, so supported form controls, scrollbars, system colors, and the page canvas render consistently.
- Before introducing or substantially reshaping a screen, state the visual direction: typography source, primary token, neutral/background scale, radius/shadow role, and which values come from the existing theme. If the existing theme is weak or no strong reference exists, compare two or three compact visual directions instead of styling from habit. When alternatives are genuinely useful, make them **meaningfully different on the variables left after the Precedence gates** — hierarchy, density, surface/material treatment, attention model, and (where not token-fixed) type pairing or color temperature; you need not vary every axis, and never change design-system typography roles, component semantics, semantic-status colors, contrast, or accessibility behavior just to look different. If one direction is clearly product-correct, or the surface is utilitarian/high-trust and should reuse the existing visual language, state that instead of inventing filler options. Direction swap-test: with the same content and constraints, if two options share the same hierarchy, density, token rhythm, component emphasis, and attention model, merge them or replace the weaker one.

## Motion And Interaction Polish

- Use motion for high-value moments: first load, feed refresh, publish success, AI generation, upload progress, notification arrival, or trust-state transition.
- Prefer one coherent motion system over scattered decorative micro-interactions.
- Motion must not block reading, replying, moderation, publishing, or recovery actions.
- Provide stable hover, focus, active, disabled, loading, selected, and error states for interactive elements.
- Respect reduced-motion and low-performance contexts when implementation supports them.

## Spatial Composition

- Consumer relaxed surfaces can use more breathing room, visual rhythm, and atmospheric detail.
- Productive compact surfaces should favor density, scanning, sticky controls, and predictable alignment.
- Use asymmetry, overlap, or grid breaks only when they improve orientation or brand feel without harming readability.
- Keep long content, metadata, badges, tags, and action groups from overlapping or pushing primary content out of view.
- Text containers should have readable line lengths; avoid full-width paragraphs on desktop.
- **Classify the surface archetype by region, not by page.** One page usually mixes archetypes — marketing/story, app/workbench, dashboard/analytics, onboarding/auth, trust/safety, docs — and each follows different composition rules. Marketing/story: brand-first hierarchy, the first viewport reads as one composition (a poster, not a document), one job per section, and cards earn their role — a card should group or enable something (pricing, comparison, proof), not just tile content into a generic grid. App/tool/dashboard: calm surface hierarchy, dense but readable, minimal chrome, one accent, navigation and status legible over decoration. Any region with live data, controls, or status takes app/tool composition plus the required-state and trust rules even inside a landing page.
- **Subtraction is the default — after inventorying what is required.** Before cutting, map the required states (loading/empty/error/success/partial), accessibility affordances, and trust/provenance cues; only decorative or redundant elements are eligible. Within that eligible set, if an element does not earn its pixels, cut it and fix visual noise by removal before addition — decorative card grids, redundant headings, and chrome that competes with the primary task go first. Required states, accessibility affordances, and trust cues are never "chrome".

## Backgrounds And Details

- Background treatment should clarify product mood or depth; it should not compete with content.
- Use texture, layering, shadow, glass, patterns, or atmospheric detail sparingly and consistently.
- Do not add decorative effects that reduce contrast, scroll performance, or mobile clarity.
- Cards and panels should not all look equally loud. Establish a hierarchy between feed content, side panels, AI, and system messages.

## Acceptance Questions

These questions contribute visual-craft criteria; they cannot mark a runtime slice ready or complete. Evaluate them on every affected rendered layer and bind the resulting evidence through the complete design/test/producer/client set and design verdict in `delivery-contract.md`.

Before calling client visual work polished, ask:

- Does the screen have a clear product-level visual point of view?
- Does it avoid generic AI frontend patterns?
- Does the visual direction support the target product loop instead of distracting from it?
- Are typography, color, spacing, radius, motion, and background choices tied to existing tokens or an explicit product reason?
- Does the surface remain readable, accessible, and performant across the supported sizes, host modes, input/capability modes, and adaptation matrix of every affected client—not only Mobile and desktop Web?
