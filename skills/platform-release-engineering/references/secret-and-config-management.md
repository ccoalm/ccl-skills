# Secret and Config Management

Three tiers, three lifecycles. Mixing them up is a recurring source of outages and leaks.

## The three tiers

### Static config

What it is: values that change only when the application changes. Defaults, feature definitions, hardcoded behavior switches that no operator should flip without a code review.

How it ships: bundled into the image, in a known path (`conf/<env>.yml` or `config/default.yml`). Per-env split is acceptable (`conf/prod.yml`, `conf/test.yml`) but only for values that legitimately differ per env (DB hostnames, queue cluster names).

Updates: require a code change + deploy.

Examples:
- DB connection pool sizes.
- Default timeouts.
- Feature definitions ("there is a feature called X").

### Dynamic config (config center)

What it is: values an operator can flip at runtime without redeploy. Feature flags, rate limits, A/B test variants, kill switches.

How it ships: through a config center (Apollo, etcd KV, Consul KV, internal dcc-style service). Application SDK subscribes, caches locally, receives push updates.

Updates: configurable via API / UI; audit-logged like deploys.

Examples:
- `feature_X_enabled = true | false`.
- `rate_limit_per_user = 100/s`.
- `experiment_split = { control: 50, variant_a: 25, variant_b: 25 }`.
- Kill switch for a degraded-mode path.

Feature-flag lifecycle (flags are release levers, not just config values — they decouple *deploy* from *release*: code ships dark, the flag turns it on; per Fowler/Hodgson "Feature Toggles", flags are inventory with a carrying cost):

- Classify at creation: **release toggle** (transient, days–weeks), **experiment toggle** (weeks), **ops toggle** (usually short-lived — retire once operational confidence is gained; only a small, deliberate subset become long-lived **kill switches**, each with an owner and periodic review), **permission toggle** (long-lived). The categories age differently; manage them differently.
- Transient toggles get an owner and an expiry/cleanup task when created (an expiration date on the flag itself is a workable enforcement). A flag past its expiry is debt: surface it (report, lint, or CI warning) — every stale flag is an untested code path and a config surface someone can flip by accident.
- A production flag flip that exposes new behavior IS a release event, not "just config": deploy-decoupled does not mean gate-decoupled. Risk-class it like a deploy (high-blast-radius flips take the same approval path as R8), keep it in the same audit trail, stage the exposure where blast radius warrants (cohort/percentage ramp with SLI checks, per the promotion gate), and have the kill-switch/rollback path tested before the flip.
- Test both sides of every mutable flag deployed to production — "we never plan to flip it" is not a waiver, because the untested branch stays one operator click / stale automation run away from live traffic. The full flag combination space is untestable, so test the combinations that will actually run (current production config, the config about to go live, and the fallback/off state — per Fowler), and for cohort/percentage ramps also the *mixed* state the ramp itself creates — old and new behavior running concurrently against shared state (reader/writer compatibility, caches, queues) — before enabling the ramp. Declare dependencies between flags where one implies another, keep the concurrently-active flag count low, and retire release toggles as part of the feature's definition of done.

### Secrets

What it is: credentials, tokens, certs. Any value that, if leaked, causes a security incident.

How it ships: via a secret store (cloud KMS, Vault, internal secret manager). Injected into pods at start (init container, sidecar, or projected volume). Never committed to git, never in a regular ConfigMap.

Updates: rotation pipeline. Old value remains valid for a grace window during cutover.

Examples:
- DB password.
- Third-party API key.
- TLS cert + private key.
- OAuth client secret.

## Tier selection rules

| Need to flip without redeploy? | yes → dynamic config |
| Sensitive to leak? | yes → secret store |
| Both? | secret-aware dynamic config (some platforms support encrypted KV with audit) |
| Neither? | static config |

If you find a feature flag in static YAML, move it to dynamic. If you find a password in dynamic config, move it to a secret store.

## Static config patterns

```
service/
  conf/
    default.yml          ← shared defaults
    prod.yml             ← prod overrides (no secrets)
    pre.yml
    test.yml
    dev.yml
```

Load order: default → env-specific. Application reads `env.Lane()` or equivalent to pick the file.

If two envs share most config, factor shared values into `default.yml` and let env files override only what differs.

## Dynamic config (config center) shape

Client SDK contract:

```go
val, ok := dcc.GetString("rate_limit.user_per_second")
flag := dcc.GetBool("feature.checkout_v2.enabled")
dcc.Watch("kill_switch.payment", func(newVal interface{}) {
    // react to flip
})
```

