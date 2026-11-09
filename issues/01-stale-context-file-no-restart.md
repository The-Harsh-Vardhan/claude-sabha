<!--
title: sabha-loop never restarts a pane when its context file is not where the loop looks
labels: bug, loop, field-report
-->

## What happened

From 1 Nov to 3 Nov 2026 no pane restarted at 30 percent context. The newest context files were about 52 hours old.
The loop read `status/context/<role>.txt` in one sabha folder. The panes wrote it to another. The cause was config
lookup: a pane started without `SABHA_CONF` from a folder that holds another project's `sabha.conf`, so the status line
resolved a different `SABHA_IMPL`. The same cause printed `sabha-loop: unknown role`.

The loop saw a stale file, logged one quiet warning ("keeping the session"), and carried on. Nothing told the relay.

## Impact

The 30 percent rule is the main safety of the design. For two days it did nothing, and nobody knew. Sessions could
grow past the limit with no restart.

## Proposed fix

- Keep the existing quiet warning. Add one loud alert (log, desktop notification, and the relay's alert file) when a
  Claude pane's context file is missing or stale for longer than `SABHA_LOOP_STALE_ALERT` (default 600 s). Fire once
  per stale spell, and keep the spell across a session restart, so there is one alert, not one per session.
- A non-Claude pane must not alert (it writes no context file).
- Test: a fake agent that never writes the file, `SABHA_LOOP_STALE=1`, `SABHA_LOOP_STALE_ALERT=2`: exactly one alert.
- Longer term: make `sabha-loop` and the status line resolve the sabha folder the same way, and print the resolved
  folder at start.

## Status

A fix for the alert exists on a local branch of mine (one commit, three files, with tests). It is not in a pull
request yet. `sabha doctor` already warns about another project's config, but not at run time.
