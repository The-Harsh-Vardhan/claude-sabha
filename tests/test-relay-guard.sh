#!/usr/bin/env bash
# bin/sabha-relay-guard on hook JSON (stdin): each tool class allowed and denied, Bash chaining and redirects refused,
# the "you do it" override for one turn, and sabha-up.sh passing the hooks to the relay only. No claude runs.
# Run: tests/test-relay-guard.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
command -v jq >/dev/null || { echo "FAIL: jq missing"; exit 1; }
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-guard.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

I=$dir/impl
mkdir -p "$I/inbox/Yudhi" "$I/status" "$dir/ws"
printf 'SABHA_WS=%s/ws\nSABHA_IMPL=%s\nSABHA_ROSTER="Vidur:opus Yudhi:opus Arjun:sonnet"\n' "$dir" "$I" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf CLAUDE_CONFIG_DIR=$dir/cc
# hook <mode> <json>: runs the guard, sets rc and err
hook() { err=$(printf '%s' "$2" | "$SH" "$BIN/sabha-relay-guard" "$1" 2>&1 >/dev/null); rc=$?; }
tool() { hook pre "$(jq -cn --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name: $t, tool_input: {($k): $v}}')"; }
allows() { tool "$@"; (( rc == 0 )); }
denies() { tool "$@"; (( rc == 2 )) && [[ $err == "relay: brief the dispatcher"* ]]; }

for t in Read Grep Glob SendMessage AskUserQuestion ListAgents ToolSearch; do
  check "$t is allowed" 'allows $t pattern x'
done
for t in Agent WebFetch NotebookEdit TaskCreate mcp__x__y; do
  check "$t is denied" 'denies $t x y'
done
check "Write under inbox/ is allowed" 'allows Write file_path "$I/inbox/Yudhi/001-vidur-x.md"'
slug=$(printf %s "$dir/ws" | sed 's/[^A-Za-z0-9]/-/g')
check "Edit in the relay's own project memory dir is allowed" 'allows Edit file_path "$dir/cc/projects/$slug/memory/MEMORY.md"'
check "memory of another project is denied" 'denies Edit file_path "$dir/cc/projects/-other-project/memory/MEMORY.md"'
check "a nested path under memory is denied" 'denies Write file_path "$dir/cc/projects/$slug/memory/a/b.md"'
check "a path under the project dir but not memory is denied" 'denies Write file_path "$dir/cc/projects/$slug/settings.json"'
check "Write to status/ is denied" 'denies Write file_path "$I/status/vidur.md"'
check "Edit of code in the workspace is denied" 'denies Edit file_path "$dir/ws/main.go"'
check "MultiEdit outside is denied" 'denies MultiEdit file_path "$dir/ws/a.txt"'
check "inbox/../ escape is denied" 'denies Write file_path "$I/inbox/../PROTOCOL.md"'
check "a relative path is denied" 'denies Write file_path "inbox/Yudhi/001.md"'

for c in 'ls -la inbox' 'cat status/x.md | head -5' 'git -C /r log --oneline -3 2>/dev/null' 'git status && git diff' \
         'git branch --show-current' 'echo a=b' 'grep -rn "foo bar" docs' 'cd /r; grep -rn foo . | wc -l' 'tail -20 a >/dev/null 2>&1'; do
  check "Bash read-only: $c" 'allows Bash command "$c"'
done
for c in 'rm -rf x' 'ls; rm -rf x' 'ls && touch x' 'cat a | tee b' 'echo $(rm x)' 'echo `id`' 'echo x > f' \
         'echo x >> f' 'cat <(rm x)' 'git branch -D main' 'git -c core.pager=sh log' 'git diff --output=f' \
         'X=1 ls' 'ls >/dev/nullx' 'git push' 'git -C /r push' 'bin/sabha-run' 'sed -i s/a/b/ f' $'ls\nrm x' 'ls & rm x' \
         'cat =(touch F)' 'ls *(e:'"'"'touch F'"'"':)' 'echo ${(e):-\$\(touch F\)}' 'echo ${x@P}' 'echo $HOME' 'ls {a,b}' \
         'echo a\;touch F' '=ls' 'ls =ls' 'ls a\ b' 'ls $'"'"'a\tb'"'"'' 'echo a=b b=(c)'; do
  check "Bash denied: $c" 'denies Bash command "$c"'
