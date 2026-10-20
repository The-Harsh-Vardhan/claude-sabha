#!/usr/bin/env bash
# Sourced by sabha-up.sh and sabha-nudge, never run: the herdr terminal backend (the default on every OS).
# SABHA_BACKEND=iterm keeps the old iTerm2/osascript path (macOS only, frozen). Panes are made with
# `herdr workspace|tab create` and `herdr pane split`; a Claude role runs `sabha-up.sh <Name>` in its pane, any other
# agent (opencode tested; codex, agy, muse UNTESTED) is started with `herdr agent start --kind`. The files under
# SABHA_IMPL stay the source of truth: herdr only nudges and waits. status/herdr-panes.txt maps "RoleId pane_id": emptied
# at grid start, filled as each pane is made, added to by a role that starts inside a pane, pruned against `pane list`
# before each nudge.
# Windows: herdr is native beta there and bash scripts run in Git Bash (Claude Code on Windows needs Git for Windows
# as far as we know; UNTESTED, no Windows machine here). `herdr attach` (VS Code integrated terminal) is Mac/Linux only.
# The JSON keys read below (workspace_id, tab_id, pane_id, root_pane) follow `herdr --skill`; checked against a fake
# herdr only for agent start/prompt/read, send-keys and pane split (UNTESTED live); a real herdr 0.9.4 session confirmed
# the server start, the "status: running" line, workspace create/list, pane list, agent list, workspace close and
# session stop/delete.

sabha_backend() { echo "${SABHA_BACKEND:-herdr}"; }

# sabha_jid <json> <key>: the first "<key>":"value" in the JSON, one line or pretty-printed
sabha_jid() { grep -o "\"$2\" *: *\"[^\"]*\"" <<<"$1" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

# Sabha runs in its OWN herdr session (SABHA_HERDR_SESSION, default "sabha"), never the default one, which holds the
# user's own workspaces. A named session has no server until it is started (sabha_herdr_ready does that). Every herdr
# call goes through sabha_h so it carries --session; `session stop|delete <name>` is the only call that takes the
# name as an argument instead.
# Unset = "sabha"; set-but-empty is refused, not defaulted.
sabha_session() { echo "${SABHA_HERDR_SESSION-sabha}"; }
# sabha_session_valid: the name is [A-Za-z0-9_-]+, does not start with "-" (it would read as a herdr option), and not "default" in any case (herdr's own session, which holds the
# user's workspaces: stopping or deleting it would destroy them). Prints why on stderr and returns 1 otherwise.
sabha_session_valid() {
  local s lower
  s=$(sabha_session)
  lower=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  if [[ -z $s || $s == -* || $s == *[!A-Za-z0-9_-]* || $lower == default ]]; then
    echo "sabha: SABHA_HERDR_SESSION='$s' is refused: use letters, digits, - and _ (not a leading -), and never \"default\" (herdr's own session)" >&2
    return 1
  fi
}
sabha_h() { sabha_session_valid || return 1; herdr --session "$(sabha_session)" "$@"; }

# sabha_herdr_guard: with SABHA_TEST=1 only the herdr binary named by SABHA_HERDR_BIN (tests/hermetic-bin/herdr, a
# fake) may be used; the real one would open workspaces and start real claude sessions on the default herdr session.
sabha_herdr_guard() {
  sabha_session_valid || return 1
  [[ ${SABHA_TEST:-} == 1 ]] || return 0
  [[ -n ${SABHA_HERDR_BIN:-} && $(command -v herdr 2>/dev/null) == "$SABHA_HERDR_BIN" ]] && return 0
  echo "sabha: SABHA_TEST=1 and herdr ($(command -v herdr 2>/dev/null)) is not SABHA_HERDR_BIN (${SABHA_HERDR_BIN:-unset}); refusing to touch a real herdr" >&2
  return 1
}

# sabha_herdr_ready: herdr is installed and its server runs (started headless when it does not)
sabha_herdr_ready() {
  command -v herdr >/dev/null 2>&1 || {
    echo "sabha: herdr not found (brew install herdr, or curl -fsSL https://herdr.dev/install.sh | sh; SABHA_BACKEND=iterm keeps the old macOS path)" >&2
    return 1
  }
  sabha_herdr_guard || return 1
  sabha_h status server 2>&1 | grep -q 'status: running' && return 0
  sabha_h server >/dev/null 2>&1 &
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    sabha_h status server 2>&1 | grep -q 'status: running' && return 0
  done
  echo "sabha: the herdr server did not start" >&2
  return 1
}

# sabha_power_source: ac, battery or unknown, read-only (`pmset -g ps` first line: Now drawing from 'AC Power')
sabha_power_source() {
  case $(pmset -g ps 2>/dev/null | head -1) in
    *"AC Power"*) echo ac ;;
    *"Battery Power"*) echo battery ;;
    *) echo unknown ;;
  esac
}

