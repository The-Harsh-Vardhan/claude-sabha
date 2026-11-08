#!/usr/bin/env bash
# bin/sabha-upstream, the upstream move watcher: run 1 records a baseline and reports nothing; each later finding
# (archived, renamed, branch gone, layout path gone, upstream merged in) writes one for-me.items entry and one brief that
# names the clone's worktrees; the same facts again report nothing; a failed read never reads as a move; an account stop
# changes nothing; --daily runs once per local day. gh is the fake in tests/hermetic-bin; GitHub is never reached.
# Run: tests/test-upstream.sh
# shellcheck disable=SC2016,SC2034,SC2329  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-upstream.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

# two clones (one with a second worktree) and the repos list that sits in <ws>/dev beside them
ws=$dir/ws
mkdir -p "$ws/dev" "$ws/backend/app" "$ws/backend/lib" "$dir/impl"
for r in app lib; do
  git -C "$ws/backend/$r" init -q 2>/dev/null
  git -C "$ws/backend/$r" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
done
git -C "$ws/backend/app" remote add origin https://github.com/acme/app.git
git -C "$ws/backend/lib" remote add origin git@github.com:acme/lib.git
git -C "$ws/backend/app" worktree add -q -b feat-x "$dir/app-feat-x" 2>/dev/null
cat > "$ws/dev/repos.conf" <<'EOF'
# repo  dir  base-ref  products  kind
app   backend/app   main   x   commits
lib   backend/lib   dev    x   none
EOF

FD=$FAKE_GH_DIR
mkdir -p "$FD"
CALLS=$FD/calls
: > "$CALLS"
fx() { printf '%s\n' "$2" > "$dir/fx-$1.json"; }
fx app-repo '{"full_name":"acme/app","archived":false,"default_branch":"main"}'
fx app-branch '{"exists":true,"name":"main"}'
fx app-probe '{"exists":true,"type":"dir"}'
fx app-cmp '{"ahead_by":0,"behind_by":3,"status":"behind"}'
fx lib-repo '{"full_name":"acme/lib","archived":false,"default_branch":"dev"}'
fx lib-branch '{"exists":true,"name":"dev"}'
fx new-repo '{"full_name":"acme/new","archived":true,"default_branch":"main"}'
fx new-branch '{"exists":true,"name":"main"}'
MAP_ALL=(
  "repos/acme/app --jq|$dir/fx-app-repo.json"
  "repos/acme/app/branches/main --jq|$dir/fx-app-branch.json"
  "repos/acme/app/contents/apps/?ref=main|$dir/fx-app-probe.json"
  "repos/acme/app/compare/dev...rel|$dir/fx-app-cmp.json"
  "repos/acme/lib --jq|$dir/fx-lib-repo.json"
  "repos/acme/lib/branches/dev --jq|$dir/fx-lib-branch.json"
  "repos/acme/new --jq|$dir/fx-new-repo.json"
  "repos/acme/new/branches/main --jq|$dir/fx-new-branch.json"
)
printf '%s\n' "${MAP_ALL[@]}" > "$FD/map"

