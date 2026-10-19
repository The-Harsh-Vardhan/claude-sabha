# Sourced by sabha-up.sh, sabha-run, sabha-down.sh and sabha-check, never run: the config, the roster, and the claude
# processes that carry a session name.
# shellcheck shell=bash disable=SC2034  # ROLES, NAMES, RELAY, DISPATCHER, R_* are for the callers

SABHA_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# sabha_load <caller>: reads the config (sabha_conf_read below: sabha.conf, the plan file sabha.<SABHA_PLAN>.conf beside
# the scripts when SABHA_PLAN is set (sabha-up.sh --plan pro|max5|max20; a plan file carries only the roster, the
# panes, the copies and the labels, never paths), the team's .sabha/config, sabha.conf again), and sets ROLES
# ("name agent model effort flags", the relay first, then the dispatcher, then grid order; flags is "-" or a comma
# list), NAMES (every role), PANES, LAZY, RELAY, DISPATCHER and MAX_COPIES.
# Roster entry: Name:agent:model[:effort[:flags]]. A second field that is not an agent in SABHA_AGENTS is the model
# and the agent is claude, so the older Name:model[:effort[:flags]] still parses. Flags: "ondemand" = no pane,
# started by hand with sabha-up.sh <Name>; "gate" = a pane in the second tab (Gate) instead of the first (Build);
# "lazy" = no pane when the grid opens, started with sabha-up.sh <Name> when a brief lands (RAM: each claude session
# is a process); "mcp" = keeps the user's MCP servers (every other role starts with none).
# PANES: the names in SABHA_PANES, in that order, when it is set (every other profile is on demand: a subagent of
# the dispatcher, or sabha-up.sh <Name>); otherwise every role but the relay and the "ondemand" ones.
# A role id is one word, and it is the claude -n name, the status file and the inbox directory (Ved Vyasa is
# Keeper). SABHA_LABEL_<Name> is the role label shown next to the name ("Architect").
SABHA_AGENTS=${SABHA_AGENTS:-"claude opencode codex agy muse"}
# Keys a committed .sabha/config may set: the team's shape and tracker. Everything else (paths, plan, theme, ntfy
# topic, SABHA_REMOTE, SABHA_USER_ID) is personal and stays in sabha.conf.
SABHA_SHARED_KEYS="SABHA_PROJECT SABHA_ROSTER SABHA_PANES SABHA_MAX_COPIES SABHA_TRACKER SABHA_SHEET_ID SABHA_LABEL_* SABHA_PROMPT_*"

# sabha_shared_key <key>: true when a committed .sabha/config may set it
sabha_shared_key() {
  local k
  for k in $SABHA_SHARED_KEYS; do
    # shellcheck disable=SC2254  # the * in SABHA_LABEL_* is the pattern
    case $1 in $k) return 0 ;; esac
  done
  return 1
}

# sabha_shared_read <file> [warn]: sets the shared keys of a committed .sabha/config WITHOUT running it: a teammate's
# pull request can change that file, so it is parsed (KEY=value, one level of quotes, no $ or ` expansion), never
# sourced. A personal or unknown key is skipped (with "warn", reported on stderr).
sabha_shared_read() {
  local line key val
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^(SABHA_[A-Za-z0-9_]+)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]} val=${BASH_REMATCH[2]}
    if ! sabha_shared_key "$key"; then
      [[ ${2:-} == warn ]] && echo "sabha: $key is personal; ignored in $1 (keep it in your sabha.conf)" >&2
      continue
    fi
    case $val in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
    printf -v "$key" '%s' "$val"
  done <"$1"
}

