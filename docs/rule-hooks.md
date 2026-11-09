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
| `SABHA_SHARED_BRANCHES` | `main master dev develop staging release/*` | globs the `shared-push` rule protects; put your sprint branches here. The Claude hook: a value REPLACES the default (`SABHA_SHARED_BRANCHES="qa"` leaves `main` unprotected, so list `main` again). The pre-push hook: a value only ADDS to the default. Empty or only spaces, tabs or newlines means the default, in both hooks |
| `SABHA_ASCII_EXEMPT` | empty | path globs the `ascii` rule skips (vendored or imported files) |

## Pre-push layer (git hook)

`hooks/git-pre-push.sh` is a second check for the `shared-push` rule. The Claude hook above stays the first check (it
stops the command before it runs); this one runs inside git, after the command. Git calls a `pre-push` hook with the
remote name and url as arguments and one line per ref on stdin, `<local ref> <local sha> <remote ref> <remote sha>`, so
the hook judges the real refs of the push, not the command text: quoting, backslashes, aliases, config, `eval`, a
piped string or a command word from a variable all end in the same lines.

- Refused (exit 1, `sabha pre-push: shared-push: ...` on stderr naming the branch, the remote ref and the remote): any
  line whose remote ref is a shared branch. The list is read by `hk_rule_conf` in `hooks/lib.sh`, the one function both
  hooks use, but the pre-push hook does not trust the environment of the push: the default list (`main master dev
  develop staging release/*`) is always on, `SABHA_SHARED_BRANCHES` from the environment and from the `sabha.conf`
  beside the scripts can only ADD branches (so `SABHA_SHARED_BRANCHES=none` adds a branch called `none`), and a
  `SABHA_CONF` in the environment is ignored. A git-run hook does not get your shell's `SABHA_CONF` anyway, so put
  your sprint branches in `sabha.conf` beside the scripts, or export `SABHA_SHARED_BRANCHES` in the shell that pushes.
  The remote ref is normalised first, the prefixes `refs/heads/` and `heads/` in any letter case (`refs/Heads/Main`,
  `REFS/HEADS/MAIN` and `Heads/Main` are `main`; review 244 S1; `refs/tags/...` is not a branch and is judged by its
  full ref, so it passes): `refs/heads/main`, `heads/main` and `main` are the same branch; a delete (local sha all zeros) and
  a force (`+main`, non-fast-forward) count the same as a push. `--all` and `--mirror` are refused when they touch a
  shared ref.
- Names are compared case-folded: `Main`, `MAIN` and `Release/x` are refused too, because on a case-insensitive disk
  (APFS, a local or `file://` bare repo on this Mac) a remote ref `Main` moves `main` (probed by review 242). Cost: a
  branch really called `Main` on a case-sensitive remote (GitHub) is refused as well. `mainline` and `feat/main` pass.
  The Claude hook still compares case-sensitively.
- Passed: tags and other `refs/*` that are not `refs/heads/*`, branches not on the list, and an empty stdin.
- A line that is not four fields with 40- or 64-hex ids is refused (fail closed), as is a missing `hooks/lib.sh`. A NUL
  byte in a line is refused on bash 3.2 (the macOS `/bin/bash`, which the hook runs under); bash 4 and later drop the
  NUL and judge the rest of the line. A very long line is not refused: it is judged like any other, and git never sends
  one that could hide a shared ref.
- Cost, measured (tests/test-prepush.sh, the hook alone on a feature line, wall time, 5 runs): best 21-40 ms at low
  load; at load average 13 on 9 Nov: best 40, median 67, worst 143 ms (review 242 saw 49-128 ms at load 12). Under load
  it can pass 100 ms; the whole push takes 0.2-0.4 s. The test row asserts the best of 5 is under 100 ms and prints
  the median and worst. Bash 3.2, no new dependency.

Install it in the ONE repository that contains the path, only when you choose to (nothing global: no git config is
written, no template dir):

```bash
bin/sabha-prepush-install /path/to/repo
```

