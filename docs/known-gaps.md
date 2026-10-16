# Known gaps

What is untested or limited in this release, why, and what to run to confirm it. Nothing here blocks the local
workflow; each item says what a teammate must run to turn "untested" into "tested". Windows is beta until a teammate has
run it.

## Untested

| Gap | Why | Confirm it by |
| --- | --- | --- |
| herdr: the JSON keys read from `workspace create`, `tab create` and `pane split`, and the spelling of `agent start`, `agent prompt`, `agent read` and `agent send-keys` | Written from `herdr --skill` and checked against a fake herdr only (tests never touch a real one). Status: pending 4a-real (the real-herdr smoke test is not recorded yet) | On a machine with herdr, in a throwaway herdr session (not your working one): `bin/sabha-up.sh --plan pro`, then `bin/sabha-nudge <Name> "say hi"`; record what differs from `bin/sabha-herdr.sh` |
| `bin/sabha-sheet` live Google OAuth and Sheets calls | Only `--dry-run` runs without a Google account | `bin/sabha sheet-auth` once, then `bin/sabha sheet-sync --dry-run` and `bin/sabha sheet-sync` against a copy of the sheet |
| `sabha doctor` seat detection | Reads the text of `claude auth status`, which differs between Claude Code versions | Run `bin/sabha doctor` on a Pro/Max login and on a Team seat; override with `SABHA_DOCTOR_SEAT=Team` if the text is not recognised |
| Windows | No Windows run and no Windows machine here; Git Bash being enough is not verified | Follow `docs/windows.md` and `docs/quickstart.md`; report each step that fails |
| Quickstart steps 4-7 | They are chat steps that need a real Claude session; the mechanical equivalents (scripts, fake herdr, fake agents) are run | Follow `docs/quickstart.md` in a plain terminal with a real login |
| Remote Control, ntfy delivery, `SABHA_SHEET_AGENT_SYNC` | Depend on account policy, a phone and a Sheet respectively | Each is labelled UNTESTED where the README describes it; set it up and report |

## Limits (by design for now)

- The critic file naming: any verdict file named `*-review.md` is read as the reviewer's and needs `verdict: ACCEPT`;
  name critic files by lens (`-sec.md`, `-be.md`), never `-review.md`.
- `bin/sabha-worktree` hook uses `git --path-format`, which needs git 2.31 or later, and has no fallback.
- `bin/sabha-brief` reads the body from stdin only when stdin is a pipe or a file. A socket stdin (some tool
  runners) is skipped: pass `--body FILE`.
- `sabha-gate` decides "newer" by the last `verdict:` line in a file and by file mtime for answers; it does not read
  git history.

## Residual risks in the test suite

- One check calls herdr by absolute path style (`herdr` resolved from `PATH`): tests rely on `tests/hermetic.sh`
  putting a fake first and on the guard in `bin/sabha-herdr.sh` (`SABHA_TEST=1` plus `SABHA_HERDR_BIN`). A script that
  calls a herdr by absolute path would bypass both.
- The iTerm/osascript backend (`SABHA_BACKEND=iterm`) is frozen and covered only against osascript stubs.
