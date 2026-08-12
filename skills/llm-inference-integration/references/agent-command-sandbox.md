# Agent Command-Execution Sandbox (Implementation Layer)

Implementation companion to the shell-authorization and sandbox-as-defense-in-depth rules in
`SKILL.md` (Core Workflow) and the Tool Execution section of `retrieval-agent-safety.md`. Those
rules state *what the authorization decision must require*; this reference states *how to build the
enforcement* when an agent executes model-proposed shell commands or file edits on a real host.

Use when the agent runs commands/edits locally (coding agent, dev/ops agent, CI agent). Do not use
for pure API tool calls with no local process execution — there the Tool Execution rules suffice.

These patterns are drawn from a production reference agent and cross-checked against OS sandbox
primitives; treat the OS-primitive facts as the authority and the composition shapes as a proven
pattern, not the only valid design.

## 1. Separate the three axes — never collapse them

A safe-execution decision is the product of three independent inputs. Collapsing any two produces a
security hole:

- **Approval policy** — how much human confirmation this session requires (see §6).
- **Sandbox enforcement** — what OS-level confinement is actually applied to the process (§3–§4).
- **Command classification** — what the command itself is judged to do (§5).

Resolve them into one explicit outcome: `auto-approve(sandbox_type, user_explicitly_approved)`,
`ask-user`, or `reject(reason)`. The outcome must record *which* sandbox type was selected and
whether a human explicitly approved — downstream audit and escalation depend on both.

**Fail-closed coupling rule:** auto-approve is valid only when a sandbox can *actually be enforced*
on this platform. If the policy would auto-run but no sandbox primitive is available, downgrade to
`ask-user` (or `reject` if the policy forbids unsandboxed approval) — never silently run
unsandboxed. "Sandbox unavailable" is uncertainty, not permission.

**The boundary is the kernel, not the string.** Path, basename, and command-string checks are
*advisory hints* that decide whether to *attempt* auto-approval — they are not containment. The only
real boundaries are the kernel sandbox (filesystem + network confinement, §4/§8) and a closed
process surface (closed FDs, allowlisted env, no inherited credentials, §9). Every classification or
path check in §3/§5/§6 can be defeated by a determined malicious command; design so that defeating
one still leaves the kernel sandbox enforcing. Never let an advisory check be the *sole* gate in
front of an irreversible or exfil-capable action.

## 2. Sandbox policy = a small set of named profiles, not ad-hoc flags

Express the filesystem/network posture as a closed enum of named profiles. A minimal proven set:

- **full-access** — no restriction. Reserve for explicit user opt-in; mark dangerous.
- **read-only** — no writes; network off by default with an explicit on toggle.
- **workspace-write** — read-only everywhere plus write access to the working directory and an
  explicit list of additional writable roots; network off by default; explicit toggles to
  include/exclude the per-user temp dir and `/tmp`.
- **external-sandbox (pass-through)** — the agent already runs inside someone else's sandbox
  (container, VM, CI runner). Apply no *additional* inner filesystem sandbox but still honor the
  declared network posture. **Pass-through is a trust assertion — attest it, do not assume it.** A
  CI/container host frequently exposes broad mounts, a Docker socket, cloud-credential files, the
  user's home dir, or unrestricted egress; "I'm in a container" is not "I'm confined". Probe the
  effective writable paths, reachable credentials, and network controls before selecting
  pass-through; if you cannot attest the outer boundary, apply the normal inner sandbox or treat the
  sandbox as unavailable (fail closed), not as full trust.

Default network to **off** in every write-capable profile. Network is a separate grant from
filesystem write (§4).

**Reads need a confidentiality boundary too, not just writes.** A profile that confines *writes* but
allows reading the whole host is still an exfil hole: an auto-approved "safe" read (`cat`, `rg`,
`sed`, `find`) can slurp `~/.ssh`, `~/.aws`/cloud-credential files, browser profiles, keychains,
agent tokens, or other repos and leak them through stdout, generated artifacts, or simply into the
model's context (then out via any later egress). Redaction is not a boundary — it cannot recognize
arbitrary secrets. Treat sensitive credential/key/browser/agent paths as **deny-by-default reads**
even under a broad read profile, and have auto-approved read commands validate their target paths
against an explicit read allowlist (workspace + minimal toolchain/system paths), not just the
write/network checks.

