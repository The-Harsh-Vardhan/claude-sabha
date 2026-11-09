#!/usr/bin/env bash
# sabha-for-me --digest: Finished honours the window, Blocked lists only live .blocked files and Blocked: lines, a command
# with an inline # or ... is withheld, non-ASCII input and control bytes are safe, a rerun (even after a status mtime
# change) writes nothing, a new day leaves yesterday's file alone, sabha-watch does not build it.
# Fixture files only; no herdr, no agent. Run: tests/test-morning-digest.sh
set -u
# shellcheck source=tests/hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-digest.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
impl=$dir/impl
mkdir -p "$impl/status" "$impl/inbox/Zed"
printf 'SABHA_IMPL=%s\nSABHA_ROSTER="Zed:sonnet Old:sonnet Sleepy:sonnet"\nSABHA_PROJECT=Demo\n' "$impl" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
fail() { echo "FAIL: $*"; exit 1; }
chk() { grep -q -- "$2" "$1" || fail "$3"; }
nochk() { grep -q -- "$2" "$1" && fail "$3"; return 0; }

printf 'task: new thing\n' > "$impl/inbox/Zed/001-boss-new-thing.md"
printf 'task: old thing\n' > "$impl/inbox/Zed/002-boss-old-thing.md"
printf 'task: stuck thing\n' > "$impl/inbox/Zed/003-boss-stuck-thing.md"
printf 'Shipped the new thing.\nSecond line of it.\n\nSecond paragraph stays out.\n' > "$impl/inbox/Zed/001.done"
printf 'Shipped the old thing.\n' > "$impl/inbox/Zed/002.done"
touch -t 202001010000 "$impl/inbox/Zed/002.done"
printf 'status: needs a licence key\n' > "$impl/inbox/Zed/003.blocked"
for n in 004 005 006 007 008; do printf 'task: brief %s\n' "$n" > "$impl/inbox/Zed/$n-boss-b$n.md"; done
printf 'status: resolved blocker\n' > "$impl/inbox/Zed/004.blocked"; printf 'ok\n' > "$impl/inbox/Zed/004.done"
touch -t 202601010000 "$impl/inbox/Zed/004.done"
printf 'status: cancelled blocker\n' > "$impl/inbox/Zed/005.blocked"; : > "$impl/inbox/Zed/005.cancel"
printf 'status: cleared blocker\n' > "$impl/inbox/Zed/006.blocked.md.cleared-0532"
: > "$impl/inbox/Zed/007.blocked"
printf 'status: blocker before the ack\n' > "$impl/inbox/Zed/008.blocked"; : > "$impl/inbox/Zed/008.ack"
touch -t 202601010000 "$impl/inbox/Zed/008.blocked"; touch -t 202601020000 "$impl/inbox/Zed/008.ack"
printf 'task: brief 011\n' > "$impl/inbox/Zed/011-boss-b011.md"
printf 'status: parked blocker\n' > "$impl/inbox/Zed/011.blocked"; printf 'PARKED\n' > "$impl/inbox/Zed/011.parked.md"
touch -t 202601010000 "$impl/inbox/Zed/011.blocked"; touch -t 202601020000 "$impl/inbox/Zed/011.parked.md"
printf 'Title\nIdle: by design (waiting)\nBlocked: stale line\n' > "$impl/status/sleepy.md"
printf 'Title\nBlocked: waiting on review\n' > "$impl/status/old.md"
printf 'Title\nCurrent: work\n' > "$impl/status/zed.md"
cat > "$impl/for-me.items" <<'I'
---
id: 7
utc: 2026-11-08T01:00:00Z
title: good command
cmd: cd /tmp/demo && git status
---
id: 8
utc: 2026-11-08T00:00:00Z
title: commented command
cmd: cd /tmp/demo && git status # check it
---
id: 9
utc: 2026-11-08T02:00:00Z
title: elided command
cmd: cd /tmp/demo && git log ...
---
id: 10
utc: 2026-11-08T03:00:00Z
title: quoted hash is fine
cmd: cd /tmp/demo && echo "a # b"
---
id: 11
utc: 2026-11-08T03:00:00Z
title: closed one
cmd: cd /tmp/closed && ls
---
id: 11
utc: 2026-11-08T04:00:00Z
state: DONE
I

