---
name: terminal-cli-dev
description: CLI/terminal/console/PTY/ANSI/keyboard/TUI design, implementation, review, debugging, testing, or shipping. Owns the command/subcommand/flag/help contract (owned here even when nothing is rendered) and the command/subcommand/flag/default/help/output/exit/action/confirmation/progress/recovery contract, plus layout, input, accessibility, and real-terminal evidence. Triggers include "命令行/TUI 界面怎么做", "CLI 界面怎么写", "refactor a terminal command / TUI view". Skip only parser/library/tooling internals owned by a language skill ("用 Python 写个命令行工具" → python-service-dev, Go CLI → go-microservice-dev, Node.js CLI → nodejs-service-dev) that provably preserve every user-facing command tree, default/action path, help/output/exit behavior, confirmation, progress, and recovery path; compose both owners when user-visible semantics change.
---

# Terminal CLI Dev

Use this skill for terminal and command-line product surfaces. It owns the user-facing command tree, flags/defaults, help/output/exit behavior, confirmations, progress/recovery, plus implementation mechanics for text UIs, console workflows, ANSI-rendered output, PTY-backed interaction, keyboard input, terminal capability handling, and real terminal verification. A language skill may own parser or library mechanics, but those mechanics do not displace this user-visible contract. This skill does not own web browsers, mobile apps, mini-program hosts, backend services, or product design judgment.

## Routing

- Use `product-rd-workflow` first when the work spans product intent, design, implementation, testing, release, or postmortem follow-up.
- A user-facing command/subcommand/flag/default/help/output/exit/action/confirmation/progress/recovery path is a terminal surface even when it emits only plain text and never enters an alternate screen.
- Use `product-ui-ux-design` before or alongside coding for that user-facing terminal surface: hierarchy, density, interaction model, copy, states, accessibility, consequence, recovery, and visual/textual acceptance.
- Use `testing-strategy` to choose unit, snapshot, PTY, integration, and real-terminal evidence; return here for terminal-specific implementation mechanics.
- Use `defect-diagnosis` first for rendering regressions, input bugs, flicker, selection/copy issues, broken resize behavior, color/readability defects, or flaky terminal tests.
- Use `platform-observability` for telemetry/log schema and `platform-release-engineering` for rollout of behavior-changing defaults, persisted settings migrations, or terminal capability fallbacks. Do not treat CLI package distribution, installer, or updater mechanics as covered unless the release skill has explicit terminal distribution guidance.

## Core Workflow

Before editing a user-facing command tree, flag/default/action path, help/output/exit behavior, confirmation/progress/recovery flow, terminal UI code, output formatting, keyboard handling, PTY integration, layout, color/theme logic, or terminal tests, complete enough analysis and planning for the change to be reviewable. Scale the plan to risk: a small copy or formatting change can use a short note; a new command path, changed default, interactive surface, renderer, input mode, terminal capability change, high-risk action, release behavior, or bug fix needs explicit scenarios, target terminal environments, verification commands, and stop conditions.

Repo-local agent contracts (`AGENTS.md` at the repo root and in source directories) are part of the delivery contract: when a change moves a stable boundary, generated surface, workflow, or directory-local rule, update the nearest contract in the same MR and keep coverage in sync per `product-rd-workflow`'s spec / repo-contract sync gate.

When checking a terminal/CLI project against team standards, split conformance into deterministic and agent review evidence. Deterministic checks cover exit-code conventions (0 on success / non-zero on failure; `os.Exit`/`process.exit`/`sys.exit` only in the entrypoint, not the library layer), stdout-vs-stderr routing (primary/machine-readable output to stdout, logs/diagnostics/progress/prompts to stderr), `--help`/`--version`/`--json` (or `--plain`) flag presence in the parser tree, signal-handler registration, `NO_COLOR`/isatty handling, and absence of hardcoded ANSI escape literals outside the rendering module. Agent review checks cover terminal-state restoration on every exit path, capability-fallback completeness, the `NO_COLOR`/non-TTY/`TERM=dumb`/`--no-color` color-disable matrix, prompt-only-on-TTY (`--no-input` honored), error actionability, and whether tests prove real-terminal behavior rather than only string snapshots. For the per-language deterministic executor list (Go `errcheck`/`forbidigo`, Rust Clippy `print_stdout`/`exit`/`unwrap_used`, Ruff `T201`/`PLR1722`) and the shipped `client-terminal-ansi-check.py` (CB-1: flags hardcoded ANSI escape literals outside an allowlisted rendering module), see `testing-strategy/references/fitness-functions.md` §4.1.3 (client language-basics; spec 006). CLI/TUI invariants have almost no off-the-shelf CLI-aware linter, so most of this contract is agent-review plus a few repository checks — prefer a capability-aware lib over hand-emitted escapes.

