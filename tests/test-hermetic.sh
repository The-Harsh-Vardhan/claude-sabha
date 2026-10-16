#!/usr/bin/env bash
# A test run cannot reach a real herdr: with SABHA_TEST=1 and any herdr on PATH that is not SABHA_HERDR_BIN, sabha-up
# and sabha-nudge refuse and call nothing; with the fake they work. "Real" here is a stand-in that logs every call;
# the true herdr binary and its socket are never used. Run: tests/test-hermetic.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-hermetic.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/real" "$dir/impl" "$dir/ws" "$dir/stubs" "$dir/fh"
printf '#!/bin/sh\necho "REAL $*" >>"$REAL_LOG"\n' > "$dir/real/herdr"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
chmod +x "$dir/real/herdr" "$dir/stubs/claude"
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; } > "$dir/sabha.conf"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt REAL_LOG=$dir/real.log FAKE_HERDR_LOG=$dir/fake.log FAKE_HERDR_DIR=$dir/fh
: > "$REAL_LOG"; : > "$FAKE_HERDR_LOG"
unset SABHA_BACKEND SABHA_PLAN SABHA_PANES SABHA_REMOTE HERDR_ENV
good=$PATH

out=$(PATH=$dir/real:$dir/stubs:$good "$SH" "$BIN/sabha-up.sh" --plan pro 2>&1); rc=$?
check "SABHA_TEST=1 + a herdr that is not SABHA_HERDR_BIN: sabha-up --plan pro refuses" '(( rc != 0 )) && grep -q "refusing to touch a real herdr" <<<"$out"'
check "...and the other herdr was never called" '[[ ! -s $REAL_LOG ]]'
out=$(PATH=$dir/real:$dir/stubs:$good "$SH" "$BIN/sabha-nudge" Arjun "x" 2>&1); rc=$?
check "sabha-nudge refuses the same way and calls nothing" '(( rc != 0 )) && [[ ! -s $REAL_LOG ]]'
out=$(SABHA_HERDR_BIN= PATH=$dir/stubs:$good "$SH" "$BIN/sabha-up.sh" --plan pro 2>&1); rc=$?
check "SABHA_HERDR_BIN unset or empty: refuses" '(( rc != 0 )) && grep -q "refusing" <<<"$out"'

out=$(PATH=$dir/stubs:$good "$SH" "$BIN/sabha-up.sh" --plan pro 2>&1); rc=$?
check "with the fake (tests/hermetic-bin/herdr) sabha-up --plan pro works" '(( rc == 0 )) && grep -q "^workspace create" "$FAKE_HERDR_LOG"'
check "...and the other herdr was still never called" '[[ ! -s $REAL_LOG ]]'
out=$(SABHA_TEST= PATH=$dir/real:$dir/stubs:$good "$SH" "$BIN/sabha-up.sh" --plan pro 2>&1)
check "outside tests (SABHA_TEST unset) the guard does nothing" '[[ -s $REAL_LOG ]]'

# every test sources hermetic.sh, so a new test cannot forget the guard (this one and test-leak are exempt)
missing=""
for t in "$ROOT"/tests/test-*.sh; do
  case $(basename "$t") in test-hermetic.sh|test-leak.sh) continue ;; esac
  grep -q 'hermetic\.sh' "$t" || missing="$missing $(basename "$t")"
done
check "every tests/test-*.sh sources hermetic.sh (missing:${missing:- none})" '[[ -z $missing ]]'

(( fails == 0 )) && { echo "ok: a test run cannot reach a herdr other than the fake"; exit 0; }
echo "$fails check(s) failed"; exit 1
