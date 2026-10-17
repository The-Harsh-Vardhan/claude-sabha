---
title: Windows
nav_order: 3
---

# Running claude-sabha on Windows

**Status: not tested on a real Windows machine (beta).** The PowerShell and cmd launchers are gone: Windows uses the
same bash scripts as macOS and Linux, with herdr as the terminal backend.

- herdr has a native Windows beta (install from PowerShell: `irm https://herdr.dev/install.ps1 | iex`; Windows
  Terminal is its attach app). `herdr attach` is not available on Windows.
- The scripts need bash: use **Git Bash** (Git for Windows). Claude Code on Windows is understood to need Git for
  Windows as well; this is recalled from its docs and UNTESTED here.
- Copy `sabha.conf.example` to `sabha.conf` beside `bin/` and set `SABHA_WS` and `SABHA_IMPL` (Git Bash paths such as
  `/c/path/to/work`).
- Launch from a plain Git Bash terminal: `bin/sabha-up.sh` opens the herdr workspace; `bin/sabha-up.sh <Name>` starts
  one role; `bin/sabha-nudge <Name> "text"` wakes one.
- macOS-only pieces stay macOS-only: the `SABHA_BACKEND=iterm` fallback, and desktop notifications via osascript.
