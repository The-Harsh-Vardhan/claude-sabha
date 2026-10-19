#!/usr/bin/env bash
# sabha-check, sabha-down.sh (dry run) and the sabha-up.sh guard against a fake process list: duplicates are found,
# the relay is never in the kill list, the dry run writes nothing, and the guard stops a second start.
# claude and osascript are stubs, so nothing is launched or killed. Run: tests/test-procs.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-procs.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/inbox" "$dir/ws" "$dir/stubs"
cat > "$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$dir/impl
SABHA_ROSTER="Relay:opus:medium Dispatcher:opus:medium Architect:fable:medium BuilderHeavy:opus:high BuilderPrecise:opus:medium Reviewer:sonnet:high Writer:sonnet:medium Scribe:haiku:high Housekeeper:haiku:medium"
EOF
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
# osascript: a heredoc script (sabha-up) is echoed; an -e script (sabha-down) is logged, answers SABHA_LIST from
# FAKE_WINDOWS, and a nudge to a role in FAKE_SAVERS writes that brief's .done, as the tab would
cat > "$dir/stubs/osascript" <<'STUB'
#!/bin/sh
if [ "$1" != -e ]; then echo "STUB osascript $*"; [ -t 0 ] || cat; exit 0; fi
case $2 in
  *SABHA_LIST*) cat "$FAKE_WINDOWS" ;;
  *"write text"*)
    set -- $(printf '%s\n' "$2" | sed -n 's/.*tty of s is "\([^"]*\)".*see inbox\/\([A-Za-z]*\)\/\([0-9]*\).*/\1 \2 \3/p')
    echo "NUDGE $1 $2 $3" >> "$ACTLOG"
    case " $FAKE_SAVERS " in *" $2 "*) : > "$IMPL/inbox/$2/$3.done" ;; esac ;;
  *"close w"*) echo "CLOSE $(printf '%s\n' "$2" | sed -n 's/.*if id of w is \([0-9]*\).*/\1/p')" >> "$ACTLOG" ;;
esac
STUB
# kill: logged; -0 says the pid is gone, so no KILL follows
printf '#!/bin/sh\necho "KILL $*" >> "$ACTLOG"; [ "$1" != -0 ]\n' > "$dir/stubs/fakekill"
chmod +x "$dir/stubs/claude" "$dir/stubs/osascript" "$dir/stubs/fakekill"

# ps -axo pid=,tty=,lstart=,command=
cat > "$dir/ps.txt" <<'EOF'
  101 ttys004  Tue Oct 13 09:00:01 2026     claude -n Relay --model opus --effort medium You are Relay
  102 ttys010  Tue Oct 13 17:30:00 2026     /opt/bin/claude --name Relay --model opus
  201 ttys003  Tue Oct 13 17:42:08 2026     claude -n Dispatcher --model opus --effort medium You are Dispatcher
  301 ttys009  Tue Oct 13 17:42:08 2026     claude -n Writer --model sonnet --effort medium You are Writer
  302 ??       Tue Oct 13 15:00:00 2026     claude --name=Writer --bg
  401 ttys007  Tue Oct 13 17:42:08 2026     claude -n BuilderPrecise --model opus --effort medium You are BuilderPrecise, run sabha -n BuilderHeavy
  501 ttys004  Tue Oct 13 17:50:00 2026     claude -n Reviewer --model sonnet
  601 ttys011  Tue Oct 13 17:00:00 2026     claude You are a session -n Architect
  701 ttys012  Tue Oct 13 17:00:00 2026     grep claude -n Scribe
  801 ttys013  Tue Oct 13 17:00:00 2026     claude
EOF
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH
# herdr is the default backend; these checks cover the iTerm/osascript path, so pin it (a real herdr on PATH must
# never be reached). The herdr path is checked against a fake herdr at the end.
export SABHA_BACKEND=iterm

