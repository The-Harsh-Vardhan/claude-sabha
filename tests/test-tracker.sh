#!/usr/bin/env bash
# Tracker kit: header-only templates, xlsx tabs and formulas, html page from fixtures, sheet-sync dry run, repos-export.
# No network. The xlsx part needs openpyxl in the repo-local .venv and says SKIP when it is missing.
# Run: tests/test-tracker.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-tracker.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

for n in tracker progress agents for-me inbox repos; do
  f="$here/tracker/templates/$n.csv"
  [ "$(wc -l < "$f" | tr -d ' ')" = 1 ] || fail "$n.csv is not header-only"
done
echo "ok: templates header-only"

py="$here/.venv/bin/python"
[ -x "$py" ] || py=python3
if "$py" -c 'import openpyxl' 2>/dev/null; then
  "$py" "$here/tracker/build-xlsx.py" "$dir/t.xlsx" >/dev/null || fail "build-xlsx"
  "$py" - "$dir/t.xlsx" <<'P' || fail "xlsx content"
import sys
from openpyxl import load_workbook
wb = load_workbook(sys.argv[1])
assert wb.sheetnames == ["Dashboard", "Tasks", "Progress", "Agents", "Repos", "Agent inboxes", "Decisions", "Inbox"], wb.sheetnames
t = wb["Tasks"]
assert [c.value for c in t[1]][:3] == ["ID", "Parent", "Task"] and t.max_row == 1, t.max_row
vals = [dv.formula1 for dv in t.data_validations.dataValidation]
assert any("P0,P1,P2,P3" in v for v in vals) and any("Done" in v for v in vals), vals
d = wb["Dashboard"]
assert d["B4"].value.startswith("=COUNTIF(Tasks!") and d["E4"].value.startswith("=COUNTIF(Tasks!"), (d["B4"].value, d["E4"].value)
P
  echo "ok: xlsx 8 tabs, validations, COUNTIF formulas"
else
  echo "SKIP: xlsx (no openpyxl; uv venv .venv && uv pip install --python .venv/bin/python openpyxl)"
fi

mkdir "$dir/csv"
cp "$here"/tracker/templates/*.csv "$dir/csv/"
printf 'ID,Parent,Task,Area,Who acts,Priority,Deadline,Status,Next action,Where / notes,Updated\nH1,,<script>alert(1)</script>,x,me,P0,,Done,,,\n' > "$dir/csv/tracker.csv"
python3 "$here/tracker/build-html.py" "$dir/csv" "$dir/out.html" >/dev/null || fail "build-html"
grep -q '&lt;script&gt;alert(1)' "$dir/out.html" || fail "html escape"
grep -q '<script>alert' "$dir/out.html" && fail "html unescaped cell"
grep -q 'Tasks (1)' "$dir/out.html" || fail "html tab count"
echo "ok: html builds from fixtures, cells escaped"

printf 'ID,Kind,Title,Explanation,Options,Recommended,Answer,Status,Owner,Created,Link/source\n1,question,a,b,c,A,,open,V,t,\n' > "$dir/csv/for-me.csv"
out=$(SABHA_CONFIG_DIR="$dir/cfg" SABHA_CONF=/nonexistent python3 "$here/bin/sabha-sheet" sync --dry-run --csv-dir "$dir/csv") || fail "sync dry run"
printf '%s\n' "$out" | grep -q "Tasks!A2:K" || fail "Tasks range"
printf '%s\n' "$out" | grep -q "'Agent inboxes'!A2:H" || fail "inbox range"
printf '%s\n' "$out" | grep -q "Decisions!H2:K2" || fail "Decisions keeps G"
printf '%s\n' "$out" | grep -q "Decisions!G" && fail "Decisions wrote column G"
[ ! -e "$dir/cfg" ] || fail "dry run wrote state"
echo "ok: sheet-sync dry run (ranges, Decisions skips G, no state written)"

git init -q "$dir/r" && git -C "$dir/r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || fail "git init"
(cd "$dir" && WS="$dir" REPOS="r:r:main" OUT="$dir/repos.csv" python3 "$here/tracker/repos-export.py" >/dev/null) || fail "repos-export"
[ "$(wc -l < "$dir/repos.csv" | tr -d ' ')" = 2 ] || fail "repos.csv rows"
echo "ok: repos-export parameterised"
echo "PASS: tracker"