## 3. Writable roots must protect privilege-escalation paths

A writable root is not uniformly writable. Within each root, carve out read-only sub-paths and
protected metadata names so the agent cannot rewrite the very files that would re-grant it
privileges:

- VCS hooks and config (`.git/hooks`, `.git/config`), agent/tool config directories, and any
  on-disk policy the runtime reads back. A writable workspace that lets the agent edit its own
  approval policy or a git hook is a sandbox escape by construction.
- Enforce protected-metadata names at the *first path component* under the root, so a new
  `.git/`-shaped directory cannot be created to shadow protections.

**Hard-link / symlink escape:** path-prefix checks alone do not prove containment, and the two link
types fail differently. A **symlink** under a writable root can point outside it — catch these by
*canonicalizing* (resolving symlinks) before the prefix check, not after. A **hard link** is
harder: it shares an inode with a file outside the root while the path genuinely *is* inside the
root, so canonicalization cannot detect it — you need filesystem identity (device + inode) checks,
or run the write inside the OS sandbox so the kernel enforces the boundary regardless. Identity
checks are best-effort (reject files whose link count > 1, or that resolve to a different device);
the robust fix is a kernel-enforced writable layer, not a userspace check. Normalize `.`/`..`
without touching the filesystem before any prefix comparison, but remember normalization is not
canonicalization.

**TOCTOU — the check and the write are not atomic.** Any path validated by canonicalization can be
swapped (symlink replaced, directory swapped, mount changed) between the check and the write. A
userspace "validate then write" is a race. Close it by performing writes *under* kernel sandbox
enforcement, or with race-safe APIs (`openat2` with `RESOLVE_BENEATH`/`RESOLVE_NO_SYMLINKS`, or
`O_NOFOLLOW` + dirfd), and treat the per-invocation decision snapshot as immutable. Do not re-derive
permission from a path string a second time after the model influenced the filesystem.

**Temp dirs are not ordinary writable roots.** A shared `/tmp` or per-user temp invites predictable-
path races, Unix-socket spoofing, lockfile poisoning, and disk-fill. Give each invocation a private,
bounded temp directory (ideally a tmpfs mounted only inside the sandbox) and clean it on exit,
rather than granting the shared temp as a writable root.

## 4. Compose the OS sandbox: deny-default + minimal layered allow + dynamic roots

Same architecture on every platform: start from a closed-by-default base policy, layer in a minimal
fixed allowlist (process spawn within the same sandbox, read-only system info, PTY, temp), then
inject the policy's writable roots and network exception dynamically per invocation.

- **macOS** — Seatbelt via `sandbox-exec` with an SBPL policy that begins `(deny default)` and adds
  minimal allowances; append `(allow file-write*)` rules generated from the writable roots.
  **Pin the absolute launcher path** (`/usr/bin/sandbox-exec`) — never resolve it through `PATH`,
  or a planted binary on `PATH` defeats the sandbox. (`sandbox-exec` is Apple-deprecated but still
  functional and widely used in production agents/browsers; validate availability per OS version
  and be ready to migrate to a per-process sandbox API if Apple removes it.)
- **Linux** — two complementary primitives: **Landlock** (stackable LSM, unprivileged, mainline
  since kernel 5.13) for filesystem access control, plus **seccomp-bpf** for syscall filtering.
  Landlock controls *which files*; seccomp controls *which syscalls* — use both. Run setup in an
  **unprivileged self-re-exec helper** (a multi-call-binary dispatch): the main binary re-invokes
  itself with `argv[0]` set to a marker name; at startup the process inspects its own `argv[0]` and,
  when it matches, acts as a minimal helper that applies Landlock+seccomp (or bubblewrap) and then
  `exec`s the real command. This isolates the sandbox-setup code path and keeps the enforcing
  process minimal. Pass the policy to the helper as serialized JSON, and put a `--` separator before
  the target command so args starting with `-` are not parsed as helper options. **Authenticate the
  helper invocation:** the helper applies whatever policy JSON it is handed, so a sandboxed child
  that re-invokes the multi-call binary under the marker with attacker-chosen, *looser* policy is a
  full escape. Gate helper mode behind a sealed parent-created credential (an inherited
  authenticated fd / one-time token the child cannot forge), and reject helper invocations whose
  policy did not come from the trusted parent.
