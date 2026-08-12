/**
 * TC ID helper for Vitest and Jest.
 *
 * Recording happens at REGISTRATION time (not when the test body runs), so
 * `test.skip` / `test.skipIf` / `test.todo` / fixture-failure cases still
 * register the TC mapping.
 *
 * ## Setup
 *
 *     // <project>/test/<your>.test.ts:
 *     import { test, describe } from 'vitest'              // or '@jest/globals'
 *     import { createTcSuite, tc } from './tc'
 *     const { tcTest, tcDescribe } = createTcSuite(test, describe)
 *
 *     tcDescribe('Auth', () => {
 *       tcTest('TC-SY-001', 'login success', () => { expect(...).toBe(...) })
 *       tcTest(['TC-SY-001', 'TC-SY-002'], 'bulk partial', () => { ... })
 *       tcTest.skip('TC-SY-003', 'wip', () => { ... })
 *       tcTest.skipIf(!process.env.LIVE)('TC-SY-004', 'live only', () => { ... })
 *       tcTest.only('TC-SY-005', 'focused', () => { ... })
 *       tcTest.todo('TC-SY-006', 'pending')
 *       tcTest.concurrent('TC-SY-007', 'parallel', () => { ... })
 *       tcTest.each([1,2,3])('TC-SY-008', 'row %s', (n) => { ... })
 *       tcTest('TC-SY-009', 'with timeout', () => { ... }, 5000)
 *       tcTest('TC-SY-010', 'with options', { timeout: 3000 }, () => { ... })
 *     })
 *
 *     // top-level (no surrounding describe)
 *     tcTest('TC-SY-011', 'standalone', () => { ... })
 *
 * Use `tcDescribe` (not plain `describe`) so the helper can capture the full
 * nested path "Auth > login success" — this is what Vitest emits in JUnit
 * `<testcase name>`, so the sidecar key matches exactly.
 *
 * For TC IDs computed at runtime (rare — derived from test input), the
 * in-body `tc(...)` form is exported below; it records only when the body
 * runs, so skipped tests are not covered via that path.
 *
 * Set `TC_SIDECAR_STRICT=1` in CI so sidecar write failures fail the test
 * (otherwise a permission/disk error silently leaves Bitable stale).
 *
 * Each registration appends one JSONL line to `test/results/tc-map.jsonl`
 * (override via `TC_SIDECAR`). The Makefile `test` target truncates the
 * sidecar before each run.
 */

