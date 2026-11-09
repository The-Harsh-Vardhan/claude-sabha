# sabha shipped

`sabha shipped <owner/repo#n>` answers "has this merged PR reached staging, master, the release line?" from GitHub,
read-only, through [`bin/sabha-gh`](github-layer.md).

```
sabha shipped acme/app#12
acme/app#12 merged into dev at 3f9a1c0d2e (2026-11-03)
  dev      in
  staging  in
  main     NOT IN
  v2.1     no such branch
NOT IN is by commit sha: a squash or cherry-pick promotion makes a new sha and is not detected.
```

Config: one chain per repo, `SABHA_CHAIN_<repo>="dev staging main v2.1"` in `sabha.conf` or the environment, where
`<repo>` is the name after the slash with every character that is not a letter or digit turned into `_`
(`my-app` -> `SABHA_CHAIN_my_app`). `--chain "dev staging main"` overrides it for one run. No chain: exit 2, and the
message names the key.

How: the PR's merge commit (`sabha-gh pr`) is compared against each branch (`sabha-gh compare <branch> <sha>`); the
branch holds the commit when the compare status is `behind` or `identical`. A branch that does not exist is reported
as such (`sabha-gh branch`).

Limits (v1): the check is by sha only. When a promotion squashes or cherry-picks, the branch carries the change under
another sha and reads `NOT IN`; finding it by title or number needs a commit-list read that `sabha-gh` does not have.
Chain entries are literal branch names: a pattern such as `9.4.x` is not resolved to the newest matching branch, that
needs a branch-list read.

Exit: 0 answered, 1 the PR is not merged or a read failed, 2 usage or no chain, 3 wrong GitHub account, 4 under the
quota floor, 10 answered from a stale cache. `gh` needs the network and the keychain: run it from a plain terminal.