- **Linux (container-less hosts)** — bubblewrap as an alternative unprivileged-namespace sandbox.
  Detect environments where it cannot work (e.g. WSL1) and degrade explicitly rather than
  silently running unsandboxed.
- **Windows** — a write-restricted token (restricted SID list) and/or AppContainer (Low integrity
  level, capability SIDs). For input/screen isolation, launch under a **private window
  station + desktop** so the sandboxed process cannot inject input into or scrape the user's
  desktop. The boundary must **follow the child-process tree** (package managers, test runners,
  scripts spawn children), not just the first executable.

Inheritance differs by platform: on Linux (Landlock/seccomp) and macOS (Seatbelt) the sandbox
domain applies to the process and all descendants automatically. On **Windows it is not
automatic** — a child gets the restricted token / AppContainer only if launched with it, and you
need a Job object that blocks process breakaway so a child cannot escape; enforce and verify it
across the whole process tree. On every platform, verify spawned helpers do not run *before* the
sandbox is applied.

## 5. Classify the command before auto-running it

OS confinement is defense-in-depth; classification decides whether a command may auto-run *at all*.

- **Known-safe read-only allowlist** — a curated set of read-only inspection commands (list/read/
  search/status) may auto-approve under stricter policies. Validate flags and subcommands: a
  "read" tool with a flag that writes, executes, or reaches the network is no longer read-only.
- **Parse shell wrappers — don't trust the string.** When the command is `bash -lc "<payload>"` /
  `sh -c` / `zsh -lc`, parse the payload and only auto-classify when it decomposes into plain
  commands joined by a *tiny allowlist of safe operators* (`&&`, `||`, `;`, `|`). Reject — i.e.
  fall through to human approval — on redirections, subshells, command substitution, heredocs,
  process substitution, or any operator not explicitly allowed. A safe-looking wrapper hiding a
  dangerous payload is the most common bypass.
- **Interpreter-escape ban (allowlist hygiene).** Never let a user/policy allowlist a *prefix* that
  is an interpreter or shell: `python`/`python3 -c`, `node -e`, `perl`, `ruby`, `bash -lc`, `sh -c`,
  `pwsh -Command`, plus `env` and `sudo`. Allowlisting any of these is equivalent to allowlisting
  arbitrary code execution. Reusable allow suggestions must target concrete leaf programs, never a
  shell/interpreter/wrapper prefix.
- **Exec-escape flags hide in "normal" tools too.** The basename is not the whole story: many
  ordinary allowlisted programs have a flag or subcommand that runs arbitrary commands —
  `find -exec`, `xargs`, `git -c core.pager=`/`-c alias.x='!sh'`/`-c core.sshCommand=`, `make`,
  `npm`/`yarn` run-scripts, `tar --checkpoint-action=exec`, `ssh -o ProxyCommand=`, `rsync -e`,
  `awk 'BEGIN{system(...)}'`, `vim/less` shell-out. Auto-approval needs a *flag/subcommand-level*
  validator that denies these escape hatches, not just a basename match.
- **Planted-binary defense.** A bare basename allow (`git`, `rg`) can be satisfied by a `./git` the
  model just wrote into the writable workspace, which then reads/prints secrets through stdout even
  with network off. Every auto-allow rule must bind to an **absolute path in a trusted system
  location**, never a name resolved against a workspace-influenced `PATH` or cwd.
- **Dangerous-command detection** — independently flag destructive operations (recursive delete,
  force-push, history rewrite, disk format, ownership/permission changes) for mandatory approval
  even when other checks would pass.

## 6. Command-policy as a testable DSL

For anything beyond a hardcoded allowlist, express command policy as data, not branching code:

- **Ordered prefix rules**: a token pattern → a decision of `allow` | `prompt` | `forbidden`. A
  rule that *omits* its decision defaults to `allow` (a prefix rule is an allowlist entry). Any
  pattern token may be a set of alternatives. First match wins.
- **The unmatched default is fail-closed.** The per-rule `allow` default applies only to an explicit
  matched rule — never to the no-match case. When *no* rule matches, do not auto-allow: fall through
  to `prompt` (interactive) or deny (non-interactive). An allowlist whose "nothing matched" branch
  allows is not an allowlist.
