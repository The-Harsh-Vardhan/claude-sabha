---
description: Write this role's status/<name>.md handoff (Task, Done, Next, Constraints)
allowed-tools: Read, Write, Edit
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Write your handoff now. No script runs; this is an instruction to you, the current role (RULES.md rule 1,
docs/inbox-protocol.md section 8). Load the `sabha-handoff-writing` skill for the format.

1. Find your file: `<IMPL>/status/<your lower-case role name>.md`. Write only your own file.
2. For a full rewrite, first copy the old file to `<IMPL>/status/.bak/<name>-<utc>.md`
   (`date -u +%Y-%m-%dT%H:%M:%SZ`); small mid-day edits are in place.
3. Top block: line 1 `Current: <task>`, or `Idle: by design (<reason>)`, or `Blocked: <reason>`. Then:

   ```
   Continue this work in a fresh context (previous session at NN%).
   Session: <transcript path, if you know it>
   Task: <the brief or goal>
   Done: <do not redo>
   Next: <where it stopped + the immediate step>
   Constraints: <locked decisions, scope>
   ```
4. ASCII only; no secrets, no `.env` contents.
5. Confirm to the user in one line: the file path, the context percent, and whether a restart is due (30 percent or
   more). Do not stop a session mid-task for this.