import { appendFileSync, mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

type TestFn = (...args: any[]) => unknown | Promise<unknown>

// Shape of Vitest/Jest's `test` function. Methods are optional so Jest
// (which lacks .skipIf / .runIf / .fails) still type-checks against the
// factory; runtime fallbacks handle missing methods.
interface RunnerTest {
  (...args: any[]): unknown
  skip: (...args: any[]) => unknown
  only: (...args: any[]) => unknown
  todo?: (...args: any[]) => unknown
  concurrent?: (...args: any[]) => unknown
  fails?: (...args: any[]) => unknown
  skipIf?: (cond: boolean) => (...args: any[]) => unknown
  runIf?: (cond: boolean) => (...args: any[]) => unknown
  each?: (table: any) => (...args: any[]) => unknown
}

type RunnerDescribe = (name: string, cb: () => void) => unknown

function sidecarPath(): string {
  return process.env.TC_SIDECAR ?? 'test/results/tc-map.jsonl'
}

function _record(testKey: string, ids: string[]): void {
  if (!testKey || ids.length === 0) return
  const path = sidecarPath()
  const strict = ['1', 'true', 'yes'].includes(
    (process.env.TC_SIDECAR_STRICT ?? '').toLowerCase(),
  )
  try {
    mkdirSync(dirname(path), { recursive: true })
    appendFileSync(path, JSON.stringify({ test: testKey, tc_ids: ids }) + '\n', 'utf-8')
  } catch (err) {
    if (strict) throw err
    // best-effort fallback (default)
  }
}

/** Extract the test file path from a stack trace, skipping our own frames. */
function callerTestFile(): string {
  const orig = Error.stackTraceLimit
  Error.stackTraceLimit = 25
  const stack = new Error().stack || ''
  Error.stackTraceLimit = orig
  const lines = stack.split('\n')
  const cwd = process.cwd() + (process.platform === 'win32' ? '\\' : '/')
  for (const raw of lines) {
    const line = raw.trim()
    // Skip own frames
    if (line.includes('/tc.ts:') || line.includes('/tc.js:') ||
        line.includes('createTcSuite') || line.includes('callerTestFile') ||
        line.includes('_record')) continue
    // Skip node internal frames
    if (line.includes('node:internal') || line.includes('(node:')) continue
    // Match "at fn (FILE:line:col)" or "at FILE:line:col"
    const m = line.match(/[(\s](?:file:\/\/)?([^():\s]+\.(?:test|spec)\.[a-z]+):\d+:\d+\)?$/)
    if (m) {
      const f = m[1]
      return f.startsWith(cwd) ? f.slice(cwd.length) : f
    }
  }
  return ''
}

function normaliseIds(ids: string | string[]): string[] {
  return Array.isArray(ids) ? ids.filter(Boolean) : ids ? [ids] : []
}

/** Expand a Vitest/Jest .each name template per row.
 *  Supports both printf-style %s/%d/%i/%f/%j/%o/%# and object-key $name.
 *  Mirrors what Vitest/Jest emit in JUnit `<testcase name>` so sidecar keys join.
 */
function expandEachName(template: string, row: any, index: number): string {
  let out = template
  // $key substitution for object rows (mirror Vitest/Jest: missing key → "undefined")
  if (row !== null && typeof row === 'object' && !Array.isArray(row)) {
    out = out.replace(/\$(\w+)/g, (_, k) => {
      const v = (row as any)[k]
      return v === undefined ? 'undefined' : String(v)
    })
  }
  // printf-style; arguments come from row (array → positional; scalar → single arg)
  const args = Array.isArray(row) ? row : [row]
  let i = 0
  out = out.replace(/%[sdifjo#%]/g, (m) => {
    if (m === '%%') return '%'
    if (m === '%#') return String(index)
    const v = args[i++]
    if (m === '%j' || m === '%o') {
      try { return JSON.stringify(v) } catch { return String(v) }
    }
    return v === undefined ? '' : String(v)
  })
  return out
}

/**
 * Build a tcTest + tcDescribe pair bound to the user's runner globals.
 * Use this in test files so describes can be tracked at collection time.
 */
export function createTcSuite(testFn: RunnerTest, describeFn?: RunnerDescribe) {
  // currentPath is the path Vitest is currently collecting inside. Vitest
  // describes are lazy + reordered: outer cb may finish before the inner cb
  // is scheduled. We snapshot the parent path at describe-CALL time (closure
  // capture), then prepend it when the inner cb runs.
  let currentPath = ''

  function path(leaf: string): string {
    const inner = currentPath ? currentPath + ' > ' + leaf : leaf
    const file = callerTestFile()
    return file ? file + '::' + inner : inner
  }

  function tcDescribe(name: string, cb: () => void): unknown {
    // Snapshot at describe-call: this is "what was inside currentPath when
    // we were CALLED" (i.e. our parent describe's path, if any).
    const parent = currentPath
    const wrapped = () => {
      const before = currentPath
      currentPath = parent ? parent + ' > ' + name : name
      try { cb() } finally { currentPath = before }
    }
    if (!describeFn) {
      wrapped()
      return
    }
    return describeFn(name, wrapped)
  }

  // Variadic forwarder: tcTest(ids, ...args) → testFn(...args). The first
  // element of `args` MUST be the test name (string); everything after passes
  // through unchanged, so all runner overloads work:
  //   test(name, fn)
  //   test(name, fn, timeout)            // Vitest/Jest both support
  //   test(name, options, fn)             // Vitest: { timeout, retry, concurrent, ... }
  //   test.concurrent(name, fn)           // → tcTest.concurrent(ids, name, fn)
  //   test.each(table)(name, fn)          // → tcTest.each(table)(ids, name, fn)
  function recordAndForward(method: any, ids: string | string[], args: any[]): unknown {
    if (args.length > 0 && typeof args[0] === 'string') {
      _record(path(args[0]), normaliseIds(ids))
    }
    return method(...args)
  }

  function wrap(ids: string | string[], ...args: any[]): unknown {
    return recordAndForward(testFn, ids, args)
  }
  wrap.skip = function(ids: string | string[], ...args: any[]): unknown {
    return recordAndForward(testFn.skip, ids, args)
  }
  wrap.only = function(ids: string | string[], ...args: any[]): unknown {
    return recordAndForward(testFn.only, ids, args)
  }
  wrap.todo = function(ids: string | string[], ...args: any[]): unknown {
    return recordAndForward(testFn.todo, ids, args)
  }
  wrap.concurrent = function(ids: string | string[], ...args: any[]): unknown {
    // Jest doesn't always expose .concurrent at top-level; fall back to test.
    return recordAndForward(testFn.concurrent ?? testFn, ids, args)
  }
  wrap.fails = function(ids: string | string[], ...args: any[]): unknown {
    // Vitest's expect-failure marker; on Jest, no-op fallback to test.
    return recordAndForward(testFn.fails ?? testFn, ids, args)
  }
  /** tcTest.skipIf(cond)(ids, ...args). Vitest: testFn.skipIf(cond). Jest fallback: branch on cond. */
  wrap.skipIf = function(cond: boolean) {
    return function(ids: string | string[], ...args: any[]): unknown {
      if (typeof testFn.skipIf === 'function') return recordAndForward(testFn.skipIf(cond), ids, args)
      return recordAndForward(cond ? testFn.skip : testFn, ids, args)
    }
  }
  /** tcTest.runIf(cond)(ids, ...args). Vitest equivalent of `skipIf(!cond)`. */
  wrap.runIf = function(cond: boolean) {
    return function(ids: string | string[], ...args: any[]): unknown {
      if (typeof testFn.runIf === 'function') return recordAndForward(testFn.runIf(cond), ids, args)
      return recordAndForward(cond ? testFn : testFn.skip, ids, args)
    }
  }
  /**
   * Parameterized: tcTest.each(table)(ids, nameTemplate, fn).
   *
   * Records ONE sidecar entry per row using the same name-expansion rules
   * Vitest/Jest apply (`%s` `%d` `%i` `%f` `%j` `%o` `%#`, and `$key` for
   * object rows), so every row's JUnit `<testcase name>` matches the sidecar.
   *
   * All rows share the same TC IDs by design; for row-specific TC mapping,
   * register each row individually via plain `tcTest(ids, name, fn)`.
   */
  wrap.each = function(table: any) {
    return function(ids: string | string[], nameTemplate: string, fn: TestFn): unknown {
      const ids_ = normaliseIds(ids)
      if (Array.isArray(table)) {
        for (let i = 0; i < table.length; i++) {
          _record(path(expandEachName(nameTemplate, table[i], i)), ids_)
        }
      }
      if (!testFn.each) throw new Error('tcTest.each: runner does not expose test.each')
      return testFn.each(table)(nameTemplate, fn)
    }
  }

  return { tcTest: wrap, tcDescribe }
}

/** Back-compat: just the tcTest factory (no describe tracking; leaf name only). */
export function createTcTest(testFn: RunnerTest) {
  return createTcSuite(testFn, undefined).tcTest
}

/** In-body form for runtime-computed TC IDs. Skipped tests are not registered
 *  via this path — use the wrapper for those. */
function currentTestNameRuntime(): string | null {
  const w: any = (globalThis as any).__vitest_worker__
  if (w?.current) {
    let task: any = w.current
    const parts: string[] = []
    while (task && task.name) {
      parts.unshift(task.name)
      task = task.suite
    }
    if (parts.length) return parts.join(' > ')
  }
  try {
    const state = (globalThis as any).expect?.getState?.()
    const n = state?.currentTestName
    if (typeof n === 'string' && n.length > 0) return n
  } catch {}
  return null
}

export function tc(...ids: string[]): void {
  if (ids.length === 0) return
  const name = currentTestNameRuntime()
  if (!name) return
  _record(name, ids)
}
