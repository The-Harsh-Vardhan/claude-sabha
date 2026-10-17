---
name: sabha-handoff-writing
description: Use after finishing each task, when a status line changes (Current/Idle/Blocked), and before a fresh restart at 30 percent context - writing status/<name>.md in the handoff format.
---

# The handoff

Source: RULES.md rule 1; docs/inbox-protocol.md section 8; PROTOCOL-core "Status file, handoff, restart".

## When

- After each task, before reporting it: save progress so a fresh session can continue from files alone.
- At 30 percent context or near it: write the handoff, tell the dispatcher, then stop. Never stop mid-task.
- Order at the end of a brief: update `status/<role>.md`, then write `NNN.done` (section 4).
- A restart is a FRESH session with the same opening prompt, never `--resume`. `sabha-loop` restarts a Claude pane
  when `status/context/<name>.txt` is at 30 or more AND the handoff file is newer than the last start, so write the
  handoff first or the loop will not restart you.

## File and ownership

`<IMPL>/status/<lower-case role>.md`, written by its own role only. Before a full rewrite copy it to
`status/.bak/<role>-<utc>.md` (utc from `date -u +%Y-%m-%dT%H:%M:%SZ`); mid-day edits are in place.

## Format (top block)

```
Current: <task>
Continue this work in a fresh context (previous session at NN%).
Session: <the transcript path, if you know it>
Task: <the brief or goal>
Done: <do not redo>
Next: <where it stopped + the immediate step>
Constraints: <locked decisions, scope>
```

Line 1 is one of `Current: <task>` (what you are on; the board reads it), `Idle: by design (<reason>)` (never
marked stale) or `Blocked: <reason>` (the only way to show blocked). Words in a `Next:` line never change the state.
The board's "In flight" is the first `Next:` after `Current:`.

## Rules

- ASCII only, short, top block only; results go in files and the status names the path.
- Next must be a concrete immediate step a stranger could take.
- Constraints holds locked decisions (numbered decisions if the project keeps them), so they are not re-opened.
- No secrets and nothing from `.env*`, `.npmrc` or key files.
- A user-blocking item also gets a `for-me.items` block (section 7).
- Messages to others stay at most 3 lines: what, result or sha, next step; detail is a file.
