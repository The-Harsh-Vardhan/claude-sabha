# Changelog

## 1.0.0 - 2026-10-18

- First public release.
- Windows (Git Bash) path fix for the board and tracker.
- Skill renamed to `sabha-handoff-writing` (it clashed with the `/sabha-handoff` command).

All of it UNTESTED live until it has run inside Claude Code.

- Claude Code plugin (`.claude-plugin/`): install with `/plugin marketplace add The-Harsh-Vardhan/claude-sabha`.
- Commands: `sabha-start`, `sabha-stop`, `sabha-status`, `sabha-board`, `sabha-run`, `sabha-brief`, `sabha-handoff`,
  `sabha-restart`, `sabha-init`, `sabha-doctor`, `sabha-gate`.
- Skills: `sabha-brief-writing`, `sabha-handoff-writing`, `sabha-gate-review`, `sabha-relay`, `sabha-dispatch`.
- Hooks: SessionStart (loads handoff and open briefs), PreToolUse guard (blocks `git push`, `gh pr` and chat services
  for non-relay roles; matches at command position only, so quoted text and heredoc bodies pass; blocks when
  `SABHA_ROLE` is set but cannot be resolved), Stop (handoff reminder). `SECURITY.md`: the guard is a safety net for
  honest mistakes, not enforcement; v0.4 TODO: wider `gh` coverage, non-curl chat clients, a pre-push hook and no
  tokens for workers.
- Commands open with a `CLAUDE_PLUGIN_ROOT` fallback line (the clone directory, else ask); `plugin.json` no longer
  declares `hooks` (the default path is auto-loaded); role card for Dronacharya. `sabha doctor`: a read-only install
  dir is a warning while there is no config. `tests/test-leak.sh` allows the owner's name only in the manifests'
  author/owner `name` field.
- Docs: `ARCHITECTURE.md` (diagram, components, file bus, brief lifecycle, restart, plugin pieces); README sections
  "Install as a Claude Code plugin", "Commands, skills and hooks", "Files and owners", "Works with".
- Templates: `template/impl/ARCHITECTURE.md`, `DECISIONS.md`, `LESSONS.md`, `TODOS.md` and `template/CLAUDE.md`
  (file, owner role, when it is updated).

## 0.2.0 - not yet tagged

- W1-W2: safe-defaults deny list (`share/claude-settings.json`: no remote pushes, gh pr, recursive deletes, .env or .npmrc
  reads), `sabha init` and `sabha doctor`, `tests/test-leak.sh` (no names, paths, ids or tokens in shipped files), herdr
  backend and nudge, limits guard, plan files (`sabha.pro.conf`, `sabha.max5.conf`, `sabha.max20.conf`).
- W3: Google Sheet tracker (`sabha sheet-auth`, `sabha sheet-sync`; the dispatch says "not installed" when `bin/sabha-sheet`
  is absent), local HTML and xlsx trackers, T20 scripts, README, RULES.md, protocol core and role cards.
- W3 extras: per-role cost log `status/cost-log.tsv` (one tab-separated line per headless brief and per pane session end:
  utc, role, model, context %, event); `sabha update` (a fast-forward pull in the install dir, then the CHANGELOG head; it
  runs nothing else); `tests/test-grid.sh` uses its own fixture config, so a clean clone is green.
- herdr runs in its own named session (`SABHA_HERDR_SESSION`, default `sabha`): every call carries `--session`, the
  default session (the user's own workspaces) is never used, and `sabha-down.sh --yes` stops and deletes only that
  session. Tests are hermetic (`tests/hermetic.sh`, `SABHA_TEST=1`, `SABHA_HERDR_BIN`): none can reach a real herdr.

### Removed in 0.2.0

- `sabha-up.ps1` and the `.cmd` launchers (Windows now runs the bash scripts in Git Bash, see `docs/windows.md`).

### Headless runner

- `sabha-run`: headless runner. For each served role (default: the `lazy` ones) with a brief nobody acked, it writes
  the ack, takes `inbox/<Name>/run.lock` and starts one `claude -p` with the role's model, effort, MCP flag and
  opening context; at most `SABHA_RUN_MAX` (2) at once, stopped after `SABHA_RUN_TIMEOUT` (3600 s), one log per run
  under `SABHA_RUN_LOGS`, a BLOCKED done when a run ends without one; `--print` shows the command, `--wait` waits.
  `sabha-watch` runs a pass when `SABHA_RUN_AUTO=1`. Prompts are denied (`--permission-prompts none`), never
  skipped. Windows is not covered yet. Design: `docs/headless-runner.md`; test: `tests/test-run.sh`.
- `sabha-lib.sh`: `sabha_reads` holds the opening reads that `sabha-up.sh` and `sabha-run` share.

## 0.1.0 - unreleased

- `sabha-up.sh`: opens one window with two 4x2 tabs built from the roster, Build and Gate (flag `gate`), and refuses to
  start a role a live `claude -n <Name>` already holds (`--force` skips the check). `sabha-up.ps1` (Windows; removed in 0.2.0) built one 4x2 grid and needed a 9-role
  roster.
- `sabha-down.sh`: asks each running pane role to save, waits, kills what still holds a pane role's name and closes
  the window; dry run unless `--yes`; never touches the relay.
- Roster flag `ondemand` (`Name:model:effort:ondemand`): no grid pane, started by hand; `SABHA_PROMPT_<Name>` replaces
  a role's opening-prompt tail. Default roster adds Krishna, an on-demand tutor.
- `sabha-check`: read-only list of each role's processes, with DUPLICATE when more than one holds a name.
- `sabha-up.sh` and `sabha-up.ps1` (the latter removed in 0.2.0): open the grid of role tabs, start one role, `--print` / `-Print` a role's
  one-line restart command; paths and the project name come from `sabha.conf`; the opening prompt checks for a
  duplicate name, reads the protocol, the status file and the role's inbox.
- `sabha-watch`: read-only report of context percent, tab state, restart lines, open items and unacked briefs.
- `sabha-for-me`: renders the user's board (`FOR-ME.md`, `FOR-ME.html`) from `for-me.items` and the status files.
- `docs/inbox-protocol.md`: briefs, acks, dones, cancels, the GO token, the user's queue and status-file lines.
- `docs/windows.md`, role icons, `sabha.conf.example`.
