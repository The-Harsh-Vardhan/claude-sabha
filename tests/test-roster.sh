#!/usr/bin/env bash
# Roster v2: Name:agent:model[:effort[:flags]] rows and the older Name:model rows side by side, SABHA_PANES picking the
# panes (the relay as pane 1), copies Name-N under SABHA_MAX_COPIES, role labels, the three plan files and
# --plan, and the board reading the same rows. claude and osascript are stubs (nothing opens). Run: tests/test-roster.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-roster.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
printf '#!/bin/sh\necho "STUB osascript $*"; [ -t 0 ] || cat\n' > "$dir/stubs/osascript"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH
unset SABHA_PLAN SABHA_PANES SABHA_MAX_COPIES
export SABHA_BACKEND=iterm

# conf <extra lines...>: writes sabha.conf with the paths and the given lines
conf() { { echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; printf '%s\n' "$@"; } > "$dir/sabha.conf"; }
# load <extra lines...>: sources the lib with that conf and prints ROLES, PANES, RELAY, DISPATCHER, MAX_COPIES
load() {
  conf "$@"
  "$SH" -c '. "$1/sabha-lib.sh"; sabha_load t; printf "ROLE %s\n" "${ROLES[@]}"; echo "PANES ${PANES[*]-}"; echo "RELAY $RELAY DISPATCHER $DISPATCHER COPIES $MAX_COPIES"' _ "$BIN" 2>&1
}
up() { SABHA_CONF=$dir/sabha.conf "$SH" "$BIN/sabha-up.sh" "$@" 2>&1; }

echo "--- rows"
out=$(load 'SABHA_ROSTER="V:opus:medium Y:claude:opus:high B:opencode:gpt-5:low:gate O:sonnet N:codex:o3"')
check "old row Name:model:effort parses as claude" 'grep -q "^ROLE V claude opus medium -$" <<<"$out"'
check "new row Name:claude:model:effort" 'grep -q "^ROLE Y claude opus high -$" <<<"$out"'
check "another agent keeps its model and flags" 'grep -q "^ROLE B opencode gpt-5 low gate$" <<<"$out"'
check "effort defaults to medium in both shapes" 'grep -q "^ROLE O claude sonnet medium -$" <<<"$out" && grep -q "^ROLE N codex o3 medium -$" <<<"$out"'
check "relay and dispatcher are the first two rows" 'grep -q "^RELAY V DISPATCHER Y COPIES 2$" <<<"$out"'
check "without SABHA_PANES: every role but the relay" 'grep -q "^PANES Y B O N$" <<<"$out"'
out=$(load 'SABHA_ROSTER="V:opus Y:claude"')
check "a row with no model is refused" 'grep -q "names no model" <<<"$out"'
out=$(load)
check "no SABHA_ROSTER: the default 20-role list, agent claude" '(( $(grep -c "^ROLE [A-Za-z]* claude " <<<"$out") == 20 )) && grep -q "^ROLE Architect claude fable medium -$" <<<"$out"'

echo "--- panes"
R='SABHA_ROSTER="V:opus:medium Y:opus:medium A:sonnet:high:lazy G:haiku:low:gate T:opus:medium:ondemand"'
out=$(load "$R" 'SABHA_PANES="V Y A"')
check "SABHA_PANES picks the panes in its order, the relay included" 'grep -q "^PANES V Y A$" <<<"$out"'
out=$(load "$R" 'SABHA_PANES="V Z"')
check "an unknown name in SABHA_PANES is refused" 'grep -q "SABHA_PANES names Z" <<<"$out"'
conf "$R" 'SABHA_PANES="V Y A G"'
out=$(up); rc=$?
check "grid: relay is pane 1, a lazy role listed in SABHA_PANES gets a pane, the gate flag still picks the tab" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 2x2: V Y A$" <<<"$out" && grep -q "^sabha-up: tab Gate 1x2: G$" <<<"$out"'
check "grid: the on-demand role has no pane" '! grep -q "\"T\"" <<<"$out"'
conf "$R"
out=$(up); rc=$?
check "grid without SABHA_PANES: unchanged (no relay, no lazy)" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 1x2: Y$" <<<"$out" && grep -q "^sabha-up: tab Gate 1x2: G$" <<<"$out"'

