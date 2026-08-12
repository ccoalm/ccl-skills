# Input State Machines: Paste, Keybindings, Modal Editing

Full contracts for the three stateful input boundaries named in `SKILL.md`
Core Workflow step 5. Load this file whenever the change touches terminal
paste/clipboard ingress, configurable keybindings, or modal (vi-like) text
editing. Every bullet is an obligation, not advice.

## Paste And Clipboard Ingress

Treat terminal paste and clipboard ingress as a stateful input boundary before normal text handling.

- Bracketed paste needs parser state that treats embedded escape sequences as literal content, emits explicit empty-paste events when the platform can paste non-text media, and flushes or cancels incomplete paste state deliberately.
- Large-paste and dragged-file fallbacks need bounded chunk aggregation, completion timeout, synchronous pending state so a following key cannot submit stale input before the paste lands, and cleanup of orphan focus or terminal-response fragments without dropping valid user text.
- Clipboard media probing must be opt-in by capability and platform, debounced across focus changes, rate-limited for hints, fenced by mounted/input generation, and separated from ordinary text submit.
- File-path or media-path paste handling must normalize quoting and shell escapes, preserve non-media text, reject unverifiable or unsupported files before media insertion, enforce size/dimension/type budgets after reading trusted bytes, delete temporary artifacts best-effort, and route model-visible insertion through the runtime input/attachment gate.
- Diagnostics may expose bounded categories, counts, capability states, and sanitized failure classes, but not clipboard text, filenames, local paths, raw media bytes, platform command strings, credentials, or free-form native errors.

## Configurable Keybindings

Treat configurable keybindings as an input-to-action control boundary.

- Validate the user keymap schema before merging with defaults; user overrides must be ordered, explicit null/unbind entries must shadow defaults, and duplicate raw keys must be detected before permissive parsers collapse them.
- Bind every resolved shortcut to context stack, active mode, terminal capability, platform-reserved and application-reserved shortcut set, key-parser generation, keymap generation, handler registration generation, pending-chord generation, and command-dispatch generation when a shortcut invokes a command.
- Reserved or non-rebindable shortcuts need fail-closed errors or visible warnings instead of appearing supported.
- Chords require prefix capture, timeout, escape/cancel, unbind shadowing, and stale-pending cleanup so chord keystrokes cannot leak into the prompt or another focused control.
- Hot reload must publish only a complete parsed generation, reset to defaults on deletion or invalid config according to product policy, and close watchers/timers/handler registrations on unmount, exit, and shutdown.
- Diagnostics may expose bounded warning categories, counts, and display labels, but not raw local config paths, binding bodies, command names, prompt text, credentials, or free-form parse errors.

## Modal Text Editing

Treat modal text editing as a command-language state machine, not as independent shortcuts.

- Bind mode, parse state, bounded count prefix, pending operator, pending motion, text-object scope and type, find/replace literal, last-find state, last-change state, register contents plus linewise flag, insert-buffer snapshot, undo generation, active input identity, cursor/text snapshot, and grapheme/display-width model.
- Cancel, focus loss, mode switch, submit, history search, paste, composition input, external insertion, prompt replacement, unmount, and resize that invalidates cursor geometry must either reset pending command state or fence it to the original input generation.
- Operators that combine with motions or text objects must define inclusive, exclusive, and linewise ranges; logical-line versus wrapped-row behavior; missing-target and unmatched-delimiter no-ops; cursor clamping after mutation; register/yank/paste linewise behavior; and grapheme-safe boundaries.
- Repeat commands may replay only successful mutations against a compatible snapshot/generation, and diagnostics may expose bounded state categories but not prompt text, registers, raw command bodies, local paths, credentials, or free-form parser errors.
