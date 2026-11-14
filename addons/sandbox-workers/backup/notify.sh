#!/usr/bin/env bash
# Usage: notify.sh "title" "message"   (ntfy alert; never put secrets in the message)
# NTFY_TOPIC empty = nothing is sent. Reads NTFY_SERVER / NTFY_TOPIC from the environment or sandbox.conf.
SW_NEED_CONF=0
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf >/dev/null 2>&1 || true
[ -n "${NTFY_TOPIC:-}" ] || exit 0
curl -fsS -m 15 -H "Title: ${1:-sandbox-workers}" -H "Priority: high" -H "Tags: warning" \
  -d "${2:-}" "${NTFY_SERVER%/}/$NTFY_TOPIC" >/dev/null 2>&1 || true
