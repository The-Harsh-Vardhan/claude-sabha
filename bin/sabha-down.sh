#!/usr/bin/env bash
# Clean shutdown of the grid: asks every running pane role to save its status file (a brief in its inbox, typed into
# its iTerm2 pane as a nudge), waits for the .done files, kills the claude processes of the roles that saved
# (duplicates and background copies too), then closes each iTerm2 window whose every session was one of them.
#   sabha-down.sh                                       dry run: print what it would send, wait for, kill and close
#   sabha-down.sh --yes [--timeout S] [--kill-unsaved]  do it; S seconds for the saves (SABHA_DOWN_TIMEOUT, else 300)
# A role with no .done at the timeout is listed and left running (exit 1) unless --kill-unsaved is given.
# The relay (first role) is never asked or killed: not by name, not on its tty, not as this script's ancestor. A
# window is closed only when all its sessions are killed panes, so the relay's tab and the user's own tab survive
# even when ps cannot see them. ps sees only sessions started with -n/--name; cross-check ListAgents.
# Run it from a plain terminal: osascript is blocked inside a Claude sandbox, and --yes refuses to run inside a
# Claude session (CLAUDECODE set), since a kill there needs a go: line (docs/inbox-protocol.md section 6).
# On the herdr backend (the default) it also stops and deletes the sabha herdr session (SABHA_HERDR_SESSION, default
# "sabha") and no other session, once nothing is left running; the iTerm2 steps above are macOS-only (no Linux or
# Windows fallback for the window closing; the process kill is portable).
# Tests: SABHA_PS_FILE replaces the process list (see sabha-lib.sh); with --yes it needs SABHA_KILL (a stub for
# kill) so a fake list is never signalled for real. SABHA_KILL_GRACE is the TERM-to-KILL wait (default 3 s).
set -uo pipefail

# shellcheck source=sabha-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/sabha-lib.sh"
# shellcheck source=sabha-herdr.sh
. "$(dirname "$0")/sabha-herdr.sh"
sabha_load sabha-down

YES=0 KILL_UNSAVED=0 TIMEOUT=${SABHA_DOWN_TIMEOUT:-300}
while (( $# )); do
  case $1 in
    --yes) YES=1 ;;
    --kill-unsaved) KILL_UNSAVED=1 ;;
    --timeout) TIMEOUT=${2:?--timeout needs seconds}; shift ;;
    *) echo "usage: sabha-down.sh [--yes] [--timeout seconds] [--kill-unsaved]" >&2; exit 2 ;;
  esac
  shift
done
KILL=${SABHA_KILL:-kill}
if (( YES )); then
  [[ -n ${CLAUDECODE:-} ]] && { echo "sabha-down: --yes refused inside a Claude session; run it from a plain terminal" >&2; exit 2; }
  [[ -n ${SABHA_PS_FILE:-} && -z ${SABHA_KILL:-} ]] && { echo "sabha-down: --yes with SABHA_PS_FILE needs SABHA_KILL (a fake list is never signalled)" >&2; exit 2; }
else
  echo "sabha-down: DRY RUN (pass --yes to act)"
fi
[[ $(sabha_backend) == herdr ]] && { sabha_session_valid || exit 2; }
# stop_session: the sabha herdr session only; a dry run says what it would do
stop_session() {
  [[ $(sabha_backend) == herdr ]] || return 0
  if (( YES )); then
    sabha_session_stop && echo "herdr session $(sabha_session) stopped and deleted (no other session touched)" || echo "herdr session $(sabha_session) not stopped: close it by hand"
  else
    echo "would stop and delete the herdr session $(sabha_session) (no other session)"
  fi
}
FOOTER="(ps sees only claude -n/--name sessions; cross-check ListAgents)"

procs=$(sabha_procs) || { echo "sabha-down: cannot read the process list; nothing done" >&2; exit 2; }
relay_ttys=" $(awk -v r="$RELAY" '$1 == r { printf "%s ", $3 }' <<<"$procs")"
# this script's own ancestors, so a run from inside a pane never kills the shell running it
ancestors=" $$ "
if [[ -z ${SABHA_PS_FILE:-} ]]; then
  p=$PPID
  while (( p > 1 )); do ancestors+="$p "; p=$(ps -o ppid= -p "$p" | tr -d ' '); [[ -n $p ]] || break; done
fi

# targets: "name pid tty day time" for every grid role, minus anything tied to the relay or to this script
targets() {
  awk -v want=" ${NAMES[*]:1} " -v relay="$RELAY" -v rt="$relay_ttys" -v anc="$ancestors" '
    index(want, " " $1 " ") && $1 != relay && !index(rt, " " $3 " ") && !index(anc, " " $2 " ")' <<<"$1"
}
victims=$(targets "$procs")
if [[ -z $victims ]]; then echo "sabha-down: no grid role is running $FOOTER"; stop_session; exit 0; fi

