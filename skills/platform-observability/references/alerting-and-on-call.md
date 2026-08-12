# Alerting and On-Call

## Two patterns

### Pattern A — Prometheus AlertManager
Standard CNCF stack. AlertManager dedupes, groups, silences, routes to receivers (email, chat, pager). Use when:
- Multiple delivery channels and complex routing.
- Alert rules co-located with Prometheus.
- You need silencing UI for ops.

### Pattern B — Grafana-only alerting (chat-webhook)
Grafana evaluates alert rules against the long-term metric store, posts to a webhook receiver. Use when:
- Single delivery channel (chat/IM platform).
- You want alert authoring next to dashboards.
- Operational simplicity > routing flexibility.

Both patterns appear in the wild. Pick one per environment; running both invites duplication. The grafana-only pattern is the de-facto choice when AlertManager is disabled in the Prometheus deployment.

## Webhook receiver shape (Pattern B)

A small control-plane API receives grafana webhooks and forwards to the chat platform:

```
POST /alerts/grafana_hook
Body: grafana alert payload (status, ruleName, labels, annotations, values)
→ Adapter formats a chat message with: severity, service, summary, runbook link, dashboard link, alert id
→ Chat platform SDK posts to the on-call channel / group
```

The adapter MUST attach a runbook link. Drop alerts without a `runbook_url` annotation; refusing to deliver them forces authors to write the runbook.

## Severity → channel routing

| Severity | Channel | Ack window | Escalation |
|---|---|---|---|
| P0 | On-call group chat + phone push | < 5 min | Page secondary if no ack in 10 min |
| P1 | Team chat channel | < 1 hour during work | None |
| P2 | Daily digest channel | None | None |

Pager integration (if used): only P0. Never page on P2.

## Runbook contract

Each alert annotation `runbook_url` points to a wiki page (Feishu/Confluence/Notion/equivalent) containing:

1. **Summary** — one sentence: what fired, what user pain it predicts.
2. **First check** — one query (dashboard link or kibana saved search) to confirm/refute.
3. **Quick fix** — one command or playbook step that resolves the most common cause.
4. **Escalation** — who to notify if quick fix fails.
5. **Post-incident** — link to the incident review template.

A runbook longer than one screen is not a runbook; it is a manual. Link to deeper docs from the runbook, do not embed them.

## Runbook discovery for agents

If the team wiki has a CLI or API (e.g. `lark-cli` for Feishu, `confluence` API), agents SHOULD pull the runbook content into the diagnosis session rather than asking the user to paste. The skill does NOT embed runbook content directly; it tells the agent to fetch.

Keep wiki/CLI lookup locations in local project docs or private memory, not in this shared skill.

## On-call shift handoff

At end of shift, the outgoing on-call posts in the team channel:
- Number of pages received.
- Number resolved vs escalated.
- Any open incident handed off.
- Any silenced alert that should be unsilenced.

This is process, not tooling. If it's not happening, the alert pipeline is being ignored.

## Anti-patterns

- P0 to email only → guaranteed miss.
- Alert with no runbook → page-and-pray.
- Alert on every cause → noise → ignored channel.
- Silencing as a long-term fix → silence rot.
- Webhook receiver with no retry → lost alerts on transient chat-platform 5xx.
