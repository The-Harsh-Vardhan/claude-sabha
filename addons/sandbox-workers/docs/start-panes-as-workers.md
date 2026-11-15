# Run worker panes as the sandbox user

Prerequisite: `sudo bash bin/setup-workers-user.sh` and `sudo bash bin/check-workers.sh` both finished clean.
Below, `WORKERS` is your `WORKERS_USER` (default `workers`) and `WS` is your `SABHA_WORKSPACE`.

## Syntax found in herdr 0.9.5 (`herdr pane --help`, `herdr agent --help`)

- `herdr pane run <PANE_ID> <COMMAND>...` runs a command in an existing pane.
- `herdr pane close <pane_id>`, `herdr pane split [--pane ID] [--direction right|down] [--cwd PATH] [--no-focus]`.
- `herdr agent start <NAME> --kind <agy|opencode|...> --pane <ID>` starts a supported agent in a pane at a shell
  prompt. It launches the agent as the pane's own user, so it cannot switch user. Use `pane run` with
  `sudo -u WORKERS` instead.
- agy flags: `--mode accept-edits|auto|plan` and `--dangerously-skip-permissions` (auto-approve every tool
  request). opencode: the config written by setup already allows everything, no flag needed.

## One-time sign-in (you, once)

Do not copy tokens from your own account. Sign in as the workers user in a plain shell:

    sudo -u WORKERS -H bash -lc 'cd ~ && ~/.local/bin/agy'                  # follow the login prompt, then /exit
    sudo -u WORKERS -H bash -lc '~/.opencode/bin/opencode providers login'

If a login needs a browser, open the printed URL on your own machine and paste the code back. The credentials land
in the workers' home, not yours.

## Restart the panes

Stop the agent in the pane first (so it is back at your shell prompt), then, with `H=herdr` (add `--session NAME`
if you use one):

    $H pane run <DISPATCHER_PANE> "sudo -u WORKERS -H bash -lc 'cd WS && exec /home/WORKERS/.local/bin/agy --mode auto --dangerously-skip-permissions'"
    $H pane run <BUILDER_PANE>    "sudo -u WORKERS -H bash -lc 'cd WS && exec /home/WORKERS/.opencode/bin/opencode'"

For code work have the agent `cd /home/WORKERS/work` and clone there; the Sabha workspace is only for briefs,
status and queue files. If a pane's shell is gone, make one: `$H pane split --pane <PANE> --direction right --no-focus`.

Verify:

    $H pane list
    ps -o user= -C agy,opencode        # expect: the workers user

## Keep them alive overnight

herdr cannot see agents that run as another user, so it will not nudge them. Install the heartbeat from
`backup/crontab.example` (one line per pane); see the README, "Heartbeat". Its busy-regex is the text that is on the
screen only while the agent works: check yours by looking at a working pane.

## Known limits

- herdr's agent detection and lifecycle reports were set up for the owner. As another user the agent may show as a
  plain shell in herdr and its hooks cannot reach the owner's herdr config (that folder is 700). Cosmetic only; the
  pane still works. The pane restart flow is UNTESTED outside the author's machine.
- herdr itself keeps running as the owner; only the agent process in the pane is the workers user.
- `sudo -u WORKERS` needs the owner's sudo rights, which the pane's shell has. The agent running as the workers user
  does not.
