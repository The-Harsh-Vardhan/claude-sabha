#!/usr/bin/env bash
# bin/sabha-reap against a fake process list and the fake herdr only (tests/hermetic.sh): the list shows age, idle, ctx
# and pane state, marks STALE? copies and ORPHAN panes, and prints plain ASCII whatever ps or a file holds; --close acts
# only on ids named on the command line and never on a role's last live copy, an id not in the list, or a live pane.
# Run: tests/test-reap.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
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
unset SABHA_BACKEND SABHA_PLAN FAKE_HERDR_PANES FAKE_HERDR_FAIL_PANELIST
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo 'SABHA_ROSTER="Relay:opus:medium Builder:opus:medium"'; } > "$dir/sabha.conf"
map=$dir/impl/status/herdr-panes.txt
reap() { "$SH" "$ROOT/bin/sabha-reap" "$@" 2>&1; }

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
printf 'Relay w1:p1\nGhost w1:p5\nBuilder w1:p2\n' > "$map"
export FAKE_HERDR_PANES="w1:p1 w1:p2 w1:p5"
out=$(reap); rc=$?
check "Relay row shows its pane and state" 'grep "^101 " <<<"$out" | grep -q "w1:p1 *unknown"'
check "pane shown on the newest Builder copy only" 'grep "^802 " <<<"$out" | grep -q "w1:p2" && ! grep "^801 " <<<"$out" | grep -q "w1:p2"'
check "Ghost (no live claude) is an ORPHAN row" 'grep "^ORPHAN " <<<"$out" | grep -q "Ghost.*w1:p5"'
check "a role with a live claude is not an orphan" '(( $(grep -c "^ORPHAN" <<<"$out") == 1 ))'
check "listing closes nothing and never signals" '! grep -q "pane close" "$FAKE_HERDR_LOG" && [[ ! -s $dir/kill.log ]]'
check "every herdr call carried --session" '! grep -qv "^--session sabha" "$FAKE_HERDR_CALLS"'

echo "--- close"
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
out=$(reap --close w1:p1); rc=$?
check "a live pane (its role has a claude) is refused" '(( rc == 1 )) && ! grep -q "pane close" "$FAKE_HERDR_LOG"'
: > "$FAKE_HERDR_LOG"
out=$(reap --close w1:p5); rc=$?
check "an orphan pane is closed through herdr pane close" '(( rc == 0 )) && grep -qx "pane close w1:p5" "$FAKE_HERDR_LOG"'

echo "--- herdr down"
rm -f "$dir/fh/server-sabha"
out=$(reap); rc=$?
check "no herdr server: rows still listed, pane problem said, exit 0" '(( rc == 0 )) && grep -q "^802 " <<<"$out" && grep -q "could not read herdr panes" <<<"$out" && ! grep -q "^ORPHAN" <<<"$out"'
: > "$FAKE_HERDR_LOG"
out=$(reap --close w1:p5); rc=$?
check "an unreadable pane list proves nothing: the pane id is refused" '(( rc == 1 )) && ! grep -q "pane close" "$FAKE_HERDR_LOG"'

echo
(( fails == 0 )) && echo "all reap checks passed" || echo "$fails reap check(s) failed"
exit "$fails"
