#!/usr/bin/env bash
# bin/sabha-check --agents: a fake ListAgents list with "Vidur-old [x]" and "Vidur [y]" prints both rows, one
# "duplicate role" line naming Vidur [y] as newest, exit 1; two plain rows name the last listed; a copy such as
# BuilderPrecise-2 is its own role; a clean list exits 0. No herdr, no process list, no config. Run: tests/test-agents-dup.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-agents.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
C() { bash "$BIN/sabha-check" --agents "$@"; }

printf '%s\n' 'Vidur-old [ee9597] idle' 'Yudhishthira [eddbfa] busy' 'Vidur [70d3c2] busy' 'BuilderPrecise [a1]' 'BuilderPrecise-2 [a2]' >"$dir/list"
o=$(C "$dir/list"); rc=$?
[[ $rc -eq 1 ]] || fail "a duplicate role must exit 1, rc=$rc: $o"
for want in 'Vidur: Vidur-old \[ee9597\]' 'Vidur: Vidur \[70d3c2\]' 'duplicate role Vidur: 2 rows; newest is Vidur \[70d3c2\]'; do
  printf '%s\n' "$o" | grep -q "$want" || fail "missing '$want': $o"
done
printf '%s\n' "$o" | grep -q 'duplicate role BuilderPrecise\|duplicate role Yudhishthira' && fail "a copy or a single row is not a duplicate: $o"

o=$(printf '%s\n' 'Yudhishthira [d8b43f]' 'Yudhishthira [eddbfa]' | C -); [[ $? -eq 1 ]] || fail "two plain rows are a duplicate"
printf '%s\n' "$o" | grep -q 'newest is Yudhishthira \[eddbfa\]' || fail "the last listed plain row is the newest: $o"

o=$(printf '%s\n' 'Vidur [70d3c2]' 'Vidur-old [ee9597]' | C -)
printf '%s\n' "$o" | grep -q 'newest is Vidur \[70d3c2\]' || fail "a row without -old beats a later -old row: $o"

o=$(C "$dir/nothere" 2>&1); [[ $? -eq 2 ]] || fail "an unreadable list is a usage error (2): $o"
o=$(printf 'Vidur [1]\nNakul [2]\n' | C -); rc=$?
[[ $rc -eq 0 ]] && printf '%s\n' "$o" | grep -q 'no duplicate role rows' || fail "a clean list exits 0, rc=$rc: $o"
echo "ok: --agents names duplicate and -old rows with the newest, copies stay separate, clean list passes"
