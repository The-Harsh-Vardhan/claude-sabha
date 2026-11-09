#!/usr/bin/env bash
# FOR-ME.md stays fresh: sabha-item add and close re-render it (the new item shows, its header time is not older than
# the item); with a failing renderer the append still succeeds and warns; SABHA_FORME_REGEN=0 skips the render;
# sabha-watch prints a STALE BOARD banner naming both times when for-me.items is newer than FOR-ME.md by more than
# SABHA_FORME_STALE_SECS, and none when fresh or when the threshold is 0. Temp folder only. Run: tests/test-forme-fresh.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-fresh.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_IMPL=$dir SABHA_NOTIFY_DESKTOP=0 SABHA_NUDGE_BIN=true
fail() { echo "FAIL: $*"; exit 1; }
board=$dir/FOR-ME.md

id=$(printf 'why: fresh\n' | "$BIN/sabha-item" add Worker "fresh item one") || fail "add failed"
[[ -f $board ]] && grep -q 'fresh item one' "$board" || fail "add must re-render FOR-ME.md with the new item"
gen=$(sed -n 's/.*generated \([0-9-]* [0-9:]*\)Z.*/\1/p' "$board" | head -1)
added=$(sed -n 's/^utc: \(.*\)T\(.*\)Z$/\1 \2/p' "$dir/for-me.items" | tail -1)
[[ -n $gen && ! $gen < $added ]] || fail "board header time ($gen) must not be older than the item ($added)"
touch -t 202611040900 "$board" "$dir/ref"
"$BIN/sabha-item" close "$id" || fail "close failed"
[[ $board -nt $dir/ref ]] || fail "close must re-render the board"

o=$(printf 'why: x\n' | SABHA_CONF=$dir/missing.conf "$BIN/sabha-item" add Worker "with a broken renderer" 2>&1 >/dev/null); rc=$?
[[ $rc -eq 0 ]] || fail "a failed render must not fail the append, rc=$rc"
grep -q 'title: with a broken renderer' "$dir/for-me.items" || fail "the item must be written even when the render fails"
grep -q 'warning: item written, but FOR-ME.md was not re-rendered' <<<"$o" || fail "a failed render must warn: $o"
grep -q 'with a broken renderer' "$board" && fail "the broken render must not have written the board"

touch -t 202611040900 "$board"
printf 'why: y\n' | SABHA_FORME_REGEN=0 "$BIN/sabha-item" add Worker "no render" >/dev/null || fail "add with regen off failed"
grep -q 'no render' "$board" && fail "SABHA_FORME_REGEN=0 must not render"

touch -t 202610300600 "$board"; touch -t 202611041951 "$dir/for-me.items"
o=$(bash "$BIN/sabha-watch" 2>&1)
grep -q '^STALE BOARD: FOR-ME.md 2026-10-30 06:00 is older than for-me.items 2026-11-04 19:51' <<<"$o" || fail "stale banner with both times missing: $o"
o=$(SABHA_FORME_STALE_SECS=0 bash "$BIN/sabha-watch" 2>&1)
grep -q 'STALE BOARD' <<<"$o" && fail "threshold 0 turns the banner off: $o"
touch -t 202611041950 "$board"
o=$(bash "$BIN/sabha-watch" 2>&1)
grep -q 'STALE BOARD' <<<"$o" && fail "a board 60 s behind is inside the 300 s threshold: $o"
echo "ok: add and close re-render FOR-ME.md, a failed render warns and keeps the item, regen off, stale banner with both times"