It installs where git looks for hooks, the path `git rev-parse --git-path hooks` gives: `<repo>/.git/hooks/pre-push`
(shared by the worktrees of that repository), or, when `core.hooksPath` is set, THAT directory. It prints which. The
real repositories are the second case: chitragupt sets `core.hooksPath=.githooks`, a tracked directory (the new file
would show up as untracked, with the absolute path of your clone in it: do not commit it), and guardians sets
`.husky/_`, which husky regenerates (the hook can vanish). The file is a two-line script (`#!/bin/bash -p`, then a line
that sources `hooks/git-pre-push.sh` from this clone). `-p` makes bash ignore a `BASH_ENV` in the push's environment
(proved on bash 3.2.57 with a `BASH_ENV` file holding `exit 0`: without `-p` the hook is skipped, with it the hook
runs). A second run on an installed repository says `already installed`. A different `pre-push` hook, or a stub of the
older kind (`#!/usr/bin/env bash`), is never touched: the installer says it kept that hook, that nothing was installed
or changed, and how to proceed on purpose (add a line to the existing hook that runs `hooks/git-pre-push.sh` with the
same stdin and arguments, or move the old file aside and run the installer again). When `core.hooksPath` comes from a
global or system git config (not from the repository), the directory it names is shared by every repository that uses
it: the installer prints `installed <file> -> <script>` and a `WARNING` that the hook now runs on all of their pushes
(review 244 S3). Undo: delete the file it names.

## Known gaps

A safety net for honest mistakes, as the push guard is (SECURITY.md); a session set on breaking a rule can get round it.
The hooks and their settings are not protected: a session can edit them.

Status: a best-effort guard against accidents by an agent, NOT a security boundary. Both layers are opt-in and nothing
is installed (the Claude hook is not in `hooks/hooks.json`; the pre-push hook is in a repository only after
`bin/sabha-prepush-install`). The shared-branch push rule does not rest on these hooks: it stays enforced by the other
layers (branch protection on the shared branches, and the standing rule that agents never push to them). Do not rely on
the hooks alone for it.

### Still open with both layers

Checked with the Claude hook on made-up text (rc 0 = allowed) and with real pushes to a local bare repo in
tests/test-prepush.sh ("known gap" rows):

- `git push --no-verify ...` skips the pre-push hook. The Claude hook does not flag `--no-verify`; it still denies the
  push when the refspec it reads names a shared branch, but not the text-level bypasses listed below.
- `core.hooksPath` (`git -c core.hooksPath=/x push`, `git config core.hooksPath ...`) and a removed or renamed
  `.git/hooks/pre-push` skip the hook. The Claude hook flags none of them.
- Environment of the push. Closed in round 6 (review 242 M1) for the pre-push hook: `SABHA_SHARED_BRANCHES` can only add
  to the default list, `SABHA_CONF` is ignored, and the stub runs under `bash -p`, so `BASH_ENV` does nothing (rows in
  tests/test-prepush.sh). `PATH` closed in round 8 (review 244 S2): the decision path of the pre-push hook (the
  installed stub, `hooks/git-pre-push.sh`, `hk_rule_conf` and the `cd`/`pwd` of `hooks/lib.sh`) runs bash builtins only
  and finds `lib.sh` by `${BASH_SOURCE[0]%/*}`, no `dirname`, `sed`, `cat` or `tr`; rows put a fake `dirname`, `sed`, `tr`,
  `cat`, `awk`, `cut`, `head` and `grep` first on `PATH` and the push to `main` is still refused. External commands that
  remain are not on that path: `bin/sabha-prepush-install` (run by you, not by a push) uses `dirname`, `cat`, `cut`
  and `git`, and `git` itself runs the hook. The conf beside the scripts runs in a child `"$BASH" -c` that reads
  `BASH_ENV` and sources your `sabha.conf`, so what that file calls is yours to keep clean; it can only add branches.
  Still open: anything else that changes what the hook runs. The Claude hook
  itself still takes its list from the environment (`export SABHA_SHARED_BRANCHES=none` or `SABHA_SHARED_BRANCHES=none
  git push ...` switches it off) and flags neither; only the whitespace-only list was closed there.
- An installer that follows `core.hooksPath` puts the hook where that setting points; if you later change
  `core.hooksPath`, the hook is no longer on the path (it falls under the `core.hooksPath` bullet above).
- A repository where the hook is not installed (a fresh clone, another repository), and tools that do not run git
  hooks (an IDE on JGit, go-git, libgit2).
- Server-side moves never reach a local hook: `gh api` writes on refs or merges (`gh<TAB>api ...` of review 235 MUST 4 is
  still open in the Claude hook), `gh pr merge`, `gh repo sync -b main`, the web UI.

### Closed by the pre-push layer (review 235, round 5, tip 4b632c4)

