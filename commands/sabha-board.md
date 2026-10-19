---
description: Render the sabha board once and walk the user's open items as MCQs
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-for-me), Read
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Render the board and work through what needs the user.

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
