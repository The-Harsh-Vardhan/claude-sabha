# claude-sabha

Run a team of named Claude Code sessions - a relay you talk to, a dispatcher and workers - that hand each other
work through plain files, keep their progress in plain files, and restart fresh before their context fills up.

Status: 0.1.0, unreleased. macOS (iTerm2) is used daily; Windows is untested ([docs/windows.md](docs/windows.md)).

## What is in it

| Path | What |
| --- | --- |
| `bin/sabha-up.sh` | Opens a herdr workspace by default (iTerm2 on macOS is the fallback: `SABHA_BACKEND=iterm`) with two 4x2 tabs, Build and Gate (roster flag `gate`), one pane per role; on-demand roles get no pane; `sabha-up.sh <Name>` starts one role; `--print <Name>` prints its restart line |
| `bin/sabha-herdr.sh`, `bin/sabha-nudge` | The herdr backend (the default on every OS) and `sabha-nudge <Name> "text"` (`herdr agent prompt --wait`) |
| `bin/sabha-run` | headless runner: one `claude -p` per due brief, for roles with no pane; `--print` shows the command ([docs/headless-runner.md](docs/headless-runner.md)) |
| `bin/sabha-watch` | read-only report: context percent per tab, restart lines above 30 percent, open items, unacked briefs |
| `bin/sabha-for-me` | renders `FOR-ME.md` and `FOR-ME.html`, the user's board, from `for-me.items` and the status files (`--watch` to refresh) |
| `docs/inbox-protocol.md` | the file formats: briefs, acks, dones, cancels, the GO token, `for-me.items`, status files |
| `docs/windows.md` | Windows setup and checks |
| `tests/test-claim.sh` | shows that a second claim of a brief number fails |
| `icons/` | one icon per role (optional: a missing one falls back to `sabha.*`), plus `sabha.*` |
| `sabha.conf.example` | the config every script reads |

## Setup

1. Requirements: Claude Code (`claude` on PATH, logged in), bash, python3 (for `sabha-for-me`), iTerm2 on macOS or
   Windows Terminal on Windows.
2. `cp sabha.conf.example sabha.conf` and set `SABHA_WS` (your workspace), `SABHA_IMPL` (the folder that holds the
   project's `PROTOCOL.md`, `status/`, `inbox/` and `for-me.items`), `SABHA_PROJECT`, `SABHA_USER` and `SABHA_ROSTER`.
   `sabha.conf` is gitignored; `SABHA_CONF` points the scripts at another file.
3. In `SABHA_IMPL`, create `inbox/<Name>/` for each role, `status/`, `status/context/` and a `PROTOCOL.md` that binds
   [docs/inbox-protocol.md](docs/inbox-protocol.md) to your project (roles, paths, rules).
4. From a plain terminal (not from inside a Claude session; its sandbox blocks osascript and wt.exe):
   `bin/sabha-up.sh`. Start the relay yourself in your editor with the line `bin/sabha-up.sh --print <relay>` prints.

The roster names are the default theme (Mahabharat); rename them in `SABHA_ROSTER` in `sabha.conf`, the one roster
source for the launchers, `sabha-watch` and the board. `status/context/<name>.txt` is written by a statusline hook of your own that saves the context percent.

## Headless roles

A role flagged `lazy` has no pane. `bin/sabha-run` starts it when a brief lands: it acks the brief, runs
`claude -p` with the role's model, effort and opening context, and the process exits once `NNN.done` and the status
file are written, so the role holds memory only while it works. Run `bin/sabha-run` after writing a brief, or set
`SABHA_RUN_AUTO=1` and let each `bin/sabha-watch` run start what is due. At most `SABHA_RUN_MAX` (2) run at once, one
per role; each is stopped after `SABHA_RUN_TIMEOUT` seconds and logged under `SABHA_IMPL/runs`. A permission prompt
is denied, never skipped: the run writes the denial to `for-me.items` and a BLOCKED done. macOS and Linux only for
now. Design: [docs/headless-runner.md](docs/headless-runner.md).

## License

MIT, see [LICENSE](LICENSE).
