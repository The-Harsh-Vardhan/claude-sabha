---
title: Durable helpers
nav_order: 5
---

# Durable helpers (`bin/sabha-helper`, `sabha-run --detach`)

Why: a dispatcher that fans work out to in-session subagents loses all of it when it restarts. The loop restarts a
Claude pane at 30% context on purpose, and every subagent in that process dies with it. On 3 Nov 2026 six lanes
(builds, tests, a browser run) stopped mid-flight at once. A durable helper is the same headless run `sabha-run`
already makes, started outside the dispatcher's session and recorded in a registry, so a fresh dispatcher can find it.

No second runner: the helper is `sabha-run`'s child (`claude -p`, `run.lock`, `.ack`, log, timeout, fallback `.done`).
Two things are added around it: a detached start, and a registry under `status/helpers/`.

## What it is

- **Detached start.** `sabha-run --detach <Name>` (and `sabha-helper start <Name>`, same thing) starts the child in a
  new session (`setsid` when present, else Python's `os.setsid`; a start with neither fails and says so). A signal to
  the dispatcher's process group, its pane closing or its `/exit` no longer reaches the helper.
- **Registry.** `$SABHA_IMPL/status/helpers/<id>.json`, one per helper; `<id>` is `<Name>-<NNN>` (the role, which may be
  a copy such as `Karna-2`, and the brief number). Fields: `id role brief brief_n worktree model effort started
  started_epoch pid log state attempts ended exit why stop_reason`. The log is `status/helpers/<id>-<utc>.log`.
- **States.** `running`, then `done` (the `.done` result is not BLOCKED), `blocked` (result starts with BLOCKED),
  `cancelled` (a `.cancel`), `timeout`, or `stopped` (stopped by `sabha-helper stop`, which `sabha-down.sh` calls).
  `dead` is set only by `reattach`: the pid is gone and no `.done` exists (a kill -9, a reboot, a crashed host).
- **Output.** The `.done` marker in the role's inbox is the result channel, as for every sabha brief; the log holds
  claude's text.

## Commands

| Command | Does |
| --- | --- |
| `sabha-helper start <Name>` | one detached run of the role's lowest due brief; refuses (exit 3) and says why when a check below fails |
| `sabha-helper list` | the registry: id, state, pid, age, brief, log; running ones first |
| `sabha-helper reattach [--redispatch]` | for a fresh dispatcher: reconcile every entry (alive, finished, dead), print them, and with `--redispatch` start the dead ones again, resumed |
| `sabha-helper wait [--timeout S] [id...]` | poll the `.done` markers and the registry until the named helpers (default all running) end |
| `sabha-helper stop (<id>\|--all) [--reason R] [--timeout S]` | write the `.cancel`, wait for the run to end, record `stopped` |

`reattach` is idempotent and safe to run on every dispatcher start; the opening prompt of the dispatcher role tells it
to. A dead helper is started again only by `--redispatch`, and only up to `SABHA_HELPER_RETRIES` (default 2) attempts;
after that it stays `dead`, a line goes to `for-me.items`, and the brief gets a BLOCKED `.done`.

## Decisions

| Question | Choice | Why |
| --- | --- | --- |
| Reuse or rewrite | `sabha-run`'s child is the runner; the new code is detach, registry, CLI | one place builds the claude command and the timeout; the brief said not to write a second runner |
| Detach how | new session via `setsid` or `python3 -c os.setsid`; no `disown` games | stock macOS has no `setsid`; Python is already a kit dependency; a process group alone still shares the pane's session |
| Which work | long work (about 10 minutes, or anything that builds, tests or browses) goes through `start`; short reads stay in-session subagents | a durable helper costs a full claude process |
| Registry format | JSON, one `"key": value` per line, read and written in plain bash (no process per call) | a loaded machine makes every exec slow (a bare `sabha-helper list` took 16 s at load 350); the tests parse the file with a real JSON parser |
| Alive | `kill -0 <pid>`, plus, when `ps` is readable and no test list is set, the command line must mention `sabha-run` | a reused pid after a reboot must not read as a live helper; `ps` is denied inside some sandboxes, then the check is `kill -0` only |
| No double start | three layers: a live registry entry, a live `run.lock` (a dead pid's lock is cleared), the noclobber `.ack` | the same brief twice would give two writers on one status file |
| Re-dispatch | the `.ack` is moved to `NNN.ack.dead-<epoch>` so the brief is due again; the prompt gets "a previous run died: read status/<name>.md and what is on disk, resume, never redo or overwrite" | the brief's work is on disk; redoing it overwrites it |
| Caps | `SABHA_STOP` and the per-account stop lines (`bin/sabha-limits.sh`) refuse a start; `SABHA_HELPER_MAX` (default 4) live `run.lock` files across all inboxes; role copies stay inside `SABHA_MAX_COPIES`; a detached run is headless, so it takes no pane and does not count against a headful cap | the existing lines hold for helpers; running one more than the machine carries is the failure this feature must not add |
| Load | `SABHA_HELPER_LOAD_MAX` (default 4 x cores, 0 or `off` disables) against the 1-minute load average; over it, a start is refused and the message names both numbers | the Mac ran out of memory at 16 panes and sits at load 80 to 100 on a busy day |
| Load unknown | when none of `/proc/loadavg`, `sysctl vm.loadavg` and `uptime` can be read the start goes ahead and says the load was not measured | a failed probe must not read as "idle", and must not block all work |
| Panes | a helper whose role has a live `claude -n <Name>` is refused, as `sabha-run` does; `ps` unreadable skips that check with a warning (plain `sabha-run` still refuses to run then) | one writer per status file; a sandboxed dispatcher cannot read the process list |
| Slow start | a start waits up to `SABHA_HELPER_START_WAIT` seconds (default 30) for the helper to name itself in the registry, then kills it and writes a BLOCKED `.done` | plain `sabha-run` waits 5 s, too short when python or bash take seconds to start under load |
| `sabha down` | `sabha-down.sh` stops helpers first (`.cancel`, wait, `stopped`, reason `sabha-down`) and lists them in a dry run; a stopped helper is not re-dispatched by `reattach` | down is a deliberate stop; the user restarts what they want |
| Loop restart and `/exit` | nothing is done: the helper is in its own session, its registry entry stays `running` | this is the point of the feature |
| Hold file | `status/loop/<name>.hold` (the loop keeps a pane below 45%) is unchanged and stays useful for short in-session helpers | durable helpers are the answer for long work, the hold for short |

## Limits

- The helper's pid is `sabha-run --child` (the supervisor), not claude. A `kill -9` of the supervisor leaves claude
  running in its own process group until it finishes or the machine restarts; `reattach` then reports the helper
  `dead` and a re-dispatch could run beside the orphan. `stop` and the timeout go through the supervisor and are clean.
- `stopped` is final: `reattach` never re-dispatches it (a stop, by hand or by `sabha-down.sh`, is a decision). To run
  that brief again, write a new brief.
- A re-dispatch takes the role's lowest due brief. If a lower-numbered brief of the same role is unacked it runs first,
  and the dead one stays dead until the next `reattach`.
- Two `start`s in the same instant can exceed `SABHA_HELPER_MAX` by one (as `SABHA_RUN_MAX`).
- The registry is local: no host-to-host sharing. Windows: not covered.