# sabha_conf_read <caller>: finds sabha.conf (SABHA_CONF, else ./.sabha/local/sabha.conf, else ../sabha.conf beside the
# scripts) and exports SABHA_CONF, so every pane, hook and worktree session finds the same file whatever its cwd. Then
# layers: sabha.conf, the plan file sabha.<SABHA_PLAN>.conf, the team's .sabha/config (SABHA_SHARED), and sabha.conf
# again, so a key you set yourself wins over the team's. Docs (PROTOCOL-core.md, protocol/) come from SABHA_SHARED when
# it holds them, else SABHA_IMPL (SABHA_DOCS). Returns 1 (message on stderr) when a file is missing.
sabha_conf_read() {
  CONF=${SABHA_CONF:-}
  [[ -z $CONF && -f $PWD/.sabha/local/sabha.conf ]] && CONF=$PWD/.sabha/local/sabha.conf
  CONF=${CONF:-$SABHA_BIN/../sabha.conf}
  [[ -f $CONF ]] || { echo "$1: no config at $CONF (run bin/sabha init, or cd to a project that has .sabha/local)" >&2; return 1; }
  export SABHA_CONF=$CONF
  # shellcheck source=/dev/null
  . "$CONF"
  if [[ -n ${SABHA_PLAN:-} ]]; then
    PLAN_CONF=${SABHA_PLAN_DIR:-$SABHA_BIN/..}/sabha.$SABHA_PLAN.conf
    [[ -f $PLAN_CONF ]] || { echo "$1: no plan file at $PLAN_CONF (plans: pro, max5, max20)" >&2; return 1; }
    # shellcheck source=/dev/null
    . "$PLAN_CONF"
  fi
  if [[ -n ${SABHA_SHARED:-} && -f $SABHA_SHARED/config ]]; then
    sabha_shared_read "$SABHA_SHARED/config"
    # shellcheck source=/dev/null
    . "$CONF"
  fi
  SABHA_DOCS=${SABHA_IMPL:-}
  [[ -n ${SABHA_SHARED:-} && -f $SABHA_SHARED/${SABHA_PROTOCOL_CORE:-PROTOCOL-core.md} ]] && SABHA_DOCS=$SABHA_SHARED
  return 0
}

sabha_load() {
  sabha_conf_read "$1" || exit 1
  : "${SABHA_WS:?missing from sabha.conf}" "${SABHA_IMPL:?missing from sabha.conf}"
  # SABHA_ROSTER replaces this default list.
  ROLES=(
    "Relay claude opus medium -"
    "Dispatcher claude opus medium -"
    "Architect claude fable medium -"
    "BuilderHeavy claude opus high -"
    "BuilderPrecise claude opus medium -"
    "Reviewer claude sonnet high -"
    "Writer claude sonnet medium -"
    "Runner claude sonnet medium -"
    "Scribe claude haiku high -"
    "BackendCritic claude opus high gate,lazy"
    "FrontendCritic claude sonnet high gate,lazy"
    "SecurityCritic claude opus high gate,lazy"
    "ScopeCritic claude sonnet high gate,lazy"
    "BlindReviewer claude sonnet medium gate,lazy"
    "Keeper claude sonnet medium gate,lazy"
    "Observer claude haiku medium gate"
    "Housekeeper claude haiku medium gate"
    "Tutor claude opus medium ondemand"
    "Watcher claude haiku high ondemand"
    "Coach claude sonnet medium ondemand"
  )
  if [[ -n ${SABHA_ROSTER:-} ]]; then
    ROLES=()
    local e n a m f g
    for e in $SABHA_ROSTER; do
      IFS=: read -r n a m f g <<<"$e"
      if [[ " $SABHA_AGENTS " != *" $a "* ]]; then g=$f f=$m m=$a a=claude; fi
      [[ -n $m ]] || { echo "$1: roster entry \"$e\" names no model" >&2; exit 1; }
      ROLES+=("$n $a $m ${f:-medium} ${g:--}")
    done
  fi
  sabha_theme "$1" || exit 1
  NAMES=() PANES=() LAZY=()
  local r i=0
  for r in "${ROLES[@]}"; do
    NAMES+=("${r%% *}")
    (( i++ > 0 )) && ! sabha_flag "$r" ondemand && PANES+=("${r%% *}")
    sabha_flag "$r" lazy && LAZY+=("${r%% *}")
  done
  if [[ -n ${SABHA_PANES:-} ]]; then
    PANES=()
    for n in $SABHA_PANES; do
      [[ " ${NAMES[*]} " == *" $n "* ]] || { echo "$1: SABHA_PANES names $n, not in the roster" >&2; exit 1; }
      PANES+=("$n")
    done
  fi
  RELAY=${NAMES[0]}
  DISPATCHER=${NAMES[1]}
  MAX_COPIES=${SABHA_MAX_COPIES:-2}
}

