#!/usr/bin/env bash
# The heartbeat (SABHA_HEARTBEAT in sabha-loop: dispatcher and Elephant get a wake-up prompt, nobody else), the duplicate
# check inside sabha-loop (a live claude -n <Name>, or a second loop), and the sabha.conf fallback for a kit worktree.
# The agent is a fake (SABHA_LOOP_CMD), herdr is the hermetic fake, ps is a file; no cron, no real pane.
# Run: tests/test-heartbeat.sh (takes about 20 s)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-hb.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
lp=""
trap '[[ -n $lp ]] && kill -TERM "$lp" 2>/dev/null; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1: ${out:-}"; fails=$((fails + 1)); fi; }
W=${SABHA_TEST_WAIT:-60}
wait_for() { local i; for (( i = 0; i < $3; i++ )); do grep -Eq "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }

mkdir -p "$dir/impl/status" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Builder:opus Elephant:opus"\nSABHA_ELEPHANT=Elephant\n' "$dir/ws" "$dir/impl" > "$dir/sabha.conf"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt SABHA_LOOP_INTERVAL=1 SABHA_LOOP_MIN_UP=3 SABHA_LOOP_GRACE=2 SABHA_NOTIFY_DESKTOP=0
FAKE='trap "exit 0" INT TERM; sleep 60 & wait'

echo "--- helpers"
h() { "$SH" -c '. "$1/sabha-lib.sh"; sabha_load t; shift; "$@"' _ "$BIN" "$@" 2>&1; }
out=$(h sabha_hb_secs 20m); check "20m = 1200" '[[ $out == 1200 ]]'
out=$(h sabha_hb_secs 90s); check "90s = 90" '[[ $out == 90 ]]'
out=$(h sabha_hb_secs 2h); check "2h = 7200" '[[ $out == 7200 ]]'
out=$(h sabha_hb_secs off); check "off = 0" '[[ $out == 0 ]]'
out=$(h sabha_hb_secs nonsense); check "a typo falls back to 20 minutes, never silent" '[[ $out == 1200 ]]'
check "the dispatcher and the Elephant get the heartbeat, the builder does not" 'h sabha_hb_role Dispatcher >/dev/null && h sabha_hb_role Elephant >/dev/null && ! h sabha_hb_role Builder >/dev/null && ! h sabha_hb_role Relay >/dev/null'
out=$(h sabha_hb_text Dispatcher)
check "dispatcher text: gate, queue, inbox, lock, with this kit's paths" 'grep -q "^Heartbeat 20" <<<"$out" && grep -q "$BIN/sabha-heavy gate" <<<"$out" && grep -q "$BIN/sabha-queue next" <<<"$out" && grep -q "$BIN/sabha-lock" <<<"$out" && grep -q "unacked briefs" <<<"$out"'
out=$(h sabha_hb_text Elephant)
check "Elephant text: INDEX.md, counter, digest, open-threads, replies" 'grep -q "$dir/ws/docs/sabha/bhishma/INDEX.md" <<<"$out" && grep -q "sabha-ask --counter" <<<"$out" && grep -q "nightly digest" <<<"$out" && grep -q "open-threads.md" <<<"$out" && grep -q "ask-\*.md" <<<"$out"'

echo "--- the loop: heartbeat"
SABHA_HEARTBEAT=2s SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Dispatcher 2>/dev/null &
lp=$!
wait_for "$dir/impl/status/loop/dispatcher.log" ' heartbeat$' "$W"
out=$(cat "$dir/impl/status/loop/dispatcher.log" 2>/dev/null)
check "dispatcher loop logs a heartbeat" 'grep -q " heartbeat$" <<<"$out"'
wait_for "$FAKE_HERDR_DIR/log" 'agent prompt dispatcher Heartbeat ' 20
out=$(grep 'agent prompt' "$FAKE_HERDR_DIR/log" 2>/dev/null)
check "the nudge text reached the fake herdr: agent prompt dispatcher Heartbeat ..." 'grep -q "agent prompt dispatcher Heartbeat " <<<"$out"'
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""
check "the loop's pid file is gone after TERM" '[[ ! -e $dir/impl/status/loop/dispatcher.pid ]]'

SABHA_HEARTBEAT=2s SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Builder 2>/dev/null &
lp=$!
wait_for "$dir/impl/status/loop/builder.log" ' start \(' "$W"; sleep 5
out=$(cat "$dir/impl/status/loop/builder.log")
check "a builder loop never logs a heartbeat" '! grep -q " heartbeat$" <<<"$out"'
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""

SABHA_HEARTBEAT=0 SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Elephant 2>/dev/null &
lp=$!
wait_for "$dir/impl/status/loop/elephant.log" ' start \(' "$W"; sleep 4
out=$(cat "$dir/impl/status/loop/elephant.log")
check "SABHA_HEARTBEAT=0 turns it off" '! grep -q " heartbeat$" <<<"$out"'
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""

echo "--- the loop: duplicate check"
printf '  901 ttys014  Tue Nov 10 18:00:00 2026     claude -n Builder --model opus --effort medium\n' > "$dir/ps.txt"
rm -f "$dir/impl/status/loop/builder.log"
out=$(SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Builder 2>&1); rc=$?
check "a live claude -n Builder (a --resume pane): refused, exit 1, names the pid" '(( rc == 1 )) && grep -q "Builder already has a live claude session" <<<"$out" && grep -q "901 ttys014" <<<"$out"'
check "nothing was started" '! grep -q " start (" "$dir/impl/status/loop/builder.log" 2>/dev/null'
out=$(SABHA_FORCE=1 SABHA_LOOP_CMD='exit 0' "$SH" "$BIN/sabha-loop" Builder 2>&1 | head -3); rc=$?
check "SABHA_FORCE=1 skips the check" '! grep -q "already has a live" <<<"$out"'
: > "$dir/ps.txt"
rm -f "$dir/impl/status/loop/builder.log"
SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Builder 2>/dev/null &
lp=$!
wait_for "$dir/impl/status/loop/builder.log" ' start \(' "$W"
out=$(SABHA_LOOP_CMD="$FAKE" "$SH" "$BIN/sabha-loop" Builder 2>&1); rc=$?
check "a second loop for the same role is refused, names the first pid" '(( rc == 1 )) && grep -q "a loop for Builder is already running (pid $lp)" <<<"$out"'
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""

echo "--- sabha.conf fallback"
mkdir -p "$dir/kit" "$dir/cwd" && cp -R "$BIN" "$dir/kit/bin"
chk() { ( cd "$dir/cwd" && env -u SABHA_CONF "$@" 2>&1 ); }
out=$(chk "$SH" "$dir/kit/bin/sabha-check"); rc=$?
check "no conf beside the scripts, no SABHA_HOME_CONF: says how to set SABHA_CONF" '(( rc == 1 )) && grep -q "no config at .*/kit/bin/../sabha.conf" <<<"$out" && grep -q "set SABHA_CONF=/path/to/sabha.conf" <<<"$out"'
out=$(chk env SABHA_HOME_CONF="$dir/sabha.conf" "$SH" "$dir/kit/bin/sabha-check"); rc=$?
check "SABHA_HOME_CONF is the fallback: roster read, the notice names the file" '(( rc == 0 )) && grep -q "using $dir/sabha.conf" <<<"$out" && grep -q "^Dispatcher " <<<"$out"'
out=$(chk env SABHA_HOME_CONF="$dir/sabha.conf" "$SH" "$dir/kit/bin/sabha-loop" Nobody); rc=$?
check "unknown role: names the conf, the roster and SABHA_CONF" '(( rc == 2 )) && grep -q "unknown role: Nobody (roster in $dir/sabha.conf: Relay Dispatcher Builder Elephant" <<<"$out" && grep -q "set SABHA_CONF=" <<<"$out"'
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\n' "$dir/ws" "$dir/impl" > "$dir/kit/sabha.conf"
out=$(chk env SABHA_HOME_CONF="$dir/sabha.conf" "$SH" "$dir/kit/bin/sabha-check"); rc=$?
check "a conf beside the scripts wins over the fallback" '! grep -q "using " <<<"$out"'
out=$(chk env SABHA_CONF="$dir/none.conf" SABHA_HOME_CONF="$dir/sabha.conf" "$SH" "$dir/kit/bin/sabha-check"); rc=$?
check "an explicit SABHA_CONF that is missing is an error, not a fallback" '(( rc == 1 )) && grep -q "no config at $dir/none.conf" <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
