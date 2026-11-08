#!/usr/bin/env bash
# bin/sabha-gh, the read-only GitHub layer: each named read builds the expected gh argv, a flag or a mutation is
# refused (exit 2) before gh is called, the wrong account and a quota under the floor stop, the cache serves a hit with
# no call, refetches after the TTL, and a failed call returns the cached copy as stale (exit 10) or fails (exit 1).
# gh is the fake in tests/hermetic-bin; GitHub is never reached. Run: tests/test-gh.sh
# shellcheck disable=SC2016,SC2034,SC2329  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-gh.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$FAKE_GH_DIR"
CALLS=$FAKE_GH_DIR/calls
: > "$CALLS"
echo '{"title":"fix"}' > "$dir/pr.json"
echo '{"total":1,"items":[{"repo":"acme/app","number":7}]}' > "$dir/search.json"
echo '{"ahead_by":2,"behind_by":231,"status":"diverged"}' > "$dir/cmp.json"
echo '{"full_name":"acme/app","archived":true}' > "$dir/repo.json"
echo '{"exists":true,"name":"dev"}' > "$dir/branch.json"
echo '{"exists":true,"type":"file"}' > "$dir/contents.json"
{
  echo "-F n=7|$dir/pr.json"
  echo "q=is:pr+is:open+author:me|$dir/search.json"
  echo "compare/dev...feat/x|$dir/cmp.json"
  echo "repos/acme/app --jq|$dir/repo.json"
  echo "branches/dev --jq|$dir/branch.json"
  echo "contents/docs/a.md?ref=main|$dir/contents.json"
} > "$FAKE_GH_DIR/map"
export SABHA_GH_CACHE=$dir/cache SABHA_GH_USER=fake-user SABHA_CONF=$dir/none.conf
unset SABHA_GH_TTL SABHA_GH_MIN_LEFT
ncalls() { wc -l < "$CALLS" | tr -d ' '; }
gh_() { "$SH" "$BIN/sabha-gh" "$@" 2>"$dir/err"; }

echo "--- the named reads"
out=$(gh_ pr acme/app 7); rc=$?
check "pr: fixture out, graphql argv with owner, name, number" '(( rc == 0 )) && [[ $out == "$(cat "$dir/pr.json")" ]] && grep -q "^api graphql -f query=query.*-f owner=acme -f name=app -F n=7 --jq .data.repository.pullRequest$" "$CALLS"'
out=$(gh_ prs-by-author acme me); rc=$?
check "prs-by-author org: search query is:pr is:open author org" '(( rc == 0 )) && grep -q "^api search/issues?per_page=100&q=is:pr+is:open+author:me+org:acme --jq" "$CALLS"'
out=$(gh_ prs-by-author acme/app me); rc=$?
check "prs-by-author owner/repo: repo: qualifier" '(( rc == 0 )) && grep -q "author:me+repo:acme/app --jq" "$CALLS"'
out=$(gh_ compare acme/app dev feat/x); rc=$?
check "compare: base...head path" '(( rc == 0 )) && [[ $out == "$(cat "$dir/cmp.json")" ]] && grep -q "^api repos/acme/app/compare/dev...feat/x --jq" "$CALLS"'
out=$(gh_ repo acme/app); rc=$?
check "repo: repos/<repo>" '(( rc == 0 )) && [[ $out == "$(cat "$dir/repo.json")" ]] && grep -q "^api repos/acme/app --jq" "$CALLS"'
out=$(gh_ branch acme/app dev); rc=$?
check "branch: branches/<b>" '(( rc == 0 )) && grep -q "^api repos/acme/app/branches/dev --jq" "$CALLS"'
out=$(gh_ contents acme/app docs/a.md main); rc=$?
check "contents: path and ?ref=" '(( rc == 0 )) && grep -q "^api repos/acme/app/contents/docs/a.md?ref=main --jq" "$CALLS"'
out=$(gh_ branch acme/app gone); rc=$?
check "a 404 on branch is {exists:false}, exit 0" '(( rc == 0 )) && [[ $out == "{\"exists\":false}" ]]'
check "no call carried a method or a body flag" '! grep -Eq -- "(^| )(-X|--method|--input|-H)( |$)|-f query=mutation" "$CALLS"'

