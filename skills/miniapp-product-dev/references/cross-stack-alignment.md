# Cross-Stack Alignment

Use this reference when the mini-program is one of several client stacks (web desktop, H5, native app, mini-program) sharing one product/brand. It enumerates the **scope** of what must align across stacks — beyond color tokens and the logo — so the mini-program implementation can call out misalignment instead of silently diverging.

This reference owns the **enumeration of alignment surfaces** the mini-program must check. The actual design rules (token system, voice/tone, brand assets) are owned by `product-ui-ux-design/references/multi-stack-strategy.md` and `multi-project-token-consistency.md`. This file maps what mini-program-side implementation has to verify against those design sources.

## Alignment surfaces

### Visual / brand layer (design source of truth)

Owned upstream by `product-ui-ux-design`; verified here that the mini-program implementation reflects the source faithfully.

| Surface | Aligned across stacks | Mini-program-side check |
|---|---|---|
| Color tokens | Primary, neutral, semantic (success/warning/error/info), surface tiers | Are mini-program theme variables sourced from the same token set, not redrawn locally? Inspect ALL of the host-platform theme entry points before concluding: (1) global theme slot (`app.json` `themeLocation` + `theme.json` for WeChat, equivalent for Alipay/Douyin/Baidu/QQ); (2) subpackage-local theme files when subpackages override; (3) generated WXSS / CSS-variable token injection (Taro / uni-app / native build-time token transform); (4) cross-framework token imports (`@import "tokens.scss"`, Taro `App.scss` token modules); (5) rendered primary on a real page in the host devtools or device. An empty / absent global `themeLocation` is a **detection signal that triggers the deeper inspection**, not a standalone verdict — a compliant mini-program may legitimately inject tokens through (2)–(4) without using the global slot. Fail only when all five layers fail to deliver the brand token; that case is the mini-program equivalent of the "empty framework-wrapper theme config" cross-stack anti-pattern in `product-ui-ux-design/references/multi-project-token-consistency.md`. |
| Typography scale | Font family per language, size scale, weight scale, line-height scale | Verify mini-program text sizes map to the same scale even when host renders `rpx` differently. |
| Spacing scale | 4/8 (or project's chosen) grid; standard component padding/margin tokens | Check that mini-program component padding matches the token, not the framework default. |
| Iconography | Source set, sizes, stroke weight, on-brand exceptions | Verify the mini-program's icon font/SVG set is the canonical set, not a host-specific replacement. |
| Logo / wordmark / app icon | Per-host packaging (square/round, light/dark, sizes) | Verify the mini-program app icon and within-app brand mark match the brand asset library. |
| Imagery / illustration | Brand style, photography vs illustration boundaries | Verify hero / empty / error illustrations match the cross-stack set. |
| Motion / transition | Duration scale, easing, when motion is used vs suppressed | Verify mini-program transitions match the cross-stack pattern; do not adopt host-default-only animations. |

### Voice / copy / vocabulary layer

Subtle, high-leakage misalignment surface. The product feels "off" when the same action has different copy across stacks.

| Surface | What aligns | Mini-program-side check |
|---|---|---|
| Action verbs | "保存 / 提交 / 确认 / 完成" — pick one verb per action class | Mini-program does not use a different verb for the same action than web/app. |
| Error vocabulary | "未登录 / 登录失效 / 无权限 / 网络异常 / 服务器繁忙" — fixed strings | Mini-program error toast/dialog copy comes from the same string library. |
| Empty-state copy | "暂无数据 / 还没有内容 / 即将开始" — chosen tone | Mini-program empty states match the cross-stack tone, not a generic host default. |
| Trust / safety copy | Payment confirmations, account-delete, data-collection consent, share-attribution copy | Identical or controlled paraphrase across stacks; legal review confirms every variant. |
| Privacy disclosure | Phrasing of what is collected, why, how to revoke, data-deletion path | Same language across stacks (legal liability is shared). |
| Brand voice | First-person vs second-person, formality, English/Chinese mixing rules | Mini-program follows the cross-stack guide. |
| Terminology / domain nouns | One canonical name per domain object (e.g. "工单" vs "任务" vs "事项") | Mini-program uses the same noun the web/app uses; no host-specific synonyms. |

### Interaction / navigation layer

Each host has its own primitives; alignment is about **mental model**, not pixel-identical UI.

| Surface | What aligns across stacks | Mini-program adaptation |
|---|---|---|
| Primary navigation labels | Tab/menu labels and order across stacks where the product surfaces are equivalent | Mini-program tab labels match web/app top-level concepts; reorder only when host UX strongly favors a different order, and document the divergence. |
| Auth / onboarding flow | Identity model (phone / wechat / email), bound-account semantics, first-login setup steps | Mini-program login path produces the same `user_id` + permissions as web/app login; one user, one identity across stacks. |
| Account / profile structure | Account settings hierarchy, privacy controls, security actions, account deletion | Mini-program "我的"/profile surfaces match the cross-stack list; do not silently omit privacy/legal/about routes. |
| Payment / order flow | Steps (review → pay → result), pending/cancel/success copy, support-id surfacing | Mini-program payment screens follow the same step model; the receipt looks like the same brand's receipt across stacks. |
| Share / deep-link payload | **Opaque token** issued by backend, bound to `(audience, platform, route, action, target, target-tenant, issuer-user, issuer-tenant, redeemer-permission-scope, expiry)` — the issuer principal + tenant must be recorded so the redeemer's permissions are checked against the issuer's authorization at redeem time, not just at issue time; multi-tenant target IDs may collide across tenants, so target-tenant is part of the binding; `issuer-vs-redeemer` semantics are explicit (e.g. invite tokens are issued by one user for another to redeem; capability tokens are issued for the same user to consume on a different channel). The backend exchanges the opaque token for the resolved target after verifying redemption-context channel + redeemer eligibility + issuer permission still valid. | Mini-program redeems share tokens through the backend; rejects tokens whose channel / target-tenant / issuer-permission no longer matches; does not assume issuer-user == redeemer-user. |
| Notification / push contract | Topic/template names, channel mapping, opt-in/opt-out model | Mini-program subscribe-message templates map to the same notification topics web/app use. |
| Error / recovery paths | "What did the user see when X failed and what do they do next" | Mini-program error screens offer the cross-stack-equivalent recovery (retry / refresh / re-login / contact support). |

### Data / contract layer

Below the visible UI, alignment means same backend identity, same business semantics, same audit trail.

| Surface | What aligns | Mini-program-side check |
|---|---|---|
| User identity | Same `user_id` + tenant resolution rules across stacks | Mini-program session resolves to the identical user/tenant; no host-specific identity. |
| Permissions model | Same scope/role/feature-flag dimensions | Mini-program reads from the same permission service; no client-side permission table. |
| Tracking event names | Same event name per action across stacks; platform dimension is a tag, not a different event | Mini-program analytics emits `<event>` with `platform=miniapp/<host>`, not a renamed event. |
| Error class taxonomy | Same error codes / classes mapped across stacks | Mini-program maps host errors into the cross-stack class set. |
| Locale / i18n | Same locale set, same translation keys, same fallback chain | Mini-program reads from the same i18n source. |
| Time / formatting / currency | Same date/time/number/currency formats per locale | Mini-program formatters use the shared utilities, not host defaults. |

### Compliance / legal layer

Cross-stack alignment here is not aesthetic; misalignment is a regulatory risk.

| Surface | What aligns | Mini-program-side check |
|---|---|---|
| Privacy policy text | **Canonical base policy** (the cross-stack truth) **plus per-platform annex** (host-specific SDKs, host-specific permission disclosures, host-specific data-collection requirements that the canonical base does not name), each annex versioned. | Mini-program review matrix checks both the base policy version AND the platform-specific annex; the per-platform annex covers what the host platform's review will ask about. |
| User agreement / ToS | Same document, same versioning | Mini-program accept-flow records same version. |
| Data-collection consent | Same matrix of fields × purposes × opt-in mechanism | Mini-program collects only what the cross-stack matrix permits. |
| Account deletion / data export | Same path, same SLA, same evidence | Mini-program account deletion produces the same data lifecycle as web/app. |
| Minors handling | Same age gate / parental consent flow | Mini-program implements the same gate; do not relax it because the host happens not to enforce. |
| Region / regulatory carve-outs | Per-region rules (PIPL / GDPR / CCPA / India DPDP / etc.) | Mini-program respects region-specific behavior the cross-stack policy declares. |

## Alignment check ritual (mini-program-side)

Run this before declaring a mini-program release ready when it shares a brand with another stack:

1. List the alignment surfaces this release touches.
2. For each, name the **cross-stack source of truth** (Figma project, design tokens repo, copy library, i18n keys, privacy doc URL, analytics event registry, identity service).
3. **Run the design-source health check before consuming a design source**: see `product-ui-ux-design/references/multi-project-token-consistency.md` → "Design-Source Health Check (Pre-Consumption Gate)". The check covers five failure classes — undeclared third-party mirror / vendor-derived source, drift inside one source, unresolved placeholder values in a shipped semantic tier, no source provenance, no versioned snapshot. If the design source fails the gate, **scope the block to the affected token classes the mini-program release would consume** (an unrelated unresolved-semantic-tier finding does not block a release that consumes none of the broken roles); copying a broken source into the mini-program just propagates the brokenness and will surface as findings during cross-end review. The escape valve described in that reference (time-boxed provisional consumption with design owner + risk owner approval, pinned source version, "not fully aligned" label, expiry date) applies here too.
4. For each, confirm the mini-program implementation reads from / matches that source. "Reads from" does not require runtime fetch on cold start — generated versioned snapshots (built at release time, shipped in the package, validated by source hash + drift check in CI) are acceptable. The discipline is **no silent drift**, not "must call the source at runtime".
5. Capture screenshots / sample copy / event sample for each touched surface; compare against web/app equivalent.
6. Record any **intentional divergence** with rationale ("this is the host-platform convention; we adopt it for X reason"); the cross-stack design owner approves the divergence.
7. Land cross-stack alignment as a release checklist item, not as an afterthought QA pass.

## What this skill does NOT decide

- The token system, voice guide, or brand asset library — owned by `product-ui-ux-design`.
- The backend identity / permission / event taxonomy — owned by backend skills.
- The product strategy of which stacks to ship — owned by `product-rd-workflow`.
- Per-stack design language deviation — that's a design judgment; this file just makes the deviation explicit so it isn't accidental.
