#!/usr/bin/env bash
# Opens a herdr workspace with two tabs of 4x2 panes, Build and Gate (roster flag "gate"), and starts one
# role per pane; the relay (first role) and on-demand roles are started by hand. SABHA_BACKEND=iterm opens the old
# maximised iTerm2 window instead (macOS only, frozen); see bin/sabha-herdr.sh for the herdr backend.
#   sabha-up.sh                 open the grid
#   sabha-up.sh <Name>          start one role in the current terminal (each pane's sabha-loop runs this); a non-claude role
#                               (opencode, codex, agy, muse) is started in a new pane beside it, inside herdr
#   SABHA_REMOTE=1              pass --remote-control to Claude panes (default off; Pro/Max only, org policy may block)
#   sabha-up.sh --print <Name>  print that role's one-line restart command, then a "pane:" line with the sabha-loop
#                               command a grid pane runs for it, and exit
#   on-demand roles (roster flag "ondemand") have no pane: start them with sabha-up.sh <Name>
#   sabha-up.sh <Name>-N        a copy of that role (BuilderPrecise-2): same profile, its own inbox and status file
#   --plan pro|max5|max20       (first argument) roster, panes, copies and labels from sabha.<plan>.conf beside
#                               sabha.conf; SABHA_PANES names the roles that get a pane, the rest are on demand
#   --force (first argument)    start even when a claude process already holds a role's name
# Run it from a plain terminal: osascript (iterm backend) is blocked inside a Claude sandbox.
# Paths and names come from sabha.conf (SABHA_CONF, else ../sabha.conf beside this script).
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# shellcheck source-path=SCRIPTDIR source=sabha-lib.sh
. "$(dirname "$SELF")/sabha-lib.sh"
# shellcheck source-path=SCRIPTDIR source=sabha-herdr.sh
. "$(dirname "$SELF")/sabha-herdr.sh"
if [[ ${1:-} == --plan ]]; then
  [[ $# -ge 2 && -n $2 ]] || { echo "usage: sabha-up.sh --plan pro|max5|max20 [...]" >&2; exit 2; }
  export SABHA_PLAN=$2; shift 2
fi
sabha_load sabha-up
sabha_theme sabha-up || exit 1
[[ $(sabha_backend) == herdr ]] && { sabha_session_valid || exit 2; }
PROJECT=${SABHA_PROJECT:-this project}
OWNER=${SABHA_USER:-the user}

FORCE=0
# SABHA_FORCE=1 is how a grid started with --force passes it through sabha-loop to the role's sabha-up.sh
[[ ${SABHA_FORCE:-0} == 1 ]] && FORCE=1
[[ ${1:-} == --force ]] && { FORCE=1; shift; }
LOOP="$(dirname "$SELF")/sabha-loop"

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
  sabha_role "$1" || { echo "unknown role: $1" >&2; exit 1; }
  r=$R_ENTRY name=$R_NAME model=$R_MODEL effort=$R_EFFORT
  to=$DISPATCHER
  [[ $R_BASE == "$DISPATCHER" ]] && to=$RELAY
  [[ $R_BASE == "$RELAY" ]] && to=$OWNER
  who=$(sabha_who "$name")
  # SABHA_PROMPT_<Name> in sabha.conf replaces what follows the status file (an on-demand role's own job)
  tail_var=SABHA_PROMPT_$R_BASE
  tail="then inbox/$name/ (ack any brief without an ack; resume any brief with an ack and no done), and continue from the status file's Next line. Report to $to."
  [[ -n ${!tail_var:-} ]] && tail=${!tail_var}
  reads=$(sabha_reads "$name")
  prompt="You are $who in $PROJECT session setup. First run ListAgents: if another live row has the name $name, append a restart item to $SABHA_IMPL/for-me.items and stop. Then read $reads, $tail"
}

if [[ ${1:-} == --print && $# -eq 2 ]]; then
  role "$2"
  # the line is pasted into zsh or bash, so a double quote, $ or backtick would break it
  [[ $prompt$SABHA_WS != *[\"\$\`]* ]] || { echo "sabha-up: config value holds a quote, \$ or backtick" >&2; exit 1; }
  if [[ $R_AGENT != claude ]]; then
    echo "herdr --session $(sabha_session) agent start $(tr '[:upper:]' '[:lower:]' <<<"$name") --kind $R_AGENT --pane <pane-id>   # then: herdr --session $(sabha_session) agent prompt <name> \"$prompt\""
    exit 0
  fi
  mcp=""; sabha_flag "$r" mcp || mcp=" --strict-mcp-config"
  remote=""; [[ ${SABHA_REMOTE:-0} == 1 ]] && remote=" --remote-control"
  echo "cd \"$SABHA_WS\" && claude -n $name --model $model --effort $effort$mcp$remote \"$prompt\""
  echo "pane: cd \"$SABHA_WS\" && '$LOOP' $name"
  exit 0
fi

# herdr_agent <Name> <pane_id>: starts the role's non-claude agent in that pane and submits its opening prompt
# (no --wait: the prompt starts a whole session, and a nudge waits for what it needs)
herdr_agent() {
  local lower
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  sabha_h agent start "$lower" --kind "$R_AGENT" --pane "$2" >/dev/null || return 1
  sabha_pane_note "$1" "$2"
  sabha_h agent prompt "$lower" "$prompt" >/dev/null
}

if [[ $# -eq 1 ]]; then
  role "$1"
  if [[ $R_AGENT != claude ]]; then
    # this pane's shell is busy running this script and agent start wants an idle shell: use a sibling pane
    [[ ${HERDR_ENV:-} == 1 ]] || { echo "sabha-up: $name runs on $R_AGENT, which starts inside a herdr pane (open herdr first)" >&2; exit 1; }
    sabha_herdr_ready || exit 1
    pane=$(sabha_jid "$(sabha_h pane split --current --direction right --cwd "$SABHA_WS" --no-focus)" pane_id)
    [[ -n $pane ]] || { echo "sabha-up: herdr gave no pane id" >&2; exit 1; }
    herdr_agent "$name" "$pane" || { echo "sabha-up: herdr could not start $name ($R_AGENT)" >&2; exit 1; }
    echo "sabha-up: $name started on $R_AGENT in pane $pane"
    # stay alive while the agent does: sabha-loop supervises this process and asks for a restart with two Ctrl-C
    lower=$(tr '[:upper:]' '[:lower:]' <<<"$name")
    trap 'sabha_h agent send-keys "$lower" C-c C-c >/dev/null 2>&1; exit 0' INT TERM   # UNTESTED: key spelling
    while sabha_h agent get "$lower" >/dev/null 2>&1; do sleep 5; done
    exit 0
  fi
  guard "$name"
  # iTerm2 badge: "Fable Medium"; macOS bash 3.2 has no ${v^}, hence awk
  if [[ ${LC_TERMINAL:-${TERM_PROGRAM:-}} == iTerm* ]]; then
    badge=$(awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)} 1' <<<"$model $effort")
    printf '\033]1337;SetBadgeFormat=%s\a' "$(printf %s "$badge" | base64)"
    # Homebrew colours: black background, green text; this pane only, the profile is untouched
    printf '\033]1337;SetColors=bg=000000\a\033]1337;SetColors=fg=00ff00\a\033]1337;SetColors=curbg=23ff18\a'
    # the toolbelt's session list shows the title; claude would replace the role name with its own
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
    printf '\033]0;%s\a' "$(sabha_display "$name")"
  fi
  cd "$SABHA_WS"
  # the hooks and the pre-push hook (sabha-worktree push-guard) read the role from here; a worker gets no GitHub
  # token, so a push or a gh write that slips past the guard has nothing to sign in with (gh's keyring login stays)
  export SABHA_ROLE=$name
  [[ $R_BASE == "$RELAY" ]] || unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
  # MCP servers each cost memory and the roles do not use them; "mcp" in the roster flags keeps them
  mcp=(--strict-mcp-config); sabha_flag "$r" mcp && mcp=()
  remote=(); [[ ${SABHA_REMOTE:-0} == 1 ]] && remote=(--remote-control)
  exec claude -n "$name" --model "$model" --effort "$effort" ${mcp[@]+"${mcp[@]}"} ${remote[@]+"${remote[@]}"} "$prompt"
fi

# two tabs: Build takes the pane roles in pane order, Gate takes those flagged "gate"; each is two rows of up to four.
# Without SABHA_PANES the lazy roles get no pane here; a name listed in SABHA_PANES always does (the relay too, Q25).
build=() gate=()
for n in ${PANES[@]+"${PANES[@]}"}; do
  sabha_role "$n"
  [[ -z ${SABHA_PANES:-} ]] && sabha_flag "$R_ENTRY" lazy && continue
  if sabha_flag "$R_ENTRY" gate; then gate+=("$n"); else build+=("$n"); fi
done
(( ${#build[@]} >= 1 && ${#build[@]} <= 8 && ${#gate[@]} <= 8 )) ||
  { echo "sabha-up: each tab holds up to 8 panes (Build has ${#build[@]}, Gate has ${#gate[@]})" >&2; exit 1; }
# on-demand roles have no pane, so only the panes are checked (the relay too when SABHA_PANES lists it)
guard "${build[@]}" ${gate[@]+"${gate[@]}"}
# each pane runs sabha-loop, which starts sabha-up.sh <Name> and restarts it fresh on a handoff; the plan and
# --force reach that inner sabha-up.sh as environment, since sabha-loop takes only the name
pane_args=""; [[ -n ${SABHA_PLAN:-} ]] && pane_args="SABHA_PLAN=$SABHA_PLAN "
(( FORCE )) && pane_args+="SABHA_FORCE=1 "
# a spawned pane has no inherited env (herdr pane run, a fresh iTerm tab): pass the config path sabha_conf_read found,
# or sabha-loop falls back to its own no-fallback search and fails with "no config"
[[ -n ${SABHA_CONF:-} ]] && pane_args+="SABHA_CONF='$SABHA_CONF' "

# herdr backend (the default): one workspace, Build as its first tab and Gate as a second; each tab is two rows of up
# to four panes. fill_tab <root pane id> <name>...: columns by splitting right, the second row by splitting down, then
# the roles in order (top row first). Widths are herdr's halves, not equal; resize with the mouse.
fill_tab() {
  local root=$1 p k cols n=$(( $# - 1 )) ids out
  shift
  cols=$(( (n + 1) / 2 ))
  ids=("$root")
  for (( k = 2; k <= cols; k++ )); do
    out=$(sabha_h pane split "${ids[$((k - 2))]}" --direction right --cwd "$SABHA_WS" --no-focus) || exit 1
    ids+=("$(sabha_jid "$out" pane_id)")
  done
  for (( k = 0; k < cols && cols + k < n; k++ )); do
    out=$(sabha_h pane split "${ids[$k]}" --direction down --cwd "$SABHA_WS" --no-focus) || exit 1
    ids+=("$(sabha_jid "$out" pane_id)")
  done
  k=0
  for name in "$@"; do
    p=${ids[$k]}
    [[ -n $p ]] || { echo "sabha-up: herdr gave no pane id for $name" >&2; exit 1; }
    role "$name"
    sabha_h pane rename "$p" "$(sabha_display "$name")" >/dev/null
    if [[ $R_AGENT == claude ]]; then
      sabha_pane_note "$name" "$p"
      sabha_h pane run "$p" "$pane_args'$LOOP' $name" >/dev/null
    else
      herdr_agent "$name" "$p" || echo "sabha-up: herdr could not start $name ($R_AGENT)" >&2
    fi
    k=$(( k + 1 ))
  done
}
if [[ $(sabha_backend) == herdr ]]; then
  sabha_herdr_ready || exit 1
  sabha_keep_awake || true
  echo "sabha-up: tab Build $(( (${#build[@]} + 1) / 2 ))x2: ${build[*]}"
  out=$(sabha_h workspace create --cwd "$SABHA_WS" --label "$PROJECT" --no-focus) || exit 1
  ws=$(sabha_jid "$out" workspace_id)
  fill_tab "$(sabha_jid "${out#*\"root_pane\"}" pane_id)" "${build[@]}"
  if (( ${#gate[@]} )); then
    echo "sabha-up: tab Gate $(( (${#gate[@]} + 1) / 2 ))x2: ${gate[*]}"
    out=$(sabha_h tab create --workspace "$ws" --cwd "$SABHA_WS" --label Gate --no-focus) || exit 1
    fill_tab "$(sabha_jid "${out#*\"root_pane\"}" pane_id)" "${gate[@]}"
  fi
  echo "sabha-up: attach with: herdr --session $(sabha_session)   (UNTESTED flag spelling; VS Code integrated terminal on Mac/Linux: herdr attach)"
  exit 0
fi

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
    printf '    tell %s%d\n      set name to "%s"\n      write text "%s"\n    end tell\n' "$p" "$k" "$(sabha_display "$name")" "cd '$SABHA_WS' && ${pane_args}'$LOOP' $name"
    k=$(( k + 1 ))
  done
}
# $SABHA_WS and $SABHA_CONF go into AppleScript text (tab_script) and a shell line it writes: a quote, $ or backtick
# in either would break both
[[ $SABHA_WS${SABHA_CONF:-} != *[\"\$\`]* ]] || { echo "sabha-up: config value holds a quote, \$ or backtick" >&2; exit 1; }
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
