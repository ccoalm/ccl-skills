# Framework Choice

Use this reference when deciding whether **Taro** is the right framework for a new mini-program project, or whether to migrate an existing project to a different framework. The skill's default is Taro; this file documents how to test that default against a specific project.

## When to re-evaluate

Re-evaluate framework choice when any of the following changes:

- Target host platforms expand or contract (e.g. dropping WeChat or adding Douyin/Baidu changes the multi-target gain).
- Design system diverges per host beyond what tokens can absorb (each host needs distinct interaction idioms).
- The shared monorepo's web/React + mini-program code coupling becomes painful (drift, branching, runtime bugs).
- Build-time, package-size, or cold-start budgets become release-blockers.
- The team's React/TypeScript expertise no longer matches the runtime (e.g. team migrated to Vue, or the React layer is mostly read-only).
- Taro / underlying framework has a material breaking change (Taro 3 → Taro 4 class of event) and migration cost is non-trivial.
- Host platform releases a substantial native feature (e.g. WeChat Skyline) that the multi-platform framework lags on.

A framework decision is not permanent. Annual or release-train review is healthier than waiting for a forcing event.

## Decision factors

Compare candidates along the dimensions below. No single dimension wins; the **combination** does. Score each candidate `strong / acceptable / weak / blocking` against the project's actual needs (not against the abstract framework).

| Dimension | What it asks |
|---|---|
| Target-platform set | How many hosts must this project ship? One host = native often simpler; 2+ = multi-platform framework usually pays. |
| Shared-code gain | What fraction of code (component, state, business logic) realistically reuses across web/app/mini-program? If the shared layer is small, multi-platform framework cost > gain. |
| Team stack fit | React/TypeScript (Taro, Remax) vs Vue (uni-app) vs none (native). Hiring/replacing matters more than founder preference. |
| Component-library maturity per target | Does the candidate's UI-kit family (taroify, NutUI-Taro, tdesign-miniprogram, uni-app uView, etc.) actually look like the design needs, or will every component be wrapped/overridden? |
| Host-feature lag | When WeChat / Alipay / Douyin ships a new capability, how quickly does the framework expose it? Multi-platform frameworks usually trail native by weeks to months on novel features (Skyline, new pay flows, new permission models). |
| Build / package-size cost | Multi-platform frameworks add runtime weight; native does not. Tight package-size budgets favor native. |
| Cold-start performance | Native is usually fastest; Taro's emulated runtime adds startup work that matters on low-end devices. |
| Debugging / runtime opacity | Multi-platform frameworks add a layer between your code and the host runtime. Bugs that fail at the framework boundary are harder to diagnose than native bugs. |
| Migration / exit cost | If the team has to leave this framework in 2-3 years, how painful? Native code is more portable than framework-bound code. |
| Ecosystem and maintenance signal | Is the framework actively maintained? Release cadence, issue-response time, contributor depth, last major release date. A stale framework is a hidden cost. |

## Candidate sketches (decision context, not endorsement)

These are framework facts the team should re-verify against current docs and project needs before deciding. Do not adopt them as conclusions.

- **Taro**: React/TypeScript, broad multi-target (WeChat / Alipay / Douyin / Baidu / QQ / H5 / RN). Strongest fit when (a) a React web project shares substantial business logic with the mini-program, (b) the team is React-first, (c) two or more host platforms must ship, and (d) the design system is consistent across hosts. Weakest fit when target is single-host with tight package-size budget, or when novel host capabilities (new pay flows, Skyline) are on the critical path.
- **uni-app**: Vue-based, broad multi-target including native app via uni-native. Strong fit for Vue-first teams or when a unified web + mini-program + native app codebase is required. Weak fit for React-first teams.
- **Native (WeChat / Alipay / Douyin / Baidu)**: simplest runtime, smallest package, fastest host-feature uptake, no framework abstraction tax. Strong fit when target is single-host or the project is small. Weak fit when 2+ hosts must ship and shared code matters.
- **Remax / kbone**: React syntax compiled to native templates (Remax) or browser-runtime emulation (kbone). Niche; verify project activity before adopting.
- **mpvue**: Vue-based, smaller scope than uni-app. Verify maintenance state.
- **Per-platform split (native per host)**: best feature uptake and runtime fit per host, worst shared-code story. Strong fit when each host's product diverges materially or when the team can staff per-host owners.

