#!/usr/bin/env bash
# setup-workers-user.sh - create the unprivileged WORKERS_USER that runs agy and opencode with their approval
# prompts off, while keeping the owner's secrets and the cloud metadata address out of reach.
#
#   sudo bash bin/setup-workers-user.sh            # needs sudo once
#   sudo ROOTLESS_DOCKER=1 bash bin/setup-workers-user.sh
#
# Idempotent. It never loosens a permission, never flushes firewall rules and never copies a credential.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0" >&2; exit 1; }
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../lib/common.sh"
sw_load_conf
sw_need SABHA_WORKSPACE

W=$WORKERS_USER
WH=$WORKERS_HOME
step() { printf '\n==> %s\n' "$*"; }

RO_DIR=""
if [ -n "${REPO_DIR:-}" ] && [ -d "$REPO_DIR/$READONLY_SUBDIR" ]; then RO_DIR=$REPO_DIR/$READONLY_SUBDIR; fi
[ -d "$SABHA_WORKSPACE" ] || { echo "SABHA_WORKSPACE $SABHA_WORKSPACE does not exist" >&2; exit 1; }

# traverse-only directories: every ancestor of the workspace and of the read-only dir, inside the owner's home
TRAVERSE=$(
  sw_chain "$SABHA_WORKSPACE"
  if [ -n "$RO_DIR" ]; then sw_chain "$RO_DIR"; fi
  if [ -n "${REPO_DIR:-}" ]; then sw_chain "$REPO_DIR"; echo "$REPO_DIR"; fi
) || true
TRAVERSE=$(printf '%s\n' "$TRAVERSE" | sort -u)
OPEN_TOPS=" "
for p in "$SABHA_WORKSPACE" "$RO_DIR" "${REPO_DIR:-}"; do
  [ -n "$p" ] || continue
  t=$(sw_top_of "$p"); [ -n "$t" ] && OPEN_TOPS="$OPEN_TOPS$t "
done

# ---------------------------------------------------------------- a. user
step "a. user '$W' (no sudo, not in docker/sudo/adm/lxd)"
if id "$W" >/dev/null 2>&1; then
  echo "    user exists"
else
  useradd --create-home --home-dir "$WH" --shell /bin/bash "$W"
  echo "    created (no password: reachable only through sudo -u $W from the owner)"
fi
BAD=""
for g in docker sudo adm lxd; do
  if id -nG "$W" | tr ' ' '\n' | grep -qx "$g"; then BAD="$BAD $g"; fi
done
if [ -n "$BAD" ]; then
  echo "    ERROR: $W is in forbidden group(s):$BAD" >&2
  echo "    Remove with: sudo gpasswd -d $W <group>   (then rerun)" >&2
  exit 1
fi
echo "    group check OK: $(id -nG "$W")"
chmod go-w,o-rwx "$WH"

# --------------------------------------------- b. tighten the owner's secrets
step "b. tighten the owner's home and secret paths (tighten only)"
cur=$(stat -c %a "$OWNER_HOME")
echo "    $OWNER_HOME currently $cur"
case "$cur" in
  700|750) echo "    ok, leaving as is" ;;
  *)       chmod 750 "$OWNER_HOME"; echo "    tightened to 750" ;;
esac
for rel in $SW_DEFAULT_SECRET_FILES ${EXTRA_SECRET_FILES:-}; do
  f=$OWNER_HOME/$rel
  [ -f "$f" ] && [ ! -L "$f" ] || continue
  chmod 600 "$f"; echo "    file $f -> $(stat -c %a "$f")"
done
for rel in $SW_DEFAULT_SECRET_DIRS ${EXTRA_SECRET_DIRS:-}; do
  d=$OWNER_HOME/$rel
  [ -d "$d" ] && [ ! -L "$d" ] || continue
  chmod 700 "$d"; echo "    dir  $d -> $(stat -c %a "$d")"
done
# The traverse ACL in step c lets workers pass through the owner's home, so anything in it whose "other" bits
# are open would be reachable. Close group/other on every top-level entry except the ones workers need.
# Non-recursive: removing x from the top directory already blocks the subtree.
echo "    closing group/other bits on top-level entries of $OWNER_HOME"
while IFS= read -r -d '' e; do
  case "$OPEN_TOPS" in *" $e "*) continue ;; esac
  case " ${KEEP_OPEN:-} " in *" $e "*|*" ${e#"$OWNER_HOME"/} "*) continue ;; esac
  [ -L "$e" ] && continue
  m=$(stat -c %a "$e")
  case "$m" in
    *00) : ;;
    *) chmod go-rwx "$e"; echo "      $e $m -> $(stat -c %a "$e")" ;;
  esac
done < <(find "$OWNER_HOME" -mindepth 1 -maxdepth 1 -print0)

# ------------------------------------------------- c. shared hand-off, ACLs
step "c. POSIX ACLs for the Sabha hand-off"
if ! command -v setfacl >/dev/null 2>&1; then
  echo "    setfacl missing, installing package 'acl'"
  apt-get update -qq && apt-get install -y acl
fi
for d in $TRAVERSE; do
  setfacl -m "u:$W:--x" "$d"; echo "    traverse-only: $d"
