# Run queue

Every ask of the user is one row, from the moment the relay passes it on. The dispatcher keeps this file; the relay
writes each new row into its brief. Long history goes to the tracker, not here.

States: READY, RUNNING, BLOCKED-USER, BLOCKED-OTHERS, DONE. Priorities: P0 now, P1 today, P2 this week, P3 later.

| id | asked | ask | priority | state | owner | brief | last change | next step |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Q-001 | 2026-01-01 09:00 | Example: run the e2e suite on the release branch | P1 | READY | dispatcher | 001 | 2026-01-01 09:05 | Wait for the heavy gate (`bin/sabha-heavy acquire e2e`), then brief the runner |

## Rules

1. Scheduler: the dispatcher takes READY rows by priority, then age. A heavy row (dev server, build, browser or
   Docker run) starts only after `bin/sabha-heavy acquire <label>` says GO (load, memory, slots); a WAIT line goes to
   the relay once per change of reason.
2. Interrupt: a new P0 pauses lower RUNNING work at a safe point (state file written); it never kills it.
3. Aging: a BLOCKED-USER row older than 2 hours gets "AGED" in its state; the relay asks it first in its next message.
4. Batching: BLOCKED-USER questions are asked together, at a natural break, one at a time.
5. DONE rows stay 24 hours, then move to the Done section below.

## Done