The round-5 review left 4 MUST and 3 SHOULD on the Claude hook. Its code was not changed for them. Where the
pre-push hook is installed, a push that slips past the Claude hook's text check is still refused, because git hands the
hook the real remote ref. Each case below has a real-push row in tests/test-prepush.sh that refuses the push and checks
that the remote ref did not move (and the row fails, the push lands, when the hook is not installed). The probes are
made-up text for the Claude hook's stdin; do not run them in a shell.

MUST (each one lets a push to a shared branch past the Claude hook):

1. Closed. The scanner is fed text with every backslash already deleted (`sed` at the scanner call), so it sees a
   different command than the shell. `\#` becomes a comment, and `\\` before a closing quote turns that quote into an
   escaped one. Probes: `echo \#; git push origin main` and `echo "x\\"; git push origin main; echo "y\\"`.
2. Closed. `<<` inside arithmetic is taken for a heredoc, so the next lines are scanned one at a time with fresh quotes.
   Probe: `echo $((1<<2))`, then a line `echo "a`, a line `b"; git push origin main; echo "c`, a line `d"`.
3. Closed. The current-branch exception (`$(git branch --show-current)` as the refspec) is judged against the
   directory of the push, but the shell runs the substitution in its own directory: from a main checkout that sits on
   `main`, `git -C <feature worktree> push origin "$(git branch --show-current)"` pushes `main`. The pre-push hook sees
   `refs/heads/main`.
4. Closed for git, open for gh. The Claude hook's push judge only runs when the lowercase text `push`, ` api` or
   `config-env` is in the command, so `git config remote.origin.Push HEAD:main`, `git config remote.origin.mirror
   true`, `git config Push.Default matching`, `git config alias.p x` or `git -c remote.origin.mirror=true status` is
   never judged and a later plain `git push` goes where the config says; the pre-push hook judges that later push.
   `gh<TAB>api repos/o/r/merges -f base=main -f head=x` does not go through git: still open (above).

SHOULD:

1. Closed for pushes. A command just under the 16 KB guard is not judged in time and a Claude hook timeout lets the
   call through (measured at load 41-51: 1 KB 0.24 s, 4 KB 0.82 s, 8 KB 3.68 s, 15 KB 62.7 s; quadratic). A padded
   push that gets through still meets the pre-push hook, which does not read the command. The timeout still lets the
   other rules (ascii, attribution, secret-read) through on such a command.
2. Closed. `git -c push.default=upstream -c branch.feat/x.merge=refs/heads/main push`; a pushed string piped into a
   shell (`echo "git push origin main" | bash`); only the first quoted string of an `eval` or `sh -c` is read
   (`eval "git push origin" main`); a command word from a substitution or variable (`$(which git) push origin main`,
   `G=git; $G push origin main`). All end in a `refs/heads/main` line.
3. Not closed (it is about the Claude hook itself): the current-branch path is about 2x slower (0.47-0.95 s against a
   0.5 s budget at load 50), and the 18 quote rows of tests/test-rules.sh assert only a denial, not that the rule is
   `shared-push`.

Also closed for git pushes, from the older list: a push hidden in a variable (`T=push; git $T`), a git alias, a split
string, arguments fed by `xargs`, a bare push judged by an upstream or `push.default`, a refspec or alias already in a
config file, `GIT_DIR` built at run time, and command words built at run time (`git${IFS}push`, `$(printf git)`).

Fixes the reviewer proposed for the Claude hook (not applied): hand the scanner the command with only line
continuations joined; treat `<<` as a heredoc only outside `((`; accept the current-branch form only when no `-C`,
`--git-dir`, `--work-tree` or `env -C` applies; widen the gate to a case-insensitive
`*push*|*api*|*config*|*alias*|*mirror*`; lower the size guard to about 6 KB.

### Other gaps of the Claude hook

- `ascii` and `attribution` miss text built at run time: a split string (`"Co-Author""ed-By"`), a variable
  (`T=...; -m "$T"`), `$(printf ...)`, `g=git; $g commit`, `git-commit`, a git alias for `commit`, `git merge -m`,
  `git tag -m`, `gh pr merge --body`, `gh api ... -f body=`.
- `shared-push` does not see a push hidden in a variable (`T=push; git $T`), a git alias (`alias.pushit=push`), a split
  string, or arguments fed by `xargs` from another command. A bare push is judged by the current branch, not by an
  upstream or `push.default`. The pre-push layer catches all of these where it is installed. `gh pr merge` is the
  reviewed-PR route and is left to the human's say-so; neither hook blocks it.
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
