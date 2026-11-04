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

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
