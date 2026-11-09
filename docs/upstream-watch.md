# The upstream move watcher (`sabha upstream`)

A repo you build on can move without a word: it is archived, renamed, loses the branch you target, reorganises its
folders, or has the upstream branch merged into yours. A local file cannot show any of that. `bin/sabha-upstream` asks
GitHub once a day and says so the first day it changes. It is read-only: every read goes through `bin/sabha-gh`
([github-layer.md](github-layer.md)), and it never edits your repos list, a clone or a remote.

## What it checks

Your repos list has one row per repo with the columns `repo`, `dir`, `base-ref` (more columns are ignored; `#` lines and
blank lines are skipped). `dir` is relative to `SABHA_UPSTREAM_ROOT`, by default the parent of the folder that holds the
list. The repo's owner and name come from the clone's `origin` URL; with no clone they come from `SABHA_UPSTREAM_ORG`.

| Finding | Read | When |
| --- | --- | --- |
| archived | `repo` | `archived` is true |
| renamed | `repo` | GitHub's `full_name` differs from the origin URL's `owner/name` |
| default branch changed | `repo` | differs from the last run |
| base branch gone | `branch` | the `base-ref` branch no longer exists |
| layout | `contents` | a path in `SABHA_UPSTREAM_PROBE_<repo>` appeared or disappeared since the last run |
| upstream merged in | `compare` | for a pair `repo:base:upstream` in `SABHA_UPSTREAM_PAIRS`: the commits of `upstream` that `base` lacks fell from more than 0 to 0 |

## What it writes

- One `for-me.items` entry per new finding (`bin/sabha-item`): owner `SABHA_USER`, title `upstream: <repo> archived`, the
  fact in `why:`.
- One brief per run to `SABHA_UPSTREAM_TO` (`bin/sabha-brief`, reply `ack`) that lists the findings and the worktrees of
  the affected clones (`git worktree list`). No receiver set: items only.
- `status/upstream/last.json` (the last facts and the findings already reported), `status/upstream/day` (the local day of
  the last finished run). Both stay under `status/`, which the kit does not track.

The first run, and the first run of a repo newly added to the list, only records facts and reports nothing. A finding is
reported once: while the cause stays the same the next runs are silent. A read that fails keeps the last known fact and
adds one warning line; a failed read never counts as a move. An account or quota stop from `sabha-gh` ends the run with
one line and changes nothing.

## Run it

`sabha upstream --conf /path/to/repos.conf` from a plain terminal (`gh` needs the network and the keychain; it fails in
the Claude sandbox). `--fresh` skips the 10-minute cache of `sabha-gh`; `--daily` runs only if no run finished today.
With `SABHA_UPSTREAM_CONF` set, `bin/sabha-watch` starts `sabha-upstream --daily` in the background on each pass and
logs to `status/upstream/watch.log`. Set `SABHA_GH_USER` so a wrong `gh` account stops the run.

The tests (`tests/test-upstream.sh`) use the fake `gh` in `tests/hermetic-bin`, so they never reach GitHub.