## Skyline (or any host-new-renderer) opt-in

WeChat Skyline (worklet-driven, GPU-composited renderer for single-thread interaction) and similar host-new-renderer paths are **opt-in for specific surfaces, not a project-wide default**. Skyline is WeChat-only and the multi-platform frameworks (e.g. Taro 4.0.8+ exposes worklet) trail native host releases. Adopt only when (a) high-frequency scroll / complex gesture / immersive animation / low-end-device interaction performance is a release-blocker proven by measurement, (b) the surface can be re-implemented in Skyline-compatible component subset (some legacy components and behaviors are unsupported), and (c) the team accepts the dual-renderer maintenance cost during transition. CRUD pages, financial / data forms, content-list / settings flows default to WebView renderer — migrating them yields no user-visible win.

## HarmonyOS target (Taro 4 / uni-app x) is a distinct runtime, not another mini-program build

The multi-platform frameworks added a HarmonyOS build target. As of framework docs reviewed 2026-05, Taro 4 compiles toward HarmonyOS via a C-API native-rendering path with Vite-based compilation (documented around the React DSL), and uni-app x compiles Vue + UTS toward HarmonyOS native ArkTS / ArkUI. Verify the current build command, supported DSLs (Vue parity on Taro's C-API path is not assumed), and component/API coverage against the framework docs before planning a Harmony target. Two consequences for this skill:

- **Verification matrix**: a HarmonyOS target is a separate row, not folded into "the Taro build passes". `taro build --type weapp` passing is not evidence the harmony target builds or renders — the harmony output runs on a native rendering engine, not the mini-program WebView/Skyline runtime, so supported components, lifecycle, and host-capability shapes differ. Prove it independently like any other shipped target.
- **Ownership boundary**: the HarmonyOS output is a native OS application (a Harmony app, or a separately-confirmed atomic-service), not a host mini-program. Native-app delivery concerns — Harmony app review, signing, native real-device evidence, OS-level permission model, and any separately-confirmed atomic-service packaging/review path — coordinate with `app-cross-platform-dev`; this skill stays authoritative for the shared cross-target code layer and the mini-program targets only. When one Taro codebase ships both mini-program and harmony targets, name the per-layer final-decision owner the same way the web/mini-program shared-adapter boundary is named in the SKILL.

## Decision evidence the team must collect

Before changing framework, record:

- Current code's actual shared-code ratio (lines / modules genuinely shared between web and mini-program, vs platform-branched).
- Three real defects from the past quarter that the current framework caused or hid; estimate of what each would cost on the candidate framework.
- Three real wins from the past quarter that the current framework enabled; estimate of what each would cost on the candidate framework.
- A 2-week spike on the candidate framework rebuilding one production page, including: cold-start time, package size delta, real-device test pass/fail, design-token fidelity. **Expedited path** for emergencies (host capability deprecation deadline, critical security advisory, framework end-of-life with no patch): skip the 2-week spike at risk-owner signoff, ship behind a server-side flag with a tested rollback, and run the spike post-release to validate the bet. Do not waive the spike for non-emergencies.
- Migration cost estimate (engineering weeks) with a 1.5× buffer; framework migrations always run long.
- An "exit cost" clause: if the candidate fails, what's the rollback path and timeline?

A framework switch decided on opinion or vendor demo, without these rows, is a high-risk move.

## What this skill does NOT decide

- Whether the team should use a mini-program at all vs. a web app or native app — that's a product / distribution / GTM question owned by product-rd-workflow.
- Whether to ship multiple hosts simultaneously or sequence them — that's a release-strategy question owned by product-rd-workflow.
- UI-kit choice within a given framework — **co-owned**: `product-ui-ux-design` owns the UX, token, accessibility, and brand-fit criteria; this skill owns runtime fit (package size, host-platform compatibility, framework version compatibility, build pipeline integration). A UI-kit decision requires both owners' sign-off, not either alone.
- Cross-stack alignment scope — owned by `cross-stack-alignment.md`.
