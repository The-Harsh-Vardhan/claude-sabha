<!--
title: sabha-brief should warn when the target role is over the restart limit
labels: enhancement, brief, loop, field-report
-->

## What happened

On 2 Nov a worker above 30 percent context was sent an urgent brief. It declined the brief, as the rules say it
should (write the handoff, stop). The dispatcher cancelled the brief and gave it to a sub-agent. A round trip was
lost on an urgent task. On 15 Oct the same thing stalled a documentation task until the worker was restarted.

## Impact

The brief sits in an inbox of a role that will not take it. The dispatcher finds out only when the worker answers.

## Proposed fix

`sabha-brief` and the dispatcher skill read `status/context/<role>.txt` before they write a brief. If the target is
at or over `SABHA_LOOP_LIMIT`, print a warning and the name of a copy (`<Role>-2`) that has room. This needs the
context file to be fresh (see the stale-context issue), so say "context unknown" when the file is old.

## Status

Open. The rule is in RULES.md (rule 4) and `skills/sabha-dispatch`. No script checks it.
