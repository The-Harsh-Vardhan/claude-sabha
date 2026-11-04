#!/usr/bin/env bash
# Durable helpers (docs/durable-helpers.md) against a fake claude and a fake process list, never a real herdr:
# a detached start, a registry entry, survival of a simulated dispatcher restart (its process group is killed),
# re-attach, crash detection and re-dispatch, no double start, the caps (SABHA_STOP, SABHA_HELPER_MAX, load), stop,
# and sabha-down.sh cleanup. No model is called. Run: tests/test-helper.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-helper.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
hold=$dir/hold
S=${HELPER_TEST_SLOW:-1}
export SABHA_HELPER_START_WAIT=$(( 30 * S ))
cleanup() {
  rm -f "$hold"
  "$SH" "$BIN/sabha-helper" stop --all --timeout $((10 * S)) >/dev/null 2>&1
  rm -rf "$dir" "$HERMETIC_FAKE_DIR"
}
trap cleanup EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
# waitfor <condition> [seconds]: polls until the condition holds; the wait and every timeout below scale with
# HELPER_TEST_SLOW (a machine at load 300 needs 10 to 20 seconds for one process start)
waitfor() { local end=$(( SECONDS + ${2:-30} * S )); while ! eval "$1"; do (( SECONDS >= end )) && return 1; sleep 0.2; done; return 0; }
jget() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2" 2>/dev/null; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
cat > "$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$dir/impl
SABHA_PROJECT=Test
SABHA_ROSTER="Relay:opus:medium Yudhi:opus:medium Karna:sonnet:high Lazy1:haiku:low:gate,lazy Lazy2:sonnet:medium:lazy,mcp"
EOF
# fake claude: logs its argv and its pid; FAKE_HOLD keeps it running while that file exists; FAKE_DONE=1 writes the
# brief's .done as a real run would
cat > "$dir/stubs/claude" <<'STUB'
#!/bin/sh
echo "FAKE claude $*"
echo "$*" >> "$CALLS"
[ -n "$FAKE_PIDS" ] && echo $$ >> "$FAKE_PIDS"
if [ -n "$FAKE_HOLD" ]; then i=0; while [ -e "$FAKE_HOLD" ] && [ $i -lt 240 ]; do sleep 0.5; i=$((i+1)); done; fi
if [ "$FAKE_DONE" = 1 ]; then
  f=$(printf '%s\n' "$*" | sed -n 's/.*write \(inbox\/[A-Za-z0-9-]*\/[0-9]*\.done\).*/\1/p' | head -1)
  [ -n "$f" ] && printf 'utc: x\nresult: ok\n' > "$IMPL/$f"
