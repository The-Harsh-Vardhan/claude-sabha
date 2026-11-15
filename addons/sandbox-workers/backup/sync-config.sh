#!/usr/bin/env bash
# Copy config into CONFIG_REPO_DIR, secret-scan it, commit (and push when CONFIG_PUSH=1) only if it changed.
# A scan finding stops everything: nothing is committed and an alert is sent. Disabled while CONFIG_REPO_DIR is empty.
set -uo pipefail
umask 077
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
[ -n "${CONFIG_REPO_DIR:-}" ] || { echo "sync-config: CONFIG_REPO_DIR is empty, nothing to do"; exit 0; }
[ -n "${CONFIG_SYNC_DIRS:-}" ] || { echo "sync-config: CONFIG_SYNC_DIRS is empty, nothing to do"; exit 0; }
export PATH="$OWNER_HOME/.local/bin:$PATH"
R=$CONFIG_REPO_DIR
mkdir -p "$BACKUP_DIR/logs"
exec >>"$BACKUP_DIR/logs/sync-config.log" 2>&1
echo "[sync] $(date -u +%FT%TZ)"
cd "$R" || exit 1
alert() { echo "[sync] $*"; "$SW_ROOT/backup/notify.sh" "config sync problem" "$*"; }

for pair in $CONFIG_SYNC_DIRS; do
  src=${pair%%:*}; dest=${pair#*:}
  case "$dest" in /*|*..*|"") alert "bad CONFIG_SYNC_DIRS entry (dest must be relative): $pair"; exit 1 ;; esac
  mkdir -p "$R/$dest"
  rsync -a --delete --exclude-file="$SW_ROOT/backup/excludes.txt" "$src/" "$R/$dest/" || { alert "rsync failed for $pair"; exit 1; }
done
chmod -R go-w . 2>/dev/null

if ! "$SW_ROOT/backup/secret-scan.sh" "$R"; then
  alert "secret scan found key-like strings in the config repo; NOT committed. Run backup/secret-scan.sh on it."
  git reset -q 2>/dev/null
  exit 1
fi
git add -A
if git diff --cached --quiet; then echo "[sync] no changes"; exit 0; fi
git -c user.name="$SYNC_GIT_NAME" -c user.email="$SYNC_GIT_EMAIL" commit -q -m "sync config $(date -u +%F\ %H:%MZ)" || { alert "commit failed"; exit 1; }
if [ "$CONFIG_PUSH" = 1 ]; then
  git push -q origin "$CONFIG_BRANCH" || { alert "git push of the config repo failed"; exit 1; }
  echo "[sync] pushed $(git rev-parse --short HEAD)"
else
  echo "[sync] committed $(git rev-parse --short HEAD) (CONFIG_PUSH=0, not pushed)"
fi
