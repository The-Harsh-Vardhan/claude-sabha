#!/usr/bin/env bash
# Full backup: run dump hooks, restic backup to BACKUP_REPO (always encrypted), prune, periodic check.
# Run as the OWNER from cron. Never run as the workers user. Bash 3.2 safe.
set -uo pipefail
umask 077
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
sw_need BACKUP_REPO || exit 1
export PATH="$OWNER_HOME/.local/bin:$OWNER_HOME/bin:$PATH"
B=$BACKUP_DIR
mkdir -p "$B/logs"; chmod 700 "$B"
LOG="$B/logs/backup-$(date -u +%Y%m%dT%H%M%SZ).log"
exec >>"$LOG" 2>&1

export RESTIC_REPOSITORY="$BACKUP_REPO"
# Password source: a command if given, else a mode-600 file. There is no way to run without a password.
if [ -n "${RESTIC_PASSWORD_COMMAND:-}" ]; then
  unset RESTIC_PASSWORD_FILE
  export RESTIC_PASSWORD_COMMAND
else
  unset RESTIC_PASSWORD_COMMAND
  export RESTIC_PASSWORD_FILE
fi

fail() {
  echo "[backup] FAILED: $*"
  "$SW_ROOT/backup/notify.sh" "Backup FAILED on $(hostname -s)" "$* (log: $LOG)"
  ls -1t "$B"/logs/backup-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f
  exit 1
}
START=$(date +%s)
echo "[backup] start $(date -u +%FT%TZ) repo=$BACKUP_REPO"
command -v restic >/dev/null || fail "restic is not installed"

# Preflight: the remote and the password must exist.
case "$BACKUP_REPO" in
  rclone:*)
    remote="${BACKUP_REPO#rclone:}"; remote="${remote%%:*}"
    rclone listremotes 2>/dev/null | grep -qx "${remote}:" \
      || fail "rclone remote '${remote}' is not configured (run: rclone config)"
    ;;
esac
if [ -n "${RESTIC_PASSWORD_COMMAND:-}" ]; then
  sh -c "$RESTIC_PASSWORD_COMMAND" 2>/dev/null | head -c1 | grep -q . \
    || fail "the restic password command printed nothing"
else
  [ -s "$RESTIC_PASSWORD_FILE" ] || fail "restic password file missing or empty: $RESTIC_PASSWORD_FILE"
  case "$(stat -c %a "$RESTIC_PASSWORD_FILE" 2>/dev/null || stat -f %Lp "$RESTIC_PASSWORD_FILE")" in
    ?00) : ;;
    *) fail "restic password file must be mode 600 (chmod 600 $RESTIC_PASSWORD_FILE)" ;;
  esac
fi

"$SW_ROOT/backup/dump.sh" || fail "dump.sh failed"

if ! restic cat config >/dev/null 2>&1; then
  echo "[backup] repo not readable, trying init"
  restic init || fail "cannot open or init the restic repo"
fi

PATHS=${BACKUP_PATHS:-}
if [ -z "$PATHS" ]; then PATHS="${SABHA_PARENT:-} $DUMP_DIR"; fi
EXARGS=""
for x in ${BACKUP_EXTRA_EXCLUDES:-}; do EXARGS="$EXARGS --exclude $x"; done
# paths and patterns have no spaces (documented); word splitting is intended
# shellcheck disable=SC2086
restic backup --tag auto --exclude-file="$SW_ROOT/backup/excludes.txt" --exclude "$B/logs" $EXARGS $PATHS \
  || fail "restic backup failed"

restic forget --prune --keep-hourly "$KEEP_HOURLY" --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
  --keep-monthly "$KEEP_MONTHLY" || fail "restic forget/prune failed"

MARK="$B/.last-check"
if [ ! -f "$MARK" ] || [ -n "$(find "$MARK" -mtime +$((CHECK_EVERY_DAYS-1)) 2>/dev/null)" ]; then
  restic check && touch "$MARK" || fail "restic check failed"
fi

echo "[backup] OK in $(( $(date +%s) - START ))s"
ls -1t "$B"/logs/backup-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f