fi
exit 0
STUB
# osascript and kill for sabha-down.sh: nothing is closed or signalled for real
printf '#!/bin/sh\nexit 0\n' > "$dir/stubs/osascript"
printf '#!/bin/sh\n[ "$1" = -0 ] && exit 1\nexit 0\n' > "$dir/stubs/fakekill"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript" "$dir/stubs/fakekill"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH IMPL=$dir/impl CALLS=$dir/calls FAKE_PIDS=$dir/pids
export SABHA_BACKEND=iterm SABHA_NOTIFY_DESKTOP=0 SABHA_HELPER_LOAD_MAX=off SABHA_LOADAVG=1
export FAKE_HOLD="" FAKE_DONE=1
unset SABHA_STOP SABHA_HELPER_MAX SABHA_RUN_TIMEOUT SABHA_DETACH_TOOL
brief() { mkdir -p "$dir/impl/inbox/$1"; echo "to: $1" > "$dir/impl/inbox/$1/$2-yudhi-task.md"; }
# busy: some run.lock names a live process (an earlier case's supervisor still finishing)
busy() { local l; for l in "$dir"/impl/inbox/*/run.lock; do [[ -e $l ]] && kill -0 "$(cat "$l" 2>/dev/null)" 2>/dev/null && return 0; done; return 1; }
reset() {
  # an earlier case's helper must be gone before its files are wiped: a late supervisor would write its done and its
  # registry entry into the next case, which reuses the same role, brief number and id
  rm -f "$hold"; waitfor '! busy' 60
  "$SH" "$BIN/sabha-helper" stop --all --timeout $((10 * S)) >/dev/null 2>&1; waitfor '! busy' 60
  rm -rf "$dir/impl/inbox" "$dir/impl/runs" "$dir/impl/status/helpers" "$dir/impl/status/limits.txt"; : > "$CALLS"; : > "$FAKE_PIDS"
  : > "$dir/ps.txt"; export SABHA_PS_FILE=$dir/ps.txt FAKE_HOLD="" FAKE_DONE=1
}
helper() { out=$("$SH" "$BIN/sabha-helper" "$@" 2>&1); rc=$?; }
reg() { echo "$dir/impl/status/helpers/$1.json"; }
alive() { [[ -n ${1:-} ]] && kill -0 "$1" 2>/dev/null; }
calls() { wc -l < "$CALLS" | tr -d ' '; }

# 1. a detached start writes the registry entry, the ack, the lock and runs claude -p
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1
echo "--- sabha-helper start Lazy1 (rc $rc)"; echo "$out"
r=$(reg Lazy1-001)
check "start: exit 0 and says started" '(( rc == 0 )) && grep -q "started Lazy1 001" <<<"$out"'
check "start: registry entry has role, brief number, state running, a live pid" '[[ $(jget "$r" role) == Lazy1 && $(jget "$r" brief_n) == 001 && $(jget "$r" state) == running ]] && alive "$(jget "$r" pid)"'
check "start: registry carries model, effort, worktree, log, attempts" '[[ $(jget "$r" model) == haiku && $(jget "$r" effort) == low && $(jget "$r" worktree) == "$dir/ws" && $(jget "$r" attempts) == 1 && -n $(jget "$r" started) ]]'
check "start: the log is under status/helpers" '[[ $(jget "$r" log) == "$dir"/impl/status/helpers/Lazy1-001-*.log ]] && waitfor "grep -q \"FAKE claude\" \"$(jget "$r" log)\" 2>/dev/null" 10'
check "start: ack and run.lock name the helper" 'grep -q "session: Lazy1 \[headless\]" "$dir/impl/inbox/Lazy1/001.ack" && [[ $(cat "$dir/impl/inbox/Lazy1/run.lock") == $(jget "$r" pid) ]]'
check "start: claude -p with the roster profile" 'grep -q "^-p -n Lazy1 --model haiku --effort low --strict-mcp-config --permission-prompts none" "$CALLS"'
check "a fresh start is not told it is a resume" '! grep -q "previous run" "$CALLS"'
pid1=$(jget "$r" pid)

# 2. survive a simulated dispatcher restart: kill the dispatcher's whole process group
helper list
check "list shows the running helper" 'grep -q "Lazy1-001" <<<"$out" && grep -q running <<<"$out"'
check "start: a helper.ack and no helper.done while it runs" 'grep -q "helper Lazy1 001: durable helper Lazy1-001" "$dir/impl/inbox/Lazy1/001.helper.ack" && [[ ! -e $dir/impl/inbox/Lazy1/001.helper.done ]]'
rm -f "$hold"; helper wait --timeout $((30 * S))
check "end: helper.done ends with the exit sentinel" '[[ $(tail -1 "$dir/impl/inbox/Lazy1/001.helper.done") == "### EXIT=0 ###" ]]'
# the pair writer for any helper (a dispatcher subagent): ack, done, a refused non-numeric exit
helper ack Yudhi 363 "review helper" /x/agent-ab12.jsonl
check "ack: one line with what and transcript" '(( rc == 0 )) && [[ $(wc -l < "$dir/impl/inbox/Yudhi/363.helper.ack") -eq 1 ]] && grep -q "review helper, transcript: /x/agent-ab12.jsonl" "$dir/impl/inbox/Yudhi/363.helper.ack"'
helper "done" Yudhi 363 7 /x/agent-ab12.jsonl
check "done: last line is ### EXIT=7 ###" '(( rc == 0 )) && [[ $(tail -1 "$dir/impl/inbox/Yudhi/363.helper.done") == "### EXIT=7 ###" ]]'
helper "done" Yudhi 364 ok
check "done: a non-numeric exit is refused, no file" '(( rc == 2 )) && [[ ! -e $dir/impl/inbox/Yudhi/364.helper.done ]]'
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
set -m
"$SH" -c 'exec 2>/dev/null; "$1" start Lazy1; sleep 120' _ "$BIN/sabha-helper" >"$dir/disp.out" 2>&1 &
disp=$!
set +m
r=$(reg Lazy1-001)
waitfor '[[ $(jget "$r" state) == running ]]'
pid=$(jget "$r" pid); cpid=$(head -1 "$FAKE_PIDS" 2>/dev/null)
waitfor '[[ -s $FAKE_PIDS ]]' 10; cpid=$(head -1 "$FAKE_PIDS")
check "before the restart: dispatcher, supervisor and claude are alive" 'alive "$disp" && alive "$pid" && alive "$cpid"'
kill -TERM -- -"$disp" 2>/dev/null; kill -HUP -- -"$disp" 2>/dev/null; kill -KILL -- -"$disp" 2>/dev/null
waitfor '! alive "$disp"' 10
check "the dispatcher's group is gone" '! alive "$disp"'
sleep 1
check "after the restart: the helper's supervisor and claude still run" 'alive "$pid" && alive "$cpid"'
check "after the restart: the registry still says running" '[[ $(jget "$r" state) == running ]]'

# 3. a fresh dispatcher re-attaches: reports it, starts nothing
helper reattach
echo "--- sabha-helper reattach (rc $rc)"; echo "$out"
check "reattach: rc 0, names the running helper" '(( rc == 0 )) && grep -q "Lazy1-001" <<<"$out" && grep -q "running" <<<"$out"'
check "reattach starts nothing (still one claude call)" '[[ $(calls) == 1 ]]'
helper reattach --redispatch
check "reattach --redispatch leaves a live helper alone" '[[ $(calls) == 1 && $(jget "$r" attempts) == 1 ]]'
rm -f "$hold"
helper wait --timeout $((30 * S)) Lazy1-001
echo "--- sabha-helper wait (rc $rc)"; echo "$out"
check "wait: returns 0 once the done marker is there" '(( rc == 0 )) && [[ -e $dir/impl/inbox/Lazy1/001.done ]]'
check "after the run: state done, ended set, lock gone, pid not alive" '[[ $(jget "$r" state) == done && -n $(jget "$r" ended) && ! -e $dir/impl/inbox/Lazy1/run.lock ]] && waitfor "! alive $pid" 10'
helper reattach
check "reattach reports a finished helper and starts nothing" 'grep -q "done" <<<"$out" && [[ $(calls) == 1 ]]'

# 4. crash detection and re-dispatch (a kill -9 of the supervisor and claude: no done is ever written)
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1; r=$(reg Lazy1-001); pid=$(jget "$r" pid)
waitfor '[[ -s $FAKE_PIDS ]]' 10; cpid=$(head -1 "$FAKE_PIDS")
kill -KILL "$pid" "$cpid" 2>/dev/null
waitfor '! alive "$pid"' 10
helper reattach
echo "--- sabha-helper reattach after a crash (rc $rc)"; echo "$out"
check "crash: reattach reports the helper dead" 'grep -q "Lazy1-001" <<<"$out" && grep -q "dead" <<<"$out" && [[ $(jget "$r" state) == dead ]]'
check "crash: without --redispatch nothing is started" '[[ $(calls) == 1 && ! -e $dir/impl/inbox/Lazy1/001.done ]]'
rm -f "$hold"; : > "$FAKE_PIDS"
helper reattach --redispatch
echo "--- sabha-helper reattach --redispatch (rc $rc)"; echo "$out"
waitfor '[[ $(calls) == 2 ]]' 20
check "redispatch: started again, attempts 2, old ack kept aside" '(( rc == 0 )) && [[ $(calls) == 2 && $(jget "$r" attempts) == 2 ]] && ls "$dir"/impl/inbox/Lazy1/001.ack.dead-* >/dev/null 2>&1'
check "redispatch: the prompt says resume, never redo" 'tail -1 "$CALLS" | grep -q "previous run" && tail -1 "$CALLS" | grep -q "never redo"'
helper wait --timeout $((30 * S)) Lazy1-001
check "redispatch: the helper finishes, state done" '(( rc == 0 )) && [[ $(jget "$r" state) == done ]]'

# crash again past SABHA_HELPER_RETRIES: stays dead, BLOCKED done, for-me line
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1; r=$(reg Lazy1-001); pid=$(jget "$r" pid)
waitfor '[[ -s $FAKE_PIDS ]]' 10
kill -KILL "$pid" "$(head -1 "$FAKE_PIDS")" 2>/dev/null; waitfor '! alive "$pid"' 10
SABHA_HELPER_RETRIES=0 helper reattach --redispatch
check "retries exhausted: stays dead, BLOCKED done written, no new run" 'grep -q "dead" <<<"$out" && [[ $(calls) == 1 ]] && grep -q "result: BLOCKED" "$dir/impl/inbox/Lazy1/001.done" && grep -q "Lazy1-001" "$dir/impl/for-me.items"'
helper reattach
check "a dead helper with a BLOCKED done is reported blocked, not re-dispatched" 'grep -q "blocked" <<<"$out" && [[ $(calls) == 1 ]]'

# 5. no double start
reset; brief Lazy1 001; brief Lazy1 002; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1
waitfor '[[ $(calls) == 1 ]]' 20
helper start Lazy1
echo "--- second start (rc $rc)"; echo "$out"
check "a second start on a live helper is refused (rc 3) and says why" '(( rc == 3 )) && grep -q "already on Lazy1" <<<"$out"'
check "no second claude, no ack for 002" '[[ $(calls) == 1 && ! -e $dir/impl/inbox/Lazy1/002.ack ]]'
rm -f "$hold"; helper wait --timeout $((30 * S))

# 6. the existing lines hold: SABHA_STOP, the helper cap, the load, a live pane, an unreadable ps
reset; brief Lazy1 001
printf 'five_hour 95 %s %s\n' "$(( $(date +%s) + 3600 ))" "$(date +%s)" > "$dir/impl/status/limits.txt"
helper start Lazy1
check "SABHA_STOP: refused (rc 3), names the stop line, nothing written" '(( rc == 3 )) && grep -q SABHA_STOP <<<"$out" && [[ ! -e $dir/impl/inbox/Lazy1/001.ack && ! -e $(reg Lazy1-001) && $(calls) == 0 ]]'
rm -f "$dir/impl/status/limits.txt"

reset; brief Lazy1 001; brief Lazy2 001; : > "$hold"; export FAKE_HOLD=$hold
SABHA_HELPER_MAX=1 helper start Lazy1
waitfor '[[ $(calls) == 1 ]]' 20
SABHA_HELPER_MAX=1 helper start Lazy2
check "SABHA_HELPER_MAX: the second live helper is refused (rc 3), names the cap" '(( rc == 3 )) && grep -q "cap of 1" <<<"$out" && [[ $(calls) == 1 ]]'
rm -f "$hold"; "$SH" "$BIN/sabha-helper" wait --timeout $((30 * S)) >/dev/null 2>&1

reset; brief Lazy1 001
SABHA_LOADAVG=50.5 SABHA_HELPER_LOAD_MAX=10 helper start Lazy1
echo "--- load over the threshold (rc $rc)"; echo "$out"
check "load over the threshold: refused (rc 3), says both numbers, nothing written" '(( rc == 3 )) && grep -q "load 50.5" <<<"$out" && grep -q "10" <<<"$out" && [[ ! -e $dir/impl/inbox/Lazy1/001.ack && $(calls) == 0 ]]'
SABHA_LOADAVG=9.9 SABHA_HELPER_LOAD_MAX=10 helper start Lazy1
check "load under the threshold: started" '(( rc == 0 )) && grep -q "started Lazy1 001" <<<"$out"'
helper wait --timeout $((30 * S))
reset; brief Lazy1 001
SABHA_LOADAVG=500 SABHA_HELPER_LOAD_MAX=off helper start Lazy1
check "SABHA_HELPER_LOAD_MAX=off: any load starts" '(( rc == 0 )) && grep -q "started Lazy1 001" <<<"$out"'
helper wait --timeout $((30 * S))
reset; brief Lazy1 001
SABHA_LOADAVG=none SABHA_HELPER_LOAD_MAX=10 helper start Lazy1
check "load not readable: starts and says it was not measured" '(( rc == 0 )) && grep -q "not measured" <<<"$out" && grep -q "started Lazy1 001" <<<"$out"'
helper wait --timeout $((30 * S))

reset; brief Lazy1 001
echo "  101 ttys004  Tue Oct 13 09:00:01 2026     claude -n Lazy1 --model haiku You are Lazy1" > "$dir/ps.txt"
helper start Lazy1
check "a live claude -n Lazy1 holds the role: refused (rc 3), nothing written" '(( rc == 3 )) && grep -q "live claude -n Lazy1" <<<"$out" && [[ ! -e $dir/impl/inbox/Lazy1/001.ack && $(calls) == 0 ]]'
reset; brief Lazy1 001
export SABHA_PS_FILE=$dir/no-such-ps
helper start Lazy1
check "process list unreadable: warns, still starts" '(( rc == 0 )) && grep -q "process list" <<<"$out" && grep -q "started Lazy1 001" <<<"$out"'
helper wait --timeout $((30 * S))
export SABHA_PS_FILE=$dir/ps.txt

reset; brief Lazy1 001
SABHA_DETACH_TOOL=none helper start Lazy1
check "no setsid and no python3: refused, nothing written" '(( rc != 0 )) && grep -q "setsid" <<<"$out" && [[ ! -e $dir/impl/inbox/Lazy1/001.ack && ! -e $(reg Lazy1-001) ]]'

# a role copy (Karna-2) is its own helper with its own inbox, inside SABHA_MAX_COPIES
reset; brief Karna-2 313
helper start Karna-2
check "a copy Karna-2 starts as helper Karna-2-313 on the Karna profile" '(( rc == 0 )) && [[ $(jget "$(reg Karna-2-313)" model) == sonnet && $(jget "$(reg Karna-2-313)" role) == Karna-2 ]]'
helper wait --timeout $((30 * S))
reset; brief Karna-9 001
helper start Karna-9
check "a copy past SABHA_MAX_COPIES is refused" '(( rc != 0 )) && ! grep -q "started" <<<"$out"'
reset; brief Relay 001
helper start Relay
check "the relay is never a helper" '(( rc != 0 )) && grep -q "relay" <<<"$out" && [[ $(calls) == 0 ]]'

# 7. how a run ends: timeout, no done, cancel by hand
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
SABHA_RUN_TIMEOUT=2 helper start Lazy1
helper wait --timeout $((30 * S))
check "timeout: state timeout, a BLOCKED done from the runner" '[[ $(jget "$(reg Lazy1-001)" state) == timeout ]] && grep -q "result: BLOCKED" "$dir/impl/inbox/Lazy1/001.done"'
reset; export FAKE_DONE=0; brief Lazy1 001
helper start Lazy1; helper wait --timeout $((30 * S))
check "claude exits with no done: state blocked" '[[ $(jget "$(reg Lazy1-001)" state) == blocked ]] && grep -q "ended without a done" "$dir/impl/inbox/Lazy1/001.done"'
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1; r=$(reg Lazy1-001)
waitfor '[[ -s $FAKE_PIDS ]]' 10; cpid=$(head -1 "$FAKE_PIDS")
: > "$dir/impl/inbox/Lazy1/001.cancel"
helper wait --timeout $((30 * S))
check "a .cancel written by hand: state cancelled, claude gone" '[[ $(jget "$r" state) == cancelled ]] && waitfor "! alive $cpid" 10'

# 8. sabha-helper stop, then sabha-down.sh cleanup
reset; brief Lazy1 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1; r=$(reg Lazy1-001); pid=$(jget "$r" pid)
waitfor '[[ -s $FAKE_PIDS ]]' 10; cpid=$(head -1 "$FAKE_PIDS")
helper stop Lazy1-001 --reason test --timeout $((20 * S))
echo "--- sabha-helper stop (rc $rc)"; echo "$out"
check "stop: rc 0, state stopped with the reason, claude and supervisor gone" '(( rc == 0 )) && [[ $(jget "$r" state) == stopped && $(jget "$r" stop_reason) == test ]] && ! alive "$cpid" && waitfor "! alive $pid" 10'
check "stop: a CANCELLED done, no lock" 'grep -q "result: CANCELLED" "$dir/impl/inbox/Lazy1/001.done" && [[ ! -e $dir/impl/inbox/Lazy1/run.lock ]]'
helper reattach --redispatch
check "a stopped helper is not re-dispatched" 'grep -q "stopped" <<<"$out" && [[ $(calls) == 1 ]]'

reset; brief Lazy1 001; brief Karna 001; : > "$hold"; export FAKE_HOLD=$hold
helper start Lazy1; helper start Karna
waitfor '[[ $(wc -l < "$FAKE_PIDS") -ge 2 ]]' 10
out=$("$SH" "$BIN/sabha-down.sh" 2>&1); rc=$?
echo "--- sabha-down.sh dry run (rc $rc)"; echo "$out"
check "sabha-down dry run: lists the helpers it would stop and stops none" 'grep -q "would stop 2 helper" <<<"$out" && grep -q "Lazy1-001" <<<"$out" && [[ $(jget "$(reg Lazy1-001)" state) == running && $(jget "$(reg Karna-001)" state) == running ]]'
out=$(env -u CLAUDECODE SABHA_KILL="$dir/stubs/fakekill" "$SH" "$BIN/sabha-down.sh" --yes --timeout $((5 * S)) 2>&1); rc=$?
echo "--- sabha-down.sh --yes (rc $rc)"; echo "$out"
check "sabha-down --yes: both helpers stopped, reason sabha-down, recorded" '[[ $(jget "$(reg Lazy1-001)" state) == stopped && $(jget "$(reg Lazy1-001)" stop_reason) == sabha-down && $(jget "$(reg Karna-001)" state) == stopped ]]'
check "sabha-down --yes: no run.lock left, claude processes gone" '[[ ! -e $dir/impl/inbox/Lazy1/run.lock && ! -e $dir/impl/inbox/Karna/run.lock ]] && ! alive "$(head -1 "$FAKE_PIDS")" && ! alive "$(sed -n 2p "$FAKE_PIDS")"'
helper reattach --redispatch
check "after down, a fresh dispatcher does not restart stopped helpers" '[[ $(calls) == 2 ]]'

# the plain runner is untouched: without --detach no registry is written
reset; brief Lazy1 001
"$SH" "$BIN/sabha-run" --wait Lazy1 >/dev/null 2>&1
check "sabha-run without --detach writes no registry entry" '[[ ! -e $(reg Lazy1-001) && -e $dir/impl/inbox/Lazy1/001.done ]]'

echo
if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "all checks passed"
