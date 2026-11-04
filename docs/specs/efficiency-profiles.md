# Efficiency profiles for sabha

Status: SPEC ONLY. Nothing here is built. Written 4 Nov 2026 for Harsh, on brief 356 (Vidur to Yudhishthira,
`Arcus-Dev/docs/pdf-report-2.0/impl/inbox/Yudhishthira/356-vidur-sabha-efficiency-apply.md`), which carries Harsh's
answers Q1-Q6 and Q8 ("spec now, behind a flag"). Marks used below: [VERIFIED] = I ran or read it this session;
[UNVERIFIED] = reasoned or assumed, check before building; [PROPOSAL] = a number or name I chose, Harsh may change it.

## 0. Read this first: the base problem

This branch (`spec/efficiency-profiles`) was cut from the local `main` HEAD `ab3f9d2` as instructed. That HEAD is
104 commits behind `origin/main` (`cd90eaf`) [VERIFIED: `git rev-list --count ab3f9d2..origin/main` = 104]. It has no
`bin/sabha-loop`, no `SABHA_PANES`, no plan files and no `sabha_conf_read`. Those exist on `origin/main` (read in the
worktree `~/Work/claude-sabha-worktrees/main-live` at `91e5488`, one commit behind `cd90eaf`) and in the installed
plugin `~/.claude/plugins/cache/claude-sabha/claude-sabha/2.0.0/` [VERIFIED]. So every file named in section 8 is
named from `origin/main`; the implementation must start from `origin/main`, not from this branch. Line numbers are
not quoted because they differ between the two.

## 1. What this changes, in one table

| # | Change | Harsh's answer | Where it lives |
| --- | --- | --- | --- |
| 1 | Profiles Lite / Standard / Full from cores and RAM | Q1, Q2 | `bin/sabha-lib.sh`, `sabha.conf.example` |
| 2 | Dispatcher load gate, max heavy jobs at once | Q3, Q4 | new `bin/sabha-heavy`, dispatcher protocol file |
| 3 | `sabha-loop` is the default starter | Q5 | `bin/sabha-up.sh` |
| 4 | Per-role MCP sets | Q6 | `bin/sabha-up.sh`, `bin/sabha-run`, `bin/sabha-lib.sh` |
| 5 | One flag `SABHA_EFFICIENCY` switches all four; off = today | Q8 | `sabha.conf` |

The load indicator mod (Q4, second half) is a separate task in `~/Work/claude-mods`; section 3.6 only fixes the one
command it reads so the colours and the gate use the same numbers.

## 2. The flag

```
SABHA_EFFICIENCY=1      # default on; any other value is off
```

- Set in `sabha.conf` (gitignored, per user) and documented in `sabha.conf.example` (tracked) with the default
  shown as `SABHA_EFFICIENCY=1` uncommented in the example, so a fresh copy is on. A user whose existing
  `sabha.conf` has no line gets the library default `${SABHA_EFFICIENCY:-1}`, i.e. on. This is what "default on" means
  here; it is a behaviour change for existing installs, which is why section 6 pins the off path.
- One read point: a function `sabha_efficiency` in `bin/sabha-lib.sh` returning 0 when `SABHA_EFFICIENCY` is `1`.
  Every change below starts with `sabha_efficiency || <today's code>`. No second flag; the per-feature knobs in
  section 7 only tune values and are ignored when the flag is off.

## 3. Design

### 3.1 Profiles (Q1, Q2)

Harsh, Q1: five sessions - one relay, one dispatcher, three worker panes, long-lived tasks; the rest headless and
managed by the dispatcher. Q2: the three panes are Bhishma, Arjun (code), Karna (testing). That is `Standard`.

Selection. Read hardware once: cores = `hw.ncpu`, RAM = `hw.memsize` (bytes). Each gives a tier; the profile is the
lower tier of the two (the scarcer resource decides).

