#!/usr/bin/env bash
# Config resolution: SABHA_CONF, else the nearest <dir>/.sabha/local/sabha.conf from the cwd upward, else the sabha.conf
# beside the scripts. A second copy of the scripts whose own sabha.conf names another project must never win over the
# project the cwd is in (one team's context files landing in another project's folder). Read-only on real projects:
# everything lives under a temp dir. Run: tests/test-conf.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-conf.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd "$dir" && pwd)   # $TMPDIR may end in a slash; $PWD never does
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "skip: needs jq"; exit 0; }
unset SABHA_CONF SABHA_IMPL SABHA_WS SABHA_THEME SABHA_CTX_DIR

# a team project: workspace with .sabha/local/sabha.conf -> its own sabha folder
team=$dir/team; teamimpl=$dir/team-impl
mkdir -p "$team/.sabha/local" "$team/sub/deep" "$team/inner/.sabha/local" "$teamimpl/status" "$dir/inner-impl/status"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_NOTIFY_DESKTOP=0\nSABHA_ROSTER="Relay:opus:medium"\n' "$team" "$teamimpl" > "$team/.sabha/local/sabha.conf"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_NOTIFY_DESKTOP=0\n' "$team/inner" "$dir/inner-impl" > "$team/inner/.sabha/local/sabha.conf"
# another project's copy of the scripts: its own sabha.conf sits beside bin/ (the fallback)
copy=$dir/copy; otherimpl=$dir/other-impl
mkdir -p "$copy" "$otherimpl/status" "$otherimpl/inbox"
cp -R "$ROOT/bin" "$ROOT/themes" "$ROOT/icons" "$copy/" 2>/dev/null
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_NOTIFY_DESKTOP=0\nSABHA_ROSTER="Relay:opus:medium"\n' "$dir/other-ws" "$otherimpl" > "$copy/sabha.conf"

sl() { (cd "$1" && printf '{"session_name":"Relay","model":{"display_name":"Opus"},"context_window":{"used_percentage":12}}' | bash "$copy/bin/statusline-sabha.sh" >/dev/null); }

echo "--- statusline (writes the context file)"
sl "$team"
check "cwd is the workspace: the team's status/context gets it, the copy's project does not" '[[ -f $teamimpl/status/context/relay.txt && ! -e $otherimpl/status/context/relay.txt ]]'
rm -f "$teamimpl/status/context/relay.txt"
sl "$team/sub/deep"
check "cwd is a subdirectory: the nearest .sabha/local above it still wins over the copy's conf" '[[ -f $teamimpl/status/context/relay.txt && ! -e $otherimpl/status/context/relay.txt ]]'
rm -f "$teamimpl/status/context/relay.txt"
sl "$team/inner/x" 2>/dev/null || { mkdir -p "$team/inner/x"; sl "$team/inner/x"; }
check "nested projects: the nearest .sabha/local wins" '[[ -f $dir/inner-impl/status/context/relay.txt && ! -e $teamimpl/status/context/relay.txt ]]'
rm -f "$dir/inner-impl/status/context/relay.txt"
sl "$dir"
check "no .sabha/local anywhere above: the conf beside the scripts is the fallback" '[[ -f $otherimpl/status/context/relay.txt ]]'
rm -f "$otherimpl/status/context/relay.txt"
(cd "$team/sub/deep" && SABHA_CONF=$copy/sabha.conf bash -c 'printf "{\"session_name\":\"Relay\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":12}}" | bash "$1/bin/statusline-sabha.sh" >/dev/null' _ "$copy")
check "SABHA_CONF in the environment still beats the walk-up" '[[ -f $otherimpl/status/context/relay.txt && ! -e $teamimpl/status/context/relay.txt ]]'

echo "--- the lib (every script that sources it)"
lib() { (cd "$1" && "$SH" -c '. "$2/bin/sabha-lib.sh"; sabha_conf_read t && echo "$SABHA_CONF"' _ "$1" "$copy" 2>&1); }
out=$(lib "$team/sub/deep")
check "sabha_conf_read: nearest .sabha/local from a subdirectory" '[[ $out == "$team/.sabha/local/sabha.conf" ]]'
out=$(lib "$dir")
check "sabha_conf_read: fallback beside the scripts when nothing is above" '[[ $out == "$copy/bin/../sabha.conf" ]]'
out=$(cd "$team/sub/deep" && SABHA_CONF=$copy/sabha.conf "$SH" -c '. "$1/bin/sabha-lib.sh"; sabha_conf_read t && echo "$SABHA_CONF"' _ "$copy")
check "sabha_conf_read: SABHA_CONF in the environment wins" '[[ $out == "$copy/sabha.conf" ]]'

echo "--- sabha-theme use, sabha doctor, the board"
(cd "$team/sub/deep" && "$SH" "$copy/bin/sabha-theme" use plain >/dev/null 2>&1)
check "sabha-theme use writes the team's conf from a subdirectory, not the copy's" 'grep -q "^SABHA_THEME=plain$" "$team/.sabha/local/sabha.conf" && ! grep -q SABHA_THEME "$copy/sabha.conf"'
out=$(cd "$team/sub/deep" && PATH=$PATH "$SH" "$copy/bin/sabha" doctor 2>&1)
check "sabha doctor reports the team's config" 'grep -q "^ok    config $team/.sabha/local/sabha.conf$" <<<"$out"'
mkdir -p "$teamimpl/inbox"; : > "$teamimpl/for-me.items"; : > "$otherimpl/for-me.items"
(cd "$team/sub/deep" && python3 "$copy/bin/sabha-for-me" >/dev/null 2>&1)
check "the board is written into the team's project, not the copy's" '[[ -f $teamimpl/FOR-ME.md && ! -e $otherimpl/FOR-ME.md ]]'
(cd "$dir" && python3 "$copy/bin/sabha-for-me" >/dev/null 2>&1)
check "the board falls back to the conf beside the scripts when nothing is above" '[[ -f $otherimpl/FOR-ME.md ]]'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: config resolution: env, nearest .sabha/local upward, beside the scripts; a copy's own conf never beats the cwd's project"
