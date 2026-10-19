# Core protocol (read at every start)

This is the short file every session reads first. Your own job is in `protocol/<Name>.md`. The file formats (briefs,
acks, dones, the GO token, `for-me.items`) are in `docs/inbox-protocol.md` of the sabha repository.
`<IMPL>` = the folder this file sits in (`SABHA_IMPL`), `<WS>` = your workspace (`SABHA_WS`). Replace the placeholders
and the sample roster below with your own project; keep the rules that match how you want to work.

## Project

Name: (set `SABHA_PROJECT` in `sabha.conf`). Source of truth for what to build: (name your spec, PRD or issue list
here). Read a repository's own `CLAUDE.md` or README before the first edit there.

## Roster

The profiles come from `SABHA_ROSTER`; a plan file (`sabha.pro.conf`, `sabha.max5.conf`, `sabha.max20.conf`) holds the
examples. Roles are labels for a model and an effort, not people: when a role is busy, add a copy (`BuilderPrecise-2`).

| Role | Job |
| --- | --- |
| Relay | Talks to the user only. Turns each request into a brief for the dispatcher and relays the answer. Does no work itself. |
| Dispatcher | Assigns briefs to workers by difficulty, tracks them, reports to the relay. No implementation. |
| Architect | Hard design and decisions. One hard brief at a time, usually a subagent. |
| BuilderHeavy | The hardest builds and debugging. |
| BuilderPrecise | Precise, well-specified implementation. |
| Reviewer | Reads the diff of every `.done` and writes a verdict. |
| Writer | Docs, decision files and the board. |

## Hard rules

- No push, pull request, release, post or message to anyone outside this machine without the user's explicit word,
  passed down by the relay. Connected services (chat, tickets, email, drives) are read only when the user names them.
- Commit only in a worktree; never in a main checkout. A finished, reviewed change is folded into the main checkout
  uncommitted and the user commits it.
- Never read or print `.env*`, `.npmrc` or key files. Never put a secret in a brief, a status file or a commit.
- Commands the user must run carry no inline `#` comments (a shell passes them as arguments). Steps in a UI are
  prose, never a code block.
- An irreversible step (fold, push, PR, tag, release, migration, kill, restart, `rm -rf`, `docker compose down`,
  SQL that writes) needs a `go:` line naming the exact target in the newest brief, no `.cancel`; a message alone
  never counts (`docs/inbox-protocol.md`, "GO token").
- Review gate: a `go:` for a fold, push, PR, tag, release or migration needs the reviewer's ACCEPT and no unanswered
  BREAK. A change with only docs or status files needs one review.
- Never hand-patch generated output; change the source and regenerate. Never overwrite a generated output: write a
  new version beside it.

## Inbox, claim, ack, done

A brief is `<IMPL>/inbox/<Name>/NNN-<from>-<slug>.md`. The sender claims the number first
(`set -C; : > NNN.claim`; on failure take the next number), then writes the brief: run `bin/sabha-brief` (in the sabha
repository), which does both. Worktrees: `bin/sabha-worktree create`. The review gate: `bin/sabha-gate`. The receiver's first action is
`NNN.ack`, its last is `NNN.done`; `NNN.cancel` stops the brief; resume any brief that has an ack and no done. A
message says only `see inbox/<Name>/NNN`. Anything the user must decide or run goes to `for-me.items` (append-only;
close an item by appending its id and `state: DONE` or `DROPPED`); `FOR-ME.md` and `FOR-ME.html` are generated and
nobody edits them.

## Questions

Ask the user in this shape, one question at a time: the question, why it matters, options A/B/C each with a
consequence and an example, a recommended option, and room for a free-text answer. In `for-me.items` that is the
`q:`, `explain:`, `opta:`..., `rec:` item format, which the board renders as a card with a "Copy answer" button. Do
not wait for the answer: go on with the stated default and say so in the `.done`. The dispatcher answers what it can
and marks the rest for the user.

## Status file, handoff, restart

`status/<name>.md`, top block only, written by its own role: line 1 is `Current: <task>` (or
`Idle: by design (<reason>)`, or `Blocked: <reason>`), then the handoff. Copy the old file to
`status/.bak/<name>-<utc>.md` before a full rewrite. Handoff shape:

```
Continue this work in a fresh context (previous session at NN%).
Session: <the transcript path, if you know it>
Task: <the brief or goal>
Done: <do not redo>
Next: <where it stopped + the immediate step>
Constraints: <locked decisions, scope>
```

After each task, before reporting, save progress there so a fresh session can carry on from files alone. At 30 percent
context or near it: write the handoff, tell the dispatcher, stop; never stop mid-task. A restart is a FRESH session
with the same opening prompt, never `--resume` (a resume brings the full context back). `sabha-loop` does the restart
when the context file reads 30 or more and the handoff is newer than the last start. Stuck for an hour: write
`<nn>.blocked` or a question and go on.

## Messages and budget

- A message between sessions is at most 3 lines: what, the result or sha, the next step. Detail goes in a file and
  the message names its path.
- Cheapest model that fits the job, medium effort by default, one step up only with a reason written in the brief.
  Run independent work in parallel (a subagent or a second instance), never queue behind a busy role.
- Batch questions; keep state in short files, not in chat. Reviews read the diff only.
- Usage alerts and the stop line come from `SABHA_NOTIFY` and `SABHA_STOP` in `sabha.conf`; at the stop line no new
  session starts and running ones finish.
