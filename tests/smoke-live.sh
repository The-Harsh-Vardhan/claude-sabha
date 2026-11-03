#!/usr/bin/env bash
# Live smoke test for bin/sabha-loop: manual and opt-in (not test-*.sh, so the suite never runs it). The hermetic tests
# run with no tty, a fake herdr and a 1 s interval, which is where the launch bugs of 2.0.0 hid (#5 uptime measured after
# a sleep, #8 Bun's kqueue rejecting a reopened /dev/tty). This runs the loop the way a grid pane does: inside a real
# pty, SABHA_LOOP_CMD=claude with no opening prompt (plain interactive claude, it spends no tokens), the default
# interval, a temp SABHA_IMPL. It passes when, after SMOKE_SECONDS (30), the log has no "crash:" or "launch failed"
# line and the claude child is still alive. Needs `claude` on PATH. Never touches herdr (the fake one is first on PATH).
# Run: tests/smoke-live.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
BIN=$(cd "$here/../bin" && pwd)
secs=${SMOKE_SECONDS:-30}
command -v claude >/dev/null || { echo "smoke-live: claude is not on PATH"; exit 2; }
command -v script >/dev/null || { echo "smoke-live: script(1) is not installed"; exit 2; }
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-smoke-live.XXXXXX") || exit 2
spid=""
kids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; kids "$c"; done; }
cleanup() {
  bash "$BIN/sabha-loop" --stop Smoke >/dev/null 2>&1
  [[ -n $spid ]] && { kids "$spid" | xargs kill -TERM 2>/dev/null; kill -TERM "$spid" 2>/dev/null; wait "$spid" 2>/dev/null; }
  rm -rf "$dir"
}
trap cleanup EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:claude:sonnet Smoke:claude:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
mkdir -p "$dir/status" "$dir/inbox/Smoke"
log=$dir/status/loop/smoke.log
fail() { echo "FAIL: $*"; [[ -f $log ]] && sed 's/^/  log: /' "$log"; exit 1; }

# the interval is left at its default on purpose; the one forced variable is the agent command
cd "$dir" || exit 2
env -u SABHA_PLAN -u SABHA_LOOP_INTERVAL -u SABHA_LOOP_MIN_UP -u SABHA_ROLE \
  PATH="$here/hermetic-bin:$PATH" SABHA_HERDR_BIN="$here/hermetic-bin/herdr" SABHA_TEST=1 \
  SABHA_CONF="$dir/sabha.conf" SABHA_LOOP_CMD=claude SABHA_NOTIFY_DESKTOP=0 \
  script -q /dev/null bash "$BIN/sabha-loop" Smoke >"$dir/pty.out" 2>&1 </dev/null &
spid=$!

for (( i = 0; i < secs; i++ )); do
  kill -0 "$spid" 2>/dev/null || break
  sleep 1
done
kill -0 "$spid" 2>/dev/null || fail "the loop is gone after $i s (see pty.out: $(tail -c 300 "$dir/pty.out" 2>/dev/null | tr -d '\r'))"
grep -Eq 'crash:|launch failed|stopped:' "$log" 2>/dev/null && fail "the loop logged a failed launch"
grep -q ' start (' "$log" 2>/dev/null || fail "the loop never logged a start"
loop=$(pgrep -P "$spid" | head -1)
[[ -n $loop ]] && [[ -n $(pgrep -P "$loop") ]] || fail "no claude child is alive under the loop after $secs s"
echo "ok: sabha-loop kept claude alive for ${secs}s in a real pty, no crash or launch failure logged"
