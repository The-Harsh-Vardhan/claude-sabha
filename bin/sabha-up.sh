#!/usr/bin/env bash
# Opens one maximised iTerm2 window with two tabs of 4x2 panes, Build and Gate (roster flag "gate"), and starts one
# role per pane; the relay (first role) and on-demand roles are started by hand.
#   sabha-up.sh                 open the grid
#   sabha-up.sh <Name>          start one role in the current terminal (each pane runs this)
#   sabha-up.sh --print <Name>  print that role's one-line restart command and exit
#   on-demand roles (roster flag "ondemand") have no pane: start them with sabha-up.sh <Name>
#   --force (first argument)    start even when a claude process already holds a role's name
# Run it from a plain terminal: osascript is blocked inside a Claude sandbox.
# Paths and names come from sabha.conf (SABHA_CONF, else ../sabha.conf beside this script).
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# shellcheck source=sabha-lib.sh
. "$(dirname "$SELF")/sabha-lib.sh"
sabha_load sabha-up
PROJECT=${SABHA_PROJECT:-this project}
OWNER=${SABHA_USER:-the user}
PROTOCOL=$SABHA_IMPL/PROTOCOL.md

FORCE=0
[[ ${1:-} == --force ]] && { FORCE=1; shift; }

# refuses to start a role that a live claude process already holds; --force skips the check
guard() {
  (( FORCE )) && return 0
  local live procs
  procs=$(sabha_procs) || { echo "sabha-up: cannot read the process list; pass --force to start without the check" >&2; exit 1; }
  live=$(awk -v want=" $* " 'index(want, " " $1 " ") { print "  " $0 }' <<<"$procs")
  [[ -z $live ]] && return 0
  echo "sabha-up: already running (name pid tty start):" >&2
  echo "$live" >&2
  echo "sabha-up: stop them first (sabha-down.sh, or /exit in the tab), or pass --force" >&2
  exit 1
}

role() {
  for r in "${ROLES[@]}"; do
    read -r name model effort flags <<<"$r"
    [[ $name == "$1" ]] || continue
    lower=$(tr '[:upper:]' '[:lower:]' <<<"$name")
    to=$DISPATCHER
    [[ $name == "$DISPATCHER" ]] && to=$RELAY
    [[ $name == "$RELAY" ]] && to=$OWNER
    # SABHA_PROMPT_<Name> in sabha.conf replaces what follows the status file (an on-demand role's own job)
    tail_var=SABHA_PROMPT_$name
    tail="then inbox/$name/ (ack any brief without an ack; resume any brief with an ack and no done), and continue from the status file's Next line. Report to $to."
    [[ -n ${!tail_var:-} ]] && tail=${!tail_var}
    # SABHA_PROTOCOL_CORE (file under SABHA_IMPL) + SABHA_ROLE_DIR (folder of <Name>.md) split the protocol: core, the role file, then the top block of the status file
    reads="$PROTOCOL, then status/$lower.md"
    [[ -n ${SABHA_PROTOCOL_CORE:-} && -n ${SABHA_ROLE_DIR:-} ]] &&
      reads="$SABHA_IMPL/$SABHA_PROTOCOL_CORE, then $SABHA_IMPL/$SABHA_ROLE_DIR/$name.md, then the top block of status/$lower.md"
    prompt="You are $name in $PROJECT session setup. First run ListAgents: if another live row has the name $name, append a restart item to $SABHA_IMPL/for-me.items and stop. Then read $reads, $tail"
    return 0
  done
  echo "unknown role: $1" >&2; exit 1
}

