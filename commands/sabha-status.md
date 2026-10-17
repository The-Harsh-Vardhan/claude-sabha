---
description: Sabha status - who is running, context over 30 percent, open items, unacked briefs
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-check), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-watch)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Report the state of the sabha. Both scripts are read-only.

Run each as a single plain command (no pipes, no chaining), honouring `SABHA_CONF` (if sabha-watch says there is no
config, point the user to `sabha init --out <file>`):

1. `${CLAUDE_PLUGIN_ROOT}/bin/sabha-check` for the processes per role. Exit 1 means a DUPLICATE role.
2. `${CLAUDE_PLUGIN_ROOT}/bin/sabha-watch` for each role's context percent, age and state, restart lines, the user's
   open items and briefs nobody has acked. It always exits 0. (If `SABHA_RUN_AUTO=1` is set it also starts one
   headless `sabha-run` pass; say so if the output shows it.)

Summarise in this order, short:
- roles over 30 percent context first, with the restart line sabha-watch printed (never `--resume`),
- DUPLICATE or not-running roles,
- open items for the user (count and titles),
- unacked briefs (which role, which number).

Do not act on any of it; suggest `/sabha-restart`, `/sabha-board` or `/sabha-run` as the next step.
