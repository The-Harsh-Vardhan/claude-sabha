#!/usr/bin/env bash
# herdr session restore (win B): herdr may resume a Claude conversation after a herdr crash (`herdr integration
# install claude`), but sabha itself never resumes one: the 30 percent restart is always a fresh session. Fails when
# a claude start line in sabha-up.sh, sabha-loop or sabha-run gains --resume or --continue, or when the README stops
# naming the install, status and uninstall commands. Run: tests/test-restore.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-restore.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="V:opus:medium Y:opus:medium A:sonnet:low"\n' "$dir" "$dir" >"$dir/sabha.conf"
out=$(SABHA_CONF=$dir/sabha.conf bash "$ROOT/bin/sabha-up.sh" --print A) || fail "sabha-up.sh --print A exited $?"
grep -q '^claude ' <<<"$out" || grep -q 'claude -n' <<<"$out" || fail "--print A shows no claude line: $out"
! grep -q -E -- '--resume|--continue|(^| )-c( |$)|(^| )-r( |$)' <<<"$out" || fail "the restart line resumes: $out"
! grep -n -E 'claude .*(--resume|--continue)' "$ROOT/bin/sabha-up.sh" "$ROOT/bin/sabha-loop" "$ROOT/bin/sabha-run" || fail "a claude start resumes"
for c in 'herdr integration status' 'herdr integration install claude' 'herdr integration uninstall claude'; do
  grep -qF "$c" "$ROOT/README.md" || fail "README should name: $c"
done
echo "ok: sabha never resumes a session; README names the herdr integration commands"
