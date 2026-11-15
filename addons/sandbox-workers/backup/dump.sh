#!/usr/bin/env bash
# Run every executable *.sh in dump.d/ (next to this script, or DUMP_HOOKS_DIR). Each hook writes its dump
# into $DUMP_DIR (mode 700, exported here) and must exit non-zero on failure. Dumps go only to the encrypted
# restic repo, never to git. With no hooks this does nothing.
set -uo pipefail
umask 077
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
HOOKS=${DUMP_HOOKS_DIR:-$SW_ROOT/backup/dump.d}
mkdir -p "$DUMP_DIR"; chmod 700 "$DUMP_DIR"
export DUMP_DIR
log() { echo "[dump $(date -u +%FT%TZ)] $*"; }
rc=0
for h in "$HOOKS"/*.sh; do
  [ -f "$h" ] && [ -x "$h" ] || continue
  if "$h"; then log "$(basename "$h") ok"; else log "$(basename "$h") FAILED"; rc=1; fi
done
exit $rc
