#!/usr/bin/env bash
# bin/sabha-nightly: the day window over .done mtimes and for-me.items utc, BLOCKED and waiting rows, control
# characters and bad bytes, torn and garbage input, rerun stability, a kept hand edit, the lock, flag errors.
# Fixtures only; nothing reads a real sabha folder. Run: tests/test-nightly.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-nightly.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

impl=$dir/impl
mkdir -p "$impl/inbox/Worker" "$impl/inbox/Reviewer"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$impl" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
N() { "$BIN/sabha-nightly" "$@"; }

printf 'task: build the export matrix\n\nbody\n' >"$impl/inbox/Worker/001-boss-export.md"
printf 'utc: x\nresult: matrix written, 68 rows\n' >"$impl/inbox/Worker/001.done"
printf 'result: older work\n' >"$impl/inbox/Worker/002.done"
printf 'result: BLOCKED needs a token\n' >"$impl/inbox/Worker/003.done"
printf 'result: caf\303\251 \377 \033]0;pwn\007 end \342\200\256 \342\200\250 x\r\n' >"$impl/inbox/Reviewer/010.done"
mkdir "$impl/inbox/Worker/004.done"
head -c 200000 /dev/zero | tr '\0' 'a' >"$impl/inbox/Worker/005.done"
touch -t 202611081200 "$impl/inbox/Worker/001.done" "$impl/inbox/Worker/003.done" "$impl/inbox/Reviewer/010.done" "$impl/inbox/Worker/005.done"
touch -t 202611071200 "$impl/inbox/Worker/002.done"
cat >"$impl/for-me.items" <<'X'
---
id: 1
utc: 2026-11-08T08:00:00Z
owner: Worker
state: OPEN
title: pick a base branch
ask: the user
---
id: 2
utc: 2026-11-07T08:00:00Z
owner: Worker
state: OPEN
title: older question
---
id: 2
utc: 2026-11-08T09:00:00Z
owner: Worker
state: DONE
title: older question
---
id: 3
utc: 2026-11-08T10:00:00Z
owner: Worker
state: OPEN
title: esc \033[31mred\033[0m title
cmd:
id: 99
utc: 2026-11-08T10:00:00Z
state: DONE
---
id: 4
utc: 2026-11-08T11:00:00Z
owner: Worker
state: OPEN
title: torn block
X
sed -i.bak 's/\\033/'"$(printf '\033')"'/g' "$impl/for-me.items"; rm -f "$impl/for-me.items.bak"
content=$(cat "$impl/for-me.items")
printf '%s' "$content" >"$impl/for-me.items"

out=$dir/out
N --date 2026-11-08 --out "$out"; rc=$?
d=$out/2026-11-08.md
check "writes the draft, rc 0" '[[ $rc -eq 0 && -f $d ]]'
check "in-window done listed with its brief title" 'grep -q "Worker 001 build the export matrix: matrix written, 68 rows" "$d"'
check "out-of-window done not listed" '! grep -q "older work" "$d"'
check "BLOCKED done under Blocked" 'sed -n "/^## Blocked/,\$p" "$d" | grep -q "Worker 003.*BLOCKED needs a token"'
check "BLOCKED done not under Shipped" '! sed -n "/^## Shipped/,/^## Board/p" "$d" | grep -q "BLOCKED"'
check "a directory named NNN.done is skipped" '! grep -q " 004" "$d"'
check "huge done is capped, not dumped" '[[ $(wc -c <"$d") -lt 3000 ]]'
check "no control byte in the draft" '! LC_ALL=C grep -q "[[:cntrl:]]" <(tr -d "\n" <"$d")'
check "bidi and line-separator characters are stripped" '[[ $(LC_ALL=C grep -c -e "$(printf "\342\200\256")" -e "$(printf "\342\200\250")" "$d") -eq 0 ]]'
check "bad bytes do not crash and the line is kept" 'grep -q "Reviewer 010" "$d"'
check "item opened today listed" 'grep -q "opened #1 pick a base branch" "$d"'
check "item closed today listed" 'grep -q "closed #2 older question (DONE)" "$d"'
check "item opened before today not listed as opened" '! grep -q "opened #2" "$d"'
check "open item shows who it waits on" 'grep -q "#1 pick a base branch (waiting on the user)" "$d"'
check "cmd body lines never become a block" '! grep -q "#99" "$d"'
check "torn last block skipped" '! grep -q "torn block" "$d"'
check "marked draft, not sent" 'grep -q "DRAFT" "$d" && grep -q "not sent" "$d"'

before=$(cksum <"$d")
N --date 2026-11-08 --out "$out" >"$dir/r2"; rc=$?
check "same-day rerun is unchanged" '[[ $rc -eq 0 ]] && grep -q "^unchanged" "$dir/r2" && [[ $(cksum <"$d") == "$before" ]]'
echo "my edit" >>"$d"
N --date 2026-11-08 --out "$out" 2>/dev/null; rc=$?
check "an edited draft is kept (rc 3)" '[[ $rc -eq 3 ]] && grep -q "my edit" "$d"'
N --date 2026-11-08 --out "$out" --force >/dev/null; rc=$?
check "--force replaces it" '[[ $rc -eq 0 ]] && ! grep -q "my edit" "$d"'

N --date 2026-11-07 --out "$out" >/dev/null
check "another day writes its own file and leaves the first" '[[ -f $out/2026-11-07.md && $(cksum <"$d") == "$before" ]]'
check "that day holds the older done" 'grep -q "older work" "$out/2026-11-07.md"'
check "--stdout writes no file" '[[ -z $(N --date 2026-11-06 --out "$out" --stdout >/dev/null; ls "$out" | grep 11-06) ]]'
"$BIN/sabha" nightly --date 2026-11-08 --out "$out" >"$dir/r3"
check "sabha nightly reaches the tool" 'grep -q "^unchanged" "$dir/r3"'

for bad in "--date" "--out" "--date nope" "--date 2026-13-45" "--bogus" "--date --force"; do
  # shellcheck disable=SC2086  # the words are the case
  N $bad >/dev/null 2>&1; rc=$?
  check "usage error exits 2: $bad" '[[ $rc -eq 2 ]]'
done

mkdir -p "$dir/impl2"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s/impl2\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha2.conf"
SABHA_CONF=$dir/sabha2.conf N --date 2026-11-08 --stdout >"$dir/empty.md"; rc=$?
check "empty folder: rc 0 and says nothing recorded" '[[ $rc -eq 0 ]] && grep -q "nothing recorded as done" "$dir/empty.md" && grep -q "nothing blocked" "$dir/empty.md"'
for junk in '[1,2,3]' '{"a": 1}' ''; do
  printf '%s' "$junk" >"$dir/impl2/for-me.items"
  SABHA_CONF=$dir/sabha2.conf N --date 2026-11-08 --stdout >/dev/null 2>&1; rc=$?
  check "garbage items file '$junk' does not crash" '[[ $rc -eq 0 ]]'
done
head -c 3000 /dev/urandom >"$dir/impl2/for-me.items"
SABHA_CONF=$dir/sabha2.conf N --date 2026-11-08 --stdout >/dev/null 2>&1; rc=$?
check "binary items file does not crash" '[[ $rc -eq 0 ]]'

mkdir "$out/.nightly.lock"
N --date 2026-11-05 --out "$out" >/dev/null 2>&1; rc=$?
check "a fresh lock blocks a second run (rc 1) and is not removed" '[[ $rc -eq 1 && -d $out/.nightly.lock ]]'
touch -t 202001010000 "$out/.nightly.lock"
N --date 2026-11-05 --out "$out" >/dev/null 2>&1; rc=$?
check "a stale lock is reaped, and released after the run" '[[ $rc -eq 0 && ! -d $out/.nightly.lock ]]'

check "own files are pure ASCII" '! LC_ALL=C grep -q "[^[:print:][:space:]]" "$BIN/sabha-nightly" "$0"'

if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: sabha-nightly window, blocked and waiting rows, clean output, bad input, rerun, kept edit, lock, usage"
