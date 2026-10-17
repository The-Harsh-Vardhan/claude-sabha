---
description: Print the fresh-restart command for a role (never --resume)
argument-hint: <Role>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-up.sh --print:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

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
