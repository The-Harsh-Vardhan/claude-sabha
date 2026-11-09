#!/usr/bin/env bash
# bin/sabha-reap against a fake process list and the fake herdr only (tests/hermetic.sh): the list shows age, idle, ctx
# and pane state, marks STALE? copies and ORPHAN panes, and prints plain ASCII whatever ps or a file holds; --close acts
# only on ids named on the command line and never on a role's last live copy, an id not in the list, a live pane, a pane
# herdr does not report idle or done, the pane it runs in, a pane two map rows name, or any pane when ps shows no named claude.
# Run: tests/test-reap.sh
# shellcheck disable=SC2016,SC2034,SC2329  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-reap.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status/context" "$dir/ws" "$dir/stubs" "$dir/fh"
cp "$ROOT/tests/fake-herdr.sh" "$dir/stubs/herdr"
# a kill that only logs; -0 says "gone" so the TERM check passes
cat > "$dir/stubs/kill" <<EOF
#!/bin/sh
echo "\$*" >> "$dir/kill.log"
[ "\$1" = -0 ] && exit 1
exit 0
EOF
chmod +x "$dir/stubs/herdr" "$dir/stubs/kill"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt SABHA_KILL=$dir/stubs/kill SABHA_KILL_GRACE=0
export FAKE_HERDR_LOG=$dir/herdr.log FAKE_HERDR_DIR=$dir/fh FAKE_HERDR_CALLS=$dir/calls
export PATH=$dir/stubs:$PATH SABHA_HERDR_BIN=$dir/stubs/herdr
unset SABHA_BACKEND SABHA_PLAN FAKE_HERDR_PANES FAKE_HERDR_FAIL_PANELIST FAKE_HERDR_STATUS FAKE_HERDR_FAIL_CLOSE FAKE_HERDR_GARBAGE FAKE_HERDR_PANELIST_OK_ONCE HERDR_PANE_ID SABHA_ANCESTORS
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo 'SABHA_ROSTER="Relay:opus:medium Builder:opus:medium Ghost:opus:medium Ghost2:opus:medium Coder:opencode:gpt"'; } > "$dir/sabha.conf"
map=$dir/impl/status/herdr-panes.txt
reap() { "$SH" "$ROOT/bin/sabha-reap" "$@" 2>&1; }
# reapp: as reap, from a pane (w1:p9) that is not one of the listed panes
reapp() { HERDR_PANE_ID=w1:p9 reap "$@"; }
# no_close: herdr was reachable (its log exists) and holds no pane close
no_close() { [[ -f $FAKE_HERDR_LOG ]] && ! grep -q "pane close" "$FAKE_HERDR_LOG"; }

cat > "$dir/ps.txt" <<'EOF'
  101 ttys004  Tue Oct 13 09:00:01 2026     claude -n Relay --model opus
  801 ttys005  Tue Oct 13 10:00:00 2026     claude -n Builder --model opus
  802 ttys006  Tue Oct 13 12:00:00 2026     claude -n Builder --resume x --model opus
  900 ttys007  Tue Oct 13 12:00:00 2026     grep claude -n Builder
EOF
epoch() { date -j -f '%Y-%b-%d %H:%M:%S' "$1" +%s 2>/dev/null || date -d "$1" +%s; }
export SABHA_NOW=$(( $(epoch '2026-Oct-13 12:00:00') + 7200 ))
printf '42' > "$dir/impl/status/context/builder.txt"
touch -t 202610131230 "$dir/impl/status/context/builder.txt"
mt=$(stat -f %m "$dir/impl/status/context/builder.txt" 2>/dev/null || stat -c %Y "$dir/impl/status/context/builder.txt")
SABHA_NOW_IDLE=$(( mt + 5400 ))

