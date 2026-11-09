<!--
title: Relay and dispatcher skills: on an idle report, start the local work the open question does not block
labels: enhancement, skills, field-report
-->

## What happened

On 30 Oct a large build was gated and the team waited for two answers from the human and a later push window. All
workers sat idle for about three hours (08:50 to 11:35). Several next steps were local and reversible: a base-branch
check, scratch branches, deletions with a written spec, tests, gates. A base check that ran later found a large amount
of unpushed work. Pull requests slipped about three hours.

## Impact

Idle workers cost wall-clock time, and a read-only check that would have informed the question was run after it.

## Proposed fix

Add to the relay and dispatcher skills, and to RULES.md:

- When a role reports "idle" or "waiting on the human", list what local, reversible work the open question does NOT
  block, and brief it at once on the stated default. Ask the human in parallel.
- Run the read-only check that informs a question before asking it.
- Only pushes, pull requests, sends and destructive steps wait for the human's word.

## Status

Open. The rule is in the author's own standing rules. The skills in this repo have no text about idle workers.