today=$(date +%Y-%m-%d)
md=$impl/DIGEST-$today.md; page=$impl/DIGEST-$today.html
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z >/dev/null || fail "digest run"
[[ -f $md && -f $page ]] || fail "digest files not written"
chk "$md" 'inbox/Zed/001.done: new thing' "001.done missing from Finished"
chk "$md" 'Shipped the new thing. Second line of it.' "first paragraph of the .done missing"
nochk "$md" 'Second paragraph' "only the first paragraph may show"
nochk "$md" '002.done' "a .done older than the window must not show"
chk "$md" '## Finished (1)' "Finished count"
chk "$md" 'needs a licence key' "a .blocked file missing"
chk "$md" 'waiting on review' "a Blocked: status line missing"
chk "$md" '## Blocked (3)' "Blocked count (003, empty 007 marker, Old)"
nochk "$md" 'resolved blocker' "a blocker with a .done beside it must not list"
nochk "$md" 'cancelled blocker' "a blocker with a .cancel beside it must not list"
nochk "$md" 'cleared blocker' "a .cleared marker must not list"
nochk "$md" 'parked blocker' "a blocker older than a .parked marker must not list"
nochk "$md" 'blocker before the ack' "a blocker older than the brief's ack must not list"
chk "$md" '007.blocked): (no text)' "an empty marker must say (no text)"
nochk "$md" 'Sleepy.*stale line' "an Idle: role with an old Blocked: line must not list"
chk "$md" '## Commands for you (4)' "closed item must not be listed"
chk "$md" 'git status$' "good command not shown verbatim"
nochk "$md" 'check it' "a command with an inline # comment must be withheld"
nochk "$md" 'git log' "a command with ... must be withheld"
chk "$md" 'inline # comment' "withheld reason missing"
chk "$md" 'elision' "elision reason missing"
chk "$md" 'echo "a # b"' "a # inside quotes is fine"
a=$(grep -n 'commented command' "$md" | cut -d: -f1); b=$(grep -n 'good command' "$md" | cut -d: -f1)
[[ $a -lt $b ]] || fail "commands must be oldest first"
chk "$page" '<pre>cd /tmp/demo &amp;&amp; git status</pre>' "html copy block (escaped)"
chk "$page" 'prefers-color-scheme' "html theme"
nochk "$md" '([0-9.]*[mh])$' "Roles must not print an age"
echo "ok: window, blocked (live only), commands (withheld, quoted, order), md and html"

before=$(ls -l "$md" "$page")
sleep 1
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z | grep -q wrote && fail "a rerun with nothing new must write nothing"
[[ $(ls -l "$md" "$page") == "$before" ]] || fail "a rerun changed the files"
python3 "$here/bin/sabha-for-me" --digest >/dev/null
chk "$md" 'since: 2026-01-01T00:00:00Z' "a rerun without --since must keep today's window"
touch -t "$(date -v-10M +%Y%m%d%H%M)" "$impl/status/old.md" "$impl/status/sleepy.md"
touch -t "$(date -v-5M +%Y%m%d%H%M)" "$impl/status/zed.md"
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z | grep -q wrote && fail "a status mtime change alone must not rewrite the page"
echo "ok: rerun writes nothing (also after a status mtime change), window sticks for the day"

old=$impl/DIGEST-2000-01-01.md
printf 'yesterday\n' > "$old"; cp "$old" "$dir/old.copy"
rm -f "$md" "$page"
touch -t 202611080000 "$old"
python3 "$here/bin/sabha-for-me" --digest >/dev/null
cmp -s "$old" "$dir/old.copy" || fail "an older day's digest was touched"
chk "$md" "since: $(date -u -r "$old" +%Y-%m-%dT%H:%M:%SZ)" "default window must be the previous digest's mtime"
echo "ok: older day untouched, window starts at the previous digest"

rm -f "$impl"/DIGEST-*
SABHA_DIGEST_HOUR=0 bash "$here/bin/sabha-watch" >/dev/null 2>&1
[[ ! -f $md ]] || fail "sabha-watch must not build the digest (it stays read-only)"
grep -qi digest "$here/bin/sabha-watch" && fail "bin/sabha-watch still mentions the digest"
echo "ok: sabha-watch leaves the digest to cron"

rm -f "$impl"/DIGEST-*
printf 'task: caf\303\251 title\n' > "$impl/inbox/Zed/009-boss-x.md"
printf 'Shipped caf\303\251 \342\200\224 done \033[31mred\n' > "$impl/inbox/Zed/009.done"
printf 'task: ten\n' > "$impl/inbox/Zed/010-boss-ten.md"; printf 'status: needs caf\303\251\n' > "$impl/inbox/Zed/010.blocked"
printf 'Title\nCurrent: caf\303\251 work\n' > "$impl/status/zed.md"
printf -- '---\nid: 12\nutc: 2026-11-08T05:00:00Z\ntitle: caf\303\251\ncmd: echo "```" && ls\n' >> "$impl/for-me.items"
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z >"$dir/out.txt" 2>&1 || { cat "$dir/out.txt"; fail "a non-ASCII input crashed the digest"; }
[[ -z $(compgen -G "$impl/.for-me-*") ]] || fail "a temp file was left behind"
chk "$md" 'caf? title' "non-ASCII title must show as ?"
chk "$md" 'Shipped caf? ? done' "non-ASCII .done text must show as ?"
chk "$md" 'needs caf?' "non-ASCII blocker text must show as ?"
LC_ALL=C grep -q '[^ -~]' "$md" "$page" && fail "digest holds a non-ASCII or control byte"
chk "$md" '^````$' "a command holding a triple backtick needs a longer fence"
echo "ok: non-ASCII and control bytes, no temp file left, long fence"

rm -f "$impl"/DIGEST-*; mkdir "$impl/DIGEST-$today.html"
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z >/dev/null 2>&1
[[ -z $(compgen -G "$impl/.for-me-*") ]] || fail "a failed write left a temp file behind"
rm -rf "$impl/DIGEST-$today.html" "$impl"/DIGEST-*
printf 'SABHA_IMPL=%s\nSABHA_ROSTER="Zed:sonnet"\nSABHA_FORME_DIR=%s\n' "$impl" "$dir/missing" > "$dir/sabha2.conf"
SABHA_CONF=$dir/sabha2.conf python3 "$here/bin/sabha-for-me" --digest 2>&1 | grep -q 'digest folder missing' || fail "a missing digest folder needs a clear message"
echo "ok: failed write cleans up, missing folder message"
echo "all passed"