echo "--- list"
rm -f "$map"
out=$(reap); rc=$?
check "list exits 0 and names every claude copy, not the grep line" '(( rc == 0 )) && grep -q "^101 " <<<"$out" && grep -q "^801 " <<<"$out" && grep -q "^802 " <<<"$out" && ! grep -q "^900 " <<<"$out"'
check "oldest first: 101 before 801 before 802" '[[ $(grep -n "^\(101\|801\|802\) " <<<"$out" | cut -d" " -f1 | cut -d: -f2 | tr "\n" " ") == "101 801 802 " ]]'
check "the older Builder is STALE?, the newer is newest of 2, Relay is only copy" 'grep "^801 " <<<"$out" | grep -q "STALE?" && grep "^802 " <<<"$out" | grep -q "newest of 2" && grep "^101 " <<<"$out" | grep -q "only copy"'
check "age of the newest Builder is 2h0m" 'grep "^802 " <<<"$out" | grep -q " 2h0m "'
check "no pane map: says so, still lists" 'grep -q "^panes: no status/herdr-panes.txt" <<<"$out"'
out2=$(SABHA_NOW=$SABHA_NOW_IDLE reap)
check "ctx 42% and idle 1h30m from the context file (the same file gives both)" 'grep "^802 " <<<"$out2" | grep -q "1h30m *42%"'
check "a session with no context file shows - - " 'grep "^101 " <<<"$out" | grep -qE "^101 +Relay +[0-9a-z]+ +- +- "'

echo "--- context file input"
: > "$dir/impl/status/context/relay.txt"
out=$(reap); check "empty context file: ctx -" 'grep "^101 " <<<"$out" | grep -qE " 0m +- +- +-"'
head -c 200000 /dev/zero | tr '\0' 'x' > "$dir/impl/status/context/relay.txt"
out=$(reap); check "huge non-numeric context file: ctx -, no crash" '[[ $? == 0 ]] && grep "^101 " <<<"$out" | grep -qE "[0-9a-z]+ +[0-9a-z]+ +- "'
rm -f "$dir/impl/status/context/relay.txt"

echo "--- bad input"
mv "$dir/ps.txt" "$dir/ps.gone"
out=$(reap); rc=$?
check "unreadable process list: exit 2, says so" '(( rc == 2 )) && grep -q "cannot read the process list" <<<"$out"'
mv "$dir/ps.gone" "$dir/ps.txt"
out=$(reap --close); rc=$?;  check "--close with no id: exit 2" '(( rc == 2 ))'
out=$(reap --bogus); rc=$?;  check "unknown option: exit 2" '(( rc == 2 ))'
out=$(reap --close -x); rc=$?; check "--close -x: exit 2" '(( rc == 2 ))'
out=$(reap --close ../x); rc=$?; check "--close ../x: exit 2" '(( rc == 2 ))'
out=$(SABHA_KILL='' reap --close 801); rc=$?
check "--close on a fake list without SABHA_KILL: exit 2, nothing signalled" '(( rc == 2 )) && [[ ! -s $dir/kill.log ]]'
printf '  102 ttys008  Tue Oct 13 09:00:01 2026     claude -n Rel\033]0;x\a\302\233ay\342\200\256 --model opus\n' >> "$dir/ps.txt"
out=$(reap); rc=$?
bad=$(printf '%s' "$out" | LC_ALL=C tr -d ' -~\n' | wc -c | tr -d ' ')
check "control, C1 and bidi bytes in a session name never reach the output" '(( rc == 0 && bad == 0 )) && grep -q "^102 " <<<"$out"'
sed -i.bak '/ttys008/d' "$dir/ps.txt"; rm -f "$dir/ps.txt.bak"

