---
title: Known gaps
nav_order: 6
---

# Known gaps

What is untested or limited in this release, why, and what to run to confirm it. Nothing here blocks the local
workflow; each item says what a teammate must run to turn "untested" into "tested". Windows is beta until a teammate has
run it.

## Untested

| Gap | Why | Confirm it by |
| --- | --- | --- |
| herdr: `agent start`, `agent prompt`, `agent wait`, `agent read`, `send-keys` and `pane split` (flags, JSON keys, spelling) | Checked against a fake herdr only (tests never touch a real one). A real-herdr smoke test (herdr 0.9.4, a throwaway session) covered the named-session server start and the `status: running` line, `workspace create`, `workspace list`, `pane list`, `agent list`, `workspace close` and `session stop` / `delete`; those are no longer untested | In a throwaway `SABHA_HERDR_SESSION` (never your working one): `bin/sabha-up.sh --plan pro`, then `bin/sabha-nudge <Name> "say hi"`; record what differs from `bin/sabha-herdr.sh`, then `bin/sabha-down.sh --yes` |
| herdr extras: `sabha-alert` (`agent wait --until blocked`, `agent read --source visible`, `notification show`), the sidebar `pane report-metadata` calls (display name, brief and ctx tokens, `--ttl-ms`), and session restore after `integration install claude` | Fake herdr only; the exit status of `agent wait`, whether `HERDR_PANE_ID` reaches the statusline hook, whether `--display-agent` survives an agent restart, and what a restored pane runs are from help text and docs, not observed; also unobserved: `agent rename` on a pane id, `agent focus` from a key binding, `agent explain` output, and whether `notification show --sound` obeys `[ui.sound.agents]` | In a throwaway `SABHA_HERDR_SESSION`: block a pane on a prompt with `bin/sabha-alert` running; watch the sidebar; after installing the integration, restart that session's server and see what the pane runs |
| `bin/sabha-sheet` live Google OAuth and Sheets calls | Only `--dry-run` runs without a Google account | `bin/sabha sheet-auth` once, then `bin/sabha sheet-sync --dry-run` and `bin/sabha sheet-sync` against a copy of the sheet |
| `sabha doctor` seat detection | Reads the text of `claude auth status`, which differs between Claude Code versions | Run `bin/sabha doctor` on a Pro/Max login and on a Team seat; override with `SABHA_DOCTOR_SEAT=Team` if the text is not recognised |
| Windows | 23 of 24 tests pass in Git Bash; `tests/test-procs.sh` S3 cannot make a folder unwritable on NTFS (`chmod` has no effect) | Follow `docs/windows.md` and `docs/quickstart.md`; report each step that fails |
| Quickstart steps 4-7 | They are chat steps that need a real Claude session; the mechanical equivalents (scripts, fake herdr, fake agents) are run | Follow `docs/quickstart.md` in a plain terminal with a real login |
| Remote Control, ntfy delivery, `SABHA_SHEET_AGENT_SYNC` | Depend on account policy, a phone and a Sheet respectively | Each is labelled UNTESTED where the README describes it; set it up and report |

## Limits (by design for now)

- The critic file naming: any verdict file named `*-review.md` is read as the reviewer's and needs `verdict: ACCEPT`;
  name critic files by lens (`-sec.md`, `-be.md`), never `-review.md`.
- `bin/sabha-worktree` hook uses `git --path-format`, which needs git 2.31 or later, and has no fallback.
- `bin/sabha-brief` reads the body from stdin only when stdin is a pipe or a file. A socket stdin (some tool
  runners) is skipped: pass `--body FILE`.
- `bin/sabha-down.sh` has no Linux or Windows fallback for closing windows: the iTerm2/osascript steps are macOS-only
  (the process kill and the herdr session stop are portable).
- `sabha-gate` decides "newer" by the last `verdict:` line in a file and by file mtime for answers; it does not read
  git history.

## Residual risks in the test suite

- One check calls herdr by absolute path style (`herdr` resolved from `PATH`): tests rely on `tests/hermetic.sh`
  putting a fake first and on the guard in `bin/sabha-herdr.sh` (`SABHA_TEST=1` plus `SABHA_HERDR_BIN`). A script that
  calls a herdr by absolute path would bypass both.
- The iTerm/osascript backend (`SABHA_BACKEND=iterm`) is frozen and covered only against osascript stubs.