out=$("$SH" "$BIN/sabha-check"); rc=$?
echo "--- sabha-check (rc $rc)"; echo "$out"
check "sabha-check exits 1 on a duplicate" '(( rc == 1 ))'
check "Writer (-n and --name=) is DUPLICATE" '(( $(grep -c "^Writer .*DUPLICATE" <<<"$out") == 2 ))'
check "Relay (-n and --name) is DUPLICATE" '(( $(grep -c "^Relay .*DUPLICATE" <<<"$out") == 2 ))'
check "BuilderPrecise single, not DUPLICATE" 'grep -q "^BuilderPrecise .*401 " <<<"$out" && ! grep -q "^BuilderPrecise .*DUPLICATE" <<<"$out"'
check "-n inside a prompt names nothing (BuilderHeavy, Architect)" 'grep -q "^BuilderHeavy .*not running" <<<"$out" && grep -q "^Architect .*not running" <<<"$out"'
check "grep and unnamed claude ignored (Scribe)" 'grep -q "^Scribe .*not running" <<<"$out"'

out=$("$SH" "$BIN/sabha-down.sh"); rc=$?
echo "--- sabha-down.sh dry run (rc $rc)"; echo "$out"
kill_list=$(sed -n '/^kill list/,/^would close/p' <<<"$out")
check "dry run exits 0" '(( rc == 0 ))'
check "kill list holds both Writer copies, Dispatcher and BuilderPrecise" '(for p in 301 302 201 401; do grep -q " $p " <<<"$kill_list" || exit 1; done)'
check "relay never in the kill list (pids 101, 102)" '! grep -qE "^  Relay| 10[12] " <<<"$kill_list"'
check "a role on the relay tty is spared (Reviewer 501 on ttys004)" '! grep -q " 501 " <<<"$kill_list"'
check "dry run writes nothing" '[[ -z $(find "$dir/impl/inbox" -type f) ]]'
check "dry run sends one brief per role, numbered 001" 'grep -q "inbox/Writer/001-sabha-down-save-handoff.md (would write)" <<<"$out" && (( $(grep -c "^save brief" <<<"$out") == 3 ))'
check "a background copy gets no nudge and no window" 'grep -q "on no terminal" <<<"$out" && ! grep -q "/dev/??" <<<"$out"'
check "osascript not called in a dry run" '! grep -q STUB <<<"$out"'

