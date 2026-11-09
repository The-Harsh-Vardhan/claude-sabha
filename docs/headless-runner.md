---
title: Headless runner
nav_order: 4
---

# Headless runner (`bin/sabha-run`)

Why: an interactive role holds a `claude` process, and its memory, while it waits. Sixteen idle panes exhausted a
32 GB Mac. `sabha-run` starts a role only when a brief is due and the process exits when the brief is done.

## What a pass does

For each served role, the lowest `inbox/<Name>/NNN-*.md` with no `.ack`, `.cancel` or `.done` is due. Unless a
check below says no, the pass takes `inbox/<Name>/run.lock` (noclobber, holds the run's pid), writes `NNN.ack`
(noclobber, `session: <Name> [headless]`, `log: <file>`), and starts in the background, from `SABHA_WS`:

```
claude -p -n <Name> --model <model> --effort <effort> [--strict-mcp-config] --permission-prompts none "<prompt>"
```

The prompt carries what `sabha-up.sh` opens with (the protocol, or `SABHA_PROTOCOL_CORE` plus the role file, then the
status file; both read it from `sabha_reads` in `sabha-lib.sh`), then the brief's path and the rules for a headless
run: do this brief only, update `status/<name>.md`, write `NNN.done`, stop. `sabha-run --print [Name...]` prints
that exact line per due brief and writes nothing.

## Decisions

| Question | Choice | Why |
| --- | --- | --- |
| Loop or one shot | One shot. `sabha-watch` runs a pass when `SABHA_RUN_AUTO=1`; a sender may also run `sabha-run <Name>` right after writing a brief | the kit has no daemon; whatever already calls `sabha-watch` (by hand, `/loop`, cron, launchd) drives it |
| Concurrency | `SABHA_RUN_MAX` (default 2) live `run.lock` files across all inboxes | each run is a full claude process; 2 fits next to the relay |
| Single flight | one `run.lock` per role, and the `.ack` is written with noclobber, so a pane or a second pass that acked first wins; a role with a live `claude -n <Name>` (pane or hand start) is left alone | one writer per status file |
| Which roles | `SABHA_RUN_ROLES`: `lazy` (default, the roles with no pane), `all` (every role but the relay and ondemand ones) or a list of names. A name on the command line is always served, except the relay | the relay is the one the user talks to; an ondemand role such as a tutor needs a person |
| MCP | roster flag `mcp` keeps the user's MCP servers; every other run gets `--strict-mcp-config`, as in `sabha-up.sh` | memory |
| Permissions | no `--dangerously-skip-permissions`, no `--permission-mode`: the run uses the same settings files as an interactive role (it starts in `SABHA_WS`). `--permission-prompts none` turns a prompt into a denial | nobody is at the terminal; a hang would hold memory until the timeout |
| A denial | the run appends it to `for-me.items`, writes `NNN.done` with `result: BLOCKED <the denial>` and stops; it never works around it | the user decides, as with a denied command in a pane |
| Timeout | `SABHA_RUN_TIMEOUT` seconds (default 3600), then TERM, KILL after 5 s, to claude's whole process group (`set -m`), so builds and servers its tools started stop too | a stuck run must free its slot; stock macOS has no `timeout`, so the runner watches once a second |
| Spawn fails | the child writes its pid to `run.lock` first; a pass that does not see it within 5 s writes `NNN.done` with `result: BLOCKED headless run did not start` and removes the lock | an ack with no done and an orphan lock would stall the sender |
| No done at exit | the runner writes `NNN.done` with `result: BLOCKED headless run ended without a done (exit N or timeout), log <file>` | the sender waits on a `.done` |
| Logs | `SABHA_RUN_LOGS` (default `$SABHA_IMPL/runs`), one `<Name>-NNN-<utc>.log` per run: the command, claude's text output, the end line | read after the fact; nothing streams |
| Windows | not covered yet (the Windows launchers were removed in 0.2.0) | the Mac is where memory ran out |

## Limits

- Two passes started in the same instant can both see a free slot and exceed the cap by one.
- `needs:` gates only briefs this runner serves; a pane role reads its inbox itself and is not held by it.
- An amendment written while a headless run is on its brief is not seen by that run (`claude -p` takes no message);
  `sabha-brief --amend` warns. Write `NNN.cancel` and re-brief when the run must see it.

## Brief lifecycle: amendments, needs, attempts

| Question | Choice | Why |
| --- | --- | --- |
| A change after the brief was sent | a new file `NNN.K-<from>-<slug>.md` (`sabha-brief --amend NNN`), never an edit; due() never takes it as a brief, the run's prompt lists every amendment after the brief in K order; an acked pane brief gets a `sabha-nudge` with the file name | an edit after the ack is invisible to a worker that already read it; `sabha-watch` reports a brief edited after its ack (advisory: it compares mtimes, so a git checkout, rsync or `touch` of the inbox can trigger it) |
| Order between briefs | `needs: NNN Name/NNN ...` in the header block; a brief waits while a need is open and the next brief of the role runs | dependency order without a queue file |
| A need that can never be met | unknown id, the brief itself, a cycle, a need that is cancelled or ended `BLOCKED`/`CANCELLED`: the runner writes `NNN.done` with `result: BLOCKED needs: <why>`, so the sender is told and briefs that need this one block too | claude-queue treats a missing need as met and never propagates a failed one |
| Attempts | one line per start in `NNN.attempts`, written when the run starts, so a crash still uses one | a crashing run cannot loop |
| Retries | `SABHA_RUN_ATTEMPTS` (default 1 = no retry). Only a run that exits non-zero with no `.done`, a spawn that fails, or a run that died (headless ack, no `.done`, no live `run.lock`) is retried: the ack is removed and `NNN.retry` names the earliest restart, `SABHA_RUN_BACKOFF` s doubled per attempt (cap 16x: 60, 120, 240, 480, 960 s, then 960 s). A timeout, an exit 0 with no `.done`, or the agent's own `BLOCKED` done is final | retry the machine, not the agent; another hour of a timed-out model is a cost decision |
| A dead run | a headless ack with no `.done`, no live `run.lock` and no live `claude -n <Name>` is retried while attempts are left, else closed `BLOCKED headless run died without a done`. An ack with no `NNN.attempts` (written before attempts were counted) has used one, so at the default it is closed, not run again | it used to stay open forever; a worker resumed by hand in a pane (`sabha-up.sh <Name>`) keeps the brief |
- `sabha-down.sh` sees a headless run as a running role (it carries `-n <Name>`) and sends it a save brief it never
  reads; such a run ends on its own or at its timeout, and a later pass then runs that save brief headless. (A run
  started as a durable helper is stopped by `sabha-down.sh` first, so this does not apply to it.)

## Durable helpers

`sabha-run --detach <Name>` is the same run started in its own session with a registry entry, so it outlives the
session that started it; see [durable-helpers.md](durable-helpers.md).
