# Security

Sabha has four layers between a worker role and the outside world. None is enforcement on its own; together they
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

## 4. The permission relay (`hooks/sabha-permission.sh`, `bin/sabha-perm`)

Workers run in a mode that asks (`SABHA_PERMISSION_MODE`, default `default`) with a short allow list, so a risky
tool call becomes a permission prompt. A `PermissionRequest` hook writes it to
`<IMPL>/inbox/<relay>/permissions/<Role>-NNN.req` with the tool input byte for byte, nudges the relay, and waits for
the user's answer as a decision file ([inbox protocol, section 9](docs/inbox-protocol.md)). Fail safe: an error, a
missing role, or no answer within `SABHA_RELAY_WAIT` gives no decision, and the ordinary prompt shows in the pane;
the hook never allows on its own. The relay's own prompts are never relayed. No "always allow" is ever passed on.

`bin/sabha-perm snippet` prints the Claude Code settings for it (`defaultMode` and the allow list from
`SABHA_PERMISSION_MODE` and `SABHA_PERMISSION_ALLOW` in your `sabha.conf`; the shipped list is only the default, so
each user picks their own). Sabha never edits a settings file: you paste the snippet into yours. The default list
covers the relay's routine work (reads, writes under `SABHA_IMPL`, `sabha-perm`) and read-only git and shell commands;
its `deny` part keeps the Edit and Write tools out of the permissions folder, so decision files come from
`sabha-perm` only. The deny list below and the guard still win over any allow.

What the nonce stops: a stale or copied decision (replay), a decision meant for another request (mis-pairing), and
two requests of one role racing. Each request gets 128 random bits, and a decision counts only with the same nonce.

What it does not stop (same-account limit): workers and the relay run as the same OS user, so a worker can read the
nonce in the `.req` and write its own `.allow` (with Bash), or run `sabha-perm allow` with `SABHA_ROLE` unset (the
check there refuses a worker that runs it by mistake, not one that means to). This is detection, not prevention:
`sabha-perm audit` lists every honoured decision that has no row in the relay's `relay.tsv` (a file written by hand),
and `log.tsv` keeps role, id, tool, input hash and the user's words for each outcome. A forge through `sabha-perm`
itself leaves a `relay.tsv` row too, so only the relay's chat shows it was never asked. For a hard line, run
workers as a second OS user that cannot write the permissions folder.

Also not covered: a timeout above 600 s and a killed hook giving the pane prompt rather than a denial are documented
but UNVERIFIED by a live run; prompts the hook never sees (a sandboxed
command's network request, protected paths) stay in the pane.

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
