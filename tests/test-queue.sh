#!/usr/bin/env bash
# bin/sabha-queue: append-only queue.items blocks, newest value wins, next order and --light-only, the state verbs. Run: tests/test-queue.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-t.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

export SABHA_IMPL=$dir/impl
mkdir -p "$SABHA_IMPL"
q() { "$SH" "$BIN/sabha-queue" "$@" 2>&1; }

out=$(q add 2057 "heartbeat work" --kind heavy --note "needs the box"); rc=$?
check "add prints id 1" '(( rc == 0 )) && [[ $out == 1 ]]'
out=$(q add 2058 "light thing")
check "second add is id 2, kind defaults to light" '[[ $out == 2 ]] && grep -q "^kind: light$" "$SABHA_IMPL/queue.items"'
out=$(q next)
check "next is the oldest queued item" '[[ $out == "1 queued heavy brief 2057: heartbeat work" ]]'
out=$(q next --light-only)
check "next --light-only skips the heavy item" '[[ $out == "2 queued light brief 2058: light thing" ]]'
q start 1 Karna >/dev/null
out=$(q list running)
check "start: running with its owner" '[[ $out == "1 running heavy brief 2057 owner Karna: heartbeat work | needs the box" ]]'
out=$(q next)
check "next skips a running item" '[[ $out == 2\ * ]]'
q block 2 "waits on 1" >/dev/null
out=$(q next); rc=$?
check "nothing queued: exit 1" '(( rc == 1 )) && grep -q "nothing queued" <<<"$out"'
q done 1 "tests green" >/dev/null; q fail 2 "gave up" >/dev/null
out=$(q list)
check "done and failed with notes" 'grep -q "^1 done heavy .*| tests green$" <<<"$out" && grep -q "^2 failed light .*| gave up$" <<<"$out"'
check "append-only: 6 blocks (2 adds, 4 changes), id 1 has 3, none rewritten" '[[ $(grep -c "^---$" "$SABHA_IMPL/queue.items") == 6 ]] && [[ $(grep -c "^id: 1$" "$SABHA_IMPL/queue.items") == 3 ]]'
check "finished is set on done" '[[ -n $(sed -n "s/^finished: \(20.*\)/\1/p" "$SABHA_IMPL/queue.items" | head -1) ]]'
out=$(q status)
check "status counts" '[[ $out == "queue 0 queued, 0 running, 0 blocked, 1 done, 1 failed" ]]'
out=$(q start 99); rc=$?
check "an unknown id is refused" '(( rc == 1 )) && grep -q "no item 99" <<<"$out"'
out=$(q add x "t" --kind big); rc=$?
check "a bad kind is refused" '(( rc == 2 ))'
out=$(q add 9 "two"$'\n'"lines"); rc=$?
check "a multi-line title is refused" '(( rc == 2 ))'
out=$(q add 3 "after done"); 
check "ids never repeat after changes" '[[ $out == 3 ]]'
out=$(q start 3 A); out2=$(q start 3 B); rc=$?
check "start refuses an item that is not queued (no double start)" '(( rc == 1 )) && grep -q "item 3 is running, not queued" <<<"$out2" && [[ $(q list running | grep -c "^3 ") == 1 ]] && [[ $(q list running) == *"owner A:"* ]]'
# a regression of the trailing-option bug loops forever, so each call gets a hard timeout
tq() { perl -e 'alarm 5; exec @ARGV' "$SH" "$BIN/sabha-queue" "$@" 2>&1; }
out=$(tq add 4 "t" --kind); rc=$?
check "trailing --kind dies with a message, no hang" '(( rc == 2 )) && grep -q "^sabha-queue: --kind needs a value" <<<"$out"'
out=$(tq add 4 "t" --note); rc=$?
check "trailing --note dies with a message, no hang" '(( rc == 2 )) && grep -q "^sabha-queue: --note needs a value" <<<"$out"'
out=$(tq add 4 "t" --kind heavy --note); rc=$?
check "trailing --note after a valid --kind also dies" '(( rc == 2 )) && grep -q "needs a value" <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
