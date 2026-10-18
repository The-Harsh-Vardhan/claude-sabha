#!/bin/bash
# Sabha status line: session name | model Effort | ctx % | 5h/7d usage | dir @ branch* | $cost.
# Colors: green < 25, amber 25-30, red >= 30 (the 30% restart rule).
# Side effects: writes the context percent to $SABHA_IMPL/status/context/<name>.txt (what sabha-loop, sabha-watch and
# the board read) and the usage windows to status/limits.txt, then fires the SABHA_NOTIFY alerts (bin/sabha-limits.sh).
# Install: in ~/.claude/settings.json, "statusLine": {"type": "command", "command": "bash /path/to/bin/statusline-sabha.sh"}.
# Needs jq. Paths come from sabha.conf (SABHA_CONF, else ../sabha.conf beside this script); SABHA_CTX_DIR overrides.
BIN=$(cd "$(dirname "$0")" && pwd)
CONF=${SABHA_CONF:-$BIN/../sabha.conf}
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
  printf '%s | %s | ctx n/a%s\n' "$name" "$model" "$extra"
else
  p=${pct%.*}
  tag=""
  if   [ "$p" -ge 30 ]; then c='\033[31m'; tag=" RESTART"
  elif [ "$p" -ge 25 ]; then c='\033[33m'
  else c='\033[32m'; fi
  printf '%s | %s | ctx '"$c"'%s%%%s\033[0m%s\n' "$name" "$model" "$pct" "$tag" "$extra"
fi

if [ -n "$CTX_DIR" ] && [ -n "$pct" ] && [ "$name" != "unnamed" ]; then
  f=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-')
  mkdir -p "$CTX_DIR" 2>/dev/null && printf '%s\n' "$pct" > "$CTX_DIR/$f.txt" 2>/dev/null
fi
if [ -n "${SABHA_IMPL:-}" ] && { [ -n "$h5" ] || [ -n "$d7" ]; }; then
  # shellcheck source=sabha-limits.sh
  . "$BIN/sabha-limits.sh"
  [ -n "$h5" ] && sabha_limits_write five_hour "$h5" "${h5r:-0}"
  [ -n "$d7" ] && sabha_limits_write seven_day "$d7" "${d7r:-0}"
  sabha_limits_alert
fi
exit 0