- **Justification** on every rule, surfaced in approval/rejection UX. `forbidden` rules should name
  the recommended alternative (e.g. "use `X` instead").
- **Inline self-tests**: each rule carries `match` / `not_match` example invocations validated *at
  load time*. A policy that fails its own examples must fail to load — this prevents a typo'd rule
  from silently allowing or blocking the wrong commands.
- **Host-executable binding is mandatory for any auto-`allow` rule**: constrain a basename rule to a
  set of trusted absolute paths so a rule for `git` cannot be satisfied by a planted `./git` on a
  workspace-influenced `PATH`. A basename `allow` with no path binding is a bypass, not a
  convenience. (`prompt`/`forbidden` rules may match on basename since a human or denial still
  gates them.)
- **Layered precedence**: managed/admin policy, then user policy, then defaults. Deny/`forbidden`
  outranks `prompt` outranks `allow`. Make the layer that produced a decision visible in the trace.

## 7. Approval and escalation as a state machine

Graduated approval modes (strictest → loosest):

- **untrusted** — only known-safe read-only commands auto-approve; everything else asks.
- **on-request** — the model may *request* approval, but the policy engine still decides
  independently; a sensible interactive default. Phrase it as "the model can ask", never "the model
  decides what is safe": a compromised or jailbroken model under `on-request` will simply never ask
  and frame risky commands as routine. **Model self-classification is never a security boundary** —
  the deny/policy/sandbox layers must hold regardless of what the model claims about a command.
- **granular** — per-category booleans (shell approval, policy-`prompt` rules, skill-script
  execution, permission-request tool, server elicitations). **A `false` category auto-*rejects*,
  it does not silently allow** — explicit denial, not a gap.
- **never** — non-interactive; failures return to the model and are never escalated to a human.

**Escalation flow (run-then-escalate):** under sandbox-first policies, run the command inside the
sandbox; on failure, offer the human an *explicit* escalation to re-run with additional permissions
or outside the sandbox. The escalated re-run must carry `user_explicitly_approved = true` through
the decision trace. Never let the model self-escalate; escalation is a human grant. Distinguish a
sandbox-caused failure (worth escalating) from a genuine command error (not worth escalating).

## 8. Egress control via a local proxy

Network is granted at two layers that must agree:

- The OS sandbox **blocks all outbound network except the exact loopback address+port** of a local
  proxy the runtime owns. With network "off", even that exception is omitted. "Allow loopback" is
  *not* good enough — a broad loopback allowance lets commands reach the Docker socket, kubelet,
  local databases, a browser remote-debug port, or other local agent APIs. Pin the single proxy
  `host:port`; deny all other loopback and all non-loopback egress.
- The **local proxy enforces a per-destination allowlist** (host/port, protocol), so "network on"
  still means "only approved domains". Inject the proxy's address into the child via the standard
  proxy environment variables and require proxy-only networking when a managed network policy is
  active.

This makes deny-by-default egress real, but **the enforcement must be at the kernel/network layer,
not env vars** — a child can unset proxy env vars and open a raw socket. The proxy env vars are a
convenience for proxy-aware clients; the *boundary* is a per-platform network confinement:
- **Linux** — network namespace with no route except the proxy, or nftables/iptables owner-scoped
  egress rules, or an eBPF/cgroup egress filter.
- **Windows** — Windows Filtering Platform (WFP) rules scoped to the sandboxed token/AppContainer.
- **macOS** — Seatbelt network rules are coarse; if you cannot constrain egress to the single proxy
  endpoint, route through a network namespace-equivalent (e.g. a per-task proxy with a hardened
  client config) or **fail closed** rather than claiming egress is contained.
If no platform mechanism can enforce the block, treat network as unavailable, not open.

## 9. Helper-process hardening

The process that applies the sandbox and the sandboxed child both need hardening. The child inherits
the parent's open resources unless you stop it, and an inherited resource is an exfil channel that
*bypasses both the filesystem and network sandbox* — an open authenticated socket, an SSH-agent fd,
a proxy fd, or a credential-bearing env var lets a "network off" command still reach the network or
read secrets. Before sandboxed exec:

- **Default-close every non-stdio file descriptor** (close-on-exec by default; pass only the fds the
  child genuinely needs). Never let the child inherit the agent's API sockets or auth fds.
