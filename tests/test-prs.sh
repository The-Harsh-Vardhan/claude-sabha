#!/usr/bin/env bash
# bin/sabha-prs (sabha prs): the PR radar over fake gh fixtures. An archived repo flags ARCHIVED and sorts first, a
# DIRTY merge state is CONFLICT, 231 behind is BEHIND>50, then CHANGES_REQUESTED, STALE>7d, ok; an empty search prints
# "no open PRs"; a gh failure prints the cached table under a STALE header; --md and --json write what they say; no
# gh call carries a write flag. GitHub is never reached. Run: tests/test-prs.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-prs.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$FAKE_GH_DIR"
CALLS=$FAKE_GH_DIR/calls
: > "$CALLS"
LONG="a very long pull request title that goes well past sixty characters of width"
cat > "$dir/search-acme.json" <<EOF
{"total":6,"items":[
 {"repo":"acme/old","number":1350,"title":"stranded","created_at":"2026-08-01T00:00:00Z","updated_at":"2026-09-01T00:00:00Z","draft":false},
 {"repo":"acme/app","number":1231,"title":"$LONG","created_at":"2026-09-10T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false},
 {"repo":"acme/app","number":5,"title":"conflicting","created_at":"2026-11-01T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false},
 {"repo":"acme/app","number":6,"title":"needs work","created_at":"2026-10-20T00:00:00Z","updated_at":"2026-11-06T00:00:00Z","draft":false},
 {"repo":"acme/app","number":7,"title":"fine","created_at":"2026-11-05T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false},
 {"repo":"acme/app","number":8,"title":"forgotten","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-19T00:00:00Z","draft":false}]}
EOF
echo '{"total":0,"items":[]}' > "$dir/search-empty.json"
{
  echo "q=is:pr+is:open+author:me+org:acme|$dir/search-acme.json"
  echo "q=is:pr+is:open+author:me+repo:me/tool|$dir/search-empty.json"
  echo "q=is:pr+is:open+author:me+org:empty|$dir/search-empty.json"
} > "$FAKE_GH_DIR/map"
# mk <repo> <n> <review> <mergeable> <mergeState> <behind>
mk() {
  local name=${1#*/}
  printf '{"baseRefName":"dev","headRefName":"feat-%s","headRepository":{"nameWithOwner":"%s"},"reviewDecision":%s,"mergeable":"%s","mergeStateStatus":"%s"}\n' \
    "$2" "$1" "$3" "$4" "$5" > "$dir/pr-$2.json"
  echo "{\"ahead_by\":1,\"behind_by\":$6,\"status\":\"diverged\"}" > "$dir/cmp-$2.json"
  echo "name=$name -F n=$2 --jq|$dir/pr-$2.json" >> "$FAKE_GH_DIR/map"
  echo "compare/dev...feat-$2 --jq|$dir/cmp-$2.json" >> "$FAKE_GH_DIR/map"
}
mk acme/old 1350 null MERGEABLE CLEAN 0
mk acme/app 1231 null MERGEABLE BEHIND 231
mk acme/app 5 null CONFLICTING DIRTY 3
mk acme/app 6 '"CHANGES_REQUESTED"' MERGEABLE CLEAN 0
mk acme/app 7 '"APPROVED"' MERGEABLE CLEAN 0
mk acme/app 8 null MERGEABLE CLEAN 2
echo '{"full_name":"acme/old","archived":true}' > "$dir/repo-old.json"
echo '{"full_name":"acme/app","archived":false}' > "$dir/repo-app.json"
{ echo "repos/acme/old --jq|$dir/repo-old.json"; echo "repos/acme/app --jq|$dir/repo-app.json"; } >> "$FAKE_GH_DIR/map"

NOW=$(python3 -c 'import calendar; print(calendar.timegm((2026, 11, 8, 12, 0, 0)))')
export SABHA_GH_CACHE=$dir/cache SABHA_GH_USER=fake-user SABHA_NOW=$NOW SABHA_CONF=$dir/none.conf
prs() { "$BIN/sabha-prs" "$@" 2>"$dir/err"; }

echo "--- the table"
out=$(prs --org acme --repo me/tool --author me); rc=$?
flags=$(printf '%s\n' "$out" | awk 'NR > 1 { printf "%s ", $NF }')
check "worst first: ARCHIVED CONFLICT BEHIND>50 CHANGES_REQUESTED STALE>7d ok" '(( rc == 0 )) && [[ $flags == "ARCHIVED CONFLICT BEHIND>50 CHANGES_REQUESTED STALE>7d ok " ]]'
check "header names the columns" 'printf "%s\n" "$out" | head -1 | grep -Eq "^repo +# +title +base +age +review +mergeable +behind +flag$"'
check "the archived repo PR is the first row" 'printf "%s\n" "$out" | sed -n 2p | grep -q "^acme/old  *1350 "'
check "231 behind is shown" 'printf "%s\n" "$out" | grep "^acme/app  *1231 " | grep -q " 231 "'
check "a long title is cut to 60 characters with ..." 'printf "%s\n" "$out" | grep "^acme/app  *1231 " | grep -q "a very long pull request title that goes well past sixty \.\.\. "'
check "age is days since opened (1350: 99 days)" 'printf "%s\n" "$out" | grep "^acme/old" | grep -q " 99d "'
check "not stale: no STALE: header" '! printf "%s\n" "$out" | grep -q "^STALE:"'
check "no gh call carried a write flag" '! grep -Eq -- "(^| )(-X|--method|--input)( |$)|-f query=mutation" "$CALLS"'

echo "--- the same PRs through bin/sabha prs"
out2=$("$SH" "$BIN/sabha" prs --org acme --repo me/tool --author me 2>/dev/null); rc=$?
check "bin/sabha prs prints the same table" '(( rc == 0 )) && [[ $out2 == "$out" ]]'

echo "--- files and formats"
prs --org acme --author me --md "$dir/out.md" --json > "$dir/out.json"; rc=$?
check "--json prints rows; the first is ARCHIVED" '(( rc == 0 )) && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"rows\"][0][\"flag\"]==\"ARCHIVED\" and d[\"stale\"] is False and len(d[\"rows\"])==6" "$dir/out.json"'
check "--md writes a markdown table" 'grep -q "^| repo | # | title | base | age | review | mergeable | behind | flag |$" "$dir/out.md" && grep -q "^| acme/old | 1350 | stranded " "$dir/out.md"'
check "--md is ASCII" '[[ -s $dir/out.md ]] && ! LC_ALL=C grep -q "[^ -~]" "$dir/out.md"'

echo "--- empty and failures"
out=$(prs --org empty --author me); rc=$?
check "no PRs: prints 'no open PRs'" '(( rc == 0 )) && [[ $out == "no open PRs" ]]'
out=$(prs --org acme --author me >/dev/null; FAKE_GH_FAIL=1 SABHA_GH_TTL=0 prs --org acme --author me); rc=$?
check "gh down, cache warm: the table again under a STALE header" '(( rc == 0 )) && printf "%s\n" "$out" | head -1 | grep -q "^STALE:" && printf "%s\n" "$out" | grep -q "^acme/old  *1350 "'
out=$(SABHA_GH_CACHE=$dir/cold FAKE_GH_FAIL=1 prs --org acme --author me); rc=$?
check "gh down, no cache: exit 1 with one sabha prs line" '(( rc == 1 )) && [[ -z $out ]] && grep -q "^sabha prs: " "$dir/err"'
out=$(prs --org acme); rc=$?
check "no author: exit 1 says what to set" '(( rc != 0 )) && grep -q "SABHA_PRS_AUTHOR" "$dir/err"'
printf 'SABHA_PRS_ORGS="acme"\nSABHA_PRS_AUTHOR=me\n' > "$dir/c.conf"
out=$(SABHA_CONF=$dir/c.conf prs); rc=$?
check "defaults come from sabha.conf" '(( rc == 0 )) && printf "%s\n" "$out" | sed -n 2p | grep -q "^acme/old"'

echo "--- review 206"
mkdir -p "$dir/proj/.sabha/local"
printf 'SABHA_PRS_ORGS="acme"\nSABHA_PRS_AUTHOR=me\n' > "$dir/proj/.sabha/local/sabha.conf"
out=$(cd "$dir/proj" && env -u SABHA_CONF "$SH" "$BIN/sabha" prs 2>"$dir/err"); rc=$?
check "MUST 4: bin/sabha prs reads the project's .sabha/local/sabha.conf from the cwd" '(( rc == 0 )) && printf "%s\n" "$out" | sed -n 2p | grep -q "^acme/old"'

# a fork PR (head owner:branch), a PR whose details cannot be read, a head name sabha-gh refuses
echo '{"total":3,"items":[
 {"repo":"acme/app","number":9,"title":"unreadable","created_at":"2026-11-01T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false},
 {"repo":"acme/app","number":10,"title":"from a fork","created_at":"2026-11-05T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false},
 {"repo":"acme/app","number":11,"title":"odd head","created_at":"2026-11-02T00:00:00Z","updated_at":"2026-11-07T00:00:00Z","draft":false}]}' > "$dir/search-edge.json"
echo '{"baseRefName":"dev","headRefName":"feat-x","headRepository":{"nameWithOwner":"forkuser/app"},"reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}' > "$dir/pr-10.json"
echo '{"baseRefName":"dev","headRefName":"a..b","headRepository":{"nameWithOwner":"acme/app"},"reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}' > "$dir/pr-11.json"
echo '{"ahead_by":1,"behind_by":4,"status":"diverged"}' > "$dir/cmp-10.json"
{
  echo "q=is:pr+is:open+author:me+org:edge|$dir/search-edge.json"
  echo "name=app -F n=10 --jq|$dir/pr-10.json"
  echo "name=app -F n=11 --jq|$dir/pr-11.json"
  echo "compare/dev...forkuser:feat-x --jq|$dir/cmp-10.json"
} >> "$FAKE_GH_DIR/map"
: > "$CALLS"
out=$(prs --org edge --author me); rc=$?
flags=$(printf '%s\n' "$out" | awk 'NR > 1 && !/^note:/ { printf "%s ", $NF }')
check "MUST 1: a fork PR compares owner:branch; a refused head or an unreadable PR does not kill the table" '(( rc == 0 )) && grep -q "compare/dev...forkuser:feat-x --jq" "$CALLS" && printf "%s\n" "$out" | grep "^acme/app  *10 " | grep -q " 4 "'
check "MUST 3: a PR whose details are missing is UNKNOWN, never ok (9 unreadable, 11 compare refused)" '[[ $flags == "UNKNOWN UNKNOWN ok " ]] && printf "%s\n" "$out" | grep "^acme/app  *9 " | grep -q " UNKNOWN$"'
check "MUST 1: the table says why in a note" 'printf "%s\n" "$out" | grep -q "^note: .*#11"'

: > "$CALLS"
printf '5000\n10\n' > "$FAKE_GH_DIR/left.seq"
: > "$FAKE_GH_DIR/expire-preflight"
out=$(SABHA_GH_CACHE=$dir/cacheq prs --org acme --author me); rc=$?
rm -f "$FAKE_GH_DIR/left.seq" "$FAKE_GH_DIR/expire-preflight"
check "MUST 3: the quota drops after the search: exit 1, one sabha prs line naming the quota, no table" '(( rc == 1 )) && [[ -z $out ]] && grep -q "^sabha prs: .*quota" "$dir/err"'
check "MUST 3: the stop is honoured, gh was asked for the quota twice and for no PR after it" '[[ $(grep -c "^api rate_limit" "$CALLS") == 2 ]] && ! grep -q "^api graphql" "$CALLS"'

echo "---"
(( fails == 0 )) && { echo "all ok"; exit 0; }
echo "$fails failed"; exit 1
