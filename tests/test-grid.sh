#!/usr/bin/env bash
# The grid sabha-up.sh builds from the roster: two 4x2 tabs (Build, Gate) for the default 20 roles, on-demand roles
# with no pane, shorter rosters, more than 8 panes in a tab refused. osascript and claude are stubs (the script is captured, nothing opens). Run: tests/test-grid.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-grid.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl" "$dir/ws" "$dir/stubs"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
printf '#!/bin/sh\necho "STUB osascript $*"; [ -t 0 ] || cat\n' > "$dir/stubs/osascript"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript"
: > "$dir/ps.txt"
export SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH SABHA_BACKEND=iterm

# grid <roster or "-" for none>: runs sabha-up.sh with that roster (none = the script's default list)
grid() {
  { echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; [[ $1 == - ]] || echo "SABHA_ROSTER=\"$1\""; } > "$dir/sabha.conf"
  out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
  nv=$(grep -c 'split vertically' <<<"$out"); nh=$(grep -c 'split horizontally' <<<"$out")
}
roster() { local r="" i; for i in $(seq 0 "$1"); do r+="R$i:sonnet:medium "; done; echo "${r% }"; }

grid -
echo "--- default roster:"; grep '^sabha-up: tab' <<<"$out"
check "Build tab: 8 panes in brief order" 'grep -q "^sabha-up: tab Build 4x2: Dispatcher Architect BuilderHeavy BuilderPrecise Reviewer Writer Runner Scribe$" <<<"$out"'
check "Gate tab: only the non-lazy gate roles" 'grep -q "^sabha-up: tab Gate 1x2: Observer Housekeeper$" <<<"$out"'
check "lazy roles get no pane" '! grep -qE "\"(BackendCritic|FrontendCritic|SecurityCritic|ScopeCritic|BlindReviewer|Keeper)\"" <<<"$out"'
check "splits: Build 3 vertical + 4 horizontal, Gate 1 horizontal" '(( rc == 0 && nv == 3 && nh == 5 ))'
check "equal columns by halving: b1->b3, b1->b2, b3->b4" 'grep -q "tell b1 to set b3 to (split vertically" <<<"$out" && grep -q "tell b3 to set b4 to (split vertically" <<<"$out"'
check "g2 under g1 and the Gate tab is created" 'grep -q "tell g1 to set g2 to (split horizontally" <<<"$out" && grep -q "create tab with default profile" <<<"$out"'
check "on-demand Tutor, Watcher, Coach and relay Relay are not panes" '! grep -qE "Tutor|Watcher|Coach|\"Relay\"" <<<"$out"'
check "no menu click any more" '! grep -q "Arrange Split Panes" <<<"$out"'
check "each pane runs sabha-loop <Name>, not sabha-up.sh or claude" 'grep -q "write text \"'"'"'$BIN/sabha-loop'"'"' BuilderPrecise\"" <<<"$out" && [[ $(grep -c "write text \"'"'"'$BIN/sabha-loop'"'"' " <<<"$out") -eq 10 ]] && ! grep -q "write text .*sabha-up.sh" <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --plan max5 --force 2>&1)
check "--plan and --force reach the loop as environment" 'grep -q "write text \"SABHA_PLAN=max5 SABHA_FORCE=1 '"'"'$BIN/sabha-loop'"'"' BuilderPrecise\"" <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print BuilderPrecise); rc=$?
check "--print: restart line first, then the wrapped pane command" '(( rc == 0 )) && sed -n 1p <<<"$out" | grep -q "claude -n BuilderPrecise " && [[ $(sed -n 2p <<<"$out") == "pane: cd \"$dir/ws\" && '"'"'$BIN/sabha-loop'"'"' BuilderPrecise" ]]'
for n in Relay Dispatcher Architect BuilderHeavy BuilderPrecise Reviewer Writer Runner Scribe BackendCritic FrontendCritic SecurityCritic ScopeCritic BlindReviewer Keeper Observer Housekeeper Tutor Watcher Coach; do
  SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print "$n" >/dev/null 2>&1 || echo "FAIL print $n"