- **Start from a strict environment allowlist**, not the parent's full env. Strip credential-bearing
  variables (cloud tokens, `SSH_AUTH_SOCK`, API keys) unless a specific task explicitly needs a
  scoped, short-lived one.
- Drop ambient privileges before exec, and disable core dumps (a dump leaks the memory of a process
  that handled secrets).
- Give helper processes bounded lifetime with orphan self-healing after a hard parent death. A
  sandbox helper that outlives its parent or keeps the agent process alive is its own footgun.

## 10. Persistent interactive process sessions (not just one-shot exec)

Sections 1–9 model a command as one shot: run, capture, exit. Agents also need **long-lived interactive
processes** — a REPL, a dev server, a debugger, a shell the model drives across several turns. That is a
different lifecycle, and the difference is where the bugs are.

- **Identify and reuse the process across tool calls — with an unforgeable, generation-bound handle.**
  Allocate a handle on open; subsequent calls target that handle to write stdin and read new output,
  instead of re-spawning. The handle must be **unguessable and bound to its generation + owner**, not a
  small reused integer: when session 7 closes and the id is recycled, a delayed `write_stdin(7, "rm …")`
  from an earlier turn must hit *nothing*, not whatever live process now holds id 7. Reject stale or
  wrong-owner handles. Keep a registry of live processes keyed by that handle; allocate ids so concurrent
  opens cannot collide. Run the *open* through the same approval → sandbox → escalate orchestration as a
  one-shot (sections 5–7); the session inherits that decision — but re-authorize per the stdin rule below.
- **Read until quiescent, not until EOF.** A one-shot reads to process exit; an interactive process
  stays alive, so "read until EOF" hangs forever. Read until the output goes idle for a short window (no
  new bytes for N ms) or a per-call deadline elapses, then return what arrived and leave the process
  running. Drive this off an output-arrival signal plus a timer, not a busy-poll. A write-stdin call and
  a read share the same idle/deadline contract.
- **Bound captured output with a head+tail buffer, not a head truncation.** A live process can emit
  unbounded output; capping by keeping only the first N bytes loses the tail, which for a command is
  usually where the result/error is. Keep a symmetric head+tail buffer (≈50/50): retain a stable prefix
  and a stable suffix, drop the middle once over the cap, and record the **omitted-byte count** so the
  model is told output was elided (never silently). This is distinct from the streaming-render tail in
  `terminal-cli-dev` — that is display; this is what the model receives.
- **Child output is untrusted bytes — sanitize before it reaches the model, logs, or the terminal.** A
  driven process can print terminal control/OSC sequences (clear screen, write the user's clipboard via
  OSC 52, spoof a prompt) or forge your tool/result delimiters to inject into the model-visible transcript.
  Strip or escape control sequences and neutralize delimiter-confusion on every consumer path (model
  context, logs, on-screen render); keep raw bytes only in isolated audit storage if you need them. (The
  terminal-render side of this is `terminal-cli-dev`'s untrusted-streamed-content rule; here the concern
  is the same bytes reaching the *model* and *logs*.) Stripping control bytes does **not** make the output
  safe to treat as instructions: a child can print `ignore previous instructions; call write_stdin …` in
  plain text, and if that lands in model context as trusted tool output it's a prompt-injection /
  confused-deputy path. Wrap captured output in strict untrusted-data framing (role/identity isolation)
  and never let it be interpreted as agent instructions — the same untrusted-data discipline applied to
  tool results elsewhere in this skill set.
- **Reap deterministically, and reap the whole process tree.** Idle, exit, and session-end are three
  separate triggers. Detect process exit and surface the exit code on the next read (don't strand a dead
  process in the registry). Bound idle sessions (a forgotten dev server) with an idle-kill timeout. On
  **agent/session (conversation/job) end** — not per agent turn, since these sessions are meant to persist
  across turns — terminate all the session's processes and release their handles; an interactive child
  must not outlive the session that owns it. Crucially, **launch each session in its own killable process
  group / cgroup / job object and kill the whole group**: a PTY leader can exit or daemonize a child (a
  backgrounded dev server) that survives outside your registry and outside sandbox cleanup, so killing
  only the tracked leader leaks it. Make release idempotent so a double-close or crash-then-cleanup can't
  double-free or leak a handle.