echo "--- read-only by construction"
before=$(ncalls)
gh_ -X POST pr acme/app 7 >/dev/null; rc1=$?
gh_ pr acme/app 7 -f body=x >/dev/null; rc2=$?
gh_ pr acme/app 7 --method=DELETE >/dev/null; rc3=$?
gh_ graphql 'mutation { addComment }' >/dev/null; rc4=$?
gh_ api repos/acme/app >/dev/null; rc5=$?
gh_ pr 'acme/app;id' 7 >/dev/null; rc6=$?
gh_ compare acme/app dev 'a..b' >/dev/null; rc7=$?
check "-X POST, -f, --method, a mutation, a raw api path, a bad value: all exit 2" '(( rc1 == 2 && rc2 == 2 && rc3 == 2 && rc4 == 2 && rc5 == 2 && rc6 == 2 && rc7 == 2 ))'
check "...and gh was not called for any of them" '[[ $(ncalls) == "$before" ]]'
check "the refusal says read-only" 'gh_ pr acme/app 7 -f x=1 >/dev/null; grep -q "read-only" "$dir/err"'
out=$(env -u SABHA_GH_BIN SABHA_TEST=1 "$SH" "$BIN/sabha-gh" repo acme/app 2>&1); rc=$?
check "SABHA_TEST=1 without SABHA_GH_BIN refuses (never a real gh)" '(( rc == 2 )) && [[ $out == *refusing* ]]'

echo "--- account and quota"
rm -rf "$dir/cache"; : > "$CALLS"
FAKE_GH_LOGIN=someone-else gh_ repo acme/app >/dev/null; rc=$?
check "wrong login: exit 3, one line naming both, no read call" '(( rc == 3 )) && grep -q "someone-else.*fake-user" "$dir/err" && ! grep -q "repos/acme/app" "$CALLS"'
rm -rf "$dir/cache"
FAKE_GH_LEFT=10 gh_ repo acme/app >/dev/null; rc=$?
check "quota 10 under the floor 200: exit 4, no read call" '(( rc == 4 )) && grep -q "quota" "$dir/err" && ! grep -q "repos/acme/app --jq" "$CALLS"'
rm -rf "$dir/cache"; : > "$CALLS"
out=$(FAKE_GH_LEFT=10 SABHA_GH_MIN_LEFT=5 gh_ repo acme/app); rc=$?
check "the floor is SABHA_GH_MIN_LEFT" '(( rc == 0 ))'
unset SABHA_GH_USER
rm -rf "$dir/cache"
FAKE_GH_LOGIN=anyone gh_ repo acme/app >/dev/null; rc=$?
check "SABHA_GH_USER unset: no account check" '(( rc == 0 ))'
export SABHA_GH_USER=fake-user

echo "--- cache"
rm -rf "$dir/cache"; : > "$CALLS"
gh_ compare acme/app dev feat/x >/dev/null
n1=$(ncalls)
out=$(gh_ compare acme/app dev feat/x); rc=$?
check "second read inside the TTL: same output, no new gh call" '(( rc == 0 )) && [[ $out == "$(cat "$dir/cmp.json")" ]] && [[ $(ncalls) == "$n1" ]]'
SABHA_GH_TTL=0 gh_ compare acme/app dev feat/x >/dev/null
check "TTL 0 (expired): one more read call" '[[ $(ncalls) == $((n1 + 1)) ]]'
n2=$(ncalls)
gh_ --fresh compare acme/app dev feat/x >/dev/null
check "--fresh bypasses a fresh cache" '[[ $(ncalls) == $((n2 + 1)) ]]'
out=$(FAKE_GH_FAIL=1 SABHA_GH_TTL=0 gh_ compare acme/app dev feat/x); rc=$?
check "gh fails with a cached copy: exit 10, the cached body, STALE on stderr" '(( rc == 10 )) && [[ $out == "$(cat "$dir/cmp.json")" ]] && grep -q "^sabha-gh: STALE" "$dir/err"'
out=$(FAKE_GH_FAIL=1 gh_ repo acme/other); rc=$?
check "gh fails with no cache: exit 1, says plain terminal" '(( rc == 1 )) && [[ -z $out ]] && grep -q "plain terminal" "$dir/err"'

