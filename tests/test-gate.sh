#!/usr/bin/env bash
# bin/sabha-gate: ACCEPT needed, an unanswered BREAK/BLOCK shuts the gate, answers open it, --brief reads gate:.
# Run: tests/test-gate.sh
set -u
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-gate.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir"' EXIT
cd "$dir" || exit 1
g() { "$bin/sabha-gate" "$@" >/dev/null; }
want() { # want <rc> <label> <args...>
  local w=$1 l=$2; shift 2; g "$@"; local r=$?
  [[ $r -eq $w ]] || { echo "FAIL: $l (rc $r, wanted $w)"; "$bin/sabha-gate" "$@"; exit 1; }
}
printf 'verdict: ACCEPT\n' > t-review.md
printf 'verdict: NO BREAK\n' > t-sec.md
printf 'verdict: BREAK 2\nfinding a\nfinding b\n' > t-be.md
want 2 "no args"
want 0 "accept + no break" t-review.md t-sec.md
want 1 "unanswered BREAK" t-review.md t-sec.md t-be.md
printf 'REFUTED: a by test x\n' > t-be-answer.md
want 1 "one of two answered" t-review.md t-be.md
printf 'FIXED: b in abc123\n' >> t-be-answer.md
want 0 "both answered" t-review.md t-sec.md t-be.md
printf 'verdict: REVISE\n' > r-review.md
want 1 "reviewer not ACCEPT" r-review.md t-sec.md
want 1 "no reviewer file at all" t-sec.md
want 1 "missing file" t-review.md nope-fe.md
printf 'verdict: BLOCK 1\n' > t-scope.md
want 1 "unanswered BLOCK" t-review.md t-scope.md
printf 'gate: t-review.md, t-sec.md, t-be.md\n\nbody\n' > brief.md
want 0 "--brief" --brief brief.md
printf 'gate: t-review.md, t-scope.md\n' > brief2.md
want 1 "--brief shut" --brief brief2.md
mkdir sub && cp t-review.md t-sec.md sub/
want 0 "-C dir" -C sub t-review.md t-sec.md
echo "ok: gate needs ACCEPT, unanswered BREAK/BLOCK shut it, REFUTED/FIXED answers open it, --brief and -C work"
