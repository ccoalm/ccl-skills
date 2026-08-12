# Terminal Side Channels: Chrome, Status, Progress, Title, Sleep Lease, Backgrounding

Full contracts for the terminal side-channel surfaces named in `SKILL.md`
Core Workflow step 6. Load this file whenever the change touches secondary
guidance chrome, status lines/footers, progress indicators or notifications,
terminal/tab titles and chrome metadata, host sleep prevention, delay/polling
commands, or session-background shortcuts. Every bullet is an obligation.

Shared routing for all surfaces in this file: route model-visible semantics
to `llm-inference-integration`, signal schema to `platform-observability`,
rollout/default policy to `platform-release-engineering`, stale or misleading
state incidents to `defect-diagnosis`, and product/security review when a
side channel alters user attention, privacy, approval/completion state, or
automation expectations.

## Tips, Nudges, And Secondary Guidance Chrome

Render tips, nudges, release notes, update notices, and other secondary
guidance as interrupt-budgeted terminal chrome rather than primary output.

- Suppress or downgrade them in noninteractive, automation, structured-output, privacy-restricted, narrow-terminal, or user-disabled contexts.
- Bind display to eligibility, cache freshness, cooldown/history, and current terminal/session generation.
- Avoid stealing focus, submitting input, clearing scrollback, polluting copy selection, or changing machine-readable output channels.
- Keep diagnostics to categories, counts, freshness state, and sanitized reason codes instead of raw local context, filenames, command text, account state, or notice bodies.

## Custom Status Lines, Footers, And Status Commands

Treat custom status lines, footers, and prompt-adjacent status commands as
external command boundaries, not as static labels.

- Execute only after the relevant trust, source-precedence, managed-policy, and user-disable gates pass; send a bounded allowlisted runtime snapshot rather than the full session state; debounce and cancel in-flight refreshes; reject late output after session, workspace, permission mode, model, input mode, terminal generation, settings, trust, or policy drift; bound execution time and output size; normalize multiline output before rendering; reserve stable footer height in fullscreen or constrained layouts; and ensure status output cannot steal focus, submit input, clear scrollback, pollute copy selection, or appear on machine-readable output channels.
- Diagnostics may expose command length, source class, timeout/cancel counts, and sanitized failure categories, but not raw commands, command output, local paths, session ids, account state, cost/context bodies, or free-form errors.

## Progress Indicators And Notifications

Treat terminal progress indicators and notifications as a terminal side
channel, not primary stdout, structured protocol output, transcript content,
or proof that work completed.

- Emit terminal status only after capability detection and user/settings policy gates; route raw control sequences through the terminal writer path rather than ordinary printable output; wrap control sequences for multiplexed terminals when required, while preserving deliberately raw fallback signals only when wrapping would break the fallback.
- Progress states need bounded state values, clamped percentages when percentages exist, explicit clear behavior on success, error, cancellation, unmount, and unsupported-terminal fallback, and no stale indicator after the owning operation/session/input generation changes.
- Notifications must be scoped to visible user attention rather than model context, must not steal focus or submit input, and must degrade quietly when unsupported.
- Diagnostics may expose bounded terminal capability, state, fallback, and count categories, but not notification bodies, raw progress messages, command text, local paths, account/session identifiers, control-sequence bytes, credentials, or free-form terminal errors.
- Route model-visible progress attachment semantics to `llm-inference-integration`, signal schema to `platform-observability`, rollout/default policy to `platform-release-engineering`, stale or noisy status incidents to `defect-diagnosis`, and product/security review when notifications or terminal status alter user attention, privacy, or automation expectations.

## Terminal Title And Declarative Chrome Metadata

Treat terminal title, tab title, sidebar status, prompt-adjacent status
labels, and similar declarative terminal chrome metadata as side channels,
not stdout, protocol frames, transcript content, copied user content,
model-visible evidence, or task-finality proof.

- Emit them only through the terminal-writer or platform-title path after capability, terminal, multiplexer, settings, trust, managed-policy, privacy, entrypoint, and owner-generation gates; multiplexer contexts require the correct passthrough wrapping and escaping or a disabled/safe fallback, and unsupported or disabled contexts must no-op, clear only owner-scoped state, or fall back safely rather than writing printable output.
- Title/status labels must be bounded, allowlisted by source class, stripped of style/control/hyperlink/hidden-text payloads before terminal emission, and unable to spoof prompts, approvals, errors, or completion.
- Command-backed status lines remain external command boundaries under the custom-status-command rule above; this metadata rule only adds the display-side freshness, stale-rejection, layout stability, and no-pollution obligations after command output has been authorized and normalized.
- Null, disable, owner-change, unmount, normal exit, crash-recovery, and unsupported-terminal transitions need explicit stale-clear semantics for state the session owns, without clearing unrelated user or terminal state.
- Diagnostics may expose bounded capability, source-class, timeout/cancel, clear/fallback, and count categories, but not raw title or status bodies, command text, command output, prompt text, local paths, workspace names, branch names, account/session identifiers, control bytes, credentials, or free-form terminal errors.
- Beyond the shared routing above: route the visual meaning of chrome metadata to `product-ui-ux-design`, and require security review when chrome metadata can expose sensitive context or confuse approval/completion state.

