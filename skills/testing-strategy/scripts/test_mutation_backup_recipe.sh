#!/usr/bin/env bash
# Executable spec for the mutation backup/restore recipe in
# references/run-killing-mutation-walk.md (Guarded Backup Recipe).
#
# The recipe is prose an agent follows by hand, so this file carries the steps
# verbatim and asserts each property the prose promises. It exists because the
# prose accumulated nineteen review rounds of real defects — symlinks, name
# collisions, quoting, failed copies, cleanup ordering — and narrative scratch
# checks proved them once without leaving anything that fails on regression.
#
# Every assertion here has a stated killing mutation in the deep self-audit
# recorded alongside this change; changing the recipe's guarantees must turn a
# case red.
set -uo pipefail

# Every case runs in `( cd "$t" || exit 1; ... )`. The `|| exit` is load-bearing:
# without it a failed cd leaves the subshell running in the repository root, where
# the fixture writes land — that is how an earlier run of this very file left six
# stray files at the repo root and got them committed.

# Counting is done by parsing markers off stdout, not by shared state: every case
# runs in a subshell, and neither shell variables (invisible to the parent) nor a
# temp tally directory (which earlier vanished mid-run and silently zeroed the
# count while the suite still exited 0) survive that boundary reliably.
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got '$2', want '$3')"; fi; }

# Probe the stat dialect explicitly. A BSD-first `stat -f ... || stat -c ...` does
# NOT fall back on GNU: there `-f` means --file-system and SUCCEEDS with unrelated
# output, so the || branch never runs and the assertion compares garbage.
if stat --version >/dev/null 2>&1; then
  stat_mode() { stat -c '%a' "$1"; }; stat_mtime() { stat -c '%Y' "$1"; }
else
  stat_mode() { stat -f '%Lp' "$1"; }; stat_mtime() { stat -f '%m' "$1"; }
fi
have_git() { command -v git >/dev/null 2>&1; }

