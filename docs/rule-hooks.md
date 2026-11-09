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

Status: a best-effort guard against accidents by an agent, NOT a security boundary. It is opt-in and nothing is
installed (it is not in `hooks/hooks.json`). The shared-branch push rule does not rest on this hook: it stays enforced
by the other layers (branch protection on the shared branches, and the standing rule that agents never push to them).
Do not rely on the hook alone for it.

### Open after review 235 (round 5, tip 4b632c4)

The round-5 review (5 reviews, 4 fix rounds so far) still holds 4 MUST and 3 SHOULD. Code rounds stopped here on
purpose; these are written down instead. Every probe is made-up text for the hook's stdin (a tool-call JSON with this
command string), run by the reviewer on scratch repos. Do not run them in a shell.

MUST (each one lets a push to a shared branch through):

1. The scanner is fed text with every backslash already deleted (`sed` at the scanner call), so it sees a different
   command than the shell. `\#` becomes a comment, and `\\` before a closing quote turns that quote into an escaped one.
   Probes: `echo \#; git push origin main` and `echo "x\\"; git push origin main; echo "y\\"` are allowed.
   The first is a regression of round 4 (denied on e94f084); the second is the old quote-swallow class.
2. `<<` inside arithmetic is taken for a heredoc, so the next lines are scanned one at a time with fresh quotes.
   Probe: `echo $((1<<2))`, then a line `echo "a`, a line `b"; git push origin main; echo "c`, a line `d"`, is allowed.
3. The current-branch exception (`$(git branch --show-current)` as the refspec) is judged against the directory of the
   push, but the shell runs the substitution in its own directory. From a main checkout that sits on `main`:
   `git -C <feature worktree> push origin "$(git branch --show-current)"` is allowed and pushes `main`.
   Same for `env -C <worktree> git push origin "$(git branch --show-current)"`.
4. The push judge only runs when the lowercase text `push`, ` api` or `config-env` is in the command, so a config
   write that lacks it is never judged. Probes, each allowed as a command of its own: `git config remote.origin.Push
   HEAD:main`, `git config remote.origin.mirror true`, `git config Push.Default matching`, `git config alias.p x`,
   `git -c remote.origin.mirror=true status`. A later plain `git push` then goes where the config says. Also
   `gh<TAB>api repos/o/r/merges -f base=main -f head=x` (a tab, not a space, before `api`).

SHOULD:

1. A command just under the 16 KB guard is not judged in time, and a hook timeout lets the call through. Measured at
   load 41-51 with the 5 s timeout of the example settings: 1 KB 0.24 s, 4 KB 0.82 s, 8 KB 3.68 s, 15 KB 62.7 s (time
   is quadratic in size). Pre-existing; the checkable size is about 8 KB at load 40, not 16 KB. Adversary-only (a
   padded command).
2. More gap classes, all allowed (the first is listed above already):
   `git -c push.default=upstream -c branch.feat/x.merge=refs/heads/main push`; a pushed string piped into a shell
   (`echo "git push origin main" | bash`, `printf 'git push origin main' | sh`); only the first quoted string of an
   `eval` or `sh -c` is read (`eval "git push origin" main`, `sh -c "git push origin "main`); a command word from a
   substitution or variable (`$(which git) push origin main`, `G=git; $G push origin main`).
3. Timing and test hygiene: the current-branch path is about 2x slower (0.47-0.95 s against a 0.5 s budget at load 50),
   and the 18 quote rows assert only a denial, not that the rule is `shared-push`, so one could pass on another rule.

Fixes the reviewer proposed (not applied): hand the scanner the command with only line continuations joined; treat `<<`
as a heredoc only outside `((`; accept the current-branch form only when no `-C`, `--git-dir`, `--work-tree` or `env -C`
applies; widen the gate to a case-insensitive `*push*|*api*|*config*|*alias*|*mirror*`; lower the size guard to about 6 KB.

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
- `shared-push` and `secret-read` also miss: `xargs` fed from another command, `gh api "$URL" -X PUT` and `gh api $(echo .../merge)` (a path
  built at run time), a graphql mutation hidden in `-F query=@q.graphql` or `--input q.json`, the mutation
  `enablePullRequestAutoMerge`, `gh repo sync -b main`, and a push hidden behind a split word (`"pu""sh"`).
