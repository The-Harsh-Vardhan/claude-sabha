---
description: Create sabha.conf and copy the impl template into your project
argument-hint: "[target dir]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha init:*), Bash(ls:*), Read
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Set up a project for sabha. Target given: $ARGUMENTS

1. Ask for the target directory if none was given (the project's state folder, `SABHA_IMPL`, e.g. `<project>/impl`).
2. Write the config: `sabha init [--plan pro|max5|max20] [--tracker html|xlsx|sheet] [--push ntfy|off] [--ws DIR]
   [--impl DIR] [--out FILE] [--force]`. Run it as one plain command (no pipes, no chaining):
   `${CLAUDE_PLUGIN_ROOT}/bin/sabha init --out <file> --impl <target>` plus any flag the user chose; ask for what is
   not given. Without `--out` it writes `sabha.conf` beside the scripts, which in a plugin install is the cache
   directory and is replaced on update, so always use `--out` and tell the user to set `SABHA_CONF=<file>`.
   Without `--force` the script keeps an existing file; do not add `--force` unless the user confirms.
3. Template: `ls` the target. The template is `${CLAUDE_PLUGIN_ROOT}/template/impl/` (`GOALS.md`, `PROTOCOL-core.md`,
   `for-me.items`, `protocol/`, `status/`). Copy files one at a time with Read and Write. If a destination file
   already exists, list the clashes and ask the user; overwrite nothing without an explicit yes for that file.
4. Tell the user to edit the project block of `PROTOCOL-core.md` (name, source of truth, roster) and then run
   `/sabha-doctor`.
