# Streaming Rich/Markdown Output Into Scrollback

Full contract for streaming rich (markdown) content into append-only
scrollback, referenced from `SKILL.md` Core Workflow step 6. Load this file
whenever the change streams model output, fetched text, or any progressively
arriving rich content into a terminal.

The general invariant: **never commit reshape-prone content to an
irreversible surface; hold it mutable until it is stable.** Split the stream
into a committed *stable* region and a mutable *tail*, because a later token
can retroactively reshape earlier output and scrollback cannot be
un-printed. (In a DOM/web or app chat UI the whole subtree re-renders
cheaply, so this discipline is terminal-specific — the append-only
scrollback constraint is what forces it.)

## Commit At Structural Boundaries, Not On Every Token — With One-Line Lookbehind

Buffer the incoming delta and only re-render/commit *complete lines* (gate on
newline); keep the trailing incomplete line in the tail. A complete line is
still not safe to commit until the *next* line proves it is not the start of
a construct that reinterprets it: a `Title` line followed by `---` becomes a
setext heading, and a line followed by a pipe-table delimiter becomes a table
header. So hold at least one settled line of lookbehind — commit line N only
once line N+1 shows N is not a setext/table/continuation anchor. Re-render
the still-mutable prefix from accumulated source rather than appending raw
deltas, so inline markdown that completes mid-line renders correctly.

## Hold Back Deferred-Resolution Constructs Until They Resolve

Hold back any construct whose later content reshapes earlier output, until it
resolves. This is a *class*, not a fixed list — markdown has several
deferred-resolution constructs, and committing early prints something the
later tokens prove wrong: a table's column widths change when a new row
arrives; a setext heading rewrites its title line; a reference-style link
(`[docs]` … later `[docs]: https://…`) should have been a hyperlink; a
list's tight/loose spacing flips when a later blank line or sub-paragraph
appears.

- You will not enumerate them all, so prefer one of two strategies over
  per-construct hacks: (a) render in a **streaming-invariant** form that does
  not depend on not-yet-arrived content (e.g. resolve only inline/closed
  constructs; do not attempt reference-link or setext resolution mid-stream);
  or (b) when you do want the rich form, **detect the construct as it opens
  and keep it in the mutable tail until it resolves or the stream
  finalizes**, under the bounded-tail rule below.
- Committing a half-built table or a premature paragraph to scrollback prints
  output you cannot un-print.
- Scan for these patterns only outside open code fences.

## Bound The Held Tail And The Re-Render Cost

Never hold or re-parse unboundedly. A minutes-long table or an unclosed code
fence would otherwise hold from block-start forever: nothing commits, the
buffer grows without bound, and the user sees a frozen tail.

- Cap the held region by lines / bytes / elapsed time; on exceeding the cap,
  stop holding and commit the oversized block degraded to streaming-safe
  plain or preformatted text (accept a non-reflowed table over an infinite
  tail and a memory leak).
- The same cap protects against a re-render **CPU** DoS: because the mutable
  tail is re-rendered from accumulated source on every delta, adversarial
  markdown (deeply nested brackets/emphasis, pathological reference or table
  syntax) can drive O(n²)-or-worse parsing/regex work each tick and freeze
  the terminal. Use a linear-time/bounded parser and cap per-tick render
  size/time, falling back to plain text when exceeded — never re-run an
  unbounded parse over an ever-growing tail on every token.

## Finalize Flushes The Remainder

On stream end, render and commit whatever is left in the tail (including a
last line with no trailing newline and any still-open held-back block,
rendered best-effort).

## Sanitize Terminal Control Sequences Out Of Streamed Content — A Security Boundary

Streamed primary content (model output, fetched/user text) is untrusted and
can embed raw escape/control bytes: `ESC[2J` clears the screen,
cursor-movement sequences overwrite earlier output, OSC 52 writes the user's
clipboard, OSC 8 injects hyperlinks, and a forged sequence can spoof a
prompt or approval line.

- Rendering those bytes as if they were the renderer's own gives the content
  author control of the terminal. Before rendering streamed content, strip
  or visibly escape all control sequences and only emit renderer-owned,
  allowlisted styling (the SGR/colors *you* chose, the hyperlinks *you*
  constructed).
- This is distinct from ANSI-stripping for width measurement — here the goal
  is to deny the content any terminal capability, not just to count cells.
- Stripping control bytes is necessary but not sufficient.
- The general rule is **untrusted streamed content must not be able to
  deceive through the terminal**, and that has several instances beyond raw
  escapes: plain-text chrome spoofing (printing `Approve command? [y/N]` or
  `Password:` that reads as a real prompt), and Unicode display/byte
  mismatches — bidirectional-override controls, zero-width/invisible format
  characters, and confusable homoglyphs that make the *displayed* line differ
  from the *copied/actual* bytes (the "Trojan-source" class: a command that
  looks safe on screen hides or reorders a malicious suffix when pasted).
- Defenses: render untrusted streamed output inside a clearly delimited
  content region and reserve prompts/approvals/status chrome for
  renderer-owned styling/layout the content cannot reproduce (so the user can
  always tell agent/remote output from the terminal's own UI); and neutralize
  the display/byte-mismatch vectors — visibly escape bidi-override controls
  and zero-width/invisible format characters (these are unambiguously
  deceptive in a command/code context), and *flag or annotate* suspicious
  confusable homoglyphs rather than silently normalizing them (homoglyphs are
  legitimate Unicode; blanket normalization corrupts real content and still
  can't guarantee display==copy across fonts/locales).
- Treat any new "content influences the terminal" vector as the same
  boundary, not a fresh special case.

## Pace The Commit Drain Adaptively, Source-Agnostically

Drive commits from a FIFO queue of settled lines stamped with arrival time.
Under light load drain ~one line per display tick for smooth pacing; when
queue depth or oldest-queued age crosses a threshold, switch to catch-up and
drain the backlog so visible lag converges. Decide from queue pressure alone,
not from the producer's identity or a hardcoded throughput target.

## Don't Bake Width Into Committed Rich Output

You cannot rewrite width artifacts you already emitted into scrollback: a
line hard-wrapped or column-padded at 120 columns stays mis-aligned and
copies wrong after a shrink to 80. (Soft-wrapped output is different — many
terminal emulators reflow soft-wrapped scrollback on resize; the stuck case
is renderer-baked hard wraps/padding, not all committed text.) So prefer
soft-wrap-friendly output and let the terminal reflow, or treat the render
width as part of the committed artifact and accept that a later resize won't
re-align that block. The still-mutable tail *does* re-render on resize; only
the committed region is stuck, which is the more reason to keep
width-sensitive blocks (tables) in the tail until finalize.
