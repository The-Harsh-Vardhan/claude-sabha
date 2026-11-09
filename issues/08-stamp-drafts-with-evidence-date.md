<!--
title: Drafts and status notes written from files go stale; stamp them and re-check before send
labels: enhancement, docs, gate, field-report
-->

## What happened

Roles write drafts from files: a nightly update, a pull request body, a push pack. On 2 Nov a pull request body still
said that a SQL step had never run on a real database, after the check that ran it had finished. A dispatcher fixed
that one line by hand. On 3 Nov a nightly update said two small issues would go "in the next patch". The same day both
were fixed in the hotfix branch. The note was true when it was written and wrong later. The dispatcher held it until
the branch state was final (the commit count was still changing).

## Impact

A message that goes to other people can state something that is no longer true. The human is the last check.

## Proposed fix

- The handoff and draft templates get an `As of:` line (UTC time and the commit sha the claims come from).
- `sabha-gate-review` gets one check: for each claim of state in a draft (counts, "fixed", "never ran"), re-read the
  evidence now, and list claims whose evidence is newer than the `As of:` line.
- A draft that goes to a person is marked ready only after that check.

## Status

Open. Today this is done by hand. No code yet.
