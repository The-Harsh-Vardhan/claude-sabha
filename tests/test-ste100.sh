#!/usr/bin/env bash
# SABHA_STE100_PERCENT: the example conf defaults to 60, an override reaches the role's opening prompt, a bad value means 60,
# the core protocol holds the rule, and doctor warns on a bad value. No Claude runs. Run: tests/test-ste100.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-ste100.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd "$dir" && pwd)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
unset SABHA_CONF SABHA_IMPL SABHA_WS SABHA_STE100_PERCENT
mkdir -p "$dir/impl/status"

# conf [extra line]: a minimal conf; no SABHA_STE100_PERCENT unless the line sets it
conf() { printf 'SABHA_WS=%s\nSABHA_IMPL=%s/impl\nSABHA_ROSTER="Relay:opus:medium Dispatcher:opus:medium"\n%s\n' "$dir" "$dir" "${1:-}" >"$dir/sabha.conf"; }
# prompt: the Relay's restart command, which holds the opening prompt
prompt() { SABHA_CONF=$dir/sabha.conf "$SH" "$ROOT/bin/sabha-up.sh" --print Relay 2>&1; }

check "sabha.conf.example sets SABHA_STE100_PERCENT=60" 'grep -q "^SABHA_STE100_PERCENT=60$" "$ROOT/sabha.conf.example"'
check "the example line has a comment above it" 'grep -B3 "^SABHA_STE100_PERCENT=" "$ROOT/sabha.conf.example" | grep -q "^# "'
check "the core protocol holds the rule with the placeholder" 'grep -q "ASD-STE100 for about\$" "$ROOT/template/impl/PROTOCOL-core.md" && grep -q "^\${SABHA_STE100_PERCENT}% of the text" "$ROOT/template/impl/PROTOCOL-core.md"'

conf
check "no setting: the opening prompt carries 60" 'grep -q "SABHA_STE100_PERCENT=60\." <<<"$(prompt)"'
conf "SABHA_STE100_PERCENT=20"
check "an override of 20 reaches the opening prompt" 'grep -q "SABHA_STE100_PERCENT=20\." <<<"$(prompt)"'
conf "SABHA_STE100_PERCENT=0"
check "0 (off) is kept, not read as unset" 'grep -q "SABHA_STE100_PERCENT=0\." <<<"$(prompt)"'
conf "SABHA_STE100_PERCENT=100"
check "100 (strict) is kept" 'grep -q "SABHA_STE100_PERCENT=100\." <<<"$(prompt)"'
for bad in 101 abc -5 "" 5.5; do
  conf "SABHA_STE100_PERCENT=\"$bad\""
  check "a bad value (\"$bad\") means 60" 'grep -q "SABHA_STE100_PERCENT=60\." <<<"$(prompt)"'
done
conf "SABHA_STE100_PERCENT=007"
check "a leading zero is not read as octal" 'grep -q "SABHA_STE100_PERCENT=7\." <<<"$(prompt)"'

echo "--- sabha doctor"
doc() { SABHA_CONF=$dir/sabha.conf SABHA_DOCTOR_COPIES="" "$SH" "$ROOT/bin/sabha" doctor 2>&1; }
conf "SABHA_STE100_PERCENT=30"
check "doctor shows the value" 'grep -q "^ok    ASD-STE100: 30% " <<<"$(doc)"'
conf "SABHA_STE100_PERCENT=150"
check "doctor warns on 150 and names the default" 'grep -q "^warn  SABHA_STE100_PERCENT=150 is not a whole number 0-100: roles use the default 60" <<<"$(doc)"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: SABHA_STE100_PERCENT: default 60, override and bad-value fallback in the opening prompt, rule in the core protocol, doctor"
