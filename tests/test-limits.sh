#!/usr/bin/env bash
# bin/sabha-limits.sh against fake files: a reading is recorded newest-wins, each SABHA_NOTIFY step fires once per
# window reset and again after the reset, SABHA_STOP holds only while the reset is ahead. No notification is sent
# (SABHA_NOTIFY_DESKTOP=0), no Claude runs. Run: tests/test-limits.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-limits.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
export SABHA_IMPL=$dir SABHA_NOTIFY_DESKTOP=0 SABHA_PUSH=off
# shellcheck source=../bin/sabha-limits.sh
. "$BIN/sabha-limits.sh"
fail() { echo "FAIL: $*"; exit 1; }
now=$(date +%s); reset=$(( now + 3600 ))

sabha_limits_write five_hour 23.5 "$reset"
sabha_limits_write seven_day 41 "$reset"
sabha_limits_write five_hour 24 "$reset"
[[ $(wc -l <"$dir/status/limits.txt") -eq 2 ]] || fail "limits.txt should hold one line per window"
read -r pct r _ <<<"$(sabha_limits_read five_hour)"
[[ $pct == 24 && $r == "$reset" ]] || fail "newest five_hour reading should win, got $pct $r"

export SABHA_NOTIFY="10 20 30 40"
sabha_limits_alert
log=$dir/status/alerts.log
[[ $(wc -l <"$log") -eq 6 ]] || fail "24% and 41% cross 2 + 4 steps, got $(wc -l <"$log") alerts"
grep -q 'five-hour usage 24% (crossed 20%)' "$log" || fail "five-hour 20% alert missing"
sabha_limits_alert
[[ $(wc -l <"$log") -eq 6 ]] || fail "a second pass must fire nothing"
sabha_limits_write five_hour 35 "$reset"; sabha_limits_alert
[[ $(wc -l <"$log") -eq 7 ]] || fail "35% should add only the 30% step"
sabha_limits_write five_hour 12 $(( reset + 18000 )); sabha_limits_alert
[[ $(wc -l <"$log") -eq 8 ]] || fail "a new window should fire its 10% step again"

sabha_limits_stopped && fail "35%/41% must not stop"
sabha_limits_write seven_day 90 "$reset"
why=$(sabha_limits_stopped) || fail "90% with the reset ahead must stop"
[[ $why == *seven-day* ]] || fail "stop reason should name the window: $why"
SABHA_STOP=95 sabha_limits_stopped && fail "SABHA_STOP=95 must not stop at 90%"
SABHA_STOP=off sabha_limits_stopped && fail "SABHA_STOP=off must never stop"
sabha_limits_write seven_day 90 $(( now - 1 ))
sabha_limits_stopped && fail "a passed reset must not stop"
sabha_limits_banner | grep -q '^limits: five-hour 12%' || fail "banner should print the readings"

# a message with quotes, a backslash and AppleScript-looking text reaches osascript as one argv item, never as source
if [[ $(uname -s) == Darwin ]]; then
  mkdir -p "$dir/fakebin"
  printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done >"$FAKE_OSA_OUT"\n' >"$dir/fakebin/osascript"
  chmod +x "$dir/fakebin/osascript"
  PATH="$dir/fakebin:$PATH" FAKE_OSA_OUT="$dir/osa.out" SABHA_NOTIFY_DESKTOP=1 sabha_notify 'say "hi" \ & do shell script "id"'
  grep -qxF 'say "hi" \ & do shell script "id"' "$dir/osa.out" || fail "message must arrive verbatim as one argument"
  grep -qF 'display notification (item 1 of argv)' "$dir/osa.out" || fail "script source must not embed the message"
fi
echo "ok: newest reading wins, 8 alerts once each across a reset, SABHA_STOP holds only until resets_at"