# sabha_theme <caller>: a theme is a skin. SABHA_THEME (default plain) names themes/<theme>.theme, one
# "Role|Name|#hex|persona" line per role id. It renames ROLES, SABHA_PANES and SABHA_LABEL_<Role> to the themed names
# and sets SABHA_COLOR_<Name> and SABHA_PERSONA_<Name>. The plan files keep the role ids, so one plan works with every
# theme.
sabha_theme() {
  local file=${SABHA_THEME_DIR:-$SABHA_BIN/../themes}/${SABHA_THEME:-plain}.theme id name color persona i v panes p
  if [[ ! -f $file ]]; then
    [[ -z ${SABHA_THEME:-} ]] && return 0
    echo "$1: no theme file at $file (themes: $(ls "${file%/*}" 2>/dev/null | sed -n 's/\.theme$//p' | tr '\n' ' '))" >&2
    return 1
  fi
  while IFS='|' read -r id name color persona || [[ -n $id ]]; do
    [[ -z $id || $id == \#* ]] && continue
    persona=${persona%$'\r'}
    printf -v "SABHA_ID_$name" '%s' "$id"
    for i in "${!ROLES[@]}"; do [[ ${ROLES[i]%% *} == "$id" ]] && ROLES[i]="$name ${ROLES[i]#* }"; done
    panes=
    for p in ${SABHA_PANES:-}; do [[ $p == "$id" ]] && p=$name; panes="$panes $p"; done
    [[ -n ${SABHA_PANES:-} ]] && SABHA_PANES=${panes# }
    v=SABHA_LABEL_$id
    [[ -n ${!v:-} ]] && printf -v "SABHA_LABEL_$name" '%s' "${!v}"
    printf -v "SABHA_COLOR_$name" '%s' "$color"
    printf -v "SABHA_PERSONA_$name" '%s' "$persona"
  done <"$file"
  return 0
}

# sabha_role <Name>: sets R_ENTRY (the ROLES line), R_NAME, R_AGENT, R_MODEL, R_EFFORT, R_FLAGS, R_BASE and R_LABEL
# for that role; false when the roster has no such role. A copy Name-N (N from 1 to MAX_COPIES) takes the profile
# of Name and keeps its own name: its own inbox, status file and worktree.
sabha_role() {
  local r base n
  R_BASE=$1
  for r in "${ROLES[@]}"; do [[ ${r%% *} == "$1" ]] && break; done
  if [[ ${r%% *} != "$1" ]]; then
    base=${1%-*} n=${1##*-}
    [[ $1 == *-* && -n $n && $n != *[!0-9]* && " ${NAMES[*]} " == *" $base "* ]] || return 1
    (( n >= 1 && n <= MAX_COPIES )) || { echo "sabha: $1 is past SABHA_MAX_COPIES ($MAX_COPIES)" >&2; return 1; }
    R_BASE=$base
    for r in "${ROLES[@]}"; do [[ ${r%% *} == "$base" ]] && break; done
  fi
  R_ENTRY=$r
  read -r _ R_AGENT R_MODEL R_EFFORT R_FLAGS <<<"$r"
  R_NAME=$1
  local lv=SABHA_LABEL_$R_BASE
  R_LABEL=${!lv:-}
  return 0
}

# sabha_reads <Name>: what a role reads at start, shared by sabha-up.sh and sabha-run so both open the same way.
# SABHA_PROTOCOL_CORE (file under SABHA_DOCS: the team's .sabha/ when it holds the docs, else SABHA_IMPL) +
# SABHA_ROLE_DIR (folder of <Name>.md) split the protocol: core, the role file, then the top block of the status file.
sabha_reads() {
  # a copy Thor-1 shares Thor's card and persona; a dash is not legal in a variable name
  local lower card=$1 id=SABHA_ID_${1%-[0-9]*} persona=SABHA_PERSONA_${1%-[0-9]*} tail= docs=${SABHA_DOCS:-$SABHA_IMPL}
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  # a themed role keeps the card of its role id unless the project has a card under the themed name
  [[ -n ${!id:-} && ! -f $docs/${SABHA_ROLE_DIR:-protocol}/$1.md ]] && card=${!id}
  [[ -n ${!persona:-} ]] && tail=". Your persona: ${!persona}"
  if [[ -n ${SABHA_PROTOCOL_CORE:-} && -n ${SABHA_ROLE_DIR:-} ]]; then
    echo "$docs/$SABHA_PROTOCOL_CORE, then $docs/$SABHA_ROLE_DIR/$card.md, then the top block of status/$lower.md$tail"
  else
    echo "$SABHA_IMPL/PROTOCOL.md, then status/$lower.md$tail"
  fi
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

# sabha_cost_log <Name> <model> <event>: appends "utc role model ctx% event" (tab separated) to
# $SABHA_IMPL/status/cost-log.tsv, the context % read from status/context/<name>.txt ("-" when unknown).
# One line per brief or session end; it holds no prompt text and no secret. A write failure never stops a caller.
sabha_cost_log() {
  local lower ctx=-
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  set -- "$1" "$2" "$(printf '%s' "$3" | tr '\t\r\n' '   ')"
  [[ -f $SABHA_IMPL/status/context/$lower.txt ]] && ctx=$(tr -d ' \n' <"$SABHA_IMPL/status/context/$lower.txt")
  { mkdir -p "$SABHA_IMPL/status" && printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$ctx" "$3" \
      >>"$SABHA_IMPL/status/cost-log.tsv"; } 2>/dev/null || true
}
