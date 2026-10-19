# Changelog

## Unreleased

- Tooltips: `tips/tips.txt` (key|surfaces|text|doc|needs) feeds the board (hover and keyboard focus on headings, columns,
  states and the question card) and the CLI (`sabha tips`, `sabha help <key>`, a rotating `Tip:` line after
  `sabha doctor` and `sabha init`). A tip whose `needs` string is absent from bin/ and hooks/ stays hidden.
- Themes v2: a theme is a skin over the role ids and never renames a role. `claude -n`, `status/<roleid>.md`,
  `inbox/<RoleId>` and the hooks key on the role id; the character name, colour and icon are display only (statusline,
  board, pane titles), and a voice reaches the opening prompt of Relay, Tutor and Coach only. The old per-theme
  persona line is gone; each role's job line stays in its role card.
- New theme file format: `key: value` header (title, author, category, fan, description, licence) and 20 rows
  `Character|DefaultRole|#colour|icon|voice`. The five shipped themes are converted (same cast, new voices).
- Presets: `~/.config/claude-sabha/presets/<name>.preset` layer your changes over a theme (`Role|theme:Character`,
  `Character.field|value`), including characters from other themes. `SABHA_THEME` names a theme or a preset.
- `bin/sabha-theme` (`resolve`, `list`, `show`, `use`, `validate`) is the one parser and validator; `/sabha-theme`
  lists and switches. Shipped themes are validated strictly; a preset's bad voice is a warning.
- Upgrading a running grid: status files and inboxes named for the old character (`status/vidur.md`) move to the role
  id (`status/relay.md`) at the grid's next full restart.
- Fix: `tests/hermetic-bin/herdr` was not executable, so every hermetic test refused to run.
- Config lookup now walks up from the cwd for `.sabha/local/sabha.conf`, so a role started in a subfolder of its
  project uses the project's own config, not a copy's. Every resolver (`sabha`, `sabha-lib`, `sabha-theme`,
  `sabha-for-me`, `sabha-sheet`, the statusline) uses the same order.
- `sabha doctor` warns (never deletes or moves) about a statusline script that has no `SABHA_CONF` lookup, a second
  claude-sabha copy whose config names another `SABHA_IMPL`, and a script run from a copy whose config belongs to
  another project.
- herdr pane map: `status/herdr-panes.txt` is emptied at grid start, keyed by role id, and pruned against
  `herdr pane list` before each nudge. Fix: `sabha_nudge` no longer exits under `set -e` when the map is missing.

## 1.0.0 - 2026-10-18

- First public release.
- One sabha folder per project, outside your repos: `sabha init --ws <project>` makes `~/my-claude-sabha/<name>`
  (`--home`, asked on a terminal; `--name`, default the project folder's name), copies the starter files, makes one
  inbox per role, writes `sabha.conf` inside it with the protocol keys, and links it into the project as
  `my-claude-sabha` (symlink; junction on Windows without Developer Mode), listed in `.git/info/exclude`. Re-running
  keeps existing files. Paths are quoted, so a space no longer breaks the config.
- Config lookup: `SABHA_CONF`, else `./my-claude-sabha/sabha.conf`, else `sabha.conf` beside the scripts; the scripts
  export it to every pane. A config in its sabha folder finds the plan file beside the scripts.
- Role ids are now plain names (Relay, Dispatcher, BuilderHeavy, ...); themes, including mahabharat, are display skins over them, and `plain` is the default.
- Themes: `SABHA_THEME` / `sabha init --theme` picks role names, colours and personas: mahabharat (default),
  avengers, hogwarts, middle-earth, plain.
- Fix: the statusline's `tr` set broke on GNU tr (Linux, Git Bash).
- Windows (Git Bash) path fix for the board and tracker.
- Skill renamed to `sabha-handoff-writing` (it clashed with the `/sabha-handoff` command).
- Security: the guard also blocks `gh` release/repo/issue/gist/secret/workflow writes, more `gh pr` verbs, `gh api`
  writes, `git remote add|set-url`, and chat webhooks reached through any common client (wget, python, node, ...).
  New `sabha-worktree push-hook` (git pre-push: only the human and the relay push); `sabha-up.sh` exports
  `SABHA_ROLE` and gives worker roles no GitHub token from the environment. Deny list widened to match.
- Role cards for all 20 roles (`template/impl/protocol/`), including the security critic (Shakuni).

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
