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
| Windows | not covered yet; `sabha-up.ps1` has no runner twin | the Mac is where memory ran out |

## Limits

- Two passes started in the same instant can both see a free slot and exceed the cap by one.
- An acked brief with no `.done` (a run killed with `kill -9` on the runner itself) is not retried; the role's later
  briefs still run, and `sabha-watch` shows the role mid-task. Resume it by hand with `sabha-up.sh <Name>`.
- `sabha-down.sh` sees a headless run as a running role (it carries `-n <Name>`) and sends it a save brief it never
  reads; such a run ends on its own or at its timeout, and a later pass then runs that save brief headless.
