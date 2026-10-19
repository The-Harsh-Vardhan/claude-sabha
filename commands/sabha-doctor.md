---
description: Check the machine for sabha (tools, config, statusline hook)
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha doctor)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha doctor` as one plain command (no pipes, no chaining). Honour `SABHA_CONF`
(config path) and `SABHA_SETTINGS` (the settings.json it checks for the statusline hook, default
`~/.claude/settings.json`).

It exits 1 only on a FAIL; warnings never fail the run. Report FAILs first with the fix each line suggests, then the
warnings. If it says there is no config, suggest `/sabha-init` (or starting the session in the project folder, or setting `SABHA_CONF`). Fix nothing
yourself.