echo "--- copies"
conf "$R" 'SABHA_MAX_COPIES=3'
out=$(up --print A-2); rc=$?
check "A-2 takes A's profile under its own name" '(( rc == 0 )) && grep -q "claude -n A-2 --model sonnet --effort high --strict-mcp-config \"You are A-2 in " <<<"$out" && grep -q "inbox/A-2/" <<<"$out" && grep -q "status/a-2.md" <<<"$out"'
out=$(up --print A-4); rc=$?
check "A-4 is past SABHA_MAX_COPIES=3" '(( rc == 1 )) && grep -q "past SABHA_MAX_COPIES (3)" <<<"$out"'
conf "$R"
out=$(up --print A-3); rc=$?
check "copies default to 2" '(( rc == 1 )) && grep -q "past SABHA_MAX_COPIES (2)" <<<"$out"'
out=$(up --print A-0); rc=$?
check "A-0 is not a copy" '(( rc == 1 )) && grep -q "unknown role: A-0" <<<"$out"'
out=$(up --print Q-1); rc=$?
check "a copy of an unknown role is unknown" '(( rc == 1 )) && grep -q "unknown role: Q-1" <<<"$out"'
out=$(up --print Y-2); rc=$?
check "a dispatcher copy reports to the relay like the dispatcher" '(( rc == 0 )) && grep -q "Report to V\.\"$" <<<"$out"'

echo "--- labels and agents"
conf "$R" 'SABHA_LABEL_A="Builder"'
out=$(up --print A)
check "a label goes into the opening prompt" 'grep -q "\"You are A (Builder) in " <<<"$out" && grep -q "the name A, append" <<<"$out"'
out=$(up --print A-1)
check "a copy carries the base role's label" 'grep -q "\"You are A-1 (Builder) in " <<<"$out"'
out=$(up --print Y)
check "no label, no brackets" 'grep -q "\"You are Y in " <<<"$out"'
conf 'SABHA_ROSTER="V:opus:medium Y:opus:medium C:codex:o3:low"'
out=$(up --print C); rc=$?
check "a non-claude role prints a herdr agent start line, not a refusal" '(( rc == 0 )) && grep -q "^herdr --session sabha agent start c --kind codex" <<<"$out"'
mkdir -p "$dir/impl/inbox/C"; echo "to: C" > "$dir/impl/inbox/C/001-y-task.md"
out=$(SABHA_RUN_ROLES=all "$SH" "$BIN/sabha-run" --print 2>&1); rc=$?
check "sabha-run never serves a non-claude role" '(( rc == 0 )) && ! grep -q "C" <<<"$out"'

echo "--- plans"
for plan in pro max5 max20; do
  check "sabha.$plan.conf exists and carries no path" '[[ -f $ROOT/sabha.$plan.conf ]] && ! grep -qE "^SABHA_(WS|IMPL|CONF|PROJECT|USER)=" "$ROOT/sabha.$plan.conf"'
  out=$(SABHA_PLAN=$plan SABHA_PLAN_DIR=$ROOT load)
  check "plan $plan loads: SABHA_PANES set, relay is pane 1" 'grep -q "^PANES Relay " <<<"$out"'
