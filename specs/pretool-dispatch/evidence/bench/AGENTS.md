# pretool-dispatch bench Agent Contract

`hook_latency.py` times the PreToolUse hooks of two extracted plugin trees on the same payloads. It reports a parallel figure (how Claude Code runs hooks) and a serial figure (how the OpenCode plugin and `agy-bridge.py` run them).

Rules:

- **A measurement tool, not a gate.** Nothing in `make test` runs it. Its results are recorded in `../validation.md` together with the two revisions, the host, the jq and Python versions, and the load.
- **Same run, same payloads.** Compare a baseline and a candidate only within one invocation. Figures from different hosts or runs are not compared.
- **Changes keep the output format.** Earlier recorded figures must stay comparable. A changed measurement method gets a note in `../validation.md`.

Validation:

- `python3 -m py_compile specs/pretool-dispatch/evidence/bench/hook_latency.py`
