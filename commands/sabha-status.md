---
description: Sabha status - who is running, context, open items, unacked briefs; `board` walks the open items
argument-hint: "[board]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-check), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-watch), Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-for-me), Read
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Arguments: $ARGUMENTS. Empty: the status report. `board`: render the board and walk the user's open items.

## Status

Report the state of the sabha. Both scripts are read-only.

Run each as a single plain command (no pipes, no chaining), honouring `SABHA_CONF` (if sabha-watch says there is no
config, point the user to `/sabha-init`):

1. `${CLAUDE_PLUGIN_ROOT}/bin/sabha-check` for the processes per role. Exit 1 means a DUPLICATE role.
2. `${CLAUDE_PLUGIN_ROOT}/bin/sabha-watch` for each role's context percent, age and state, restart lines, the user's
   open items and briefs nobody has acked. It always exits 0. (If `SABHA_RUN_AUTO=1` is set it also starts one
   headless `sabha-run` pass; say so if the output shows it.)

Summarise in this order, short:
- roles over 30 percent context first, with the restart line sabha-watch printed (never `--resume`),
- DUPLICATE or not-running roles,
- open items for the user (count and titles),
- unacked briefs (which role, which number).

Do not act on any of it; suggest `/sabha-start restart <Role>`, `/sabha-status board` or `/sabha-start run` as the next step.

## Board (`/sabha-status board`)

Board first: read `SABHA_BOARD_URL` from the config (`SABHA_CONF`, else `sabha.conf` beside `bin/`). When it is set,
tell the user the URL to open and sync it, before anything else. This command only tells them; it never publishes
or writes an artifact itself. When it is empty or the key is missing, skip this paragraph: the command is unchanged.

Then render the FOR-ME board and work through what needs the user.

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/sabha-for-me` once as a plain command (no pipes, no chaining). Never use
   `--watch`: it loops until interrupted. Honour `SABHA_CONF` (point to `/sabha-init` if there is no
   config).
2. Read the generated `FOR-ME.md` (in the impl folder, `SABHA_IMPL`) and list the user's open items (state OPEN).
3. Ask them one at a time, in the shape RULES.md rule 5 and PROTOCOL-core "Questions" set: the question, one line on why
   it matters, options A/B/C each with consequence and a concrete example, the recommended option FIRST, and room for a
   free-text answer. Wait for the answer before the next question.
4. Items that are commands (`cmd:`) are shown for the user to run verbatim; never run them yourself and never add
   inline `#` comments.
5. Do not edit `for-me.items` blocks or the generated `FOR-ME.*`. To close an item, append a new block with the same
   `id`, a `utc` and `state: DONE` or `DROPPED` (docs/inbox-protocol.md section 7), only after the user answers.
   Record the answer where the change ships, per RULES.md rule 5.