- A bare `export GIT_DIR=...` or `GIT_DIR=...;` makes the directory of every later push unknown until `unset GIT_DIR`;
  a push that names its own branch literally is still allowed after it. Still open (review 225 S4): the name built
  at run time (`export $'GIT_DIR'=...`, `k=GIT_DIR; export $k=...`), and an `unset GIT_DIR` that runs in a subshell or a
  pipeline, which clears the flag although the parent shell keeps the variable (`unset -f` does not clear it).
- Routes to a shared branch that the hook cannot read: a refspec or alias already in a config file (`git config` run in
  an earlier command, `.git/config` or `~/.gitconfig` edited by another tool, a pre-existing `alias.*`), and
  `git config` options other than the ones named. Denied, in any case of the key (git reads `Remote.origin.Push` as
  `remote.origin.push`): `-c` or a `git config` write of `remote.*.push`, `remote.*.pushurl`, `remote.*.mirror`,
  `alias.*`, `push.default=matching`; any `--config-env`; `GIT_CONFIG_*`. A `git config` call is a read only when the
  first word after the scope options (`--global`, `--local`, `--file x`, ...) is `--get*`, `--unset*`, `--list`/`-l` or
  `get`/`list`/`unset`, so `git config remote.origin.push HEAD:main --list` is a write. Still open:
  `-c branch.<b>.merge=` with `push.default=upstream`, and a `git config` key or value built at run time. The refspec is
  judged as git reads it: `refs/heads/x`, `heads/x` and `x` are the same branch.
- Quotes: the push judge reads the command with a left-to-right scanner (single and double quotes, `$'...'`, backslash,
  `$(`, backticks, heredocs, `#` comments), so a quoted word keeps its text (`git push "origin" "main"` is judged as
  `git push origin main`) and a quoted `;` is data. A quote or a `$(` left open is refused with the rule `shared-push`.
  A heredoc body is judged as commands whatever reads it (`bash <<EOF` runs it), so `cat <<EOF > notes.md` with a line
  `git push origin main` is denied (a false positive: write notes with the Write tool). Not modelled: a `case ... )`
  inside `$( )` (its `)` ends the substitution early), a quote inside `${ ... }`, and zsh-only quoting.
- Command words built at run time are not seen: `git${IFS}push${IFS}origin${IFS}main`, `$'git' push origin main`,
  `git $'push' origin main`, `$(printf git) push origin main`, `{git,push,origin,main}`, `git pu{s,}h origin main`,
  `gh api ... -X $'PUT'`. The same holds for the `.e""nv`-style secret names above, and for `curl -d @"$f"` (a variable in
  a quoted name).
- A command substitution anywhere in a push (remote, option value or refspec: `git push $(echo origin) HEAD:main`,
  `git push origin $(echo main)`) is denied, whatever it prints, and so are the refspecs `:`, `+:` and `+` (push every
  matching branch). One exception: a refspec that is exactly `$(git branch --show-current)` or
  `$(git rev-parse --abbrev-ref HEAD)` (quoted or not) is judged as `HEAD`, the current branch; `HEAD:$(...)` is still
  denied. `cp a $(echo /dev/null)` is also denied (a `/dev` word on a `cp` line with a substitution).
- Size: a command over 16 KB, or any word over 8 KB, is refused with the rule `size` ("split the command, or write the
  data with the Write tool"). Bash 3.2 is quadratic on long words and a hook that times out lets the call through, so the
  check runs first: inside the `jq` call for a command over 16 KB (a 1 MB command is refused in about 0.3 s, measured),
  then before every scan for a word over 8 KB. It applies when `shared-push` or `secret-read` is on; a hook run
  with a shorter timeout than the machine needs (heavy load) can still time out and let the call through. Write, Edit,
  MultiEdit and NotebookEdit text never reaches bash: `jq` counts its non-ASCII bytes and looks for a marker line, so a
  200 KB file is judged in time and `ascii` and `attribution` stay on.
- Input: two JSON documents on stdin are read as one (the first); Claude Code sends one.
- Tests: tests/test-rules.sh runs on bash 3.2 from the repository; tests/test-hooks.sh fails inside a sandbox whose write
  list excludes the working directory (a bash 3.2 here-string needs a temp file there) and passes from an archive copy or
  unsandboxed.
