#!/usr/bin/env bash
# bin/sabha-rfc-check: a clean RFC passes; each defect class fails with its own message.
# Run: tests/test-rfc-check.sh
set -u
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rfc.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir"' EXIT
cd "$dir" || exit 1
S="Summary,Problem,Design"
good() {
  printf '# Title\n\n## Summary\nWe do it. See [design](#design) and [notes](notes.md).\n\n## Problem\nIt hurts.\n\n## Design\nLike so.\n\n### Detail\nMore.\n' > "$1"
}
: > notes.md
good ok.md
out=$("$bin/sabha-rfc-check" ok.md --sections "$S") || { echo "FAIL: clean rfc rejected: $out"; exit 1; }
expect() { # expect <label> <regex> <file>
  local out; out=$("$bin/sabha-rfc-check" "$3" --sections "$S"); local r=$?
  [[ $r -eq 1 ]] && grep -q -E "$2" <<<"$out" || { echo "FAIL: $1 (rc $r): $out"; exit 1; }
}
good a.md; sed -i.bak '/^## Problem/,/^It hurts/d' a.md; expect "missing section" 'missing section: Problem' a.md
good b.md; sed -i.bak 's/^It hurts\.$//' b.md; expect "empty section" 'empty section: Problem' b.md
good c.md; echo 'TBD later' >> c.md; expect "placeholder" 'placeholder' c.md
good d.md; echo '[x](#nowhere)' >> d.md; expect "dead anchor" 'dead anchor: #nowhere' d.md
good e.md; echo '[x](gone.md)' >> e.md; expect "dead file link" 'dead file link: gone.md' e.md
good f.md; printf 'caf\303\251\n' >> f.md; expect "non-ASCII" 'non-ASCII' f.md
good g.md; echo '[web](https://example.com/x)' >> g.md
"$bin/sabha-rfc-check" g.md --sections "$S" >/dev/null || { echo "FAIL: http link wrongly rejected"; exit 1; }
[[ $("$bin/sabha-rfc-check" 2>/dev/null; echo $?) == 2 ]] || { echo "FAIL: no args should exit 2"; exit 1; }
echo "ok: clean rfc passes; missing/empty section, placeholder, dead anchor, dead file link, non-ASCII each fail"
