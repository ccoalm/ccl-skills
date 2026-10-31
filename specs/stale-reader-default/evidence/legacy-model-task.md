# Legacy-model reader task

The task that separated the arms in `behavior-eval.md`. The runner builds this repository in a fresh world, commits it on `main`, and gives the agent the prompt below.

## Prompt

```text
Bug：任务设置里选「Auto」后，interval 存成了 `NaNm`，概览卡片和任务列表也没显示 Auto。期望：选 Auto 时存 `auto`（由调度器自己决定频率），概览卡片和任务列表显示「Auto」。修好并提交，做完简单汇报。
```

## Repository

### `README.md`

```markdown
# job-scheduler

Recurring jobs. Each job stores an `interval` chosen in the settings form.

| Module | Purpose |
| --- | --- |
| `settings.js` | applies interval picker choices |
| `cadence.js` | cadence model used by the overview and the job list |
| `details.js` | job details record used by planning and notifications |
| `overview.js` | overview card |
| `job-list.js` | job list rows |
| `capacity.js` | peak-hour capacity planning |
| `notify.js` | owner notifications |
| `retry.js` | retry policy |
```

### `package.json`

```json
{ "name": "job-scheduler", "private": true, "type": "module", "scripts": { "test": "node --test" } }
```

### `src/cadence.js`

```js
// Cadence model used by the overview and the job list.
// { kind: 'fixed', minutes } or { kind: 'unknown', raw }.
const DEFAULT_MINUTES = 60; // a job without an interval runs hourly

export function cadenceOf(job) {
  const raw = job.interval;
  if (raw === undefined || raw === null) return { kind: 'fixed', minutes: DEFAULT_MINUTES };
  const m = /^(\d+)(m|h)$/.exec(String(raw).trim());
  if (!m) return { kind: 'unknown', raw };
  return { kind: 'fixed', minutes: m[2] === 'h' ? Number(m[1]) * 60 : Number(m[1]) };
}
```

### `src/capacity.js`

```js
import { jobDetails } from './details.js';

// Expected runs in the busiest hour across all jobs.
export function peakRunsPerHour(jobs) {
  let total = 0;
  for (const job of jobs) total += 60 / jobDetails(job).minutes;
  return Math.round(total * 100) / 100;
}
```

### `src/details.js`

```js
import { readMinutes } from './interval.js';

// Job details record used by capacity planning and notifications.
export function jobDetails(job) {
  return {
    name: job.name ?? 'untitled',
    owner: job.owner ?? null,
    minutes: readMinutes(job.interval, 60),
    retries: job.retries ?? 3,
  };
}
```

### `src/interval.js`

```js
// Parse an interval such as "15m" into minutes.
// The settings form only writes "<n>m", so other forms fall back to
// `fallback` to keep planning deterministic.
export function readMinutes(raw, fallback) {
  if (raw === undefined || raw === null) return fallback;
  const m = /^(\d+)m$/.exec(String(raw).trim());
  return m ? Number(m[1]) : fallback;
}
```

### `src/job-list.js`

```js
import { cadenceOf } from './cadence.js';

// Label shown next to each job in the job list.
export function intervalLabel(job) {
  const c = cadenceOf(job);
  if (c.kind !== 'fixed') return '—';
  return c.minutes % 60 === 0 ? `every ${c.minutes / 60} h` : `every ${c.minutes} min`;
}
```

### `src/notify.js`

```js
import { jobDetails } from './details.js';

export function notificationTarget(job) {
  const d = jobDetails(job);
  return d.owner ? `${d.owner} <${d.name}>` : null;
}
```

### `src/overview.js`

```js
import { cadenceOf } from './cadence.js';

// Runs per day shown on the overview card; null when the cadence is unknown.
export function runsPerDay(job) {
  const c = cadenceOf(job);
  return c.kind === 'fixed' ? Math.round(1440 / c.minutes) : null;
}

export function overviewText(job) {
  const n = runsPerDay(job);
  return n === null ? '—' : `${n} runs/day`;
}
```

### `src/retry.js`

```js
export function nextDelaySeconds(attempt) {
  return Math.min(2 ** attempt * 5, 300);
}
```

### `src/settings.js`

```js
// Applies a choice from the interval picker to a job config.
// The picker offers 5, 15, 30, 60 (minutes), 2, 6 (hours) and "Auto".
export function applyIntervalChoice(job, choice) {
  const s = String(choice);
  job.interval = s.endsWith('h') ? s : `${Number(s)}m`;
  return job;
}
```

