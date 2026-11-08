#!/usr/bin/env bash
# bin/sabha-upstream, the upstream move watcher: run 1 records a baseline of the change detectors but reports a state
# that is bad in itself (archived, renamed, default branch is not the base); each later finding (archived, renamed,
# branch gone, layout path gone, upstream merged in) writes one for-me.items entry and one brief that names the clone's
# worktrees; the same facts again report nothing; a failed or 404 read never reads as a move and never overwrites a
# stored fact; an account stop changes nothing; two overlapping runs write one item; a conf value with $HOME is
# expanded; --daily runs once per local day. gh is the fake in tests/hermetic-bin; GitHub is never reached.
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
echo "repos/acme/new/branches/main --jq|$dir/fx-new-branch.json" >> "$FD/map"
SABHA_UPSTREAM_ORG=acme up; rc=$?
check "new repo, already archived: recorded and reported at once (a state, not an event)" '(( rc == 0 )) && [[ $(nitems) == 7 ]] && grep -q "\"new\"" "$LAST" && grep -q "^title: upstream: new archived$" "$ITEMS"'
SABHA_UPSTREAM_ORG=acme up
check "and not reported again on the run after" '[[ $(nitems) == 7 ]]'

echo "--- a failed read is not a move"
cp "$LAST" "$dir/last.before"
SABHA_GH_CACHE=$dir/cache-empty FAKE_GH_FAIL=1 up; rc=$?
check "gh down, no cache: exit 0, no item, one warning line" '(( rc == 0 )) && [[ $(nitems) == 7 ]] && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "read(s) failed, last known facts kept" "$dir/err"'
check "the last facts are kept as they were" 'cmp -s "$LAST" "$dir/last.before" || { diff "$LAST" "$dir/last.before"; false; }'
SABHA_GH_TTL=999999 FAKE_GH_FAIL=1 up; rc=$?
check "gh down, cache valid: still no item" '(( rc == 0 )) && [[ $(nitems) == 7 ]]'

echo "--- account stop"
SABHA_GH_CACHE=$dir/cache-other FAKE_GH_LOGIN=someone-else up; rc=$?
check "wrong account: exit 3, one line, nothing changed" '(( rc == 3 )) && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "stopped, nothing recorded" "$dir/err" && cmp -s "$LAST" "$dir/last.before" && [[ $(nitems) == 7 ]]'

echo "--- once a day"
up
c0=$(ncalls)
up --daily; rc=$?
check "--daily after a run today: no call" '(( rc == 0 )) && [[ $(ncalls) == "$c0" ]]'
SABHA_NOW=$((SABHA_NOW + 86400)) up --daily; rc=$?
check "--daily the next local day: runs" '(( rc == 0 )) && [[ $(ncalls) -gt $c0 ]]'

echo "--- first run: a state that is bad in itself is reported, the change detectors only record"
up2() { "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" "$@" >"$dir/out" 2>"$dir/err"; }
reset_fx() {
  fx app-repo '{"full_name":"acme/app","archived":false,"default_branch":"main"}'
  fx app-branch '{"exists":true,"name":"main"}'
  printf '%s\n' "${MAP_ALL[@]}" > "$FD/map"
}
echo "app   backend/app   main   x   commits" > "$ws/dev/repos2.conf"
export SABHA_UPSTREAM_PROBE_app='' SABHA_UPSTREAM_PAIRS=''
i3=$dir/impl3
reset_fx; fx app-repo '{"full_name":"acme/app","archived":true,"default_branch":"trunk"}'
SABHA_IMPL=$i3 up2; rc=$?
check "archived and on another default branch from the very first run: both reported" '(( rc == 0 )) && [[ $(grep -c "^id: " "$i3/for-me.items") == 2 ]] && grep -q "^title: upstream: app archived$" "$i3/for-me.items" && grep -q "^title: upstream: app default branch is trunk, the configured base is main$" "$i3/for-me.items"'
SABHA_IMPL=$i3 up2
check "and reported once, not on every run" '[[ $(grep -c "^id: " "$i3/for-me.items") == 2 ]] && grep -q "0 new finding" "$dir/out"'
reset_fx; fx app-repo '{"full_name":"acme/app2","archived":false,"default_branch":"main"}'
SABHA_IMPL=$dir/impl3b up2
check "renamed away from the configured name on the first run: reported" 'grep -q "^title: upstream: acme/app renamed to acme/app2$" "$dir/impl3b/for-me.items"'
reset_fx; grep -v 'branches/main' "$FD/map" > "$FD/map.t" && mv "$FD/map.t" "$FD/map"
SABHA_IMPL=$dir/impl3c up2
check "base branch missing on the first run (repo read fine): reported" 'grep -q "^title: upstream: app base branch main is gone$" "$dir/impl3c/for-me.items"'