echo "--- review 206"
{
  echo "compare/dev...forkuser:feat-x|$dir/cmp.json"
  echo "compare/dev...feat+x@y|$dir/cmp.json"
} >> "$FAKE_GH_DIR/map"
rm -rf "$dir/cache"; : > "$CALLS"
out=$(gh_ compare acme/app dev forkuser:feat-x); rc=$?
check "MUST 1: a fork head owner:branch is read" '(( rc == 0 )) && [[ $out == "$(cat "$dir/cmp.json")" ]] && grep -q "^api repos/acme/app/compare/dev...forkuser:feat-x --jq" "$CALLS"'
out=$(gh_ compare acme/app dev 'feat+x@y'); rc=$?
check "MUST 1: + and @ in a branch name are read" '(( rc == 0 )) && grep -q "^api repos/acme/app/compare/dev...feat+x@y --jq" "$CALLS"'
before=$(ncalls)
gh_ compare acme/app dev 'a:b:c' >/dev/null; rc1=$?
gh_ compare acme/app dev 'u:a..b' >/dev/null; rc2=$?
gh_ compare acme/app 'u:dev' feat/x >/dev/null; rc3=$?
gh_ compare acme/app dev ':x' >/dev/null; rc4=$?
gh_ branch acme/app 'u:dev' >/dev/null; rc5=$?
check "MUST 1: two owners, '..' after an owner, an owner on the base, an empty owner, an owner on branch: all exit 2" '(( rc1 == 2 && rc2 == 2 && rc3 == 2 && rc4 == 2 && rc5 == 2 )) && [[ $(ncalls) == "$before" ]]'
gh_ repo '../..' >/dev/null; rc1=$?
gh_ repo 'acme/..' >/dev/null; rc2=$?
gh_ branch './x' dev >/dev/null; rc3=$?
gh_ prs-by-author '../..' me >/dev/null; rc4=$?
check "SHOULD 1: a . or .. repo segment is refused, no gh call" '(( rc1 == 2 && rc2 == 2 && rc3 == 2 && rc4 == 2 )) && [[ $(ncalls) == "$before" ]]'
out=$(gh_ repo acme/.github); rc=$?
check "SHOULD 1: a real name that starts with a dot (.github) still passes the pattern" '(( rc != 2 ))'

printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_GH_MIN_LEFT=5\nSABHA_GH_TTL=0\n' "$dir" "$dir" > "$dir/g.conf"
rm -rf "$dir/cache"; : > "$CALLS"
out=$(FAKE_GH_LEFT=10 SABHA_CONF=$dir/g.conf gh_ repo acme/app); rc=$?
check "MUST 2: SABHA_GH_MIN_LEFT from the conf (quota 10, floor 5) reads" '(( rc == 0 ))'
n3=$(ncalls)
SABHA_CONF=$dir/g.conf gh_ repo acme/app >/dev/null
check "MUST 2: SABHA_GH_TTL=0 from the conf refetches" '[[ $(ncalls) == $((n3 + 1)) ]]'
rm -rf "$dir/cache"
out=$(FAKE_GH_LEFT=100 SABHA_GH_MIN_LEFT=200 SABHA_CONF=$dir/g.conf gh_ repo acme/app); rc=$?
check "MUST 2: an env SABHA_GH_MIN_LEFT wins over the conf" '(( rc == 4 ))'

rm -rf "$dir/cache"
out=$(FAKE_GH_LEFT=10 gh_ repo acme/app); rc=$?
check "SHOULD 4: the quota stop does not blame the sandbox" '(( rc == 4 )) && ! grep -q "plain terminal" "$dir/err"'

rm -rf "$dir/cache"
out=$(FAKE_GH_WARN="warning: a token is about to expire" gh_ compare acme/app dev feat/x); rc=$?
check "SHOULD 3: a gh warning on stderr is not in stdout or the cache" '(( rc == 0 )) && [[ $out == "$(cat "$dir/cmp.json")" ]] && ! grep -rq "warning" "$dir/cache"'
rm -rf "$dir/cache"
(umask 022; gh_ repo acme/app >/dev/null)
mode_of() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
check "SHOULD 2: the cache dir is 0o700 and its files 0o600 even under umask 022" '[[ $(mode_of "$dir/cache") == 0o700 && $(mode_of "$(ls "$dir"/cache/*.json | head -1)") == 0o600 ]]'

echo "---"
(( fails == 0 )) && { echo "all ok"; exit 0; }
echo "$fails failed"; exit 1
