# Rule hooks

`hooks/sabha-rules.sh` turns four working rules into a PreToolUse hook that applies to every session it is installed
for, whatever the role (the relay included). It is a file in this repository and **nothing loads it**: it is not in
`hooks/hooks.json`, so installing the plugin does not turn it on. You choose where it runs.

| Rule | Denies |
| --- | --- |
| `ascii` | Write, Edit, MultiEdit and NotebookEdit text, the command of a `git commit` or `gh pr/issue/release` write, and a shell file write (heredoc, `>`, `>>`, `tee`) that holds a non-ASCII byte; a bare `echo` is allowed |
| `attribution` | a `Co-Authored-By:` or "generated with/by <AI>" marker in a commit or PR command, or at the start of a line of file text. The workspace rule overrides a harness reminder that asks for the trailer: the denial says to retry without it |
| `shared-push` | `git push` to a shared branch (`origin main`, `HEAD:dev`, `+x:release/y`, a bare push from a checkout on one), `--all`, `--mirror`, a refspec glob that reaches one, a refspec with a shell expansion, and `gh api` writes (`-X PUT/POST/PATCH/DELETE`, or `-f/-F/--input` which imply POST) on refs, merges, branches or contents. The directory is tracked through `cd`, `pushd`, `popd`, `git -C` and `GIT_DIR`; a push whose branch cannot be told (unknown directory) is denied unless the refspec names a branch literally. `git` is found as a command word with a path prefix, options (`-c k=v`, `-C d`), subshells, `$( )`, backticks, and inside `sh -c`, `bash -c`, `eval` and `xargs` |
| `secret-read` | Read, Grep, Glob or a shell word that names a secret file (`.env`, `.env.*`, `.npmrc`, `.netrc`, `.pgpass`, `.pypirc`, `.htpasswd`, `.vault-token`, `.yarnrc.yml`, `.git-credentials`, `kubeconfig`, `credentials*`, `terraform.tfvars`, `secrets.y*ml`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.keystore`, private `id_*` keys, `.aws/`, `.ssh/config`, `.git/config`, `.docker/config.json`, `gh/hosts.yml`); and environment dumps: a bare `env`, `printenv`, `set`, `export` or `declare` with `-p`/`-x` or no name, `printenv`/`echo`/`printf` of a `$NAME` that looks like a secret (TOKEN, SECRET, PASSWORD, KEY, CREDENTIAL), `/proc/*/environ`, `gh auth token`, `gh auth status --show-token`. `*.example`, `*.sample`, `*.template` and `*.pub` are allowed. `cp` of a secret is allowed in one shape only: one source, a directory with a trailing slash (or the same file name), not under `/dev` or `/proc`, and not read later in the same command |

A denial exits 2 with `sabha-rules: <rule>: <reason>` on stderr. Setup problems (no `jq`) and input that is not a tool-call JSON (empty, truncated, not an object, a guarded tool with
a field of the wrong type) also deny, so a broken hook never lets a call through quietly. A tool the hook does not guard
passes after a good parse. A typo in `SABHA_RULES` prints one line on stderr and enforces all four.

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
The hook and its settings file are not protected: a session can edit them.

- `ascii` and `attribution` miss text built at run time: a split string (`"Co-Author""ed-By"`), a variable
  (`T=...; -m "$T"`), `$(printf ...)`, `g=git; $g commit`, `git-commit`, a git alias for `commit`, `git merge -m`,
  `git tag -m`, `gh pr merge --body`, `gh api ... -f body=`.
- `shared-push` does not see a push hidden in a variable (`T=push; git $T`), a git alias (`alias.pushit=push`), a split
  string, or arguments fed by `xargs` from another command. A bare push is judged by the current branch, not by an
  upstream or `push.default`. `gh pr merge` is the reviewed-PR route and is left to the human's say-so; the hook does
  not block it.
- `secret-read` matches names, not shell globs: `cat .e*`, `cat .[e]nv`, `find . -name '.env*' -exec cat {} +`, a split
  quote (`./.e""nv`) and `f=.en; cat ${f}v` are not seen (Grep and Glob tool globs are). A Grep over a directory does not
  know what is inside. Environment reads through `python -c`, `node -e` or `awk` with ENVIRON are not seen. A shell
  word that merely names a secret (`grep --exclude=.env`) is denied.
