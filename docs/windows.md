# Running claude-sabha on Windows

**Status: not tested on a real Windows machine.** The launcher (`bin/sabha-up.ps1`, `bin/sabha-up.cmd`) and this guide
were written on a Mac. Run the checks in "Verify it" below before relying on it.

## Prerequisites

- Windows 10 or 11 with **Windows Terminal** (`wt` on PATH; it ships with Windows 11, or install it from the Store).
- **PowerShell 7** (`pwsh`) or the built-in Windows PowerShell 5.1.
- **Claude Code installed natively** (`claude` on PATH) and logged in: run `claude` once in any terminal and sign in.
- Your workspace cloned on this machine, with its state folder (`SABHA_IMPL`, which holds `PROTOCOL.md`) inside.
- Execution policy: running `.ps1` files may be blocked. `sabha-up.cmd` avoids this (it calls PowerShell with
  `-ExecutionPolicy Bypass` for that one run). To run the `.ps1` directly, either use
  `powershell -ExecutionPolicy Bypass -File bin\sabha-up.ps1`, or allow local scripts once for your user:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## One-time setup: sabha.conf

Copy `sabha.conf.example` to `sabha.conf` beside `bin\` and set `SABHA_WS` (the workspace), `SABHA_IMPL` (its state
folder, for example `$SABHA_WS\path\to\impl`), `SABHA_PROJECT` and `SABHA_USER`. `~` and `$NAME` expand as on macOS.
`-Workspace <path>` overrides `SABHA_WS` for one run. `SABHA_CONF` (environment) points at another config file.

Launch the grid from a plain terminal, never from inside a Claude session: a session's sandbox can block `wt.exe`.

## Run the 4x2 grid

Not yet updated: the macOS launcher now opens two 4x2 tabs (Build and Gate) from a 20-role roster, but
`sabha-up.ps1` still builds one 4x2 grid and stops unless `SABHA_ROSTER` has exactly 9 roles (the relay plus 8
panes). Use a 9-role `SABHA_ROSTER` on Windows until its own brief brings it level; that brief comes before the
first commit or release of claude-sabha.

```powershell
cd path\to\claude-sabha
.\bin\sabha-up.ps1        # or: bin\sabha-up.cmd (also works from cmd or a double-click)
```

One maximised Windows Terminal window opens with eight panes: Yudhishthira, Bhishma, Bhima, Arjun on the top row;
Sahadev, Nakul, Sanjaya, Abhimanyu below. Each pane starts its role's `claude` session.

## Restart one role

claude-sabha lives wherever you cloned it (below, `C:\path\to\claude-sabha`). A pane's working directory is the
workspace, not claude-sabha, so use the full path to the launcher. In that role's pane, `/exit`, then:

```powershell
& "C:\path\to\claude-sabha\bin\sabha-up.cmd" Nakul
```

This restarts the named role in the current terminal (a fresh session, not a resume). To only see the line, run
`sabha-up.ps1 -Print Nakul`; it prints the launch command with the opening prompt and exits.

## Icons and the optional desktop shortcut

- On each grid launch the script writes a Windows Terminal profile fragment to
  `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\claude-sabha\sabha.json`. It holds the profiles "Sabha <Name>",
  each with `icons\<role>.ico` (else `icons\sabha.ico`, else none). A missing icon never stops the launch.
  If Terminal was already open during the first launch, it may show a profile error because the fragment is new; close
  and reopen Terminal once and it loads.
- Desktop shortcut: right-click the desktop, New > Shortcut, target
  `C:\Windows\System32\cmd.exe /c "C:\path\to\claude-sabha\bin\sabha-up.cmd"`, name it "Sabha". Then Properties >
  Change Icon > Browse to `claude-sabha\icons\sabha.ico`.

## Using it from WSL

`bin/sabha-up.sh` targets iTerm2 on macOS and does not work in WSL. To launch the Windows grid from a WSL shell, run
the Windows launcher through `powershell.exe`:

```bash
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w bin/sabha-up.ps1)"
```

The sessions run as Windows processes, not in WSL. The workspace path must be a Windows path: pass
`-Workspace 'C:\...'` or set `SABHA_WS` in `sabha.conf` to a Windows path.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| "running scripts is disabled on this system" | Execution policy. Use `sabha-up.cmd`, or see Prerequisites. |
| `wt` or `claude` "is not recognized" | Not on PATH. Install it, then open a new terminal. |
| Panes open but PROTOCOL.md is not found | Wrong `SABHA_IMPL` in `sabha.conf`, or wrong workspace; check both or pass `-Workspace`. |
| Panes show the default icon | Reopen Windows Terminal once; check the `Fragments\claude-sabha` file exists and `icons\*.ico` are present. |
| A pane closes at once | Run `claude` by hand in that folder to see its error (usually not logged in). |

## Verify it (on a Windows machine)

Nothing below has been run on Windows. Please check, and report what differs:

1. `wt --version`, `claude --version` and `pwsh --version` (or `$PSVersionTable.PSVersion`) all print a version.
2. `bin\sabha-up.cmd` opens one maximised window with eight panes in the 4x2 order above, each in its role's profile. (Pane titles are not guaranteed: Claude may overwrite them.)
3. Each pane shows a `claude` session whose first prompt reads PROTOCOL.md from the workspace.
4. In a pane, `& "C:\path\to\claude-sabha\bin\sabha-up.cmd" Nakul` restarts only that role.
5. `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\claude-sabha\sabha.json` exists; after reopening Terminal the
   "Sabha <Name>" profiles appear in the dropdown with their icons.
6. `-Workspace` pointing at another folder is honoured, and `SABHA_IMPL=$SABHA_WS\...` follows it (rerun, confirm the panes start there).
7. `bin\sabha-up.ps1 -Print Arjun` prints one line containing `-n Arjun` and `inbox/Arjun`.
8. The desktop shortcut launches the grid and shows the Sabha icon.
9. Optional: from WSL, the `powershell.exe` line above works.
