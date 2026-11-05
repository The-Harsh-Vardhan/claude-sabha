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

echo "--- sabha-loop is the default starter"
conf 'SABHA_ROSTER="V:opus Y:opus A:opus K:sonnet:medium:lazy"'
out=$(up --print K)
check "--print: one line, the sabha-loop line with the config path" '[[ $out == "cd \"$dir/ws\" && SABHA_CONF='"'"'$dir/sabha.conf'"'"' '"'"'$BIN/sabha-loop'"'"' K" ]]'
out=$(up --print --raw K)
check "--print --raw: the claude line only" '[[ $(wc -l <<<"$out") -eq 1 ]] && grep -q "^cd \"$dir/ws\" && claude -n K --model sonnet --effort medium " <<<"$out"'
out=$(SABHA_EFFICIENCY=0 up --print K)
check "flag off: the claude line first, then the pane: line" 'sed -n 1p <<<"$out" | grep -q "claude -n K " && sed -n 2p <<<"$out" | grep -q "^pane: "'
out=$(up K)
check "a start outside a loop says so and still starts" 'grep -q "not supervised: use sabha-loop K" <<<"$out" && grep -q "^STUB claude -n K " <<<"$out"'
out=$(SABHA_LOOP_ACTIVE=K up K)
check "under its loop: no notice" '! grep -q "not supervised" <<<"$out" && grep -q "^STUB claude -n K " <<<"$out"'
check "sabha-loop exports SABHA_LOOP_ACTIVE to its child" 'grep -q "export SABHA_LOOP_ACTIVE=\"\$name\"" "$BIN/sabha-loop"'

echo "--- per-role MCP"
mkdir -p "$dir/mcp" && echo '{"mcpServers":{}}' > "$dir/mcp/aikido.json"
conf 'SABHA_ROSTER="V:opus Y:opus A:opus B:opus K:sonnet:medium:lazy"' 'SABHA_MCP_A=aikido' "SABHA_MCP_FILE_aikido=$dir/mcp/aikido.json"
out=$(up --print --raw A)
check "a named set: --mcp-config before --model (it takes many values), strict after" 'grep -q "claude -n A --mcp-config '"'"'$dir/mcp/aikido.json'"'"' --model opus --effort medium --strict-mcp-config \"" <<<"$out"'
out=$(up --print --raw B)
check "no set: strict, no --mcp-config" 'grep -q -- "--effort medium --strict-mcp-config \"" <<<"$out" && ! grep -q -- "--mcp-config " <<<"$out"'
out=$(up --print --raw V; up --print --raw Y)
check "relay and dispatcher keep the full set (Q6)" '! grep -q -- "mcp-config" <<<"$out"'
out=$(SABHA_EFFICIENCY=0 up --print --raw V)
check "flag off: the relay without the mcp flag is strict, as today" 'grep -q -- "--strict-mcp-config" <<<"$out"'
out=$(up A)
check "the start path passes the same MCP arguments" 'grep -q "^STUB claude -n A --mcp-config $dir/mcp/aikido.json --model opus --effort medium --strict-mcp-config " <<<"$out"'
conf 'SABHA_ROSTER="V:opus Y:opus A:opus"' 'SABHA_MCP_V=none' 'SABHA_MCP_A=nosuch'
out=$(up --print --raw V)
check "SABHA_MCP_<Name>=none overrides the relay default" 'grep -q -- "--strict-mcp-config" <<<"$out"'
out=$(up --print --raw A); rc=$?
check "a set with no SABHA_MCP_FILE_<set> is refused" '(( rc == 1 )) && grep -q "SABHA_MCP_FILE_nosuch" <<<"$out"'

conf 'SABHA_ROSTER="V:opus Y:opus K:sonnet:medium:lazy"'
mkdir -p "$dir/impl/inbox/K" && printf 'to: K\nmcp: full\n' > "$dir/impl/inbox/K/001-y-test.md"
out=$("$SH" "$BIN/sabha-run" --print K 2>&1)
check "sabha-run: a brief with mcp: full runs with the full set" 'grep -q "claude -p -n K" <<<"$out" && ! grep -q "strict-mcp-config" <<<"$out"'
printf 'to: K\n' > "$dir/impl/inbox/K/001-y-test.md"
out=$("$SH" "$BIN/sabha-run" --print K 2>&1)
check "sabha-run: without it, strict" 'grep -q "strict-mcp-config" <<<"$out"'
printf 'to: K\nmcp: full\n' > "$dir/impl/inbox/K/001-y-test.md"
out=$(SABHA_EFFICIENCY=0 "$SH" "$BIN/sabha-run" --print K 2>&1)
check "sabha-run, flag off: the header is ignored" 'grep -q "strict-mcp-config" <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
