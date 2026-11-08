# Rule hooks

`hooks/sabha-rules.sh` turns four working rules into a PreToolUse hook that applies to every session it is installed
for, whatever the role (the relay included). It is a file in this repository and **nothing loads it**: it is not in
`hooks/hooks.json`, so installing the plugin does not turn it on. You choose where it runs.

| Rule | Denies |
| --- | --- |
| `ascii` | Write, Edit and MultiEdit text, and the command of a `git commit` or `gh pr/issue/release` write, that holds a non-ASCII byte |
| `attribution` | a `Co-Authored-By:` or "generated with/by <AI>" marker in a commit or PR command, or at the start of a line of file text |
| `shared-push` | `git push` to a shared branch (`origin main`, `HEAD:dev`, `+x:release/y`, a bare push from a checkout on one), `--all`, `--mirror` |
| `secret-read` | Read, Grep, Glob or a shell word that names a secret file: `.env`, `.env.*`, `.<name>.env`, `.envrc`, `.npmrc`, `.netrc`, `.pgpass`, `.git-credentials`, `kubeconfig`, `credentials*`, `*.pem`, `*.key`, `id_rsa`-style keys, `.aws/`, `.git/config`, `.docker/config.json`. `*.example`, `*.sample`, `*.template` and a `cp` command are allowed |

A denial exits 2 with `sabha-rules: <rule>: <reason>` on stderr. Setup problems (no `jq`) also deny, so a broken hook
never lets a call through quietly.

## Turn it on

Paste `hooks/rules.settings.example.json` into a Claude Code settings file you choose (user, project or a
`--settings` file), with the absolute path to your clone. Remove the block to turn it off.

## Settings

Environment first, then `SABHA_CONF` when set (the conf runs in its own bash; only these keys are read):

| Key | Default | Meaning |
| --- | --- | --- |
| `SABHA_RULES` | `ascii attribution shared-push secret-read` | space-separated rules to enforce |
| `SABHA_SHARED_BRANCHES` | `main master dev develop staging release/*` | globs the `shared-push` rule protects; put your sprint branches here |
| `SABHA_ASCII_EXEMPT` | empty | path globs the `ascii` rule skips (vendored or imported files) |

## Known gaps

A safety net for honest mistakes, as the push guard is (SECURITY.md); a session set on breaking a rule can get round it.

- `ascii` and `attribution` look at the message of a commit or PR command and at Write/Edit text, not at a file written by
  a shell redirect or a heredoc.
- `shared-push` sees a refspec in plain words. A push built in `sh -c "$X"`, a split string or a quoted refspec with a
  space is not seen; a bare push is judged by the current branch, not by an upstream or `push.default`.
- `secret-read` matches names, not globs in the shell: `cat .e*` is not seen. A Grep over a directory does not know
  what is inside. A shell word that merely names a secret (`grep --exclude=.env`) is denied.