# sabha_keep_awake_conf: re-reads the three SABHA_KEEP_AWAKE* keys from sabha.conf (plain words only, never executed)
# so `sabha keep-awake <mode>` takes effect in a running sabha-loop without a restart
sabha_keep_awake_conf() {
  local k v
  [[ -f ${SABHA_CONF:-} ]] || return 0
  for k in SABHA_KEEP_AWAKE SABHA_KEEP_AWAKE_AC SABHA_KEEP_AWAKE_BATTERY; do
    v=$(sed -n "s/^$k=\"\{0,1\}\([a-z]*\)\"\{0,1\}[[:space:]]*\$/\1/p" "$SABHA_CONF" | tail -1)
    [[ -n $v ]] && eval "$k=\$v"
  done
  return 0
}

# sabha_keep_awake_mode: the effective mode. SABHA_KEEP_AWAKE=auto (the default) picks by power source: AC -> lid
# (SABHA_KEEP_AWAKE_AC overrides), battery or unknown -> open (SABHA_KEEP_AWAKE_BATTERY overrides). An explicit
# off|open|lid wins over the per-source pair.
sabha_keep_awake_mode() {
  local m=${SABHA_KEEP_AWAKE:-auto}
  if [[ $m == auto ]]; then
    case $(sabha_power_source) in
      ac) m=${SABHA_KEEP_AWAKE_AC:-lid} ;;
      *) m=${SABHA_KEEP_AWAKE_BATTERY:-open} ;;
    esac
  fi
  echo "$m"
}

# sabha_keep_awake: off does nothing (and ends a caffeinate this script started). open and lid start
# `caffeinate -dis -w <herdr server pid>` so idle sleep is blocked as long as the sabha server lives (no sudo; it
# ends with the server). A caffeinate recorded in status/keep-awake.pid and alive is reused, never doubled. lid also
# needs `sudo pmset -a disablesleep 1`, which only the user runs (docs/keep-awake.md); this warns when it is not set.
# sabha-loop calls it every poll, so a power-source or conf change is picked up live.
# The server's command line (`herdr --session <name> server`) is UNTESTED live.
sabha_keep_awake() {
  local mode d=$SABHA_IMPL/status/keep-awake.lck
  # a test must opt in: a real caffeinate must never start from a test run
  [[ ${SABHA_TEST:-} == 1 && ${SABHA_KEEP_AWAKE_FAKES:-} != 1 ]] && return 0
  sabha_keep_awake_conf
  mode=$(sabha_keep_awake_mode)
  case $mode in
    off|open|lid) ;;
    *) echo "sabha: SABHA_KEEP_AWAKE='$mode' is not auto, off, open or lid; ignored" >&2; return 1 ;;
  esac
  mkdir -p "$SABHA_IMPL/status"
  # loops poll together: a kernel lock (lockf on fd 9) around check+start, so one caffeinate is ever started and a dead
  # holder leaves nothing stale; no lockf (not macOS) = no lock, and caffeinate is macOS-only anyway
  if command -v lockf >/dev/null 2>&1; then
    { lockf -s -t 10 9 || return 1; _sabha_keep_awake_locked "$mode"; } 9>>"$d"
    return $?
  fi
  _sabha_keep_awake_locked "$mode"
}

# sabha_keep_awake_ours <pid> [server pid]: true only when <pid> is a caffeinate holding -w <server pid>
# (any pid when none is given); a pid file outlives reboots and macOS reuses pids, so never trust the number alone
sabha_keep_awake_ours() {
  local c
  c=$(ps -p "$1" -o command= 2>/dev/null)
  case $c in caffeinate\ *|*/caffeinate\ *) ;; *) return 1 ;; esac
  if [[ -n ${2:-} ]]; then case "$c " in *" -w $2 "*) return 0 ;; *) return 1 ;; esac; fi
  case $c in *" -w "[0-9]*) return 0 ;; *) return 1 ;; esac
}

_sabha_keep_awake_locked() {
  local mode=$1 f=$SABHA_IMPL/status/keep-awake.pid old spid cpid sdw=$SABHA_IMPL/status/keep-awake.warned-sd
  old=$(cat "$f" 2>/dev/null)
  # SleepDisabled is machine-wide and only the user can undo it (sudo); outside lid mode a closed lid then keeps running
  if [[ $mode != lid ]] && pmset -g 2>/dev/null | grep -Eq 'SleepDisabled[[:space:]]+1'; then
    [[ -f $sdw ]] || { echo "sabha: keep-awake $mode: SleepDisabled is 1, so a closed lid will not sleep: run sudo pmset -a disablesleep 0 (see docs/keep-awake.md)" >&2; : >"$sdw"; }
  else rm -f "$sdw"; fi
  if [[ $mode == off ]]; then
    [[ -n $old ]] && sabha_keep_awake_ours "$old" && kill "$old" 2>/dev/null
    rm -f "$f"; return 0
  fi
  command -v caffeinate >/dev/null 2>&1 || { echo "sabha: SABHA_KEEP_AWAKE=$mode needs caffeinate (macOS only); ignored" >&2; return 1; }
  spid=$(pgrep -f "herdr --session $(sabha_session) server" 2>/dev/null | head -1)
  if [[ -z $old ]] || ! sabha_keep_awake_ours "$old" "$spid"; then
    rm -f "$f"
    [[ -n $spid ]] || { echo "sabha: keep-awake: no herdr server for session $(sabha_session) to hold awake" >&2; return 1; }
    caffeinate -dis -w "$spid" >/dev/null 2>&1 9>&- &
    cpid=$!
    echo "$cpid" >"$f"
    echo "sabha: keep-awake ($mode): caffeinate $cpid holds the Mac awake while herdr server $spid runs"
  fi
  if [[ $mode == lid ]] && ! pmset -g 2>/dev/null | grep -Eq 'SleepDisabled[[:space:]]+1'; then
    # said once per mode change, not every poll
    [[ $(cat "$SABHA_IMPL/status/keep-awake.warned" 2>/dev/null) == lid ]] ||
      echo "sabha: keep-awake lid: closing the lid still sleeps until you run: sudo pmset -a disablesleep 1 (see docs/keep-awake.md)" >&2
  fi
  echo "$mode" >"$SABHA_IMPL/status/keep-awake.warned"
  return 0
}