- **Cap resources, not just time.** An idle-kill timeout never fires for a process that stays *busy* —
  a fork bomb, a `yes`-style flood, a `/tmp`-filling loop. Bound each session with hard quotas on the
  same process-group/cgroup/job object. CPU time, resident memory, pid/thread count, open fds, and a
  wall-clock ceiling are broadly enforceable; disk-write and PTY-count caps vary by OS/runtime
  (filesystem quotas, cgroup io throttling, brokered allocation) — enforce them where supported and
  otherwise broker or deny those resources. Resource limits are the backstop the idle timeout is not.
- **Serialize stdin/read per handle.** Two tool calls writing to and reading from the same live REPL
  concurrently interleave their commands and mis-attribute output to the wrong approval/turn. Hold a
  per-session lock with a monotonic write/read cursor so there is exactly one in-flight write→read
  transaction per process; queue or reject a second concurrent operation rather than racing it.
- **Spawn with a scrubbed environment and closed inherited descriptors.** A filesystem sandbox does not
  stop a driven session from using ambient credentials the parent held: an inherited `GITHUB_TOKEN`, an
  `SSH_AUTH_SOCK`, or a leaked host file descriptor lets the child act with the agent's own authority.
  Launch each session with an allowlisted minimal env (no secrets unless the task requires that exact
  one) and close non-allowlisted inherited fds/sockets — the same least-privilege discipline as a hook
  or auto-reviewer subprocess elsewhere in this skill set.
- **stdin is an authorization surface, and command-boundary classification is weak inside a REPL/editor.**
  Writing stdin to a live process drives it somewhere the open-time approval never covered: an approved
  `python` REPL runs `os.system("…")`, an approved editor runs `:!sh`, an approved shell runs anything.
  A command classifier that parses an argv cannot reliably see these embedded escapes. So: **never expose
  a persistent *unsandboxed* interactive session** (the session always keeps the sandbox it opened under —
  an in-sandbox escape is contained, an unsandboxed one is not), and treat each stdin write as a fresh
  authorization event, defaulting to **deny/ask on ambiguity** rather than trusting that a REPL/editor
  input is benign. The OS sandbox, not the input parser, is the real boundary for what a driven session
  can do; classification of stdin is best-effort on top of it, never a substitute.
- **Secret stdin must not echo, persist, or land in the transcript.** Writing a password/token into a
  live `psql`/`ssh`/shell/REPL prompt is different from passing it as an env var: the child often echoes
  it back, the shell saves it to history, and the read path captures it into the model-visible output and
  logs — env-scrubbing (above) doesn't help because the secret arrives via stdin, not the environment.
  Classify secret-bearing stdin and deliver it non-echoed (a no-echo pipe / askpass-style channel),
  redact any matching echo from every transcript/log surface (the redaction non-negotiable below applies
  to *input* echoes too, not just command output), and disable or purge interactive history for sessions
  that receive secrets.
- **A PTY lets the child inject its own input — close that path.** With a controlling terminal a child can
  push bytes straight into its own input queue (`TIOCSTI` and equivalents), running commands with **no**
  `write_stdin` authorization event at all — the authorization surface above is bypassed entirely. Block
  terminal input-injection at the kernel/sandbox layer (seccomp-filter the ioctl, or run without a
  controlling TTY unless the task genuinely needs one). Reliably *detecting* all non-write-path input is
  not portable, so don't promise universal detection — block the known injection primitives, and where
  unexpected/out-of-band input is observable, treat it as a session compromise and kill the session. This is why a PTY session is strictly more
  dangerous than a plain stdin pipe and must stay sandboxed.
- **A live session can grow its own command channel — bind it under the egress controls.** Even with
  stdin and TTY-injection closed, a persistent child can open a socket or debug/IPC server (bind a
  localhost or network port, a debugger listener, a control FIFO) and take commands through *that*,
  bypassing `write_stdin` authorization and the session handle entirely. Deny inbound listeners by
  default and route any allowed bind through the same per-session network policy as §8 — here the listen/bind
  (ingress) side, controlled separately from egress (allowlist specific ports with sandbox/firewall
  enforcement, kill on an unapproved bind). A persistent session is
  not just longer-lived than a one-shot — it has more time and more surface to open a side channel, so
  its network posture must be at least as locked down as a one-shot's, not relaxed for convenience.
