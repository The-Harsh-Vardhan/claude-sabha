---
name: sabha-dispatch
description: Use when you are the dispatcher - taking a brief from the relay, splitting it, assigning pieces to workers by difficulty, tracking acks and dones, or starting a copy (BuilderPrecise-2) because a role is busy.
---

# Dispatching

Source: RULES.md rules 2, 3, 4; template/impl/protocol/Dispatcher.md; docs/inbox-protocol.md sections 2-6;
PROTOCOL-core "Roster", "Messages and budget".

## Loop

1. Read `inbox/<Dispatcher>/`; write `NNN.ack` first (section 3), before any work.
2. Split the brief into pieces. Each piece is its own brief: `bin/sabha-brief <Worker> <dispatcher> <slug> "<task>"
   --output ... --body FILE` (it claims the number). Load `sabha-brief-writing`.
   Refuse to send a brief that opens a UI or a login without its "Preflight (step 0)" section (`sabha-brief-writing`).
   Browsers run headless unless the brief says `headed: yes` and why; an agent never leaves a browser it opened
   running and records its pid in the brief's output folder.
3. Nudge each worker with one line: `see inbox/<Worker>/NNN`.
4. Track. A brief with an ack and no `.done` is open; one with neither is unacked. `bin/sabha-watch` lists unacked
   briefs, the restart lines and open items. Resume any brief that has an ack and no done.
5. Every `.done` of code goes to the reviewer; docs and decision files go to the scribe (Dispatcher.md).
6. Report to the relay at milestones only: at most 3 lines, detail in a file.

## Route by difficulty (cheapest that fits)

- Precise, well specified: a builder at medium effort.
- Hard design or new decisions: the architect, one hard brief at a time.
- Hardest builds and debugging: the strong builder.
- Review of each `.done`: the reviewer; docs, decisions, board: the scribe.
- Mechanical runs: the smallest model, never at low effort.
- Step up a model or effort only with a reason written in the brief (RULES.md rule 3).
The real roster is the project's `SABHA_ROSTER` and `PROTOCOL-core.md`; roles are labels for a model and an effort.

## Never queue behind a busy role

If a worker is busy, above 30 percent context or down: brief a copy (`BuilderPrecise-2`; same profile, its own inbox, status
file and worktree; needs `SABHA_MAX_COPIES` to allow it, README) or run the piece as a subagent with that role's
model. Start a copy with `sabha-up.sh BuilderPrecise-2`. Run independent briefs side by side (rule 4).

## After a restart

Write `Session: <Name> [<ref>] started <utc>` to your status file first, so others can address you. Send to the newest
row of each role by its exact name plus id; `bin/sabha-check --agents FILE` names it when `-old` or duplicate rows
appear, and the old row is marked retired with its id in your status file.

## Questions and irreversible steps

- Answer a worker's question when the spec or protocol already does; otherwise forward it to the relay marked for
  the user, with the default the worker is using.
- Never implement. Never write a `go:` for an irreversible step unless the relay's brief carries the user's word and
  the gate passes (`bin/sabha-gate --brief`); see `sabha-gate-review`.
- Refused (an approved external write or kill denied to you or a helper): stop, do not retry; write a pack and queue it
  in the blocked-on-human state as docs/delegated-writes.md says.
- To stop a brief, write `inbox/<To>/NNN.cancel` (`utc:`, `reason:`); it beats any message (section 5).