## Host Sleep Prevention As A Resource Lease

Treat host sleep-prevention for long-running terminal work as a local
resource lease, not as an always-on convenience.

- Acquire it only while foreground work is actually active, not while waiting for user approval, local dialogs, idle input, or background work that has its own resumability contract; bind acquisition to session/process identity, active-work generation, platform capability, product setting or policy generation, and cleanup generation.
- Use reference counting or equivalent ownership so overlapping work does not release the lease early, and make release idempotent on normal completion, error, user interrupt, unmount, parent cancellation, shutdown, and stale active-work state.
- Helper processes, timers, or native assertions must have bounded lifetime or orphan self-healing after hard process death, must not keep the CLI process alive by themselves, and must restart or refresh only while ownership is still positive and the current tuple still matches.
- Unsupported platforms, missing helpers, spawn failure, kill failure, or cleanup failure should degrade without blocking the task or polluting the transcript; diagnostics may expose bounded platform/capability/state categories and counts, but not raw helper commands, process ids, local paths, account/session identifiers, exact private-activity durations, or free-form native errors.
- Beyond the shared routing above: route active-work semantics to `llm-inference-integration` when model/task finality changes, route stale-lease or battery-drain incidents to `defect-diagnosis`, and require product/security review when preventing sleep changes user-visible power, privacy, or device-control expectations.

## Delay Commands, Polling, And Auto-Backgrounding

Treat delay-only shell commands and delay-then-check polling patterns as
foreground-turn blockers, not as useful progress.

- Detect leading delay statements before execution when a background or monitor mechanism is available; allow bounded short pacing delays, but reject longer leading delays with a repair path that preserves the intended follow-up check or stream watch.
- Do not automatically background pure delay commands or commands whose semantics depend on remaining foreground; explicit user-requested backgrounding may still run through the ordinary background-task contract.
- Auto-backgrounding for other long-running commands must be gated by command class, entrypoint/mode, user and managed settings, task registration state, and current tool invocation generation.
- If a foreground task is already registered, detach that same task in place instead of re-spawning it; preserve task id, output location, cleanup owner, progress stream, and completion notification, and wake any waiting progress loop so the tool result records background finality promptly.
- Background task lifecycle must flush output before completion finality, retain final output by cursor or digest until required UI, model-visible, SDK/control-stream, transcript, and support-artifact consumers have acknowledged it or explicitly skipped it with typed degraded evidence, and mark finality unknown rather than deleting the only proof behind a completion/failure claim.
- Suppress duplicate completion or stop notifications with an atomic notified marker, preserve SDK/control-stream task-terminated parity when noisy shell output is suppressed, and cleanup owner-scoped child processes and queued notifications when the owning agent/session exits.
- A stalled-output watchdog may notify only after two-phase stable-idle detection bound to task id, output generation, read cursor, and progress/event generation; recheck the same tuple immediately before emission, cancel on any output append, progress, status, session, or owner drift, bind the one-shot marker to that generation, and never let a late prompt warning fire after work resumed or completed.
- Statusless stalled-prompt notifications must not masquerade as completion/failure and must avoid raw prompt/output/path leakage.
- If backgrounding is disabled, unavailable, stale, or denied by command class, keep the command foreground and surface bounded guidance rather than inventing a detached task.
- Diagnostics and telemetry may expose sanitized command classes, background reason categories, status categories, counts, and bounded durations, but not raw command text, arguments, output bodies, prompt tails, local paths, task ids, credentials, or free-form shell errors.

## Session-Background Shortcuts

Treat session-background shortcuts as terminal control boundaries with
explicit priority, not ordinary input.

- If a foreground shell or tool task is active, the control must apply to that task through the task backgrounding contract before it can background the main session query; session-level backgrounding is eligible only when a model turn is in progress, no higher-priority foreground task owns the shortcut, and the feature is enabled by the current entrypoint, terminal, user setting, and policy.
- Confirmation or double-press patterns must be bounded by input generation, focus state, terminal mode, and shortcut configuration so ordinary text editing, scrollback navigation, or reserved terminal prefixes are not swallowed.
- Hints must be terminal chrome with no focus theft, submit, scrollback clearing, copy pollution, stdout or protocol pollution, or raw prompt/session leakage; unsupported, disabled, or stale contexts should no-op or surface bounded guidance rather than changing task ownership.
- Multiplexer or remapped shortcut displays are presentation only and must not widen the accepted input grammar.
- Route the model-visible foreground and background session handoff and queued-notification transfer to `llm-inference-integration`; route rollout defaults, signal schema, stale/lost-background incidents, and privacy/security review to the usual platform and review owners.
