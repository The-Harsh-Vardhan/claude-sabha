# sandbox-workers (optional add-on)

Sabha with non-Claude workers (agy, opencode) that stall on permission prompts. This add-on runs those workers as a
separate, unprivileged Linux user with their approvals turned off, keeps them away from your secrets, keeps them
working overnight, and backs the machine up offsite. Nothing in the core tools changes; you opt in by running the
scripts below.

Status: the sandbox, its checks and the backup ran on one Ubuntu 24.04 aarch64 cloud VM. The pane restart flow, the
heartbeat on other setups and macOS are UNTESTED. Linux only (it uses `useradd`, POSIX ACLs and `iptables`).

## What it does, in plain words

1. **Sandbox user.** Creates a user (default `workers`) with no password, no sudo and no Docker. The agents run as
   that user with approvals off, so they do not stop and ask. A stalled prompt costs a night; a wrong command inside
   a fenced area costs little.
2. **Fences.** Your home is closed to other users, your secret files and folders are locked to mode 600/700, and the
   workers get only what they need: read/write on the Sabha workspace and their own `work` folder, traverse-only on
   the folders leading there, read-only on one protocol folder.
3. **Metadata block.** A firewall rule stops the workers reaching the cloud metadata address (169.254.169.254 by
   default), which would otherwise hand out the VM's own cloud credentials. Kept across reboots by a tiny systemd unit.
4. **Heartbeat.** A cron job looks at each worker pane every few minutes and types a "continue your queue" nudge when
   it is idle, and alerts you when it is stuck on a prompt, dead, or showing an unchanged screen. Needed because
   herdr cannot detect agents that run as another user.
5. **Backup.** restic to any repo (typically an rclone remote), encrypted, every 6 hours, with retention and a weekly
   integrity check; optional database dump hooks; optional secret-scanned config repo sync.

## Threat model and known limits

The goal is to stop an over-eager or confused agent, not a determined attacker.

- **Protected:** your SSH keys, cloud CLI config, gh/rclone/claude/opencode tokens, `.env` files, the metadata
  credentials, sudo, and your Docker daemon.
- **Internet egress is not blocked.** The workers can reach any website, any package registry and your private
  network. Only the metadata address is blocked, and only on IPv4.
- **Damage inside their own areas is possible.** They can delete or corrupt the shared Sabha workspace (briefs,
  status, queue) and everything in their home. Treat what they produce as untrusted, review it before use, and keep
  the backup running.
- **Your home must be closed to others.** The workers hold a traverse ACL on your home so they can reach the
  workspace. Anything in your home with open group/other bits and a guessable name is reachable. Setup closes the
  top-level entries once; anything you create later with mode 755 is not. Re-run setup or the checks after adding
  things and keep secrets in 700 folders.
- **Services you run locally are reachable** (anything listening on 127.0.0.1 or the VM address) without a login.
- **Docker is root-equivalent.** Never add the workers user to the `docker` group or hand it your socket. If a worker
  needs containers use the rootless option (`ROOTLESS_DOCKER=1`), a private daemon inside the workers account.
- `--dangerously-skip-permissions` and `allow` mean the agents run any shell command as the workers user unasked.
- The password for the backup is the key to the backup. Lose it and the backup cannot be read.

## Layout

    addons/sandbox-workers/
      README.md                     this file
      sandbox.conf.example          the one config file (copy, edit, chmod 600)
      lib/common.sh                 finds and loads the config, sets defaults
      bin/setup-workers-user.sh     run once with sudo
      bin/check-workers.sh          PASS/FAIL checks, run with sudo
      bin/undo-workers-user.sh      prints (or with --apply runs) the undo commands
      bin/heartbeat-worker.sh       cron heartbeat for one pane
      backup/backup.sh dump.sh sync-config.sh secret-scan.sh notify.sh
      backup/excludes.txt           files never backed up (keys, .env, credentials, ssh, rclone.conf)
      backup/dump.d/                database dump hooks (an example is included)
      backup/crontab.example        the cron lines
      docs/start-panes-as-workers.md  one-time sign-in and how to restart the panes
    tests/test-sandbox-workers.sh   offline self-test (bash -n, shellcheck if present, forbidden strings)

All scripts are bash 3.2 safe (no mapfile, no associative arrays, no case-changing expansions), like the core tools.

## Install

1. Config. Set at least `SABHA_WORKSPACE` (your sabha project folder, the `SABHA_IMPL` of your `sabha.conf`):

       mkdir -p ~/.config/sandbox-workers && chmod 700 ~/.config/sandbox-workers
       cp addons/sandbox-workers/sandbox.conf.example ~/.config/sandbox-workers/sandbox.conf
       chmod 600 ~/.config/sandbox-workers/sandbox.conf
       $EDITOR ~/.config/sandbox-workers/sandbox.conf

