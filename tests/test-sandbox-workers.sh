#!/usr/bin/env bash
# addons/sandbox-workers: bash -n on every script, shellcheck when installed, a dry config load, and a grep that
# keeps site-specific or personal values out of the add-on. Offline: no sudo, no network, touches nothing.
# Run: tests/test-sandbox-workers.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
A=$ROOT/addons/sandbox-workers
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

scripts=$(find "$A" -type f \( -name '*.sh' -o -name '*.example' \) -perm -u+x; find "$A" -name '*.sh' -type f)
scripts=$(printf '%s\n' "$scripts" | sort -u)
check "addon folder has scripts" '[[ -n $scripts ]]'
for s in $scripts; do
  check "bash -n ${s#"$ROOT"/}" 'bash -n "$s"'
done

if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  check "shellcheck" 'shellcheck -x -S warning $scripts'
else
  echo "skip: shellcheck is not installed"
fi

# the example config must parse and load with only the two required values set
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sw-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
sed -e "s|^SABHA_WORKSPACE=.*|SABHA_WORKSPACE=$tmp/ws|" -e "s|^BACKUP_REPO=.*|BACKUP_REPO=$tmp/repo|" \
  "$A/sandbox.conf.example" >"$tmp/sandbox.conf"
check "example config loads with defaults" \
  '( export SANDBOX_CONF=$tmp/sandbox.conf OWNER_USER=tester OWNER_HOME=$tmp/home; . "$A/lib/common.sh"; sw_load_conf \
     && [[ $WORKERS_USER == workers && $META_IP == 169.254.169.254 && $SABHA_PARENT == $tmp ]] )'
check "backup refuses to run without a password source" \
  '( export SANDBOX_CONF=$tmp/sandbox.conf OWNER_USER=tester OWNER_HOME=$tmp/home PATH=$tmp/nobin:$PATH
     mkdir -p "$tmp/nobin" "$tmp/home"; printf "#!/bin/sh\nexit 0\n" >"$tmp/nobin/restic"; chmod +x "$tmp/nobin/restic"
     "$A/backup/backup.sh"; rc=$?; [[ $rc -ne 0 ]] && grep -rq "password file missing" "$tmp/home/backup-state/logs" )'
check "excludes keep secrets out of the backup" \
  'for p in ".env" "*.pem" "rclone.conf" ".ssh" ".credentials.json" "restic-password"; do grep -qxF -e "$p" "$A/backup/excludes.txt" || exit 1; done'

# forbidden strings. Site-specific values are written in pieces so this file does not hold them itself.
owner_name=$(git -C "$ROOT" log -1 --format=%an 2>/dev/null)
owner_mail=$(git -C "$ROOT" log -1 --format=%ae 2>/dev/null)
forbid=(
  '/home/ubu''ntu' 'Gram''IQ' 'gram''iq' 'free-''a1' 'oracle-''vm' 'sabha-''alerts' 'kp''3' 'n8''n ' 'w1:''p[0-9]'
  'vault-''secret' 'restic-backup-''password' 'deepseek-''v' 'The-Harsh-''Vardhan' ':80''90'
)
forbid_re=(
  '100\.[0-9]+\.[0-9]+\.[0-9]+' '(^|[^0-9.])10\.[0-9]+\.[0-9]+\.[0-9]+' 'ocid1\.' '-----BEGIN ([A-Z]+ )*PRIVATE KEY-----'
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' 'AKIA[0-9A-Z]{16}' 'eu-[a-z]+-[0-9]|ap-[a-z]+-[0-9]|us-[a-z]+-[0-9]'
)
[[ -n $owner_name ]] && forbid+=("$owner_name")
[[ -n $owner_mail ]] && forbid+=("$owner_mail")
for f in "${forbid[@]}"; do
  check "no '${f:0:4}...' in the add-on" '! grep -rIqF -e "$f" "$A"'
done
for r in "${forbid_re[@]}"; do
  check "no match for /${r:0:18}/ in the add-on" '! grep -rIqE -e "$r" "$A"'
done

echo
if ((fails)); then echo "$fails FAILED"; exit 1; fi
echo "all passed"