- **Bind the session to an authorization/policy generation; a long-lived session must not act under stale
  authority.** A one-shot is authorized once and gone; a persistent session outlives the policy that
  opened it. If the user revokes a scope, the sandbox profile tightens, a credential is rotated, or
  approval mode changes, an already-open session otherwise keeps its old capabilities/fds/sandbox and
  keeps acting under the *old* authority on every later stdin write. Stamp each session with the
  authorization/policy generation it opened under; on any policy/credential/sandbox change, suspend or
  kill sessions whose generation is now stale unless they are explicitly re-approved under the new
  generation. (Same generation-binding discipline as approval single-use and the retry/re-render tuple
  elsewhere in this skill set — a persistent process is just a long-lived holder of an authorization that
  can go stale.) The OS-isolation strength of that sandbox is §1–§4's job, and it matters more for a
  persistent session than a one-shot: a long-lived same-UID child has time to use `ptrace`/`/proc`/
  same-UID IPC to inspect or drive the agent or a sibling session. Isolate sessions from each other and
  from the agent (per-session UID or user/PID namespace, deny cross-tree ptrace/procfs) under §1–§4 —
  don't rely on the session-lifecycle rules here to provide that containment.

## Non-negotiables

- The kernel sandbox and a closed process surface are the only real boundaries; path/basename/string
  checks are advisory and must never be the sole gate for an irreversible or exfil-capable action.
- Auto-approve only when a sandbox is actually enforceable on this platform; otherwise ask or
  reject. Unavailable/disabled/bypassed/excluded-command sandbox states never imply allow.
- Never resolve the OS sandbox launcher (`sandbox-exec`, the helper binary) through `PATH`.
- Never allowlist an interpreter, shell, or wrapper prefix; every auto-`allow` rule must bind to a
  trusted absolute executable path, and must deny exec-escape flags (`find -exec`, `git -c`,
  `tar --checkpoint-action`, `ssh -o ProxyCommand`, …) — basename match alone is a bypass.
- Filesystem write and network access are separate grants; default network off in write profiles.
- Reads are a confidentiality boundary too: deny-by-default the sensitive credential/key/browser/
  agent paths and validate auto-approved read targets against a read allowlist — broad read + any
  exfil channel (stdout, artifacts, model context) leaks secrets.
- Egress is enforced at the kernel/network layer scoped to the single proxy `host:port`, never by
  proxy env vars alone and never as a broad "allow loopback"; fail closed if the platform cannot
  enforce it.
- Close all non-stdio FDs and start from an env allowlist before sandboxed exec; an inherited
  socket, agent fd, or credential env var bypasses both sandboxes.
- Authenticate helper/sandbox-launcher invocations so a child cannot re-enter helper mode with
  looser attacker-chosen policy.
- Protect VCS hooks/config, agent config, and on-disk policy as read-only even inside writable
  roots; account for hard-link/symlink escape and the check-vs-write (TOCTOU) race — prefer kernel
  enforcement or race-safe `openat2`/`O_NOFOLLOW` over validate-then-write.
- `external-sandbox` pass-through requires attesting the outer boundary; unattested → inner sandbox
  or fail closed.
- Refresh sandbox/policy configuration synchronously after any permission, settings, or
  writable-root change so a pending command cannot slip through stale policy.
- A policy DSL that fails its own inline `match`/`not_match` examples must fail to load.
- Apply secret/path redaction to *all* model- and user-visible surfaces (stdout/stderr, generated
  artifacts, test snapshots, approval prompts, logs), not only structured diagnostics. Diagnostics
  themselves may expose sandbox type, decision category, and policy layer, but never raw command
  strings, local paths, env values, proxy targets, or credentials.

## Routing

- The authorization *decision trace*, deny/ask/allow precedence, and "sandbox is defense-in-depth
  not permission" rule live in `SKILL.md` Core Workflow — this reference is the enforcement layer
  beneath them.
