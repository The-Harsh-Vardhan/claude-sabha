---
description: Check whether a brief's review gate is open or shut
argument-hint: <brief file>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/sabha-gate --brief:*)
---

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`; a plugin install puts it under `~/.claude/plugins/`) in its place; if you do not know it, ask the user for the path before running anything.

Check the gate for the brief: $ARGUMENTS

Run one plain command (no pipes, no chaining):
`${CLAUDE_PLUGIN_ROOT}/bin/sabha-gate --brief <brief>`
Add `-C DIR` before `--brief` when the `gate:` paths are relative to another directory. It reads the brief's
`gate:` line (exit 2 and a message when there is none).

Exit codes: 0 = gate open, 1 = shut, 2 = usage. Explain the result using docs/inbox-protocol.md section 6:
- a `*-review.md` file needs `verdict: ACCEPT` (at least one is required);
- a critic file passes on `verdict: NO BREAK`, or on `verdict: BREAK n` / `BLOCK n` only when the builder's
  `<file minus .md>-answer.md` holds n or more lines starting `REFUTED:` or `FIXED:`;
- the last `verdict:` line in a file is current, and an answers file older than its verdict file is stale (0 answers).

When shut, name which file is missing, has no ACCEPT, or has unanswered findings. Shut means no `go:` for a fold, push,
PR, tag, release or migration. Never edit a verdict file to open the gate.
