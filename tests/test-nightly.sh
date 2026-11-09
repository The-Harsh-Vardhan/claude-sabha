#!/usr/bin/env bash
# bin/sabha-nightly: the day window (its boundary seconds in two time zones) over .done utc or mtime and for-me.items
# utc, BLOCKED and waiting rows, control characters and bad bytes, a torn last block, string ids, garbage input, rerun
# stability, a kept hand edit, the lock, a large inbox, flag errors.
# Fixtures only; nothing reads a real sabha folder. Run: tests/test-nightly.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
export TZ=UTC
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
check "torn last block skipped whole: its id is not listed" '! grep -q "#4" "$d" && ! grep -q "torn block" "$d"'
check "the block before the torn one is still listed" 'grep -q "#3 esc " "$d"'
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

# a torn closing block (its state line is cut) must not show up as an item opened today
rm -rf "$dir/impl3"; mkdir -p "$dir/impl3"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s/impl3\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha3.conf"
N3() { SABHA_CONF=$dir/sabha3.conf N "$@"; }
printf -- '---\nid: 1\nutc: 2026-11-08T08:00:00Z\nstate: OPEN\ntitle: whole one\n---\nid: 7\nutc: 2026-11-08T12:00:00Z\nstate: DONE' >"$dir/impl3/for-me.items"
N3 --date 2026-11-08 --stdout >"$dir/torn7.md"
check "a torn closing block is not listed as opened" '! grep -q "#7" "$dir/torn7.md" && grep -q "opened #1 whole one" "$dir/torn7.md"'

# string ids, "DONE (note)" and SUPERSEDED states, no title, newest-first Blocked with a cap
{
  printf -- '---\nid: dushasan-1\nutc: 2026-11-08T08:00:00Z\nowner: Worker\nstate: OPEN\ntitle: string id\n'
  printf -- '---\nid: a-2\nutc: 2026-11-07T08:00:00Z\nstate: OPEN\ntitle: closes with a note\n'
  printf -- '---\nid: a-2\nutc: 2026-11-08T09:00:00Z\nstate: DONE (brief 406 settled it)\n'
  printf -- '---\nid: a-3\nutc: 2026-11-07T08:00:00Z\nstate: OPEN\ntitle: replaced\n'
  printf -- '---\nid: a-3\nutc: 2026-11-08T09:30:00Z\nstate: SUPERSEDED (by a-9)\n'
  printf -- '---\nid: a-4\nutc: 2026-11-08T09:40:00Z\nstate: OPEN\n'
  i=1
  while (( i <= 40 )); do
    printf -- '---\nid: %d\nutc: 2026-11-01T00:%02d:00Z\nowner: Worker\nstate: OPEN\ntitle: old%d\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
} >"$dir/impl3/for-me.items"
N3 --date 2026-11-08 --stdout >"$dir/ids.md"
blocked=$(sed -n '/^## Blocked/,/^## Plan/p' "$dir/ids.md")
check "a string id is opened and waiting" 'grep -q "opened #dushasan-1 string id (owner Worker)" "$dir/ids.md" && grep -q "#dushasan-1 string id (waiting on Worker)" <<<"$blocked"'
check "DONE (note) closes an item" 'grep -q "closed #a-2 closes with a note (DONE)" "$dir/ids.md" && ! grep -q "#a-2 .*waiting" <<<"$blocked"'
check "SUPERSEDED closes an item" 'grep -q "closed #a-3 replaced (SUPERSEDED)" "$dir/ids.md" && ! grep -q "#a-3 .*waiting" <<<"$blocked"'
check "an item with no title prints (no title), not a gap" 'grep -q "opened #a-4 (no title) (owner ?)" "$dir/ids.md" && ! grep -q "  " "$dir/ids.md"'
check "Blocked lists newest first, so today is not dropped by the cap" 'grep -q "#dushasan-1" <<<"$blocked" && grep -q "#40 old40 " <<<"$blocked" && ! grep -q "#1 old1 " <<<"$blocked"'
check "the cap says how many more" 'grep -q "^- and 12 more" <<<"$blocked"'

# the window edge, to the second, under an east and a west zone; a +-1 h widening must fail a row
edge() {
  tz=$1; lom1=$2; lo=$3; him1=$4; hi=$5
  rm -rf "$dir/impl3"; mkdir -p "$dir/impl3/inbox/Worker"
  for n in 011 012 013 014; do printf 'result: r%s\n' "$n" >"$dir/impl3/inbox/Worker/$n.done"; done
  TZ=$tz touch -t 202611072359.59 "$dir/impl3/inbox/Worker/011.done"
  TZ=$tz touch -t 202611080000.00 "$dir/impl3/inbox/Worker/012.done"
  TZ=$tz touch -t 202611082359.59 "$dir/impl3/inbox/Worker/013.done"
  TZ=$tz touch -t 202611090000.00 "$dir/impl3/inbox/Worker/014.done"
  for p in "eb $lom1" "ea $lo" "ez $him1" "ey $hi"; do
    printf -- '---\nid: %s\nutc: %s\nstate: OPEN\ntitle: t%s\n' "${p% *}" "${p#* }" "${p% *}"
  done >"$dir/impl3/for-me.items"
  TZ=$tz N3 --date 2026-11-08 --stdout >"$dir/edge.md"
  check "$tz: done at 23:59:59 the day before is out" '! grep -q "r011" "$dir/edge.md"'
  check "$tz: done at 00:00:00 is in" 'grep -q "r012" "$dir/edge.md"'
  check "$tz: done at 23:59:59 is in" 'grep -q "r013" "$dir/edge.md"'
  check "$tz: done at 00:00:00 the next day is out" '! grep -q "r014" "$dir/edge.md"'
  check "$tz: item one second before the day is not opened" '! grep -q "opened #eb" "$dir/edge.md"'
  check "$tz: item at the first second is opened" 'grep -q "opened #ea" "$dir/edge.md"'
  check "$tz: item at the last second is opened" 'grep -q "opened #ez" "$dir/edge.md"'
  check "$tz: item at the next day's first second is not opened" '! grep -q "opened #ey" "$dir/edge.md"'
}
edge Asia/Kolkata 2026-11-07T18:29:59Z 2026-11-07T18:30:00Z 2026-11-08T18:29:59Z 2026-11-08T18:30:00Z
edge America/New_York 2026-11-08T04:59:59Z 2026-11-08T05:00:00Z 2026-11-09T04:59:59Z 2026-11-09T05:00:00Z

