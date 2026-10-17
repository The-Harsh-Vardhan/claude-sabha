#!/usr/bin/env bash
# Stop: a reminder only. A role that works a brief but leaves its handoff stale loses the work at the next restart.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0
hk_init || exit 0

open=$(hk_open_briefs acked)
[ -n "$open" ] || exit 0
sf=$(hk_status_file)
max=${SABHA_HANDOFF_MAX_AGE:-30}
case $max in ''|*[!0-9]*) max=30 ;; esac
# find -mmin exits 0 either way, so the output decides: a fresh file prints its name
if [ -f "$sf" ] && [ -n "$(find "$sf" -mmin "-$max" 2>/dev/null)" ]; then
  exit 0
fi
echo "[sabha] You have an open brief ($(printf '%s' "$open" | head -n 1)) and status/$(hk_lower "$HK_ROLE").md was not updated in the last $max minutes. Update it (Task, Done, Next, Constraints) before you stop."
exit 0