# sabha_session_stop: stops and deletes the sabha session and nothing else (the default session is never touched)
sabha_session_stop() {
  local s
  s=$(sabha_session)
  sabha_herdr_guard || return 1
  herdr session stop "$s" >/dev/null 2>&1; herdr session delete "$s" >/dev/null 2>&1
}

# sabha_map_lock / sabha_map_unlock: every pane of a grid start rewrites the map at once, and a read-modify-write
# without a lock keeps only the last writer's row. mkdir is atomic on every OS; flock is not on macOS.
# A lock dir older than 10 s is stale (its writer died between mkdir and rmdir); after 30 s of waiting we write anyway.
sabha_map_lock() {
  local l=$SABHA_IMPL/status/herdr-panes.lock i m
  for (( i = 0; i < 300; i++ )); do
    mkdir "$l" 2>/dev/null && return 0
    (( i % 10 )) || { m=$(date -r "$l" +%s 2>/dev/null) && (( $(date +%s) - m > 10 )) && rmdir "$l" 2>/dev/null; }
    sleep 0.1
  done
}
sabha_map_unlock() { rmdir "$SABHA_IMPL/status/herdr-panes.lock" 2>/dev/null || true; }

# sabha_pane_note <Name> <pane_id>: records which pane holds a role (replaces an older line for that Name)
sabha_pane_note() {
  local f=$SABHA_IMPL/status/herdr-panes.txt t
  mkdir -p "$SABHA_IMPL/status"
  sabha_map_lock
  # mktemp, not $f.tmp.$$: $$ is the parent's pid inside a ( ) subshell
  t=$(mktemp "$f.XXXXXX") && { grep -v "^$1 " "$f" 2>/dev/null; echo "$1 $2"; } >"$t" && mv "$t" "$f"
  sabha_map_unlock
}

# sabha_pane_reset: an empty map, for a grid start: the roles of an older grid and their pane ids are gone
sabha_pane_reset() {
  mkdir -p "$SABHA_IMPL/status"
  : >"$SABHA_IMPL/status/herdr-panes.txt"
}

# sabha_pane_prune: drops the map lines whose pane herdr no longer lists (a closed pane id is never reused, so a line
# for a missing id is dead for good), and says so on stderr. A failed `pane list`, or one with no pane id we can read,
# proves nothing and leaves the map alone.
sabha_pane_prune() {
  local f=$SABHA_IMPL/status/herdr-panes.txt out live name pane t
  [[ -s $f ]] || return 0
  out=$(sabha_h pane list 2>/dev/null) || return 0
  live=$(grep -o '"pane_id" *: *"[^"]*"' <<<"$out" | sed 's/.*: *"\(.*\)"/\1/') || true
  [[ -n $live ]] || return 0
  sabha_map_lock
  t=$(mktemp "$f.XXXXXX") || { sabha_map_unlock; return 0; }
  while read -r name pane; do
    [[ -n $name ]] || continue
    if grep -qxF "$pane" <<<"$live"; then echo "$name $pane" >>"$t"
    else echo "sabha: pane $pane of $name is gone; dropped from the pane map" >&2; fi
  done <"$f"
  mv "$t" "$f"
  sabha_map_unlock
}

# sabha_nudge <Name> <text>: submits text to that role's agent and waits until it settles (idle, done or blocked).
# The target is the role's live pane from the map, else the lower-case agent name (a role started with `agent start`).
sabha_nudge() {
  local t
  sabha_herdr_guard || return 1
  sabha_pane_prune
  # awk exits 2 on a missing map, which under set -e would end the caller before the fallback below
  t=$(awk -v n="$1" '$1 == n { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null) || t=
  [[ -n $t ]] || t=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  sabha_h agent prompt "$t" "$2" --wait --timeout "${SABHA_NUDGE_TIMEOUT:-120000}"
}

# sabha_target <Name>: the herdr target for a role, its recorded pane, else its lower-case agent name (as sabha_nudge)
sabha_target() {
  local t
  t=$(awk -v n="$1" '$1 == n { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null)
  if [[ -n $t ]]; then echo "$t"; else tr '[:upper:]' '[:lower:]' <<<"$1"; fi
}