echo "--- herdr panes"
herdr --session sabha server
printf 'Relay w1:p1\nGhost w1:p5\nBuilder w1:p2\nCoder w1:p6\nStray w1:p8\nGhost2 w1:p10\n' > "$map"
export FAKE_HERDR_PANES="w1:p1 w1:p2 w1:p5 w1:p6 w1:p8 w1:p10" FAKE_HERDR_STATUS="w1:p5=idle w1:p6=idle w1:p8=idle w1:p10=done"
out=$(reap); rc=$?
check "Relay row shows its pane and state" 'grep "^101 " <<<"$out" | grep -q "w1:p1 *unknown"'
check "pane shown on the newest Builder copy only" 'grep "^802 " <<<"$out" | grep -q "w1:p2" && ! grep "^801 " <<<"$out" | grep -q "w1:p2"'
check "Ghost (no named claude, herdr idle) is an ORPHAN row marked closable" 'grep "^ORPHAN " <<<"$out" | grep "Ghost" | grep -q "w1:p5 *idle.*closable"'
check "a role with a live claude is not an orphan: only Ghost and Ghost2 are" '(( $(grep -c "^ORPHAN" <<<"$out") == 2 ))'
check "a non-claude role pane and a pane outside the roster are OTHER, not ORPHAN" 'grep "^OTHER " <<<"$out" | grep "Coder" | grep -q "runs on opencode" && grep "^OTHER " <<<"$out" | grep "Stray" | grep -q "not in the roster" && ! grep "^ORPHAN" <<<"$out" | grep -qE "Coder|Stray"'
check "the list says cost is context % only and idle is the status-line render" 'grep -q "ctx is the last context %" <<<"$out" && grep -q "a STALE? copy may be the busy one" <<<"$out"'
check "listing closes nothing and never signals" '[[ -s $FAKE_HERDR_CALLS ]] && no_close && [[ ! -s $dir/kill.log ]]'
check "every herdr call carried --session" '[[ -s $FAKE_HERDR_CALLS ]] && ! grep -qv "^--session sabha" "$FAKE_HERDR_CALLS"'

echo "--- close: pids"
: > "$dir/kill.log"
out=$(reap --close 801); rc=$?
check "close the stale copy: TERM to 801 only" '(( rc == 0 )) && grep -qx -- "-TERM 801" "$dir/kill.log" && ! grep -q 802 "$dir/kill.log"'
: > "$dir/kill.log"
out=$(reap --close 101); rc=$?
check "the only copy of a role is refused" '(( rc == 1 )) && grep -q "refused 101" <<<"$out" && [[ ! -s $dir/kill.log ]]'
out=$(reap --close 801 802); rc=$?
check "naming every copy of a role is refused, nothing signalled" '(( rc == 1 )) && [[ ! -s $dir/kill.log ]]'
out=$(reap --close 4242); rc=$?
check "a pid not in the list is refused" '(( rc == 1 )) && grep -q "refused 4242" <<<"$out" && [[ ! -s $dir/kill.log ]]'
for z in 0101 00101; do
  out=$(reap --close "$z"); rc=$?
  check "leading zero $z: the only copy is still refused, nothing signalled" '(( rc == 1 )) && grep -q "refused 101: that would close every live copy" <<<"$out" && [[ ! -s $dir/kill.log ]]'
done
out=$(reap --close 801 0802); rc=$?
check "801 0802 names both copies: refused, nothing signalled" '(( rc == 1 )) && grep -q "every live copy of Builder" <<<"$out" && [[ ! -s $dir/kill.log ]]'
out=$(reap --close 0801); rc=$?
check "0801 is signalled in its canonical form 801, never as 0801" '(( rc == 0 )) && grep -qx -- "-TERM 801" "$dir/kill.log" && ! grep -q 0801 "$dir/kill.log"'
: > "$dir/kill.log"
out=$(reap --close 801 801); rc=$?
check "a duplicate id signals once" '(( rc == 0 )) && [[ $(grep -c -- "-TERM 801" "$dir/kill.log") == 1 ]]'
: > "$dir/kill.log"
out=$(reap --close 801 0801); rc=$?
check "801 and 0801 are one id: signalled once, as 801" '(( rc == 0 )) && [[ $(grep -c -- "-TERM" "$dir/kill.log") == 1 ]] && grep -qx -- "-TERM 801" "$dir/kill.log"'
: > "$dir/kill.log"
for bad in +101 -101 0x65 1e2 " 101" 0 000 12345678901 101$'\n'; do
  out=$(reap --close "$bad"); rc=$?
  check "malformed pid '$(printf %s "$bad" | tr -d '\n')': exit 2, nothing signalled" '(( rc == 2 )) && [[ ! -s $dir/kill.log ]]'