export SABHA_IMPL=$dir/impl SABHA_CONF=$dir/none.conf SABHA_GH_CACHE=$dir/cache SABHA_GH_USER=fake-user SABHA_GH_TTL=0
export SABHA_UPSTREAM_PROBE_app="apps/" SABHA_UPSTREAM_PAIRS="app:rel:dev" SABHA_UPSTREAM_TO=Boss SABHA_USER=Pat
export SABHA_NOW=1762000000
ITEMS=$SABHA_IMPL/for-me.items
LAST=$SABHA_IMPL/status/upstream/last.json
nitems() { grep -c '^id: ' "$ITEMS" 2>/dev/null || true; }
nbriefs() { find "$SABHA_IMPL/inbox/Boss" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
ncalls() { wc -l < "$CALLS" | tr -d ' '; }
up() { "$BIN/sabha-upstream" --conf "$ws/dev/repos.conf" "$@" >"$dir/out" 2>"$dir/err"; }

echo "--- baseline"
up; rc=$?
check "run 1 exits 0 and says the baseline was recorded" '(( rc == 0 )) && grep -q "baseline recorded" "$dir/out"'
check "run 1 writes no item and no brief" '[[ ! -e $ITEMS && $(nbriefs) == 0 ]]'
check "run 1 records the facts of both repos" 'grep -q "\"app\"" "$LAST" && grep -q "\"lib\"" "$LAST" && grep -q "\"apps/\": true" "$LAST"'
check "the clone origin gives the owner and name (https and scp forms)" 'grep -q "repos/acme/app " "$CALLS" && grep -q "repos/acme/lib " "$CALLS"'

echo "--- archived"
fx app-repo '{"full_name":"acme/app","archived":true,"default_branch":"main"}'
up; rc=$?
check "archived: one item, one brief" '(( rc == 0 )) && [[ $(nitems) == 1 && $(nbriefs) == 1 ]]'
check "the item is owned by the user, titled and explained" 'grep -q "^owner: Pat$" "$ITEMS" && grep -q "^title: upstream: app archived$" "$ITEMS" && grep -q "^why: acme/app is archived" "$ITEMS"'
b=$(ls "$SABHA_IMPL"/inbox/Boss/*.md)
check "the brief is addressed, from the watcher, and names the worktrees of the clone" 'grep -q "^to: Boss$" "$b" && grep -q "^from: upstream-watch$" "$b" && grep -q "app-feat-x (feat-x)" "$b" && grep -q "ws/backend/app (" "$b"'
check "the brief says nothing was changed" 'grep -q "Nothing was changed" "$b"'

echo "--- same facts"
up; rc=$?
check "same facts: no new item, no new brief" '(( rc == 0 )) && [[ $(nitems) == 1 && $(nbriefs) == 1 ]] && grep -q "0 new finding" "$dir/out"'

echo "--- renamed"
fx app-repo '{"full_name":"acme/app2","archived":true,"default_branch":"main"}'
up; rc=$?
check "renamed: an item naming the old and the new name" '(( rc == 0 )) && [[ $(nitems) == 2 ]] && grep -q "^title: upstream: acme/app renamed to acme/app2$" "$ITEMS" && [[ $(nbriefs) == 2 ]]'

echo "--- default branch, branch gone, layout, reverse merge"
fx app-repo '{"full_name":"acme/app2","archived":true,"default_branch":"trunk"}'
up
check "default branch changed: an item" '[[ $(nitems) == 3 ]] && grep -q "^title: upstream: app default branch is now trunk$" "$ITEMS"'
grep -v 'branches/main' "$FD/map" > "$FD/map.t" && mv "$FD/map.t" "$FD/map"
up
check "base branch gone (a 404 is an answer): an item" '[[ $(nitems) == 4 ]] && grep -q "^title: upstream: app base branch main is gone$" "$ITEMS"'
grep -v 'contents/apps' "$FD/map" > "$FD/map.t" && mv "$FD/map.t" "$FD/map"
up
check "probe path disappeared: an item" '[[ $(nitems) == 5 ]] && grep -q "^title: upstream: app layout: apps/ disappeared on main$" "$ITEMS"'
fx app-cmp '{"ahead_by":0,"behind_by":0,"status":"identical"}'
up
check "upstream merged in (behind_by 3 -> 0): an item" '[[ $(nitems) == 6 ]] && grep -q "^title: upstream: dev merged into rel in app$" "$ITEMS"'
up
check "all the same again: nothing new" '[[ $(nitems) == 6 ]]'

echo "--- a repo newly listed is a baseline of its own"
echo "new   backend/new   main   x   none" >> "$ws/dev/repos.conf"
SABHA_UPSTREAM_ORG=acme up; rc=$?
check "new repo, already archived: recorded, no item" '(( rc == 0 )) && [[ $(nitems) == 6 ]] && grep -q "\"new\"" "$LAST"'
SABHA_UPSTREAM_ORG=acme up
check "and silent on the run after" '[[ $(nitems) == 6 ]]'

echo "--- a failed read is not a move"
cp "$LAST" "$dir/last.before"
SABHA_GH_CACHE=$dir/cache-empty FAKE_GH_FAIL=1 up; rc=$?
check "gh down, no cache: exit 0, no item, one warning line" '(( rc == 0 )) && [[ $(nitems) == 6 ]] && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "read(s) failed, last known facts kept" "$dir/err"'
check "the last facts are kept as they were" 'cmp -s "$LAST" "$dir/last.before" || { diff "$LAST" "$dir/last.before"; false; }'
SABHA_GH_TTL=999999 FAKE_GH_FAIL=1 up; rc=$?
check "gh down, cache valid: still no item" '(( rc == 0 )) && [[ $(nitems) == 6 ]]'

echo "--- account stop"
SABHA_GH_CACHE=$dir/cache-other FAKE_GH_LOGIN=someone-else up; rc=$?
check "wrong account: exit 3, one line, nothing changed" '(( rc == 3 )) && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "stopped, nothing recorded" "$dir/err" && cmp -s "$LAST" "$dir/last.before" && [[ $(nitems) == 6 ]]'

echo "--- once a day"
up
c0=$(ncalls)
up --daily; rc=$?
check "--daily after a run today: no call" '(( rc == 0 )) && [[ $(ncalls) == "$c0" ]]'
SABHA_NOW=$((SABHA_NOW + 86400)) up --daily; rc=$?
check "--daily the next local day: runs" '(( rc == 0 )) && [[ $(ncalls) -gt $c0 ]]'

echo "--- read-only and usage"
check "every gh call is an api read: no write flag, no mutation" '! grep -v "^api " "$CALLS" | grep -q . && ! grep -Eq -- "-X|--method|--input|mutation|POST" "$CALLS"'
check "no repos list: exit 2 with a message" '"$BIN/sabha-upstream" >"$dir/out" 2>"$dir/err"; (( $? == 2 )) && grep -q "no repos list" "$dir/err"'
check "the repos list and the clones are untouched" '[[ $(grep -c . "$ws/dev/repos.conf") == 4 ]] && [[ -z $(git -C "$ws/backend/app" status --porcelain) ]]'
check "bin/sabha-gh is the shared copy, byte for byte" '[[ $(shasum -a 256 "$BIN/sabha-gh" | cut -d" " -f1) == 006ab5885b32730cd3e4709ac5cb7f7d93e8e455813a9cb75c41e31ac1e3d9a0 ]]'

echo "--- sabha-watch starts it once a day, only when SABHA_UPSTREAM_CONF is set"
wdir=$dir/watch
mkdir -p "$wdir/inbox/Dispatcher" "$wdir/status"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus"\n' "$wdir" "$wdir" > "$wdir/sabha.conf"
wlog=$wdir/status/upstream/watch.log
watch_run() { SABHA_CONF=$wdir/sabha.conf SABHA_IMPL=$wdir SABHA_NOTIFY_DESKTOP=0 "$@" bash "$BIN/sabha-watch" >/dev/null 2>&1; }
wait_for() { local i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.2; done; return 1; }
c1=$(ncalls)
watch_run env; sleep 1
check "no SABHA_UPSTREAM_CONF: sabha-watch makes no gh call" '[[ $(ncalls) == "$c1" && ! -e $wlog ]]'
watch_run env SABHA_UPSTREAM_CONF="$ws/dev/repos.conf" SABHA_UPSTREAM_ORG=acme
check "with it: the watcher runs in the background and finishes" 'wait_for "grep -q \"repo(s) checked\" \"\$wlog\" 2>/dev/null"'
check "its state sits in the watch's own impl dir" '[[ -s $wdir/status/upstream/last.json ]]'
c2=$(ncalls)
watch_run env SABHA_UPSTREAM_CONF="$ws/dev/repos.conf" SABHA_UPSTREAM_ORG=acme; sleep 2
check "a second pass the same day makes no call" '[[ $(ncalls) == "$c2" ]]'

echo
if (( fails )); then echo "FAILED: $fails"; exit 1; fi
echo "all passed"