1. Classify the terminal surface.
   - One-shot CLI output, interactive prompt, full-screen TUI, embedded terminal panel, log/status stream, diff/code viewer, installer/updater, or background task display.
   - Output-only, input-driven, mouse/selection-aware, PTY-backed, or mixed.
   - Plain text, ANSI-styled, hyperlink-capable, alternate-screen, scrollback-preserving, or terminal-query-dependent.

2. Define the terminal contract before coding.
   - Supported terminals, shells, OS families, remote/headless behavior, CI behavior, and fallback mode.
   - Whether the feature requires a TTY, raw mode, cursor control, bracketed paste, mouse reporting, focus reporting, hyperlinks, truecolor, or scrollback control.
   - Behavior when capabilities are missing, disabled by user preference, blocked by a multiplexer, proxied through a remote shell, or unavailable in CI.
   - State ownership for input focus, modal overlays, selection, scroll position, unseen output, pending operations, and resize recovery.
   - For every user-facing terminal/CLI contract change—including command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, or recovery—load `../product-ui-ux-design/references/delivery-contract.md` and consume either its full Design brief + Phase 0 or its valid low-risk copy-only record + lightweight Phase 0 before coding. Only parser/library internals that preserve all of those user-visible semantics may mark UI/UX `not-applicable`, with the preservation evidence recorded. The lightweight path checks semantics, accessible text, localization/width, cell extent, and target-terminal render without inventing unrelated matrices; risk-bearing copy or behavior uses the full path. For full slices, map structure, state/adaptation matrices, behavior and criteria to the screen buffer/lifecycle; record terminal classes, dimensions, input/capability modes, resize/scrollback/selection, and preserved state.
   - Before the first implementation edit, add the canonical `client_entry` defined there: local rule identifier or short quote and implementation decision, target surface/runtime, planned run/capture command, and behavior that must remain unchanged.

3. Render by terminal cells, not string length.
   - Measure display width with ANSI-stripped, Unicode-aware logic. Cover combining marks, emoji, East Asian width, zero-width code points, variation selectors, and control characters.
   - Preserve grapheme and wide-character boundaries when wrapping, truncating, slicing, highlighting, cursoring, or copying. Never split the trailing cell of a wide character into visible content.
   - Keep a screen-buffer model for interactive surfaces: cell char, style, width, hyperlink, selectable/non-selectable status, soft-wrap continuation, and damage bounds.
   - Treat soft-wrapped rows differently from hard newlines so selection/copy reconstructs logical text instead of copying padded screen rows.

4. Handle color and ANSI state deliberately.
   - Respect explicit no-color or reduced-color settings.
   - Choose truecolor, 256-color, or plain fallback from actual capability and user preference; avoid assuming environment variables are complete truth.
   - Keep color as enhancement, not the only state carrier. Important states need text, symbols, underline, inverse, or another readable fallback.
   - Strip or replace background/inverse styles intentionally for overlays such as selection and search highlights so existing syntax or status colors do not make the current target unreadable.
   - Reset style transitions cleanly; avoid leaking style state across lines, prompts, streamed chunks, or restored screen regions.

