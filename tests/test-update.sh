#!/usr/bin/env bash
# `sabha update` against a local bare repo (no network): a clone that is behind fast-forwards and prints the
# CHANGELOG head; a diverged clone and a dirty clone die and change nothing. Run: tests/test-update.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-update.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
g() { git -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }

g init -q "$dir/seed"; mkdir -p "$dir/seed/bin"
cp "$BIN/sabha" "$dir/seed/bin/sabha"
printf '# Changelog\n\n## 0.1.0\n\n- first\n' > "$dir/seed/CHANGELOG.md"
g -C "$dir/seed" add -A; g -C "$dir/seed" commit -q -m first; g -C "$dir/seed" tag v0.1.0
g -C "$dir/seed" symbolic-ref HEAD refs/heads/main 2>/dev/null; g -C "$dir/seed" branch -q -M main 2>/dev/null
g clone -q --bare "$dir/seed" "$dir/origin.git"
# advance <text>: a new commit on origin's main, made in a scratch clone and brought in with fetch (no network)
adv() {
  rm -rf "$dir/scratch"; g clone -q "$dir/origin.git" "$dir/scratch"
  printf '\n## %s\n' "$1" >> "$dir/scratch/CHANGELOG.md"
  g -C "$dir/scratch" commit -q -am "$1"
  g -C "$dir/origin.git" fetch -q "$dir/scratch" main:main
}
clone() { g clone -q "$dir/origin.git" "$dir/$1"; }
head_of() { g -C "$dir/$1" rev-parse HEAD; }

clone behind; clone diverged; clone dirty
adv "0.2.0 new thing"
before=$(head_of behind)
out=$("$SH" "$dir/behind/bin/sabha" update 2>&1); rc=$?
check "behind clone fast-forwards (rc 0, HEAD moved to origin)" '(( rc == 0 )) && [[ $(head_of behind) != $before && $(head_of behind) == $(g -C "$dir/origin.git" rev-parse main) ]]'
check "...and prints the CHANGELOG head with the new entry" 'grep -q "0.2.0 new thing" <<<"$out" && grep -q "CHANGELOG.md (head)" <<<"$out"'

g -C "$dir/diverged" pull -q --ff-only
printf 'local\n' > "$dir/diverged/local.txt"; g -C "$dir/diverged" add -A; g -C "$dir/diverged" commit -q -m local
printf 'local edit\n' >> "$dir/dirty/CHANGELOG.md"
adv "0.3.0 later thing"
b1=$(head_of diverged); b2=$(head_of dirty); sum=$(cksum <"$dir/dirty/CHANGELOG.md")
out=$("$SH" "$dir/diverged/bin/sabha" update 2>&1); rc=$?
check "diverged clone dies and changes nothing" '(( rc != 0 )) && grep -q "nothing changed" <<<"$out" && [[ $(head_of diverged) == $b1 && -f $dir/diverged/local.txt ]]'
out=$("$SH" "$dir/dirty/bin/sabha" update 2>&1); rc=$?
check "dirty clone (edit to a file origin changed) dies and changes nothing" '(( rc != 0 )) && [[ $(head_of dirty) == $b2 && $(cksum <"$dir/dirty/CHANGELOG.md") == $sum ]]'
(( fails == 0 )) && { echo "ok: sabha update fast-forwards and prints the CHANGELOG head; diverged and dirty trees change nothing"; exit 0; }
echo "$fails check(s) failed"; exit 1