done
hook pre 'not json'
check "unreadable input is denied" '(( rc == 2 ))'

hook prompt '{"prompt":"Ok, you do it this time"}'
check "\"you do it\" leaves a one-turn marker" '[[ -e $I/status/.relay-override ]]'
check "override: Edit of workspace code passes" 'allows Edit file_path "$dir/ws/main.go"'
check "override: Bash write passes" 'allows Bash command "touch x"'
hook stop '{}'
check "Stop ends the turn: marker gone" '[[ ! -e $I/status/.relay-override ]]'
check "after the turn the guard is back" 'denies Edit file_path "$dir/ws/main.go"'
hook prompt '{"prompt":"please you do items 3 and 4"}'
check "\"you do items\" does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"doyou do itch"}'
check "\"you do itch\" does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"You Do It."}'
check "\"You Do It.\" (case, punctuation) lifts the guard" '[[ -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"YOU DO IT"}'; hook prompt '{"prompt":"thanks, now brief it"}'
check "the next prompt without the words clears the marker" '[[ ! -e $I/status/.relay-override ]]'

out=$(SABHA_CONF=$dir/none.conf "$SH" "$BIN/sabha-relay-guard" pre <<<'{"tool_name":"Edit"}' 2>&1); rc=$?
check "no config: pre fails closed" '(( rc == 2 ))'
out=$(SABHA_CONF=$dir/none.conf "$SH" "$BIN/sabha-relay-guard" pre <<<'{"tool_name":"Read"}' 2>&1); rc=$?
check "no config: even Read is denied (the guard cannot judge)" '(( rc == 2 ))'

# fail closed: any crash or odd input is a deny, never the non-blocking exit 1 of a hook
EDIT_IN='{"tool_name":"Edit","tool_input":{"file_path":"/x"}}'
badconf() { printf '%s\nSABHA_IMPL=%s\n' "$1" "$I" > "$dir/bad.conf"; out=$(SABHA_CONF=$dir/bad.conf "$SH" "$BIN/sabha-relay-guard" pre <<<"${2:-$EDIT_IN}" 2>&1); rc=$?; }
badconf 'SABHA_X=$NOPE_UNSET_VAR'
check "conf with an unbound variable: pre denies (rc 2)" '(( rc == 2 )) && [[ $out == *"brief the dispatcher"* ]]'
badconf 'exit 3'
check "conf that exits: pre denies (rc 2)" '(( rc == 2 )) && [[ $out == *"brief the dispatcher"* ]]'
badconf 'false' '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
check "conf with a failing command still lets Read through" '(( rc == 0 ))'
hook pre ''
check "empty stdin: pre denies" '(( rc == 2 )) && [[ $err == "relay: brief the dispatcher"* ]]'
hook pre '{"tool_name":"Bash","tool_input":{}}'
check "Bash with no command field: denied" '(( rc == 2 ))'
hook pre '{"tool_name":"Write","tool_input":{}}'
check "Write with no file_path: denied" '(( rc == 2 ))'
hook pre '{"tool_name":"Bash","tool_input":{"command":5}}'
check "Bash with a non-string command: denied" '(( rc == 2 ))'
hook pre '[1,2'
check "truncated JSON: denied" '(( rc == 2 ))'

out=$(SABHA_RELAY_GUARD=1 "$SH" "$BIN/sabha-up.sh" --print Vidur 2>&1)
json=$(sed -n "s/.* --settings '\([^']*\)'.*/\1/p" <<<"$out")
check "sabha-up --print: the relay gets --settings with the guard hooks" '[[ -n $json ]] && jq -e --arg g "\"$BIN/sabha-relay-guard\" pre" ".hooks.PreToolUse[0].matcher == \"*\" and .hooks.PreToolUse[0].hooks[0].command == \$g and (.hooks.UserPromptSubmit | length) == 1 and (.hooks.Stop | length) == 1" <<<"$json" >/dev/null'
out=$(SABHA_RELAY_GUARD=1 "$SH" "$BIN/sabha-up.sh" --print Yudhi 2>&1)
check "sabha-up --print: the dispatcher gets no guard" '! grep -q -- --settings <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" --print Vidur 2>&1)
check "flag off: the relay gets no guard" '! grep -q -- --settings <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
