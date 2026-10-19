#!/bin/bash
# Sabha status line: session name | model Effort | ctx % | 5h/7d usage | dir @ branch* | $cost.
# Colors: green < 25, amber 25-30, red >= 30 (the 30% restart rule).
# Side effects: writes the context percent to $SABHA_IMPL/status/context/<name>.txt (what sabha-loop, sabha-watch and
# the board read) and the usage windows to status/limits.txt, then fires the SABHA_NOTIFY alerts (bin/sabha-limits.sh).
# Install: in ~/.claude/settings.json, "statusLine": {"type": "command", "command": "bash /path/to/bin/statusline-sabha.sh"}.
# Needs jq. Paths come from sabha.conf (SABHA_CONF, else the nearest .sabha/local/sabha.conf upward from the cwd, else ../sabha.conf beside this
# script); SABHA_CTX_DIR overrides.
BIN=$(cd "$(dirname "$0")" && pwd)
CONF=${SABHA_CONF:-}
# the nearest .sabha/local/sabha.conf from the cwd upward (the project the session is in), else the one beside the scripts
if [ -z "$CONF" ]; then
  d=$PWD
  while [ -n "$d" ]; do
    [ -f "$d/.sabha/local/sabha.conf" ] && { CONF=$d/.sabha/local/sabha.conf; break; }
    d=${d%/*}
  done
fi
CONF=${CONF:-$BIN/../sabha.conf}
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"
CTX_DIR="${SABHA_CTX_DIR:-${SABHA_IMPL:+$SABHA_IMPL/status/context}}"

input=$(cat)
name=$(echo "$input" | jq -r '.session_name // empty')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
# claude.ai Pro/Max only, after the first API response; each window may be absent on its own (sabha-share-facts-2.md)
h5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
h5r=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
d7=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
d7r=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Effort: from the JSON if this Claude Code version sends it, else the --effort of the claude
# process above us (sabha panes), else effortLevel in settings.json.
effort=$(echo "$input" | jq -r '(.effort.level? // .effort? // .model.effort? // empty) | strings')
if [ -z "$effort" ]; then
  pid=$PPID
  for _ in 1 2 3 4; do
    args=$(ps -o args= -p "$pid" 2>/dev/null) || break
    case "$args" in *--effort\ *) effort=${args#*--effort }; effort=${effort%% *}; break ;; esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$pid" ] || [ "$pid" -le 1 ] && break
  done
fi
[ -z "$effort" ] && effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
[ -n "$effort" ] && model="$model $(echo "${effort:0:1}" | tr '[:lower:]' '[:upper:]')${effort:1}"

[ -z "$name" ] && name="unnamed"
# the role's character and colour from the theme (a copy Arjun-1 shows as the character's copy); the session name is the
# role id, so it stays visible in brackets. A name that is no role id (or no theme) stays as it is.
shown=$name
row=$(SABHA_THEME="${SABHA_THEME:-}" SABHA_THEME_DIR="${SABHA_THEME_DIR:-}" SABHA_PRESET_DIR="${SABHA_PRESET_DIR:-}" "${BASH:-bash}" "$BIN/sabha-theme" resolve 2>/dev/null | awk -F'|' -v n="${name%-[0-9]*}" '$1 == n { print $2 "|" $3; exit }')
if [ -n "$row" ]; then
  disp=${row%%|*} hex=${row#*|}
  case $name in *-[0-9]*) disp="$disp-${name##*-}" ;; esac
  shown=$disp
  case $hex in
    \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
      shown=$(printf '\033[38;2;%d;%d;%dm%s\033[0m' "0x${hex:1:2}" "0x${hex:3:2}" "0x${hex:5:2}" "$disp") ;;
  esac
  [ "$disp" != "$name" ] && shown="$shown ($name)"
fi

# Trailing " | 5h 23% 7d 41% | dir @ branch* | $cost"; each part drops out on its own when missing.
extra=""
if [ -n "$h5" ] || [ -n "$d7" ]; then
  extra=" |${h5:+ 5h ${h5%.*}%}${d7:+ 7d ${d7%.*}%}"
fi
if [ -n "$dir" ]; then
  extra="$extra | ${dir##*/}"
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    br=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$br" ] && br=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
    dirty=$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null | head -c 1)
    [ -n "$br" ] && extra="$extra @ $br${dirty:+*}"
  fi
fi
if [ -n "$cost" ]; then
  c2=$(LC_NUMERIC=C printf '%.2f' "$cost" 2>/dev/null) && extra="$extra | \$$c2"
fi

