// Packaging inclusion is a DELIVERABILITY property, and it needs its own test.
//
// Round 058 built a repository-wide documentation gate and verified it the way
// this repo verifies everything: gates, mutation differential, dual-track, two
// lanes. All green. The enumerator still shipped to nobody, because it sat in
// the repo-root `scripts/` directory which the packaging roots exclude — so the
// published package carried seventeen lines DESCRIBING a gate it did not carry.
// Not one of those checks asks "can a consumer get this?".
//
// Round 059 moved it into the skill package. That move was first verified by
// hand — run the build, look at the directory, paste the result into an
// evidence file. Both review lanes rejected that independently, and correctly:
// a manual check is not repeatable, so packaging can regress tomorrow and every
// test plus every gate still passes. This file is the repeatable version.
//
// It runs in `npm test`, whose first step is `npm run build`, so `dist/` is
// already populated when these assertions execute.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const shippedSkillScripts = join(
  pkg,
  "dist/assets/marketplace/plugins/ccl-skills/skills/tighten-doc/scripts",
);

// The two files whose absence was the whole defect, plus the linter they drive.
const REQUIRED = ["doc-lint-repo.py", "doc-lint.py"];

const CLEAN = "# T\n\n| Name | Count (n) |\n| --- | --- |\n| a | 1 |\n";
// An empty table header: the linter's ERROR tier, objective, not a style call.
const BAD = "# T\n\n|  |  |\n| --- | --- |\n| a | 1 |\n| b | 2 |\n";

function python() {
  // Fail closed, do not skip. A missing interpreter means this property went
  // unverified, and "unverified" must not read the same as "verified".
  const probe = spawnSync("python3", ["--version"], { encoding: "utf8" });
  assert.equal(
    probe.status,
    0,
    "python3 is required to exercise the shipped scanner; treating it as absent " +
      "would leave packaging inclusion unverified while the suite printed a pass",
  );
  return "python3";
}

function makeConsumerRepo(docs) {
  const root = mkdtempSync(join(tmpdir(), "consumer-"));
  const git = (...args) => execFileSync("git", ["-C", root, ...args], { encoding: "utf8" });
  execFileSync("git", ["init", "-q", "-b", "main", root]);
  git("config", "user.email", "t@example.invalid");
  git("config", "user.name", "T");
  git("config", "commit.gpgsign", "false");
  for (const [rel, body] of Object.entries(docs)) {
    const full = join(root, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  }
  git("add", "-A");
  git("commit", "-qm", "seed");
  return root;
}

function runShipped(repoRoot) {
  return spawnSync(python(), [join(shippedSkillScripts, "doc-lint-repo.py"), repoRoot], {
    encoding: "utf8",
  });
}

test("the shipped package carries the scanner and its linter", () => {
  for (const name of REQUIRED) {
    assert.ok(
      existsSync(join(shippedSkillScripts, name)),
      `${name} is missing from the built package — the capability ships to nobody`,
    );
  }
});

test("the shipped scanner passes a clean consuming repository", () => {
  const root = makeConsumerRepo({ "README.md": CLEAN });
  try {
    const res = runShipped(root);
    assert.equal(res.status, 0, res.stdout + res.stderr);
    // Assert the COUNT, not the word. A pass that does not say how much it read
    // is unfalsifiable — it reads identically when the scan covered nothing.
    assert.match(res.stdout, /doc_structure_check_ok: 1 tracked doc\(s\), 0 ERROR/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("the shipped scanner blocks on an ERROR-class defect and names it", () => {
  const root = makeConsumerRepo({ "README.md": CLEAN, "docs/bad.md": BAD });
  try {
    const res = runShipped(root);
    assert.equal(res.status, 1, res.stdout + res.stderr);
    assert.match(res.stderr, /WCAG-131-TABLE/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("the shipped scanner does not swallow a consumer's own tests/ documents", () => {
  // The fixture exclusion is derived from the linter's own location. In a
  // consuming repo that location is outside the scanned tree, so nothing may be
  // excluded — including a path that happens to match this skill's own layout.
  // A hardcoded prefix would drop this document and turn the run green.
  const root = makeConsumerRepo({
    "README.md": CLEAN,
    "skills/tighten-doc/scripts/tests/theirs.md": BAD,
  });
  try {
    const res = runShipped(root);
    assert.equal(
      res.status,
      1,
      "a consuming repo's document was dropped by an exclusion that must not " +
        "apply outside this skill's own checkout:\n" + res.stdout + res.stderr,
    );
    assert.match(res.stderr, /WCAG-131-TABLE/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("the shipped scanner covers uppercase Markdown extensions", () => {
  // `git ls-files '*.md'` is case-sensitive; a gate that claims repo-wide
  // Markdown coverage and misses `BAD.MD` is lying about its own scope.
  const root = makeConsumerRepo({ "README.md": CLEAN, "docs/BAD.MD": BAD });
  try {
    const res = runShipped(root);
    assert.equal(res.status, 1, res.stdout + res.stderr);
    assert.match(res.stderr, /WCAG-131-TABLE/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
