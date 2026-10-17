---
description: Start the sabha grid, or one role (sabha-check first)
argument-hint: "[Role]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-check), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Start the sabha. Optional role: $ARGUMENTS

Run each script as one plain command: no pipes, no `&&`, no redirects (sandbox exclusions match the exact command
string). The scripts read `sabha.conf` from `SABHA_CONF`, else beside the scripts; this plugin has no `sabha.conf`, so
if `SABHA_CONF` is unset and the scripts say there is no config, tell the user to run `sabha init --out <file>` and set
`SABHA_CONF` to it. Do not guess a path.

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-check`. It is read-only and lists each role's claude processes; a role marked
   DUPLICATE (exit 1) is a problem to report before starting anything.
2. Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh` (no argument: open the grid) or
   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh <Role>` when a role was named. `<Name>-N` starts a copy (Arjun-2).
3. If it reports that a claude process already holds a role's name ("already running"): report that, show the
   `sabha-check` rows, and ask the user before using `--force` (first argument of `sabha-up.sh`). Never add `--force`
   on your own.
4. If it fails with -10822, -54, -600 or `LSOpenURLsWithRole() failed` (osascript/iTerm is blocked in the Claude
   sandbox): stop. Do not retry, and do not retry outside the sandbox. Print the exact command for the user to paste
   into a plain terminal, with no inline `#` comments:

   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh <Role>` (written out with the real path).

Report what started and what is still down.
