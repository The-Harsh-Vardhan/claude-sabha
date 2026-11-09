# Claude Sabha 3.0 - coupling audit (step 2 of 3)

Audit of 16 Oct 2026. Read-only. Scope: `bin/` (sabha-up.sh, .ps1, .cmd, sabha-run, sabha-lib.sh, sabha-down.sh, sabha-watch, sabha-check, sabha-for-me), `sabha.conf.example`, `tests/`, `README.md`. `.bak*` copies skipped. Effort: S = hours, M = a day or two, L = a redesign of that piece.

## Findings

| file:line | what is coupled | coupled to | effort | note |
| --- | --- | --- | --- | --- |
| bin/sabha-up.sh:130-153 | builds the grid: create window, tabs, split panes, maximise via Finder bounds | macOS osascript + iTerm2 AppleScript | L | the whole layout engine; needs a per-OS launcher (wt.exe on Windows already exists, tmux elsewhere) |
| bin/sabha-up.sh:144-151 | toggles the Toolbelt via System Events menu click (needs Accessibility) | macOS System Events + iTerm2 menu | S | cosmetic; drop or keep in the macOS launcher only |
| bin/sabha-up.sh:9 | "osascript is blocked inside a Claude sandbox" | macOS + Claude Code sandbox | S | doc/constraint, moves with the launcher |
| bin/sabha-up.sh:66-74 | badge, colours, title via OSC 1337; `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | iTerm2 escape codes; Claude Code env var | S | already guarded by `TERM_PROGRAM == iTerm*`; env var is per-agent adapter |
| bin/sabha-up.sh:59,79 | `claude -n NAME --model M --effort E [--strict-mcp-config] "PROMPT"` | Claude Code CLI flags | M | the core agent seam: name, model, effort, MCP-off, initial prompt |
| bin/sabha-up.sh:48 | opening prompt "First run ListAgents..." | Claude Code ListAgents (cross-session) | M | duplicate check depends on a Claude-only tool; ps/lock-file fallback needed for other agents |
| bin/sabha-up.ps1:73-79 | same prompt and `claude -n --model --effort` on Windows | Claude Code CLI | M | same seam as above, duplicated in PowerShell |
| bin/sabha-up.ps1:85-121 | grid via `wt.exe` panes | Windows Terminal | M | already a Windows launcher; no duplicate guard (ps-based guard is bash only) |
| bin/sabha-up.cmd | wrapper that runs the .ps1 | Windows cmd | S | portable as is |
| bin/sabha-run:33-38 | headless `claude -p -n ... --model --effort [--strict-mcp-config]` | Claude Code print mode | M | headless seam; Codex `exec`, Cursor/others differ in flags and permission model |
| bin/sabha-run:89-103 | `set -m` process group, `kill -TERM -- -pid`, 1 s watch instead of `timeout` | POSIX shells (bash) | M | fine on macOS/Linux/WSL; Windows native needs a Job Object or `Stop-Process -Id` tree kill |
| bin/sabha-run:20, sabha-down.sh:58 | `date -u +%Y-%m-%dT%H:%M:%SZ` | POSIX date | S | portable across GNU/BSD (no BSD-only flags used) |
| bin/sabha-lib.sh:82-90 | `sabha_procs` parses `ps -axo pid=,tty=,lstart=,command=` for `claude -n NAME` | BSD/GNU ps + Claude's argv | M | `-axo lstart` works on macOS and Linux; not on Windows; also matches only `claude` |
| bin/sabha-lib.sh:12-14 | role id = the `claude -n` name, status file and inbox dir | Claude session naming | S | the id itself is neutral; only "claude -n" is the coupling |
| bin/sabha-check:2,25 | lists claude processes per role; "cross-check ListAgents" | ps + Claude Code | S | reuses sabha_procs; follows that seam |
| bin/sabha-down.sh:94-104 | nudges a role by typing `see inbox/...` into the iTerm2 pane on its tty | osascript + iTerm2 | M | needs a per-launcher "send text to pane" (wt has none; tmux send-keys) |
| bin/sabha-down.sh:46 | walks ancestors with `ps -o ppid= -p` | POSIX ps | S | |
| bin/sabha-down.sh:140-174 | reads iTerm2 windows/ttys and closes windows whose panes were killed | osascript + iTerm2 | M | launcher-specific teardown |
| bin/sabha-watch:33, bin/sabha-for-me:137 | reads `status/context/<name>.txt` | a Claude Code statusline hook the user writes (README.md:36) | M | context percent exists only where the agent exposes it; other agents need their own writer or "unknown" |
| bin/sabha-for-me (python3) | board, CSV, HTML from status/inbox/for-me.items | python3 | S | portable (stdlib only seen); Windows needs python on PATH |
| sabha.conf.example:19 + sabha-lib.sh roster | model names opus/sonnet/haiku/fable and efforts low..high | Anthropic model ids, Claude effort flag | S | map per adapter (model alias table) |
| tests/test-grid.sh:15-17,44-65 | stubs `claude` and `osascript`; asserts exact claude argv | Claude CLI + osascript | S | tests follow the seams; add an adapter-argv test per agent |
| bin/*: `#!/usr/bin/env bash` | bash scripts; README notes macOS bash 3.2 limits (sabha-up.sh:66) | bash | M | runs in WSL/Git Bash; native Windows only through .ps1 |
| (convention, not code) | restart rule "fresh session, never --resume"; `.jsonl` session paths in handoffs | Claude Code sessions | S | text in protocol/status files, not parsed by bin/ (grep: no `.jsonl` or `--resume` use in bin/) |
| (convention) | SendMessage nudges between live sessions | Claude Code cross-session messaging | M | a nudge only; the file inbox carries the content, so a missing transport degrades to polling the inbox |

