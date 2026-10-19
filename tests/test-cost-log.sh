#!/usr/bin/env bash
# sabha_cost_log line shape (one tab-separated line per event), an unwritable dir returns 0, and the sheet dispatch
# says "not installed" (rc 1) when bin/sabha-sheet is absent (a temp copy of bin/, no real file touched).
# Run: tests/test-cost-log.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-cost.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
# shellcheck source=../bin/sabha-lib.sh
. "$bin/sabha-lib.sh"

SABHA_IMPL=$dir/impl
mkdir -p "$SABHA_IMPL/status/context"; echo 41.5 >"$SABHA_IMPL/status/context/builderprecise.txt"
sabha_cost_log BuilderPrecise sonnet "brief 004 exit 0"
sabha_cost_log BuilderPrecise sonnet $'brief 005\ttab\nnewline'
f=$SABHA_IMPL/status/cost-log.tsv
[[ $(wc -l <"$f" | tr -d ' ') == 2 ]] || fail "two events must be two lines: $(cat "$f")"
head -n 1 "$f" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z	BuilderPrecise	sonnet	41.5	brief 004 exit 0$' || fail "line shape: $(head -n 1 "$f")"
[[ $(tail -n 1 "$f" | awk -F'\t' '{print NF}') == 5 ]] || fail "tab or newline in the event broke the columns"
sabha_cost_log Nobody haiku x; tail -n 1 "$f" | awk -F'\t' '$4 == "-"' | grep -q . || fail "unknown ctx should be -"

: >"$dir/file"; SABHA_IMPL=$dir/file
sabha_cost_log BuilderPrecise sonnet x; [[ $? -eq 0 ]] || fail "unwritable dir must return 0"

mkdir -p "$dir/tree"; cp -R "$bin" "$dir/tree/bin"; rm -f "$dir/tree/bin/sabha-sheet"
out=$("$dir/tree/bin/sabha" sheet-auth 2>&1); rc=$?
[[ $rc -eq 1 && $out == *"not installed"* ]] || fail "sheet-auth without bin/sabha-sheet: rc $rc: $out"
echo "ok: cost log one tab-separated line per event, unwritable dir returns 0, sheet dispatch says not installed (rc 1)"
