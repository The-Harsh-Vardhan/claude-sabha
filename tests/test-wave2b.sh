#!/usr/bin/env bash
# Three stress-test fixes, hermetic, fake claude: SABHA_STOP holds sabha-run and sabha-up.sh; a .cancel stops a headless
# run; briefs numbered 1000 and up are found by sabha-brief, sabha-run, sabha-watch and the hooks. Run: tests/test-wave2b.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-w2b.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
cat >"$dir/sabha.conf" <<C
SABHA_WS=$dir/ws
SABHA_IMPL=$dir/impl
SABHA_PROJECT=Test
SABHA_ROSTER="Relay:opus:medium Dispatcher:opus:medium Worker:sonnet:medium:lazy"
C
# fake claude: logs its argv; FAKE_HOLD keeps it running while that file exists; a grandchild whose pid goes to FAKE_GC
cat >"$dir/stubs/claude" <<'S'
#!/bin/sh
echo "$*" >>"$CALLS"
[ -n "$FAKE_GC" ] && { sleep 60 & echo $! >"$FAKE_GC"; }
if [ -n "$FAKE_HOLD" ]; then i=0; while [ -e "$FAKE_HOLD" ] && [ $i -lt 240 ]; do sleep 0.5; i=$((i+1)); done; fi
exit 0
S
chmod +x "$dir/stubs/claude"
: >"$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH CALLS=$dir/calls SABHA_NOTIFY_DESKTOP=0
export SABHA_IMPL=$dir/impl SABHA_LIMITS_FILE=$dir/limits.txt FAKE_HOLD="" FAKE_GC=""
fail() { echo "FAIL: $*"; exit 1; }
inbox=$dir/impl/inbox/Worker; mkdir -p "$inbox"
wait_for() { local i; for (( i = 0; i < ${3:-100}; i++ )); do eval "$1" && return 0; sleep 0.1; done; fail "$2"; }

# b. SABHA_STOP: a window at 95% with its reset ahead starts nothing in sabha-run and sabha-up.sh
now=$(date +%s)
printf 'five_hour 95 %s %s\n' $(( now + 3600 )) "$now" >"$SABHA_LIMITS_FILE"
printf 'to: Worker\n' >"$inbox/001-d-t.md"; : >"$CALLS"
out=$(bash "$BIN/sabha-run" Worker 2>&1)
[[ $out == *SABHA_STOP* && ! -e $inbox/001.ack && ! -s $CALLS ]] || fail "sabha-run must start nothing at the stop line: $out"
out=$(bash "$BIN/sabha-up.sh" Worker 2>&1); rc=$?
[[ $rc -eq 3 && $out == *SABHA_STOP* && ! -s $CALLS ]] || fail "sabha-up.sh must start nothing at the stop line (rc $rc): $out"
printf 'five_hour 40 %s %s\n' $(( now + 3600 )) "$now" >"$SABHA_LIMITS_FILE"
bash "$BIN/sabha-up.sh" Worker >/dev/null 2>&1 || fail "sabha-up.sh must start below the stop line"
grep -q -- '-n Worker' "$CALLS" || fail "below the stop line sabha-up.sh did not start claude: $(cat "$CALLS")"
rm -f "$SABHA_LIMITS_FILE" "$inbox"/*; : >"$CALLS"

# c. a .cancel written while a headless run is on stops it, with a CANCELLED done and no leftover tool process
export FAKE_HOLD=$dir/hold FAKE_GC=$dir/gc; : >"$FAKE_HOLD"
printf 'to: Worker\n' >"$inbox/001-d-t.md"
bash "$BIN/sabha-run" Worker >/dev/null 2>&1
wait_for '[[ -s $dir/gc ]]' "the fake run did not start"
: >"$inbox/001.cancel"
wait_for '[[ -e $inbox/001.done && ! -e $inbox/run.lock ]]' "a cancelled run did not stop" 150
grep -q '^result: CANCELLED' "$inbox/001.done" || fail "a cancelled run must write result: CANCELLED: $(cat "$inbox/001.done")"
kill -0 "$(cat "$dir/gc")" 2>/dev/null && { kill "$(cat "$dir/gc")" 2>/dev/null; fail "the tool process outlived a cancelled run"; }
rm -f "$FAKE_HOLD"; export FAKE_HOLD="" FAKE_GC=""; rm -f "$inbox"/*; : >"$CALLS"

# d. numbers past 999: sabha-brief continues at 1000 without a gap, and every reader sees a four-digit brief
: >"$inbox/999.claim"; printf 'to: Worker\n' >"$inbox/999-d-t.md"; : >"$inbox/999.ack"; : >"$inbox/999.done"
export SABHA_IMPL=$dir/impl
a=$("$BIN/sabha-brief" Worker d first "task" </dev/null); b=$("$BIN/sabha-brief" Worker d second "task" </dev/null)
[[ ${a##*/} == 1000-d-first.md && ${b##*/} == 1001-d-second.md ]] || fail "briefs past 999 must number 1000, 1001: $a $b"
[[ -e $inbox/1000.claim && -e $inbox/1001.claim && ! -e $inbox/1002.claim ]] || fail "claims must be 1000 and 1001 only: $(ls "$inbox")"
out=$(bash "$BIN/sabha-run" --print Worker 2>&1)
[[ $out == *"inbox/Worker/1000-d-first.md"* ]] || fail "sabha-run must see brief 1000: $out"
touch -t 202001010000 "$inbox/1000-d-first.md" "$inbox/1001-d-second.md"
out=$(bash "$BIN/sabha-watch" 2>&1)
[[ $out == *"unacked briefs:"*"inbox/Worker/1000"* ]] || fail "sabha-watch must list brief 1000 as unacked: $out"
out=$(HK_IMPL=$dir/impl HK_ROLE=Worker bash -c '. "$1/hooks/lib.sh"; hk_open_briefs all' _ "$ROOT")
[[ $out == *1000-d-first.md* ]] || fail "hooks must list brief 1000 as open: $out"

echo "ok: SABHA_STOP holds sabha-run and sabha-up.sh, a .cancel stops a headless run (CANCELLED, no orphan), briefs 1000+ are numbered and seen everywhere"
