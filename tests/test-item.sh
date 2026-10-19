#!/usr/bin/env bash
# bin/sabha-item: 50 parallel adds get 50 distinct ids and the board shows all 50; close hides one; an id past one
# written by hand is never reused; and sabha-for-me splits a block that lost its leading --- (the stress-test losses).
# Run: tests/test-item.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-item.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_IMPL=$dir
fail() { echo "FAIL: $*"; exit 1; }
board() { python3 -I "$BIN/sabha-for-me" >/dev/null 2>&1; grep -c '^### [0-9]' "$dir/FOR-ME.md"; }

for i in $(seq 1 50); do ( printf 'why: stress %s\n' "$i" | "$BIN/sabha-item" add Worker "item $i" >>"$dir/ids" ) & done; wait
[[ $(sort -u "$dir/ids" | wc -l) -eq 50 ]] || fail "50 parallel adds must print 50 distinct ids, got $(sort -u "$dir/ids" | wc -l)"
[[ $(grep -c '^id: ' "$dir/for-me.items") -eq 50 && $(grep -c '^---$' "$dir/for-me.items") -eq 50 ]] || fail "file must hold 50 blocks, each with its ---"
[[ $(board) -eq 50 ]] || fail "board must show all 50 items, shows $(board)"

"$BIN/sabha-item" close 7 || fail "close failed"
[[ $(board) -eq 49 ]] || fail "a closed item must leave the open list, board shows $(board)"
"$BIN/sabha-item" close 999 2>/dev/null && fail "closing an unknown id must fail"

printf -- '---\nid: 70\nutc: 2026-10-19T10:00:00Z\nowner: A\nstate: OPEN\ntitle: by hand\n' >>"$dir/for-me.items"
[[ $("$BIN/sabha-item" add Worker "after hand") -eq 71 ]] || fail "the next id must follow the highest id in the file"

# a block appended without its leading --- (the second item has no separator)
cat >"$dir/for-me.items" <<'X'
---
id: 1
utc: 2026-10-19T10:00:00Z
owner: A
state: OPEN
title: first item
why: one
id: 2
utc: 2026-10-19T10:01:00Z
owner: B
state: OPEN
title: second item
X
rm -rf "$dir/status/item-ids"
[[ $(board) -eq 2 ]] || fail "a block without its --- must still be its own item, board shows $(board)"

echo "ok: 50 parallel adds give 50 ids and 50 board items, close, next id past a hand-written one, a block missing its --- is split"