2. Read what setup will change (below), then run it once. It needs sudo and is safe to repeat:

       sudo bash addons/sandbox-workers/bin/setup-workers-user.sh
       # optional private Docker for the workers: sudo ROOTLESS_DOCKER=1 bash ...

   Under `sudo` the config is found through the user who ran sudo (`SUDO_USER`); `SANDBOX_CONF=/path` overrides.
3. Run the checks (see below), then sign the agents in and restart the panes:
   [docs/start-panes-as-workers.md](docs/start-panes-as-workers.md).
4. Heartbeat: add one line per sandboxed pane from `backup/crontab.example` to your own crontab. Give it the Sabha
   role name, the herdr pane id, the process name (`agy` or `opencode`) and a regex that matches text shown only
   while the agent works. The heartbeat stops nudging when `status/<role>.md` contains `QUEUE EMPTY`.
5. Backup (optional):
   - Pick the repo: `BACKUP_REPO=rclone:REMOTE:BUCKET/restic` (after `rclone config`), or a local path or sftp.
   - Password: by default a file at `~/.config/sandbox-workers/restic-password`, mode 600
     (`umask 077; openssl rand -base64 32 > ~/.config/sandbox-workers/restic-password`). Or set
     `RESTIC_PASSWORD_COMMAND` to any command that prints the password (a vault helper). **Also store a copy in your
     password manager**: without it a lost VM means a lost backup. The backup refuses to run with no password and
     there is no unencrypted mode.
   - `BACKUP_PATHS` lists what to save (default: the Sabha parent folder and the dump folder). `excludes.txt` is
     always applied: `.env*`, keys, credentials, ssh, rclone.conf and similar never leave the machine.
   - Database dumps: put an executable script in `backup/dump.d/` (see `postgres-docker.sh.example`); each writes
     to `$DUMP_DIR`.
   - Run once by hand (`backup/backup.sh`, then read `~/backup-state/logs/`), then add the cron lines.
   - Config repo sync is off until `CONFIG_REPO_DIR` and `CONFIG_SYNC_DIRS` are set; it never pushes unless
     `CONFIG_PUSH=1`, and it commits nothing if the secret scan finds anything.

### Everything setup changes

| Where | Change |
| --- | --- |
| passwd, shadow, group, the workers' home | new user, no password, never in docker/sudo/adm/lxd (setup refuses otherwise) |
| your home | mode 750 if looser; every top-level entry loses group/other bits (except the workspace's top folder) |
| your secret files and folders | files 600, folders 700 (`~/.ssh`, `~/.oci`, `~/.aws`, `~/.gnupg`, `~/.claude`, gh, rclone, opencode auth, this add-on's config); never loosened |
| ACLs | workers: traverse on the folders leading to the workspace; rwX (plus default ACL, plus rwX for you) on the workspace; rX on `REPO_DIR/READONLY_SUBDIR` if set |
| firewall | one `iptables -I OUTPUT 1 -m owner --uid-owner USER -d META_IP -j REJECT`, no flush |
| systemd | `/etc/systemd/system/USER-metadata-block.service` re-adds that single rule at boot |
| packages | `acl` if missing; with `ROOTLESS_DOCKER=1` also `uidmap` and `dbus-user-session`, subuid/subgid ranges, linger |
| workers' home | copies of `agy` and `opencode`, `work/`, `.config/opencode/opencode.jsonc` with permissions allowed |

## Run the checks

    sudo bash addons/sandbox-workers/bin/check-workers.sh

PASS/FAIL per line, exit status 1 on any FAIL, never prints file contents. It confirms the workers cannot open your
secrets, list your home, reach the metadata address, write to the repo or its `.git/hooks`, use sudo or Docker, and
that they can write in their folders and you can edit what they create. Off-cloud, set `CHECK_METADATA_CONTROL=0`.

The offline self-test of the add-on itself (no sudo, no network):

    tests/test-sandbox-workers.sh

## Undo

    addons/sandbox-workers/bin/undo-workers-user.sh            # prints the commands for your config
    sudo addons/sandbox-workers/bin/undo-workers-user.sh --apply

That removes the firewall rule, the boot unit, the ACLs and the user with its home (tools, config, work folder,
rootless Docker data). Not undone: the permission tightening (it only removed access; use `chmod` on a path by
hand) and installed packages. To stop the rest: remove the cron lines and delete `~/.config/sandbox-workers`
and `~/backup-state`. Back up or move the workers' `work/` folder first; `userdel -r` deletes it.

## Heartbeat

`bin/heartbeat-worker.sh <Role> <pane> <proc> <busy-regex>` runs as you. Each beat it reads the pane screen, checks
the process list for the workers user, and keeps a small state folder under `HEARTBEAT_STATE_DIR`. Idle on two beats
in a row: it types the nudge and Enter. Stuck on a permission prompt, process gone, or screen unchanged for three
beats: one alert (ntfy when `NTFY_TOPIC` is set, always in the log). Set `HERDR_SESSION` if you use a named herdr
session. UNTESTED on a herdr or agent other than the author's.

## Not included

A draft for running herdr without tmux (systemd user units) was considered and left out: it was not available to
package, so it is not claimed here.
