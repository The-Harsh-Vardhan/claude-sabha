#!/usr/bin/env bash
# bin/sabha-shipped (sabha shipped) over fake gh fixtures: a merge commit that is an ancestor of a branch (compare
# status behind or identical) reads "in", ahead or diverged "NOT IN", a missing branch "no such branch"; a repo without
# a chain exits 2 and names the conf key; an open PR exits 1; the chain comes from sabha.conf, the environment or
# --chain; a gh failure with a cached answer prints it under STALE and exits 10; no gh call carries a write flag.
# GitHub is never reached. Run: tests/test-shipped.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-shipped.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$FAKE_GH_DIR"
CALLS=$FAKE_GH_DIR/calls
SHA=3f9a1c0d2e5b7a8c9d0e1f2a3b4c5d6e7f8a9b0c
export SABHA_GH_CACHE=$dir/cache
echo "SABHA_CHAIN_my_app=\"dev staging main ghost\"" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
run() { SABHA_GH_TTL=${TTL:-600} python3 "$BIN/sabha-shipped" "$@" > "$dir/out" 2> "$dir/err"; echo $? > "$dir/rc"; if [[ -n ${DEBUG:-} ]]; then cat "$dir/out" "$dir/err"; cat "$FAKE_GH_DIR/calls"; fi; }
rc() { cat "$dir/rc"; }

# PR 12 merged into dev; PR 13 still open
echo "{\"state\":\"MERGED\",\"baseRefName\":\"dev\",\"mergedAt\":\"2026-11-03T10:00:00Z\",\"mergeCommit\":{\"oid\":\"$SHA\"}}" > "$dir/pr12.json"
echo '{"state":"OPEN","baseRefName":"dev","mergedAt":null,"mergeCommit":null}' > "$dir/pr13.json"
branch() { echo "{\"exists\":true,\"name\":\"$1\",\"sha\":\"abc\",\"date\":\"2026-11-04T00:00:00Z\"}" > "$dir/b-$1.json"; echo "branches/$1 --jq|$dir/b-$1.json" >> "$FAKE_GH_DIR/map"; }
cmp_() { echo "{\"ahead_by\":1,\"behind_by\":1,\"status\":\"$2\"}" > "$dir/c-$1.json"; echo "compare/$1...$SHA --jq|$dir/c-$1.json" >> "$FAKE_GH_DIR/map"; }
{
  echo "name=my-app -F n=12 --jq|$dir/pr12.json"
  echo "name=my-app -F n=13 --jq|$dir/pr13.json"
} > "$FAKE_GH_DIR/map"
branch dev; cmp_ dev identical
branch staging; cmp_ staging behind
branch main; cmp_ main ahead

run acme/my-app#12
check "direct merge: dev and staging in, main NOT IN, ghost has no branch, exit 0" \
  '[[ $(rc) == 0 ]] && grep -q "^  dev  *in$" "$dir/out" && grep -q "^  staging  *in$" "$dir/out" && grep -q "^  main  *NOT IN$" "$dir/out" && grep -q "^  ghost  *no such branch$" "$dir/out"'
check "the header names the base, the short sha and the merge date" 'grep -q "acme/my-app#12 merged into dev at 3f9a1c0d2e (2026-11-03)" "$dir/out"'
check "a NOT IN adds the squash caveat" 'grep -q "squash or cherry-pick" "$dir/out"'

cmp_ main diverged
run --fresh acme/my-app#12
check "diverged is NOT IN too" 'grep -q "^  main  *NOT IN$" "$dir/out"'
cmp_ main behind
run --fresh acme/my-app#12
check "all in: no caveat line" '! grep -q "squash" "$dir/out" && grep -q "^  main  *in$" "$dir/out"'

run acme/other#1
check "no chain for the repo: exit 2, the conf key named" '[[ $(rc) == 2 ]] && grep -q "SABHA_CHAIN_other" "$dir/err"'
run acme/my-app#13
check "an open PR: exit 1 and says not merged" '[[ $(rc) == 1 ]] && grep -q "not merged (state OPEN)" "$dir/out"'
run acme/my-app
check "no PR number: exit 2 with usage" '[[ $(rc) == 2 ]] && grep -q "usage: sabha shipped" "$dir/err"'
run --method acme/my-app#12
check "a flag is refused: exit 2" '[[ $(rc) == 2 ]]'

SABHA_CHAIN_other="dev" run acme/other#1
check "the chain also comes from the environment (and then fails on the unmapped PR, not on the chain)" '! grep -q "no chain" "$dir/err"'
run --chain "dev" --fresh acme/my-app#12
check "--chain overrides the conf" '[[ $(rc) == 0 ]] && grep -q "^  dev  *in$" "$dir/out" && ! grep -q staging "$dir/out"'

TTL=0 FAKE_GH_FAIL=1 run acme/my-app#12
check "gh down with a cached answer: STALE header, exit 10" '[[ $(rc) == 10 ]] && grep -q "^STALE:" "$dir/out"'
rm -rf "$dir/cache"
TTL=0 FAKE_GH_FAIL=1 run acme/my-app#12
check "gh down and no cache: exit 1, one line" '[[ $(rc) == 1 ]] && [[ $(wc -l < "$dir/err") -le 2 ]]'
FAKE_GH_LOGIN=someone-else SABHA_GH_USER=someuser TTL=0 run --fresh acme/my-app#12
check "wrong account: exit 3" '[[ $(rc) == 3 ]]'

check "no gh call carried a write flag" '! grep -E -- " -X|--method|--input|mutation" "$CALLS" >/dev/null'
check "the fake gh answered every call (the real one was never reached)" '[[ -s $CALLS ]]'

if (( fails == 0 )); then echo "all ok"; else echo "$fails failed"; exit 1; fi