done
out=$(SABHA_ANCESTORS=801 reap --close 801); rc=$?
check "a pid in the command's own process chain is refused" '(( rc == 1 )) && grep -q "refused 801: it runs this command" <<<"$out" && [[ ! -s $dir/kill.log ]]'
out=$(SABHA_ANCESTORS=801 reap --close 0801); rc=$?
check "the own-process guard holds for a leading-zero spelling" '(( rc == 1 )) && grep -q "it runs this command" <<<"$out" && [[ ! -s $dir/kill.log ]]'
out=$(SABHA_PS_FILE='' reap --close 801); rc=$?
check "SABHA_KILL without a fake process list is refused (test hook only)" '(( rc == 2 )) && grep -q "test hook" <<<"$out" && [[ ! -s $dir/kill.log ]]'

echo "--- close: panes"
: > "$FAKE_HERDR_LOG"
out=$(reapp --close w1:p1); rc=$?
check "a live pane (its role has a claude) is refused, and says so" '(( rc == 1 )) && grep -q "refused w1:p1: not an ORPHAN pane" <<<"$out" && no_close'
out=$(reapp --close w1:p6); rc=$?
check "a non-claude role pane (Coder, opencode) is refused, not an ORPHAN" '(( rc == 1 )) && grep -q "refused w1:p6: not an ORPHAN pane" <<<"$out" && no_close'
out=$(reapp --close w1:p8); rc=$?
check "a pane of a name outside the roster is refused" '(( rc == 1 )) && grep -q "refused w1:p8: not an ORPHAN pane" <<<"$out" && no_close'
for st in working blocked unknown; do
  out=$(FAKE_HERDR_STATUS="w1:p5=$st" reapp --close w1:p5); rc=$?
  check "an orphan herdr reports $st is refused" '(( rc == 1 )) && grep -q "refused w1:p5: herdr reports it $st; only an idle or done pane is closed" <<<"$out" && no_close'
done
out=$(FAKE_HERDR_STATUS="w1:p5=working" reapp); rc=$?
check "a busy orphan is listed as list only" '(( rc == 0 )) && grep "^ORPHAN " <<<"$out" | grep "Ghost" | grep -q "working: list only"'
out=$(HERDR_PANE_ID=w1:p5 reap --close w1:p5); rc=$?
check "the pane this command runs in (HERDR_PANE_ID) is refused" '(( rc == 1 )) && grep -q "refused w1:p5: it is the pane this command runs in" <<<"$out" && no_close'
out=$(reap --close w1:p5); rc=$?
check "HERDR_PANE_ID unset: every pane close is refused" '(( rc == 1 )) && grep -q "HERDR_PANE_ID is not set" <<<"$out" && no_close'
out=$(HERDR_PANE_ID='' reap --close w1:p5); rc=$?
check "HERDR_PANE_ID empty: every pane close is refused" '(( rc == 1 )) && grep -q "HERDR_PANE_ID is not set" <<<"$out" && no_close'
out=$(SABHA_TEST='' reapp --close w1:p5); rc=$?
check "a fake process list never closes a pane unless SABHA_TEST=1" '(( rc == 1 )) && grep -q "a fake process list never closes a pane" <<<"$out" && no_close'
out=$(FAKE_HERDR_PANELIST_OK_ONCE=1 reapp --close w1:p5); rc=$?
check "herdr stops answering between the list and the close: refused, nothing closed" '(( rc == 1 )) && grep -q "refused w1:p5: the pane is gone or herdr cannot list it now" <<<"$out" && no_close'
rm -f "$dir/fh/pl-once"
out=$(FAKE_HERDR_FAIL_CLOSE=1 reapp --close w1:p5 w1:p10); rc=$?
check "herdr pane close failing (pane gone): never reported as closed, exit 1, both named" '(( rc == 1 )) && [[ $(grep -c "could not close pane" <<<"$out") == 2 ]] && ! grep -q "closed pane" <<<"$out"'
: > "$FAKE_HERDR_LOG"
out=$(reapp --close w1:p5 w1:p5); rc=$?
check "an idle orphan is closed through herdr pane close, once for a duplicate id" '(( rc == 0 )) && grep -q "^closed pane w1:p5" <<<"$out" && [[ $(grep -cx "pane close w1:p5" "$FAKE_HERDR_LOG") == 1 ]]'
: > "$FAKE_HERDR_LOG"
out=$(reapp --close w1:p10); rc=$?
check "a done orphan is closed too" '(( rc == 0 )) && grep -qx "pane close w1:p10" "$FAKE_HERDR_LOG"'
out=$(FAKE_HERDR_GARBAGE=1 reapp); rc=$?
check "herdr answering exit 0 with non-pane output: no orphans, problem said" '(( rc == 0 )) && ! grep -q "^ORPHAN" <<<"$out" && grep -q "could not read herdr panes" <<<"$out"'

