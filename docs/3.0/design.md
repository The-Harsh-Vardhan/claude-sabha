# Claude Sabha 3.0 - design (step 3 of 3)

Bhishma, 8 Nov 2026 (from the relay's overnight-work and upstream-radar briefs). Design only: no code.
Base: `origin/main` at d1fe294 (#61). Step 2 is `docs/3.0/coupling-audit.md` (Arjun, 16 Oct), copied unchanged into
this branch. Every `path:line` below is in this branch unless it starts with `<workspace>/` (the owner's workspace
root), which is where the real-use evidence lives.

Effort: S = hours, M = a day or two, L = a redesign of that piece (same scale as the audit, coupling-audit.md:3).

## 0. What changed since the audit (16 Oct -> d1fe294)

The audit is three weeks old. Half of its seam list already landed, ad hoc. The plan starts from today's code, not
from the audit's line numbers.

| Audit finding | State on d1fe294 | Evidence |
| --- | --- | --- |
| iTerm2 grid is the layout engine (audit row 1) | herdr is the default backend on every OS; iTerm2 is `SABHA_BACKEND=iterm`, "macOS only, frozen" | bin/sabha-herdr.sh:2-3, :16; bin/sabha-up.sh:2-4, :241-256 (herdr), :297 (osascript) |
| Windows grid via `sabha-up.ps1` / `wt.exe` (rows 7-9) | the .ps1 and .cmd are gone; Windows = Git Bash + herdr native beta, untested | docs/windows.md:9-10 |
| one agent only (claude) | roster field 2 is the agent: `claude opencode codex agy muse`; non-claude roles start with `herdr agent start --kind` | bin/sabha-lib.sh:12-13, :21; bin/sabha-up.sh:119-127; bin/sabha-herdr.sh:4-5 |
| nudge by typing into an iTerm2 tty (row 17) | `sabha_nudge` = `herdr agent prompt --wait` on the role's pane from `status/herdr-panes.txt` | bin/sabha-herdr.sh:226-236 |
| headless = `claude -p` only (row 10) | still claude only; other agents are refused by `served` | bin/sabha-run:37, :49-50 |
| process discovery = `ps` for `claude -n NAME` (row 14) | unchanged | bin/sabha-lib.sh:317-341 |
| duplicate check = ListAgents in the opening prompt (row 6) | unchanged | bin/sabha-up.sh:81 |
| close windows on teardown (row 19) | herdr: `session stop/delete` (portable); iTerm: three osascript blocks remain | bin/sabha-down.sh:44-51, :110, :162, :188 |
| tmux launcher (audit's "Linux/WSL tmux") | does not exist | `grep -rn tmux bin/` -> no hits |

So 3.0 is not "add herdr"; it is: (1) make the two half-seams real seams with one file each, (2) put tmux beside
herdr as the plain-terminal fallback, (3) freeze iTerm2 as a thin launcher, (4) add the workflow features in
sections 6 and 7 on top of the unchanged file protocol.

## 1. Goals and non-goals

Goals
- One launcher interface, four implementations: herdr (default), tmux, iTerm2 (frozen), Windows Terminal (via herdr).
- One agent adapter interface; claude stays the reference; OpenCode is the second real adapter.
- State and protocol files unchanged (section 4): a 2.x `SABHA_IMPL` folder works under 3.0 with no migration.
- The seven workflow features in sections 6 and 7, specced; more in section 8 "Later".

Non-goals
- No daemon. Scheduling stays "whatever calls `sabha-watch`" (docs/headless-runner.md:30).
- No change to the brief lifecycle, the gate, or the restart rule.
- No write to GitHub from any new command (section 7.0 is read-only by construction).

## 2. Launcher seam (per OS / terminal)

Interface: one sourced file per launcher, `bin/launch/<name>.sh`, defining exactly these functions. Today's
equivalents are named so the move is mechanical.

| Function | Contract | herdr today | iTerm today |
| --- | --- | --- | --- |
| `L_ready` | backend usable (installed, server up); false + one stderr line otherwise | `sabha_herdr_ready` bin/sabha-herdr.sh:51 | none today: the `TERM_PROGRAM` test at bin/sabha-up.sh:149 only gates the badge block (see `L_cosmetics`); an iTerm `L_ready` is new (S) |
| `L_open_grid <build[]> <gate[]>` | two tabs, panes in roster order; records `Name pane_id` | `fill_tab` bin/sabha-up.sh:210-240 | `tab_script` + osascript bin/sabha-up.sh:262-320 |
| `L_pane_note / L_target <Name>` | the pane map, `status/herdr-panes.txt` renamed `status/panes.txt` (old name read as fallback) | bin/sabha-herdr.sh:191-226, :239-243 | none (tty from ps) |
| `L_send <Name> <text>` | submit text to a role and wait to settle; timeout = exit 75 | `sabha_nudge` bin/sabha-herdr.sh:226-236 | osascript write text bin/sabha-down.sh:110 |
| `L_close_all` | close only sabha's own panes/session, never the user's | `sabha_session_stop` bin/sabha-herdr.sh:170 | osascript bin/sabha-down.sh:162-188 |
| `L_list_panes` | live pane ids, for prune and the reaper (section 8) | `pane list` bin/sabha-herdr.sh:212 | none |
| `L_cosmetics <Name>` | optional badge/title | herdr `pane report-metadata` (bin/sabha-up.sh:231, bin/statusline-sabha.sh:134-135; docs/known-gaps.md:17 lists it untested) | OSC 1337 bin/sabha-up.sh:149-160 |

Selection: `SABHA_BACKEND` (bin/sabha-herdr.sh:16) keeps its name and default `herdr`; new value `tmux`.

Implementations
- **herdr** (M): move `bin/sabha-herdr.sh` to `bin/launch/herdr.sh`, keep a one-line shim at the old path for one
  release. Nine kit scripts source it by that path (grep `sabha-herdr.sh` in bin/): bin/sabha-up.sh:28,
  bin/sabha-down.sh:24, bin/sabha-loop:30, bin/sabha-alert:17, bin/sabha-nudge:9, bin/sabha-check:49,
  bin/sabha-herdr-config:21, bin/sabha:308, bin/statusline-sabha.sh:117. The owner's `<workspace>/bin/sabha-up-au-herdr.sh`
  does not (it calls `herdr --session` directly; `grep -n 'sabha-herdr\|herdr-panes' <workspace>/bin/*` has no hit). The session guard
  (bin/sabha-herdr.sh:29-48: own named session, never `default`, fake-only under `SABHA_TEST=1`) moves unchanged.
- **tmux** (M, new): `tmux -L sabha` (own server socket = same isolation idea as herdr's named session);
  `new-session -d -s sabha`, `split-window`, `select-layout tiled`; `L_send` = `send-keys -t <pane> -l <text>` then
  `Enter`, with no "wait until settled" (tmux cannot see agent state): returns at once, the inbox file carries the
  content (coupling-audit.md:33 already accepts a missing transport degrading to polling). Linux, WSL, and macOS
  without herdr.
- **iTerm2** (S): frozen. Only its osascript blocks move into `bin/launch/iterm.sh`; no new features.
- **Windows Terminal** (S, doc): not a launcher of its own. herdr's Windows beta uses Windows Terminal as its attach
  app (docs/windows.md:12-13), so WT = the herdr launcher under Git Bash. A `wt.exe` launcher comes back only if
  herdr on Windows fails in a real test (docs/known-gaps.md:20 lists the open Windows test).

`kill_tree` (bin/sabha-run:89-103 in the audit, now the `--child` block from bin/sabha-run:82, `set -m` at :95) stays in
`sabha-run`: it is per-OS process handling, not per-terminal, and bash-on-Windows already goes through Git Bash.

## 3. Agent adapter

Interface: one sourced file per agent, `bin/agents/<agent>.sh`, picked by the roster's agent field
(bin/sabha-lib.sh:278 `read -r _ R_AGENT ...`).

| Function | Contract | claude today |
| --- | --- | --- |
| `A_interactive_argv <Name> <model> <effort> <prompt>` | argv array `ARGV` for a pane | bin/sabha-up.sh:171 (`exec claude -n ... --model --effort ...`), :109 (print form) |
| `A_headless_argv <Name> <model> <effort> <prompt>` | argv for one unattended run; must turn a permission prompt into a denial | bin/sabha-run:37-39 (`claude -p -n ... --permission-prompts none`) |
| `A_model <alias> <effort>` | agent's model id and effort flag, or empty | identity for claude (sabha.conf.example model names) |
| `A_proc_match` | awk filter over `ps -axo pid=,tty=,lstart=,command=` that yields `name pid tty date time` | bin/sabha-lib.sh:322-341 (`cmd != "claude"`) |
| `A_dup_check_text <Name>` | the duplicate-check sentence of the opening prompt | "First run ListAgents ..." bin/sabha-up.sh:81 |
| `A_context <Name>` | percent or `-` | `status/context/<name>.txt` from bin/statusline-sabha.sh:4 |
| `A_herdr_kind` | the `--kind` for `herdr agent start`, empty = run argv in the pane | empty for claude; bin/sabha-up.sh:124 for others |

Duplicate check without ListAgents (M): for any agent whose `A_dup_check_text` is empty, `sabha-up.sh <Name>`
itself refuses to start when `sabha_procs` (through `A_proc_match`) or a live `inbox/<Name>/run.lock`
(bin/sabha-run, `live_lock`) shows the role already running. This is the "ps / lock-file fallback" the audit asked
for (coupling-audit.md:14) and makes the check a script exit code, not a prompt sentence (same reasoning as
docs/specs/efficiency-profiles.md:258).

Adapters to ship
- **claude** (M): pure move of today's lines; argv byte-identical (tests/test-grid.sh asserts the exact argv).
- **opencode** (M): interactive through herdr `--kind opencode` as today (bin/sabha-herdr.sh:5 "opencode tested");
  headless = `opencode run` with the prompt, UNVERIFIED flags: the adapter's first test pins whatever `opencode run
  --help` prints on the owner's machine. Until then `served` keeps refusing non-claude headless (bin/sabha-run:50).
- **codex, agy, muse**: stay `--kind` only, marked UNTESTED as now (bin/sabha-herdr.sh:5). No adapter file until one
  is run for real.

Context percent for non-claude agents: `-` (unknown). `sabha-loop` already treats a missing or stale context file
as "do not restart" (bin/sabha-loop:9-10), so unknown is safe; non-claude panes restart per `.done` as today
(bin/sabha-loop:10-11).

## 4. State and protocol files: unchanged

Unchanged in name, format and meaning: `inbox/<Name>/NNN-*.md` and `.claim .ack .done .cancel .blocked`,
`for-me.items`, `status/<role>.md` (top block), `status/context/<name>.txt`, `status/heavy/*.slot`,
`status/loop/*`, `questions/`, `sabha.conf` roster `Name:agent:model:effort:flags` (bin/sabha-lib.sh:12-13).
The audit already lists these as portable (coupling-audit.md:37-38).

Additive only: `status/panes.txt` (renamed map, old name still read), `status/heavy/queue/` (6a),
`status/whoami/<Name>.txt` (6c), `status/gh-cache/` (7.0), `DIGEST-<date>.html` (6b). A 2.x reader ignores them.

## 5. Migration steps (in order)

| # | Step | Size | Depends on | Breaks if skipped |
| --- | --- | --- | --- | --- |
| 1 | Commit `coupling-audit.md` and this design (this branch) | S | - | - |
| 2 | Agent adapter: `bin/agents/claude.sh`, call sites in sabha-up.sh, sabha-run, sabha-lib.sh use it; argv byte-identical | M | 1 | - |
| 3 | Script-level duplicate check (section 3) beside the ListAgents sentence; keep both for one release | S | 2 | - |
| 4 | Launcher seam: `bin/launch/herdr.sh`, `iterm.sh`; shim at `bin/sabha-herdr.sh`; `status/panes.txt` with fallback | M | 2 | - |
| 5 | tmux launcher | M | 4 | Linux users keep "herdr or nothing" |
| 6 | 6c `sabha whoami` + pre-turn check (smallest, highest daily value) | S | - (uses today's code) | - |
| 7 | 6a heavy queue | M | - | - |
| 8 | 7.0 GitHub fetch layer, then 7.1 `sabha prs`, 7.4 watcher, 7.2 `sabha shipped` | M + S + S + M | - | - |
| 9 | 6b morning digest, 7.3 `sabha owe` (digest embeds owe) | M + S | 7, 8 for full content | - |
| 10 | opencode headless adapter | M | 2 | - |
| 11 | Remove the `bin/sabha-herdr.sh` shim (3.1) | S | 4 + one release | none known outside the kit; the nine in-kit sourcers (section 2) move to `bin/launch/herdr.sh` first |

Steps 6 to 9 do not depend on 2 to 5 and can ship first; the overnight brief (item 4) already picks 6c as the first
implementation.

## 5.1 What breaks for current users

- Anything that sources `bin/sabha-herdr.sh` by path: covered by the shim until step 11. The known callers are the
  nine kit scripts listed in section 2; no caller outside the kit is known (`<workspace>/bin/*` has none, see section 2).
- Anything reading `status/herdr-panes.txt` directly (bin/sabha-check:50 inside the kit; the owner's board writer
  does not, per <workspace>/docs/<queue>/board-writer/status-mapping.md sources table): the launcher writes both
  names for one release.
- `SABHA_BACKEND=iterm` users: no change in behaviour; the code just moves.
- Windows: no change (herdr path), still untested.
- Nothing in `SABHA_IMPL` needs a migration (section 4).

## 5.2 Test plan

All hermetic (`tests/hermetic.sh`: fake herdr first on PATH, `SABHA_TEST=1`, inherited `SABHA_*` cleared,
tests/hermetic.sh:1-25). One suite run at a time, never against a real herdr or tmux server.
- Adapter: `tests/test-grid.sh` already asserts exact claude argv; it must pass unchanged after step 2 (the
  byte-identical proof). New `tests/test-adapter.sh`: each adapter's argv for one role, interactive and headless.
- Launcher: existing `tests/test-herdr*.sh` pass unchanged after step 4, and so do the suites that reach the nine
  in-kit sourcers through the shim (the sabha-down, sabha-loop, sabha-alert and sabha-nudge tests) while the shim
  exists; step 11 repoints those nine and deletes the shim. New `tests/hermetic-bin/tmux` fake that logs
  calls (same shape as `tests/fake-herdr.sh`) and `tests/test-tmux.sh`: grid of 3 roles -> expected `split-window`
  / `send-keys` lines; a guard test that `-L sabha` is on every call (no call can reach the user's default server).
- Pane map rename: a map only at the old path is read; a write lands at both paths.
- Per-feature tests are in each feature section.
- Release: `tests/smoke-live.sh` (existing, opt-in, throwaway session) is the only live check, run by the owner by hand.

## 6. Specced features (overnight brief)

### 6a. Load-aware heavy queue

**Problem (real use).** 8 Nov: the Uploads gate run was ready at about 19:50 but waited for hours,
because the rule "start one headless Karna when load5 <= 20" lived in the dispatcher's status file and needed a
session to keep re-checking it (<workspace>/<impl>/status/yudhishthira.md, the 8 Nov block that
reads "NNN mid-flight. Git work DONE, gates NOT run (load5 31-61)", and the line "Cap 4: slot 4 reserved for
headless Karna (NNN gates) at load5 <= 20"; a live status file, so quoted not line-cited). The kit's gate exists
(`bin/sabha-heavy`, #61) but (1) it judges `load1 <= 2 x cores`, not the owner's rule (header bin/sabha-heavy:10, load
read :28-33, limit :67, check :70), (2) `acquire` gives up after `SABHA_HEAVY_WAIT` 900 s and returns 75
(bin/sabha-heavy:94-110, `acquire`), and (3) nothing re-tries later: `sabha-run` starts any due brief without asking the gate
(bin/sabha-run:169-173).

**Design.**
1. Threshold: two new keys in `bin/sabha-heavy`: `SABHA_HEAVY_LOAD_AVG` (1 or 5, default 1 = today) and
   `SABHA_HEAVY_LOAD_MAX` (absolute number; when set it replaces `FACTOR x cores`). The owner's conf:
   `SABHA_HEAVY_LOAD_AVG=5`, `SABHA_HEAVY_LOAD_MAX=20`. load5 is the second field of the same `vm.loadavg` /
   `uptime` read (bin/sabha-heavy:28-33), so no new probe.
2. Queue = the inbox. A brief header line `heavy: <label>` marks a heavy brief; the sender writes it by hand like
   any other header line (docs/inbox-protocol.md), nothing else writes it. In `sabha-run`, right after the
   SABHA_STOP check (bin/sabha-run:169-170), a heavy brief runs `sabha-heavy check`; on WAIT `sabha-run` prints
   `sabha-run: <Name> <n>: queued (HEAVY WAIT: ...)`, writes `status/heavy/queue/<Name>-<n>` (one line: the WAIT
   reason and utc, for the board and digest), and moves on; the brief stays un-acked. That insertion point is after
   the live-pane test (bin/sabha-run:155-156), so a role with a live pane never gets a queue file: the digest
   cannot show a brief as queued that will never start headless (step 4). The queue file is removed when the ack
   is written.
   On GO the slot is taken by the child, with the child's own pid. Decision: add an optional pid argument to
   `sabha-heavy acquire` (`acquire <label> <secs> [pid]`, default 0 = today), not `sabha-heavy run`. Why: the CLI
   `acquire` hard-codes pid 0 (bin/sabha-heavy:115) and `clean()` skips the liveness test for pid 0
   (bin/sabha-heavy:55 `[[ ${pid:-0} != 0 ]]`), so a pid-0 slot of a crashed run lives until the 1800 s TTL; and
   `sabha-heavy run` (bin/sabha-heavy:118-126) would put `sabha-heavy` between the pass and the child, so the lock
   would hold the child's `$$` while the pass waits for `$!` = the wrapper's pid (bin/sabha-run:88 and :180-187)
   and every heavy run would be reported "did not start". In the `--child` block (bin/sabha-run:84-88), right
   after the lock line, the child runs `sabha-heavy acquire <label> ${SABHA_HEAVY_WAIT:-900} $$`; on 75 it writes
   a BLOCKED `.done` (the same shape as bin/sabha-run:192-193) instead of running claude; on exit its EXIT trap
   releases the slot. Its 1 s watch loop (bin/sabha-run:101 on) runs `sabha-heavy touch <label>` (bin/sabha-heavy:117)
   once a minute: the TTL test (bin/sabha-heavy:54, mtime older than 1800 s) applies to live pids too, so a run
   over 30 minutes needs the heartbeat. A crash is covered by liveness (pid dead) at the next `clean()`, no
   longer by TTL alone. A pane that runs a heavy command itself uses `sabha-heavy run` as it does today (there the
   wrapper is the process that must be alive).
3. "Starts by itself" = the existing schedule: `sabha-watch` with `SABHA_RUN_AUTO=1` runs a `sabha-run` pass
   (bin/sabha-watch:98); docs/headless-runner.md:30 says what drives it. No new daemon, no new process. Order: oldest
   queue file first, one heavy start per pass (the 45 s settle, bin/sabha-heavy:22 and :74, spaces them anyway).
4. A heavy brief for a role that has a live pane (Karna is a long-lived session, the workspace's PROTOCOL-core.md roster
   note) is not run headless (bin/sabha-run:155-157); the pane's own protocol must run `sabha-heavy check` first.
   So the queue serves headless runs only; this is stated, not solved.

Why the inbox and not a job file of shell commands: a queued shell line would run unattended later with whatever is
in the file (a code-execution surface); a queued brief runs through the same `claude -p` path, permission mode and
guard hooks as every other brief.

**Files touched.** `bin/sabha-heavy` (two keys, load5 parse, the optional pid argument of `acquire`), `bin/sabha-run`
(heavy header, queue file, slot and heartbeat in the child), `docs/headless-runner.md`, `docs/inbox-protocol.md` (the `heavy:` header), `sabha.conf.example`.

**Tests.** `tests/test-heavy.sh` (exists; stub sysctl/uptime): load5 = 21 with MAX 20 -> 75; load5 = 19 -> 0;
LOAD_AVG unset keeps today's load1 result; `acquire <label> 0 <pid>` writes that pid, a slot whose pid is dead is
reaped by the next `clean()` at once, and `acquire` without the argument still writes pid 0. `tests/test-run.sh` (exists): a `heavy:` brief under WAIT is not acked
and leaves a queue file; under GO it is acked, a slot file names the child pid, and the slot is gone after the run;
two heavy briefs in one pass -> only one starts.

**Size.** M.

### 6b. Morning digest page

**Problem (real use).** Overnight work ends as scattered `.done` files, status top blocks and for-me items; the
relay rebuilds a 5-line report by hand each morning, and the deadline is fixed in the brief ("at 07:00 IST with
what is left", the relay's overnight brief to the dispatcher, last paragraph). The board
(`FOR-ME.html`) shows current state, not "what changed since last night".

**Design.** A new mode `sabha-for-me --digest [--since <utc>]` in the existing renderer (bin/sabha-for-me:2, render
paths :543, :744, :1010). Default `--since` = the mtime of the previous digest, else 12 h. Writes
`DIGEST-<yyyy-mm-dd>.html` (and `.md`) beside `FOR-ME.html`, never overwriting an older day (the owner's
version-never-overwrite rule). Sections, each built from files the renderer already parses:
1. Finished: every `NNN.done` with mtime in the window: role, brief title, first paragraph of the `.done`.
2. Blocked: `.blocked*` files, `Blocked:` status lines, heavy queue files (6a) with their WAIT reason.
3. The owner's commands: OPEN `for-me.items` whose block has `cmd:`, oldest first, the command shown verbatim in a copy
   block (no elision, no inline `#`: the pack-lint rule from section 8 is applied as a check, and an item that fails
   it is shown with the reason instead of the command).
4. Owed: the `sabha owe` list (7.3) when present.
5. Roles: status line 1 per role and its age.
Built by the same schedule as 6a (the watch pass), once per local day after `SABHA_DIGEST_HOUR` (default 6).
Read-only on every source file.

**Files touched.** `bin/sabha-for-me`, `bin/sabha-watch` (one call), `docs/how-it-works.md`, `sabha.conf.example`.

**Tests.** `bin/sabha-for-me --selftest` (exists, bin/sabha-for-me:1055) gains digest cases: a fixture IMPL with one
.done inside and one outside the window -> only one in Finished; a cmd containing ` # ` or `...` is flagged; a
second run on the same day writes nothing new when nothing changed, and a new day never touches yesterday's file.

**Size.** M.

### 6c. `sabha whoami` and the relay pre-turn check

**Problem (real use).** 8 Nov (the relay's overnight brief, item 2 (c)): the relay confused its own session id
with another, and a cwd drift made a `sed` the owner pasted run in the wrong folder. 4 Nov: the relay said the grid was
down because its `ps` grep used the wrong flag, and four stale resumed sessions sat beside the live ones
(<workspace>/<impl>/status/vidur.md:18). The kit has the pieces but no single answer: the role
comes from `SABHA_ROLE` or the hook's `session_name` (hooks/lib.sh:12-22), the cwd from the statusline input
(bin/statusline-sabha.sh:28), live processes from `sabha_procs` (bin/sabha-lib.sh:322).

**Design.**
1. `bin/sabha whoami` (new subcommand in bin/sabha, dispatch table at bin/sabha:430-436). Prints exactly:
   `role: <Name> | session: <id or unknown> | cwd: <pwd> | conf: <SABHA_CONF> | impl: <SABHA_IMPL> | pane: <id or -> | live copies: <n>`.
   `session` comes from `status/whoami/<Name>.txt`, which the SessionStart hook writes (hooks/sabha-session-start.sh
   already runs at startup|clear|compact and has `HK_ROLE`; it adds `session_id` and `cwd` from its stdin JSON).
   `live copies` = rows of `sabha_procs` with this name; more than one prints a `WARN duplicate` line and exits 3.
2. Relay pre-turn check: a `UserPromptSubmit` hook (new entry in hooks/hooks.json, which today has SessionStart,
   PreToolUse, PermissionRequest, Stop) that runs only for the relay role (`HK_BASE = HK_RELAY`, the same comparison as
   hooks/sabha-guard.sh:13, which uses it the other way round: there `[ "$HK_BASE" = "$HK_RELAY" ] && exit 0` exempts
   the relay from the worker guard, here the relay is the only role the hook runs for) and prints the whoami line as context before each turn. Stdout of the hook becomes
   context (the SessionStart hook relies on this, hooks/sabha-session-start.sh:2). Cost: one line per turn.
3. Packs: every command line the owner pastes starts with `cd <absolute path> &&`. The whoami cwd and the pack lint
   (section 8) together cover the drift case; the hook alone cannot fix a pasted command.

**Files touched.** `bin/sabha` (subcommand), `hooks/sabha-session-start.sh` (write whoami file), new
`hooks/sabha-preturn.sh`, `hooks/hooks.json`, `hooks/lib.sh` (only if a helper for session_id parse is shared),
`README.md` (commands table), `skills/sabha-relay` (one line: read the whoami line before answering "who/where").

**Tests.** `tests/test-hooks.sh` (exists): feed SessionStart JSON with a session_id -> whoami file written;
pre-turn hook prints one line for the relay and nothing for another role or a non-sabha session; a hook failure
exits 0 (hooks/lib.sh:1 "fail soft"). New `tests/test-whoami.sh` with `SABHA_PS_FILE` (bin/sabha-lib.sh:318): one
copy -> exit 0; two copies -> WARN and exit 3.

**Size.** S.

## 7. Specced features (upstream radar)

### 7.0 Shared read-only GitHub fetch layer (used by 7.1, 7.2, 7.4 and Later 8)

**Problem.** The kit has no GitHub code today (`grep -n 'gh ' bin/*` -> no command hits). The owner's PR facts are
gathered by hand per session (<workspace>/docs/<queue>/pr-states-5nov.md:1-3: "read live ... read-only gh"),
and each new tool would otherwise re-invent auth, paging and rate limits.

**Design.** One file `bin/sabha-gh`, bash, wrapping `gh api` only.
- Read-only by construction: it builds the `gh api` argv itself and accepts only a path and `--paginate`/`--jq`;
  a path must start with `repos/`, `orgs/`, `search/` or `users/` (or be a named read below) and must not start with
  `-` or contain whitespace, so a path cannot turn into a flag; there is no way to pass `-X`, `--method`, `-f`, `-F` or `--input`. GraphQL reads go through
  `gh api graphql -f query=...` built inside the wrapper from a fixed list of named queries; a query text
  containing `mutation` is refused. So no caller can write.
- Account: `SABHA_GH_USER` (owner's conf: `<gh-user>`); before the first call it checks `gh api user --jq .login`
  and stops with one line if it differs (the wrong account gives "Could not resolve to a Repository").
- Cache: `status/gh-cache/<sha1 of argv>.json` with fetch time (it holds PR titles and bodies of private repos: it
  lives under `SABHA_IMPL/status/`, which both the kit `.gitignore` (`/status/`) and the workspace's ignore, and no pack
  or digest copies the files, only the rendered table); `SABHA_GH_TTL` (default 600 s); `--fresh` bypasses.
  A failed call returns the cached copy marked `stale` rather than nothing, or exit 1 when there is none.
- Rate: honours `X-RateLimit-Remaining` (via `gh api -i` on the first page) and stops at `SABHA_GH_MIN_LEFT`
  (default 200), so a radar never eats the owner's quota.
- Sandbox: `gh` fails inside the Claude sandbox (network and keychain); the tools are meant for a plain terminal or
  the watch schedule, and say so on failure.
- Named reads: `pr <repo> <n>`, `prs-by-author <org> <login>`, `compare <repo> <base> <head>` (returns
  `ahead_by`, `behind_by`, `status`), `repo <repo>` (archived, default branch, renamed: GitHub redirects a renamed
  repo and the returned `full_name` differs), `branch <repo> <b>`, `contents <repo> <path> <ref>` (exists or not).

**Files touched.** new `bin/sabha-gh`, new `tests/hermetic-bin/gh` fake, `tests/hermetic.sh` (fake gh first on PATH,
same guard pattern as herdr), `docs/github-layer.md`.

**Tests.** `tests/test-gh.sh`: every named read maps to the expected `gh api` argv (fake logs calls); a caller
passing `-X POST` or a mutation is refused with exit 2; a path starting with `-` is refused with exit 2; wrong login -> stop; cache hit makes no second call; TTL
expiry makes one; failure with cache -> stale result; rate below the floor -> stop. Hermetic guard: the test exits
2 if the first `gh` on PATH is not the fake.

**Size.** M.

### 7.1 `sabha prs` - PR radar

**Problem (real use).** 8 Nov (the relay's upstream-radar brief, item 1): guardians #1350 and #1278
were stranded in an archived repo; arcus #1231 was 51 behind dev and #1189 231 behind, both from before the `apps/`
layout. Guardians still sits in the owner's repos.conf with base `release/arcus-automation-sprint-3`
(<workspace>/dev-setup-2.0/repos.conf:9), so nothing local says it is archived. The 5 Nov PR table was a one-off
hand read (<workspace>/docs/<queue>/pr-states-5nov.md).

**Design.** `bin/sabha prs [--org <org>] [--author <gh-user>] [--repo owner/name ...]` (defaults from
`SABHA_PRS_ORGS`, `SABHA_PRS_AUTHOR`, `SABHA_PRS_REPOS`; owner's conf: <org> by author, plus
The-Harsh-Vardhan/claude-sabha). Through 7.0: `prs-by-author`, then per PR `pr` (reviewDecision, mergeable,
mergeStateStatus, isDraft, baseRefName, updatedAt), `compare <base> <head>` for `behind_by`, `repo` for archived.
Output: one table sorted by risk: `ARCHIVED` > `CONFLICT` > `BEHIND>50` > `CHANGES_REQUESTED` > `STALE>7d` > ok;
columns repo, #, title (60 chars), base, age, review, mergeable, behind, flag. `--md FILE` writes the table for the
board/digest; `--json` for the board writer. Read-only; it never closes or comments (<workspace>/docs/<queue>/pr-states-5nov.md:3 "Agents close nothing").

**Files touched.** `bin/sabha` (subcommand) or a small `bin/sabha-prs`, `sabha.conf.example`, README commands table.

**Tests.** `tests/test-prs.sh` with fake gh fixtures: an archived-repo PR flags ARCHIVED and sorts first; behind_by
231 -> BEHIND; mergeStateStatus DIRTY -> CONFLICT; empty list prints "no open PRs"; a gh failure prints the stale
cache with a "stale" header.

**Size.** S (on top of 7.0).

### 7.2 `sabha shipped <repo#pr>` - where a merged PR has reached

**Problem (real use).** 8 Nov (the radar brief, item 2): testsigma #10891 and #10900 are in `master` via #10906 but not in
`9.4.7` or `9.4.7-cs`; finding that took manual branch reading. The promotion chain is not stored anywhere in the
kit; the bases are in repos.conf (testsigma `devtesting`, groot `prod`, <workspace>/dev-setup-2.0/repos.conf:10-11).

**Design.** `sabha shipped <owner/repo#n>`: read the PR (7.0 `pr`) for `mergeCommit` and base; then for each branch
of the chain run `compare <branch> <mergeCommit>`: `status: behind` or `identical` = the commit is in the branch
(in), `ahead`/`diverged` = not in. Squash merges change the sha on each promotion, so a "not in" by sha is
re-checked by searching the branch for a PR title/number reference (`commits?sha=<branch>&since=<merge date>`,
first 300) and reported as `in (via #10906)` when a promotion PR's body or title names it. Chains in conf, one line
per repo: `SABHA_CHAIN_testsigma="devtesting staging master 9.4.x 9.4.x-cs"`, `SABHA_CHAIN_groot="... prod"`;
release lines given as patterns resolve to the newest matching branch (`9.4.7`). Output: one line per branch:
`master  in (via #10906, 2026-11-0x)` / `9.4.7  NOT IN`.

**Files touched.** `bin/sabha` subcommand (or `bin/sabha-shipped`), `sabha.conf.example` (chains), docs.

**Tests.** fake gh fixtures: direct merge -> in; squash-promoted -> in (via #N); missing -> NOT IN; unknown chain ->
exit 2 naming the conf key; a pattern resolves to the newest branch.

**Size.** M (the squash re-check is the work; the sha compare is S).

### 7.3 `sabha owe` - drafts the owner owes people

**Problem (real use).** The valkyries #367 message to a reviewer blocked the picker all day (the radar brief, item 3); for-me items
already carry `owner`, `why`, `unblocks` (<workspace>/docs/<queue>/board-writer/status-mapping.md, sources
table), and drafts live as files (e.g. <workspace>/docs/daily-updates/<recipient>/2026-11-04.md), but nothing lists
"written, not sent" with what each one blocks.

**Design.** `sabha owe` reads three sources, all local and read-only:
1. OPEN `for-me.items` whose title or `why` names a person or a send verb (`send`, `message`, `reply`, `post`,
   `ask <name>`) - a word list in conf (`SABHA_OWE_WORDS`), not a model call.
2. Draft files under `SABHA_OWE_DIRS` (owner's conf: `docs/daily-updates/<recipient>`, message-draft folders) without a
   `sent:` line or a sibling `.sent` marker. Sending stays the owner's; marking sent is `sabha owe --sent <path>`
   (writes the marker, nothing else).
3. Board rows whose `dependsOn` or `unblocks` names one of the above, to print "blocks: Q-xxx, F-yyy".
Output: oldest first, `age | to | what | path | blocks`. The digest (6b) embeds it.

**Files touched.** `bin/sabha-for-me` (it already parses for-me.items; owe is a view, `--owe`), `bin/sabha`
subcommand alias, `sabha.conf.example`.

**Tests.** selftest fixtures: an OPEN item "send a reviewer the #367 note" with `unblocks:` -> listed with blocks; a
DONE item -> not listed; a draft with `.sent` -> not listed; age from `utc:` / mtime.

**Size.** S.

### 7.4 Upstream move watcher

**Problem (real use).** guardians was archived, behaviour-tree-ecosystem was renamed automation-core, and dev was
reverse-merged into sprint-3.1; all three were learned from Slack screenshots (the radar brief, item 4). repos.conf still lists
guardians with a live base (<workspace>/dev-setup-2.0/repos.conf:9) and automation-core on `feat/sigmascript-v1`
(:19), so local files cannot notice a move.

**Design.** `sabha upstream [--conf <repos.conf>]`, read-only, once a day from the watch schedule (same "once per
local day" stamp as 6b). For each row (columns repo, dir, base-ref; repos.conf header line 6): via 7.0
- `repo`: archived? `full_name` differs from the remote in the clone's `git remote get-url origin` (rename)?
  default branch changed?
- `branch <base>`: still exists?
- layout: `contents <repo> <path> <base>` for a per-repo probe list in conf (`SABHA_UPSTREAM_PROBE_arcus="apps/"`),
  flags when a probe appears or disappears against the last run.
- reverse merge: `compare <base> <upstream>` per pair in `SABHA_UPSTREAM_PAIRS` (`release/... dev`): flags when
  `behind_by` drops to 0 against a non-zero last run (the upstream was merged in).
State: `status/upstream/last.json` (last run's facts). Each new finding (not already reported) appends one
`for-me.items` block (`owner: <owner>`, `title: upstream: guardians archived`, `why:` the fact and its source) and
writes one brief to the dispatcher via `bin/sabha-brief` naming the affected worktrees (`git worktree list` in
the clone). The board writer turns the item into a row as it does today (status-mapping.md "F rows"). It never
edits repos.conf (a base change is an "Ask before" item in the owner's CLAUDE.md).

**Files touched.** new `bin/sabha-upstream`, `bin/sabha-watch` (daily call), `sabha.conf.example`, docs.

**Tests.** fake gh fixtures across two runs: run 1 baseline writes no item; run 2 with archived=true -> one item and
one brief; run 3 same facts -> nothing new; renamed full_name -> item naming old and new; branch gone -> item;
gh failure -> no item and a single warning (a failed read never reads as "moved").

**Size.** M.

## 8. Later (one paragraph each)

**Pack lint.** `sabha pack-lint <file>` rejects command lines with an inline ` # ` comment (the owner's zsh passes them
as arguments), any `...` or Unicode-ellipsis elision, a non-ASCII arrow, and a line that does not start with `cd /absolute &&`.
Used by 6b on `cmd:` fields and runnable as a pre-commit check on `docs/sabha/pr-bodies/*.md`. Size S.

**Stale pane reaper.** `sabha reap` lists panes (launcher `L_list_panes`) and claude processes (`sabha_procs`) by age,
idle time and last context percent (cost proxy), marks resumed duplicates (two rows, same name, the 4 Nov case in
<workspace>/<impl>/status/vidur.md:18), and closes only the ids the owner confirms on the same command line
(`sabha reap --close <id> ...`). Never closes a role's only live copy. Size M.

**5. Rules as hooks.** Move the owner's paste-and-repo rules from prose into the PreToolUse guard: no inline `#` in pack
files, absolute `cd` prefix, ASCII only in written files, no AI attribution in commit messages, no push to shared
branches (dev, main, master, release/*, sprint), no read of `.env*`. The pattern is the relay guard (open PR #63,
branch relay-guard-allow, commits 13c840c..28e4720) on top of hooks/sabha-guard.sh: a text check that catches
honest mistakes, documented as not enforcement (hooks/sabha-guard.sh:3). Size M.

**6. `sabha intake`.** A Slack screenshot or a Granola meeting note in a drop folder becomes a fact list, decisions
and asks, then one board row and one dispatcher brief per ask. The model reads the image or note; the script only
files the result through `sabha-brief` and `for-me.items`. Nothing is sent back to Slack. Size M.

**7. `sabha fill`.** Overnight planner: reads `bin/sabha-limits.sh` usage, the heavy gate (6a) and the backlog of
un-acked briefs, and proposes a night order with CPU-light work first and heavy briefs queued for load5 <= 20.
It proposes; the dispatcher starts. Size M.

**8. Chain view.** Board rows already have a `dependsOn` field (status-mapping.md field map, last row); render
cross-repo blocker chains (row -> PR -> branch reach from 7.2) as a small graph on the board, using 7.0 for the PR
and branch facts. Size M.

**9. `sabha-gate` workspace checks.** Make `bin/sabha-gate` read a per-workspace list of required checks: Aikido scan
recorded, screenshots named in UI PR packs, no "NOT IN DESIGN" item without an approval line, the PR questions file
present. Each check is a file test, not a model judgement. Size S per check.

**10. `sabha nightly`.** Draft the nightly progress note (the owner's nightly-update rule) from the day's `.done` markers and
board changes into `docs/daily-updates/<recipient>/<date>.md`; the owner reviews and sends. Shares 6b's window logic.
Size S.

**11. `sabha decide`.** One MCQ answer from the owner becomes, in one command: the board row state, a line in the PR
questions file (questions-go-with-the-pr), and a decision log entry with the next D number. Size S.

**12. `sabha prune`.** Weekly: run the owner's `bin/wt-inventory.sh` dry run (<workspace>/bin/wt-inventory.sh) and put its
archive candidates on the board as one row; `--apply` stays the owner's. Size S.

## 9. Open questions for the owner (defaults adopted)

1. tmux as a fourth launcher, or drop it and keep herdr-or-iTerm? Default: build it (Linux/WSL users have no other).
2. 6a: should `sabha-run` also hold a heavy brief while any interactive pane holds a heavy slot? Default: yes, the
   slot count already covers it.
3. 6c: one context line per relay turn is acceptable cost? Default: yes, relay only.
4. 7.0: `SABHA_GH_TTL` 10 minutes? Default: yes; `--fresh` for a live check.
5. 7.4: does a finding also open a brief, or only a board row? Default: both, as the radar brief asks.