out=$("$SH" "$BIN/sabha-up.sh" BuilderPrecise 2>&1); rc=$?
echo "--- sabha-up.sh BuilderPrecise (rc $rc)"; echo "$out"
check "guard stops a second BuilderPrecise" '(( rc == 1 )) && grep -q "401 ttys007" <<<"$out" && ! grep -q STUB <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" BuilderHeavy 2>&1); rc=$?
check "a free role starts (stub claude)" '(( rc == 0 )) && grep -q "STUB claude -n BuilderHeavy" <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" --force BuilderPrecise 2>&1); rc=$?
check "--force skips the guard" '(( rc == 0 )) && grep -q "STUB claude -n BuilderPrecise" <<<"$out"'
out=$(SABHA_FORCE=1 "$SH" "$BIN/sabha-up.sh" BuilderPrecise 2>&1); rc=$?
check "SABHA_FORCE=1 (set by a grid --force, through sabha-loop) skips the guard" '(( rc == 0 )) && grep -q "STUB claude -n BuilderPrecise" <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "grid guard lists the running pane roles, ignores the relay" '(( rc == 1 )) && grep -q "Writer 302" <<<"$out" && ! grep -q "Relay" <<<"$out" && ! grep -q STUB <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" --force 2>&1); rc=$?
check "grid --force passes SABHA_FORCE=1 to the panes' sabha-loop" '(( rc == 0 )) && grep -q "SABHA_FORCE=1 .*/bin/sabha-loop. Dispatcher\"" <<<"$out"'
: > "$dir/ps-empty.txt"
out=$(SABHA_PS_FILE=$dir/ps-empty.txt "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "grid opens when nothing runs" '(( rc == 0 )) && grep -q "STUB osascript" <<<"$out"'

# herdr backend, fake herdr on PATH: --force reaches the panes there too, and a free grid opens a workspace
mkdir -p "$dir/fh"; cp "$BIN/../tests/fake-herdr.sh" "$dir/stubs/herdr"; chmod +x "$dir/stubs/herdr"; export SABHA_HERDR_BIN=$dir/stubs/herdr
export FAKE_HERDR_LOG=$dir/herdr.log FAKE_HERDR_DIR=$dir/fh FAKE_HERDR_CALLS=$dir/calls
: > "$FAKE_HERDR_LOG"
out=$(SABHA_BACKEND=herdr "$SH" "$BIN/sabha-up.sh" --force 2>&1); rc=$?
check "herdr: grid --force passes SABHA_FORCE=1 to the panes' sabha-loop" '(( rc == 0 )) && grep -q "^pane run w1:p[0-9]* SABHA_FORCE=1 .*/bin/sabha-loop. Dispatcher$" "$FAKE_HERDR_LOG"'
: > "$FAKE_HERDR_LOG"
out=$(SABHA_BACKEND=herdr SABHA_PS_FILE=$dir/ps-empty.txt "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "herdr: grid opens when nothing runs, panes get no --force" '(( rc == 0 )) && grep -q "^workspace create" "$FAKE_HERDR_LOG" && ! grep -q -- "--force" "$FAKE_HERDR_LOG"'

# sabha-down on the herdr backend stops the sabha session and no other one; a dry run only says so
: > "$dir/calls"
out=$(env -u CLAUDECODE SABHA_BACKEND=herdr SABHA_PS_FILE=$dir/ps-empty.txt "$SH" "$BIN/sabha-down.sh" 2>&1); rc=$?
check "herdr: sabha-down dry run says it would stop the session and calls nothing" '(( rc == 0 )) && grep -q "would stop and delete the herdr session sabha" <<<"$out" && [[ ! -s $dir/calls ]]'
out=$(env -u CLAUDECODE SABHA_BACKEND=herdr SABHA_KILL=fakekill SABHA_PS_FILE=$dir/ps-empty.txt "$SH" "$BIN/sabha-down.sh" --yes 2>&1); rc=$?
check "herdr: sabha-down --yes stops then deletes session sabha, no other session" '(( rc == 0 )) && grep -qx "session stop sabha" "$dir/calls" && grep -qx "session delete sabha" "$dir/calls" && [[ $(wc -l <"$dir/calls" | tr -d " ") == 2 ]]'
out=$(env -u CLAUDECODE SABHA_BACKEND=herdr SABHA_HERDR_SESSION=mine SABHA_KILL=fakekill SABHA_PS_FILE=$dir/ps-empty.txt "$SH" "$BIN/sabha-down.sh" --yes 2>&1); : > "$dir/x"
check "herdr: SABHA_HERDR_SESSION picks the session to stop" 'grep -qx "session stop mine" "$dir/calls" && ! tail -2 "$dir/calls" | grep -q "session stop sabha"'

# --- --yes, with kill and osascript stubbed (008: M1, S1-S6)
export IMPL=$dir/impl ACTLOG=$dir/act.log FAKE_WINDOWS=$dir/windows.txt SABHA_KILL_GRACE=0
# window 1 holds only Dispatcher's pane; 2 holds Writer (who does not save) and another pane; 3 is the relay's;
# 4 holds BuilderPrecise's pane beside the user's own tab, which ps cannot see
printf '%s\n' "1 /dev/ttys003" "2 /dev/ttys009 /dev/ttys005" "3 /dev/ttys004" "4 /dev/ttys007 /dev/ttys020" > "$FAKE_WINDOWS"
yes_run() { rm -rf "$dir/impl/inbox"; mkdir -p "$dir/impl/inbox"; : > "$ACTLOG"
  out=$(env -u CLAUDECODE SABHA_KILL=fakekill FAKE_SAVERS="$1" "$SH" "$BIN/sabha-down.sh" --yes --timeout 1 ${2:+"$2"} 2>&1); rc=$?; act=$(cat "$ACTLOG"); }

yes_run "Dispatcher BuilderPrecise"
echo "--- sabha-down.sh --yes, Writer does not save (rc $rc)"; echo "$out"; echo "$act"
kills=$(grep '^KILL -TERM' <<<"$act")
check "one claim and one brief per running role" '(( $(find "$dir/impl/inbox" -name "001.claim" | wc -l) == 3 && $(find "$dir/impl/inbox" -name "001-sabha-down-save-handoff.md" | wc -l) == 3 ))'
check "a nudge per real tty, none for the background copy" '(( $(grep -c ^NUDGE <<<"$act") == 3 )) && ! grep -q "NUDGE ??" <<<"$act"'
check "TERM goes to the saved roles only (201, 401)" '[[ $kills == "KILL -TERM 201 401" ]]'
check "never the relay, its tty, or the unsaved role (101 102 501 301 302)" '! grep -qE " (101|102|501|301|302)( |$)" <<<"$kills"'
check "unsaved role listed and exit 1" '(( rc == 1 )) && grep -q "left running, no save: Writer" <<<"$out"'
check "M1: only the window whose every session was killed is closed (1)" '[[ $(grep ^CLOSE <<<"$act") == "CLOSE 1" ]]'

yes_run "" --kill-unsaved
kills=$(grep '^KILL -TERM' <<<"$act")
check "--kill-unsaved stops all four, still not the relay or its tty" '(( rc == 0 )) && [[ $kills == "KILL -TERM 201 301 302 401" ]]'
check "--kill-unsaved still closes only window 1 (2 holds ttys005, 4 the user tab)" '[[ $(grep ^CLOSE <<<"$act" | tr "\n" " ") == "CLOSE 1 " ]]'

: > "$ACTLOG"
out=$(CLAUDECODE=1 SABHA_KILL=fakekill "$SH" "$BIN/sabha-down.sh" --yes 2>&1); rc=$?
check "S6: --yes refused inside a Claude session" '(( rc == 2 )) && grep -q "inside a Claude session" <<<"$out" && [[ ! -s $ACTLOG ]]'
out=$(env -u CLAUDECODE -u SABHA_KILL "$SH" "$BIN/sabha-down.sh" --yes 2>&1); rc=$?
check "S1: --yes with a fake list and no SABHA_KILL refused" '(( rc == 2 )) && grep -q "needs SABHA_KILL" <<<"$out" && [[ ! -s $ACTLOG ]]'

rm -rf "$dir/impl/inbox"; mkdir -p "$dir/impl/inbox/Dispatcher"; chmod 500 "$dir/impl/inbox/Dispatcher"
out=$(env -u CLAUDECODE SABHA_KILL=fakekill FAKE_SAVERS="" "$SH" "$BIN/sabha-down.sh" --yes --timeout 1 2>&1); rc=$?
chmod 700 "$dir/impl/inbox/Dispatcher"
check "S3: an unwritable inbox stops the claim loop, nothing killed" '(( rc == 2 )) && grep -q "cannot claim" <<<"$out" && ! grep -q "^KILL" "$ACTLOG"'

for s in sabha-check sabha-down.sh; do
  out=$(SABHA_PS_FILE=$dir/missing "$SH" "$BIN/$s" 2>&1); rc=$?
  check "S5: $s stops with rc 2 when the process list cannot be read" '(( rc == 2 )) && grep -q "cannot read the process list" <<<"$out"'
done
out=$(SABHA_PS_FILE=$dir/missing "$SH" "$BIN/sabha-up.sh" BuilderPrecise 2>&1); rc=$?
check "S5: sabha-up guard stops when the process list cannot be read" '(( rc == 1 )) && grep -q "cannot read the process list" <<<"$out" && ! grep -q STUB <<<"$out"'
check "S5: sabha-check prints the ListAgents footer" '"$SH" "$BIN/sabha-check" | grep -q "cross-check ListAgents"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