| | Lite | Standard | Full |
| --- | --- | --- | --- |
| Cores | under 8 | 8 to 11 | 12 or more |
| RAM | under 12 GB | 12 GB to under 32 GB | 32 GB or more |
| Status of the row | PROPOSAL | Harsh's Mac [VERIFIED: hw.ncpu 10, hw.memsize 17179869184 = 16 GB, M1 Pro per brief] | PROPOSAL |
| Sessions at once (relay + dispatcher + panes) | 3 | 5 | 8 |
| Worker panes | 1: Arjun | 3: Bhishma, Arjun, Karna | 6: Bhishma, Arjun, Bhima, Sahadev, Karna, Nakul |
| Heavy jobs at once (3.2) | 1 | 2 | 3 |
| Headless runs at once (`SABHA_RUN_MAX`) | 1 | 2 | 3 |
| Every other role | headless, short-lived, started by the dispatcher | same | same, plus gate critics as today |

Standard's panes and the 2-heavy cap are Harsh's decisions. Everything in the Lite and Full columns is a PROPOSAL.

Basis for the proposals [UNVERIFIED reasoning, one hard data point]:
- Memory. The only measured fact in the repo is `docs/headless-runner.md`: "Sixteen idle panes exhausted a 32 GB
  Mac", about 2 GB per interactive session all-in (the claude process, its MCP servers, the child tools it started).
  That divides by 16 and is an upper-bound guess, not a measurement. Budget: leave about 7 GB for macOS, the browser,
  Docker and the dev servers; the rest divided by 2 GB: 16 GB gives about 4 to 5 sessions (Standard: 5, Harsh's
  number agrees); 8 GB gives 0 to 1, so Lite's 3 is already tight and Lite is meant for an 8 to 12 GB machine with
  one pane's worth of headroom; 32 GB gives 12, taken down to 8 to keep room for Docker e2e.
- Cores. One heavy job (a Gradle or webpack build, a Playwright run, a Docker e2e) saturates 4 to 5 cores while it
  runs, so cores / 4.5 rounded down: under 8 cores gives 1, 10 cores gives 2, 12 or more gives 3.
- Measure before trusting any of it: acceptance check A9 records resident memory per role so these numbers can be
  replaced by data.

Explicit config wins: `SABHA_PROFILE=lite|standard|full|auto` (default `auto`). `SABHA_PANES`, `SABHA_RUN_MAX`,
`SABHA_HEAVY_MAX` set in `sabha.conf` override the profile's value one by one.

What a profile actually sets, when the flag is on and the user did not set it:
- `SABHA_PANES` (the standing grid: relay, dispatcher, then the worker panes of the table); every roster role not in
  the list is headless (`lazy`) or on demand, run by `bin/sabha-run`. On the old-format roster in this workspace
  (`Name:model:effort:flags`, no agent field) the same effect is reached by rewriting the roster flags in the
  profile layer; the implementation picks one, see open question Q-B.
- `SABHA_RUN_MAX` and `SABHA_HEAVY_MAX` from the table.

Bhima's arcus work goes to Bhishma or a headless session (Harsh, Q2) - that is a dispatcher routing rule, stated in
the dispatcher's protocol file (section 8), not code.

### 3.2 Dispatcher load gate (Q3, Q4)

