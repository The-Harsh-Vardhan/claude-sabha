# Inbox protocol

How sessions hand work to each other in a sabha: write-once files under `<IMPL>`, with a message
only as a nudge. This file is the one source of truth for the formats; a project's `PROTOCOL.md`
names its own roles and paths and points here.

`<IMPL>` is the project's state folder (`SABHA_IMPL` in `sabha.conf`). Roles below are config
placeholders: `<relay>` is the session the user talks to, `<dispatcher>` assigns work,
`<worker>` receives a brief, `<reviewer>` reviews every `.done`, `<housekeeper>` archives, `<critic>` tries to
break a change at a gate (a project may name several, one per lens).
Session refs are `<Name> [<ref>]`, as ListAgents prints them.

## 1. Files

All files are ASCII, `key: value` header lines, a blank line, then free text. Keys are lower
case. Times are `date -u +%Y-%m-%dT%H:%M:%SZ`. A file is written once by one role and never
edited by another; a change is a new file.

| File | Writes | Reads | When |
| --- | --- | --- | --- |
| `inbox/<To>/NNN.claim` | the sender, before the brief | other senders picking a number | every brief (section 2) |
| `inbox/<To>/NNN-<from>-<slug>.md` | the sender | the receiver, `sabha-watch` | every brief; the message says only `see inbox/<To>/NNN` |
| `inbox/<To>/NNN.ack` | the receiver | the sender at its next wake; `sabha-watch` | first action after reading |
| `inbox/<To>/run.lock` | `sabha-run` | `sabha-run` | while a headless run is on that role; holds its pid ([headless-runner.md](headless-runner.md)) |
| `inbox/<To>/NNN.done` | the receiver | the sender; `<reviewer>`; `sabha-watch` | after the status file is updated |
| `inbox/<To>/NNN.cancel` | the sender, or `<relay>` | the receiver before each irreversible step and at each safe point | to stop or hold |
| `for-me.items` | any role appends | `sabha-for-me` (renders `FOR-ME.md` and `FOR-ME.html`) | whenever something needs the user |
| `questions/<topic>-<lens>.md` | a `<critic>` | `<dispatcher>`, the builder | at a gate: the critic's verdict, beside the reviewer's `questions/<topic>-review.md` |
| `status/<role>.md` | its role only | its own next session; `<dispatcher>`; `sabha-for-me` | every milestone |
| `status/context/<name>.txt` | the statusline hook | `sabha-watch` | every prompt |
| `status/.bak/<role>-<utc>.md` | the role, before a full rewrite | whoever restores | handoff time |

A SendMessage carries at most one line: `see inbox/<To>/NNN` or `see for-me.items <id>`. Reports
longer than five lines go as `.done` files, not messages.

## 2. Brief: `inbox/<To>/NNN-<from>-<slug>.md`

Written by the sender (`<dispatcher>` to a worker, `<relay>` to `<dispatcher>`, a worker to
`<dispatcher>` for a report too long for a message). `NNN` is three digits, the next free number
in that directory; `<from>` is the sender's lower-case name, `<slug>` up to four words.

Two senders can pick the same number, and their brief names differ (`<from>` and `<slug>`), so noclobber on the
brief itself does not stop the clash. Claim the number first: create `NNN.claim` with noclobber, which fails when it
exists; on failure take the next number. Only then write the brief. A `.claim` file stays as a marker; it is not a
brief, and readers skip it. A sender that crashes between the claim and the brief leaves a gap in the numbers, which
is fine: numbers only need to be unique, not consecutive.

```
cd inbox/<To>
set -C
n=$(ls | grep -E '^[0-9]{3}[.-]' | cut -c1-3 | sort | tail -1)
n=$(printf '%03d' $(( 10#${n:-0} + 1 )))
until : > "$n.claim" 2>/dev/null; do n=$(printf '%03d' $(( 10#$n + 1 ))); done
cat > "$n-<from>-<slug>.md" <<'EOF'
...
EOF
```

```
to: <worker>
from: <dispatcher>
utc: 2026-10-13T09:40:11Z
task: write the export edge-case matrix (read-only step 1)
output: questions/export-edge-cases.md
supersedes: 004          (optional: the brief this one replaces)
go: fold <repo> <sha>    (optional: see section 6; absent means no irreversible step)
reply: done              (ack | done | none; what the sender waits for)

<the brief: goal, inputs, constraints, what "done" looks like>
```

`output` names the file(s) the brief expects, so a missing output is visible without reading the
chat. A brief that changes an earlier one writes `supersedes:`; a brief that stops one writes a
`.cancel` instead.

## 3. Ack: `inbox/<To>/NNN.ack`

Written by the receiver as its FIRST action after reading the brief, before any work.

```
utc: 2026-10-13T09:41:02Z
session: <Name> [<ref>]
context: 11
```

