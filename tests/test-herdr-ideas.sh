#!/usr/bin/env bash
# herdr ideas 4, 5, 6, 10 (bin/sabha-herdr-config prints the settings, writes nothing) and 8 (sabha-check --explain),
# against the fake herdr. Run: tests/test-herdr-ideas.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-ideas.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
mkdir -p "$dir/impl/status" "$dir/ws" "$dir/home"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus A:sonnet:low"\n' "$dir/ws" "$dir/impl" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf HOME=$dir/home
: >"$FAKE_HERDR_LOG"

out=$(SABHA_THEME=mahabharat bash "$BIN/sabha-herdr-config" 2>/dev/null); rc=$?
check "prints, writes nothing, calls no herdr" '(( rc == 0 )) && [[ ! -s $FAKE_HERDR_LOG && -z $(ls -A "$dir/home") ]]'
check "idea 10: 2 s stagger, resume on" 'grep -qx "startup_per_agent_delay_ms = 2000" <<<"$out" && grep -qx "resume_agents_on_restore = true" <<<"$out"'
check "idea 4: sidebar rows use the brief and ctx tokens" 'grep -qF "[\"state_icon\", \"agent\", \"\$brief\", \"\$ctx\"]," <<<"$out"'
check "idea 5: herdr's own claude sounds off" 'grep -A1 -x "\[ui.sound.agents\]" <<<"$out" | grep -qx "claude = \"off\""'
check "idea 6: board and check popups run less with LESSSECURE=1 (no shell, no editor)" 'grep -qF "command = \"LESSSECURE=1 less \\\"$dir/impl/FOR-ME.md\\\"\"" <<<"$out" && grep -qF "sabha-check\\\" --explain | LESSSECURE=1 less\"" <<<"$out" && [[ $(grep -c "less" <<<"$out") -eq $(grep -c "LESSSECURE=1 less" <<<"$out") ]]'
check "names the copy whose bin/ the keys run and points at the installed copy" 'grep -qF "# The keys run this copy: $BIN (use the installed plugin copy, not a worktree)." <<<"$out"'
check "idea 6: the relay key focuses its agent and sends no text" 'grep -qx "command = \"herdr --session sabha agent focus relay\"" <<<"$out" && ! grep -qE "send-keys|send-text|prompt|pane run" <<<"$out"'
check "idea 6: the relay key is labelled with its display name" 'grep -qx "description = \"sabha: focus Vidur'"'"'s input\"" <<<"$out"'
check "every table appears once (TOML refuses repeats)" '[[ -z $(grep -E "^\[[a-z.]+\]$" <<<"$out" | sort | uniq -d) ]]'
check "keys are prefix chords, never a plain printable key" '! grep -E "^key = " <<<"$out" | grep -vq "\"prefix+alt+[a-z]\""'
out=$(SABHA_HERDR_SESSION=default bash "$BIN/sabha-herdr-config" 2>&1); rc=$?
check "refuses herdr's default session" '(( rc == 2 ))'
for evil in 'my $(touch PWNED) impl' 'my `touch PWNED` impl' "it's"; do
  mkdir -p "$dir/$evil/status"
  printf 'SABHA_WS=%s\nSABHA_IMPL='"'"'%s'"'"'\nSABHA_ROSTER="Relay:opus A:sonnet"\n' "$dir/ws" "$dir/${evil//\'/}" >"$dir/evil.conf"
  [[ $evil == "it's" ]] && printf 'SABHA_WS=%s\nSABHA_IMPL="%s"\nSABHA_ROSTER="Relay:opus A:sonnet"\n' "$dir/ws" "$dir/$evil" >"$dir/evil.conf"
  out=$(cd "$dir" && SABHA_CONF=$dir/evil.conf bash "$BIN/sabha-herdr-config" 2>&1); rc=$?
  check "refuses an IMPL path with shell metacharacters: $evil" '(( rc == 2 )) && grep -q "refusing a path" <<<"$out" && ! grep -q "^command" <<<"$out" && [[ ! -e $dir/PWNED ]]'
done
# a copy of bin/ inside a git worktree warns; the same copy in a main checkout does not (git 2.42+ for --orphan)
git init -q "$dir/main" && cp -R "$BIN" "$dir/main/bin" && git -C "$dir/main" worktree add -q --orphan -b wt "$dir/wt" 2>/dev/null && cp -R "$BIN" "$dir/wt/bin"
err=$(bash "$dir/wt/bin/sabha-herdr-config" 2>&1 >/dev/null)
check "warns when run from a git worktree" 'grep -q "is in a git worktree" <<<"$err" && grep -q "installed plugin copy" <<<"$err"'
err=$(bash "$dir/main/bin/sabha-herdr-config" 2>&1 >/dev/null)
check "no warning from a main checkout" '[[ -z $err ]]'

printf 'A w1:p3\n' >"$dir/impl/status/herdr-panes.txt"
: >"$dir/ps.txt"
out=$(SABHA_PS_FILE=$dir/ps.txt bash "$BIN/sabha-check" --explain 2>&1)
check "idea 8: sabha-check --explain asks herdr about each recorded pane" 'grep -q "^--- A (w1:p3): herdr agent explain" <<<"$out" && grep -q "^agent explain w1:p3$" "$FAKE_HERDR_LOG"'
check "idea 8: --explain never starts a server" '! grep -qx "server" "$FAKE_HERDR_LOG"'
: >"$FAKE_HERDR_LOG"
SABHA_PS_FILE=$dir/ps.txt bash "$BIN/sabha-check" >/dev/null 2>&1
check "idea 8: a plain sabha-check calls no herdr" '[[ ! -s $FAKE_HERDR_LOG ]]'
printf 'A w1:p3\nB w1:p4\n' >"$dir/impl/status/herdr-panes.txt"
out=$(FAKE_HERDR_EAT_STDIN=1 SABHA_PS_FILE=$dir/ps.txt bash "$BIN/sabha-check" --explain 2>&1)
check "idea 8: a herdr that reads stdin cannot eat the next recorded pane" 'grep -q "^--- B (w1:p4)" <<<"$out"'
rm -f "$dir/impl/status/herdr-panes.txt"
out=$(SABHA_PS_FILE=$dir/ps.txt bash "$BIN/sabha-check" --explain 2>&1)
check "idea 8: no herdr-panes.txt prints a note, not a shell error" 'grep -q "^--- no status/herdr-panes.txt" <<<"$out" && ! grep -qi "no such file" <<<"$out"'

(( fails == 0 )) && echo "ok: all checks pass" || { echo "$fails check(s) failed"; exit 1; }
