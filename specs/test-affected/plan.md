# Affected-Test Selector for the Inner Loop

## Role

`make test-affected` picks the suites most likely to catch a regression in the files you changed, and runs them in seconds to a few minutes. It is **advisory feedback while iterating**, not a gate:

- **The full lane is still required.** The root contract (`AGENTS.md`, verification section) requires `make test` locally after changing skills, scripts, hooks, docs or plugins.
- **CI still runs every lane.**
- **The output says so.** Every run ends with `advisory: run make test before push`, and the selector never prints a pass that could be read as one.

## Why not a sound selector

Two designs were reviewed:

- **Suite-level, claiming "never under-selects":** 33 findings, 15 of them suites that read a file the map does not link to them.
- **Lane-level:** 21 findings. These included:
  - inputs of the code-review family outside its directory, such as the identity test asserting that the legacy directory `skills/claude-code-review/` is absent, and the updater test reading root `AGENTS.md`;
  - tests registered in no Makefile lane;
  - gates that only CI runs.

A sound selector would have to track the whole repository's file-to-test graph, and the repository requires the full run anyway. The value that remains is fast feedback, so the soundness claim is dropped rather than chased.

## Behavior

- **Selection.** The existing per-path map, plus three automatic rules:
  - every hook suite named in the `Makefile` is used for unmapped hook changes;
  - a changed suite runs itself;
  - a changed `x-y.py` runs its sibling `test_x_y.*`.

  Missing dependencies are precision issues, fixed when found; they do not block.
- **Drift.** A suite the map names but that is missing on disk is reported. The run then falls back to `make test-repo-gates` and `make test-regressions-fast`. A unit test pins that every suite path in the selector exists.
- **Change discovery.**
  - Inputs: committed changes since the merge-base with the base, plus staged, unstaged and untracked files.
  - Paths are read NUL-delimited, with `--no-renames`.
  - Git runs bound to `--repo`, with every repository-routing variable removed: `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_CONFIG*`, `GIT_CEILING_DIRECTORIES`.
- **Base.**
  - `--base-ref`, or `CCL_SKILL_BASE_REF`, wins.
  - Otherwise, the fully qualified `refs/remotes/origin/main` and `refs/remotes/origin/dev`, whichever has its merge-base nearest HEAD.
  - A ref that does not exist is skipped. A git command that fails on an existing ref, or no usable base at all, exits 2 with a message.
  - The chosen base is printed. For a promotion between integration branches (for example `dev` into `main`), pass `--base-ref`.
- **Running.** Selected suites run through `scripts/run-parallel-suites.sh`, then the serial commands. The first non-zero exit is returned unchanged. A skipped slow lane is listed in a final `skipped:` line.
- **Output.**
  - The last line is always `advisory: run make test before push`, preceded by `select_affected_tests_done` (exit 0) or the failing command's exit code.
  - `--dry-run` prints shell-quoted commands, including `--jobs`.
- **Tests never touch the caller's repository.** Fixture git commands run with the same variables removed and `GIT_CONFIG_GLOBAL=/dev/null`.

## Tests

| Layer | Decision | Command |
| --- | --- | --- |
| unit | update | `python3 scripts/test_select_affected_tests.py`. Covers: drift fallback end to end; sibling and self rules; base resolution (stale integration ref, a local branch named `origin/main`, missing `origin/dev`, a failing git command exits 2); inherited `GIT_DIR` and `GIT_INDEX_FILE` ignored; a non-ASCII and space-containing path; a failing child keeps its exit code; quoted dry-run output |
| integration | run | `make test-affected-plan` and `make test-affected` on this branch |
| full | run | `CCL_BROAD_TEST_REASON=repo-required make test` |
