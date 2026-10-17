---
description: Write a brief into a role's inbox (claims the number, writes the header block)
argument-hint: <To> "<task>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-brief:*), Write
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Write a brief. Arguments: $ARGUMENTS (first word = the receiving role, the rest = the task).

Load the `sabha-brief-writing` skill for what a good brief holds. Then:

1. `from` is the current role's name (the session name you run as, lower-cased by the script), or `user` when the
   user is writing it directly. If the receiver or task is missing, ask once.
2. `slug` is up to four words, letters/digits/`-`/`_` only. `to`, `from` and `slug` must match
   `^[A-Za-z0-9][A-Za-z0-9_-]*$`; header values are one line.
3. Put the body (goal, inputs, constraints, what done looks like) in a file with the Write tool, in a scratch
   location, then run one plain command (no pipes, no heredocs, no chaining):

   `${CLAUDE_PLUGIN_ROOT}/bin/sabha-brief <to> <from> <slug> "<task>" --output "<file>" --reply done --body <bodyfile>`

   Flags: `--output TEXT`, `--go TEXT`, `--reply ack|done|none` (default done), `--body FILE`. Add `--go` only when
   the user's explicit word for that exact irreversible target is in hand (docs/inbox-protocol.md section 6); a
   `gate:` line goes at the top of the body file.
4. `SABHA_IMPL` (from `sabha.conf` via `SABHA_CONF`, or the environment) names the state folder; the script uses the
   current directory when it is unset, so check it is set before running.
5. The script prints the brief path. Report it, and the one-line nudge to send: `see inbox/<To>/NNN`.
