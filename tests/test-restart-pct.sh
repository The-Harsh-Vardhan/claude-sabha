#!/usr/bin/env bash
# The restart and warn thresholds (sabha_restart_levels in sabha-lib.sh): valid, missing, out of range (1-95), per role,
# warn default restart - 5, warn at or above restart ignored, the older SABHA_LOOP_LIMIT, the relay's token fallback; and
# sabha-loop logging the warning at the configured percent. The agent is a fake; no pane. Run: tests/test-restart-pct.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-pct.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
lp=""
trap '[[ -n $lp ]] && kill -TERM "$lp" 2>/dev/null; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1: ${out:-}"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status/context" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Builder:opus"\n' "$dir/ws" "$dir/impl" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
# lv <Name> [VAR=value ...]: "restart warn" (stdout) and the notices (stderr, after "|")
lv() { local n=$1; shift; env "$@" "$SH" -c '. "$1/sabha-lib.sh"; sabha_load t; shift; sabha_restart_levels "$1"' _ "$BIN" "$n" 2>&1 | tr '\n' '|'; }

out=$(lv Builder);                                      check "missing: 30 and 25" '[[ $out == "30 25|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=40);                 check "valid 40: warn defaults to 35" '[[ $out == "40 35|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=35 SABHA_WARN_PCT=20); check "valid warn 20 under restart 35" '[[ $out == "35 20|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=1);                  check "lower edge 1 is valid: warn 0 (warns at once)" '[[ $out == "1 0|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=95);                 check "upper edge 95: warn 90" '[[ $out == "95 90|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=0);                  check "0 is out of range: named, default 30" '[[ $out == "sabha: SABHA_RESTART_PCT=0 is not a whole percent from 1 to 95; ignored|30 25|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=96);                 check "96 is out of range: named, default 30" 'grep -q "SABHA_RESTART_PCT=96 is not a whole percent" <<<"$out" && grep -q "30 25|$" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=abc);                check "text is refused: default 30" 'grep -q "30 25|$" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=-5);                 check "negative is refused: default 30" 'grep -q "30 25|$" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=30.5);               check "a fraction is refused: default 30" 'grep -q "30 25|$" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=040);                check "leading zero reads as decimal 40" '[[ $out == "40 35|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=40 SABHA_WARN_PCT=40); check "warn at restart is refused: restart - 5" 'grep -q "40 35|$" <<<"$out" && grep -q "SABHA_WARN_PCT=40 is not" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=40 SABHA_WARN_PCT=99); check "warn out of range is refused: restart - 5" 'grep -q "40 35|$" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT=3);                  check "restart 3: warn stays above 0 and below restart" '[[ $out == "3 1|" ]]'
out=$(lv Builder SABHA_RESTART_PCT=30 SABHA_RESTART_PCT_Builder=45); check "per-role override beats the global" '[[ $out == "45 40|" ]]'
out=$(lv Dispatcher SABHA_RESTART_PCT=30 SABHA_RESTART_PCT_Builder=45); check "another role keeps the global" '[[ $out == "30 25|" ]]'
out=$(lv Builder-2 SABHA_RESTART_PCT_Builder=45);       check "a copy Builder-2 takes Builder's override" '[[ $out == "45 40|" ]]'
out=$(lv Builder SABHA_RESTART_PCT_Builder=200 SABHA_RESTART_PCT=33); check "a bad per-role value falls through to the global" 'grep -q "33 28|$" <<<"$out" && grep -q "SABHA_RESTART_PCT_Builder=200" <<<"$out"'
out=$(lv Builder SABHA_RESTART_PCT_Builder=45 SABHA_WARN_PCT_Builder=10); check "per-role warn" '[[ $out == "45 10|" ]]'
out=$(lv Builder SABHA_LOOP_LIMIT=35);                  check "the older SABHA_LOOP_LIMIT still sets the restart point" '[[ $out == "35 30|" ]]'
out=$(lv Builder SABHA_LOOP_LIMIT=35 SABHA_RESTART_PCT=50); check "SABHA_RESTART_PCT wins over SABHA_LOOP_LIMIT" '[[ $out == "50 45|" ]]'
out=$(lv Relay SABHA_RELAY_STOP_K=400 SABHA_RELAY_WARN_K=350); check "relay token fallback (window 1000k): 40 and 35" '[[ $out == "40 35|" ]]'
out=$(lv Relay SABHA_RELAY_STOP_K=300 SABHA_RELAY_WINDOW_K=200); check "relay tokens of a 200k window = 150%: out of range, default 30" '[[ $out == "30 25|" ]]'
out=$(lv Relay SABHA_RELAY_STOP_K=400 SABHA_RESTART_PCT=35); check "a percent knob beats the token fallback" '[[ $out == "35 30|" ]]'
out=$(lv Builder SABHA_RELAY_STOP_K=400);               check "the token fallback is the relay's only" '[[ $out == "30 25|" ]]'

echo "--- sabha-loop uses it"
W=${SABHA_TEST_WAIT:-60}
wait_for() { local i; for (( i = 0; i < $3; i++ )); do grep -Eq "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }
echo 27 > "$dir/impl/status/context/builder.txt"
SABHA_RESTART_PCT=40 SABHA_WARN_PCT=25 SABHA_LOOP_INTERVAL=1 SABHA_LOOP_MIN_UP=3 SABHA_NOTIFY_DESKTOP=0 \
  SABHA_LOOP_CMD='trap "exit 0" INT TERM; sleep 60 & wait' "$SH" "$BIN/sabha-loop" Builder 2>/dev/null &
lp=$!
wait_for "$dir/impl/status/loop/builder.log" 'context warning: 27%' "$W"
out=$(cat "$dir/impl/status/loop/builder.log" 2>/dev/null)
check "27% with warn 25: the warning names 27% and the restart point 40%" 'grep -q "context warning: 27%; restart at 40%" <<<"$out"'
check "27% is under restart 40: no restart" '! grep -q " restart: " <<<"$out"'
sleep 1
echo 41 > "$dir/impl/status/context/builder.txt"; echo "handoff" > "$dir/impl/status/builder.md"
wait_for "$dir/impl/status/loop/builder.log" 'restart: context 41%' "$W"
out=$(cat "$dir/impl/status/loop/builder.log" 2>/dev/null)
check "41% with restart 40 and a newer handoff: restart logged" 'grep -q "restart: context 41% and a newer handoff" <<<"$out"'
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