5. Make input, focus, and selection stateful.
   - Parse keys and terminal responses separately; response sequences should not be mistaken for user keypresses.
   - Gate shortcuts, mouse events, paste, focus, modal priority, and text input by active mode.
   - Treat terminal paste/clipboard ingress as a stateful input boundary, configurable keybindings as an input-to-action control boundary, and modal (vi-like) text editing as a command-language state machine — never as ordinary text handling or independent shortcuts. Before touching any of these three surfaces, load `references/input-state-machines.md`; its per-surface bullets (bracketed-paste parser state, keymap schema/generation binding, operator/motion/register semantics, and each surface's bounded-diagnostics rule) are obligations, not advice.
   - Model selection as anchor plus focus, not a transient highlight. Preserve copied text when scroll movement pushes selected rows out of the visible buffer.
   - Support word/line selection with Unicode-aware boundaries where applicable, and mark gutters, borders, status chrome, or generated line numbers as non-selectable when copying content.
   - Fence stale callbacks after mode changes, resize, unmount, stream finality, interrupted prompts, or screen replacement.

6. Layout for constrained terminals.
   - Define minimum width/height behavior, truncation strategy, collapse order, and non-interactive fallback.
   - Keep primary task content readable before decorative status, helper text, or secondary panels.
   - Recompute layout on resize and clamp scroll/selection/cursor coordinates to valid bounds.
   - Preserve scrollback intentionally: clear only the intended region, avoid destroying history unless the command contract says so, and use platform-specific clear behavior conservatively.
   - For streaming output, keep user scroll position stable when they are reading history; show a jump/new-output affordance instead of force-pinning every frame.
   - When streaming **rich/markdown** output into append-only scrollback, split the stream into a committed *stable* region and a mutable *tail*, because a later token can retroactively reshape earlier output and scrollback cannot be un-printed. The invariant: **never commit reshape-prone content to an irreversible surface; hold it mutable until it is stable** — and **sanitize terminal control sequences out of streamed content before rendering (a security boundary: untrusted content must not be able to deceive through the terminal)**. Before implementing or reviewing any streaming-rich-output path, load `references/streaming-rich-output.md` for the full contract: structural-boundary commits with one-line lookbehind, deferred-resolution construct holdback, bounded tail and re-render cost (CPU-DoS cap), finalize flush, the control-sequence/chrome-spoofing/Trojan-source defenses, adaptive drain pacing, and the no-baked-width rule.
   - Terminal side channels — secondary guidance chrome (tips/nudges/notices), custom status lines and footers, progress indicators and notifications, terminal/tab titles and chrome metadata, host sleep-prevention leases, delay/polling command backgrounding, and session-background shortcuts — are never primary stdout, protocol output, transcript content, or proof of completion. Each carries capability/policy gating, generation-bound staleness rules, no-focus-theft/no-copy-pollution obligations, and a bounded-diagnostics rule (categories and counts, never raw bodies/paths/credentials). Before touching any of these surfaces, load `references/terminal-side-channels.md` for the per-surface contracts and their routing to `llm-inference-integration` / `platform-observability` / `platform-release-engineering` / `defect-diagnosis`.

7. Optimize without changing semantics.
   - Use damage bounds, scroll hints, buffer reuse, lazy syntax/highlight loading, and bounded caches only when they preserve visible output, selection, copy text, and terminal state.
   - Do not let performance shortcuts skip non-selectable marks, soft-wrap metadata, style resets, hyperlink state, or wide-character spacer cells.
   - Bound queue sizes, redraw cost, and memory growth for long sessions or large output.

8. Verify on the real terminal surface.
   - Unit-test width, wrapping, truncation, ANSI parsing, key parsing, state transitions, and capability fallback.
   - When writing the test code itself (structure, naming, smells, fixtures, behavior-vs-state, coverage, isolation, parameterization), pick the matching § from the decision table in `testing-strategy/references/test-code-authoring-patterns.md`; enable the per-stack lint executors for its machine-decidable smells (conditional logic / sleep / assertion-free tests) per `testing-strategy/references/fitness-functions.md` §4.1.4, reusing the row for the implementation language (Go/Python/JS; Rust: sleep bans via `clippy::disallowed_methods`, conditional-logic and assertion-free checks stay agent-review).
   - Snapshot at the cell/screen-buffer layer when possible; raw string snapshots alone are insufficient for interactive terminal behavior.
   - Use a PTY or equivalent integration test for raw mode, resize, key/mouse/paste sequences, terminal responses, and process lifecycle.
   - Run at least one real terminal smoke for visible interactive changes when lower layers cannot prove color, cursor, scrollback, focus, selection, or resize behavior.
   - For UI/UX redesign evidence, include target terminal class, size and narrow/short stress size, color mode or no-color fallback, keyboard-only path, empty/loading/error/final states, scrollback behavior, selection/copy boundary, resize behavior, and screenshot/transcript/PTY artifact; mark each dimension covered or `N/A` with a one-line reason. `N/A` is valid only when the reason names a verifiable structural fact, explains why that fact makes the dimension unreachable or unchanged for this slice, and includes a checkable pointer such as a file path, config key, or commit that resolves at review time. Persist evidence artifacts where reviewers can access them after redacting tokens, PII, credentials, private paths, command secrets, and raw personal data; remove temporary smoke files or PTY capture helpers before commit unless the repo intentionally owns them.
   - Return the complete canonical client-record member defined in `../product-ui-ux-design/references/delivery-contract.md` for testing Phase 1 and the design verdict. The member includes its applied rule/decision, affected files/components, preserved behavior, exact command, immutable candidate binding, producer member/version actually exercised, artifacts, tested terminal classes/dimensions/states/input/capability modes, criterion-mapped observations, coverage boundary, and gaps. A terminal capture proves only the captured states; it cannot close an unbound producer member. `testing-strategy` records aggregate sufficiency before the design owner records the candidate-bound verdict.
   - Capture evidence: command, terminal class, size, color mode, before/after screenshot or transcript, and any unavailable capability with attempted remediation.

## Reference Loading

- `references/input-state-machines.md` — full contracts for paste/clipboard ingress, configurable keybindings, and modal text editing. Load before touching any of those input surfaces (Core Workflow step 5).
- `references/streaming-rich-output.md` — full contract for streaming rich/markdown output into scrollback, including the untrusted-content sanitization security boundary. Load before implementing or reviewing any streaming-rich-output path (step 6).
- `references/terminal-side-channels.md` — per-surface contracts for guidance chrome, status lines, progress/notifications, title/chrome metadata, sleep leases, delay/backgrounding, and session-background shortcuts. Load before touching any side-channel surface (step 6).

## Non-Negotiable Rules

- Do not treat terminal strings as layout truth; terminal cells are the layout truth.
- Do not ship a terminal UI that only works in one color depth, one width, or one local shell unless the product explicitly scopes it that way.
- Do not rely on color alone for warnings, errors, selection, current match, disabled state, or destructive action confirmation.
- Do not claim terminal behavior is verified from static code inspection or string snapshots when the change affects cursoring, focus, raw mode, resize, scrollback, selection, or color.
- Do not let generated chrome, gutters, hidden prompts, or status lines pollute copied user content.
- Do not destroy scrollback or clear the screen as a side effect of refresh unless that behavior is part of the command contract and has a fallback.
- Do not leave the terminal in raw mode, alternate screen, hidden cursor, mouse reporting, bracketed paste, focus reporting, modified keyboard mode, or non-default style state after normal exit, error, interrupt, termination signal, child crash, resize race, unmount, parent cancellation, or crash recovery.
- Do not crash or dump a traceback when a downstream consumer closes the pipe early (piping to `head`, or to a pager then quitting): a write to a closed stdout/stderr raises `EPIPE` / `BrokenPipeError`. Exit quietly with the conventional status — in Python restore the default `SIGPIPE` disposition (`signal(SIGPIPE, SIG_DFL)`) or handle `BrokenPipeError` at the top level; in Node/JS catch the stream write `EPIPE` / `ERR_STREAM_DESTROYED` error (do not rely on a portable default-signal reset). Do not let it surface as an error stack to the user. (POSIX `SIGPIPE` / `write(2)` `EPIPE`.)
- Do not write a durable file output in place when an interrupt (Ctrl-C / `SIGTERM`) or crash mid-write would leave a truncated or corrupt file: write to a temp file **in the same directory** (same filesystem — a cross-filesystem `rename` fails `EXDEV` and a copy-across-volume move is not atomic), flush and close it, then `rename(2)` onto the target — atomic replace on POSIX; on Windows use `MoveFileEx(..., MOVEFILE_REPLACE_EXISTING)` or the runtime's atomic-replace API. The reader then sees either the old file or the complete new one, never a half-written one. Streaming stdout is exempt; this is about durable file artifacts the command promises to produce.