# the .done utc: line wins over mtime; no or a bad utc: falls back to mtime; an empty result has no trailing blank
rm -rf "$dir/impl3"; mkdir -p "$dir/impl3/inbox/Worker"
printf 'utc: 2026-11-08T09:00:00Z\nresult: r021 stamped in\n' >"$dir/impl3/inbox/Worker/021.done"
printf 'utc: 2026-11-07T09:00:00Z\nresult: r022 stamped out\n' >"$dir/impl3/inbox/Worker/022.done"
printf 'result: r023 mtime only\n' >"$dir/impl3/inbox/Worker/023.done"
printf 'utc: junk\nresult: r024 bad stamp, old mtime\n' >"$dir/impl3/inbox/Worker/024.done"
printf 'result:\n' >"$dir/impl3/inbox/Worker/025.done"
touch -t 202611201200 "$dir/impl3/inbox/Worker/021.done" "$dir/impl3/inbox/Worker/024.done"
touch -t 202611081200 "$dir/impl3/inbox/Worker/022.done" "$dir/impl3/inbox/Worker/023.done" "$dir/impl3/inbox/Worker/025.done"
N3 --date 2026-11-08 --stdout >"$dir/utc.md"
check "a done with a utc: line in the day is in although its mtime was reset" 'grep -q "r021" "$dir/utc.md"'
check "a done with a utc: line outside the day is out although its mtime is inside" '! grep -q "r022" "$dir/utc.md"'
check "a done with no utc: line falls back to its mtime" 'grep -q "r023" "$dir/utc.md"'
check "a done with a bad utc: line falls back to its mtime (out here)" '! grep -q "r024" "$dir/utc.md"'
check "an empty result prints a placeholder, no trailing blank" 'grep -q "Worker 025: (no result line)$" "$dir/utc.md" && ! grep -q " $" "$dir/utc.md"'

# one class per row: the characters that must never reach the terminal
rm -rf "$dir/impl3"; mkdir -p "$dir/impl3/inbox/Worker"
n=100
for cls in "061c:\330\234" "200b:\342\200\213" "200c:\342\200\214" "200d:\342\200\215" "2060:\342\201\240" "2064:\342\201\244" "feff:\357\273\277" "e0041:\363\240\201\201" "e007f:\363\240\201\277"; do
  n=$((n + 1))
  printf 'result: a%b b\n' "${cls#*:}" >"$dir/impl3/inbox/Worker/$n.done"
  touch -t 202611081200 "$dir/impl3/inbox/Worker/$n.done"
  N3 --date 2026-11-08 --stdout >"$dir/cls.md"
  check "control class ${cls%%:*} is replaced by a blank" 'grep -q "Worker $n: a b$" "$dir/cls.md" && [[ -z $(LC_ALL=C grep -a "Worker $n" "$dir/cls.md" | LC_ALL=C grep -a "[^ -~]") ]]'
done

# a large inbox: titles come from one listing per role, not one per marker
rm -rf "$dir/impl3"; mkdir -p "$dir/impl3/inbox/Worker"
n=1
while (( n <= 2000 )); do
  : >"$dir/impl3/inbox/Worker/$n-x-job.md"; : >"$dir/impl3/inbox/Worker/$n.done"
  n=$((n + 1))
done
touch -t 202611081200 "$dir/impl3/inbox/Worker/"*.done
SECONDS=0
N3 --date 2026-11-08 --stdout >"$dir/big.md"; rc=$?
check "2000 markers in one role finish in under 10 s" '[[ $rc -eq 0 && $SECONDS -lt 10 ]] && grep -q "and 1970 more" "$dir/big.md"'

# --out "" is a usage error; a target that cannot be replaced leaves no temp file
N --date 2026-11-08 --out "" >/dev/null 2>&1; rc=$?
check "--out with an empty value exits 2 and writes nothing" '[[ $rc -eq 2 && ! -e $impl/nightly ]]'
mkdir -p "$dir/out2/2026-11-08.md"
N --date 2026-11-08 --out "$dir/out2" >/dev/null 2>&1; rc=$?
check "a target that is a directory: rc 1 and no temp file left" '[[ $rc -eq 1 && -z $(ls -A "$dir/out2" | grep tmp) ]]'

mkdir "$out/.nightly.lock"
N --date 2026-11-05 --out "$out" >/dev/null 2>&1; rc=$?
check "a fresh lock blocks a second run (rc 1) and is not removed" '[[ $rc -eq 1 && -d $out/.nightly.lock ]]'
touch -t 202001010000 "$out/.nightly.lock"
N --date 2026-11-05 --out "$out" >/dev/null 2>&1; rc=$?
check "a stale lock is reaped, and released after the run" '[[ $rc -eq 0 && ! -d $out/.nightly.lock ]]'

check "own files are pure ASCII" '! LC_ALL=C grep -q "[^[:print:][:space:]]" "$BIN/sabha-nightly" "$0"'

if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: sabha-nightly window, blocked and waiting rows, clean output, bad input, rerun, kept edit, lock, usage"
