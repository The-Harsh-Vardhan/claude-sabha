# The GitHub layer (`bin/sabha-gh`)

One bash file that wraps `gh api` for every kit tool that needs GitHub facts. It is read-only by construction: it
builds the `gh api` argv itself, takes only names and values (any argument that starts with `-` is refused, exit 2:
no `-X`, `--method`, `-f`, `-F`, `--input`), and the one GraphQL query lives in the file. A caller cannot pass query
text, so there is no path to a mutation. Values are checked against plain-character patterns before they reach a URL,
a search query or a GraphQL variable.

| Read | Prints (JSON) |
| --- | --- |
| `sabha-gh pr <owner/repo> <n>` | title, state, isDraft, baseRefName, headRefName, headRepository, reviewDecision, mergeable, mergeStateStatus, createdAt, updatedAt, mergedAt, mergeCommit, author |
| `sabha-gh prs-by-author <org or owner/repo> <login>` | `{total, items[]}`: the author's open PRs, the first 100 |
| `sabha-gh compare <owner/repo> <base> <head>` | `ahead_by`, `behind_by`, `status` |
| `sabha-gh repo <owner/repo>` | `full_name` (differs from the argument after a rename), `archived`, `default_branch`, `private`, `pushed_at` |
| `sabha-gh branch <owner/repo> <branch>` | `exists`, `name`, `sha`, `date` |
| `sabha-gh contents <owner/repo> <path> <ref>` | `exists`, `type`, `sha` |

`--fresh` (before the read) skips the cache.

## Behaviour

- Account: with `SABHA_GH_USER` set, `gh api user` must return that login, else exit 3 with one line (the wrong
  account gives "Could not resolve to a Repository").
- Quota: it stops (exit 4) when the core or GraphQL quota is under `SABHA_GH_MIN_LEFT` (200). The account and the
  quota are checked at most once a minute (`.preflight` in the cache directory), not once per read.
- Cache: `$SABHA_IMPL/status/gh-cache/<sha1 of the read and its argv>.json` plus a `.ts` fetch time; `SABHA_GH_CACHE`
  names another directory. A hit inside `SABHA_GH_TTL` (600 s) makes no gh call.
- Failure: when gh fails or the quota floor is hit and a cached copy exists, stdout is that copy, stderr says `STALE`
  and the exit code is 10. With no copy: exit 1 (exit 4 for the quota). `gh` needs the network and the keychain, so a
  tool run inside a Claude sandbox fails; run it from a plain terminal.
- A 404 on `branch` or `contents` is the answer `{"exists":false}`, exit 0.

Exit codes: 0 ok, 1 gh failed and no cache, 2 refused or usage, 3 wrong account, 4 under the quota floor and no cache,
10 stale copy served.

## Tests

`tests/test-gh.sh` runs against `tests/hermetic-bin/gh`, a fake that logs its argv and answers from fixture files;
`tests/hermetic.sh` puts it first on PATH and exits 2 when it is not, and `sabha-gh` refuses to run under
`SABHA_TEST=1` without `SABHA_GH_BIN`. A test never reaches GitHub.

## Tools built on it

`bin/sabha-prs` (`sabha prs`): the PR radar. Flags, worst first: ARCHIVED, CONFLICT (`mergeStateStatus` DIRTY or
`mergeable` CONFLICTING), BEHIND>50 (`compare` `behind_by`), CHANGES_REQUESTED, STALE>7d (no update for a week), else
ok. It never closes, comments or merges.
