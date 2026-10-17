---
name: sabha-gate-review
description: Use when you are a reviewer or critic asked to gate a change, or a builder answering findings - writing verdict files that bin/sabha-gate accepts.
---

# Gate review

Source: docs/inbox-protocol.md section 6 (GO token, gate shape); header of `bin/sabha-gate`; PROTOCOL-core "Hard
rules" (review gate).

## What the gate checks

`bin/sabha-gate [-C DIR] --brief <brief>` reads the brief's `gate:` line (a comma or space list of verdict files) and
exits 0 (open), 1 (shut) or 2 (usage). A `go:` for a fold, push, PR, tag, release or migration waits for it. Docs-only
or status-only changes need one review; any code change runs the full gate, critics in parallel.

## Reviewer: `questions/<topic>-review.md`

A file named `*-review.md` is the reviewer's. It needs `verdict: ACCEPT`; at least one such file is required. Put the
verdict as a line `verdict: ...` (the script reads the last such line). Read the diff, not the whole repository.

## Critic: `questions/<topic>-<lens>.md`

Any other file is a critic's. Its verdict line is one of:

- `verdict: NO BREAK` - passes.
- `verdict: BREAK <n>` or `verdict: BLOCK <n>` (n >= 1; BLOCK is for a scope critic) - passes only when answered.

Rules for the critic: prove each finding with a command or a test (an unreproduced claim is not a finding); never edit
the code under test; list the n findings under the verdict line, each with its proof.

## Append-only, newest wins

A verdict file is an append-only log; the LAST `verdict:` line is current. To reopen after accepting, append
`verdict: BREAK n`. Never rewrite an earlier line.

## Builder: the answer file

For each critic file `questions/<topic>-<lens>.md` write `questions/<topic>-<lens>-answer.md` (the file name minus
`.md`, plus `-answer.md`), one line per finding:

- `REFUTED: <finding> by <command or test>`
- `FIXED: <finding> in <sha or file>`

The gate counts lines starting `REFUTED:` or `FIXED:`; it needs n or more for `BREAK n`. An answers file older than
its verdict file (mtime) is stale and counts as 0, so answer AFTER the newest verdict. Before a go, run
`bin/sabha-gate --brief <brief>` and paste the exit code.

## If it is shut

Do not edit a verdict to open it. The worker takes no irreversible step, appends a `for-me.items` entry naming the
failed check, and reports (section 6).