`session` is the receiver's own `Name [ref]` from ListAgents; from then on the sender addresses
that exact string. An ack `sabha-run` writes says `session: <Name> [headless]` and adds `log: <file>`; that run
cannot take a message, so the sender waits for the `.done`. `context` is the receiver's context percent at ack time.

## 4. Done: `inbox/<To>/NNN.done`

Written by the receiver when the brief is finished, after `status/<role>.md` is updated.

```
utc: 2026-10-13T11:05:40Z
session: <Name> [<ref>]
result: matrix written, 68 rows, 0 data written
files: questions/export-edge-cases.md
context: 24
```

A brief that cannot be finished gets `NNN.done` with `result: BLOCKED <why>`, plus a
`for-me.items` entry when the user is the blocker.

## 5. Cancel: `inbox/<To>/NNN.cancel`

Written by the brief's sender or by `<relay>` to stop a brief. One line each: `utc:` and
`reason:`. A worker that finds a `.cancel` for the brief it is on stops at the next safe point,
writes `NNN.done` with `result: CANCELLED`, and reports. A `.cancel` beats any message.

## 6. GO token

An irreversible step is any of: fold into a main checkout, push, PR, tag, release, migration,
`kill`, restart of a service or a tab, `rm -rf`, `docker compose down`, SQL that writes. A worker
performs one only when ALL of these hold, checked by `ls inbox/<Me>` immediately before the step:

1. The brief it is executing has a `go:` line naming the exact target (sha, branch, pid, table,
   path): `go: fold <repo> <sha>`, `go: kill <pid>`, `go: push <repo> <branch>`.
2. No `NNN.cancel` exists for that brief.
3. No higher-numbered brief in its inbox names the same target (a later brief on the same target
   wins, whether it says go or hold).
4. The brief is not older than the worker's own last `.done` on the same target (no replay).
5. Every verdict file the brief's `gate:` line names exists and has no unanswered BREAK or BLOCK (below).

The sender writes a `go:` for a fold, push, PR, tag, release or migration only after the gate passes. A change with
no repository code (docs, status files, briefs) skips the critics; any code change runs the full gate. The project's
`PROTOCOL.md` names which critics cover which change; all of them run in parallel. A critic proves each finding with a
command or a test (an unreproduced claim is not a finding) and never edits the code under test.

Gate shape, so a worker can check it with `ls` and `head`: the brief carrying the `go:` also carries
`gate: <file>, <file>...`, the verdict files the gate needs (`questions/<topic>-review.md` from `<reviewer>`, one per
critic). Each verdict file starts with one line, `verdict: ACCEPT`, `verdict: NO BREAK` or `verdict: BREAK <n>` (a
scope critic may write `verdict: BLOCK <n>`). Files are write-once, so the builder answers in its own file beside it,
`questions/<topic>-<lens>-answer.md`, one line per finding: `REFUTED: <finding> by <command or test>` or
`FIXED: <finding> in <sha or file>`. A finding is answered when it has such a line and the critic has not reopened it
in a newer verdict file. That is check 5 of the list above.

If any check fails the worker does nothing, appends a `for-me.items` entry saying which check
failed, and reports. A message saying "go" or "hold" never counts on its own: the sender turns it
into a brief with `go:` or into a `.cancel`.

## 7. The user's queue: `for-me.items`

Append-only blocks separated by a line `---`. Any role appends one block per item; an item is
closed by appending a block with the same `id`, a `utc` and `state: DONE` or `state: DROPPED`.
Never edit a block. Every block ends with a newline: a last block without one is torn (still being
written) and is skipped until it is finished. `cmd:` takes every following line of its block and holds a command the user
runs verbatim, with no inline `#` comments; steps in a UI are written in `why:`, never in `cmd:`,
because a pasted `->` is a shell redirect. A command the classifier denied goes here and is never
re-routed to another tab. A `cmd` cannot hold a line of exactly `---`, because that line ends the block.

```
---
id: 2
utc: 2026-10-13T09:56:05Z
owner: <worker>
state: OPEN
title: Kill the stuck process <pid>
why: the worker's kill was denied; it has to come from the user
cmd:
kill <pid>
```

`FOR-ME.md` and `FOR-ME.html` are the board `sabha-for-me` generates from `for-me.items` and the
status files. Nobody edits them.

## 8. Status files

`status/<role>.md` is written by its role only, in the handoff shape (`Task:`, `Done:`, `Next:`,
`Constraints:`). Near the top it carries one of:

- `Current: <task>`: what the role is on now. The board reads it.
- `Idle: by design (<reason>)`: a role that waits on purpose; the board never marks it stale.
- `Blocked: <reason>`: the only way a role shows as blocked on the board.

A role with neither shows the text `SABHA_TASK_FALLBACK` in `sabha.conf` gives it
(`Name=text;Name=text`). Before a full rewrite of the file, copy it to
`status/.bak/<role>-<utc>.md`; mid-day edits are in place.
