# Architecture

How claude-sabha is put together, and why. Formats are in [docs/inbox-protocol.md](docs/inbox-protocol.md); the working
rules are in [RULES.md](RULES.md). Anything marked UNTESTED has not run on a real machine (see
[docs/known-gaps.md](docs/known-gaps.md)).

The design choice behind everything: files are the source of truth, the terminal backend only wakes a session. A
session can die, restart or be replaced and lose nothing, because its state is in a status file and its work is in an
inbox.

## Diagram

```
                      +-------+
                      | human |  answers cards, says "go", commits
                      +---+---+
                          |  chat                      ^ FOR-ME board / phone push
                          v                            |
                    +-----+-----+                      |
                    |   relay   |  talks to the human only
                    +-----+-----+
                          | brief
                          v
                  +-------+--------+
                  |   dispatcher   |  routes by difficulty, tracks acks/dones
                  +--+----+----+---+
         brief       |    |    |        brief
      +--------------+    |    +----------------+
      v                   v                     v
 +----+-----+       +-----+-----+         +-----+------+
 | builders |       | architect |         |   scribe   |
 | (copies) |       | (ondemand)|         |   runner   |
 +----+-----+       +-----+-----+         +-----+------+
      | .done             | .done               | .done
      v                   v                     v
 +----+---------------------------------------------+
 | reviewer (every .done) + critics (per lens)      |
 | verdict files -> bin/sabha-gate -> go: line      |
 +--------------------------+-----------------------+
                            |
        ====================+==========  FILE BUS  (SABHA_IMPL)  ==========
         inbox/<Name>/NNN.claim, NNN-<from>-<slug>.md, .ack, .done, .cancel
         status/<name>.md  (+ .bak/)   status/context/<name>.txt
         questions/<topic>-<lens>.md   for-me.items -> FOR-ME.md / .html
         tracker/*.csv -> html | xlsx | Google Sheet
        =====================================================================
              ^                                        ^
              | context %                              | nudge, panes
   +----------+-----------+                 +----------+-----------+
   | statusline hook      |  >=30%, handoff | herdr (default) or   |
   | -> sabha-loop        +---------------->| iTerm2 (frozen)      |
   | fresh restart        |  newer          | one pane per role    |
   +----------------------+                 +----------------------+
   roles with no pane: bin/sabha-run -> one `claude -p` per brief
```

## Components

One line per script in `bin/`.

| Script | Job |
| --- | --- |
| `sabha` | `init` (writes `sabha.conf`), `doctor`, `update`, `sheet-auth`, `sheet-sync` dispatch |
| `sabha-lib.sh` | Roster parsing and the opening reads shared by the launchers |
| `sabha-up.sh` | Opens the workspace and starts one role per pane; `--print` shows a restart line |
| `sabha-down.sh` | Asks each pane role to save, waits for the dones, stops what holds a role name; dry run without `--yes` |
| `sabha-check` | Read-only list of each role's processes, DUPLICATE when a name is held twice |
| `sabha-herdr.sh` | Sourced backend: workspaces, tabs, panes and agents in the `sabha` herdr session |
| `sabha-nudge` | Wakes one pane with a one-line pointer to a file |
| `sabha-loop` | Supervises one pane and restarts it fresh at the context limit |
| `statusline-sabha.sh` | Claude `statusLine` command: writes context % and usage windows, fires alerts |
| `sabha-limits.sh` | Sourced: usage windows, `SABHA_NOTIFY` steps, the `SABHA_STOP` line |
| `sabha-watch` | Read-only report: context, restart lines, open items, unacked briefs |
| `sabha-run` | Headless runner: one `claude -p` per brief for roles with no pane |
| `sabha-brief` | Claims the next brief number and writes the brief header |
| `sabha-gate` | The GO-token gate rule as an exit code |
| `sabha-worktree` | `<repo>--<slug>` worktrees and a guard against commits in a main checkout |
| `sabha-for-me` | Renders the board (`FOR-ME.md`, `FOR-ME.html`) and the tracker CSVs |
| `sabha-tracker` | Atomic row edits on a tracker CSV |
| `sabha-sheet` | Pushes the tracker CSVs to a Google Sheet (live calls UNTESTED) |
| `sabha-rfc-check` | Lints a Markdown RFC |