echo "--- a 404 or a failed read never overwrites a stored fact"
i4=$dir/impl4
reset_fx
SABHA_GH_CACHE=$dir/cache4 SABHA_IMPL=$i4 up2
check "baseline recorded, branch_exists true" '[[ ! -e $i4/for-me.items ]] && grep -q "\"branch_exists\": true" "$i4/status/upstream/last.json"'
cp "$i4/status/upstream/last.json" "$dir/last4.before"
cp -R "$i4" "$dir/impl4n"; cp -R "$i4" "$dir/impl4t"
grep -v -e 'repos/acme/app --jq' -e 'branches/main' "$FD/map" > "$FD/map.t" && mv "$FD/map.t" "$FD/map"
SABHA_GH_CACHE=$dir/cache4 SABHA_IMPL=$i4 up2; rc=$?
check "repo and branch both 404, repo only from a stale cache: one check-by-hand item, branch fact kept" '(( rc == 0 )) && [[ $(grep -c "^id: " "$i4/for-me.items") == 1 ]] && grep -q "^title: upstream: acme/app not found or renamed: check by hand$" "$i4/for-me.items" && ! grep -q "is gone" "$i4/for-me.items" && grep -q "\"branch_exists\": true" "$i4/status/upstream/last.json" && grep -q "could not read" "$dir/err"'
check "the stale-cache 404 keeps every stored fact" 'python3 -c "import json,sys; a,b=[json.load(open(f))[\"repos\"] for f in sys.argv[1:]]; sys.exit(a != b)" "$i4/status/upstream/last.json" "$dir/last4.before"'
SABHA_GH_CACHE=$dir/cache4 SABHA_IMPL=$i4 up2
check "and the stale-cache 404 item is not repeated on the next run" '[[ $(grep -c "^id: " "$i4/for-me.items") == 1 ]] && grep -q "0 new finding" "$dir/out"'
SABHA_GH_CACHE=$dir/cache4 FAKE_GH_FAIL=1 SABHA_IMPL=$dir/impl4t up2; rc=$?
check "the transient twin (gh fails, cache primed): could not read, no item, facts kept" '(( rc == 0 )) && [[ ! -e $dir/impl4t/for-me.items ]] && grep -q "could not read" "$dir/err" && grep -q "\"branch_exists\": true" "$dir/impl4t/status/upstream/last.json"'
SABHA_GH_CACHE=$dir/cache4-empty SABHA_IMPL=$dir/impl4n up2; rc=$?
check "repo and branch both 404, no cache: not a branch finding, one check-by-hand item, facts kept" '(( rc == 0 )) && [[ $(grep -c "^id: " "$dir/impl4n/for-me.items") == 1 ]] && grep -q "^title: upstream: acme/app not found or renamed: check by hand$" "$dir/impl4n/for-me.items" && ! grep -q "is gone" "$dir/impl4n/for-me.items" && grep -q "\"branch_exists\": true" "$dir/impl4n/status/upstream/last.json" && grep -q "could not read" "$dir/err"'
SABHA_GH_CACHE=$dir/cache4-empty SABHA_IMPL=$dir/impl4n up2
check "and the check-by-hand item is not repeated" '[[ $(grep -c "^id: " "$dir/impl4n/for-me.items") == 1 ]]'

echo "--- a release-line base is never a default branch"
reset_fx
echo "repos/acme/app/branches/release/x --jq|$dir/fx-app-branch.json" >> "$FD/map"
echo "app   backend/app   release/x   x   commits" > "$ws/dev/repos3.conf"
SABHA_IMPL=$dir/impl10 "$BIN/sabha-upstream" --conf "$ws/dev/repos3.conf" >"$dir/out" 2>"$dir/err"; rc=$?
check "base release/x, default main: run 1 reports no default-branch item" '(( rc == 0 )) && [[ ! -e $dir/impl10/for-me.items ]]'

echo "--- one run at a time"
reset_fx
for n in 5 6; do SABHA_IMPL=$dir/impl$n up2; done
fx app-repo '{"full_name":"acme/app","archived":true,"default_branch":"main"}'
slow() { SABHA_GH_BIN=$BIN/../tests/fake-gh-slow.sh SABHA_IMPL=$dir/impl$1 "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" >"$dir/out$2" 2>"$dir/err$2"; }
slow 5 a
check "reference: one run, one item" '[[ $(grep -c "^id: " "$dir/impl5/for-me.items") == 1 ]]'
slow 6 a & slow 6 b &
wait
check "two runs at once: still one item, one brief" '[[ $(grep -c "^id: " "$dir/impl6/for-me.items") == 1 && $(find "$dir/impl6/inbox/Boss" -name "*.md" | wc -l | tr -d " ") == 1 ]]'
check "one of them said it was skipped by the lock; no temp file is left" 'cat "$dir/outa" "$dir/outb" | grep -q "holds" && [[ -z $(find "$dir/impl6/status/upstream" -name "*.tmp") && ! -e $dir/impl6/status/upstream/.lock ]]'
i7=$dir/impl7
mkdir -p "$i7/status/upstream/.lock"
c0=$(ncalls)
SABHA_IMPL=$i7 up2; rc=$?
check "a held lock: exit 0, no gh call, no state" '(( rc == 0 )) && [[ $(ncalls) == "$c0" && ! -e $i7/status/upstream/last.json ]] && grep -q "holds" "$dir/out"'
touch -t 202001010000 "$i7/status/upstream/.lock"
SABHA_IMPL=$i7 up2; rc=$?
check "a stale lock is taken over and released" '(( rc == 0 )) && [[ -s $i7/status/upstream/last.json && ! -e $i7/status/upstream/.lock ]]'

