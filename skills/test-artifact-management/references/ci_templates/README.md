# CI Integration Templates

Templates for running tests, syncing Bitable, publishing the Feishu report,
and posting a PR/MR comment with the regression delta.

| File | Use when |
|---|---|
| `github-actions.yml` | GitHub repo |
| `gitlab-ci.yml` | GitLab repo |
| `jenkins.Jenkinsfile` | Jenkins pipeline |

## What each does

1. **Stack setup** — keep or add the runtime setup required by the unit
2. **lark-cli auth** — initializes the Feishu bot identity from CI secrets
3. **Restore `last-run.json`** — cache key per branch+unit so vs-last-run diff
   survives across runs
4. **`make report-run`** — runs tests, writes JUnit + sidecar, syncs Bitable,
   publishes / updates the Feishu report doc (exits non-zero on failure)
5. **PR/MR comment — runs even when tests fail** — pipes `--pr-summary --fail-on=never`
   to the platform comment API; shows overview line +
   🔴 new failures + 🟢 fixed. Uses `if: always()` (GitHub) / `after_script`
   (GitLab) / `post { always {} }` (Jenkins) so red CI still gets the summary
   posted when developers need it most.
6. **Artifact upload** — `test/results/` for debugging (7-day retention)
7. **`TC_SIDECAR_STRICT=1`** is exported in every template — sidecar write
   failures fail the test (instead of silently leaving Bitable stale).

## Adapting to your project

1. Pick the template matching your CI
2. Replace every `<unit>` placeholder with your deployable-unit directory
   (e.g. `web`, `app`, `services/auth`)
3. Add CI secrets:
   - `LARK_BOT_APP_ID`
   - `LARK_BOT_APP_SECRET`
4. Keep or add the stack setup that matches your unit; remove unrelated setup
5. Adjust `path:` filters so the workflow only runs when this unit's files change

These are CI-provider scaffolds, not per-stack test adapters. They do not create
the project's test command, JUnit reporter, or TC sidecar wiring. Before use,
make `make report-run` produce the configured JUnit XML and `tc-map.jsonl` for
the target stack. The bundled TC helpers cover Python, Go, TypeScript, and
Dart/Flutter; other stacks need an equivalent sidecar integration. Vite/vitest
also needs its repository's actual test command and JUnit flags rather than the
Node placeholder in a template.

## Multi-unit monorepo

Each unit gets **one workflow file** (`test-web.yml`, `test-app.yml`,
`test-svc-auth.yml`, ...). Do **not** unify into one mega-workflow — the whole
point of deployable-unit scope is independent failure / report / cadence.

GitHub example structure:

```
.github/workflows/
├── test-web.yml          # path: web/**
├── test-app.yml          # path: app/**
└── test-svc-auth.yml     # path: services/auth/**
```

A PR that only touches `web/` triggers only `test-web.yml`; its PR comment is
the web unit's report. Other units stay quiet.

## `--pr-summary` output format

The `--pr-summary` flag emits short Markdown suitable for a PR/MR comment:

```
### 🧪 自动化测试结果

通过 **45** / 总 **48** · ❌ 失败 **2** · ⚠ 阻塞 **1** · 📊 覆盖率 82.3% (412/501)

**🔴 本次新增失败 / 阻塞（2）**：

- `TC-SY-005`
- `TC-AU-003`
```

Always under ~30 lines (long ID lists truncated to 20/10 with "另外 N 个").
Safe to paste verbatim into a PR comment.

## Last-run snapshot persistence

The `test/results/last-run.json` snapshot drives the vs-last-run diff. Without
CI caching, it would reset on every fresh runner. Cache keys include the unique
run/pipeline id so each run produces a NEW cache entry (otherwise an exact-key
hit prevents the cache from being re-saved). Fallback keys pull the most recent
prior snapshot.

- **GitHub Actions**: `actions/cache@v4` with `key: tc-last-run-<unit>-<branch>-<run_id>`
  and `restore-keys` falling back to branch then main
- **GitLab CI**: stable branch/unit cache keys with a default-branch fallback
- **Jenkins**: `copyArtifacts` from `lastSuccessful()` build of the same job

If the cache is cold (first run on a branch), the report shows no
vs-last-run section — correct behavior, not an error.

## Concurrent runs

`gen_report.py` reads Bitable, mutates in memory, writes back — there is **no
CAS / ETag**. Two simultaneous runs writing to the same unit's Bitable can
overwrite each other's status / 信息流转 entries. The templates serialize
same-(unit, branch) runs:

- **GitHub Actions**: `concurrency: { group: tc-report-<unit>-${{ github.ref }}, cancel-in-progress: false }`
- **GitLab CI**: `resource_group: "tc-report-<unit>-${ref_slug}"`

A failed run inside the serialized group still releases the lock, so retries
proceed cleanly. Cross-branch parallelism is intentionally allowed (each
branch's results are independent).

## Secret handling

Bot secrets are piped to `lark-cli config init --app-secret-stdin` via
`printf '%s' "$SECRET" | …` — they never appear in process argv, so `ps aux`
on a shared runner does not leak them. Resource IDs (base_token, table_id,
report_doc_url) live in the committed `test/.report-config.json` and are not
secrets.
