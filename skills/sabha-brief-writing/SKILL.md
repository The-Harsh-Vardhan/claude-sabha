---
name: sabha-brief-writing
description: Use when you must hand work to another sabha role - writing a brief into inbox/<To>/, choosing its header fields, go line, gate line or reply mode.
---

# Writing a brief

Source: docs/inbox-protocol.md section 2 (brief), section 3 (ack), section 6 (GO token); PROTOCOL-core "Inbox, claim,
ack, done".

## Use the script

`bin/sabha-brief <to> <from> <slug> "<task>" [--output TEXT] [--go TEXT] [--reply ack|done|none] [--body FILE]`

It claims the next number (`NNN.claim`, noclobber, retries on a clash), writes `NNN-<from>-<slug>.md` with the header
block, and prints the path. The body comes from `--body FILE` or stdin. `SABHA_IMPL` names the state folder; unset, it
uses the current directory. Do not hand-number briefs.

## Header block (generated)

`to`, `from` (lower case), `utc`, `task` (one line), `output`, `go`, `reply`, then a blank line and the body. Optional
`supersedes: NNN` is not a script flag: put it at the top of the body only if the sender's convention needs it, or
write a `NNN.cancel` instead to stop an earlier brief (section 5).

## What makes it good

1. One task. A second task is a second brief (section 2: `<slug>` is up to four words).
2. `task` says what, in one line; the body gives goal, inputs, constraints and what "done" looks like.
3. `--output` names the file(s) expected, so a missing output is visible without reading chat.
4. Model and effort: start at the cheapest model and medium effort; step up only with a reason written in the body
   (RULES.md rule 3).
5. `--reply`: `ack` (sender waits for the ack only), `done` (default; waits for `NNN.done`), `none`. A headless
   `sabha-run` receiver cannot take a message, so use `done` for those (section 3).
6. Say that a connected service is read or written only if the user named it (RULES.md rule 6).

## Go line and gate line

An irreversible step (fold, push, PR, tag, release, migration, kill, restart, `rm -rf`, `docker compose down`, SQL
that writes) happens only when the brief has `--go "<verb> <exact target>"`, e.g. `fold <repo> <sha>`, `kill <pid>`,
`push <repo> <branch>` (section 6). Write it only after the gate passes and with the user's explicit word. A message
"go" is never enough. Put `gate: <file>, <file>...` as a line in the body, naming the verdict files, so
`bin/sabha-gate --brief <brief>` can read it. Absent `go:` means no irreversible step.

## After writing

Send at most one line: `see inbox/<To>/NNN` (section 1). Anything longer is a file. Check `NNN.ack` at the next
wake; no ack and no `.done` is a brief nobody has picked up (`bin/sabha-watch` lists them).
