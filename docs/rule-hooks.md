# Rule hooks

`hooks/sabha-rules.sh` turns four working rules into a PreToolUse hook that applies to every session it is installed
for, whatever the role (the relay included). It is a file in this repository and **nothing loads it**: it is not in
`hooks/hooks.json`, so installing the plugin does not turn it on. You choose where it runs.

| Rule | Denies |
| --- | --- |
| `ascii` | Write, Edit, MultiEdit and NotebookEdit text, the command of a `git commit` or `gh pr/issue/release` write, and a shell file write (heredoc, `>`, `>>`, `tee`) that holds a non-ASCII byte; a bare `echo` is allowed |
| `attribution` | a `Co-Authored-By:` or "generated with/by <AI>" marker in a commit or PR command, or at the start of a line of file text. The workspace rule overrides a harness reminder that asks for the trailer: the denial says to retry without it |
| `shared-push` | `git push` to a shared branch (`origin main`, `HEAD:dev`, `+x:release/y`, a bare push from a checkout on one), `--all`, `--mirror` (and the abbreviations git accepts: `--al`, `--m`, `--mi`, `--mir`, ...), a refspec glob that reaches one, a refspec with a shell expansion or a brace (`{main,x}`), and `gh api` writes (`-X PUT/POST/PATCH/DELETE`, or `-f/-F/--input` which imply POST) on refs, merges, branches or contents. The directory is tracked through `cd`, `pushd`, `popd`, `git -C`, `env -C`, and `GIT_DIR` / `GIT_WORK_TREE` (inline, `export`, `declare` or a bare assignment); line continuations and backslash escapes (`g\it`, `pu\sh`) are removed first; a push whose branch cannot be told (unknown directory) is denied unless the refspec names a branch literally. `git` is found as a command word with a path prefix, options (`-c k=v`, `-C d`), subshells, `$( )`, backticks, and inside `sh -c` (also `/bin/bash -c`, `bash --norc -c`, `bash -O opt -c`, `bash <<< "..."`), `eval`, `env -S` and `xargs` |
| `secret-read` | Read, Grep, Glob or a shell word that names a secret file (`.env`, `.env.*`, `.npmrc`, `.netrc`, `.pgpass`, `.pypirc`, `.htpasswd`, `.vault-token`, `.yarnrc.yml`, `.git-credentials`, `kubeconfig`, `credentials*`, `terraform.tfvars`, `secrets.y*ml`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.keystore`, private `id_*` keys, `.aws/`, `.ssh/config`, `.git/config`, `.docker/config.json`, `gh/hosts.yml`); and environment dumps: a bare `env`, `printenv`, `set`, `export` or `declare` with `-p`/`-x` or no name, `printenv`/`echo`/`printf` of a `$NAME` that looks like a secret (TOKEN, SECRET, PASSWORD, KEY, CREDENTIAL), `declare -p NAME` of a secret name, the same inside `bash -c`, `sh -c`, `eval` and `env`, `/proc/*/environ`, `gh auth token`, `gh auth status --show-token`. A file named behind `@` (`curl -d @.env`, `-F f=@.env`) is an upload of a secret and is denied. `*.example`, `*.sample`, `*.template` and `*.pub` are allowed. `cp` of a secret is allowed in one shape only: one source, a directory with a trailing slash (or the same file name), not under `/dev` or `/proc`, and not read later in the same command |

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
- `secret-read` matches names, not shell globs or built-up words. Not seen (all checked by review 222 and still open):
  `cat .e*`, `cat .en?`, `cat .[e]nv`, `find . -name '.env*' -exec cat {} +`, `rg -g '.env*'`, a split quote
  (`cat .e""nv`, `cat ".e"nv`), a variable splice (`f=.en; cat ${f}v`), `$'\x2eenv'`, `$(printf '.e%s' nv)`, and reads
  of a whole directory (`grep -r`, `rg`, `tar`, `rsync -a .`). Grep and Glob tool globs are checked, shell globs are not
  (`glob_secret` on shell words is the follow-up). Environment reads through `python -c`, `node -e` or `awk` with ENVIRON
  are not seen, nor `ps eww`, `ps auxe` (they print process environments) or a heredoc whose body holds `$NPM_TOKEN`.
  Names the lists miss: `~/.claude/.credentials.json`, `~/.kube/config`, `.yarnrc`, `.dockercfg`, `secrets.json`,
  `.secrets`, `.token`, `service-account.json`, `prod.env`, `.m2/settings.xml`, `.s3cfg`, `.my.cnf`; variable names
  `$PASS`, `$GITHUB_PAT`, `$AUTH`, `$CREDS`, `$JWT`, `$DATABASE_URL`. A shell word that merely names a secret
  (`grep --exclude=.env`) is denied, as are `$PRIMARY_KEY` and `$PUBLIC_KEY` (the `_KEY` rule). A `cp` whose arguments
  hold a substitution is denied when a secret or a `/dev` or `/proc` path is on the line, so `cp <secret> "$(pwd)/"` is
  refused: name the destination literally.
- `shared-push` and `secret-read` also miss: `xargs` fed from another command, a heredoc to a shell (`bash <<EOF`; the
  one-line here-string `bash <<< "..."` is unwrapped), `gh api "$URL" -X PUT` and `gh api $(echo .../merge)` (a path
  built at run time), a graphql mutation hidden in `-F query=@q.graphql` or `--input q.json`, the mutation
  `enablePullRequestAutoMerge`, `gh repo sync -b main`, and a push hidden behind a split word (`"pu""sh"`).
- A bare `export GIT_DIR=...` or `GIT_DIR=...;` makes the directory of every later push unknown until `unset GIT_DIR`;
  a push that names its own branch literally is still allowed after it.
- Size: a command over 16 KB, or any word over 8 KB, is refused with the rule `size` ("split the command, or write the
  data with the Write tool"). Bash 3.2 is quadratic on long words and a hook that times out lets the call through, so the
  hook fails closed instead. It applies when `shared-push` or `secret-read` is on.
- Input: two JSON documents on stdin are read as one (the first); Claude Code sends one.
- Tests: tests/test-rules.sh runs on bash 3.2 from the repository; tests/test-hooks.sh fails inside a sandbox whose write
  list excludes the working directory (a bash 3.2 here-string needs a temp file there) and passes from an archive copy or
  unsandboxed.