Server-side:
- Pushed to clients via long-poll or websocket.
- Updates are atomic per key.
- Versioning: each update has a version number; clients track their last-applied version.
- Rollout: a value can be staged (visible to canary lane only) before promotion.

Operator-facing:
- UI with audit log: who flipped what, when, why.
- Diff and dry-run: preview which clients would receive a change.

## Secret store patterns

### Pattern A — Cloud-provider KMS / Secrets Manager

AWS Secrets Manager, GCP Secret Manager, equivalent. Service reads via SDK with IAM role. No file on disk.

```
appCode → cloud SDK → KMS → secret value
```

Pros: managed, audited, integrated with cloud IAM.
Cons: cloud-coupling; cross-cloud is painful.

### Pattern B — Self-hosted Vault

HashiCorp Vault deployed in-cluster. Apps authenticate via k8s ServiceAccount JWT and request secrets.

Pros: cloud-neutral, fine-grained policy, dynamic secrets (e.g. short-lived DB credentials).
Cons: you operate Vault.

### Pattern C — Internal KMS

A platform-team-written service that brokers between cloud KMS, k8s ServiceAccount, and pods. Hides cloud specifics; exposes a uniform API.

Pros: customization, integration with internal RBAC.
Cons: you own the implementation — and the bar for a production KMS is high. Most internal KMS implementations are dangerously incomplete on day one.

**Required for an internal KMS to be production-grade** (not "an encrypted key-value store"):

