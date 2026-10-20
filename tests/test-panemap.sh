#!/usr/bin/env bash
# The pane map status/herdr-panes.txt ("RoleId pane_id"), against the fake herdr only (tests/hermetic.sh): a grid start writes
# a fresh map keyed by role ids, a role started inside a herdr pane records its own pane, sabha-nudge drops entries whose
# pane herdr no longer lists (closed pane ids are never reused) and falls back to the lower-case agent name; a missing map
# no longer aborts sabha-nudge under set -e. Run: tests/test-panemap.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-panemap.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs" "$dir/fh"
cp "$ROOT/tests/fake-herdr.sh" "$dir/stubs/herdr"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
chmod +x "$dir/stubs/herdr" "$dir/stubs/claude"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt FAKE_HERDR_LOG=$dir/herdr.log FAKE_HERDR_DIR=$dir/fh FAKE_HERDR_CALLS=$dir/calls
export PATH=$dir/stubs:$PATH SABHA_HERDR_BIN=$dir/stubs/herdr
unset SABHA_BACKEND SABHA_PLAN SABHA_PANES SABHA_REMOTE SABHA_THEME HERDR_ENV HERDR_PANE_ID FAKE_HERDR_PANES FAKE_HERDR_FAIL_PANELIST
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"
  echo 'SABHA_ROSTER="Relay:opus:medium Dispatcher:opus:medium BuilderHeavy:sonnet:low"'; } > "$dir/sabha.conf"
map=$dir/impl/status/herdr-panes.txt
reset() { : > "$FAKE_HERDR_LOG"; : > "$dir/calls"; rm -rf "$dir/fh"; mkdir -p "$dir/fh"; unset FAKE_HERDR_PANES FAKE_HERDR_FAIL_PANELIST; }
nudge() { "$SH" "$BIN/sabha-nudge" "$1" "see inbox/x" 2>&1; }

echo "--- sabha-nudge"
reset; rm -f "$map"
out=$(nudge Dispatcher); rc=$?
check "no map at all: the nudge falls back to the lower-case name instead of exiting under set -e" '(( rc == 0 )) && grep -q "^agent prompt dispatcher see inbox/x --wait" "$FAKE_HERDR_LOG"'
reset; printf 'Dispatcher w1:p2\n' > "$map"; export FAKE_HERDR_PANES="w1:p1 w1:p2"
out=$(nudge Dispatcher); rc=$?
check "a live entry is the target" '(( rc == 0 )) && grep -q "^agent prompt w1:p2 see inbox/x --wait" "$FAKE_HERDR_LOG"'
reset; printf 'Relay w4:p9\nDispatcher w1:p2\n' > "$map"; export FAKE_HERDR_PANES="w1:p1 w1:p2"
out=$(nudge Relay); rc=$?
check "a dead entry is dropped from the map, the live one stays" '! grep -q "^Relay " "$map" && grep -q "^Dispatcher w1:p2$" "$map"'
check "the drop is reported on stderr, naming the role and the pane" 'grep -q "Relay" <<<"$out" && grep -q "w4:p9" <<<"$out"'
check "a role with no live pane falls back to the lower-case name" '(( rc == 0 )) && grep -q "^agent prompt relay see inbox/x --wait" "$FAKE_HERDR_LOG" && ! grep -q "w4:p9" "$FAKE_HERDR_LOG"'
reset; printf 'Relay w4:p9\n' > "$map"; export FAKE_HERDR_FAIL_PANELIST=1
out=$(nudge Relay)
check "when herdr cannot list panes (or lists none we can read) the map is left alone, never pruned on a failed call" 'grep -q "^Relay w4:p9$" "$map"'

echo "--- grid start"
reset; printf 'Old w4:p9\nBuilderHeavy w4:p8\n' > "$map"
out=$("$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "the map is rewritten at grid start: roles of an older grid are gone" '(( rc == 0 )) && ! grep -q "^Old " "$map" && ! grep -q "w4:" "$map"'
check "every pane of this grid is in it, under its role id" 'grep -q "^Dispatcher w1:p[0-9]*$" "$map" && grep -q "^BuilderHeavy w1:p[0-9]*$" "$map"'
reset; : > "$map"
printf '%s\n' "SABHA_WS=$dir/ws" "SABHA_IMPL=$dir/impl" 'SABHA_ROSTER="Relay:opus:medium Dispatcher:opus:medium BuilderHeavy:sonnet:low"' 'SABHA_THEME=avengers' > "$dir/sabha.conf"
out=$("$SH" "$BIN/sabha-up.sh" 2>&1)
check "keys are role ids even under a theme (never the character)" 'grep -q "^BuilderHeavy w1:p" "$map" && ! grep -qE "^(Hulk|Fury|Jarvis) " "$map"'

echo "--- a role started inside a pane records it"
reset; printf 'Dispatcher w1:p2\nBuilderHeavy w1:p3\n' > "$map"
out=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p7 "$SH" "$BIN/sabha-up.sh" Dispatcher 2>&1)
check "sabha-up.sh <Role> in a herdr pane replaces that role's line with its own pane" 'grep -q "^Dispatcher w1:p7$" "$map" && [[ $(grep -c "^Dispatcher " "$map") == 1 ]] && grep -q "^BuilderHeavy w1:p3$" "$map"'
reset; : > "$map"
out=$("$SH" "$BIN/sabha-up.sh" Dispatcher 2>&1)
check "outside herdr (no HERDR_PANE_ID) it records nothing" '[[ ! -s $map ]]'

echo "--- concurrent writers"
# a grid start: every pane writes its row at once; without the lock the last writer's map erased the others (~70% lost)
: > "$map"
for i in 1 2 3 4 5 6 7 8 9 10; do
  SABHA_IMPL=$dir/impl "$SH" -c ". '$BIN/sabha-lib.sh' 2>/dev/null; . '$BIN/sabha-herdr.sh'; sabha_pane_note Role$i w1:p$i" &
done
wait
check "10 concurrent sabha_pane_note: all 10 rows kept, no lock or temp left" '[[ $(grep -c . "$map") -eq 10 ]] && [[ -z $(ls "$dir/impl/status" | grep -E "lock|panes\.txt\.") ]]'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: pane map: fresh at grid start, role ids as keys, self-registration, dead entries pruned, missing map and failed list handled"
