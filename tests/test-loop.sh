#!/usr/bin/env bash
# bin/sabha-loop with a fake agent (SABHA_LOOP_CMD) and fake files, no Claude run: the self-test passes; a Claude pane
# at 35% with a fresh handoff is restarted; two sessions that die at once stop the loop; SABHA_STOP starts nothing;
# --stop ends the loop. Run: tests/test-loop.sh (takes about 15 s; longer on Git Bash)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-loop.XXXXXX") || exit 1
lp=""
trap '[[ -n $lp ]] && kill -TERM "$lp" 2>/dev/null; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Arjun:opus:low Oc:opencode:medium"\n' "$dir" "$dir" >"$dir/sabha.conf"
# a short grace: where the test runs with SIGINT ignored (CI, a tool shell) the fake only dies from the TERM that follows
export SABHA_CONF=$dir/sabha.conf SABHA_LOOP_INTERVAL=1 SABHA_LOOP_MIN_UP=3 SABHA_LOOP_GRACE=2 SABHA_NOTIFY_DESKTOP=0
mkdir -p "$dir/status/context" "$dir/inbox/Arjun" "$dir/inbox/Oc"
fail() { echo "FAIL: $*"; exit 1; }
# wait_for <file> <grep -E pattern> <seconds>: poll instead of a fixed sleep; a loop on a slow machine (Git Bash) can
# take several seconds to log its start
wait_for() { local i; for (( i = 0; i < $3; i++ )); do grep -Eq "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }
log=$dir/status/loop/arjun.log

bash "$BIN/sabha-loop" --self-test | tail -1 | grep -q 'all ok' || fail "self-test"

# 1. a Claude pane: 35% and a handoff saved after the start -> the fake agent is interrupted and started again
#    started with SABHA_FORCE=1 (a grid --force): only the first session may see it
echo 35 >"$dir/status/context/arjun.txt"
SABHA_FORCE=1 SABHA_LOOP_CMD='echo "${SABHA_FORCE:-unset}" >>"'"$dir"'/force.txt"; trap "exit 0" INT TERM; sleep 20 & wait' bash "$BIN/sabha-loop" Arjun 2>/dev/null &
lp=$!
# the handoff must be newer than the logged start (1 s mtime granularity): wait for the line, then step past that second
wait_for "$log" ' start \(' 20; sleep 2; touch "$dir/status/context/arjun.txt" "$dir/status/arjun.md"
wait_for "$log" 'restart: context 35%' 20
grep -q 'restart: context 35%' "$log" || fail "no restart logged: $(cat "$log" 2>/dev/null)"
for _ in $(seq 1 20); do [[ $(grep -c '^.* start (' "$log") -ge 2 ]] && break; sleep 1; done
[[ $(grep -c '^.* start (' "$log") -ge 2 ]] || fail "a second start should follow the restart: $(cat "$log")"
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
[[ $(sed -n 1p "$dir/force.txt") == 1 && $(sed -n 2p "$dir/force.txt") == unset ]] || fail "SABHA_FORCE must reach the first start only: $(cat "$dir/force.txt")"

# 1b. an agent that ignores SIGINT (what a "&" child of a script may inherit): the TERM after the grace ends it and a
# second session starts
: >"$log"; touch -t 202001010000 "$dir/status/arjun.md"
SABHA_LOOP_CMD='trap "" INT; trap "exit 0" TERM; sleep 20 & wait' bash "$BIN/sabha-loop" Arjun 2>/dev/null &
lp=$!
wait_for "$log" ' start \(' 20; sleep 2; touch "$dir/status/context/arjun.txt" "$dir/status/arjun.md"
for _ in $(seq 1 30); do [[ $(grep -c ' start (' "$log" 2>/dev/null) -ge 2 ]] && break; sleep 1; done
[[ $(grep -c ' start (' "$log") -ge 2 ]] || fail "an INT-proof agent was not restarted through TERM: $(cat "$log")"
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null

# 2. an agent that dies at once: the loop gives up after the second death
: >"$log"
# a wider window here: where starting bash alone takes 2-3 s (Git Bash under load) an instant death looks like 3 s
SABHA_LOOP_MIN_UP=10 SABHA_LOOP_CMD='exit 1' bash "$BIN/sabha-loop" Arjun 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] || fail "loop should exit 1 after 2 failed starts, got $rc"
grep -q 'stopped: 2 sessions in a row' "$log" || fail "stop reason missing: $(cat "$log")"
[[ $(grep -c ' start (' "$log") -eq 2 ]] || fail "exactly 2 starts expected: $(cat "$log")"

# 3. SABHA_STOP: a window at 95% with the reset ahead starts nothing; --stop ends the loop
: >"$log"
printf 'five_hour 95 %s %s\n' $(( $(date +%s) + 3600 )) "$(date +%s)" >"$dir/status/limits.txt"
SABHA_LOOP_CMD='exit 1' bash "$BIN/sabha-loop" Arjun 2>/dev/null &
lp=$!
wait_for "$log" 'SABHA_STOP: five-hour at 95%' 20
grep -q 'SABHA_STOP: five-hour at 95%' "$log" || fail "SABHA_STOP not logged: $(cat "$log")"
grep -q ' start (' "$log" && fail "nothing may start under SABHA_STOP"
bash "$BIN/sabha-loop" --stop Arjun >/dev/null
wait "$lp"; [[ $? -eq 0 ]] || fail "--stop should end the loop with 0"
grep -q 'stop requested' "$log" || fail "--stop not logged"
rm -f "$dir/status/limits.txt"

# 4. a non-Claude pane restarts when a brief's .done lands
olog=$dir/status/loop/oc.log
SABHA_LOOP_CMD='trap "exit 0" INT TERM; sleep 20 & wait' bash "$BIN/sabha-loop" Oc 2>/dev/null &
lp=$!
wait_for "$olog" ' start \(' 20; sleep 2; : >"$dir/inbox/Oc/001.done"
wait_for "$olog" 'restart: a brief finished' 20
grep -q 'restart: a brief finished' "$olog" || fail "other pane did not restart on .done: $(cat "$olog" 2>/dev/null)"
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
echo "ok: self-test, restart at 35% with a newer handoff, SABHA_FORCE first start only, TERM fallback for an INT-proof agent, stop after 2 dead starts, SABHA_STOP gate, --stop, .done restart"
