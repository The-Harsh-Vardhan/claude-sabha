<!--
title: sabha-run refuses to run when the process list is unreadable (sandboxed dispatcher)
labels: bug, headless, sandbox, field-report
-->

## What happened

A dispatcher running inside the Claude Code Bash sandbox cannot run `ps`. On 3 Nov it tried `sabha-run` and got:
"cannot read the process list; nothing started". `sabha-run` reads the process list to skip a role that already has a
live pane. With no list it refuses, so the dispatcher could not start any headless run. The same sandbox also blocked
the herdr socket, `gh`, `git fetch`, app launch, and service control (some of these failed without a message).

## Impact

The dispatcher could not use `sabha-run` for long work. It had to hand long work to a role with its own pane. The
alternative, in-session sub-agents, dies when the dispatcher restarts at 30 percent context (six lanes on 3 Nov). The
sandbox closed the safe path.

## Proposed fix

When `ps` cannot be read, warn and skip the live-pane check, as the durable-helper start does in
[PR #35](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/35) for `--detach`. Apply the same to plain `sabha-run`,
and say in the log that the check was skipped. Keep a flag to make it strict (`SABHA_RUN_STRICT_PS=1`).

Also list, in `docs/known-gaps.md`, which commands need the sandbox off.

## Status

Open. `--detach` tolerates an unreadable `ps` only in the helper PR. Plain `sabha-run` is unchanged. `sabha init`
already prints the sandbox setting that lets roles write the sabha folder.