done
export SABHA_PLAN_DIR=$ROOT
conf
out=$(up --plan pro); rc=$?
check "--plan pro: one Build tab, Relay first, five panes" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 3x2: Relay Dispatcher BuilderHeavy BuilderPrecise Writer$" <<<"$out" && ! grep -q "create tab" <<<"$out"'
check "--plan pro: panes start with the plan" 'grep -q "SABHA_PLAN=pro .*/bin/sabha-loop. BuilderHeavy" <<<"$out"'
check "--plan pro: no fable row" '! grep -qE "^SABHA_ROSTER=.*:fable" "$ROOT/sabha.pro.conf"'
out=$(up --plan pro --print Architect)
check "--plan pro: the architect is sonnet-free opus, no label repeated" 'grep -q "claude -n Architect --model opus --effort medium --strict-mcp-config \"You are Architect in " <<<"$out"'
out=$(up --plan pro --print BuilderPrecise-3); rc=$?
check "--plan pro: two copies at most" '(( rc == 1 )) && grep -q "past SABHA_MAX_COPIES (2)" <<<"$out"'
out=$(up --plan max5); rc=$?
check "--plan max5: seven Build panes" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 4x2: Relay Dispatcher BuilderHeavy BuilderPrecise Writer Reviewer Runner$" <<<"$out"'
out=$(up --plan max5 --print BuilderPrecise-4); rc=$?
check "--plan max5: four copies" '(( rc == 0 )) && grep -q "claude -n BuilderPrecise-4 " <<<"$out"'
out=$(up --plan max20); rc=$?
check "--plan max20: Build 4x2 with Relay first and a Gate tab" '(( rc == 0 )) && grep -q "^sabha-up: tab Build 4x2: Relay Dispatcher Architect BuilderHeavy BuilderPrecise Reviewer Writer Runner$" <<<"$out" && grep -q "^sabha-up: tab Gate 1x2: Observer Housekeeper$" <<<"$out"'
out=$(up --plan nope); rc=$?
check "an unknown plan is refused" '(( rc == 1 )) && grep -q "no plan file at $ROOT/sabha.nope.conf" <<<"$out"'
conf 'SABHA_PLAN=pro'
out=$(up --print Writer)
check "SABHA_PLAN in sabha.conf works like --plan" 'grep -q "claude -n Writer --model sonnet --effort low " <<<"$out"'
unset SABHA_PLAN_DIR

echo "--- board"
conf 'SABHA_ROSTER="V:opus:medium Y:claude:opus:high B:opencode:gpt-5:low"' 'SABHA_LABEL_B="Builder"' 'SABHA_FORME_DIR='"$dir/board"
mkdir -p "$dir/board"; : > "$dir/impl/for-me.items"
out=$(python3 "$BIN/sabha-for-me" 2>&1); rc=$?
check "sabha-for-me renders a v2 roster" '(( rc == 0 )) && grep -q "^| B (Builder) | gpt-5 low |" "$dir/board/FOR-ME.md" && grep -q "^| Y | opus high |" "$dir/board/FOR-ME.md" && grep -q "^| V | opus medium |" "$dir/board/FOR-ME.md"'
conf 'SABHA_PLAN=pro' 'SABHA_FORME_DIR='"$dir/board"
out=$(SABHA_PLAN_DIR=$ROOT python3 "$BIN/sabha-for-me" 2>&1); rc=$?
check "sabha-for-me reads the plan file" '(( rc == 0 )) && grep -q "^| Architect | opus medium |" "$dir/board/FOR-ME.md"'

# S6: the default roster in sabha.conf.example and the one in sabha.max20.conf are the same string
r1=$(sed -n 's/^SABHA_ROSTER="\(.*\)"$/\1/p' "$ROOT/sabha.conf.example")
r2=$(sed -n 's/^SABHA_ROSTER="\(.*\)"$/\1/p' "$ROOT/sabha.max20.conf")
check "sabha.conf.example and sabha.max20.conf carry the same roster" '[[ -n $r1 && $r1 == "$r2" ]]'

# a theme is a display skin over the role ids: ROLES keep the ids, the display name comes from sabha_display; every theme
# fills the same 20 role ids as plain.theme (the second field of a row)
th=$("$SH" -c '. "$1/sabha-lib.sh"; ROLES=("Relay a b c -" "SecurityCritic a b c -"); SABHA_THEME=avengers sabha_theme t; echo "${ROLES[*]} $SABHA_NAME_Relay $SABHA_NAME_SecurityCritic"' _ "$BIN")
check "the avengers skin shows Jarvis and Widow but leaves ROLES as role ids" '[[ $th == "Relay a b c - SecurityCritic a b c - Jarvis Widow" ]]'
ids() { grep -v "^#" "$1" | grep -v "^[a-z]*: " | cut -d"|" -f2 | sort; }
check "every theme file fills the same 20 role ids as plain.theme" '! for f in "$ROOT"/themes/*.theme; do
  [[ $(ids "$f") == "$(ids "$ROOT/themes/plain.theme")" && $(ids "$f" | wc -l) -eq 20 ]] || echo "$f"; done | grep -q .'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
