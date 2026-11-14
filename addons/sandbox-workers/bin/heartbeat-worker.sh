#!/usr/bin/env bash
# Heartbeat for a sandboxed worker pane, run from the owner's cron.
# Usage: heartbeat-worker.sh <Role> <pane> <proc> <busy-regex>
#   e.g. heartbeat-worker.sh Builder %1 opencode "esc +interrupt"   (role, pane id, process name, busy regex)
# herdr cannot detect agents that run as another user, so state comes from the screen and the process list.
# idle -> nudge to continue; stuck prompt -> alert; process gone -> alert; same screen 3 beats -> alert once.
# Stops nudging when status/<role-lowercase>.md in the workspace contains QUEUE EMPTY.
# Runs as the OWNER (herdr belongs to the owner). Bash 3.2 safe.
set -uo pipefail

if [ $# -ne 4 ]; then echo "usage: $0 <Role> <pane> <proc> <busy-regex>" >&2; exit 2; fi
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
sw_need SABHA_WORKSPACE || exit 1
export PATH="$OWNER_HOME/.local/bin:$PATH"

ROLE=$1; PANE=$2; PROC=$3; BUSY=$4
WS=$SABHA_WORKSPACE
LOWER=$(echo "$ROLE" | tr 'A-Z' 'a-z')
ST=$HEARTBEAT_STATE_DIR/heartbeat-$LOWER; mkdir -p "$ST"; LOG=$ST/log.txt; touch "$LOG"
H="$HERDR_BIN"
SESS=""
[ -n "$HERDR_SESSION" ] && SESS="--session $HERDR_SESSION"
# herdr takes the session flag before the subcommand; $SESS is intentionally unquoted
hd() { # shellcheck disable=SC2086
  "$H" $SESS "$@"; }
note() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }
alert() { "$SW_ROOT/backup/notify.sh" "heartbeat $ROLE" "$1" || true; note "ALERT $1"; }
if [ "$(wc -l < "$LOG")" -gt 500 ]; then tail -200 "$LOG" > "$LOG.tmp"; mv "$LOG.tmp" "$LOG"; fi

if grep -q 'QUEUE EMPTY' "$WS/status/$LOWER.md" 2>/dev/null; then note "queue empty"; exit 0; fi
screen=$(hd pane read "$PANE" --lines 60 2>/dev/null) || { note "herdr unreachable"; exit 0; }
if ! pgrep -u "$WORKERS_USER" -f "$PROC" >/dev/null; then
  [ -f "$ST/alerted-dead" ] || { alert "$PROC is not running (pane at a shell?)"; touch "$ST/alerted-dead"; }
  exit 0
fi
rm -f "$ST/alerted-dead"

hash=$(printf '%s' "$screen" | md5sum | cut -c1-12)
prev=$(cat "$ST/hash" 2>/dev/null || echo none); same=$(cat "$ST/same" 2>/dev/null || echo 0)
if [ "$hash" = "$prev" ]; then same=$((same+1)); else same=0; fi
echo "$hash" > "$ST/hash"; echo "$same" > "$ST/same"

if printf '%s' "$screen" | grep -q -i -E 'permission required|requesting permission|Allow once'; then state=blocked
elif printf '%s' "$screen" | grep -q -E "$BUSY"; then state=working
else state=idle; fi
note "state=$state same=$same"

case "$state" in
  blocked) [ -f "$ST/alerted-blocked" ] || { alert "stuck on a permission prompt"; touch "$ST/alerted-blocked"; } ;;
  idle)
    rm -f "$ST/alerted-blocked"
    if [ "$same" -ge 1 ]; then   # idle on two beats in a row, so it is not mid-thought
      if hd pane send-text "$PANE" "Heartbeat: continue your overnight queue. Read $WS/inbox/$ROLE/ for your newest brief (the night-queue brief if there is one). Do the next unfinished brief. If everything is done or blocked, write QUEUE EMPTY plus one line per brief in $WS/status/$LOWER.md." >/dev/null 2>&1 \
        && hd pane send-keys "$PANE" Enter >/dev/null 2>&1; then note "nudged"; else note "nudge failed"; fi
    fi ;;
  *) rm -f "$ST/alerted-blocked" ;;
esac
if [ "$same" -ge 3 ] && [ ! -f "$ST/alerted-stall" ]; then alert "screen unchanged ~60 min (state=$state)"; touch "$ST/alerted-stall"; fi
[ "$same" -eq 0 ] && rm -f "$ST/alerted-stall"
exit 0
