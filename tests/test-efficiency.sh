#!/usr/bin/env bash
# Efficiency (docs/specs/efficiency-profiles.md): SABHA_READS_<Name>, the SABHA_EFFICIENCY flag, profiles from cores and
# RAM, the pane cap, the sabha-loop line as the --print default, per-role MCP sets. claude and osascript are stubs
# (nothing opens). Run: tests/test-efficiency.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-eff.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
printf '#!/bin/sh\necho "STUB osascript $*"; [ -t 0 ] || cat\n' > "$dir/stubs/osascript"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript"
: > "$dir/ps.txt"
export SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH SABHA_BACKEND=iterm SABHA_CONF=$dir/sabha.conf

conf() { { echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; printf '%s\n' "$@"; } > "$dir/sabha.conf"; }
up() { "$SH" "$BIN/sabha-up.sh" "$@" 2>&1; }

echo "--- SABHA_READS_<Name>"
conf 'SABHA_ROSTER="V:opus Y:opus B:opus:medium:lazy"' 'SABHA_READS_B="/ws/ROLE.md, then every file in /ws/MEMORY/"'
out=$(up --print B)
check "SABHA_READS_<Name> replaces the read list, the tail stays" 'grep -q "Then read /ws/ROLE.md, then every file in /ws/MEMORY/, then inbox/B/" <<<"$out" && ! grep -q "PROTOCOL.md" <<<"$out"'
out=$(up --print Y)
check "a role without it keeps the protocol read list" 'grep -q "Then read $dir/impl/PROTOCOL.md, then status/y.md, then inbox/Y/" <<<"$out"'

echo "--- profiles"
G=1073741824
# prof <ncpu> <mem bytes> [extra conf lines...]: the profile and the values sabha_load derives from it
prof() {
  local c=$1 m=$2; shift 2
  conf 'SABHA_ROSTER="V:opus Y:opus A:opus B:opus C:opus D:opus E:opus F:opus:medium:gate"' "$@"
  SABHA_FAKE_NCPU=$c SABHA_FAKE_MEM=$m "$SH" -c '. "$1/sabha-lib.sh"; sabha_load t; echo "$(sabha_profile) run=${SABHA_RUN_MAX:-} heavy=${SABHA_HEAVY_MAX:-} panes=$PANE_MAX"' _ "$BIN" 2>&1
}
export SABHA_EFFICIENCY=1
check "4 cores 8 GB: lite"        '[[ $(prof 4 $((8 * G))) == "lite run=1 heavy=1 panes=2" ]]'
check "10 cores 16 GB: standard"  '[[ $(prof 10 $((16 * G))) == "standard run=2 heavy=2 panes=4" ]]'
check "16 cores 32 GB: full"      '[[ $(prof 16 $((32 * G))) == "full run=3 heavy=3 panes=7" ]]'
check "16 cores 8 GB: lite (RAM is scarcer)" '[[ $(prof 16 $((8 * G))) == lite* ]]'
check "4 cores 64 GB: lite (cores are scarcer)" '[[ $(prof 4 $((64 * G))) == lite* ]]'
check "unreadable hardware counts as standard" '[[ $(prof x y) == standard* ]]'
check "SABHA_PROFILE=full wins over the hardware" '[[ $(prof 4 $((8 * G)) SABHA_PROFILE=full) == full* ]]'
check "explicit SABHA_RUN_MAX and SABHA_HEAVY_MAX win" '[[ $(prof 10 $((16 * G)) SABHA_RUN_MAX=5 SABHA_HEAVY_MAX=4) == "standard run=5 heavy=4 panes=4" ]]'
check "SABHA_PANES set: no pane cap" '[[ $(prof 10 $((16 * G)) "SABHA_PANES=\"Y A\"") == *panes=0 ]]'
check "flag off: no profile values" '[[ $(SABHA_EFFICIENCY=0 prof 4 $((8 * G))) == *"run= heavy= panes=0" ]]'
check "flag off in sabha.conf wins over the default" '[[ $(prof 4 $((8 * G)) SABHA_EFFICIENCY=0) == *"run= heavy= panes=0" ]]'

conf 'SABHA_ROSTER="V:opus Y:opus A:opus B:opus C:opus D:opus E:opus F:opus:medium:gate"'
out=$(SABHA_FAKE_NCPU=10 SABHA_FAKE_MEM=$((16 * G)) up)
check "standard grid opens 4 panes in roster order and names the rest" 'grep -q "^sabha-up: tab Build 2x2: Y A B C$" <<<"$out" && ! grep -q "tab Gate" <<<"$out" && grep -q "profile standard opens 4 panes; not opened: D E F" <<<"$out"'
out=$(SABHA_EFFICIENCY=0 SABHA_FAKE_NCPU=10 SABHA_FAKE_MEM=$((16 * G)) up)
check "flag off: today's grid" 'grep -q "^sabha-up: tab Build 3x2: Y A B C D E$" <<<"$out" && grep -q "tab Gate 1x2: F" <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