## The file bus

Write-once files under `SABHA_IMPL`, one writer each, so two sessions never edit the same file.

- `inbox/<To>/`: `NNN.claim` (number reserved), `NNN-<from>-<slug>.md` (the brief), `NNN.ack`, `NNN.done`,
  `NNN.cancel`, `run.lock`.
- `status/<name>.md`: one per role, top block only, written by that role: `Current:` line plus the handoff.
  `status/.bak/` keeps the copy taken before a full rewrite.
- `status/context/<name>.txt`, `status/limits.txt`, `status/alerts.log`, `status/cost-log.tsv`: machine-written by
  the statusline hook and the runner.
- `questions/`: reviewer and critic verdicts, and the builder's `-answer` files.
- `for-me.items`: append-only queue of what only the human can decide or run; rendered, never edited, as the board.
- `tracker/`: the one task list, mirrored to HTML, xlsx or a Google Sheet.

Why claims: two senders can pick the same number, and their brief names differ, so `noclobber` on the brief does not
stop a clash. Claiming `NNN.claim` first does.

## Lifecycle of a brief

1. The human asks the relay. The relay writes a brief to the dispatcher (`sabha-brief`) and nudges with
   `see inbox/<To>/NNN`.
2. The dispatcher splits it and writes one brief per piece into a worker's inbox, at the cheapest model that fits.
3. The worker writes `NNN.ack` first, works in a worktree, updates its status file, then writes `NNN.done`.
   `BLOCKED` and `CANCELLED` are results, not silence.
4. The reviewer reads the diff of the `.done` and writes `questions/<topic>-review.md`; critics write one verdict file
   per lens. The builder answers each finding with `REFUTED:` or `FIXED:`.
5. `sabha-gate` opens only when every named verdict is ACCEPT or NO BREAK, or every BREAK is answered.
6. The relay writes a brief carrying `go:` naming the exact target. The worker performs the irreversible step only
   after the five checks of the GO token pass; otherwise it does nothing and appends to `for-me.items`.
7. The human tests the folded change and makes the commit. No role pushes.

## Restart at 30 percent

`statusline-sabha.sh` writes each Claude session's context percent. `sabha-loop` restarts a pane when the file reads
`SABHA_LOOP_LIMIT` (30) or more and the handoff is newer than the last start. The restart is a fresh session with the
same opening prompt, which reads `PROTOCOL-core.md`, the role card and `status/<name>.md`; never `--resume`, which
would bring the full context back. A context file older than two minutes is not trusted. Two failed restarts stop the
loop. Non-Claude panes cannot report context, so they restart after each brief (when `NNN.done` appears).

## Backends

herdr is the default on every OS and runs in its own named session (`SABHA_HERDR_SESSION`), never herdr's default.
`SABHA_BACKEND=iterm` keeps the frozen macOS path. Roles flagged `lazy` get no pane and are served by `sabha-run`.
Tests never reach a real backend: `tests/hermetic.sh` puts a fake herdr first on `PATH`.

## Where the plugin pieces plug in

The plugin wraps the scripts above; it adds no second source of truth. All of it is UNTESTED live until it has run
inside Claude Code (see README, "Commands, skills and hooks").

| Piece | Plugs into | Why there |
| --- | --- | --- |
| Commands (`/sabha-start`, `-stop`, `-status`, `-board`, `-run`, `-brief`, `-handoff`, `-restart`, `-init`, `-doctor`, `-gate`) | One per script or file-bus step | A slash command is the lowest-friction way to run the right script with the right arguments |
| Skills (`sabha-brief-writing`, `sabha-handoff-writing`, `sabha-gate-review`, `sabha-relay`, `sabha-dispatch`) | The role's judgment: how to write a brief, a handoff, a verdict; what the relay and dispatcher do | Procedure that a model must follow, not a script that can enforce it |
| Hooks: SessionStart | Loads the role's handoff and open briefs | Replaces the opening prompt's reads inside a plugin-launched session |
| Hooks: PreToolUse guard | Blocks `git push`, `gh pr` and chat-service tools for non-relay roles | Enforces rule 6 mechanically instead of by instruction |
| Hooks: Stop | Reminds the role to update its handoff | Keeps the restart rule cheap: state is saved before the session ends |
