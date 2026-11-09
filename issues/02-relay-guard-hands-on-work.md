<!--
title: The relay drifts into hands-on work; add an opt-in guard
labels: enhancement, relay, field-report
-->

## What happened

The relay is meant to talk to the human, write briefs and read status files. It does no work. In practice it drifted
into doing the work, again and again: on 16 and 17 Oct it built a page and started its own sub-agents while the
dispatcher was up. On 27 Oct it read diffs and ran migration steps. On 31 Oct, after a long session, it did a
workspace clean-up, repository pulls and a skill install itself. Each time the human had to say it again.

## Impact

A relay that works is slow to answer (the human said so on 27 Oct). The cost rules (cheap model for the work, strong
model only where needed) are bypassed. Work done in the relay has no brief, no `.done` and no review.

## Proposed fix

An opt-in hook, `SABHA_RELAY_GUARD`, that keeps the relay to reading, briefing and talking:

- allow reads, `sabha-brief`, `sabha-item` and status files;
- refuse edits and shell commands that change things, with a message that says "write a brief instead";
- a whole-phrase override from the human ("you do it") so a direct ask still works;
- fail closed on a crash, a bad config or odd input; refuse shell syntax that runs code inside an allow-listed command;
- `sabha doctor` warns when the hooks are off.

Off by default, so nothing changes for existing setups.

## Status

The rule is in RULES.md (rule 2) and the relay skill. The guard is written on a local branch of an older
line of this repo. It must be ported onto main and opened as a pull request. Not in a PR yet.