echo "--- close: ambiguous panes and names that differ by case"
cp "$map" "$dir/map.keep"; cp "$dir/ps.txt" "$dir/ps.keep"
export FAKE_HERDR_PANES="w1:p1 w1:p5 w1:p6" FAKE_HERDR_STATUS="w1:p5=idle w1:p6=idle"
printf 'Relay w1:p1\nGhost w1:p5\nBuilder w1:p5\n' > "$map"
: > "$FAKE_HERDR_LOG"
out=$(reapp); rc=$?
check "two map rows name one pane (a live Builder is one): listed AMBIGUOUS, never closable" '(( rc == 0 )) && grep "^AMBIGUOUS " <<<"$out" | grep "w1:p5" | grep -q "Ghost w1:p5 / Builder w1:p5" && ! grep "^ORPHAN" <<<"$out" | grep -q "w1:p5"'
out=$(reapp --close w1:p5); rc=$?
check "two map rows one pane, one of them live: close refused, reason names both rows, nothing closed" '(( rc == 1 )) && grep -q "refused w1:p5: AMBIGUOUS.*Ghost w1:p5 / Builder w1:p5" <<<"$out" && no_close'
printf 'Relay w1:p1\nGhost w1:p5\nGhost2 w1:p5\n' > "$map"
out=$(reapp --close w1:p5); rc=$?
check "two map rows one pane, neither live: close refused as AMBIGUOUS naming both" '(( rc == 1 )) && grep -q "refused w1:p5: AMBIGUOUS.*Ghost w1:p5 / Ghost2 w1:p5" <<<"$out" && no_close'
printf 'Relay w1:p1\nGhost w1:p5\nGhost w1:p5\n' > "$map"
out=$(reapp --close w1:p5); rc=$?
check "the same row twice: close refused as AMBIGUOUS" '(( rc == 1 )) && grep -q "refused w1:p5: AMBIGUOUS" <<<"$out" && no_close'
printf 'Relay w1:p1\nGhost w1:p5\nghost w1:p6\n' > "$map"
out=$(reapp --close w1:p5 w1:p6); rc=$?
check "one role named twice (any case): both its panes refused as AMBIGUOUS" '(( rc == 1 )) && [[ $(grep -c "^refused .*AMBIGUOUS" <<<"$out") == 2 ]] && no_close'
printf 'Relay w1:p1\nGhost w1:p5\n' > "$map"
out=$(reapp --close w1:p5); rc=$?
check "control: one row, no live session: the orphan still closes" '(( rc == 0 )) && grep -q "^closed pane w1:p5" <<<"$out"'
: > "$FAKE_HERDR_LOG"
printf '  103 ttys009  Tue Oct 13 09:30:00 2026     claude -n relay --model opus\n' > "$dir/ps.txt"
printf 'Relay w1:p1\nGhost w1:p5\n' > "$map"
out=$(reapp); rc=$?
check "a live claude -n relay (lower case) keeps the Relay pane out of the ORPHAN rows" '(( rc == 0 )) && ! grep "^ORPHAN" <<<"$out" | grep -q "Relay" && grep "^103 " <<<"$out" | grep -q "only copy"'
out=$(reapp --close w1:p1); rc=$?
check "the pane of a session whose name differs by case only is refused" '(( rc == 1 )) && grep -q "refused w1:p1: not an ORPHAN pane" <<<"$out" && no_close'
printf '  101 ttys004  Tue Oct 13 09:00:01 2026     claude -n Relay --model opus\n  103 ttys009  Tue Oct 13 09:30:00 2026     claude -n relay --model opus\n' > "$dir/ps.txt"
: > "$dir/kill.log"
out=$(reap --close 101); rc=$?
check "Relay and relay are one role: closing one of the two is allowed" '(( rc == 0 )) && grep -qx -- "-TERM 101" "$dir/kill.log"'
cp "$dir/ps.keep" "$dir/ps.txt"; cp "$dir/map.keep" "$map"
export FAKE_HERDR_PANES="w1:p1 w1:p2 w1:p5 w1:p6 w1:p8 w1:p10" FAKE_HERDR_STATUS="w1:p5=idle w1:p6=idle w1:p8=idle w1:p10=done"
: > "$FAKE_HERDR_LOG"
out=$(HERDR_PANE_ID=W1:P5 reap --close w1:p5); rc=$?
check "the own-pane guard ignores case" '(( rc == 1 )) && grep -q "refused w1:p5: it is the pane this command runs in" <<<"$out" && no_close'

