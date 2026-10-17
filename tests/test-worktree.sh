#!/usr/bin/env bash
# bin/sabha-worktree: create <repo>--<slug> on a new branch from a base, refuse bad input, guard and hook block commits
# in the main checkout but not in the worktree. Run: tests/test-worktree.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-wt.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
cd "$dir" || exit 1
git init -q -b main proj && git -C proj commit -q --allow-empty -m base || { echo "FAIL: git setup"; exit 1; }
git -C proj branch dev
[[ $("$bin/sabha-worktree" 2>/dev/null; echo $?) == 2 ]] || { echo "FAIL: no args should exit 2"; exit 1; }
wt=$("$bin/sabha-worktree" create proj feat dev) || { echo "FAIL: create"; exit 1; }
[[ $wt == "$dir/proj--feat" && -d $wt ]] || { echo "FAIL: path $wt"; exit 1; }
[[ $(git -C "$wt" branch --show-current) == wt/feat ]] || { echo "FAIL: branch"; exit 1; }
"$bin/sabha-worktree" create proj feat dev 2>/dev/null && { echo "FAIL: reused path"; exit 1; }
"$bin/sabha-worktree" create proj other nobase 2>/dev/null && { echo "FAIL: unknown base"; exit 1; }
"$bin/sabha-worktree" create "$wt" again dev 2>/dev/null && { echo "FAIL: create from a worktree"; exit 1; }
"$bin/sabha-worktree" create proj x/y dev 2>/dev/null && { echo "FAIL: bad slug"; exit 1; }
"$bin/sabha-worktree" guard proj 2>/dev/null && { echo "FAIL: guard passed main checkout"; exit 1; }
"$bin/sabha-worktree" guard "$wt" || { echo "FAIL: guard refused worktree"; exit 1; }
h=$("$bin/sabha-worktree" hook proj) || { echo "FAIL: hook"; exit 1; }
[[ -x $h ]] || { echo "FAIL: hook not executable"; exit 1; }
"$bin/sabha-worktree" hook proj 2>/dev/null && { echo "FAIL: hook replaced"; exit 1; }
git -C proj commit -q --allow-empty -m nope 2>/dev/null && { echo "FAIL: main checkout commit allowed"; exit 1; }
git -C "$wt" commit -q --allow-empty -m ok || { echo "FAIL: worktree commit blocked"; exit 1; }
echo "ok: worktree <repo>--<slug> on a new branch, bad base/slug/reuse refused, hook blocks main-checkout commits only"
