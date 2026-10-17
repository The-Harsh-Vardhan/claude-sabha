# Security

## What the guard is

`hooks/sabha-guard.sh` is a PreToolUse hook on the Bash tool. For every role except the relay it refuses a command
whose first word (after env assignments, `command`, `exec`, a path prefix, or an `&&`, `||`, `;`, `|`, `(` or
newline) is `git ... push`, `gh pr create|merge|comment|edit`, or a `curl` that names `hooks.slack.com`. Quoted
strings and heredoc bodies are skipped, so a commit message, a grep pattern or a brief that mentions `git push` is
not blocked.

It is a safety net for honest mistakes: the push a model emits out of habit. It is not enforcement. A regex over
command text can be stepped around by an agent that means to (`bash push.sh`, an alias, a script written with the
Write tool, `wget` instead of `curl`, `gh api`), and a missing `jq` or a hook timeout fails open. `sh -c '...'` and
`eval '...'` are checked one quoting level deep only: `sh -c "$CMD"`, a variable, or a string built from pieces
(`'git pu'"sh"`) gets through. Treat
the guard as a reminder with teeth, and the human's own review of every push as the real gate.

## What it does not cover (v0.4 TODO)

- `gh` writes outside the four verbs: `gh api -X POST`, `gh pr review|close|ready`, `gh issue comment`,
  `gh release create`.
- Chat services reached without `curl` or on another host: `wget`, `python3 urllib`, `slack.com/api`.
- Real enforcement: a global git pre-push hook that exits 1 unless the role is the relay, and no GitHub token or
  SSH key in a worker's environment.

## Reporting

Open an issue in the repository, or write a `for-me.items` entry for the relay when running a sabha.