done > "$dir/print.txt"
check "--print works for all 20 default roles" '[[ ! -s $dir/print.txt ]]'
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus BuilderPrecise:opus:low"\n' "$dir/ws" "$dir/impl" > "$dir/watch.conf"
mkdir -p "$dir/impl/status/context" && echo 45 > "$dir/impl/status/context/builderprecise.txt"
out=$(SABHA_CONF=$dir/watch.conf "$SH" "$BIN/sabha-watch" 2>&1)
check "sabha-watch RESTART keeps only the --print restart line, not the pane: line" 'grep -q "RESTART: .*claude -n BuilderPrecise " <<<"$out" && ! grep -q "pane:" <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print Tutor); rc=$?
check "--print Tutor prints its restart line" '(( rc == 0 )) && grep -q "claude -n Tutor --model opus --effort medium" <<<"$out"'
printf '  901 ttys014  Tue Oct 13 18:00:00 2026     claude -n Tutor --model opus --effort medium\n' > "$dir/ps-k.txt"
out=$(SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps-k.txt "$SH" "$BIN/sabha-check")
check "sabha-check lists Tutor" 'grep -q "^Tutor  *901 " <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps-k.txt "$SH" "$BIN/sabha-down.sh")
check "sabha-down sends Tutor a save brief and lists it to stop" 'grep -q "inbox/Tutor/001" <<<"$out" && grep -q "^  Tutor 901 " <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps-k.txt "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "grid guard ignores a running on-demand role" '(( rc == 0 )) && grep -q "tab Gate 1x2" <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps-k.txt "$SH" "$BIN/sabha-up.sh" Tutor 2>&1); rc=$?
check "a second Tutor is refused" '(( rc == 1 )) && grep -q "Tutor 901" <<<"$out"'
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo "SABHA_ROSTER=\"$(roster 8) T:haiku:medium:ondemand\""; echo 'SABHA_PROMPT_T="then do the T job. Report to X."'; } > "$dir/sabha.conf"
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print T)
check "SABHA_PROMPT_<Name> replaces the prompt tail" 'grep -q "status/t.md, then do the T job. Report to X.\"$" <<<"$out" && ! grep -q "inbox/T/" <<<"$out"'
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo "SABHA_ROSTER=\"$(roster 8) T:haiku:medium:ondemand\""; echo "SABHA_PROTOCOL_CORE=CORE.md"; echo "SABHA_ROLE_DIR=roles"; } > "$dir/sabha.conf"
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print T)
check "SABHA_PROTOCOL_CORE + SABHA_ROLE_DIR split the read list" 'grep -q "read $dir/impl/CORE.md, then $dir/impl/roles/T.md, then the top block of status/t.md, then inbox/T/" <<<"$out"'

{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo "SABHA_ROSTER=\"$(roster 2) M:haiku:high:lazy,mcp\""; } > "$dir/sabha.conf"
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print R1)
check "roles start with no MCP servers" 'grep -q "claude -n R1 --model sonnet --effort medium --strict-mcp-config " <<<"$out"'
out=$(SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" --print M)
check "the mcp flag keeps them" 'grep -q "claude -n M --model haiku --effort high \"" <<<"$out"'

grid "$(roster 8)"
check "shorter roster, no gate flags: one Build tab 4x2, no Gate tab" '(( rc == 0 && nv == 3 && nh == 4 )) && grep -q "tab Build 4x2" <<<"$out" && ! grep -q "create tab" <<<"$out"'
grid "$(roster 5)"
check "5 panes: Build 3x2, last column full height" '(( rc == 0 && nv == 2 && nh == 2 )) && grep -q "tab Build 3x2" <<<"$out"'
grid "$(roster 4) G1:haiku:medium:gate G2:haiku:medium:gate,lazy G3:haiku:medium:gate"
check "mixed roster: Build 2x2 and Gate 1x2 (lazy G2 has no pane)" '(( rc == 0 )) && grep -q "tab Build 2x2: R1 R2 R3 R4$" <<<"$out" && grep -q "tab Gate 1x2: G1 G3$" <<<"$out"'
grid "$(roster 9)"
check "9 Build panes refused, osascript not run" '(( rc == 1 )) && ! grep -q "tell application" <<<"$out"'
grid "$(roster 1) $(for i in 1 2 3 4 5 6 7 8 9; do printf 'G%s:haiku:medium:gate ' $i; done)"
check "9 Gate panes refused" '(( rc == 1 )) && ! grep -q "tell application" <<<"$out"'

# the generated AppleScript must compile as generated (osacompile only compiles, nothing runs). iTerm must be addressed by
# bundle id: a name lookup ("iTerm2") loads no dictionary on a Mac with two copies. Skipped without osacompile or iTerm.
iterm_id=com.googlecode.iterm2
compiles() {
  printf '%s\n' "$out" | sed -n '/^tell application/,$p' > "$dir/g.applescript"
  osacompile -o "$dir/g.scpt" "$dir/g.applescript" 2> "$dir/osacompile.err"
}
printf 'tell application id "%s" to create window with default profile\n' "$iterm_id" > "$dir/canary.applescript"
if ! command -v osacompile >/dev/null; then
  echo "skip: AppleScript compile checks (osacompile not found)"
elif ! osacompile -o "$dir/canary.scpt" "$dir/canary.applescript" 2>/dev/null; then
  echo "skip: AppleScript compile checks (iTerm2 dictionary not available to osacompile)"
else
  for spec in "default roster, 4x2 Build + Gate:-" "2x2 Build + Gate:$(roster 4) G1:haiku:medium:gate G3:haiku:medium:gate" "3x2, 5 panes:$(roster 5)" "3x2, 6 panes:$(roster 6)" "4x2, 8 panes:$(roster 8)"; do
    grid "${spec#*:}"
    check "AppleScript compiles: ${spec%%:*}" 'compiles || { cat "$dir/osacompile.err"; false; }'
  done
fi

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
