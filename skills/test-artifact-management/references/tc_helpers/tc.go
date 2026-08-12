// Package tc records TC IDs from Go tests to a JSONL sidecar.
//
// Usage:
//
//	import "yourrepo/testkit/tc"
//
//	func TestLoginSuccess(t *testing.T) {
//	    tc.Mark(t, "TC-SY-001")
//	    // ... test body
//	}
//
//	func TestBulkImportPartialFailure(t *testing.T) {
//	    tc.Mark(t, "TC-SY-001", "TC-SY-002")
//	    // ... test body
//	}
//
// Each Mark call appends one JSONL line to test/results/tc-map.jsonl
// (configurable via TC_SIDECAR env). gen_report.py reads the sidecar and
// joins by t.Name(). The Makefile test target should truncate the sidecar
// before running tests so deleted tests don't leave stale entries.
package tc

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
)

var mu sync.Mutex

// testKeyFromPC returns "<package-path>::<t.Name()>" so two TestLogin functions
// in different packages don't collide. The PC argument MUST be captured at the
// Mark callsite (runtime.Caller(1) inside Mark) — passing it explicitly avoids
// brittleness around helper-function inlining: if testKey/Mark were inlined,
// a fixed runtime.Caller(2) inside testKey would skip past the user's frame.
//
// Subtest closures register as "<pkg>.<TestName>.func1[.<n>...]" via
// runtime.FuncForPC. We strip every trailing segment until we land on a test
// entry function (prefix Test/Benchmark/Example/Fuzz), then strip ONCE more
// to drop the test name and reveal the package path.
//
// If no Test* entry is ever found in the chain, the PC almost certainly
// pointed at a wrapper helper (wrong extraSkip in MarkAt). In that case we
// log loudly and — under TC_SIDECAR_STRICT — fail the test, because a
// silently-wrong key turns a passing test into untracked and the bug only
// surfaces during report review.
func testKeyFromPC(t *testing.T, pc uintptr) string {
	t.Helper()
	name := t.Name()
	fn := runtime.FuncForPC(pc)
	if fn == nil {
		warnBadFrame(t, "runtime.FuncForPC returned nil — wrong extraSkip in MarkAt?")
		return name
	}
	full := fn.Name()
	original := full
	foundEntry := false
	// Strip trailing segments until the last segment is a test entry.
	for {
		i := strings.LastIndex(full, ".")
		if i < 0 {
			break
		}
		last := full[i+1:]
		if isTestEntry(last) {
			full = full[:i] // drop the test name → leave package path
			foundEntry = true
			break
		}
		full = full[:i] // drop closure / numeric / func suffix and keep going
	}
	if !foundEntry {
		warnBadFrame(t, "no Test*/Benchmark*/Example*/Fuzz* entry found in PC chain "+
			"(captured "+original+"). Wrong extraSkip in MarkAt? "+
			"If using a project wrapper, count how many helpers sit between the "+
			"test and MarkAt; that's the extraSkip value.")
		return name
	}
	if full == "" {
		return name
	}
	return full + "::" + name
}

// warnBadFrame surfaces a wrong-frame attribution. Under TC_SIDECAR_STRICT
// this becomes a test failure so CI catches the bug instead of silently
// recording a sidecar key that won't join JUnit.
func warnBadFrame(t *testing.T, msg string) {
	t.Helper()
	if strictMode() {
		t.Fatalf("tc.MarkAt frame attribution failed: %s (TC_SIDECAR_STRICT=1)", msg)
	} else {
		t.Logf("⚠ tc.MarkAt frame attribution failed: %s", msg)
	}
}

func isTestEntry(s string) bool {
	return strings.HasPrefix(s, "Test") ||
		strings.HasPrefix(s, "Benchmark") ||
		strings.HasPrefix(s, "Example") ||
		strings.HasPrefix(s, "Fuzz")
}

// Mark links the currently-running test to one or more TC IDs.
// Safe under t.Parallel(); does not fail the test on I/O error (logged via t.Logf).
//
// MUST be called before any t.Skip / t.Skipf / setup that may call t.Fatal —
// otherwise the sidecar entry is not written for that test.
//
// DO NOT wrap Mark in a project-local helper without using MarkAt: the
// package-path detection reads the caller's PC, which would point to your
// wrapper's package instead of the test's package, producing wrong sidecar
// keys that don't join JUnit's classname.
func Mark(t *testing.T, ids ...string) {
	t.Helper()
	if len(ids) == 0 {
		return
	}
	pc, _, _, _ := runtime.Caller(1) // caller of Mark = user test
	markPC(t, pc, ids...)
}

// MarkAt lets a project-local wrapper register TC IDs while still attributing
// them to the USER's test (not the wrapper's package). `extraSkip` is the
// number of caller frames between the user's test code and the call to MarkAt.
//
// Examples:
//
//	// Single wrapper: TestX → Smoke → MarkAt; extraSkip = 1 (skip Smoke).
//	func Smoke(t *testing.T, ids ...string) {
//	    t.Helper()
//	    tc.MarkAt(t, 1, ids...)
//	}
//
//	// Two-level wrapper: TestX → Smoke → InnerMark → MarkAt; extraSkip = 2.
func MarkAt(t *testing.T, extraSkip int, ids ...string) {
	t.Helper()
	if len(ids) == 0 {
		return
	}
	// depth 0 = MarkAt; depth 1 = caller of MarkAt (the wrapper);
	// depth 1+extraSkip = the user's test (one extra hop per wrapper frame).
	pc, _, _, _ := runtime.Caller(1 + extraSkip)
	markPC(t, pc, ids...)
}

// markPC is the shared implementation. PC must already point at the user's
// test frame (so the package-path strip resolves to the test's package).
func markPC(t *testing.T, pc uintptr, ids ...string) {
	t.Helper()
	path := os.Getenv("TC_SIDECAR")
	if path == "" {
		path = "test/results/tc-map.jsonl"
	}
	mu.Lock()
	defer mu.Unlock()
	strict := strictMode()
	fail := func(err error, what string) {
		// Mark the closure as a helper too, so t.Fatalf credits the test
		// callsite (the line that invoked tc.Mark), not tc.go.
		t.Helper()
		if strict {
			t.Fatalf("tc.Mark: %s: %v (TC_SIDECAR_STRICT=1)", what, err)
		}
		t.Logf("tc.Mark: %s: %v", what, err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err, "mkdir "+filepath.Dir(path))
		return
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		fail(err, "open "+path)
		return
	}
	defer f.Close()
	entry := map[string]any{"test": testKeyFromPC(t, pc), "tc_ids": ids}
	line, err := json.Marshal(entry)
	if err != nil {
		fail(err, "marshal")
		return
	}
	if _, err := f.Write(append(line, '\n')); err != nil {
		fail(err, "write "+path)
	}
}

// strictMode returns true when TC_SIDECAR_STRICT=1|true|yes — sidecar write
// failures become test failures instead of best-effort log lines.
func strictMode() bool {
	v := strings.ToLower(os.Getenv("TC_SIDECAR_STRICT"))
	return v == "1" || v == "true" || v == "yes"
}
