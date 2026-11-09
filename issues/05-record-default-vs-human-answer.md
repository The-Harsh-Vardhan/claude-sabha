<!--
title: Record whether a question was answered by the human or by a default
labels: enhancement, protocol, for-me, field-report
-->

## What happened

A question for the human may have a recommended option. To keep work moving, the team goes on with that default
and records a numbered decision. The human reviews the batch later. In use, a page of questions for a reviewer was
published with a default on every question, and the relay's handoff had to say "all defaults" in prose.

## Impact

Risk: a decision that looks approved but was only assumed. A reader of the decision file sees "decided" and trusts it.
The record is also the base for the pull request notes, so the gap can spread.

## Proposed fix

- `sabha-item close <id>` takes `--by human|default`. The closing block gets `answered_by:`.
- A default-closed item stays visible on the board as "default, not the human's answer" until the human confirms or
  changes it.
- The decision file template gets one column for the same value.

## Status

Open. The rule is practice only. `bin/sabha-item` has the states OPEN, DONE and DROPPED, nothing about who closed.
