#!/usr/bin/env bash
# bin/sabha-rotate on fixtures: dry run writes nothing; --apply keeps top block + N entries in place (inode and mode
# kept), archives the full original with a RESTORE line that rebuilds it byte for byte; small, empty and entry-less
# files stay; headers inside a body are not cuts; a file changed mid-run is skipped; odd paths work.
# Run: tests/test-rotate.sh   (bash 3.2 and 5)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rotate.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }
R() { "${BASH:-bash}" "$ROOT/bin/sabha-rotate" "$@"; }
inode() { ls -i "$1" | awk '{print $1}'; }
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
S=$dir/status
mkdir -p "$S"
{ echo "preamble"; echo; for i in $(seq 30 -1 1); do echo "UPDATE $i (x): body $i"; echo "Current: in body"; echo "UPDATE 99 in body"; echo; done; } >"$S/yud.md"
{ echo "Current: relay"; echo "Continue this work"; echo "---"; echo "# HANDOFF (a)"; echo "Next: x"; echo "---"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "Idle: by design ($i)"; echo "Task: t$i"; echo "---"; done; } >"$S/vid.md"
{ echo "Current: small"; echo "UPDATE 2"; echo "UPDATE 1"; } >"$S/small.md"
echo "no entries here" >"$S/notes.md"
: >"$S/empty.md"
chmod 600 "$S/yud.md"
cp -Rp "$S" "$dir/orig"
ino=$(inode "$S/yud.md")

o=$(R "$S") || fail "dry run rc: $o"
diff -r "$S" "$dir/orig" >/dev/null || fail "dry run changed files"
[[ ! -d $S/.bak ]] || fail "dry run made .bak"
echo "$o" | grep -q 'yud.md: .* move 19 entries' || fail "yud dry line: $o"
echo "$o" | grep -q 'vid.md: .* move 3 entries' || fail "vid dry line: $o"
echo "$o" | grep -q 'small.md\|notes.md\|empty.md' && fail "small/notes/empty listed: $o"
echo "$o" | grep -q '(dry): 2 file(s)' || fail "summary: $o"
ok "dry run writes nothing, counts right, body headers ignored"

o=$(R --apply "$S") || fail "apply rc: $o"
[[ $(grep -c '^UPDATE [0-9]* (x)' "$S/yud.md") -eq 11 ]] || fail "yud keeps 11"
head -1 "$S/yud.md" | grep -q preamble || fail "preamble kept"
grep -q '^UPDATE 20 ' "$S/yud.md" && ! grep -q '^UPDATE 19 ' "$S/yud.md" || fail "yud cut at 19"
n=$(grep -n '^UPDATE 19 ' "$dir/orig/yud.md" | cut -d: -f1)
head -n $((n - 1)) "$dir/orig/yud.md" | cmp -s - "$S/yud.md" || fail "yud content is not head + kept entries"
[[ $(inode "$S/yud.md") == "$ino" ]] || fail "inode changed"
[[ $(perm "$S/yud.md") == 600 ]] || fail "mode not kept: $(perm "$S/yud.md")"
grep -q '^Idle: by design (9)' "$S/vid.md" && ! grep -q '(10)' "$S/vid.md" || fail "vid cut"
for x in small notes empty; do cmp -s "$S/$x.md" "$dir/orig/$x.md" || fail "$x touched"; done
[[ $(ls "$S/.bak" | grep -c '\.md$') -eq 2 ]] || fail "two archives"
for a in "$S"/.bak/yud-*.md; do cmp -s "$a" "$dir/orig/yud.md" || fail "archive is not the full original"; done
[[ $(wc -l <"$S/.bak/RESTORE.txt") -eq 2 ]] || fail "two RESTORE lines"
ls -a "$S" "$S/.bak" | grep -q keep && fail "tmp left"
ok "apply keeps top + 10 in place (inode, mode), archives the full original"

o=$(R --apply "$S") || fail "second apply rc"
echo "$o" | grep -q '0 file(s)' || fail "second apply not a no-op: $o"
ok "second apply is a no-op"

while read -r line; do eval "$line"; done <"$S/.bak/RESTORE.txt"
cmp -s "$S/yud.md" "$dir/orig/yud.md" && cmp -s "$S/vid.md" "$dir/orig/vid.md" || fail "restore not byte-identical"
ok "RESTORE lines rebuild the originals"

{ for i in 1 2 3 4; do echo "UPDATE $i"; echo; done; } >"$dir/one.md"
o=$(R --keep 1 --apply "$dir/one.md") || fail "file arg rc"
[[ $(wc -l <"$dir/one.md") -eq 4 ]] || fail "keep 1 on a file"
R --keep x >/dev/null 2>&1 && fail "bad --keep accepted"
R --bogus >/dev/null 2>&1 && fail "bad flag accepted"
ok "file arg, --keep, bad flags"

{ for i in 1 2 3 4; do echo "UPDATE $i"; echo; done; } >"$dir/busy.md"
cp "$dir/busy.md" "$dir/busy.orig"
o=$(SABHA_ROTATE_TEST_HOOK='echo late >>"$f"' R --keep 1 --apply "$dir/busy.md" 2>&1) && fail "changed file rc 0"
echo "$o" | grep -q 'changed while rotating, skipped' || fail "skip message: $o"
{ cat "$dir/busy.orig"; echo late; } | cmp -s - "$dir/busy.md" || fail "changed file was rewritten"
[[ $(ls "$dir/.bak" | grep -c busy) -eq 0 ]] || fail "archive left for skipped file"
ok "file changed between copy and write is skipped"

for d in "$dir/with space" "$dir/it's"; do
  mkdir -p "$d"; { for i in 1 2 3 4; do echo "UPDATE $i"; echo; done; } >"$d/r o.md"; cp "$d/r o.md" "$d/orig"
  R --keep 1 --apply "$d" >/dev/null || fail "odd path apply: $d"
  [[ $(wc -l <"$d/r o.md") -eq 4 ]] || fail "odd path cut: $d"
  while read -r line; do eval "$line"; done <"$d/.bak/RESTORE.txt"
  cmp -s "$d/r o.md" "$d/orig" || fail "odd path restore: $d"
done
ok "paths with a space and an apostrophe rotate and restore"
echo "ok: all checks pass"