if [[ ${1:-} == --print && $# -eq 2 ]]; then
  role "$2"
  # the line is pasted into zsh or bash, so a double quote, $ or backtick would break it
  [[ $prompt$SABHA_WS != *[\"\$\`]* ]] || { echo "sabha-up: config value holds a quote, \$ or backtick" >&2; exit 1; }
  mcp=""; sabha_flag "$r" mcp || mcp=" --strict-mcp-config"
  echo "cd \"$SABHA_WS\" && claude -n $name --model $model --effort $effort$mcp \"$prompt\""
  exit 0
fi

if [[ $# -eq 1 ]]; then
  role "$1"
  guard "$name"
  # iTerm2 badge: "Fable Medium"; macOS bash 3.2 has no ${v^}, hence awk
  if [[ ${LC_TERMINAL:-${TERM_PROGRAM:-}} == iTerm* ]]; then
    badge=$(awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)} 1' <<<"$model $effort")
    printf '\033]1337;SetBadgeFormat=%s\a' "$(printf %s "$badge" | base64)"
    # Homebrew colours: black background, green text; this pane only, the profile is untouched
    printf '\033]1337;SetColors=bg=000000\a\033]1337;SetColors=fg=00ff00\a\033]1337;SetColors=curbg=23ff18\a'
    # the toolbelt's session list shows the title; claude would replace the role name with its own
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
    printf '\033]0;%s\a' "$name"
  fi
  cd "$SABHA_WS"
  # MCP servers each cost memory and the roles do not use them; "mcp" in the roster flags keeps them
  mcp=(--strict-mcp-config); sabha_flag "$r" mcp && mcp=()
  exec claude -n "$name" --model "$model" --effort "$effort" ${mcp[@]+"${mcp[@]}"} "$prompt"
fi

# two tabs: Build takes the pane roles in roster order, Gate takes those flagged "gate"; each is two rows of up to four.
# Lazy roles get no pane here.
build=() gate=()
for r in "${ROLES[@]}"; do
  [[ " ${PANES[*]} " == *" ${r%% *} "* ]] || continue
  sabha_flag "$r" lazy && continue
  if sabha_flag "$r" gate; then gate+=("${r%% *}"); else build+=("${r%% *}"); fi
done
(( ${#build[@]} >= 1 && ${#build[@]} <= 8 && ${#gate[@]} <= 8 )) ||
  { echo "sabha-up: each tab holds up to 8 panes (Build has ${#build[@]}, Gate has ${#gate[@]})" >&2; exit 1; }
# the relay is already running when the grid opens, and on-demand roles have no pane, so only the panes are checked
guard "${build[@]}" ${gate[@]+"${gate[@]}"}
pane_args=""; (( FORCE )) && pane_args="--force "

# tab_script <prefix> <name>...: AppleScript that splits session <prefix>1 into two rows and starts one role per pane.
# A vertical split halves a pane, so 4 columns are made by halving twice (equal); 3 columns come out 1/2, 1/4, 1/4.
tab_script() {
  local p=$1 k=1 name cols; shift
  cols=$(( ($# + 1) / 2 ))
  case $cols in
    4) printf '    tell %s1 to set %s3 to (split vertically with default profile)\n' "$p" "$p"
       printf '    tell %s1 to set %s2 to (split vertically with default profile)\n' "$p" "$p"
       printf '    tell %s3 to set %s4 to (split vertically with default profile)\n' "$p" "$p" ;;
    3) printf '    tell %s1 to set %s2 to (split vertically with default profile)\n' "$p" "$p"
       printf '    tell %s2 to set %s3 to (split vertically with default profile)\n' "$p" "$p" ;;
    2) printf '    tell %s1 to set %s2 to (split vertically with default profile)\n' "$p" "$p" ;;
  esac
  for (( k = 1; k <= cols && cols + k <= $#; k++ )); do
    printf '    tell %s%d to set %s%d to (split horizontally with default profile)\n' "$p" "$k" "$p" $(( cols + k ))
  done
  k=1
  for name in "$@"; do
    printf '    tell %s%d\n      set name to "%s"\n      write text "%s"\n    end tell\n' "$p" "$k" "$name" "'$SELF' $pane_args$name"
    k=$(( k + 1 ))
  done
}
echo "sabha-up: tab Build $(( (${#build[@]} + 1) / 2 ))x2: ${build[*]}"
gate_tab=""
if (( ${#gate[@]} )); then
  echo "sabha-up: tab Gate $(( (${#gate[@]} + 1) / 2 ))x2: ${gate[*]}"
  gate_tab="  tell w
    set t2 to (create tab with default profile)
    set g1 to current session of t2
$(tab_script g "${gate[@]}")
  end tell
  tell first tab of w to select"
fi

osascript <<EOF
tell application id "com.googlecode.iterm2"
  activate
  set w to (create window with default profile)
  try
    tell application "Finder" to set b to bounds of window of desktop
    set bounds of w to {0, 25, item 3 of b, item 4 of b}
  end try
  tell w
    set b1 to current session
$(tab_script b "${build[@]}")
  end tell
$gate_tab
end tell
-- Toolbelt has no AppleScript verb; its menu item toggles, so click only when unticked (needs Accessibility for the terminal)
try
  tell application "System Events" to tell process "iTerm2"
    set mi to menu item "Show Toolbelt" of menu 1 of menu item "Toolbelt" of menu "View" of menu bar 1
    if value of attribute "AXMenuItemMarkChar" of mi is missing value then click mi
  end tell
on error e
  log "sabha-up: toolbelt not opened (" & e & "); press Cmd-Shift-B"
end try
EOF
