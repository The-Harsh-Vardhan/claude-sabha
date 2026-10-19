#!/usr/bin/env bash
# bin/sabha-watch announces each new inbox/<Role>/NNN.done once: the first pass only records what exists, a new .done
# nudges the dispatcher (the relay for a .done in the dispatcher's inbox), a second pass nudges nothing. The nudge
# program is a fake (SABHA_NUDGE_BIN); no herdr, no agent. Run: tests/test-watch.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-watch.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_NOTIFY_DESKTOP=0
mkdir -p "$dir/inbox/Worker" "$dir/inbox/Dispatcher" "$dir/status"
printf '#!/bin/sh\necho "$1|$2" >>"%s/nudges"\n' "$dir" >"$dir/fake-nudge"; chmod +x "$dir/fake-nudge"
export SABHA_NUDGE_BIN=$dir/fake-nudge
fail() { echo "FAIL: $*"; exit 1; }
wait_lines() { local i; for (( i = 0; i < 50; i++ )); do [[ -f $dir/nudges && $(wc -l <"$dir/nudges") -ge $1 ]] && return 0; sleep 0.1; done; return 1; }
run() { bash "$BIN/sabha-watch" >/dev/null 2>&1; }

: >"$dir/inbox/Worker/001.done"
run; sleep 1
[[ ! -s $dir/nudges ]] || fail "first pass must only record the existing .done: $(cat "$dir/nudges")"
[[ -e $dir/status/done-seen/Worker-001 ]] || fail "existing .done not recorded"

: >"$dir/inbox/Worker/002.done"
run; wait_lines 1 || fail "new .done did not nudge the dispatcher"
[[ $(cat "$dir/nudges") == "Dispatcher|see inbox/Worker/002.done" ]] || fail "wrong nudge: $(cat "$dir/nudges")"

run; run; sleep 1
[[ $(wc -l <"$dir/nudges") -eq 1 ]] || fail "a .done must be announced once: $(cat "$dir/nudges")"

: >"$dir/inbox/Dispatcher/001.done"
run; wait_lines 2 || fail "a .done in the dispatcher inbox did not nudge the relay"
[[ $(sed -n 2p "$dir/nudges") == "Relay|see inbox/Dispatcher/001.done" ]] || fail "wrong relay nudge: $(cat "$dir/nudges")"

echo "ok: first pass records, a new .done nudges the dispatcher once, a dispatcher-inbox .done nudges the relay"