Rule: before the dispatcher starts a heavy job it runs the gate. A heavy job is a dev server, a build, a Playwright
or browser test run, or a Docker e2e (Harsh's list). The gate says GO only when all hold:
1. load1 <= 2 x cores (20 on this Mac);
2. memory pressure is green (normal);
3. fewer than `SABHA_HEAVY_MAX` slots are held (2 on Standard).

Otherwise the job waits (3.3) and the dispatcher tells the relay why, in one line, e.g.
`HEAVY WAIT: load1 103.1 > 20 (10 cores); memory yellow; slots 1/2`.

Reads (no root, no model). Verified on this Mac on 4 Nov 2026, outside the Claude sandbox:

| Value | Command | Output [VERIFIED] |
| --- | --- | --- |
| cores | `sysctl -n hw.ncpu` | `10` |
| load1 | `sysctl -n vm.loadavg`, first number | `{ 103.10 108.81 126.63 }` |
| memory pressure | `sysctl -n kern.memorystatus_vm_pressure_level` | `2` (yellow) at the same moment |
| free memory | `memory_pressure -Q` | `System-wide memory free percentage: 32%` |

Mapping of the pressure level: 1 = green, 2 = yellow, 4 = red (macOS memorystatus levels; 1 and 2 seen, 4 not
seen: [UNVERIFIED]). The gate treats anything other than 1 as "not green".

Two facts that shape the design:
- `memory_pressure` alone does not print green/yellow/red; `-Q` prints only a free percentage. The brief's "memory
  pressure is yellow/red" therefore needs `kern.memorystatus_vm_pressure_level`. At free 32% the level was already
  yellow [VERIFIED], so a free-percentage rule under-reports pressure.
- Inside the Claude Code sandbox `sysctl` fails: `sysctl: sysctl fmt -1 1024 1: Operation not permitted` for
  `hw.ncpu`, `hw.memsize` and `vm.loadavg` [VERIFIED in this agent's sandbox; the dispatcher's own sandbox is
  UNVERIFIED]. In the same sandbox `uptime` worked (`load averages: 95.15 107.52 126.39`) and `memory_pressure`
  worked [VERIFIED]. So `bin/sabha-heavy` reads in this order: `sysctl`, and on failure `uptime` (load) and
  `memory_pressure -Q` (free percent). The core count has no sandbox-safe read found: fall back to
  `getconf _NPROCESSORS_ONLN` or `sysctl` run outside the sandbox [UNVERIFIED that getconf works in the sandbox].
  When only the fallback is available, the memory rule becomes "free percent below `SABHA_HEAVY_FREE_PCT`
  (default 40) counts as not green" [PROPOSAL: from one data point, 32% was yellow]. A gate that cannot read
  anything prints `HEAVY WAIT: cannot read load` and exits blocked; it never guesses GO.

Right now (4 Nov, 19:35 on this Mac) load1 is 103 on 10 cores and the level is yellow, so the gate would hold every
heavy job until the box recovers. That is the situation the change targets.

### 3.3 The tool: `bin/sabha-heavy` (new, one file, bash 3.2 safe)

```
sabha-heavy check                    # read-only: prints the verdict line, exit 0 GO, 75 WAIT
sabha-heavy acquire <label> [secs]   # check + take a slot; polls every 30 s up to secs (default SABHA_HEAVY_WAIT 900)
sabha-heavy release <label>          # frees the slot
sabha-heavy run <label> -- <cmd...>  # acquire, run cmd, release on exit (trap), heartbeat while it runs
sabha-heavy status                   # one line: "load 103.1/10 red | mem yellow | slots 1/2 | build-x, e2e-y"
```

Exit 75 (EX_TEMPFAIL) with the reason on stdout, so the dispatcher can paste it to the relay. It never bypasses
itself; a human override is `SABHA_HEAVY_FORCE=1` on that one call, which logs `FORCED by <who>` in the slot file.

The slot counter (Harsh's "2 heavy jobs" needs a place to live):
- Directory `$SABHA_IMPL/status/heavy/` (beside `status/loop/`; the dispatcher already writes under `status/`).
  One file per held slot: `<label>.slot`, ASCII, `key: value` lines like the inbox files: `pid`, `epoch`,
  `host_session`, `label`, `forced` (optional).
- Count and take under a lock: `mkdir "$dir/.lock"` (atomic on APFS), count, write, `rmdir`. This closes the race the
  headless runner admits to (docs/headless-runner.md "Limits": two passes in the same instant can exceed the cap by
  one); `mkdir` is the lock because stock macOS has no `flock` [UNVERIFIED: `flock` absent on this Mac].
- Staleness. A slot is live when its `pid` is alive (`kill -0`) AND its heartbeat is fresher than
  `SABHA_HEAVY_TTL` (default 1800 s). `run` touches the file every 30 s. A slot taken by `acquire` with no wrapper
  (the dispatcher ran the job through its own Bash tool, so no stable pid exists) records pid 0 and expires only by
  TTL, which the dispatcher renews with `sabha-heavy touch <label>` or frees with `release`. Every call first
  deletes dead or expired slot files and says so on stderr. TTL 1800 is a PROPOSAL (SABHA_RUN_TIMEOUT is 3600 for a
  whole headless brief; a heavy job inside it is shorter).
- Settle time. load1 is a one-minute average, so two jobs started 10 seconds apart both see the old number. After a
  successful `acquire`, the next `acquire` waits until `SABHA_HEAVY_SETTLE` (default 45 s) has passed since the last
  slot's `epoch` [PROPOSAL]. The count already stops the third job; settle stops a second job from landing on a
  box the first has not loaded yet.

Telling the relay "why": the dispatcher writes the verdict line to its own status file's top block and sends the
relay a nudge (the existing SendMessage convention), once per change of reason, not per poll. No new brief type. See
open question Q-D.

### 3.4 sabha-loop as default starter (Q5)

`sabha-loop <Name>` supervises one role in one terminal and restarts it fresh at `SABHA_LOOP_LIMIT` (30) percent
context once the handoff file is newer than the last start [VERIFIED, header of `bin/sabha-loop` in the 2.0.0 plugin
copy]. On `origin/main` the grid already runs it in every pane (`bin/sabha-up.sh`: "each pane runs sabha-loop, which
starts sabha-up.sh <Name>") [VERIFIED at 91e5488]. The gap is the single-role path: `sabha-up.sh --print <Name>`
prints the raw `claude ...` line first and the `pane: ... sabha-loop <Name>` line second [VERIFIED at 91e5488], so a
user (or Vidur composing "restart lines" for Harsh) copies the raw line and the pane runs with no supervisor.

With the flag on:
- `sabha-up.sh --print <Name>` prints the `sabha-loop` line as the primary line. The raw `claude` line is printed only
  with `--raw`, or when the user's message asks for it ("unless asked otherwise by the user"; the relay passes
  `--raw`).
- `sabha-up.sh <Name>` started by hand in a terminal that is not already under a loop prints one line to stderr
  (`not supervised: use sabha-loop <Name>`) and still starts. It must not exec the loop itself: the loop starts
  `sabha-up.sh <Name>` and that would recurse. Detect "already under a loop" by an environment variable the loop
  exports for its child (`SABHA_LOOP_ACTIVE=<Name>`) [PROPOSAL: the loop does not export one today, UNVERIFIED].
- Non-claude roles keep their herdr path (`sabha-up.sh` already branches on the agent kind on `origin/main`).

### 3.5 Per-role MCP sets (Q6)

Harsh: full stack only on Relay, Dispatcher and the test agent when needed; everything else restricted as much as
possible; Bhishma and Arjun `--strict-mcp-config` with the minimum; Karna full only if a test needs it.

Today [VERIFIED, `bin/sabha-up.sh` and `bin/sabha-run`]: the roster flag `mcp` keeps the user's MCP servers; a role
without it gets `--strict-mcp-config` and therefore no MCP server at all (no `--mcp-config` is ever passed). In this
workspace's `sabha.conf` only Yudhishthira, Sanjaya and Shakuni carry `mcp`; Vidur, Bhishma, Arjun and Karna do not.
So the gap is not "Bhishma and Arjun have too much" - they already get none when started by `sabha-up.sh` - it is
that (a) the Relay (Vidur) gets none although Harsh wants it full, (b) Arjun gets none although the Aikido rule needs
one, and (c) a hand-typed restart line (the 355 lines) can carry the full stack.

The MCP servers that exist in this setup, from config actually read [VERIFIED unless marked]:

| Server | Where it comes from | Tools seen |
| --- | --- | --- |
| `GitKraken` | `~/.claude.json` top-level `mcpServers` (the only user-level server in that file) | `mcp__GitKraken__git_*`, `pull_request_*`, `issues_*`, `gitlens_*` |
| `aikido-mcp` | plugin `aikido@claude-plugins-official` 1.2.11, `.mcp.json`: `npx -y @aikidosec/mcp@1.0.28` | `mcp__plugin_aikido_aikido-mcp__aikido_scan_paths`, `aikido_oss_dependency_scan`, `aikido_issues_list`, `aikido_full_scan`, ... |
| `plugin-authoring` | the `cc-plugin-plugin-authoring` plugin (visible as the `plugin-authoring` server in this session; its config file was not read) | `mcp__plugin-authoring__scan_secrets` |
| claude.ai connectors (Slack, Jira, Drive, ...) | account level, not in any file I read; named only in Harsh's memory notes [UNVERIFIED that they are MCP servers in a CLI session] | not listed |

Not found: no `.mcp.json` at the workspace root (`Arcus-Dev/.mcp.json` does not exist), no `mcpServers` in
`Arcus-Dev/.claude/settings.json` or `~/.claude/settings.json`, and no Playwright server in any file I read.
The `ts`/Playwright runs go through Bash and `claude --chrome`, not MCP [UNVERIFIED]. Plugins `burn-meter`,
`context-lens`, `statuspane`, `agent-flow` are enabled in `~/.claude/settings.json`; whether they register MCP
servers was not checked.

Candidate minimum per role (a PROPOSAL built only from the servers above):

| Role | Set | Why |
| --- | --- | --- |
| Relay (Vidur) | full (flag `mcp`) | Harsh, Q6; talks to Harsh and the connectors |
| Dispatcher (Yudhishthira) | full (flag `mcp`, as today) | Harsh, Q6 |
| Bhishma (design) | none (`--strict-mcp-config`, no `--mcp-config`) | writes design papers and decisions as files; no commits ("helpers stage, Vidur commits", memory note); Aikido is run by whoever commits |
| Arjun (code) | `aikido-mcp` only | the Aikido rule: `aikido_scan_paths` before every commit, and Arjun commits locally in worktrees (Arjun.md "commit on the feature branch at each green milestone"). `GitKraken` is not needed: `git` goes through Bash |
| Karna (tests) | none by default; full only when a brief says a test needs it | Karna.md: builds, suites, e2e, the stack; "Test, Docker and Chrome runs cost no tokens"; none of it is MCP in what I read |
| Headless helpers (Bhima, Nakul, Sahadev, Abhimanyu, critics) | none, as today | a reviewer reads a diff |

Mechanism (flag on):
- New config, per role: `SABHA_MCP_<Name>=full|none|<set>[,<set>]`, and per named set a JSON file of the exact
  shape `claude --mcp-config` takes: `SABHA_MCP_FILE_aikido=$SABHA_WS/.sabha/mcp/aikido.json`. The aikido file holds
  the same `aikido-mcp` block as the plugin's `.mcp.json`, version pinned there. Implementation passes
  `--strict-mcp-config --mcp-config <file>` for a named set, `--strict-mcp-config` alone for `none`, nothing for
  `full`. A plugin-contributed server is assumed NOT to load under `--strict-mcp-config` [UNVERIFIED: acceptance check
  A6 proves it, and if wrong, Arjun's set is simply `--strict-mcp-config` plus the file and the plugin server is
  dropped some other way].
- Precedence: `SABHA_MCP_<Name>` if set, else the roster flag `mcp` means `full`, else `none`. So today's configs
  keep working and Vidur needs only the `mcp` flag (or `SABHA_MCP_Vidur=full`).
- Karna "full only if a test needs it": a brief header `mcp: full` (new, optional; documented in
  `docs/inbox-protocol.md`). Karna's standing pane stays `none`. A brief carrying `mcp: full` is run by
  `bin/sabha-run` headless with the full stack (`sabha-run` reads the header), so a pane never carries the stack
  "just in case". This is a design choice that Harsh did not state; see open question Q-E.
- The one place all this is resolved: a function `sabha_mcp_args <Name> <brief-or-empty>` in `bin/sabha-lib.sh`,
  used by both `sabha-up.sh` (print and start paths) and `sabha-run` (`role_cmd`), which today duplicate the
  `sabha_flag "$r" mcp` test in three places [VERIFIED: `--print`, start path, and `role_cmd`].

### 3.6 Load indicator contract (for the separate mod)

`sabha-heavy status` is the only command the mod needs: `load <load1>/<cores> <green|amber|red> | mem <green|yellow|red> | slots <n>/<max>`.
Colour: green when load1 <= cores, amber when <= 2 x cores, red above (Harsh, via brief 356 Task 4), so red is exactly
the gate's "wait" threshold. Whether the mod's own sandbox can run `sysctl` is UNVERIFIED (this agent's could not);
if not, the mod uses the `uptime` fallback that `sabha-heavy status` already has. Not in scope here beyond this.

## 4. Decisions

| Question | Choice | Why |
| --- | --- | --- |
| Flag count | One: `SABHA_EFFICIENCY` | Harsh, Q8: "behind a flag"; knobs below it are values, not switches |
| Default | On, library default `1` | Harsh: "default on"; existing `sabha.conf` files without the line get it on |
| Profile source | Hardware tiers, lower tier wins; `SABHA_PROFILE` overrides | the scarcer of cores and RAM is the real limit |
| Gate form | A script (`sabha-heavy`), not prose in the protocol | a model forgets a prose rule; an exit code does not (the "dispatcher forgets" failure this fixes) |
| Counter | files plus `mkdir` lock, pid plus heartbeat plus TTL | no daemon exists in the kit; closes the runner's admitted race |
| Memory signal | `kern.memorystatus_vm_pressure_level` | only source of the real colour; `memory_pressure -Q` gives a percent |
| Gate failure to read | WAIT, never GO | a blind GO is how the box reached load 103 |
| Starter | `sabha-loop` primary line; raw line behind `--raw` | Harsh, Q5 |
| MCP | named sets via `--mcp-config`, resolved in one lib function | one place instead of three |
| Karna full stack | per brief (`mcp: full`) via headless run | keeps the standing pane light |

## 5. Acceptance checks

Each is a command and an expected result, run by the implementer; none has been run (nothing is built).
- A1 Flag off, regression: with `SABHA_EFFICIENCY=0`, the output of `sabha-up.sh --print <Name>` for every role, the
  output of `sabha-run --print`, and the grid script for the current `sabha.conf` are byte-identical to the base
  commit's (diff of captured output). `tests/test-grid.sh`, `tests/test-run.sh`, `tests/test-claim.sh`,
  `tests/test-procs.sh` pass unchanged.
- A2 Profile pick: new `tests/test-profile.sh` feeds fake `hw.ncpu`/`hw.memsize` (env overrides
  `SABHA_FAKE_NCPU`, `SABHA_FAKE_MEM`) and expects: (4, 8 GB) lite; (10, 16 GB) standard; (16, 32 GB) full;
  (16, 8 GB) lite; (4, 64 GB) lite. Explicit `SABHA_PANES` / `SABHA_RUN_MAX` win over the profile.
- A3 Gate: new `tests/test-heavy.sh` with stub `sysctl`/`uptime`/`memory_pressure` on PATH: load 21 on 10 cores = 75 and a
  reason line naming load; load 19, level 2 = 75 naming memory; load 19, level 1, two live slots = 75 naming slots;
  load 19, level 1, one slot = 0; unreadable = 75.
- A4 Counter: two `acquire` calls started in the same instant against an empty dir with max 1: exactly one exits 0
  (repeat 50 times). A slot with a dead pid, and a pid-0 slot older than TTL, are removed on the next call and do
  not count.
- A5 `run`: `sabha-heavy run x -- sleep 1` holds the slot while it runs and frees it on exit and on `kill -TERM` of the
  wrapper.
- A6 MCP: `sabha-up.sh --print Arjun` with the flag on contains `--strict-mcp-config --mcp-config` and the aikido file;
  `--print Bhishma` contains `--strict-mcp-config` and no `--mcp-config`; `--print Vidur` and `--print Yudhishthira`
  contain neither. Live (not a unit test, needs a real session): start Arjun and run `/mcp`; only `aikido-mcp` is
  listed, GitKraken is not.
- A7 Starter: with the flag on, `sabha-up.sh --print Karna` first line is the `sabha-loop` line; `--raw` first line
  is the `claude` line; flag off prints today's two lines in today's order.
- A8 Self-test: `bin/sabha-heavy --self-test` (same pattern as `sabha-loop --self-test`) prints `self-test: all ok`.
- A9 Measure: with the Standard grid up, `ps -axo rss=,command=` summed per `claude -n <Name>` is written to the
  change's PR so the 2 GB per session guess is replaced by data; Standard's 5 sessions fit with `memory_pressure`
  level 1 and load1 under 2 x cores at idle.
- A10 shellcheck clean on every changed script (the repo's existing `# shellcheck` directives show it is used).

## 6. Flag off

`SABHA_EFFICIENCY=0` (or the line set to anything but 1): no profile is applied, `SABHA_PANES`, `SABHA_RUN_MAX` and the
roster are read exactly as today; `sabha-up.sh` prints and starts exactly today's lines, with today's `mcp` flag logic;
`sabha-run` builds today's command; `bin/sabha-heavy` still exists as a file but nothing calls it and `sabha-check`
does not mention it; the dispatcher's protocol paragraph is the only text that remains (it is guidance, not code, so
it names `sabha-heavy` only "when SABHA_EFFICIENCY is on"). `SABHA_MCP_*`, `SABHA_HEAVY_*`, `SABHA_PROFILE` and the
brief header `mcp:` are ignored. Proof: A1.

## 7. Settings summary (all in `sabha.conf`; examples in `sabha.conf.example`)

| Key | Default | Note |
| --- | --- | --- |
| `SABHA_EFFICIENCY` | `1` | the one flag |
| `SABHA_PROFILE` | `auto` | `lite`, `standard`, `full` |
| `SABHA_HEAVY_MAX` | from profile (1 / 2 / 3) | heavy jobs at once |
| `SABHA_HEAVY_LOAD_FACTOR` | `2` | wait when load1 > factor x cores (Harsh) |
| `SABHA_HEAVY_WAIT` | `900` | seconds `acquire` polls before it gives up (exit 75) [PROPOSAL] |
| `SABHA_HEAVY_TTL` | `1800` | seconds without a heartbeat before a slot is stale [PROPOSAL] |
| `SABHA_HEAVY_SETTLE` | `45` | seconds between two acquisitions [PROPOSAL] |
| `SABHA_HEAVY_FREE_PCT` | `40` | fallback only, when the pressure level cannot be read [PROPOSAL] |
| `SABHA_MCP_<Name>` | unset | `full`, `none`, or set names |
| `SABHA_MCP_FILE_<set>` | unset | path to an `--mcp-config` JSON |

## 8. Files each change would touch (named from `origin/main` at `91e5488`, or this branch where noted)

| File | Change |
| --- | --- |
| `bin/sabha-lib.sh` | `sabha_efficiency`, `sabha_profile` (reads cores and RAM), applies profile defaults inside `sabha_load`/`sabha_conf_read`, `sabha_mcp_args`; exports the profile name |
| `bin/sabha-heavy` | NEW: `check`, `acquire`, `release`, `run`, `touch`, `status`, `--self-test` |
| `bin/sabha-up.sh` | primary `--print` line is the sabha-loop line (flag on), `--raw`, "not supervised" notice, MCP args from `sabha_mcp_args` in both the print and start paths |
| `bin/sabha-run` | `role_cmd` takes MCP args from `sabha_mcp_args`; reads brief header `mcp:`; `SABHA_RUN_MAX` default from profile |
| `bin/sabha-loop` | export `SABHA_LOOP_ACTIVE=<Name>` to its child (one line); nothing else |
| `bin/sabha-check` | print profile, cores, RAM, the slot count and the gate verdict (flag on only) |
| `bin/sabha-watch` | show the `sabha-heavy status` line (flag on only) |
| `sabha.conf.example` | the section 7 keys, commented, flag uncommented |
| `docs/headless-runner.md` | MCP row of the Decisions table; point the "Concurrency" row at the profile |
| `docs/inbox-protocol.md` | optional brief header `mcp: full` |
| `docs/specs/efficiency-profiles.md` | this file, updated to "built" |
| `README.md`, `CHANGELOG.md` | one row in the table of `bin/` files; a changelog entry |
| `tests/test-profile.sh`, `tests/test-heavy.sh` | NEW (A2 to A5, A8) |
| `tests/test-grid.sh`, `tests/test-run.sh` | add flag-off and flag-on cases (A1, A6, A7) |
| `Arcus-Dev/docs/pdf-report-2.0/impl/protocol/Yudhishthira.md` (workspace, not this repo) | the dispatcher paragraph: run `sabha-heavy` before every heavy job, route Bhima's arcus work to Bhishma or a headless run, tell the relay the verdict line |
| `Arcus-Dev/.sabha/...` or the live `sabha.conf` (workspace) | `SABHA_EFFICIENCY=1`, the three panes, `SABHA_MCP_Arjun=aikido`, the `mcp` flag on Vidur, `.sabha/mcp/aikido.json` |

Not touched: `bin/sabha-for-me`, `bin/sabha-down.sh`, the Windows scripts (`sabha-up.ps1`, `sabha-up.cmd`; the gate and
profiles are macOS and Linux only, as `sabha-run` is, and Windows keeps today's behaviour with the flag effectively
off [UNVERIFIED: `sabha-up.ps1` was not read]).

## 9. Open questions

- Q-A Base. Implement on `origin/main`, not on local `main` (104 commits behind)? Default: yes; rebase this spec's
  file onto `origin/main` when the work starts.
- Q-B Roster format. This workspace's live `sabha.conf` uses the old format (`Name:model:effort:flags`, no agent
  field) and the installed plugin is 2.0.0, while `origin/main` parses `Name:agent:model:effort:flags` and accepts the
  old one ("a row without one is claude" per `sabha.conf.example`). Is the live grid started from the plugin copy or
  from `~/Work/claude-sabha`? Both need the change or only one? Not verified which one `sabha-up.sh` runs today.
- Q-C Headless count. Do the 2 headless runs of Standard count toward the "5 sessions"? This spec says no (5 is
  standing sessions; headless are short-lived and capped separately). Harsh's wording ("the rest ... headless
  sessions managed by the dispatcher") allows either.
- Q-D Telling the relay. Status-file top block plus a nudge (this spec) or a real brief to `inbox/<Relay>/` for every
  wait? A brief is heavier but durable.
- Q-E Karna's full stack. Per-brief `mcp: full` run headless (this spec), or a second Karna pane started on demand
  with the full set? The first keeps one fewer standing session; the second keeps Karna's context between tests.
- Q-F Arjun and Aikido. Is `aikido-mcp` alone the minimum for Arjun, or should Arjun not commit at all (Vidur commits and
  scans) so that Arjun gets `none`? The Aikido rule says "before every commit"; who commits decides it.
- Q-G Lite and Full numbers (3 / 5 / 8 sessions, 1 / 2 / 3 heavy jobs, the tier cut-offs). All PROPOSAL. Does Harsh
  want to set them or wait for the A9 measurement?
- Q-H Thresholds. SETTLE 45 s, TTL 1800 s, WAIT 900 s and FREE_PCT 40 are mine. Keep, or change?
- Q-I Does the plugin-contributed `aikido-mcp` load under `--strict-mcp-config`? Decides whether the named-set file is
  needed or a simpler flag works. Answered by A6 live.
- Q-J The gate runs inside the dispatcher's sandbox, where `sysctl` was denied for this agent. Is the dispatcher
  sandboxed the same way? If so the `uptime` fallback is the main path, not the fallback, and core count needs a
  sandbox-safe read.
