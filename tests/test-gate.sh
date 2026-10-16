#!/usr/bin/env bash
# bin/sabha-gate: ACCEPT needed, an unanswered BREAK/BLOCK shuts the gate, answers open it, --brief reads gate:.
# Run: tests/test-gate.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-gate.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
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
printf 'verdict: BREAK 0\n' > z-be.md
want 1 "BREAK 0 never opens the gate" t-review.md z-be.md
printf 'verdict: BLOCK 0\n' > z-bl.md
want 1 "BLOCK 0 never opens the gate" t-review.md z-bl.md
printf 'verdict: BREAK 2x\n' > z-x.md
want 1 "BREAK 2x is unreadable" t-review.md z-x.md
printf 'gate: t-review.md, t-sec.md, t-be.md\n\nbody\n' > brief.md
want 0 "--brief" --brief brief.md
printf 'gate: t-review.md, t-scope.md\n' > brief2.md
want 1 "--brief shut" --brief brief2.md
# newer wins: the last verdict line is current; answers older than the verdict are stale
printf 'verdict: ACCEPT\nnotes\nverdict: BREAK 1\n' > n-review.md
want 1 "ACCEPT then a newer BREAK in the same reviewer file shuts the gate" n-review.md t-sec.md
printf 'verdict: BREAK 1\nverdict: ACCEPT\n' > n2-review.md
want 0 "BREAK then a newer ACCEPT opens it" n2-review.md t-sec.md
printf 'verdict: BREAK 1\n' > m-be.md; printf 'FIXED: x in abc\n' > m-be-answer.md
touch -t 202001010000 m-be.md; touch -t 202001020000 m-be-answer.md
want 0 "BREAK then a newer FIXED answer opens it" t-review.md m-be.md
touch -t 202001030000 m-be.md
want 1 "a verdict newer than its answers reopens the finding" t-review.md m-be.md
mkdir sub && cp t-review.md t-sec.md sub/
want 0 "-C dir" -C sub t-review.md t-sec.md
echo "ok: newest verdict wins; gate needs ACCEPT, unanswered BREAK/BLOCK shut it, REFUTED/FIXED answers open it, --brief and -C work"
