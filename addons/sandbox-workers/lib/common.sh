# shellcheck shell=bash
# Shared by every sandbox-workers script: find and load sandbox.conf, set defaults. Bash 3.2 safe (no mapfile,
# no associative arrays, no ${x,,}). Source it; it does not change shell options.

SW_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

sw_passwd_home() { # user -> home dir from the passwd database
  local h
  h=$(getent passwd "$1" 2>/dev/null | cut -d: -f6)
  printf '%s' "${h:-/home/$1}"
}

sw_load_conf() {
  : "${OWNER_USER:=${SUDO_USER:-$(id -un)}}"
  : "${OWNER_HOME:=$(sw_passwd_home "$OWNER_USER")}"
  local c cand
  c=""
  for cand in "${SANDBOX_CONF:-}" "$OWNER_HOME/.config/sandbox-workers/sandbox.conf" "$SW_ROOT/sandbox.conf"; do
    if [ -n "$cand" ] && [ -f "$cand" ]; then c=$cand; break; fi
  done
  if [ -n "$c" ]; then
    # shellcheck disable=SC1090
    . "$c"
  elif [ "${SW_NEED_CONF:-1}" = 1 ]; then
    echo "sandbox-workers: no sandbox.conf found (copy sandbox.conf.example; see README)" >&2
    return 1
  fi
  SW_CONF_FILE=$c
  : "${WORKERS_USER:=workers}"
  : "${WORKERS_HOME:=/home/$WORKERS_USER}"
  : "${META_IP:=169.254.169.254}"
  : "${CHECK_METADATA_CONTROL:=1}"
  : "${AGY_SRC:=$OWNER_HOME/.local/bin/agy}"
  : "${OPENCODE_SRC:=$OWNER_HOME/.opencode/bin/opencode}"
  : "${ROOTLESS_DOCKER:=0}"
  : "${READONLY_SUBDIR:=.sabha}"
  : "${HERDR_BIN:=herdr}"
  : "${HERDR_SESSION=sabha}"
  : "${HEARTBEAT_STATE_DIR:=$OWNER_HOME/.cache/sandbox-workers}"
  : "${NTFY_SERVER:=https://ntfy.sh}"
  : "${BACKUP_DIR:=$OWNER_HOME/backup-state}"
  : "${DUMP_DIR:=$BACKUP_DIR/dumps}"
  : "${RESTIC_PASSWORD_FILE:=$OWNER_HOME/.config/sandbox-workers/restic-password}"
  : "${KEEP_HOURLY:=24}" "${KEEP_DAILY:=14}" "${KEEP_WEEKLY:=8}" "${KEEP_MONTHLY:=12}" "${CHECK_EVERY_DAYS:=7}"
  : "${CONFIG_BRANCH:=main}" "${CONFIG_PUSH:=0}"
  : "${SYNC_GIT_NAME:=sandbox-workers sync}" "${SYNC_GIT_EMAIL:=sync@localhost}"
  if [ -n "${SABHA_WORKSPACE:-}" ]; then : "${SABHA_PARENT:=$(dirname "$SABHA_WORKSPACE")}"; fi
  return 0
}

sw_need() { # VAR ... : fail with a clear message if any is empty
  local v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then echo "sandbox-workers: $v is required in sandbox.conf" >&2; return 1; fi
  done
}

# Echo every directory from OWNER_HOME down to (not including) $1, when $1 is inside OWNER_HOME.
sw_chain() {
  local p d
  p=$1
  case "$p" in "$OWNER_HOME"/*) ;; *) return 0 ;; esac
  d=$(dirname "$p")
  while [ "$d" != "$OWNER_HOME" ] && [ "$d" != "/" ]; do
    printf '%s\n' "$d"
    d=$(dirname "$d")
  done
  printf '%s\n' "$OWNER_HOME"
}

# The top-level entry of OWNER_HOME that contains $1 (empty if outside).
sw_top_of() {
  case "$1" in "$OWNER_HOME"/*) local r=${1#"$OWNER_HOME"/}; printf '%s/%s' "$OWNER_HOME" "${r%%/*}" ;; esac
}

SW_DEFAULT_SECRET_FILES=".claude/.credentials.json .config/gh/hosts.yml .local/share/opencode/auth.json .config/rclone/rclone.conf .netrc .npmrc .config/sandbox-workers/sandbox.conf .config/sandbox-workers/restic-password"
SW_DEFAULT_SECRET_DIRS=".ssh .oci .aws .gnupg .claude .config/gh .config/herdr .config/rclone .config/sandbox-workers .local/share/opencode"