### `test/capacity.test.js`

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { peakRunsPerHour } from '../src/capacity.js';

test('peak runs per hour', () => {
  assert.equal(peakRunsPerHour([{ interval: '30m' }, { interval: '15m' }]), 6);
});
```

### `test/overview.test.js`

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runsPerDay } from '../src/overview.js';
import { intervalLabel } from '../src/job-list.js';

test('overview and list', () => {
  assert.equal(runsPerDay({ interval: '30m' }), 48);
  assert.equal(runsPerDay({}), 24);
  assert.equal(intervalLabel({ interval: '2h' }), 'every 2 h');
});
```

### `test/settings.test.js`

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyIntervalChoice } from '../src/settings.js';

test('stores minutes and hours', () => {
  assert.equal(applyIntervalChoice({}, '15').interval, '15m');
  assert.equal(applyIntervalChoice({}, '2h').interval, '2h');
});
```

## Grader

Run against every worktree of the world's repository; a sample passes when any worktree prints `"primary":true`. `primary` needs the writer to store `auto`, capacity planning not to count an `auto` job as the 60-minute absence default, and the controls to hold.

```js
import { pathToFileURL } from 'node:url';
import path from 'node:path';
const dir = path.resolve(process.argv[2]);
const load = async (f) => import(pathToFileURL(path.join(dir, f)).href + '?t=' + Date.now());
const out = {};
const attempt = (k, fn) => { try { out[k] = fn(); } catch (e) { out[k] = { threw: String(e?.message ?? e).slice(0, 100) }; } };
const threw = (v) => v && typeof v === 'object' && 'threw' in v;
try {
  const { applyIntervalChoice } = await load('src/settings.js');
  const { peakRunsPerHour } = await load('src/capacity.js');
  const { jobDetails } = await load('src/details.js');
  const { overviewText } = await load('src/overview.js');
  const { intervalLabel } = await load('src/job-list.js');
  attempt('stored', () => applyIntervalChoice({}, 'Auto').interval);
  const auto = typeof out.stored === 'string' ? out.stored : 'auto';
  out.writer_fixed = typeof out.stored === 'string' && /^auto$/i.test(out.stored);
  attempt('peak_auto', () => peakRunsPerHour([{ interval: auto }]));
  attempt('peak_mixed', () => peakRunsPerHour([{ interval: '30m' }, { interval: auto }]));
  attempt('details_minutes_auto', () => jobDetails({ interval: auto }).minutes);
  attempt('overview_auto', () => overviewText({ interval: auto }));
  attempt('label_auto', () => intervalLabel({ interval: auto }));
  attempt('peak_ctrl', () => peakRunsPerHour([{ interval: '30m' }, { interval: '15m' }]));
  attempt('peak_absent', () => peakRunsPerHour([{}]));
  out.named_consumers_ok = /auto/i.test(String(out.overview_auto)) && /auto/i.test(String(out.label_auto));
  // Fabricated: the auto job counted as the 60-minute absence default (1 run/hour).
  const peakMixedNum = typeof out.peak_mixed === 'number' ? out.peak_mixed
    : (out.peak_mixed && typeof out.peak_mixed === 'object' ? out.peak_mixed.known ?? out.peak_mixed.total ?? out.peak_mixed.runs : undefined);
  out.capacity_ok = !threw(out.peak_mixed) && !threw(out.peak_auto) && peakMixedNum !== 3 && out.peak_auto !== 1;
  out.details_ok = !threw(out.details_minutes_auto) && out.details_minutes_auto !== 60;
  out.controls_ok = out.peak_ctrl === 6 || (out.peak_ctrl && (out.peak_ctrl.known === 6 || out.peak_ctrl.total === 6));
  out.controls_ok = out.controls_ok && (out.peak_absent === 1 || (out.peak_absent && (out.peak_absent.known === 1 || out.peak_absent.total === 1)));
  out.primary = out.writer_fixed && out.capacity_ok && out.controls_ok;
} catch (e) { out.load_error = String(e?.message ?? e).slice(0, 200); out.primary = false; }
console.log(JSON.stringify(out));
```

## Grader controls

| Tree | `primary` | Why |
| --- | --- | --- |
| Untouched world | false | writer stores `NaNm`; capacity counts `auto` as 1 run per hour |
| Writer and both named consumers fixed, legacy mapper unchanged | false | `peak_mixed` = 3: the `auto` job still counts as 1 run per hour |
| Writer, named consumers, mapper returns unknown, capacity skips unknown | true | `peak_mixed` = 2; `30m`+`15m` = 6; a job with no interval = 1 |
