#!/usr/bin/env bash
# check-workers.sh - verify the workers sandbox. Run with: sudo bash bin/check-workers.sh
# PASS/FAIL per check, non-zero exit on any FAIL. It only tests whether paths can be opened and never prints
# file contents.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo" >&2; exit 1; }
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf || exit 1
sw_need SABHA_WORKSPACE || exit 1

U=$OWNER_HOME
W=$WORKERS_USER
FAILS=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS+1)); }
asw() { sudo -u "$W" -H bash -c "$1" >/dev/null 2>&1; }
expect_denied() { if asw "$2"; then fail "$1 (workers CAN do it)"; else pass "$1 denied"; fi; }
expect_allowed() { if asw "$2"; then pass "$1"; else fail "$1 (workers cannot)"; fi; }

OPEN_TOPS=" "
for p in "$SABHA_WORKSPACE" "${REPO_DIR:-}"; do
  [ -n "$p" ] || continue
  t=$(sw_top_of "$p"); [ -n "$t" ] && OPEN_TOPS="$OPEN_TOPS$t "
done

echo "== 1. secrets unreadable by workers =="
for rel in .ssh .oci .claude .config/sandbox-workers ${EXTRA_SECRET_DIRS:-}; do
  if [ -e "$U/$rel" ]; then expect_denied "list $U/$rel" "ls '$U/$rel'"; else echo "SKIP  $U/$rel does not exist"; fi
done
for rel in .claude/.credentials.json .config/gh/hosts.yml .local/share/opencode/auth.json .config/sandbox-workers/restic-password ${EXTRA_SECRET_FILES:-}; do
  if [ -e "$U/$rel" ]; then expect_denied "open $U/$rel" "head -c0 '$U/$rel'"; else echo "SKIP  $U/$rel missing"; fi
done
if [ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR" ]; then
  # any .env* in the repo except the committed .env.example template
  while IFS= read -r f; do
    expect_denied "open $f" "head -c0 '$f'"
  done < <(find "$REPO_DIR" -maxdepth 3 -name '.env*' -not -name '.env.example' \
             -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
fi

echo "== 2. home directory not listable =="
expect_denied "ls $U" "ls '$U'"
leaks=0
while IFS= read -r -d '' e; do
  case "$OPEN_TOPS" in *" $e "*) continue ;; esac
  if asw "test -r '$e' || test -x '$e'"; then fail "workers can reach top-level $e (run setup again)"; leaks=1; fi
done < <(find "$U" -mindepth 1 -maxdepth 1 -print0)
[ "$leaks" -eq 0 ] && pass "no other top-level entry of $U reachable"
[ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR" ] && expect_denied "list $REPO_DIR" "ls '$REPO_DIR'"

echo "== 3. metadata service =="
if asw "curl -s -m 5 -o /dev/null -f http://$META_IP/ -H 'Authorization: Bearer Oracle'"; then
  fail "workers CAN reach $META_IP"
else
  pass "workers cannot reach $META_IP"
fi
if [ "$CHECK_METADATA_CONTROL" = 1 ]; then
  code=$(sudo -u "$OWNER_USER" -H curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$META_IP/" 2>/dev/null || true)
  echo "INFO  control (owner) HTTP status: ${code:-none}"
  case "${code:-}" in
    2??|3??|4??) pass "control: the owner still gets an answer from $META_IP" ;;
    *) fail "control: the owner got '${code:-none}' (no metadata service here? set CHECK_METADATA_CONTROL=0)" ;;
  esac
fi

echo "== 4. workers can write where intended =="
tag="chk-$$-$(date +%s)"
for dir in "$WORKERS_HOME/work" "$SABHA_WORKSPACE"; do
  f="$dir/.$tag"
  if asw "echo a > '$f' && echo b >> '$f' && rm -f '$f'"; then pass "create/edit/delete in $dir"
  else fail "create/edit/delete in $dir"; rm -f "$f"; fi
done
f=$SABHA_WORKSPACE/.$tag-x
sudo -u "$W" -H bash -c "echo x > '$f'" 2>/dev/null
if sudo -u "$OWNER_USER" -H bash -c "echo y >> '$f'" 2>/dev/null; then pass "the owner can edit a file workers created in the workspace"
else fail "the owner cannot edit a workers-created file in the workspace (default ACL missing?)"; fi
rm -f "$f"

echo "== 5. no escalation paths =="
if [ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR" ]; then
  if [ -d "$REPO_DIR/.git/hooks" ]; then
    expect_denied "write $REPO_DIR/.git/hooks" "touch '$REPO_DIR/.git/hooks/.chk-$$'"
    rm -f "$REPO_DIR/.git/hooks/.chk-$$"
  fi
  expect_denied "write $REPO_DIR" "touch '$REPO_DIR/.chk-$$'"
  rm -f "$REPO_DIR/.chk-$$"
fi
expect_denied "docker ps (the owner's daemon)" "docker -H unix:///var/run/docker.sock ps"
expect_denied "sudo -n true" "sudo -n true"
for g in docker sudo adm lxd; do
  if id -nG "$W" | tr ' ' '\n' | grep -qx "$g"; then fail "workers is in group $g"; else pass "workers not in group $g"; fi
done

echo "== 6. tools =="
expect_allowed "agy --version" "$WORKERS_HOME/.local/bin/agy --version"
expect_allowed "opencode --version" "$WORKERS_HOME/.opencode/bin/opencode --version"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILS CHECK(S) FAILED"; fi
exit $((FAILS>0))
