---
description: Sabha theme - list themes and presets, show the resolved characters, switch SABHA_THEME
argument-hint: [list | show [name] | use <name>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme list), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme show:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme use:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme validate:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

A theme is a skin: it changes the character names, colours and icons shown for the 20 roles, never the roles themselves
(inboxes, status files and `claude -n` names stay the role ids). `$ARGUMENTS` is one of:

- empty or `list`: run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme list` and show the themes and the user's presets, with the
  current one marked `*`.
- `show` or `show <name>`: run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme show [name]` and show the 20 resolved rows.
- `use <name>`: run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-theme use <name>` (honours `SABHA_CONF`). It validates first and
  refuses an unknown name, a name that is both a theme and a preset, or a theme that fails the check. Pass on any warning
  it prints (for example a name two roles share) and say what it said about when the change shows: names, colours and
  icons at the next refresh, voices when each role next starts fresh. Do not restart any role.

Run each as a single plain command (no pipes, no chaining). A preset is a file `<name>.preset` in
`~/.config/claude-sabha/presets/`; the format is in `themes/README.md`.
