#!/usr/bin/env bash
# The five-pane plan (sabha.five.conf): exactly five always-on roles, the relay one of them, Architect (the Elephant) on
# opus/medium; SABHA_MAX_HEADFUL refuses a sixth. claude and osascript are stubs; nothing opens. Run: tests/test-five-pane.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-five.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl" "$dir/ws" "$dir/stubs"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
printf '#!/bin/sh\necho "STUB osascript $*"; [ -t 0 ] || cat\n' > "$dir/stubs/osascript"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript"
: > "$dir/ps.txt"
export SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH SABHA_BACKEND=iterm SABHA_PLAN_DIR=$ROOT
conf() { { echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; printf '%s\n' "$@"; } > "$dir/sabha.conf"; }
up() { SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" "$@" 2>&1; }

conf
out=$(up --plan five); rc=$?
check "five plan: one 3x2 Build tab, relay first, no Gate tab" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 3x2: Relay Dispatcher BuilderPrecise Runner Architect$" <<<"$out" && ! grep -q "create tab" <<<"$out"'
out=$(up --plan five --print Architect); rc=$?
check "Architect (Elephant) is opus/medium" '(( rc == 0 )) && grep -q "claude -n Architect --model opus --effort medium" <<<"$out"'
check "five plan carries no path" '! grep -qE "^SABHA_(WS|IMPL|CONF|PROJECT|USER)=" "$ROOT/sabha.five.conf"'

conf 'SABHA_PLAN=five'
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "SABHA_PLAN=five in sabha.conf works like --plan" '(( rc == 0 )) && grep -q "tab Build 3x2: Relay" <<<"$out"'
conf 'SABHA_MAX_HEADFUL=4' 'SABHA_ROSTER="Relay:opus Dispatcher:opus BuilderPrecise:opus Runner:sonnet Architect:opus"'
out=$(up); rc=$?
check "SABHA_MAX_HEADFUL=4 refuses the five always-on roles, no osascript" '(( rc == 1 )) && grep -q "5 headful roles" <<<"$out" && ! grep -q "tell application" <<<"$out"'
conf 'SABHA_MAX_HEADFUL=5' 'SABHA_ROSTER="Relay:opus Dispatcher:opus BuilderPrecise:opus Runner:sonnet Architect:opus Reviewer:sonnet"'
out=$(up); rc=$?
check "a sixth always-on role is refused" '(( rc == 1 )) && grep -q "6 headful roles" <<<"$out"'
conf 'SABHA_MAX_HEADFUL=5' 'SABHA_ROSTER="Relay:opus Dispatcher:opus BuilderPrecise:opus Runner:sonnet Architect:opus Reviewer:sonnet:medium:lazy Tutor:opus:medium:ondemand"'
out=$(up); rc=$?
check "lazy and ondemand roles do not count as headful" '(( rc == 0 ))'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