if [ -z "$pct" ]; then
  # null early in a session or after /compact: show it, never estimate
  printf '%s | %s | ctx n/a%s\n' "$shown" "$model" "$extra"
else
  p=${pct%.*}
  tag=""
  if   [ "$p" -ge 30 ]; then c='\033[31m'; tag=" RESTART"
  elif [ "$p" -ge 25 ]; then c='\033[33m'
  else c='\033[32m'; fi
  printf '%s | %s | ctx '"$c"'%s%%%s\033[0m%s\n' "$shown" "$model" "$pct" "$tag" "$extra"
fi

if [ -n "$CTX_DIR" ] && [ -n "$pct" ] && [ "$name" != "unnamed" ]; then
  f=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-')
  mkdir -p "$CTX_DIR" 2>/dev/null && printf '%s\n' "$pct" > "$CTX_DIR/$f.txt" 2>/dev/null
fi
# herdr sidebar, for a sabha role in a herdr pane: its display name (kept), the brief it holds (the newest claim
# without a done) and ctx % (with a ttl, so they clear when this session stops rendering). Sent again after 60 s or on
# a change. UNTESTED live: that the pane's environment carries HERDR_PANE_ID down to this hook.
inbox=${SABHA_IMPL:+$SABHA_IMPL/inbox/$name}
if [ -n "${HERDR_PANE_ID:-}" ] && [ -n "$inbox" ] && [ -d "$inbox" ] && [ -n "$CTX_DIR" ] && command -v herdr >/dev/null 2>&1; then
  brief=-
  for c in "$inbox"/[0-9][0-9][0-9].claim; do
    [ -e "$c" ] && [ ! -e "${c%.claim}.done" ] && brief=$(basename "$c" .claim)
  done
  ctxt=${pct:+${pct%.*}%} who=${disp:-$name}
  meta="$who|$brief|$ctxt"
  mf=$CTX_DIR/$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-').meta
  now=$(date +%s); old=$(cat "$mf" 2>/dev/null)
  if [ -z "$old" ] || [ "${old#* }" != "$meta" ] || [ $(( now - ${old%% *} )) -ge 60 ]; then
    mkdir -p "$CTX_DIR" 2>/dev/null && echo "$now $meta" >"$mf" 2>/dev/null
    # shellcheck source=sabha-herdr.sh
    . "$BIN/sabha-herdr.sh"
    if sabha_herdr_guard 2>/dev/null; then
      # idea 3: the herdr agent name is the lower-case role id, so scripts can say `agent wait relay`; a name herdr
      # would refuse ([a-z][a-z0-9_-]{0,31}) is skipped. A fresh session is a new occupant, hence every send
      an=$(echo "$name" | tr '[:upper:]' '[:lower:]')
      case $an in [a-z]*) ;; *) an= ;; esac
      case $an in *[!a-z0-9_-]*) an= ;; esac
      [ ${#an} -le 32 ] || an=
      # only the pane herdr-panes.txt records for this role (by role id or display name, newest row wins, as
      # sabha_target reads it) takes the name: a duplicate or a pane from another herdr session would get the relay's
      # focus key and nudges. Skipped once per name and pane in status/herdr-rename.log
      if [ -n "$an" ] && [ "$(awk -v n="$name" -v d="$who" '$1 == n || $1 == d { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null)" != "$HERDR_PANE_ID" ]; then
        an="" rl=$SABHA_IMPL/status/herdr-rename.log
        msg="rename skipped: $name in pane $HERDR_PANE_ID is not the pane status/herdr-panes.txt records"
        grep -qxF "$msg" "$rl" 2>/dev/null || echo "$msg" >>"$rl" 2>/dev/null
      fi
      { [ -n "$an" ] && sabha_h agent rename "$HERDR_PANE_ID" "$an"
        sabha_h pane report-metadata "$HERDR_PANE_ID" --source sabha:name --display-agent "$who"
        sabha_h pane report-metadata "$HERDR_PANE_ID" --source sabha:status --seq "$now" --ttl-ms "${SABHA_META_TTL:-300000}" \
          --token "brief=$brief" --token "ctx=$ctxt"; } >/dev/null 2>&1 &
    fi
  fi
fi
if [ -n "${SABHA_IMPL:-}" ] && { [ -n "$h5" ] || [ -n "$d7" ]; }; then
  # shellcheck source=sabha-limits.sh
  . "$BIN/sabha-limits.sh"
  [ -n "$h5" ] && sabha_limits_write five_hour "$h5" "${h5r:-0}"
  [ -n "$d7" ] && sabha_limits_write seven_day "$d7" "${d7r:-0}"
  sabha_limits_alert
fi
exit 0
