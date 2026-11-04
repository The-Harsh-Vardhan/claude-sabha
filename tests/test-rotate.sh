#!/usr/bin/env bash
# bin/sabha-rotate on fixtures: dry run writes nothing; --apply keeps top block + N entries, archives the rest with a
# RESTORE line that rebuilds the original byte for byte; small and entry-less files stay; mixed entry shapes parse.
# Run: tests/test-rotate.sh   (bash 3.2 and 5)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rotate.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }
R() { "${BASH:-bash}" "$ROOT/bin/sabha-rotate" "$@"; }
S=$dir/status
mkdir -p "$S"
{ echo "preamble"; for i in $(seq 30 -1 1); do echo "UPDATE $i (x): body $i"; echo; done; } >"$S/yud.md"
{ echo "Current: relay"; echo "Continue this work"; echo "# HANDOFF (a)"; echo "Next: x"; echo "---"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "Idle: by design ($i)"; echo "Task: t$i"; echo "---"; done; } >"$S/vid.md"
{ echo "Current: small"; echo "UPDATE 2"; echo "UPDATE 1"; } >"$S/small.md"
echo "no entries here" >"$S/notes.md"
cp -R "$S" "$dir/orig"

o=$(R "$S") || fail "dry run rc: $o"
diff -r "$S" "$dir/orig" >/dev/null || fail "dry run changed files"
[[ ! -d $S/.bak ]] || fail "dry run made .bak"
echo "$o" | grep -q 'yud.md: .* move 19 entries' || fail "yud dry line: $o"
echo "$o" | grep -q 'vid.md: .* move 3 entries' || fail "vid dry line: $o"
echo "$o" | grep -q 'small.md\|notes.md' && fail "small/notes listed: $o"
echo "$o" | grep -q '(dry): 2 file(s)' || fail "summary: $o"
ok "dry run writes nothing, counts right"

o=$(R --apply "$S") || fail "apply rc: $o"
[[ $(grep -c '^UPDATE ' "$S/yud.md") -eq 11 ]] || fail "yud keeps 11"
head -1 "$S/yud.md" | grep -q preamble || fail "preamble kept"
grep -q '^UPDATE 20 ' "$S/yud.md" && ! grep -q '^UPDATE 19 ' "$S/yud.md" || fail "yud cut at 19"
grep -q '^Idle: by design (9)' "$S/vid.md" && ! grep -q '(10)' "$S/vid.md" || fail "vid cut"
cmp -s "$S/small.md" "$dir/orig/small.md" && cmp -s "$S/notes.md" "$dir/orig/notes.md" || fail "small/notes touched"
[[ $(ls "$S/.bak" | grep -c '\.md$') -eq 2 ]] || fail "two archives"
[[ $(wc -l <"$S/.bak/RESTORE.txt") -eq 2 ]] || fail "two RESTORE lines"
ls "$S" | grep -q tmp && fail "tmp left"
ok "apply keeps top + 10, archives the rest"

o=$(R --apply "$S") || fail "second apply rc"
echo "$o" | grep -q '0 file(s)' || fail "second apply not a no-op: $o"
ok "second apply is a no-op"

while read -r line; do eval "$line"; done <"$S/.bak/RESTORE.txt"
cmp -s "$S/yud.md" "$dir/orig/yud.md" && cmp -s "$S/vid.md" "$dir/orig/vid.md" || fail "restore not byte-identical"
ok "RESTORE lines rebuild the originals"

{ for i in 1 2 3 4; do echo "UPDATE $i"; done; } >"$dir/one.md"
o=$(R --keep 1 --apply "$dir/one.md") || fail "file arg rc"
[[ $(wc -l <"$dir/one.md") -eq 2 ]] || fail "keep 1 on a file"
R --keep x >/dev/null 2>&1 && fail "bad --keep accepted"
R --bogus >/dev/null 2>&1 && fail "bad flag accepted"
ok "file arg, --keep, bad flags"
echo "ok: all checks pass"
