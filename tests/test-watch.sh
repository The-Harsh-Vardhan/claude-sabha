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

# F2: a config sabha_load rejects (no model for Relay) must claim nothing, so the dones are announced once it is fixed
rm -rf "$dir/status/done-seen" "$dir/nudges"; : >"$dir/inbox/Worker/003.done"
cp "$dir/sabha.conf" "$dir/good.conf"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
run; sleep 1
[[ ! -d $dir/status/done-seen ]] || [[ -z $(ls "$dir/status/done-seen") ]] || fail "a failed sabha_load claimed dones: $(ls "$dir/status/done-seen")"
[[ ! -s $dir/nudges ]] || fail "a failed sabha_load must not nudge: $(cat "$dir/nudges")"
cp "$dir/good.conf" "$dir/sabha.conf"
run; sleep 1; : >"$dir/inbox/Worker/004.done"
run; wait_lines 1 || fail "after the config is fixed the next .done must be announced"
grep -q 'inbox/Worker/004.done' "$dir/nudges" || fail "fixed config did not announce 004: $(cat "$dir/nudges")"

# F1: with a theme on (mahabharat renames Dispatcher and Relay) the nudges still go to the role ids, the names the
# inbox folders and sabha-nudge use: a .done in inbox/Dispatcher goes to Relay, every other one to Dispatcher
rm -rf "$dir/status/done-seen" "$dir/nudges"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_THEME=mahabharat\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
run; sleep 1
: >"$dir/inbox/Worker/005.done"; : >"$dir/inbox/Dispatcher/002.done"
run; wait_lines 2 || fail "themed: expected 2 nudges: $(cat "$dir/nudges" 2>/dev/null)"
grep -qx 'Dispatcher|see inbox/Worker/005.done' "$dir/nudges" && grep -qx 'Relay|see inbox/Dispatcher/002.done' "$dir/nudges" || fail "themed nudges must target the role ids Dispatcher and Relay: $(cat "$dir/nudges")"
cp "$dir/good.conf" "$dir/sabha.conf"

echo "ok: a failed sabha_load claims no .done; after the fix it announces; with a theme on, nudges go to the role ids Dispatcher and Relay"
