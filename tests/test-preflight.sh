#!/usr/bin/env bash
# bin/sabha-preflight: the 4 Nov brief 092 replayed with fakes (empty password, no session, a 402 tenant, a missing
# .env.local) reports all four failures in one run, exit 1; a healthy setup passes with exit 0; --out writes the
# report; a secret value is never printed. No network: the status call is a fake command. Run: tests/test-preflight.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-preflight.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
P() { bash "$BIN/sabha-preflight" "$@"; }

o=$(SEED_PW="" P --var SEED_PW --session "$dir/state.json" --status-cmd 'echo 402' --file "$dir/wt/.env.local" --out "$dir/report.txt"); rc=$?
[[ $rc -eq 1 ]] || fail "092 replay must exit 1, rc=$rc: $o"
for want in 'FAIL  credential: SEED_PW' 'FAIL  session: no session file' 'FAIL  account blocked: status call returned 402' 'FAIL  file: .*\.env\.local is missing' 'preflight: 4 fail'; do
  grep -q "$want" <<<"$o" || fail "092 replay must report '$want' in the same run: $o"
done
[[ $(grep -c '^      human: ' <<<"$o") -eq 4 ]] || fail "every failure needs one human action line: $o"
cmp -s <(printf '%s\n' "$o") "$dir/report.txt" || fail "--out must hold the same report"

o=$(P --status-cmd 'echo 401'); [[ $? -eq 1 ]] && grep -q 'session rejected' <<<"$o" || fail "401 must read as a rejected session: $o"
o=$(P --server no --headless no); [[ $? -eq 1 ]] && grep -q 'preflight: 2 fail' <<<"$o" || fail "server no and headless no are two failures: $o"

mkdir -p "$dir/wt"; : >"$dir/wt/.env.local"; echo '{"cookies":[1]}' >"$dir/state.json"
o=$(SEED_PW=hunter2-secret P --var SEED_PW --session "$dir/state.json" --status-cmd 'echo 200' --file "$dir/wt/.env.local"); rc=$?
[[ $rc -eq 0 ]] && grep -q 'preflight: 0 fail' <<<"$o" || fail "a healthy setup must pass, rc=$rc: $o"
grep -q 'hunter2-secret\|cookies' <<<"$o" && fail "a secret or the session contents must never be printed: $o"

P --bogus x 2>/dev/null; [[ $? -eq 2 ]] || fail "an unknown option is a usage error (2)"
P --server maybe 2>/dev/null; [[ $? -eq 2 ]] || fail "--server takes yes|no only (2)"
P --headless 1 2>/dev/null; [[ $? -eq 2 ]] || fail "--headless takes yes|no only (2)"
echo "ok: 092 replay reports password, session, 402 and env file at once; 401; server/headless; healthy pass; no secret printed"
