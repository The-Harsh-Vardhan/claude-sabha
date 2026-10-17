---
description: Headless pass - start one claude -p per served role that has an unacked brief
argument-hint: "[Role...]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-run --print:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-run:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

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
