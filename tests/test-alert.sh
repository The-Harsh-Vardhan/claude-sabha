#!/usr/bin/env bash
# bin/sabha-alert against the fake herdr: a blocked pane gets one toast with the request sound, its screen is copied
# verbatim to status/blocked/<name>.txt while it is blocked and removed after, and nothing ever answers the prompt
# (no send-keys, no agent prompt). Run: tests/test-alert.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-alert.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
mkdir -p "$dir/impl/status" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="V:opus:medium Y:opus:medium A:sonnet:low B:sonnet:low"\n' "$dir/ws" "$dir/impl" >"$dir/sabha.conf"
printf 'A w1:p3\nB w1:p4\n' >"$dir/impl/status/herdr-panes.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_ALERT_RETRY=0
log() { cat "$FAKE_HERDR_LOG"; }

out=$(bash "$BIN/sabha-alert" --once 2>&1); rc=$?
check "watches every recorded role and ends cleanly" '(( rc == 0 )) && grep -q "watching A B" <<<"$out"'
check "waits for blocked on each recorded pane" 'grep -q "^agent wait w1:p3 --until blocked --timeout 600000$" "$FAKE_HERDR_LOG" && grep -q "^agent wait w1:p4 --until blocked" "$FAKE_HERDR_LOG"'
check "one toast per blocked pane; a worker's is silent (idea 5)" '[[ $(grep -c "^notification show sabha: .* needs you .*--sound none$" "$FAKE_HERDR_LOG") -eq 2 ]]'
check "re-arms only after the pane leaves blocked" 'grep -q "^agent wait w1:p3 --until idle --until working --until done" "$FAKE_HERDR_LOG"'
check "alerts.log has a line per block" '[[ $(grep -c " blocked [AB] w1:p" "$dir/impl/status/blocked/alerts.log") -eq 2 ]]'
check "the screen file is gone once the prompt is" '[[ ! -e $dir/impl/status/blocked/a.txt ]]'
check "never answers: no send-keys, no prompt" '! grep -q -E "^agent (send-keys|prompt)|^pane (send|input)" "$FAKE_HERDR_LOG"'
check "no hidden wait file is left behind" '[[ -z $(ls -A "$dir/impl/status/blocked" | grep "^\\.") ]]'
check "every call carries --session" '! grep -v -E "^--session sabha " "$FAKE_HERDR_CALLS" | grep -q .'

# the screen copy while blocked: a wrapper herdr saves status/blocked/a.txt when the leave-blocked wait starts
: >"$FAKE_HERDR_LOG"
cat >"$dir/herdr" <<EOF
#!/bin/sh
case "\$*" in *"--until idle"*) cp "$dir/impl/status/blocked/a.txt" "$dir/screen-seen" 2>/dev/null ;; esac
exec "$SABHA_HERDR_BIN" "\$@"
EOF
chmod +x "$dir/herdr"
PATH=$dir:$PATH SABHA_HERDR_BIN=$dir/herdr FAKE_HERDR_SCREEN='Allow Bash(rm -rf build)? 1. Yes 2. No' bash "$BIN/sabha-alert" --once A >/dev/null 2>&1
check "while blocked the screen is copied word for word" 'grep -qxF "Allow Bash(rm -rf build)? 1. Yes 2. No" "$dir/screen-seen" && grep -q "^role: A$" "$dir/screen-seen"'

: >"$FAKE_HERDR_LOG"
printf 'V w1:p1\n' >>"$dir/impl/status/herdr-panes.txt"
bash "$BIN/sabha-alert" --once V >/dev/null 2>&1
check "only the relay's toast chimes (idea 5)" 'grep -q "^notification show sabha: V needs you .*--sound request$" "$FAKE_HERDR_LOG"'

echo "--- reviewer fixes"
: >"$FAKE_HERDR_LOG"; rm -f "$dir/impl/status/blocked/alerts.log"
FAKE_HERDR_GONE_PANES=1 bash "$BIN/sabha-alert" --once A >/dev/null 2>&1; rc=$?
check "fix 1: a stale pane id falls back to the agent name" '(( rc == 0 )) && grep -q "^agent wait a --until blocked" "$FAKE_HERDR_LOG"'
check "fix 1: the fallback is logged once" '[[ $(grep -c "A: herdr cannot wait on w1:p3, using the agent name a" "$dir/impl/status/blocked/alerts.log") -eq 1 ]]'
FAKE_HERDR_FAIL_READ=1 PATH=$dir:$PATH SABHA_HERDR_BIN=$dir/herdr bash "$BIN/sabha-alert" --once A >/dev/null 2>&1
check "fix 2: herdr error text never lands in the screen file" '! grep -q "agent_not_found" "$dir/screen-seen" && grep -q "screen not readable" "$dir/screen-seen"'
rm -f "$FAKE_HERDR_DIR/wait-pids"
FAKE_HERDR_WAIT_SLEEP=30 bash "$BIN/sabha-alert" A B >/dev/null 2>&1 & apid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [[ -f $FAKE_HERDR_DIR/wait-pids && $(wc -l <"$FAKE_HERDR_DIR/wait-pids") -ge 2 ]] && break; sleep 0.3; done
kill -TERM "$apid"; wait "$apid" 2>/dev/null; sleep 0.5
alive=0; while read -r w; do kill -0 "$w" 2>/dev/null && { alive=1; kill "$w"; }; done <"$FAKE_HERDR_DIR/wait-pids"
check "fix 3: stopping sabha-alert also ends its herdr waits" '[[ $(wc -l <"$FAKE_HERDR_DIR/wait-pids") -ge 2 ]] && (( alive == 0 ))'
check "a stopped sabha-alert leaves no hidden wait file" '[[ -z $(ls -A "$dir/impl/status/blocked" | grep "^\\.") ]]'

: >"$FAKE_HERDR_LOG"
FAKE_HERDR_FAIL_WAIT=1 bash "$BIN/sabha-alert" --once A >/dev/null 2>&1; rc=$?
check "a timed-out wait shows no toast" '(( rc != 0 )) && ! grep -q "^notification" "$FAKE_HERDR_LOG"'
out=$(bash "$BIN/sabha-alert" --bogus 2>&1); rc=$?
check "an unknown option prints usage" '(( rc == 2 ))'

(( fails == 0 )) && echo "ok: all checks pass" || { echo "$fails check(s) failed"; exit 1; }
