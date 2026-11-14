#!/usr/bin/env bash
# bin/sabha-lock: the machine-wide mkdir lock: acquire, busy, release by label only, run releasing on exit and on TERM, stale reclaim only when old and the holder pid is dead. Run: tests/test-lock.sh
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

export SABHA_LOCK_DIR=$dir/lock SABHA_LOCK_POLL=1
lk() { "$SH" "$BIN/sabha-lock" "$@" 2>&1; }

out=$(env -u SABHA_LOCK_DIR "$SH" "$BIN/sabha-lock" status 2>&1); rc=$?
check "SABHA_TEST=1 without SABHA_LOCK_DIR refuses the real lock" '(( rc == 2 )) && grep -q "refusing the real lock" <<<"$out"'
out=$(lk status); rc=$?
check "free at first" '(( rc == 0 )) && [[ $out == free ]]'
out=$(lk acquire build-a 0 $$); rc=$?
check "acquire takes it, holder file names label and pid" '(( rc == 0 )) && grep -q "^label: build-a$" "$dir/lock/holder" && grep -q "^pid: $$$" "$dir/lock/holder"'
out=$(lk acquire e2e-b 0); rc=$?
check "a second acquire is busy (75), naming the holder" '(( rc == 75 )) && grep -q "held: build-a" <<<"$out"'
out=$(lk release e2e-b); rc=$?
check "another label cannot release it" '(( rc == 1 )) && [[ -d $dir/lock ]]'
lk release build-a >/dev/null
check "release frees it" '[[ ! -d $dir/lock ]]'

out=$(lk run job -- sh -c 'cat "$SABHA_LOCK_DIR/holder"; exit 7'); rc=$?
check "run holds the lock while the command runs and passes its exit code" '(( rc == 7 )) && grep -q "^label: job$" <<<"$out"'
check "run released on exit" '[[ ! -d $dir/lock ]]'
"$SH" "$BIN/sabha-lock" run slow -- sleep 30 >/dev/null 2>&1 & rp=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -d $dir/lock ]] && break; sleep 0.3; done
check "a running job holds it" '[[ -d $dir/lock ]]'
kill -TERM "$rp"; wait "$rp" 2>/dev/null
check "TERM releases it (trap)" '[[ ! -d $dir/lock ]]'

echo "--- stale reclaim"
sh -c 'exit 0' & dead=$!; wait "$dead"
old=$(( $(date +%s) - 7200 ))
mklock() { rm -rf "$dir/lock"; mkdir "$dir/lock"; printf 'pid: %s\nlabel: old\nepoch: %s\n' "$1" "$2" > "$dir/lock/holder"; }
mklock "$dead" "$old"
out=$(SABHA_LOCK_STALE_MIN=90 lk acquire fresh 0 $$); rc=$?
check "old lock + dead pid: reclaimed, taken" '(( rc == 0 )) && grep -q "reclaimed a stale lock" <<<"$out" && grep -q "^label: fresh$" "$dir/lock/holder"'
lk release fresh >/dev/null
mklock $$ "$old"
out=$(SABHA_LOCK_STALE_MIN=90 lk acquire fresh 0); rc=$?
check "old lock + live pid: never reclaimed" '(( rc == 75 )) && grep -q "^label: old$" "$dir/lock/holder"'
mklock "$dead" "$(( $(date +%s) - 45 ))"
out=$(SABHA_LOCK_STALE_MIN=90 lk acquire fresh 0); rc=$?
check "young lock + dead pid: not yet stale" '(( rc == 75 ))'
out=$(SABHA_LOCK_STALE_MIN=1 lk acquire fresh 0 $$); rc=$?
check "same young lock with N=1 minute: still young (45s is not past 1 min; a 60s lock sat on the edge and flaked under load)" '(( rc == 75 ))'
mklock "$dead" "$(( $(date +%s) - 150 ))"
out=$(SABHA_LOCK_STALE_MIN=1 lk acquire fresh 0 $$); rc=$?
check "N is configurable: 150s old, dead pid, N=1 minute: reclaimed" '(( rc == 0 ))'

echo "--- a lock directory with no holder file (the holder died between mkdir and the write)"
# a regression hangs or spins, so the parallel and empty-dir calls get a hard timeout
tl() { perl -e 'alarm 20; exec @ARGV' "$SH" "$BIN/sabha-lock" "$@" 2>&1; }
rm -rf "$dir/lock"; mkdir "$dir/lock"; touch -t 202001010000 "$dir/lock"
out=$(SABHA_LOCK_STALE_MIN=1 tl acquire fresh 0 $$); rc=$?
check "empty old lock dir: reclaimed by its own mtime, taken" '(( rc == 0 )) && grep -q "reclaimed a stale lock" <<<"$out" && grep -q "^label: fresh$" "$dir/lock/holder"'
lk release fresh >/dev/null
rm -rf "$dir/lock"; mkdir "$dir/lock"
out=$(SABHA_LOCK_STALE_MIN=1 tl acquire fresh 0 $$); rc=$?
check "empty young lock dir: not reclaimed (a holder may be about to write)" '(( rc == 75 )) && [[ -d $dir/lock ]]'
rm -rf "$dir/lock"

echo "--- reclaim is a second mutex"
mklock "$dead" "$old"
for i in 1 2 3 4 5 6; do SABHA_LOCK_STALE_MIN=90 tl acquire "p$i" 0 $$ >"$dir/par.$i" 2>&1; echo $? >"$dir/par.rc.$i" & done
wait
ok=0; for i in 1 2 3 4 5 6; do [[ $(cat "$dir/par.rc.$i") == 0 ]] && ok=$((ok + 1)); done
check "6 parallel acquires on one old dead lock: exactly one rc=0" '(( ok == 1 ))'
check "the others are busy (75), not an error" '[[ $(cat "$dir"/par.rc.* | grep -c "^75$") == 5 ]]'
check "the reclaim mutex is gone on every exit path" '[[ ! -e $dir/lock.reclaim ]]'
rm -rf "$dir/lock"
mklock "$dead" "$old"; mkdir "$dir/lock.reclaim"
out=$(SABHA_LOCK_STALE_MIN=90 tl acquire fresh 0 $$); rc=$?
check "a young reclaim mutex (a live reclaimer) blocks the reclaim" '(( rc == 75 )) && grep -q "^label: old$" "$dir/lock/holder"'
touch -t 202001010000 "$dir/lock.reclaim"
out=$(SABHA_LOCK_STALE_MIN=90 tl acquire fresh 0 $$); rc=$?
check "a reclaim mutex older than 60 s is stale: reclaimed, taken, mutex gone" '(( rc == 0 )) && [[ ! -e $dir/lock.reclaim ]]'
lk release fresh >/dev/null
mklock $$ "$old"
out=$(SABHA_LOCK_STALE_MIN=90 tl acquire fresh 0); rc=$?
check "a live holder: reclaim fails and still removes its mutex" '(( rc == 75 )) && [[ ! -e $dir/lock.reclaim ]]'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
