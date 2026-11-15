---
description: Run the sabha grid - start [Role], stop, restart <Role>, run [Role...]
argument-hint: "[Role] | stop | restart <Role> | run [Role...]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-check), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-down.sh), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-run --print:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-run:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

One command for the grid lifecycle. Arguments: $ARGUMENTS

Dispatch on the first word:

| First word | Does |
| --- | --- |
| empty, or a role name | **Start** the grid, or that one role |
| `stop` | **Stop**: dry run of a clean shutdown |
| `restart <Role>` | **Restart**: print the fresh-restart line for a role |
| `run [Role...]` | **Run**: headless pass for roles with an unacked brief |

## Start

Start the sabha. Optional role: the argument.

Run each script as one plain command: no pipes, no `&&`, no redirects (sandbox exclusions match the exact command
string). The scripts read `sabha.conf` from `SABHA_CONF`, else `./my-claude-sabha/sabha.conf` in the current folder,
else beside the scripts. If they say there is no config, tell the user to run `/sabha-init` for the project (or to
start this session in the project folder, or set `SABHA_CONF`). Do not guess a path.

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-check`. It is read-only and lists each role's claude processes; a role marked
   DUPLICATE (exit 1) is a problem to report before starting anything.
2. Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh` (no argument: open the grid) or
   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh <Role>` when a role was named. `<Name>-N` starts a copy (BuilderPrecise-2).
3. If it reports that a claude process already holds a role's name ("already running"): report that, show the
   `sabha-check` rows, and ask the user before using `--force` (first argument of `sabha-up.sh`). Never add `--force`
   on your own.
4. If it fails with -10822, -54, -600 or `LSOpenURLsWithRole() failed` (osascript/iTerm is blocked in the Claude
   sandbox): stop. Do not retry, and do not retry outside the sandbox. Print the exact command for the user to paste
   into a plain terminal, with no inline `#` comments:

   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh <Role>` (written out with the real path).

Report what started and what is still down.

## Stop

Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-down.sh` exactly as written: no arguments, no pipes, no chaining. With no
arguments it is a dry run: it prints what it would send, wait for, kill and close, and changes nothing. Honour
`SABHA_CONF`; if the script reports no config, point the user to `/sabha-init`.

Never pass `--yes`, `--timeout` or `--kill-unsaved`. The script refuses `--yes` inside a Claude session (a kill needs
a `go:` line, docs/inbox-protocol.md section 6) and osascript is blocked in the sandbox.

After the dry run, summarise which roles would be asked to save, which would be killed, and that the relay is never
killed. Then print the real command for the user to paste into a plain terminal (real path, no inline `#` comments):

`${CLAUDE_PLUGIN_ROOT}/bin/sabha-down.sh --yes`

Mention that a role that has not saved by the timeout is left running unless `--kill-unsaved` is added, and that
roles should write their handoff first (`/sabha-handoff`).

## Restart

Print the restart line for: $ARGUMENTS

1. Remind the user (and the role) that the handoff comes first: the role must write `status/<name>.md`
   (`/sabha-handoff`) before it stops, and is never stopped mid-task (RULES.md rule 1).
2. Run one plain command, no pipes or chaining, honouring `SABHA_CONF`:
   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh --print <Role>`
   It prints the restart line first, then a `pane:` line (what a grid pane runs; ignore it for a hand restart), and
   exits; it starts nothing. `<Name>-N` names a copy.
3. Show the restart line (the first one) for the user to run in a plain terminal pane. A restart is a FRESH session with the same
   opening prompt: never suggest `--resume` or `--continue`, because a resume brings the whole context back.
4. Mention that `sabha-loop` does this automatically when the statusline hook is on and the handoff is newer than the
   last start.

## Run

Run the headless runner (docs/headless-runner.md). Roles named: $ARGUMENTS (none: the served roles,
`SABHA_RUN_ROLES`, default lazy).

Run each script as one plain command (no pipes, no chaining) and honour `SABHA_CONF`.

1. Dry run first: `${CLAUDE_PLUGIN_ROOT}/bin/sabha-run --print [Role...]`. It prints the exact command per due brief
   and writes nothing and starts nothing.
2. Show the user what would start (role, brief, model/effort as printed). If nothing is due, say so and stop.
3. Ask whether to go ahead. Starting headless runs spends usage and each run holds memory until its brief is done.
4. Only after a yes: `${CLAUDE_PLUGIN_ROOT}/bin/sabha-run [Role...]`. It starts the runs in the background and exits;
   do not use `--wait` unless the user asks.
5. Afterwards point to `/sabha-status` to follow acks and `.done` files. The relay is never run headless, and a brief
   that needs an irreversible step still needs its `go:` line.
