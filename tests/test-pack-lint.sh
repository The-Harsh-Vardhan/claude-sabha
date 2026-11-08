#!/usr/bin/env bash
# bin/sabha-pack-lint: a clean pack passes; each defect class fails with its own message; both CLI spellings work.
# Run: tests/test-pack-lint.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-packlint.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
cd "$dir" || exit 1
lint() { "$bin/sabha-pack-lint" "$@"; }
fail() { echo "FAIL: $*"; exit 1; }

cat > ok.md <<'EOF'
# Pack

- Branch: feat/x, sha abc1234 (see #12 and the "..." in prose are fine)
    - nested list text that is indented stays out

Commands for the owner:

    cd /abs/one && git fetch origin main:refs/remotes/origin/main
    cd /abs/one && gh pr create --title "fix #12: the thing" --body-file /abs/body.md

```
cd /abs/two && git status
cd "/abs/with space" && ls \
  -la
```

```json
{"not": "a command ... # nor a cd"}
```
EOF
out=$(lint ok.md) || fail "clean pack rejected: $out"
grep -q '^ok: 5 command lines clean$' <<<"$out" || fail "unexpected summary: $out"

expect() { # expect <label> <regex> <file>
  local out r; out=$(lint "$3"); r=$?
  [[ $r -eq 1 ]] && grep -q -E "$2" <<<"$out" || fail "$1 (rc $r): $out"
}
printf '    cd /abs && git push # note\n' > a.md;            expect "inline comment" ':1: inline # comment' a.md
printf '    cd /abs && git push origin ...\n' > b.md;        expect "three dots" ':1: elision' b.md
printf '    cd /abs && git push origin \342\200\246\n' > c.md; expect "ellipsis char" ':1: elision' c.md
printf '    cd /abs && echo a \342\206\222 b\n' > d.md;      expect "non-ASCII arrow" ':1: non-ASCII' d.md
printf '    git push origin main\n' > e.md;                  expect "no cd prefix" ":1: no 'cd /absolute" e.md
printf '    cd relative/dir && ls\n' > f.md;                 expect "relative cd" ":1: no 'cd /absolute" f.md
printf '    cd ~/x && ls\n' > g.md;                          expect "tilde cd" ":1: no 'cd /absolute" g.md
printf '    cd /abs\n' > h.md;                               expect "cd alone" ":1: no 'cd /absolute" h.md
printf '# comment line\n\n```sh\n# a comment\n```\n' > i.md;  expect "comment line in fence" ':4: inline # comment' i.md
printf '```bash\ncd /abs && ls\ngit status\n```\n' > j.md;   expect "second line of a block" ':3: no .cd /absolute' j.md

out=$(lint ok.md a.md); r=$?
[[ $r -eq 1 ]] && grep -q '^a.md:1:' <<<"$out" && ! grep -q '^ok.md' <<<"$out" || fail "two files (rc $r): $out"
lint missing.md 2>/dev/null; [[ $? -eq 2 ]] || fail "unreadable file should exit 2"
lint 2>/dev/null; [[ $? -eq 2 ]] || fail "no args should exit 2"

out=$("$bin/sabha" pack lint a.md); r=$?
[[ $r -eq 1 ]] && grep -q 'inline #' <<<"$out" || fail "sabha pack lint (rc $r): $out"
out=$("$bin/sabha" pack-lint ok.md) || fail "sabha pack-lint: $out"
"$bin/sabha" pack other >/dev/null 2>&1; [[ $? -eq 1 ]] || fail "sabha pack without lint should exit 1"
echo "ok: clean pack passes; inline comment, elision (3 dots and ellipsis), non-ASCII, missing or relative cd each fail; sabha pack lint and pack-lint dispatch"