- **Envelope encryption with DEK / KEK separation**: data is encrypted by a per-object data encryption key (DEK); the DEK itself is encrypted by a long-lived key encryption key (KEK). The KEK never appears in plaintext outside the trust root (HSM, cloud-provider KMS, or a sealed enclave). DEKs are short-lived and per-object.
- **AEAD ciphers only**: AES-GCM, ChaCha20-Poly1305, or equivalent. AES-CBC + PKCS#7 padding without an authentication tag is a finding — silently accepts tampered ciphertext.
- **KEK is never in application memory as a literal**: not a base64 string in code, not in `.env`, not in a config-center value. Acceptable sources: HSM (PKCS#11 / cloud HSM), cloud-provider KMS root, sealed enclave. If the application process can dump its own memory and recover the KEK, the design is broken.
- **Key versioning**: every encrypt records the KEK version used; decrypt reads the version and resolves the right KEK. Without versioning, rotation is impossible.
- **Key rotation is operational, not aspirational**: scheduled (cadence per policy, typically 90 days for KEK, faster for DEK), automated, with a re-wrap pipeline for existing ciphertexts and a deprecation horizon for the old version. "We support rotation in principle but never run it" is the same as no rotation.
- **Audit log per operation**: every encrypt / decrypt / rotate / disable records caller identity (workload identity, not just IP), key id, key version, operation, timestamp, request id. The audit log is append-only and stored separately from the KMS service itself. A KMS without an audit trail cannot meet any compliance bar.
- **Per-key authorization (ACL)**: not every caller can use every key. The KMS enforces caller-x-key allowlist, not "anyone in the cluster can decrypt anything".
- **Backing store is durable + encrypted at rest**: a real database or object store with per-row/per-object encryption, not a config center treated as a key-value cache. Storing ciphertext in a config center conflates "fast read" with "durable encrypted store" — wrong layer.
- **DR for the KEK**: secure backup, multi-region replication, or sealed split-shares (Shamir or equivalent). Losing the KEK loses all data forever; "we'll add this later" is not acceptable.

**Anti-pattern guardrails** (commonly observed in early-stage internal KMS):

- KEK as base64 literal in source / env / committed config → equivalent to plaintext.
- AES-CBC + PKCS#7 without HMAC / GCM → silently accepts tampered ciphertext.
- "Encryption" implemented as `xxx_encrypt(value)` writing to a config center under a regular key name → there is no envelope, no DEK, no key version, no audit; it is a config rename.
- K8s ServiceAccount TokenReview as the only authorization → any pod in the cluster (or any compromised pod) can decrypt anything; missing per-key ACL.
- No rotation → first KEK in production is the KEK forever; if it ever leaks, every byte ever encrypted is exposed.
- No audit log → no way to answer "who decrypted X on date Y" during an incident.
- Ciphertext stored in a config center as an ordinary key/value → DR / encryption-at-rest / backup story collapses to the config center's story, which usually does not meet KMS bars.

When the project is not ready to meet these bars, do not build "Internal KMS Pattern C" — use Pattern A (cloud-provider KMS) or Pattern B (self-hosted Vault) until the team has bandwidth to own a real KMS.

### Pattern C-adjacent — Cloud Session Token Brokering

Distinct from Pattern C (which encrypts data): a service that mints short-lived cloud-provider credentials (STS, OIDC, IAM session tokens) on behalf of pods and caches them. Common when the platform calls multiple cloud accounts or multiple roles per account.

- **Caller authentication and authorization MUST gate every mint**: the broker is a privilege-escalation surface — it holds credentials more powerful than any individual pod and hands them out. Before minting, the broker verifies the caller's workload identity (mTLS service identity, k8s SA TokenReview, SPIFFE/SPIRE id, or platform-issued JWT) AND checks an explicit caller × target-account × target-role × scope allowlist. "Any pod in the cluster can ask for any role" is a finding; the allowlist is data-driven and reviewed.
- **Cache key covers the full effective credential scope**, not just account+role: the cache key is `(caller_identity, account_id, role_arn, session_policy_hash, source_identity, external_id, session_tags_hash, transitive_tag_keys_hash, region, scope_hint, requested_duration)`. Every input that the cloud provider treats as credential-shaping — session policy, source identity, ABAC session tags (including which are marked transitive), external id, region — is included; omitting session-tag fields lets one caller receive credentials minted with another caller's ABAC tags, which collapses tenant / resource boundaries. A `(account_id, role_arn)`-only key leaks one caller's restricted session into another's broader request.
- **Refresh-ahead-of-expiry**: short-lived credentials (typically 15-60 minutes) refresh at `expiry - safety_buffer`. The buffer is typically 1 minute, but clock skew between the broker and the cloud provider's STS endpoint can make the broker's view of "expiry" wrong. Validate clock skew (NTP-derived or via the cloud provider's response timestamp header) and treat any skew > buffer as cause to refresh immediately.
- **Refresh is single-flight per cache key**: under load, all in-flight callers wait for one refresh, not N parallel refreshes against STS.
- **Failure to refresh fails closed, not silently serves stale**: STS / AssumeRole errors do not produce empty tokens; cached-and-now-expired tokens do not silently extend.
- **Audit token issuance**: every mint records caller (verified workload identity, not claimed), target account / role, requested scope / session policy, expiry granted, request id. Token leakage investigation requires the audit log.

### Pattern D — Sealed / external secret operators

For GitOps shops: `Sealed Secrets` (Bitnami) or `External Secrets Operator` reads from a secret store and creates k8s `Secret` objects.

Pros: declarative; integrates with Argo CD.
Cons: still need a real secret store behind it.

## Injection paths

Pod gets the secret via:

1. **Init container**: pulls from secret store, writes to a shared volume, app reads at start. Simple, works for any language.
2. **Sidecar**: continuously syncs secrets to the volume; supports rotation without restart.
3. **CSI driver**: k8s native; mounts secrets as files.
4. **Env vars from k8s Secret**: simplest but rotates only on pod restart and leaks via `/proc/<pid>/environ`.
5. **SDK fetches at runtime**: most flexible; requires the secret store SDK in the app.

Choose by rotation needs and language ecosystem.

## Rotation

Every secret has an expiry. Rotation pipeline:

```
1. Generate new secret at source (DB user new password; new API key).
2. Push new secret to secret store as a new version, marked "pending".
3. Trigger app reload (or wait for next rotation poll).
4. Confirm apps read new secret (metric: secret_version_in_use).
5. Mark new version "active"; mark old version "deprecated".
6. After grace window, revoke old secret at source.
```

Grace window: 24h - 7d depending on app traffic patterns. Long enough that all replicas pick up the new value.

### Webhook / HMAC verifier rotation

A subset of "secrets" — the shared secrets used to verify inbound webhook / callback signatures (chat-platform approval cards, OAuth provider callbacks, partner webhooks, internal control-plane callbacks) — has rotation requirements that the generic secret-rotation pipeline above does not fully cover. Apply these rules in addition to the generic pipeline:

- **Dual-verifier acceptance during cutover**: during the rotation grace window the verifier accepts both the active and the deprecated secret. Closing the grace window before all senders cut over is the most common rotation outage; the grace must be longer than the longest sender propagation path the platform commits to.
- **Key id in the signed payload (when the protocol allows)**: senders include a `kid` / `key_version` header so the verifier picks the right secret directly rather than try-all. When the protocol does not allow a key id (some chat-platform card callbacks), the verifier tries active first, then deprecated; never beyond that.
- **Constant-time comparison**: signature comparison is constant-time (`hmac.Equal`, `crypto.subtle.timingSafeEqual`). String `==` on the signature is a finding.
- **Provider cutover order**: rotate the verifier (accept new + old) BEFORE the sender starts emitting under the new secret. Senders cutting before verifiers leaves a window where valid inbound callbacks fail signature, and operators reach for the override.
- **Hard reject after revocation**: a secret moved to "revoked" (not just "deprecated") must fail verification immediately and loudly, including for already-signed-and-delayed payloads. Revoked-but-still-accepted is the bypass an attacker uses after leak.
- **Audit per verification outcome** for the rotation window: which secret version succeeded, sender id, request id. Sustained verification against the deprecated secret after the planned cutover date is the early warning that a sender did not rotate.

### Ephemeral bootstrap / pairing credentials on observable channels

Some credentials must transit a channel you cannot redact or keep private: a value printed to a system/console log, a CI build log, a device-flow user code, a QR pairing code, a one-time provisioning URL, or any handoff where the producer and consumer are reached through an observable medium. For these, "do not log the secret" and the reactive "rotate immediately if discovered" below are not enough — the exposure is *by design*, so leak-driven rotation never fires. Make the value worthless to whoever captures the channel:

- **Born single-use and short-lived, invalidated on first legitimate use.** The credential carries a risk-appropriate expiry — seconds for a machine-to-machine in-process bootstrap (a token printed to a launch log and redeemed by a local daemon), minute-scale where a human must read and enter it across devices (a device-flow user code or QR pairing code, where RFC 8628-style flows leave the exact lifetime deployment-specific but bounded) — and is consumed on first successful exchange, so the copy sitting in the log/screen/history is already dead. Design the bootstrap so the long-lived authority (session token, refreshable credential) is minted *in exchange for* the ephemeral one over a private channel, never logged.
- **Exchange it for a private-channel credential immediately; never reuse the bootstrap value as the working credential.** The observable value's only job is to authenticate one handoff; after that the parties talk over a credential that never touched the observable channel. Rotating the bootstrap value "within seconds of boot" so anything scraping the launch log past that point sees a dead credential is the canonical shape.
- **The observable value alone must not be sufficient to mint authority — redemption is not "first claimant wins".** A captured value can be redeemed by an attacker *before* the legitimate consumer (RFC 8628 §5.5 calls out this hijack: complete the flow faster than the initiating party); single-use + rate-limit + audit then only record the breach *after* a usable credential was issued to the wrong party. So redemption must require a second proof the attacker cannot obtain from the observable channel: a pre-established device/public key, mTLS/SPIFFE identity, local-IPC peer credential, or a session id that never appears on the observable channel — verified *before* minting, with an atomic single-use compare-and-swap so concurrent redemptions cannot both win. Foreign or unproven redemption must fail closed (mint nothing) and, for high-risk flows, revoke the value and alert. When no prior private proof exists (a QR or device-flow code a human scans), require user-visible device/possession confirmation; the observable code by itself never issues the working credential. Scope the value to a single generation so it cannot be replayed against a later incarnation (same single-use + generation-binding discipline as `llm-inference-integration`'s approval tokens; this is the secret-design counterpart).
- **Rate-limit and audit the redemption endpoint.** The endpoint that exchanges the ephemeral value is a brute-force and replay target: bound redemption attempts per identity/window, and audit each redemption (who, when, outcome) so an anomalous replay after the legitimate exchange is visible.
- **Treat "the channel is internal/loopback/short-lived" as defense-in-depth, not the boundary.** A log that is local today is shipped to a log aggregator tomorrow; a loopback-only console is captured by a crash report or a screen recording. The ephemerality of the value, not the assumed privacy of the channel, is what makes the exposure safe.

## What MUST NOT be in git

- Committed `.env` files.
- Plaintext passwords in any YAML.
- API keys in test fixtures (use fake values).
- Private keys in any form.
- OAuth client secrets.
- Cookie / JWT signing keys.

Run a secrets-in-git scanner (`gitleaks`, `trufflehog`, GitHub secret scanning, equivalent) on every PR. Reject merge if hit.

A leaked secret in git history persists until force-push and even then is recoverable. Rotate immediately if discovered.

## Verification

- A new service can pull DB password from secret store on cold start; no password in image.
- Flipping a feature flag in config center takes effect within seconds (subscription) or single refresh cycle (poll).
- Static config changes require a code review + deploy; bypass attempts are audited.
- Rotation pipeline runs without service outage; metric shows version transition.
- Secrets scanner runs on every PR; new credential commit is rejected.
