<!--
title: sabha-run: give each headless run its own worktree and a lead-time report
labels: enhancement, headless, field-report
-->

## What happened

Headless runs (`sabha-run`) are the right place for bounded work. In use, two writers in one worktree was the main
risk. On 3 Nov a hotfix needed a builder and a tracer. The dispatcher had to say, by hand, that the two must not
both write the worktree, and ran them one after the other. Another runner swapped files in a worktree for a
red-green check and logged a "restored" line so nobody touched it meanwhile.

On 27 Oct a headless run also timed out and the work had to move to a pane. The rule that came out of it: before
leaning on headless runs, have a `.done` watchdog, a permission preflight, and one worktree per run.

## Impact

Two writers on one tree give lost edits and confusing diffs. A human has to know which runs may touch which tree.

## Proposed fix

- `sabha-run` takes `--worktree` (or a brief header field): create `<repo>--<slug>` with `sabha-worktree create`
  for the run, refuse to start when another live run holds the same worktree.
- A 90-minute watchdog that writes a BLOCKED `.done` (a timeout already exists; this makes the limit explicit).
- A lead-time report: brief written, acked, done, per role.

## Status

The worktree, watchdog and report part is written on a local branch (one commit, six files) and not yet in a pull
request. `bin/sabha-worktree` (create, guard against a commit in a main checkout) is already on main.