# --- the recipe, verbatim -----------------------------------------------------
# backup:  bak=$(mktemp -d); mkdir -p "$bak/$(dirname "$f")" && cp -a -- "$f" "$bak/$f" || exit
# restore: cp -a -- "$bak/$f" "$f" || exit
# cleanup: rm -rf "$bak"   ONLY after every restore succeeded
# The rule promises the backup root sits OUTSIDE the worktree; mktemp honours
# TMPDIR, so that promise has to be checked rather than assumed.
backup_root_outside_worktree() { # backup_root_outside_worktree <bak>
  # Compare against the working directory, not `git rev-parse`: a minimal CI
  # image may have no git, and the original version treated that as "allow",
  # silently disabling the check in exactly the environment it matters in.
  local base bak
  base=$(pwd -P) || return 1
  bak=$(cd -- "$1" && pwd -P) || return 1
  case "$bak/" in "$base"/*) return 1 ;; esac
  return 0
}

backup_one() { # backup_one <bak> <repo-relative path>
  backup_root_outside_worktree "$1" || return 1
  # `--` on dirname too: a first component like -fixtures/ is a valid path but
  # parses as an option without it.
  mkdir -p "$1/$(dirname -- "$2")" && cp -a -- "$2" "$1/$2"
}

# The documented sequence: restore every target, and remove the backup root ONLY
# when all of them succeeded — cleanup after a failed restore destroys the last
# copy while the mutation is still live.
restore_all_and_cleanup() { # restore_all_and_cleanup <bak> <path>...
  local bak="$1"; shift
  local rc=0 one
  for one in "$@"; do restore_one "$bak" "$one" || rc=1; done
  [ "$rc" -eq 0 ] && rm -rf "$bak"
  return "$rc"
}
restore_one() { # restore_one <bak> <path>
  cp -a -- "$1/$2" "$2"
}

new_repo() {
  local d
  d=$(mktemp -d)
  git -C "$d" init -q
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  printf '%s' "$d"
}

all_cases() {
  # 1. round trip restores content byte-for-byte
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; printf 'original\n' > a.txt
    backup_one "$bak" a.txt
    printf 'MUTATED\n' > a.txt
    restore_one "$bak" a.txt
    check "content round trip" "$(cat a.txt)" "original" )
  rm -rf "$t" "$bak"

  # 2. metadata survives. Mode alone does NOT discriminate `cp -a` from plain `cp`
  #    here (a plain copy of a 755 file lands 755 after umask), so this asserts the
  #    modification time, which a plain copy resets to now. Both are checked: the
  #    mode assertion guards against an outright chmod, the mtime one is what fails
  #    if someone drops `-a`.
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; printf 'x\n' > m.sh; chmod 755 m.sh; touch -t 202001011200 m.sh
    want_mtime=$(stat_mtime m.sh)
    backup_one "$bak" m.sh
    printf 'MUTATED\n' > m.sh; chmod 600 m.sh
    restore_one "$bak" m.sh
    check "mode preserved" "$(stat_mode m.sh)" "755"
    check "mtime preserved" "$(stat_mtime m.sh)" "$want_mtime" )
  rm -rf "$t" "$bak"

  # 3. same basename in different directories must not collide
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; mkdir -p src tests
    printf 'SRC\n' > src/config.py; printf 'TESTS\n' > tests/config.py
    backup_one "$bak" src/config.py; backup_one "$bak" tests/config.py
    printf 'MUTATED\n' > src/config.py; printf 'MUTATED\n' > tests/config.py
    restore_one "$bak" src/config.py; restore_one "$bak" tests/config.py
    check "no collision (src)" "$(cat src/config.py)" "SRC"
    check "no collision (tests)" "$(cat tests/config.py)" "TESTS" )
  rm -rf "$t" "$bak"

  # 4. paths with spaces and glob characters survive quoting
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; mkdir -p "tests/cases"
    f='tests/cases/new behavior [v2].py'
    printf 'spaced\n' > "$f"
    backup_one "$bak" "$f"
    printf 'MUTATED\n' > "$f"
    restore_one "$bak" "$f"
    check "quoted path round trip" "$(cat "$f")" "spaced" )
  rm -rf "$t" "$bak"

  # 6. git state is untouched: HEAD, status (including another line's staged
  #    entry and an untracked file), and object count all unchanged
  # Skipped where git is unavailable: a minimal CI image may not ship it, and a
  # missing tool must be reported, not silently counted as a failure.
  if have_git; then
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; printf 'base\n' > tracked.txt; git add -A >/dev/null; git commit -qm init
    printf 'uncommitted\n' > tracked.txt
    printf 'staged elsewhere\n' > other.txt; git add other.txt
    printf 'untracked\n' > loose.txt
    before_status=$(git status --porcelain | sort); before_head=$(git rev-parse HEAD)
    # Inventory the object database itself: rev-list --all --count only counts
    # reachable commits, so a stray blob or a create-then-reset commit leaves
    # objects on disk while that number is unchanged.
    before_objects=$(find .git/objects -type f | sort)
    backup_one "$bak" tracked.txt
    printf 'MUTATED\n' > tracked.txt
    restore_one "$bak" tracked.txt
    check "git status untouched" "$(git status --porcelain | sort)" "$before_status"
    check "git HEAD untouched" "$(git rev-parse HEAD)" "$before_head"
    check "git objects untouched" "$(find .git/objects -type f | sort)" "$before_objects" )
  rm -rf "$t" "$bak"

  else
    echo 'SKIP git-state case (git unavailable)'
  fi

  # 7. backup failure is detectable BEFORE mutating (fail-fast precondition)
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1
    if backup_one "$bak" does/not/exist.txt 2>/dev/null; then
      check "missing source backup fails" "succeeded" "failed"
    else
      check "missing source backup fails" "failed" "failed"
    fi )
  rm -rf "$t" "$bak"

  # 8. restore failure is detectable, so cleanup can be gated on it
  t=$(new_repo); bak=$(mktemp -d)
  ( cd "$t" || exit 1; printf 'x\n' > r.txt
    backup_one "$bak" r.txt
    rm -rf "$bak"                        # simulate a lost/failed backup
    if restore_one "$bak" r.txt 2>/dev/null; then
      check "restore failure detected" "succeeded" "failed"
    else
      check "restore failure detected" "failed" "failed"
    fi )
  rm -rf "$t" "$bak"

  # 10. cleanup is gated on restore success. Failure is injected by making the
  #     target read-only, which makes cp fail (a read-only *directory* does not —
  #     overwriting an existing file needs no directory write permission).
  t=$(new_repo)
  ( cd "$t" || exit 1; bak=$(mktemp -d)
    mkdir sub; printf 'keep\n' > sub/k.txt; backup_one "$bak" sub/k.txt
    # Permission-independent failure: replace the parent directory with a regular
    # file, so the restore fails with ENOTDIR. A read-only target would not do —
    # root can overwrite it, which would make this case fail on a root-run lane.
    rm -rf sub; printf 'blocker\n' > sub
    restore_all_and_cleanup "$bak" sub/k.txt 2>/dev/null \
      && check "failed restore reported" succeeded failed || check "failed restore reported" failed failed
    check "backup kept after failed restore" "$([ -d "$bak" ] && echo kept || echo deleted)" kept
    rm -rf "$bak" )
  rm -rf "$t"

  # 11. the success path does remove the backup root
  t=$(new_repo)
  ( cd "$t" || exit 1; bak=$(mktemp -d)
    printf 'ok\n' > g.txt; backup_one "$bak" g.txt
    printf 'MUTATED\n' > g.txt
    restore_all_and_cleanup "$bak" g.txt
    check "restored content" "$(cat g.txt)" "ok"
    check "backup removed on success" "$([ -d "$bak" ] && echo kept || echo deleted)" deleted )
  rm -rf "$t"

  # 12. a backup root inside the worktree is refused (TMPDIR pointing into the repo)
  t=$(new_repo)
  ( cd "$t" || exit 1; printf 'x\n' > in.txt
    inside=$(mktemp -d "$t/inside.XXXXXX")
    backup_one "$inside" in.txt 2>/dev/null \
      && check "in-worktree backup root refused" accepted refused || check "in-worktree backup root refused" refused refused
    outside=$(mktemp -d)
    backup_one "$outside" in.txt 2>/dev/null \
      && check "outside backup root accepted" accepted accepted || check "outside backup root accepted" refused accepted
    rm -rf "$outside" )
  rm -rf "$t"

}

out=$(all_cases 2>&1)
printf '%s\n' "$out"
pass=$(printf '%s\n' "$out" | grep -c '^PASS ')
fail=$(printf '%s\n' "$out" | grep -c '^FAIL ')
echo "mutation-backup-recipe: ${pass} passed, ${fail} failed"
# Partial execution is a failure, not a pass. An empty-run check alone is not
# enough: a case that aborts before its check (a failed cd, setup, or copy) emits
# no marker, and the remaining PASS markers would still carry the suite green.
# Pin the exact count — raise it deliberately when adding a case, which is the
# point: the bump is where you confirm the new assertion actually ran.
expected=17
have_git || expected=$((expected - 3))
total=$((pass + fail))
if [ "$total" -ne "$expected" ]; then
  echo "FAIL: expected $expected assertions, saw $total (a case aborted before asserting, or the count needs updating)" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
