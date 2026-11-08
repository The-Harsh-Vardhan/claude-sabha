#!/usr/bin/env bash
# sabha-for-me --digest: Finished honours the window, Blocked lists .blocked files and Blocked: lines, a command with an
# inline # or ... is withheld, a rerun writes nothing, a new day leaves yesterday's file alone, sabha-watch builds it.
# Fixture files only; no herdr, no agent. Run: tests/test-morning-digest.sh
set -u
# shellcheck source=tests/hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-digest.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
impl=$dir/impl
mkdir -p "$impl/status" "$impl/inbox/Zed"
printf 'SABHA_IMPL=%s\nSABHA_ROSTER="Zed:sonnet Old:sonnet"\nSABHA_PROJECT=Demo\n' "$impl" > "$dir/sabha.conf"
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
chk "$md" '## Blocked (2)' "Blocked count"
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
echo "ok: window, blocked, commands (withheld, quoted, order), md and html"

before=$(ls -l "$md" "$page")
sleep 1
python3 "$here/bin/sabha-for-me" --digest --since 2026-01-01T00:00:00Z | grep -q wrote && fail "a rerun with nothing new must write nothing"
[[ $(ls -l "$md" "$page") == "$before" ]] || fail "a rerun changed the files"
python3 "$here/bin/sabha-for-me" --digest >/dev/null
chk "$md" 'since: 2026-01-01T00:00:00Z' "a rerun without --since must keep today's window"
echo "ok: rerun writes nothing, window sticks for the day"

old=$impl/DIGEST-2000-01-01.md
printf 'yesterday\n' > "$old"; cp "$old" "$dir/old.copy"
rm -f "$md" "$page"
touch -t 202611080000 "$old"
python3 "$here/bin/sabha-for-me" --digest >/dev/null
cmp -s "$old" "$dir/old.copy" || fail "an older day's digest was touched"
chk "$md" 'since: 2026-11-08T0\|since: 2026-11-07T' "default window must be the previous digest's mtime"
echo "ok: older day untouched, window starts at the previous digest"

rm -f "$impl"/DIGEST-*
SABHA_DIGEST_HOUR=0 bash "$here/bin/sabha-watch" >/dev/null 2>&1
[[ -f $md ]] || fail "sabha-watch did not build the digest at hour 0"
rm -f "$impl"/DIGEST-*
SABHA_DIGEST_HOUR=24 bash "$here/bin/sabha-watch" >/dev/null 2>&1
[[ ! -f $md ]] || fail "sabha-watch built the digest before SABHA_DIGEST_HOUR"
echo "ok: sabha-watch builds it from SABHA_DIGEST_HOUR"
echo "all passed"
