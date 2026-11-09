# Chain view (`bin/sabha-chain`)

Answers "what is the first thing to unblock?" for work that waits on other work. It reads the `dependsOn` field of the
board's rows and prints each blocker chain as a tree. It only reads files; with `--gh` it also reads GitHub through
[`bin/sabha-gh`](github-layer.md), which cannot write.

```
sabha-chain [--repos "OWNER/NAME ..."] [--gh] [--fresh] [--all] [--json] BOARD_DIR
```

## Input

`BOARD_DIR` is an exported board: a folder of `*.json` files. A file holds one row (an object) or a list of rows. A row
needs a string `id`; the tool reads `state`, `column`, `owner`, `ask`, `next`, `details`, `note` and `dependsOn` (a list of
ids). A file that is not JSON is skipped with a line on stderr.

A row is DONE when `state` is `DONE` or `column` is `done`.

## Output

```
2 chains from 8 rows (7 open)

Q-4 [READY, Bot]  Ship it: see acme/app#40
    PR acme/app#40  OPEN draft -> dev
    waits on Q-3 [RUNNING, Bot]  Repin the app to the snapshot
        waits on Q-2 [BLOCKED-OTHERS, Dev]  (+1 done hidden)  Cut the snapshot
            PR acme/lib#367  MERGED -> main
            waits on Q-1 [BLOCKED-ME, Pat]  Message the reviewer
    waits on Q-9 (not on board)
    unblock first: Q-1, Q-9
```

- A chain starts at an open row that waits on an open row and that no other open row waits on. It runs down `dependsOn` to
  the root blockers, which are listed on the `unblock first:` line.
- DONE blockers are hidden and counted; `--all` shows them, and shows DONE rows that have blockers.
- An id that is not on the board is marked `(not on board)`. A cycle is cut where it closes and marked.
- `--json` prints the same chains as JSON (`rows`, `chains` with nested `waitsOn`, `prs`, `notes`).

## PRs

`OWNER/NAME#N` in a row's `ask`, `next`, `details` or `note` is a PR of that row. `NAME#N` and `NAME #N` count only when
`NAME` is the repo part of an entry in `SABHA_CHAIN_REPOS` (space separated `OWNER/NAME`, from the environment or
`sabha.conf`, or `--repos`), so "PR #12" never becomes a PR of some repo.

With `--gh` each PR is read once through `bin/sabha-gh pr` and printed as `OPEN`, `OPEN draft`, `MERGED` or `CLOSED`,
then `-> <base branch>`. A read that fails prints `? (gh read failed)` and the run goes on; a wrong account or a quota under
the floor ends the run with one line; a cached copy used after a failure puts a `STALE` line on stderr. `gh` needs the
network and the keychain, so run `--gh` from a plain terminal. Which release branch a merged PR has reached is not read
here.

## Tests

`tests/test-chain.sh` (hermetic: fixtures and the fake gh in `tests/hermetic-bin`, GitHub is never reached).