- Network path/egress transport identity and mTLS for the proxy hop → `platform-service-connectivity`.
- Rollout of a behavior-changing default approval mode or sandbox profile → `platform-release-engineering`.
- Decision-trace signal schema and egress-block telemetry → `platform-observability`.
- Reproducing a sandbox escape, stale-policy slip, or escalation bug → `defect-diagnosis`.
- Terminal approval prompts / escalation UX rendering → `terminal-cli-dev`; the terminal UI that *displays* an interactive process's stream is also `terminal-cli-dev` (§10 here owns the agent-side process-session lifecycle, not its on-screen rendering).
- Session-end cleanup that terminates all live processes is invoked by the turn/session terminator in `agent-turn-lifecycle.md`; §10 owns the per-process lifecycle it calls.

## Shell execution authorization

Shell execution needs command-aware authorization, not string-prefix trust. Parse compound commands, operators, wrappers, environment assignments, redirections, heredocs, substitutions, and platform-specific expansion forms with a fail-closed path when parsing is unavailable, too complex, or divergent. Deny rules take precedence over ask/allow, dangerous or destructive operations require explicit approval, reusable allow suggestions must avoid bare shell or broad wrapper prefixes, and command fanout must be bounded. Read-only classification must validate flags and subcommands that can execute code, write files, perform network access, or change the effective binary/resource target.

## Filesystem write authorization

Filesystem writes must be authorized at the resource boundary and checked again immediately before mutation. Normalize observable paths for matching, but preserve user-visible input only after authorization; validate containment for absolute/relative paths, traversal, encoded or Unicode-normalized traversal, null bytes, platform path forms, glob and end-of-options behavior, symlink/hardlink and time-of-check/time-of-use swaps, and output redirections. Require prior full reads for overwrite/edit tools, reject stale or partially read files, re-check modification time/content in the no-await critical section before write, block denied settings or policy files, guard secret-bearing stores, and record undo/history or diff evidence when the surface supports it.

## Sandbox enforcement as defense-in-depth

Sandbox enforcement is defense-in-depth, not permission. Sandbox enabled, disabled, unavailable, bypassed, excluded-command, managed-lock, dependency-missing, network-proxy, or platform-unsupported states must be explicit in the decision trace. Auto-allow for sandboxed execution is valid only after deny/ask rules, path/resource validation, and sandbox configuration freshness are checked; unsandboxed fallback, unavailable sandbox dependencies, excluded commands, weaker isolation, or user-requested bypass must not imply permission allow. Refresh sandbox configuration synchronously after permission or settings changes so pending commands cannot slip through stale policy. For the enforcement layer beneath this decision — OS-sandbox composition (Seatbelt/Landlock+seccomp/bubblewrap/Windows restricted-token), named sandbox profiles, writable-root privilege-escalation carve-outs, hard-link escape, the loopback-only egress proxy, the command-policy DSL, and the run-then-escalate state machine — see `references/agent-command-sandbox.md`.

## Model-driven host OS, desktop, or GUI control

Treat model-driven host OS, desktop, or GUI control as a high-risk local action control plane, not an ordinary tool surface. Bind every control session to principal, workspace, host identity where available, session/incarnation, platform and capability generation, permission/access grant generation, tool-schema generation, display/screenshot generation, coordinate mode, native bridge generation, abort-signal generation, and cleanup generation. Separate permission discovery or access-request tools from action tools: discovery may check and explain access without acquiring exclusive control, hiding applications, installing global hotkeys, reading clipboard, sending input, or changing focus. Real control requires a single-owner lock or equivalent lease with atomic acquire, re-entrant same-session behavior, live-owner detection, stale-lock recovery, and owner-bound release; blocked sessions must surface visible uncertainty rather than running concurrently. Screenshot, display, target-app, and coordinate state must be captured under one stable generation; coordinate mode and image-resize policy cannot drift after tool descriptions or model-visible hints are rendered. Any host state mutation needs paired finality: hidden or defocused apps restored, modifier keys and mouse buttons released even on partial failure, clipboard writes read-back verified before paste and restored afterward where possible, global abort hotkeys unregistered, native event-loop pumps stopped, and locks released on normal turn end, abort during streaming, abort during tool execution, shutdown, and cleanup failure paths. Native or OS calls need platform/support checks, bounded timeouts, late-result suppression, and best-effort cleanup that cannot mask the primary failure or leave a broader active control session. Diagnostics may expose bounded categories, counts, capability states, and non-reversible digests, but not screen contents, app names, window titles, clipboard text, local paths, raw coordinates tied to private displays, credentials, command lines, bundle ids, environment values, or free-form native errors.
