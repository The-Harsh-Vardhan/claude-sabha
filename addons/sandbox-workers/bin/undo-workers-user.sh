#!/usr/bin/env bash
# undo-workers-user.sh - print (default) or run (--apply, as root) the commands that remove what
# setup-workers-user.sh added. The mode tightening of the owner's files is NOT undone (it only removed access).
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
sw_need SABHA_WORKSPACE || exit 1
W=$WORKERS_USER
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
if [ "$APPLY" = 1 ] && [ "$(id -u)" -ne 0 ]; then echo "--apply needs root (sudo)" >&2; exit 1; fi

RO_DIR=""
if [ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR/$READONLY_SUBDIR" ]; then RO_DIR=$REPO_DIR/$READONLY_SUBDIR; fi
run() { if [ "$APPLY" = 1 ]; then echo "+ $*"; "$@" || true; else printf '%s\n' "$*"; fi; }

run iptables -D OUTPUT -m owner --uid-owner "$W" -d "$META_IP" -j REJECT
run systemctl disable --now "$W-metadata-block.service"
run rm -f "/etc/systemd/system/$W-metadata-block.service"
run systemctl daemon-reload
for d in $( { sw_chain "$SABHA_WORKSPACE"; [ -n "${REPO_DIR:-}" ] && { sw_chain "$REPO_DIR"; echo "$REPO_DIR"; }; } | sort -u ); do
  run setfacl -x "u:$W" "$d"
done
for d in "$SABHA_WORKSPACE" "$RO_DIR"; do
  [ -n "$d" ] || continue
  run setfacl -R -x "u:$W" "$d"
  run setfacl -R -x "d:u:$W" "$d"
done
# the owner's own entries on the workspace (extra, harmless; remove only if you want them gone)
run setfacl -R -x "u:$OWNER_USER" "$SABHA_WORKSPACE"
run setfacl -R -x "d:u:$OWNER_USER" "$SABHA_WORKSPACE"
if [ "$ROOTLESS_DOCKER" = 1 ]; then run loginctl disable-linger "$W"; fi
run pkill -u "$W"
run userdel -r "$W"
if [ "$APPLY" != 1 ]; then echo "# printed only; run again with --apply as root to execute" >&2; fi
