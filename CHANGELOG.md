# Changelog

## 0.1.0 - unreleased

- `sabha-up.sh`: opens one window with two 4x2 tabs built from the roster, Build and Gate (flag `gate`), and refuses to
  start a role a live `claude -n <Name>` already holds (`--force` skips the check). `sabha-up.ps1` (Windows) still builds one 4x2 grid and needs a 9-role
  roster; it gets its own brief before the first commit or release.
- `sabha-down.sh`: asks each running pane role to save, waits, kills what still holds a pane role's name and closes
  the window; dry run unless `--yes`; never touches the relay.
- Roster flag `ondemand` (`Name:model:effort:ondemand`): no grid pane, started by hand; `SABHA_PROMPT_<Name>` replaces
  a role's opening-prompt tail. Default roster adds Krishna, an on-demand tutor.
- `sabha-check`: read-only list of each role's processes, with DUPLICATE when more than one holds a name.
- `sabha-up.sh` and `sabha-up.ps1`: open the grid of role tabs, start one role, `--print` / `-Print` a role's
  one-line restart command; paths and the project name come from `sabha.conf`; the opening prompt checks for a
  duplicate name, reads the protocol, the status file and the role's inbox.
- `sabha-watch`: read-only report of context percent, tab state, restart lines, open items and unacked briefs.
- `sabha-for-me`: renders the user's board (`FOR-ME.md`, `FOR-ME.html`) from `for-me.items` and the status files.
- `docs/inbox-protocol.md`: briefs, acks, dones, cancels, the GO token, the user's queue and status-file lines.
- `docs/windows.md`, role icons, `sabha.conf.example`.
