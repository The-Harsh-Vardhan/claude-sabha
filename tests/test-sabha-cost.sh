#!/usr/bin/env bash
# bin/sabha-cost on a fake projects dir: tokens per role and day, a repeated message id counted once, <synthetic>
# skipped, role from the roster or "You are", cache-read share, cost-log.tsv events, --since, usage exits.
# Run: tests/test-sabha-cost.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-costtool.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
p=$dir/proj; mkdir -p "$p"
u() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$1" "$2"; }
a() { printf '{"type":"assistant","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$@"; }
{ u 2026-11-03T10:00:00Z "You are another Arjun instance"; a m1 opus 10 90 900 5; a m1 opus 10 90 900 5; a m2 opus 0 0 1000 7
  a s1 '<synthetic>' 99 99 99 99; echo 'not json'; } >"$p/a.jsonl"
{ u 2026-11-03T11:00:00Z "brief for Karna: run the suite"; a k1 sonnet 100 0 0 1; } >"$p/b.jsonl"
{ u 2026-11-04T09:00:00Z "You are Arjun"; a m3 opus 0 0 100 2; } >"$p/c.jsonl"
u 2026-11-04T09:00:00Z "no reply" >"$p/d.jsonl"; echo ignored >"$p/e.txt"
printf '2026-11-03T12:00:00Z\tArjun\topus\t40\tbrief 1\n2026-11-03T13:00:00Z\tArjun\topus\t41\tbrief 2\n' >"$dir/log.tsv"

out=$("$bin/sabha-cost" --projects "$p" --roles "Arjun Karna" --log "$dir/log.tsv") || fail "rc $?: $out"
row() { grep -E "^$1	$2	" <<<"$out" || fail "no row $1 $2: $out"; }
[[ $(row 2026-11-03 Arjun) == "2026-11-03	Arjun	1	2	10	90	1900	12	95.0	2" ]] || fail "arjun 3 Nov: $(row 2026-11-03 Arjun)"
[[ $(row 2026-11-03 Karna) == "2026-11-03	Karna	1	1	100	0	0	1	0.0	0" ]] || fail "karna (roster name mid-prompt): $(row 2026-11-03 Karna)"
[[ $(row 2026-11-04 Arjun) == "2026-11-04	Arjun	1	1	0	0	100	2	100.0	0" ]] || fail "arjun 4 Nov: $(row 2026-11-04 Arjun)"
[[ $(grep -c . <<<"$out") == 5 ]] || fail "header + 3 rows + total, a session with no usage dropped: $out"
[[ $(tail -n 1 <<<"$out") == "total	-	3	4	110	90	2000	15	90.9	2" ]] || fail "total: $(tail -n 1 <<<"$out")"

out=$(SABHA_ROSTER="Karna:sonnet:low" "$bin/sabha-cost" --projects "$p" --since 2026-11-04) || fail "since rc $?"
[[ $(grep -c . <<<"$out") == 3 && $out == *"2026-11-04	Arjun	1	1	"* ]] || fail "--since, You-are fallback: $out"
out=$(SABHA_COST_PROJECTS=$p "$bin/sabha-cost" --roles x) || fail "env projects rc $?"
[[ $out == *"2026-11-03	-	1	1	100	"* ]] || fail "no role -> '-': $out"

"$bin/sabha-cost" --bogus >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "unknown flag must exit 2"
"$bin/sabha-cost" --projects "$dir/none" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "missing dir must exit 2"
echo "ok: sabha-cost tokens per role and day, ids once, synthetic skipped, read share, log events, --since, usage"
