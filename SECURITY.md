# Security

Sabha has three layers between a worker role and the outside world. None is enforcement on its own; together they
catch the honest mistake (the push a model emits out of habit) and make a deliberate one harder.

## 1. The guard (`hooks/sabha-guard.sh`)

A PreToolUse hook on the Bash tool. For every role except the relay it refuses a command whose first word (after env
assignments, `command`, `exec`, `sudo`, `env`, `timeout`, a path prefix, or an `&&`, `||`, `;`, `|`, `&`, `(`, `$(`,
`then`, `do` or newline) is:

- `git ... push`, `git remote add` or `git remote set-url`;
- a `gh` write: `pr create|merge|comment|edit|review|close|reopen|ready`, `issue create|comment|edit|close|reopen|delete|transfer`,
  `release create|edit|delete|upload`, `repo create|edit|delete|rename|archive|fork|sync`, `gist create|edit|delete`,
  `secret set|delete`, `workflow run`;
- `gh api` with `-X`/`--method` `POST|PUT|PATCH|DELETE`, or with `-f`, `-F`, `--field`, `--raw-field` or `--input`
  (gh sends those as a POST);
- a network client (`curl`, `wget`, `httpie`, `xh`, `python`, `node`, `deno`, `bun`, `ruby`, `perl`, `php`, `nc`,
  `pwsh`, `Invoke-WebRequest`, ...) in a command that names a chat webhook host: Slack (`hooks.slack.com`,
  `slack.com/api/`), Discord webhooks, Telegram bots, Microsoft Teams webhooks.

Quoted strings and heredoc bodies are skipped when looking for the command, so a commit message, a grep pattern or a
brief that mentions `git push` is not blocked. `sh -c '...'` and `eval '...'` are checked one quoting level deep.

## 2. The pre-push hook (`sabha-worktree push-hook <repo>`)

`bin/sabha-up.sh` exports `SABHA_ROLE` for every role it starts. `sabha-worktree push-hook <repo>` installs a git
`pre-push` hook that runs `sabha-worktree push-guard`: a push from a shell with no `SABHA_ROLE` (the human) or from
the relay goes through; a push from any other role, or from a role the roster cannot resolve, is refused. This sits
under the guard, so `bash push.sh` or an alias still meets it. It does not see a push from a tool that is not git.

## 3. No GitHub token in a worker

`bin/sabha-up.sh` unsets `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` and `GITHUB_ENTERPRISE_TOKEN` before it
starts any role but the relay. A `gh` write that slips past the guard then has no token from the environment. A login
saved by `gh auth login` (keyring) and SSH keys are still there: for a hard line, run workers as a user without them.

## The deny list (`share/claude-settings.json`)

Optional Claude Code permission rules for every session, the human's included: no `git push`, `git remote add|set-url`,
`gh pr`, `gh release create|upload|delete`, `gh repo create|edit|delete`, `gh issue create|comment`, `gh api -X` or
`--method`, recursive deletes, and no reading `.env*`, `.npmrc` or key files.

## Known gaps

A regex over command text can be stepped around by an agent that means to, and a missing `jq` or a hook timeout fails
open. Not covered:

- a script written with the Write tool and then run (`bash push.sh`), an alias, or a string built from pieces
  (`'git pu'"sh"`, `sh -c "$CMD"`); the pre-push hook still catches a git push made this way;
- `git config remote.origin.url ...` (reads of that key are common, so it is not blocked);
- `gh api` with a quoted method (`-X "POST"`), and a webhook host that is not in the list above;
- the non-claude agents started through herdr (codex, opencode, ...): they get neither `SABHA_ROLE` nor the token strip;
- anything a model does through an MCP server or a connected service.

Treat the guard as a reminder with teeth, and the human's own review of every push as the real gate.

## Reporting

Open an issue in the repository, or write a `for-me.items` entry for the relay when running a sabha.