# 1. one save brief per running role (a duplicated role gets one brief, every copy of it gets the nudge)
utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
roles=() pending=()
# shellcheck disable=SC2013  # role names are single words
for name in $(awk '{ print $1 }' <<<"$victims" | awk '!seen[$0]++'); do
  dir=$SABHA_IMPL/inbox/$name
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$name")
  # shellcheck disable=SC2010  # names are NNN.claim and NNN-<from>-<slug>.md, plain ASCII by the protocol
  n=$(ls "$dir" 2>/dev/null | grep -E '^[0-9]{3}[.-]' | cut -c1-3 | sort | tail -1)
  n=$(printf '%03d' $(( 10#${n:-0} + 1 )))
  if (( YES )); then
    mkdir -p "$dir"
    # a claim that fails for another reason than "taken" (unwritable inbox, full disk) must not loop forever
    tries=0
    until (set -C; : > "$dir/$n.claim") 2>/dev/null; do
      (( ++tries < 50 )) || { echo "sabha-down: cannot claim a brief number in $dir; nothing killed" >&2; exit 2; }
      n=$(printf '%03d' $(( 10#$n + 1 )))
    done
    cat > "$dir/$n-sabha-down-save-handoff.md" <<EOF
to: $name
from: sabha-down
utc: $utc
task: save progress and handoff, then stop
output: status/$lower.md
reply: done

The sabha is shutting down. Write your handoff to status/$lower.md in the PROTOCOL-core.md handoff shape (mid-task: Next is the
exact resume point), then write $n.done. Start no new work; this tab is closed after the save.
EOF
  fi
  echo "save brief: inbox/$name/$n-sabha-down-save-handoff.md$( (( YES )) || echo ' (would write)')"
  roles+=("$name") pending+=("$dir/$n.done")
  # shellcheck disable=SC2013  # tty names are single words
  for tty in $(awk -v n="$name" '$1 == n { print $3 }' <<<"$victims"); do
    if [[ $tty == "??" ]]; then
      echo "  a copy on no terminal (background): no pane to nudge, it is only killed"
    elif (( YES )); then
      osascript -e "tell application id \"com.googlecode.iterm2\"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if tty of s is \"/dev/$tty\" then tell s to write text \"see inbox/$name/$n\"
            end repeat
          end repeat
        end repeat
      end tell" >/dev/null 2>&1 || echo "  nudge to $tty failed: tell $name 'see inbox/$name/$n' by hand"
    else
      echo "  would type 'see inbox/$name/$n' into the iTerm2 pane on $tty"
    fi
  done
done

# 2. wait for the saves; a role is killed only once its .done exists (or with --kill-unsaved)
saved=" " unsaved=""
if (( YES )); then
  end=$(( $(date +%s) + TIMEOUT ))
  while :; do
    saved=" " unsaved=""
    for i in "${!roles[@]}"; do
      if [[ -e ${pending[i]} ]]; then saved+="${roles[i]} "; else unsaved+="${roles[i]} "; fi
    done
    [[ -z $unsaved ]] && { echo "all saves done"; break; }
    (( $(date +%s) >= end )) && { echo "timeout after ${TIMEOUT}s, no done from: $unsaved"; break; }
    sleep 1
  done
  (( KILL_UNSAVED )) && saved=" ${roles[*]} "
else
  echo "would wait up to ${TIMEOUT}s for ${#pending[@]} .done file(s); a role without one is not killed"
  saved=" ${roles[*]} "
fi

# 3. kill the saved roles, read afresh after the wait (a role started meanwhile got no brief, so it is not saved)
(( YES )) && { procs=$(sabha_procs) || { echo "sabha-down: cannot read the process list; nothing killed" >&2; exit 2; }; }
victims=$(targets "$procs" | awk -v s="$saved" 'index(s, " " $1 " ")')
echo "kill list (name pid tty start) $FOOTER:"
if [[ -z $victims ]]; then echo "  none"; else awk '{ print "  " $0 }' <<<"$victims"; fi
[[ -n $unsaved && $KILL_UNSAVED == 0 ]] && echo "left running, no save: $unsaved(re-run with --kill-unsaved to stop them anyway)"
pids=$(awk '{ print $2 }' <<<"$victims")
ttys=" $(awk '$3 != "??" { printf "/dev/%s ", $3 }' <<<"$victims")"

# 4. which windows to close: those whose every session is a killed pane (read before the kill, while the panes exist)
close=""
if (( YES )) && [[ -n ${ttys// /} ]]; then
  layout=$(osascript -e 'tell application id "com.googlecode.iterm2"
    -- SABHA_LIST: one line per window, its id then the tty of each session
    set out to ""
    repeat with w in windows
      set out to out & (id of w)
      repeat with t in tabs of w
        repeat with s in sessions of t
          set out to out & " " & (tty of s)
        end repeat
      end repeat
      set out to out & linefeed
    end repeat
    return out
  end tell' 2>/dev/null) || echo "reading the iTerm2 windows failed: no window is closed"
  close=$(awk -v hit="$ttys" 'NF > 1 { all = 1; for (i = 2; i <= NF; i++) if (!index(hit, " " $i " ")) all = 0; if (all) printf "%s ", $1 }' <<<"${layout:-}")
fi

if (( YES )) && [[ -n $pids ]]; then
  # shellcheck disable=SC2086  # one pid per word
  $KILL -TERM $pids 2>/dev/null
  sleep "${SABHA_KILL_GRACE:-3}"
  for p in $pids; do $KILL -0 "$p" 2>/dev/null && $KILL -KILL "$p" 2>/dev/null && echo "  $p needed KILL"; done
fi

if (( YES )); then
  for id in $close; do
    osascript -e "tell application id \"com.googlecode.iterm2\"
      repeat with w in windows
        if id of w is $id then close w
      end repeat
    end tell" >/dev/null 2>&1 || echo "closing iTerm2 window $id failed: close it by hand"
  done
  close=${close% }; echo "closed iTerm2 window(s): ${close:-none} (only windows whose every session was a killed pane)"
elif [[ -n ${ttys// /} ]]; then
  echo "would close each iTerm2 window whose every session is one of:$ttys"
fi
[[ -n $unsaved && $KILL_UNSAVED == 0 ]] && exit 1
stop_session
exit 0
