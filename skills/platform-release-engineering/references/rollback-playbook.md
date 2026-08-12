# Rollback Playbook

## Rollback by strategy

| Rollout strategy | Rollback mechanism | Time to steady |
|---|---|---|
| Canary (traffic-shift) | Set canary weight to 0; drain | 30s - 2 min (mesh propagation) |
| Blue-green | Switch Service selector / VirtualService destination back | seconds |
| Rolling update | Re-deploy previous image digest | minutes (per-pod replacement) |
| In-place mesh policy | Re-apply previous policy YAML | seconds |
| Config-center flip | Set value back | < 1s (push update) |
| Static config in image | Re-deploy with previous image | minutes |

Choose strategy with rollback in mind. A 2-hour rolling update means a 2-hour rollback.

## The rollback command

```
plat rollback --service=<svc> [--to-version=<v>]
```

Without `--to-version`, rolls to the most recently promoted known-good version (the one that ran before the current).

Behavior:
1. Fetch previous known-good image digest from audit log.
2. Initiate the same workflow as a forward deploy, but with the previous digest.
3. Skip review for rollback (it's restoring known state) — unless the rollback target is itself in a known-bad list (e.g. an old version with a CVE).
4. Wait for steady state; verify with smoke probes.
5. Log the rollback event.

## What "previous known-good" means

A version is "known-good" if:
- It was promoted to 100% traffic for at least N hours without abort.
- No P0/P1 incidents attributed to it during that window.

The audit log filters versions by this. Don't naively pick "the version before this one"; that version might be the one that caused yesterday's incident.

## Data migration rollback

Data migrations are the hard case. Three patterns:

### Pattern 1: Forward-compatible (preferred)

Schema changes are designed so old code can read new schema and new code can read old schema. Then:
- Step 1: deploy schema migration.
- Step 2: deploy code that uses new schema.
- Rollback: revert code only; schema stays. Data is intact.

This is the default for non-emergency migrations. Examples:
- Adding a column with a default → forward-compatible.
- Adding a new table → forward-compatible.
- Renaming a column → NOT forward-compatible directly; do "add new + dual-write + cut over + drop old" over multiple releases.

### Pattern 2: Backward-replayable

Schema changes ship with a forward migration AND a back migration. If you must roll back:
- Run the back migration.
- Revert code.

This is dangerous for migrations that drop columns or merge tables (data loss). Use only when forward-compatibility is impossible.

### Pattern 3: Soft-launched migration

The migration is gated by a config flag. Rollback flips the flag without touching schema.
- Slow to clean up old paths.
- Safe rollback.
- Best for migrations of frequently-changing or risky tables.

## Rollback for mesh policy

VirtualService changes propagate via mesh control plane. Rollback:
- Revert the YAML.
- Mesh reloads (seconds).
- In-flight requests handled by old policy until next conn refresh.

For breaking mesh changes (mTLS trust domain), rollback may require coordinated steps across multiple namespaces. Document the order.

## Rollback for secrets

Secrets that have been rotated cannot be un-rotated (old secret is invalidated at source). If a rotation causes outage:
- Old secret is dead.
- Either: roll forward (deploy code that uses new secret).
- Or: rotate again to a third value, deploy code accepting both.

Plan rotation with rollback in mind: keep N-1 valid for a grace period.

## Drill schedule

A rollback path is not real until you've used it. Schedule:

- **Per-quarter**: pick one non-critical service, deploy a no-op change, rollback through the production path. Time the rollback. Note any manual steps that should be automated.
- **Per-major-platform-change**: any change to the rollback mechanism itself (control plane, mesh, registry) triggers a drill on a sample service.
- **Per-incident-postmortem**: if rollback failed or was slow during an incident, mandate a drill on a similar service within 30 days.

If you cannot drill rollback, you cannot rely on rollback.

## Incident-time rollback decision tree

```
P0 incident, suspected cause: recent deploy
   │
   ▼
Was the change pure code / config? ───── yes ──► rollback first, investigate after
   │ no
   ▼
Was the change a data migration? ────── yes ──► consult forward-compatibility pattern;
   │                                          rollback may be unsafe; consider roll-forward fix
   │
   ▼
Was the change mesh / IAM / secret? ─── yes ──► follow per-domain rollback playbook;
                                                may require coordinated steps
```

Rule of thumb: if rollback is safe and the issue is severe, roll back. Investigation can happen with traffic restored.

## What goes wrong

- Audit log doesn't record digest, only tag → rolling back to "tag" pulls the new image again. Always record digest.
- Previous version's image evicted from registry → rollback target unavailable. Retain at least last 10 deployed digests for every prod service.
- Rollback runs but skips the canary-check task → if the previous version had a latent bug, you deploy it blind. Still run smoke probes after rollback.
- Mesh propagation slower than expected → rollback "succeeded" but some pods still see old policy. Verify via mesh access logs, not just control plane.
- Database migration not forward-compatible → code rolled back but DB now ahead. Service may crash on read. Plan migrations with this in mind.
