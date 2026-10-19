#!/usr/bin/env bash
# SABHA_KEEP_AWAKE off|open|lid with fake caffeinate, pgrep and pmset first on PATH: off starts nothing; open starts one
# `caffeinate -dis -w <server pid>` and a second call reuses it; lid adds the sudo hint until SleepDisabled is 1; a bad
# value is refused; sabha doctor reports the state. No real caffeinate, pmset or herdr. Run: tests/test-keep-awake.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-keepawake.XXXXXX") || exit 1
trap 'kill $(cat "$dir"/impl/status/keep-awake.pid 2>/dev/null) 2>/dev/null; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$dir/fb" "$dir/impl/status"
printf '#!/bin/sh\necho "$@" >>"%s/caff.log"\nexec sleep 30\n' "$dir" >"$dir/fb/caffeinate"
printf '#!/bin/sh\necho 4242\n' >"$dir/fb/pgrep"
printf '#!/bin/sh\n[ "$2" = ps ] && { echo "Now drawing from '"'"'${FAKE_PS:-AC Power}'"'"'"; exit 0; }\n[ "$1" = -g ] && [ -z "$2" ] && echo " SleepDisabled\t\t%s"\n[ "$2" = assertions ] && echo "   pid 1(caffeinate): [0x1] PreventUserIdleSystemSleep"\nexit 0\n' "\${FAKE_SD:-0}" >"$dir/fb/pmset"
printf '#!/bin/sh\necho "${FAKE_PSCMD:-caffeinate -dis -w 4242}"\n' >"$dir/fb/ps"
chmod +x "$dir/fb"/*
PATH="$dir/fb:$PATH"
echo "SABHA_WS=$dir
SABHA_IMPL=$dir/impl" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_IMPL=$dir/impl SABHA_KEEP_AWAKE_FAKES=1
. "$ROOT/bin/sabha-lib.sh"; . "$ROOT/bin/sabha-herdr.sh"
n() { [[ -f $dir/caff.log ]] && wc -l <"$dir/caff.log" | tr -d ' ' || echo 0; }

SABHA_KEEP_AWAKE=off sabha_keep_awake; sleep 1
[[ $(n) == 0 ]] || fail "off must start no caffeinate"
echo "ok: off starts nothing"

SABHA_KEEP_AWAKE=open sabha_keep_awake >/dev/null; sleep 1
[[ $(n) == 1 ]] && grep -q -- '^-dis -w 4242$' "$dir/caff.log" || fail "open: want one 'caffeinate -dis -w 4242', got: $(cat "$dir/caff.log" 2>/dev/null)"
SABHA_KEEP_AWAKE=open sabha_keep_awake >/dev/null; sleep 1
[[ $(n) == 1 ]] || fail "open twice must not start a second caffeinate"
echo "ok: open starts one caffeinate -dis -w <pid>, reused on the second call"

kill "$(cat "$dir/impl/status/keep-awake.pid")"; rm -f "$dir/caff.log" "$dir/impl/status/keep-awake.pid"
o=$(SABHA_KEEP_AWAKE=lid FAKE_SD=0 sabha_keep_awake 2>&1); sleep 1
[[ $(n) == 1 ]] && echo "$o" | grep -q 'sudo pmset -a disablesleep 1' || fail "lid with SleepDisabled 0: want caffeinate and the sudo hint: $o"
o=$(SABHA_KEEP_AWAKE=lid FAKE_SD=1 sabha_keep_awake 2>&1)
echo "$o" | grep -q 'sudo' && fail "lid with SleepDisabled 1 must not nag: $o"
echo "ok: lid starts caffeinate and warns until SleepDisabled is 1"

o=$(SABHA_KEEP_AWAKE=bogus sabha_keep_awake 2>&1); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q 'not auto, off, open or lid' || fail "bad value must be refused: rc=$rc $o"
echo "ok: a bad value is refused"

rm -f "$dir/caff.log" "$dir/impl/status/keep-awake."*
mode() { SABHA_KEEP_AWAKE=${1:-auto} SABHA_KEEP_AWAKE_AC=${2:-} SABHA_KEEP_AWAKE_BATTERY=${3:-} FAKE_PS=$4 sabha_keep_awake_mode; }
[[ $(mode auto "" "" "AC Power") == lid ]] || fail "auto on AC must be lid"
[[ $(mode auto "" "" "Battery Power") == open ]] || fail "auto on battery must be open"
[[ $(mode "" "" "" "Battery Power") == open ]] || fail "default (auto) on battery must be open"
[[ $(mode auto open "" "AC Power") == open ]] || fail "AC override must apply"
[[ $(mode auto "" off "Battery Power") == off ]] || fail "battery override must apply"
[[ $(mode lid "" off "Battery Power") == lid ]] || fail "an explicit mode beats the per-source pair"
echo "ok: auto picks lid on AC and open on battery; overrides apply; explicit wins"

# live switch: the same sabha_keep_awake sees the source change; a battery override of off ends the caffeinate
echo "SABHA_KEEP_AWAKE_BATTERY=off" >>"$dir/sabha.conf"
o=$(FAKE_PS="AC Power" FAKE_SD=0 sabha_keep_awake 2>&1); sleep 1
[[ $(n) == 1 ]] && echo "$o" | grep -q 'sudo pmset' || fail "AC: want caffeinate and the lid hint: $o"
pid=$(cat "$dir/impl/status/keep-awake.pid")
FAKE_PS="Battery Power" sabha_keep_awake >/dev/null 2>&1
kill -0 "$pid" 2>/dev/null && fail "battery with override off must end the caffeinate"
[[ ! -f $dir/impl/status/keep-awake.pid ]] || fail "pid file must go"
FAKE_PS="AC Power" FAKE_SD=1 sabha_keep_awake >/dev/null 2>&1; sleep 1
[[ $(n) == 2 ]] || fail "back on AC must start caffeinate again"
echo "ok: live switch AC -> battery -> AC"

K() { "${BASH:-bash}" "$ROOT/bin/sabha" keep-awake "$@" 2>&1; }
K open | grep -q 'SABHA_KEEP_AWAKE=open' && grep -q '^SABHA_KEEP_AWAKE=open$' "$dir/sabha.conf" || fail "keep-awake open must write the conf"
[[ $(K) == SABHA_KEEP_AWAKE=open ]] || fail "keep-awake with no mode must print it"
K lid | grep -q 'sudo pmset' || fail "keep-awake lid must show the sudo hint"
K bogus | grep -q 'use auto, off, open or lid' || fail "keep-awake must refuse a bad mode"
echo "ok: sabha keep-awake sets and shows the mode"

D() { FAKE_PS="AC Power" FAKE_SD=${1:-0} "${BASH:-bash}" "$ROOT/bin/sabha" doctor 2>&1; }
K auto >/dev/null
D 1 | grep -q 'keep awake: auto -> lid on ac power (disablesleep 1' || fail "doctor auto on AC, SleepDisabled 1: $(D 1 | grep keep)"
D 0 | grep -q 'keep awake: auto -> lid on ac power, but SleepDisabled is 0' || fail "doctor must warn: $(D 0 | grep keep)"
K off >/dev/null
D 0 | grep -q 'keep awake: off -> off on ac power' || fail "doctor off: $(D 0 | grep keep)"
echo "ok: doctor reports the state"
unset SABHA_KEEP_AWAKE SABHA_KEEP_AWAKE_AC SABHA_KEEP_AWAKE_BATTERY
# F1: a pid file naming an unrelated process is never killed and never counts as our caffeinate
sed -i.bak '/^SABHA_KEEP_AWAKE/d' "$dir/sabha.conf"; rm -f "$dir/sabha.conf.bak" "$dir/caff.log" "$dir/impl/status/keep-awake."*
sleep 300 & other=$!
echo "$other" >"$dir/impl/status/keep-awake.pid"
FAKE_PSCMD="sleep 300" SABHA_KEEP_AWAKE=off sabha_keep_awake
kill -0 "$other" 2>/dev/null || fail "off killed an unrelated process (reused pid)"
[[ ! -f $dir/impl/status/keep-awake.pid ]] || fail "off must drop a pid file that is not ours"
echo "$other" >"$dir/impl/status/keep-awake.pid"
FAKE_PSCMD="sleep 300" SABHA_KEEP_AWAKE=open sabha_keep_awake >/dev/null; sleep 1
[[ $(n) == 1 && $(cat "$dir/impl/status/keep-awake.pid") != "$other" ]] || fail "open must start its own caffeinate when the pid is reused"
kill "$other" 2>/dev/null
kill "$(cat "$dir/impl/status/keep-awake.pid")" 2>/dev/null
echo "ok: F1 a reused pid is neither killed nor reused"

# F2: 8 loops polling together start one caffeinate; a dead holder's lock is taken over
rm -f "$dir/caff.log" "$dir/impl/status/keep-awake.pid"
for i in 1 2 3 4 5 6 7 8; do SABHA_KEEP_AWAKE=open sabha_keep_awake >/dev/null 2>&1 & done; wait; sleep 1
[[ $(n) == 1 ]] || fail "8 parallel calls started $(n) caffeinates"
kill "$(cat "$dir/impl/status/keep-awake.pid")"; rm -f "$dir/caff.log" "$dir/impl/status/keep-awake.pid"
# F4: a dead holder's old-style lock dir must not let parallel calls double up; repeated rounds catch the race
for r in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  rm -rf "$dir/caff.log" "$dir/impl/status/keep-awake.pid" "$dir/impl/status/keep-awake.lock"
  mkdir "$dir/impl/status/keep-awake.lock"; sh -c 'echo $$' >"$dir/impl/status/keep-awake.lock/pid"
  for i in 1 2 3 4 5 6 7 8; do SABHA_KEEP_AWAKE=open sabha_keep_awake >/dev/null 2>&1 & done; wait; sleep 0.3
  [[ $(n) == 1 ]] || fail "F4 round $r: stale lock + 8 parallel calls started $(n) caffeinates"
  kill "$(cat "$dir/impl/status/keep-awake.pid")" 2>/dev/null
done
rm -rf "$dir/impl/status/keep-awake.lock"
echo "ok: F2 parallel calls start one caffeinate; stale lock recovered"

# F3: SleepDisabled 1 outside lid mode is a doctor warning with the undo line, said once by the loop, never run
rm -f "$dir/impl/status/keep-awake."*
o=$(FAKE_PS="Battery Power" FAKE_SD=1 "${BASH:-bash}" "$ROOT/bin/sabha" doctor 2>&1 | grep 'keep awake')
case $o in warn*"auto -> open on battery power, but SleepDisabled is 1"*"sudo pmset -a disablesleep 0"*) ;; *) fail "doctor must warn on battery with SleepDisabled 1: $o" ;; esac
o=$(FAKE_PS="Battery Power" FAKE_SD=1 SABHA_KEEP_AWAKE=auto sabha_keep_awake 2>&1 >/dev/null)
echo "$o" | grep -q 'sudo pmset -a disablesleep 0' || fail "loop must say the undo line: $o"
o=$(FAKE_PS="Battery Power" FAKE_SD=1 SABHA_KEEP_AWAKE=auto sabha_keep_awake 2>&1 >/dev/null)
[[ -z $o ]] || fail "the SleepDisabled warning must be said once: $o"

kill "$(cat "$dir/impl/status/keep-awake.pid")" 2>/dev/null
echo "ok: F3 SleepDisabled 1 on battery warns with the undo line"

# F5: the loop's poll call (stdout dropped, stderr to a log) must show the warning
rm -f "$dir/impl/status/keep-awake."* "$dir/poll.log"
FAKE_PS="Battery Power" FAKE_SD=1 SABHA_KEEP_AWAKE=auto sabha_keep_awake >/dev/null 2>>"$dir/poll.log"
grep -q 'sudo pmset -a disablesleep 0' "$dir/poll.log" || fail "F5 the poll call must keep the warning: $(cat "$dir/poll.log")"
grep -qF 'sabha_keep_awake >/dev/null 2>>"$LOOP/$lower.log"' "$ROOT/bin/sabha-loop" || fail "F5 sabha-loop must send the poll's stderr to its log"
kill "$(cat "$dir/impl/status/keep-awake.pid")" 2>/dev/null
echo "ok: F5 the poll call keeps the SleepDisabled warning"
echo "keep-awake: all ok"
