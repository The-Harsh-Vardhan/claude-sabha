#!/usr/bin/env bash
# SABHA_CHROME_<Name>=1 gives one role --chrome (the role that uses skills/sabha-browser-verify) and no other role.
# Only sabha-up.sh --print runs: no claude, herdr or browser is started. Run: tests/test-chrome-role.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-chrome.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
mkdir -p "$dir/ws" "$dir/impl"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus:medium Runner:sonnet:medium Writer:sonnet:low"\n' "$dir/ws" "$dir/impl" >"$dir/base.conf"
P() { SABHA_CONF=$dir/$1.conf "${BASH:-bash}" "$ROOT/bin/sabha-up.sh" --print --raw "$2" 2>&1; }
cp "$dir/base.conf" "$dir/off.conf"
{ cat "$dir/base.conf"; echo "SABHA_CHROME_Runner=1"; } >"$dir/on.conf"

o=$(P off Runner)
check "no switch: the Runner line has --strict-mcp-config and no --chrome" '[[ $o == *--strict-mcp-config* && $o != *--chrome* ]]'
o=$(P on Runner)
check "SABHA_CHROME_Runner=1: the Runner line has --strict-mcp-config and --chrome" '[[ $o == *--strict-mcp-config* && $o == *" --chrome "* ]]'
o=$(P on Writer)
check "SABHA_CHROME_Runner=1 does not reach Writer" '[[ $o != *--chrome* ]]'
o=$(P on Runner-2)
check "a copy follows its base role" '[[ $o == *" --chrome "* ]]'

if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "all ok"
