#!/usr/bin/env bash
# sabha-for-me --csv: agents.csv and for-me.csv, RFC 4180, one row per role and per item, inbox count skips .done/.cancel.
# Run: tests/test-forme-csv.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-csv.XXXXXX") || exit 1
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/impl/status/context" "$dir/impl/inbox/Zed"
echo 42 > "$dir/impl/status/context/zed.txt"
printf 'Current: build, "quoted"\nNext: n\n' > "$dir/impl/status/zed.md"
touch "$dir/impl/inbox/Zed/001-v-a.md" "$dir/impl/inbox/Zed/002-v-b.md" "$dir/impl/inbox/Zed/003-v-c.md" "$dir/impl/inbox/Zed/001.done" "$dir/impl/inbox/Zed/002.cancel"
printf 'SABHA_IMPL=%s/impl\nSABHA_ROSTER="Zed:sonnet:low:lazy,gate Old:opus"\n' "$dir" > "$dir/sabha.conf"
printf -- '---\nid: 1\nutc: 2026-10-14T09:00:00Z\nowner: V\ntitle: pick, one\nq: Which?\nexplain: why\nopta: x | c\noptb: y\nrec: b\n---\nid: 2\nutc: 2026-10-14T09:00:00Z\nowner: V\ntitle: plain\n' > "$dir/impl/for-me.items"
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" --csv "$dir/out" || { echo "FAIL: --csv run"; exit 1; }
python3 - "$dir/out" <<'P' || { echo "FAIL: csv content"; exit 1; }
import csv, sys
rd = lambda n: list(csv.reader(open(sys.argv[1] + "/" + n, newline="", encoding="ascii")))
a, f = rd("agents.csv"), rd("for-me.csv")
assert len(a) == 3 and len({len(r) for r in a}) == 1, a
assert len(f) == 3 and len({len(r) for r in f}) == 1, f
z = dict(zip(a[0], a[1]))
assert z["Name"] == "Zed" and z["Flags"] == "lazy/gate" and z["Context %"] == "42" and z["Over 30%"] == "yes", z
assert z["Inbox open"] == "1" and z["Current task"] == 'build, "quoted"', z
q = dict(zip(f[0], f[1]))
assert q["Options"] == "A: x | B: y" and q["Recommended"] == "B" and q["Kind"] == "question" and q["Title"] == "pick, one", q
P
echo "ok: csv export"
