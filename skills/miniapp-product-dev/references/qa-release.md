# QA Release

Use this reference for miniapp verification, platform review, release, and rollback.

## Local Verification

- Run repo formatter, lint/typecheck, unit/component tests, and the relevant miniapp build.
- Compile in the platform developer tool or framework build target.
- For visible changes, inspect the rendered page in developer tools, preview build, or real device.
- Verify at least the primary route entry, loading, success, one error/retry path, and one auth/permission state if relevant.

## Platform-Specific Evidence

For every **shipped** host platform (a platform actually included in this release), compile + developer-tool/real-device evidence is blocking. "Recorded as unverified" is only acceptable for targets that are NOT in this release's shipping set — and the release notes must say so. Do not ship a target on the strength of "another target compiled".

- WeChat: developer tool compile/preview, real-device preview or experience build for platform capabilities, app id/env sanity.
- Alipay: IDE compile/preview, capability sandbox where available, app id/env sanity.
- Douyin/TikTok/Baidu: platform IDE compile/preview and real-device checks for capabilities that differ from web/H5.
- Multi-platform frameworks (Taro / uni-app / Remax / kbone): the build matrix declares which targets ship in this release; each shipped target carries its own evidence row.

## Real-Host Flow Template

Use a real host client or real device when the behavior depends on host completion state that developer tools cannot prove, such as streaming finality, phone/login authorization, plugin permissions, native bridge callbacks, share/scene entry, payment/subscription finality, or host-rendered recovery states.

For WeChat mini-programs, keep a reusable checklist in the project repository and fill in the project-specific values:

- Entry: search the mini-program by its exact name in desktop/mobile WeChat, scan a QR code, or open a shared mini-program card.
- Minimal input: perform the smallest real user action that exercises the changed capability.
- First evidence: confirm the request/action visibly starts, such as first token/chunk, loading state, authorization prompt, or host callback.
- Final evidence: wait for the true terminal state, such as streaming closed and input restored, authorization completed/failed with readable error, payment/subscription finality, route restored, or retry path shown.
- Artifact: capture screenshot, recording, logs, preview/run id, and the filled project checklist row.
- Human-assisted host test: when the available real host is a human operator's logged-in client or device, record observer role/source class, sanitized account class or role used, host client/device and version when visible, entry path, exact actions, redacted artifacts captured, state changes requested (login, logout, permission prompt, account switch, storage clear), restoration outcome, and privacy redactions applied. Do not write personal phone numbers, personal operator names, chat/contact handles, tokens, private account names, reviewer credentials, or raw chat/contact details into shared reports.

Human-assisted evidence is manual and scenario-scoped. Do not use it as proof that automated checks, full E2E, or other runtime paths passed. If requested logout/account-switch/storage/permission restoration is not confirmed, record `blocked: restoration pending` and do not call the host test complete until the state is restored or handed off to a named owner. Redact screenshots, recordings, and logs before sharing or committing them.

If the automation or remote-control channel sees a blank/stale page but the human operator sees the mini-program rendering in the same host client, do not conclude either "app is blank" or "test passed" from that single channel. Record `observation-channel conflict`, verify focus/window/permission state, try a second host-visible evidence path (native screenshot, mobile preview, developer-tool screenshot, screen recording, or user-provided capture when needed), and label each finding by evidence source. Only file a product "blank screen" defect when a host-visible channel reproduces the blank state; otherwise file the automation limitation or mark the automated visual check blocked.

When the mini-program entry is not already open, use this entry discovery ladder before declaring the host test blocked:

1. Use the host client's global search, not a contact-only "new chat" search. Search the exact mini-program name first; if it fails, try the official short name and known aliases.
2. Press Enter or open the full search results page when the inline dropdown is incomplete; select the mini-program result type, not a contact, article, or chat record.
3. If global search cannot find it, use a QR code, shared mini-program card, or official link from the project owner.
4. If the app was opened before, try recent mini-programs or chat history only as a fallback, because those paths are account-local and less reproducible for teammates.
5. If none of the above works, record `blocked: entry unavailable` with the searched names, sanitized account class or role used, host client, and requested owner action.

Developer tools remain useful for compile, preview, route smoke, static rendering, and deterministic non-streaming interactions. Do not treat a developer-tool request start, first chunk, simulator screenshot, or generated preview QR as proof of real-host completion when the correctness claim depends on the real host client or device.

## Release Channel Mapping

Mini-program platforms ship three distinct channels with different audience, lifetime, and signing semantics. Confusing them is a recurring source of "the preview QR works but the reviewer / customer cannot open it":

- **Developer / preview build** (WeChat 开发版 / developer-tool 预览 QR; Alipay developer-tool 真机预览; Douyin 开发版): tied to the developer-tool session or preview-token; short-lived; only accessible to whitelisted member accounts (开发者 / 体验者 角色); useful for in-team smoke. NOT a substitute for the experience build below.
- **Experience build** (WeChat 体验版; Alipay 体验版; Douyin 体验版): a fully uploaded version assigned to a named whitelist (typically internal QA + product + named external reviewers); same packaging as the submitted version; ephemeral until replaced by next upload; the right channel for stakeholder review, real-host QA, and reviewer pre-walkthrough.
- **Production / official build** (正式版): the version that passed platform review and is live to public scene entries; subject to review-time policy, version-rollback rules, and gray-release where supported.

The release checklist below applies to the production build; experience-build smoke is a gate before the production submission, not after. A "preview QR" produced by the developer tool is the developer channel — do not equate it with an experience build for external reviewers.

## Release Checklist

- App id, env, base URL, feature flag, package version, and analytics version are correct.
- Private config, reviewer credentials, tokens, and local machine settings are not committed.
- Platform review-sensitive flows have product-approved copy and accessible test path, with the current platform-policy doc URL + date recorded.
- Risky mini-program flows (payment, write-finality, generated content, host capability bursts, new permission asks) need a tested kill-switch path before submission. The release/backend/platform owner may own the server-side flag, but the mini-program owner must verify the client contract and handoff evidence: disabled means the risky path no-ops, permission prompts and SDK auto-collection do not start while disabled, an unreachable flag service evaluates to OFF for high-risk actions, stale flag/config values are rejected after the declared freshness window, propagation SLO and per-region/edge verification are recorded, every flip has an audit record (who, when, from-value, to-value), and rollback verification proves the safe default is active. Host-platform config submitted for review and other client-only effects that a server flag cannot change still need code-path gating, SDK lazy-load gating, and config review.
- Gray release / version-pinned rollout path documented per host platform (each platform's gray-release mechanism is its own contract); rollback path tested.
- Owner handoff includes version, commit, build artifact, verified commands, known risks, server-flag default + ramp plan, and rollback path.

## Review Rejection Handling

- Treat rejection as a defect: capture exact reason, affected page/capability, platform rule, and reproduction path.
- Separate policy/copy/product issue from implementation/config issue.
- Patch the smallest owning artifact: product copy, permission timing, page flow, API behavior, config, or release note.
- Re-run the relevant compile, preview, and policy-sensitive path before resubmission.
