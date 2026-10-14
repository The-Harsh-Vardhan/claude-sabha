# Sourced by sabha-up.sh, sabha-down.sh and sabha-check, never run: the config, the roster, and the claude
# processes that carry a session name.
# shellcheck shell=bash disable=SC2034  # ROLES, NAMES, RELAY, DISPATCHER are for the callers

SABHA_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# sabha_load <caller>: sources sabha.conf (SABHA_CONF, else ../sabha.conf beside the scripts) and sets ROLES
# ("name model effort flags", the relay first, then the dispatcher, then grid order; flags is "-" or a comma list),
# NAMES (every role), PANES (the grid roles: not the relay, not an "ondemand" role), LAZY, RELAY and DISPATCHER.
# Roster entry: Name:model[:effort[:flags]]. Flags: "ondemand" = no pane, started by hand with sabha-up.sh <Name>;
# "gate" = a pane in the second tab (Gate) instead of the first (Build); "lazy" = no pane when the grid opens, started
# with sabha-up.sh <Name> when a brief lands (RAM: each claude session is a process); "mcp" = keeps the user's MCP
# servers (every other role starts with none). A role id is one word, and it is
# the claude -n name, the status file and the inbox directory (Ved Vyasa is VedVyasa).
sabha_load() {
  CONF=${SABHA_CONF:-$SABHA_BIN/../sabha.conf}
  [[ -f $CONF ]] || { echo "$1: no config at $CONF (copy sabha.conf.example to sabha.conf)" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$CONF"
  : "${SABHA_WS:?missing from sabha.conf}" "${SABHA_IMPL:?missing from sabha.conf}"
  # SABHA_ROSTER replaces this default list.
  ROLES=(
    "Vidur opus medium -"
    "Yudhishthira opus medium -"
    "Bhishma fable medium -"
    "Bhima opus high -"
    "Arjun opus medium -"
    "Sahadev sonnet high -"
    "Nakul sonnet medium -"
    "Karna sonnet medium -"
    "Sanjaya haiku high -"
    "Duryodhan opus high gate,lazy"
    "Dushasan sonnet high gate,lazy"
    "Shakuni opus high gate,lazy"
    "Draupadi sonnet high gate,lazy"
    "Gandhari sonnet medium gate,lazy"
    "VedVyasa sonnet medium gate,lazy"
    "Barbarika haiku medium gate"
    "Abhimanyu haiku medium gate"
    "Krishna opus medium ondemand"
    "Ashwatthama haiku high ondemand"
    "Dronacharya sonnet medium ondemand"
  )
  if [[ -n ${SABHA_ROSTER:-} ]]; then
    ROLES=()
    local e n m f g
    for e in $SABHA_ROSTER; do
      IFS=: read -r n m f g <<<"$e"
      ROLES+=("$n $m ${f:-medium} ${g:--}")
    done
  fi
  NAMES=() PANES=() LAZY=()
  local r i=0
  for r in "${ROLES[@]}"; do
    NAMES+=("${r%% *}")
    (( i++ > 0 )) && ! sabha_flag "$r" ondemand && PANES+=("${r%% *}")
    sabha_flag "$r" lazy && LAZY+=("${r%% *}")
  done
  RELAY=${NAMES[0]}
  DISPATCHER=${NAMES[1]}
}

# sabha_flag "<ROLES entry>" <flag>: true when the entry's flags list holds that flag
sabha_flag() {
  local flags=${1##* }
  [[ ,$flags, == *,"$2",* ]]
}

# sabha_procs: one line per claude process started with a session name (-n, --name, --name=):
# "<name> <pid> <tty> <yyyy-Mon-dd> <hh:mm:ss>". SABHA_PS_FILE replaces the live list (tests); it holds the output
# of `ps -axo pid=,tty=,lstart=,command=`. A process renamed after start, or a background session that ps shows
# under another command, carries no name here; ListAgents is the only place that sees those.
# Returns non-zero when the list cannot be read, so a failed ps never reads as "nothing running".
sabha_procs() {
  local list
  if [[ -n ${SABHA_PS_FILE:-} ]]; then list=$(cat "$SABHA_PS_FILE") || return 1
  else list=$(ps -axo pid=,tty=,lstart=,command=) || return 1; fi
  awk '{
      cmd = $8; sub(/.*\//, "", cmd)
      if (cmd != "claude") next
      name = ""
      # options only: two plain words in a row are the prompt, which may itself contain "-n"
      for (i = 9; i <= NF; i++) {
        if ($i == "-n" || $i == "--name") { name = $(i + 1); break }
        if ($i ~ /^--name=/) { name = substr($i, 8); break }
        if ($i !~ /^-/ && $(i - 1) !~ /^-/) break
      }
      if (name != "") printf "%s %s %s %s-%s-%s %s\n", name, $1, $2, $7, $4, $5, $6
    }' <<<"$list"
}
