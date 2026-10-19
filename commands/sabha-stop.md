---
description: Show what a clean sabha shutdown would do (dry run only)
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-down.sh)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Preview the shutdown of the sabha grid.

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