done
# read/write workspace, plus a default ACL so new files inherit it; the owner keeps rwX on what workers create.
setfacl -R -m "u:$W:rwX,u:$OWNER_USER:rwX" "$SABHA_WORKSPACE"
setfacl -R -d -m "u:$W:rwX,u:$OWNER_USER:rwX" "$SABHA_WORKSPACE"
echo "    read/write (+default): $SABHA_WORKSPACE"
if [ -n "$RO_DIR" ]; then
  setfacl -R -m "u:$W:rX" "$RO_DIR"
  setfacl -R -d -m "u:$W:rX" "$RO_DIR"
  echo "    read-only: $RO_DIR"
fi
[ -n "${REPO_DIR:-}" ] && echo "    NOTE: no write access is granted anywhere under $REPO_DIR (so .git/hooks stays safe)."

# ------------------------------------------------------ d. code work area
step "d. $WH/work (their own clones and worktrees)"
install -d -o "$W" -g "$W" -m 750 "$WH/work"
install -d -o "$W" -g "$W" -m 755 "$WH/.local" "$WH/.local/bin" "$WH/.opencode" "$WH/.opencode/bin" \
  "$WH/.config" "$WH/.config/opencode"

# ------------------------------------------------- e. metadata firewall rule
step "e. block $META_IP for uid $W (additive iptables rule, no flush)"
if iptables -C OUTPUT -m owner --uid-owner "$W" -d "$META_IP" -j REJECT 2>/dev/null; then
  echo "    rule already present"
else
  # -I OUTPUT 1 puts it ahead of any cloud image rule that accepts the link-local range
  iptables -I OUTPUT 1 -m owner --uid-owner "$W" -d "$META_IP" -j REJECT
  echo "    rule inserted at top of OUTPUT"
fi
# Persist ONLY this one rule with a tiny boot service. Do NOT save the whole live ruleset (iptables-save):
# that would freeze Docker's and Tailscale's dynamic rules and can break networking after a reboot.
cat > "/etc/systemd/system/$W-metadata-block.service" <<UNIT
[Unit]
Description=Block the cloud metadata address for the $W user
After=netfilter-persistent.service network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -C OUTPUT -m owner --uid-owner $W -d $META_IP -j REJECT 2>/dev/null || iptables -I OUTPUT 1 -m owner --uid-owner $W -d $META_IP -j REJECT'

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable "$W-metadata-block.service"
echo "    boot service $W-metadata-block.service enabled (rules.v4 untouched)"

# ---------------------------------------------------------- f. tools
step "f. copy agy and opencode binaries into the workers' home (no auth files)"
# Both are self-contained apart from glibc, so a copy is enough. If an update needs more files next to the
# binary, install as the workers user with the vendor installer instead.
for pair in "$AGY_SRC:$WH/.local/bin/agy" "$OPENCODE_SRC:$WH/.opencode/bin/opencode"; do
  src=${pair%%:*}; dst=${pair##*:}
  if [ -x "$src" ]; then
    install -o "$W" -g "$W" -m 755 "$src" "$dst"; echo "    copied $src -> $dst"
  else
    echo "    WARNING: $src not found or not executable, skipped"
  fi
done

# ------------------------------------------------- g. permissions off
step "g. opencode config for the workers (permission prompts off)"
OC_CFG=$WH/.config/opencode/opencode.jsonc
if [ -e "$OC_CFG" ]; then
  echo "    $OC_CFG exists, leaving it alone"
else
  {
    echo '{'
    echo '  "$schema": "https://opencode.ai/config.json",'
    [ -n "${OPENCODE_MODEL:-}" ] && echo "  \"model\": \"$OPENCODE_MODEL\","
    [ -n "${OPENCODE_SMALL_MODEL:-}" ] && echo "  \"small_model\": \"$OPENCODE_SMALL_MODEL\","
    echo '  "permission": {'
    echo '    "edit": "allow",'
    echo '    "bash": "allow",'
    echo '    "webfetch": "allow",'
    echo '    "external_directory": "allow"'
    echo '  }'
    echo '}'
  } > "$OC_CFG"
  chown "$W:$W" "$OC_CFG"; chmod 600 "$OC_CFG"
  echo "    wrote $OC_CFG"
fi
echo "    agy: no config file; the pane command carries '--mode auto --dangerously-skip-permissions'"

# ------------------------------------------------------ h. rootless Docker
step "h. rootless Docker for the workers (optional)"
# Never put the workers in the 'docker' group: the daemon socket is root-equivalent and they could read every
# secret. A rootless daemon lives entirely inside the workers account, separate from the owner's Docker.
if [ "$ROOTLESS_DOCKER" = "1" ]; then
  apt-get install -y uidmap dbus-user-session
  if ! grep -q "^$W:" /etc/subuid; then usermod --add-subuids 100000-165535 "$W"; fi
  if ! grep -q "^$W:" /etc/subgid; then usermod --add-subgids 100000-165535 "$W"; fi
  loginctl enable-linger "$W"
  if command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
    uid=$(id -u "$W")
    sudo -u "$W" -H env XDG_RUNTIME_DIR="/run/user/$uid" bash -lc 'dockerd-rootless-setuptool.sh install'
    echo "    rootless docker installed (DOCKER_HOST=unix:///run/user/$uid/docker.sock)"
  else
    echo "    dockerd-rootless-setuptool.sh not found: install docker-ce-rootless-extras, then rerun"
  fi
else
  echo "    skipped (set ROOTLESS_DOCKER=1 to enable)"
fi

step "done. Next: sudo bash $(dirname "$0")/check-workers.sh"