echo "--- close: ps shows no named claude"
cp "$dir/ps.txt" "$dir/ps.full"
printf '  900 ttys007  Tue Oct 13 12:00:00 2026     grep claude -n Builder\n' > "$dir/ps.txt"
: > "$FAKE_HERDR_LOG"
out=$(reapp); rc=$?
check "no named claude in ps: no ORPHAN rows, says why" '(( rc == 0 )) && ! grep -q "^ORPHAN" <<<"$out" && grep -q "ps shows no named claude session" <<<"$out"'
out=$(reapp --close w1:p5 w1:p1 w1:p2); rc=$?
check "no named claude in ps: every pane close is refused" '(( rc == 1 )) && [[ $(grep -c "ps shows no named claude session, so no pane can be called dead" <<<"$out") == 3 ]] && no_close'
: > "$dir/ps.txt"
out=$(reapp --close w1:p5); rc=$?
check "an empty ps list: the pane close is refused" '(( rc == 1 )) && grep -q "ps shows no named claude session" <<<"$out" && no_close'
mv "$dir/ps.full" "$dir/ps.txt"

echo "--- herdr down"
rm -f "$dir/fh/server-sabha"
out=$(reap); rc=$?
check "no herdr server: rows still listed, pane problem said, exit 0" '(( rc == 0 )) && grep -q "^802 " <<<"$out" && grep -q "could not read herdr panes" <<<"$out" && ! grep -q "^ORPHAN" <<<"$out"'
: > "$FAKE_HERDR_LOG"
out=$(reapp --close w1:p5); rc=$?
check "an unreadable pane list proves nothing: the pane id is refused as not an ORPHAN" '(( rc == 1 )) && grep -q "refused w1:p5: not an ORPHAN pane in the list above" <<<"$out" && no_close'

echo
(( fails == 0 )) && echo "all reap checks passed" || echo "$fails reap check(s) failed"
exit "$fails"
