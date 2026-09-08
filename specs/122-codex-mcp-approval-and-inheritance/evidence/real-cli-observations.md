# Real-CLI observations

The suite drives a fake CLI, so the properties below were measured against the
real one and are recorded here rather than left as narrative in the plan. Host
paths, credentials, and server names other than the ones under test are omitted;
what remains is the observed event shape.

## Approval arms (single variable, all other flags identical)

Wrapper flags held fixed: `--disable hooks --disable shell_tool --sandbox <mode>
--ephemeral --skip-git-repo-check -c web_search="disabled" -c
approval_policy="never"`.

| sandbox | ephemeral | packet approval mode | `read_packet` item |
| --- | --- | --- | --- |
| read-only | yes | absent | `status=failed`, `error.message=MCP tool call requires approval, but approval policy is never` |
| read-only | no | absent | same |
| workspace-write | yes | absent | same |
| danger-full-access | yes | absent | `status=completed` |
| read-only | yes | `default_tools_approval_mode="approve"` | `status=completed`, result carries `PACKET_CHUNK 0:73/73` |

## Foreign-server reachability

A source home declaring one foreign server reports it as enabled:

```
mcp list --json  ->  [{"name": "<foreign>", "enabled": true, ...}]
```

The wrapper run over that same source home returns a verdict
(`{"reviewer":"codex","status":"passed","reviewer_family":"openai"}`). It could
not, had the foreign server reached the private home: the preflight refuses a
second enabled server.

Before the private home, the same shape executed. A server declaring
`readOnlyHint: true` on a tool that appends to a file was auto-approved and the
file was written; the same server without that declaration was refused before
execution. A host REPL server declaring `readOnlyHint: true` on a tool that
evaluates arbitrary code ran to completion during a packet-only review.

## Private-home preconditions

| Property | Observation |
| --- | --- |
| `mcp list` under a home holding only a linked `auth.json` | `[]` |
| inference and packet read from that home | completed; verdict produced |
| skill under `$CODEX_HOME/skills/<name>/SKILL.md` | invoked; its content quoted back |
| the same package reached through a symlink | `NO_SKILL` |
| model preference dropped | `reasoning_output_tokens` 422 -> 0 on the same packet |

## What these do not establish

That a hostile diff can induce a foreign tool call. Two attempts to induce one
from inside the reviewed diff did not reproduce it on either pre-fix wrapper;
the prompt's untrusted-data framing held. The reachability results above stand
on direct instruction, which is why the design removes reachability rather than
relying on model refusal.