## (a) Already portable

- The file protocol: `inbox/<Name>/NNN-*.md`, `.claim` (set -C), `.ack`, `.done`, `.cancel`, `for-me.items`, `status/<role>.md`, `questions/`. Plain files and atomic create; vendor-neutral and OS-neutral today. SendMessage is only a nudge on top.
- `sabha.conf` roster format (Name:model:effort:flags) and the role/flag semantics (gate, lazy, ondemand, mcp).
- `sabha-for-me` (python3 board/CSV/HTML) and `sabha-watch` logic, apart from where the context percent comes from.
- `sabha_reads` (what a role reads at start) and the opening prompt text, apart from the "run ListAgents" step.
- `sabha-up.cmd` and the wt.exe layout in `sabha-up.ps1`.

## (b) Minimal seam list

Vendor-neutral core (keep in one place): roster/conf parsing, file protocol, prompt text, board, watch, run-lock and timeout policy.

Per-agent adapter (one small file each: claude, codex, cursor, antigravity, ...):
1. `start_interactive(name, model, effort, mcp_off, prompt)` -> argv (today sabha-up.sh:59/79, ps1:75/79).
2. `start_headless(name, model, effort, mcp_off, prompt)` -> argv (today sabha-run:33-38).
3. `model_alias(model, effort)` -> agent's model id / effort flag (or none).
4. `proc_match(name)` -> how to find a live process for a role (today `claude -n NAME` in ps).
5. `dup_check` text for the prompt (ListAgents for Claude; run.lock / ps fallback for others).
6. `context_source(name)` -> percent or unknown (today a Claude statusline hook).
7. Optional `nudge(name, text)` transport (SendMessage for Claude; none = rely on inbox).

Per-OS launcher (macOS iTerm2, Windows wt.exe, Linux/WSL tmux):
1. `open_grid(build[], gate[])` (sabha-up.sh:130-153 / ps1:85-121).
2. `send_text(pane, text)` (sabha-down.sh:94-104).
3. `close_panes(set)` (sabha-down.sh:140-174).
4. `list_procs()` (sabha-lib.sh:90; Get-CimInstance Win32_Process on Windows).
5. `kill_tree(pid, timeout)` (sabha-run:89-103; Job Object / taskkill /T on Windows).
6. Optional cosmetics: badge/colours/title (sabha-up.sh:66-74).
