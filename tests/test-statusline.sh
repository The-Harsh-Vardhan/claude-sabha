#!/usr/bin/env bash
# bin/statusline-sabha.sh fed a fake statusLine JSON: prints the line with the usage windows, writes the context
# percent to status/context/<name>.txt and the windows to status/limits.txt, and fires the alerts once.
# Needs jq. Run: tests/test-statusline.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-sl.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_NOTIFY_DESKTOP=0\nSABHA_NOTIFY="20 50"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
fail() { echo "FAIL: $*"; exit 1; }
reset=$(( $(date +%s) + 600 ))

json() { printf '{"session_name":"BuilderPrecise","model":{"display_name":"Opus"},"context_window":{"used_percentage":%s},"cwd":"%s","rate_limits":{"five_hour":{"used_percentage":55.2,"resets_at":%s},"seven_day":{"used_percentage":21,"resets_at":%s}}}' "$1" "$dir" "$reset" "$reset"; }
out=$(json 31.5 | bash "$BIN/statusline-sabha.sh") || fail "statusline exited $?"
[[ $out == $'\033[38;2;'* ]] || fail "a themed role's name should open with its 24-bit colour: $out"
out=$(sed $'s/\033\\[[0-9;]*m//g' <<<"$out")
[[ $out == BuilderPrecise* && $out == *31.5%* && $out == *RESTART* ]] || fail "line should carry the name, 31.5% and RESTART: $out"
[[ $out == *'5h 55%'* && $out == *'7d 21%'* ]] || fail "line should show both windows: $out"
[[ $(cat "$dir/status/context/builderprecise.txt") == 31.5 ]] || fail "context file should hold 31.5"
grep -q "^five_hour 55.2 $reset " "$dir/status/limits.txt" || fail "limits.txt should hold the five_hour reading"
[[ $(wc -l <"$dir/status/alerts.log") -eq 3 ]] || fail "55% and 21% over steps 20 50 = 3 alerts, got $(wc -l <"$dir/status/alerts.log")"
json 32 | bash "$BIN/statusline-sabha.sh" >/dev/null
[[ $(wc -l <"$dir/status/alerts.log") -eq 3 ]] || fail "a second render must not alert again"

out=$(printf '{"session_name":"Writer","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":null}}' | bash "$BIN/statusline-sabha.sh")
[[ $out == *'ctx n/a'* ]] || fail "null percent should print ctx n/a: $out"
[[ ! -e $dir/status/context/writer.txt ]] || fail "a null percent must not be written"
# herdr sidebar (win C, 002): a role in a herdr pane reports its display name, held brief and ctx to the fake herdr
mkdir -p "$dir/inbox/BuilderPrecise"; : >"$dir/inbox/BuilderPrecise/003.claim"; : >"$dir/inbox/BuilderPrecise/003.done"; : >"$dir/inbox/BuilderPrecise/004.claim"
: >"$FAKE_HERDR_LOG"
json 22.4 | HERDR_PANE_ID=w1:p3 SABHA_THEME=mahabharat bash "$BIN/statusline-sabha.sh" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ $(grep -c "report-metadata" "$FAKE_HERDR_LOG") -ge 2 ]] && break; sleep 0.3; done
grep -q "^pane report-metadata w1:p3 --source sabha:name --display-agent Arjun$" "$FAKE_HERDR_LOG" || fail "sidebar should get the display name Arjun: $(cat "$FAKE_HERDR_LOG")"
grep -q "^pane report-metadata w1:p3 --source sabha:status --seq [0-9]* --ttl-ms 300000 --token brief=004 --token ctx=22%$" "$FAKE_HERDR_LOG" || fail "sidebar should get brief 004 and ctx 22% with a ttl: $(cat "$FAKE_HERDR_LOG")"
! grep -v "^--session sabha " "$FAKE_HERDR_CALLS" | grep -q . || fail "every sidebar call carries --session sabha"
: >"$FAKE_HERDR_LOG"
json 22.4 | HERDR_PANE_ID=w1:p3 SABHA_THEME=mahabharat bash "$BIN/statusline-sabha.sh" >/dev/null; sleep 1
[[ ! -s $FAKE_HERDR_LOG ]] || fail "an unchanged line within 60 s must not report again"
json 22.4 | HERDR_PANE_ID=w1:p3 bash "$BIN/statusline-sabha.sh" >/dev/null; sleep 1
grep -q -- "--display-agent BuilderPrecise$" "$FAKE_HERDR_LOG" || fail "a changed display name reports again"
: >"$FAKE_HERDR_LOG"
printf '{"session_name":"Stranger","model":{"display_name":"Opus"},"context_window":{"used_percentage":5}}' | HERDR_PANE_ID=w1:p9 bash "$BIN/statusline-sabha.sh" >/dev/null
json 22.4 | bash "$BIN/statusline-sabha.sh" >/dev/null; sleep 1
[[ ! -s $FAKE_HERDR_LOG ]] || fail "no report for a non-sabha session or outside a herdr pane"
echo "ok: herdr sidebar gets name, brief and ctx with a ttl, throttled, sabha roles in herdr panes only"
echo "ok: line shows ctx and both windows, context file and limits.txt written, alerts fired once"
