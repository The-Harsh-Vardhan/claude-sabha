# Sourced by sabha-run, sabha-helper and sabha-down.sh, never run: the registry of durable helpers and the checks
# around a detached start (docs/durable-helpers.md).
# One file per helper, $SABHA_IMPL/status/helpers/<id>.json (<id> = <Name>-<NNN>), written with a temp file and a
# rename so a reader never sees half a file. Plain bash, no process is started per call: a loaded machine makes every
# exec slow, and the registry is read in loops. The file is real JSON, one "key": value per line, that this file
# alone writes (counters as numbers, the rest as strings with \ and " escaped); the tests parse it with python3.
# shellcheck shell=bash

sabha_helpers_dir() { echo "${SABHA_HELPERS_DIR:-$SABHA_IMPL/status/helpers}"; }
sabha_helper_file() { echo "$(sabha_helpers_dir)/$1.json"; }

# sabha_helper_put <id> key=value...: creates the entry or merges into it; keys keep their first-seen order.
sabha_helper_put() {
  local id=$1 dir f tmp line k v kv i found n re='^  "([A-Za-z_]+)": (.*)$'
  local -a K=() V=()
  shift
  dir=${SABHA_HELPERS_DIR:-$SABHA_IMPL/status/helpers}; f=$dir/$id.json; tmp=$f.tmp.$$
  mkdir -p "$dir" || return 1
  if [[ -f $f ]]; then
    while IFS= read -r line; do
      [[ $line =~ $re ]] || continue
      v=${BASH_REMATCH[2]}; K+=("${BASH_REMATCH[1]}"); V+=("${v%,}")
    done <"$f"
  fi
  for kv in "$@"; do
    k=${kv%%=*} v=${kv#*=}
    # a counter stays a bare number; everything else is a string
    if [[ $k == pid || $k == attempts || $k == started_epoch || $k == exit ]] && [[ $v =~ ^-?[0-9]+$ ]]; then :
    else
      v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/ }; v=${v//$'\r'/ }; v=${v//$'\t'/ }
      v=\"$v\"
    fi
    # an empty array is never expanded: bash 3.2 (macOS) calls that unbound under set -u
    found=0 i=0
    while (( i < ${#K[@]} )); do
      [[ ${K[i]} == "$k" ]] && { V[i]=$v; found=1; break; }
      i=$(( i + 1 ))
    done
    (( found )) || { K+=("$k"); V+=("$v"); }
  done
  n=${#K[@]}
  {
    echo "{"
    i=0
    while (( i < n )); do
      (( i + 1 < n )) && echo "  \"${K[i]}\": ${V[i]}," || echo "  \"${K[i]}\": ${V[i]}"
      i=$(( i + 1 ))
    done
    echo "}"
  } >"$tmp" && mv -f "$tmp" "$f"
}

# sabha_helper_get <id> <key>: the value, or nothing when the entry or the key is missing
sabha_helper_get() {
  local f=${SABHA_HELPERS_DIR:-$SABHA_IMPL/status/helpers}/$1.json line v re="^  \"$2\": (.*)\$"
  [[ -f $f ]] || return 0
  while IFS= read -r line; do
    [[ $line =~ $re ]] || continue
    v=${BASH_REMATCH[1]}; v=${v%,}
    if [[ $v == \"*\" ]]; then v=${v#\"}; v=${v%\"}; v=${v//\\\"/\"}; v=${v//\\\\/\\}; fi
    printf '%s\n' "$v"
    return 0
  done <"$f"
}

# sabha_helper_ids: every registry id, one per line (name order)
sabha_helper_ids() {
  local f
  for f in "${SABHA_HELPERS_DIR:-$SABHA_IMPL/status/helpers}"/*.json; do
    [[ -e $f ]] || continue
    f=${f##*/}; echo "${f%.json}"
  done
}

# sabha_helper_alive <id>: the registry pid is a live process; when ps can be read (and no test list stands in for
# it) its command line must mention sabha-run, so a pid reused after a reboot does not read as a helper
sabha_helper_alive() {
  local pid cmd
  pid=$(sabha_helper_get "$1" pid)
  [[ $pid =~ ^[0-9]+$ ]] && (( pid > 1 )) || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if [[ -z ${SABHA_PS_FILE:-} ]]; then
    cmd=$(ps -p "$pid" -o command= 2>/dev/null) || cmd=""
    [[ -n $cmd && $cmd != *sabha-run* ]] && return 1
  fi
  return 0
}

# sabha_helper_done_state <role> <brief number>: done, blocked or cancelled from the .done marker; nothing without one
sabha_helper_done_state() {
  local f=$SABHA_IMPL/inbox/$1/$2.done res="" line
  [[ -e $f ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == result:* ]] && { res=${line#result:}; res=${res# }; break; }
  done <"$f"
  case $res in
    BLOCKED*) echo blocked ;;
    CANCELLED*) echo cancelled ;;
    *) echo "done" ;;
  esac
}

# sabha_helper_finish <id> <role> <n> <exit code> <why> <timed 0|1> <cancelled 0|1>: the supervisor's last word, run
# after any fallback .done is written. A stop recorded by sabha-helper stop wins over the cancel it caused.
sabha_helper_finish() {
  local id=$1 role=$2 n=$3 st
  if [[ -n $(sabha_helper_get "$id" stop_reason) ]]; then st=stopped
  elif (( $7 )); then st=cancelled
  elif (( $6 )); then st=timeout
  else st=$(sabha_helper_done_state "$role" "$n") || st=blocked
  fi
  sabha_helper_put "$id" "state=$st" "ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "exit=$4" "why=$5"
}

# sabha_helper_mark_ack <role> <n> <what> [transcript]: one line at a helper's start, inbox/<role>/<n>.helper.ack.
# sabha_helper_mark_done <role> <n> <exit code> [transcript]: inbox/<role>/<n>.helper.done, last line
# "### EXIT=<code> ###" (gstack-detach style): an ack with no done, or a done with no sentinel, is never success.
# Role and n are checked before any path is built, so "../x" cannot reach outside inbox/; free text loses its line
# breaks so it cannot forge the sentinel line. Both files are written to a temp name and renamed.
sabha_helper_mark_ok() {
  [[ $1 =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || { echo "sabha-helper: bad role '$1'" >&2; return 2; }
  [[ $2 =~ ^[0-9]+$ ]] || { echo "sabha-helper: brief number must be digits, got '$2'" >&2; return 2; }
}
sabha_helper_oneline() { local v=${1//$'\n'/ }; printf '%s' "${v//$'\r'/ }"; }
sabha_helper_mark_write() {
  mkdir -p "${1%/*}" && printf '%s' "$2" >"$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"
}
sabha_helper_mark_ack() {
  sabha_helper_mark_ok "$1" "$2" || return 2
  # a redispatch acks the same number again; the last run's done would read as this run's end
  rm -f "$SABHA_IMPL/inbox/$1/$2.helper.done"
  sabha_helper_mark_write "$SABHA_IMPL/inbox/$1/$2.helper.ack" "$(printf '%s helper %s %s: %s, transcript: %s' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$(sabha_helper_oneline "$3")" "$(sabha_helper_oneline "${4:--}")")"$'\n'
}
sabha_helper_mark_done() {
  sabha_helper_mark_ok "$1" "$2" || return 2
  [[ $3 =~ ^-?[0-9]+$ ]] || { echo "sabha-helper: exit code must be a number, got '$3'" >&2; return 2; }
  sabha_helper_mark_write "$SABHA_IMPL/inbox/$1/$2.helper.done" "$(printf '%s helper %s %s ended, transcript: %s' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$(sabha_helper_oneline "${4:--}")")"$'\n'"### EXIT=$3 ###"$'\n'
}

# sabha_helper_load: the 1-minute load average on stdout; non-zero when it cannot be read.
# SABHA_LOADAVG replaces the probe in tests ("none" = unreadable).
sabha_helper_load() {
  local v=""
  if [[ -n ${SABHA_LOADAVG:-} ]]; then
    [[ $SABHA_LOADAVG == none ]] && return 1
    v=$SABHA_LOADAVG
  elif [[ -r /proc/loadavg ]]; then
    read -r v _ </proc/loadavg
  else
    v=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')
    [[ -n $v ]] || v=$(uptime 2>/dev/null | sed -n 's/.*load averages\{0,1\}:[[:space:]]*\([0-9][0-9.]*\).*/\1/p')
  fi
  [[ $v =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  echo "$v"
}

# sabha_helper_load_max: the threshold, or "off". Default 4 x cores (8 cores when the count cannot be read).
sabha_helper_load_max() {
  local m=${SABHA_HELPER_LOAD_MAX:-} cores
  case $m in
    off|0) echo off; return 0 ;;
    "") ;;
    *) echo "$m"; return 0 ;;
  esac
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
  [[ $cores =~ ^[0-9]+$ ]] || cores=8
  echo $(( cores * 4 ))
}

# sabha_helper_load_refuse: prints why and returns 0 when the load is over the threshold; returns 1 (a start may go
# ahead) otherwise. A load that cannot be read prints a note on stderr and does not refuse.
sabha_helper_load_refuse() {
  local max load
  max=$(sabha_helper_load_max)
  [[ $max == off ]] && return 1
  if ! load=$(sabha_helper_load); then
    echo "sabha: machine load not measured (no /proc/loadavg, sysctl or uptime); starting anyway" >&2
    return 1
  fi
  if awk -v l="$load" -v m="$max" 'BEGIN { exit !(l > m) }'; then
    echo "load $load is over SABHA_HELPER_LOAD_MAX $max; start it later or raise the limit"
    return 0
  fi
  return 1
}

# sabha_detach_prefix: sets DETACH (an argv prefix) so the command after it runs in a new session, out of the
# caller's process group and pane. setsid when present, else python3's os.setsid. Fails with a message when neither
# exists. SABHA_DETACH_TOOL=none simulates that (tests).
# shellcheck disable=SC2034  # DETACH is read by sabha-run
sabha_detach_prefix() {
  DETACH=()
  if [[ ${SABHA_DETACH_TOOL:-auto} != none ]]; then
    if command -v setsid >/dev/null 2>&1; then DETACH=(setsid); return 0; fi
    if command -v python3 >/dev/null 2>&1; then
      # a process that already leads its group cannot setsid; the exec still runs, only less detached
      DETACH=(python3 -I -c 'import os, sys
try:
    os.setsid()
except OSError:
    pass
os.execvp(sys.argv[1], sys.argv[1:])')
      return 0
    fi
  fi
  echo "no setsid and no python3: cannot start a helper outside this session" >&2
  return 1
}
