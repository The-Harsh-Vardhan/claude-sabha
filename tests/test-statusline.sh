#!/usr/bin/env bash
# bin/statusline-sabha.sh fed a fake statusLine JSON: prints the line with the usage windows, writes the context
# percent to status/context/<name>.txt and the windows to status/limits.txt, and fires the alerts once.
# Needs jq. Run: tests/test-statusline.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-sl.XXXXXX") || exit 1
trap 'rm -rf "$dir"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_NOTIFY_DESKTOP=0\nSABHA_NOTIFY="20 50"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
fail() { echo "FAIL: $*"; exit 1; }
reset=$(( $(date +%s) + 600 ))

json() { printf '{"session_name":"Arjun","model":{"display_name":"Opus"},"context_window":{"used_percentage":%s},"cwd":"%s","rate_limits":{"five_hour":{"used_percentage":55.2,"resets_at":%s},"seven_day":{"used_percentage":21,"resets_at":%s}}}' "$1" "$dir" "$reset" "$reset"; }
out=$(json 31.5 | bash "$BIN/statusline-sabha.sh") || fail "statusline exited $?"
[[ $out == Arjun* && $out == *31.5%* && $out == *RESTART* ]] || fail "line should carry the name, 31.5% and RESTART: $out"
[[ $out == *'5h 55%'* && $out == *'7d 21%'* ]] || fail "line should show both windows: $out"
[[ $(cat "$dir/status/context/arjun.txt") == 31.5 ]] || fail "context file should hold 31.5"
grep -q "^five_hour 55.2 $reset " "$dir/status/limits.txt" || fail "limits.txt should hold the five_hour reading"
[[ $(wc -l <"$dir/status/alerts.log") -eq 3 ]] || fail "55% and 21% over steps 20 50 = 3 alerts, got $(wc -l <"$dir/status/alerts.log")"
json 32 | bash "$BIN/statusline-sabha.sh" >/dev/null
[[ $(wc -l <"$dir/status/alerts.log") -eq 3 ]] || fail "a second render must not alert again"

out=$(printf '{"session_name":"Nakul","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":null}}' | bash "$BIN/statusline-sabha.sh")
[[ $out == *'ctx n/a'* ]] || fail "null percent should print ctx n/a: $out"
[[ ! -e $dir/status/context/nakul.txt ]] || fail "a null percent must not be written"
echo "ok: line shows ctx and both windows, context file and limits.txt written, alerts fired once"
