#!/usr/bin/env bash
# bin/sabha-loop, round 2, with a fake agent (SABHA_LOOP_CMD) and fake files, no Claude run:
#   #22 an agent's handoff save that lands while the loop rewrites the crash flag survives (a sed shim saves it
#       between the loop's read and its replace).
# Run: tests/test-loop-r2.sh (a few seconds)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-loop-r2.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus BuilderPrecise:opus:low"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_LOOP_INTERVAL=1 SABHA_LOOP_RETRIES=0 SABHA_LOOP_MIN_UP=10 SABHA_NOTIFY_DESKTOP=0
mkdir -p "$dir/status" "$dir/inbox/BuilderPrecise" "$dir/shim"
fail() { echo "FAIL: $*"; exit 1; }
md=$dir/status/builderprecise.md log=$dir/status/loop/builderprecise.log

# #22: the first sed that reads the handoff (or a copy of it) plays the agent: it lets the loop read the old text, then
# saves a new handoff before the loop can replace the file. Without a check before the replace the save is lost.
real_sed=$(command -v sed)
cat >"$dir/shim/sed" <<EOF
#!/bin/sh
"$real_sed" "\$@"; rc=\$?
case " \$* " in *"$md"*)
  if [ ! -e "$dir/saved" ]; then : >"$dir/saved"; printf 'Current: fresh save\nNext: keep me\n' >"$md"; fi ;;
esac
exit \$rc
EOF
chmod +x "$dir/shim/sed"
printf 'Current: old\nNext: old\n' >"$md"
PATH="$dir/shim:$PATH" SABHA_LOOP_CMD='exit 1' bash "$BIN/sabha-loop" BuilderPrecise 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] || fail "loop should exit 1 after 2 failed starts, got $rc: $(cat "$log")"
[[ -e $dir/saved ]] || fail "the shim never ran: the crash flag did not read the handoff"
grep -qx 'Current: fresh save' "$md" && grep -qx 'Next: keep me' "$md" ||
  fail "#22: the agent's save was erased by the crash flag: $(cat "$md")"
[[ $(sed -n 1p "$md") == "Blocked: crashed "* ]] || fail "#22: the crash flag is missing: $(cat "$md")"
grep -q 'old' "$md" && fail "#22: the old handoff came back: $(cat "$md")"
ls "$dir/status" | grep -q 'builderprecise\.md\.' && fail "#22: temp files left behind: $(ls "$dir/status")"

echo "ok: a handoff save during the crash flag survives (#22)"
