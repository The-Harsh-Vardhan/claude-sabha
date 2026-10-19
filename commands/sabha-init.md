---
description: Set up a project's sabha folder (~/my-claude-sabha/<name>), its sabha.conf and the my-claude-sabha link
argument-hint: "[project dir]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha init:*), Bash(ls:*), Read
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Set up a project for sabha. Project given: $ARGUMENTS

1. Ask for the project directory if none was given (`SABHA_WS`: the folder the roles start in, a repo or the folder
   that holds the project's repos). Ask for the plan (pro, max5, max20) and the tracker (html, xlsx, sheet) if not
   given, and whether the parent folder `~/my-claude-sabha` and the project name (the project folder's name,
   lowercased with dashes) are fine.
2. Run it as one plain command (no pipes, no chaining):
   `${CLAUDE_PLUGIN_ROOT}/bin/sabha init --ws <project dir> --plan <plan> --tracker <tracker>` plus `--home DIR`,
   `--name NAME`, `--theme NAME` or `--push ntfy|off` when the user chose them. It makes `<home>/<name>/` with the
   starter files and one inbox per role, writes `sabha.conf` inside it, and links it into the project as
   `my-claude-sabha` (kept out of git through `.git/info/exclude`). Existing files in the sabha folder are kept.
   Without `--force` it refuses to replace an existing `sabha.conf`; do not add `--force` unless the user confirms.
3. Report the three lines it prints (`wrote`, `sabha folder`, `link`). If the link line says skipped or failed, tell
   the user to run the scripts with `SABHA_CONF=<home>/<name>/sabha.conf`; otherwise the scripts find the config
   when run from the project folder.
4. Tell the user to edit the project block of `PROTOCOL-core.md` in the sabha folder (name, source of truth, roster)
   and then run `/sabha-doctor`.
