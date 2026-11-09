<!--
title: Add a .superseded marker so old ack-without-done briefs are not resumed
labels: enhancement, protocol, field-report
-->

## What happened

The protocol says: resume any brief that has an `.ack` and no `.done`. After three weeks a dispatcher inbox held many
briefs from October with an `.ack` and no `.done`. They were history, not work: the task had moved on or been replaced.
The dispatcher wrote in its own handoff that these are not resumable. In practice I made up a marker by hand: a file
`NNN.superseded` next to the brief.

## Impact

Risk: a fresh dispatcher, or a durable-helper re-dispatch, reads the rule literally and starts old work again. At the
least, a fresh session spends its first minutes sorting out what is live.

## Proposed fix

- Document `NNN.superseded` (one line: by which brief, or why) as a closing marker like `.done` and `.cancel`.
- `sabha-board`, `sabha-watch` and the durable-helper `reattach` treat it as closed.
- `sabha-brief --supersede <old> <new>` writes it.

## Status

Open. Not in main and not in an open PR.