echo "--- a conf-file-only setup and bad state"
home=$dir/home
mkdir -p "$home/dev" "$home/cwd"
cp "$ws/dev/repos2.conf" "$home/dev/repos.conf"
printf 'SABHA_IMPL="$HOME/imp"\nSABHA_UPSTREAM_CONF="$HOME/dev/repos.conf"\n' > "$home/sabha.conf"
reset_fx
( cd "$home/cwd" && env -u SABHA_IMPL HOME="$home" SABHA_CONF="$home/sabha.conf" SABHA_UPSTREAM_ORG=acme "$BIN/sabha-upstream" >"$dir/out" 2>"$dir/err" ); rc=$?
check "SABHA_IMPL and SABHA_UPSTREAM_CONF written as \$HOME in sabha.conf are expanded" '(( rc == 0 )) && [[ -s $home/imp/status/upstream/last.json && ! -e "$home/cwd/\$HOME" ]]'
( cd "$home/cwd" && env -u SABHA_IMPL SABHA_CONF="$dir/none.conf" "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" >"$dir/out" 2>"$dir/err" ); rc=$?
check "no SABHA_IMPL anywhere: exit 2 with a message, nothing written under the current folder" '(( rc == 2 )) && grep -q "SABHA_IMPL is not set" "$dir/err" && [[ ! -e $home/cwd/status ]]'
i8=$dir/impl8
mkdir -p "$i8/status/upstream"; echo "[1,2]" > "$i8/status/upstream/last.json"
SABHA_IMPL=$i8 up2; rc=$?
check "state that is not an object: moved to last.json.bad, one warning, a baseline, no traceback" '(( rc == 0 )) && [[ -s $i8/status/upstream/last.json.bad ]] && grep -q "last.json.bad" "$dir/err" && ! grep -q Traceback "$dir/err"'
i9=$dir/impl9
SABHA_GH_CACHE=$dir/cache9 FAKE_GH_FAIL=1 SABHA_IMPL=$i9 up2; rc=$?
check "every read failed: the day is not marked, the next pass retries" '(( rc == 0 )) && [[ ! -e $i9/status/upstream/day ]]'
SABHA_IMPL=$i9 up2 --daily
check "the retry reads and marks the day" '[[ -s $i9/status/upstream/day ]]'

echo "--- signals release the lock; SABHA_IMPL with an unset variable or empty in the environment"
reset_fx
wait_for() { local i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.2; done; return 1; }
sig() {
  FAKE_GH_SLEEP=2 SABHA_GH_BIN=$BIN/../tests/fake-gh-slow.sh SABHA_IMPL=$dir/impl1$1 "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" >"$dir/outs" 2>"$dir/errs" &
  spid=$!
  wait_for "[[ -d $dir/impl1$1/status/upstream/.lock ]]"
  kill -"$2" "$spid"
  wait "$spid"; srcode=$?
}
sig 1 TERM
check "SIGTERM: exit 143 and the lock is gone" '(( srcode == 143 )) && [[ ! -e $dir/impl11/status/upstream/.lock ]]'
sig 2 HUP
check "SIGHUP: exit 129 and the lock is gone" '(( srcode == 129 )) && [[ ! -e $dir/impl12/status/upstream/.lock ]]'
( cd "$home/cwd" && SABHA_IMPL='$SABHA_NO_SUCH_VAR/x' "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" >"$dir/out" 2>"$dir/err" ); rc=$?
check "SABHA_IMPL with an unset variable: exit 2, nothing created" '(( rc == 2 )) && grep -q "still contains a" "$dir/err" && [[ -z $(ls "$home/cwd") ]]'
printf 'SABHA_IMPL="$HOME/imp2"\n' > "$home/sabha2.conf"
( cd "$home/cwd" && SABHA_IMPL='' HOME="$home" SABHA_CONF="$home/sabha2.conf" SABHA_UPSTREAM_ORG=acme "$BIN/sabha-upstream" --conf "$ws/dev/repos2.conf" >"$dir/out" 2>"$dir/err" ); rc=$?
check "SABHA_IMPL empty in the environment: the value from sabha.conf is used" '(( rc == 0 )) && [[ -s $home/imp2/status/upstream/last.json ]]'

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
