#!/usr/bin/env bash
# shellcheck disable=SC2015,SC1091,SC2016
# bin/sabha-typography-check: every check finds its known fault in the fixtures, and a scratch mutant that removes the
# check makes that row fail. Also bad input, control characters, the browser path (stub runner, never a real browser).
# Run: tests/test-typography-check.sh   (PDF rows need the repo-local .venv; without it they are reported as NOT RUN)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
fx=$root/tests/fixtures/typography
tool=$root/tools/typography-check.py
work=$(mktemp -d "${TMPDIR:-/tmp}/sabha-typo-test.XXXXXX") || exit 2
[[ -d $work ]] || exit 2
trap 'rm -rf "$work" "$HERMETIC_FAKE_DIR"' EXIT
load5=$(uptime | sed -E 's/.*load averages?: *//' | awk '{gsub(",", " "); print int($2)}')
if [[ ${load5:-0} -gt 40 ]]; then echo "load5 $load5 is above 40: wait and retry"; exit 75; fi
PY=python3
have_pdf=0
if [[ -x $root/.venv/bin/python ]] && "$root/.venv/bin/python" -c 'import pdfminer' 2>/dev/null; then PY=$root/.venv/bin/python; have_pdf=1; fi
fails=0 passes=0
ok() { passes=$((passes + 1)); }
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }

typo() { "$PY" "$root/tools/typography-check.py" "$@"; }
expect_rc() { # expect_rc <label> <rc> <stderr regex> -- <args...>
  local label=$1 rc=$2 re=$3; shift 4
  local err got
  err=$(typo "$@" 2>&1 >/dev/null); got=$?
  if [[ $got -ne $rc ]]; then bad "$label: rc $got, wanted $rc ($err)"; return; fi
  if [[ -n $re ]] && ! grep -q -E -- "$re" <<<"$err"; then bad "$label: message lacks /$re/: $err"; return; fi
  if grep -q Traceback <<<"$err"; then bad "$label: traceback: $err"; return; fi
  ok
}

A=$fx/allow.json
mkdir -p "$work/out"

# ---- 1. one run per input, then every row against the real tool and against a mutant without that check ----
run_modes() { # run_modes <tool.py> <outprefix>
  local t=$1 o=$2
  [[ $have_pdf == 1 ]] && "$PY" "$t" "$fx/faulty.pdf" --allow "$A" > "$o.pdf" 2>&1
  [[ $have_pdf == 1 ]] && sed 's/"min_contrast"/"pdf_require_embedded": true, "min_contrast"/' "$A" > "$work/allow-embed.json" \
    && "$PY" "$t" "$fx/clean.pdf" --allow "$work/allow-embed.json" > "$o.pdfe" 2>&1
  "$PY" "$t" "$fx/faulty.html" --allow "$A" > "$o.htm" 2>&1
  "$PY" "$t" "$fx/computed-faulty.json" --allow "$A" > "$o.cmp" 2>&1
}
rows=(
  "pdf|FAMILY|Serif intruder" "pdf|SIZE|Off scale size" "pdf|WEIGHT|Bold weight" "pdf|COLOR|Red text"
  "pdf|CONTRAST|Pale grey text" "pdf|CONTRAST|Dark on dark" "pdf|WRAP|Runs off the page edge" "pdf|ROLE|Heading A"
  "pdfe|FALLBACK|Clean body text"
  "htm|FAMILY|\\.serif" "htm|FALLBACK|src file not found: fonts/Inter-400" "htm|FALLBACK|Roboto Mono is used but no @font-face"
  "htm|SIZE|\\.big" "htm|SIZE|style attribute #inl" "htm|WEIGHT|\\.heavy" "htm|COLOR|\\.red" "htm|CONTRAST|\\.pale"
  "htm|LINEHEIGHT|\\.tight" "htm|WRAP|\\.cut" "htm|ROLE|h1"
  "cmp|FAMILY|p\\.serif" "cmp|FALLBACK|declared face Roboto Mono did not load" "cmp|SIZE|p\\.big" "cmp|WEIGHT|p\\.heavy"
  "cmp|COLOR|p\\.red" "cmp|CONTRAST|p\\.pale" "cmp|LINEHEIGHT|p\\.tight" "cmp|WRAP|div\\.over" "cmp|WRAP|div\\.clip"
  "cmp|WRAP|div\\.ell" "cmp|WRAP|page" "cmp|ROLE|h2"
)
run_modes "$tool" "$work/out/real"
check_row() { # check_row <file-prefix> <row>  -> 0 when the finding line is present
  local tag=${2%%|*} rest=${2#*|}; local chk=${rest%%|*} pat=${rest#*|}
  [[ -f $1.$tag ]] && grep -q -E "^$chk \\| where: .*$pat" "$1.$tag"
}
skipped=0
for r in "${rows[@]}"; do
  tag=${r%%|*}
  if [[ ($tag == pdf || $tag == pdfe) && $have_pdf == 0 ]]; then skipped=$((skipped + 1)); continue; fi
  if check_row "$work/out/real" "$r"; then ok; else bad "row not found in the real output: $r"; fi
done
mutants=0
for c in FAMILY FALLBACK SIZE WEIGHT COLOR CONTRAST LINEHEIGHT WRAP ROLE; do
  "$PY" - "$tool" "$work/mut-$c.py" "$c" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
marker = "    def add(self, check, where, found, allowed=\"\"):\n"
assert marker in src
open(sys.argv[2], "w").write(src.replace(marker, marker + "        if check == %r:\n            return\n" % sys.argv[3]))
PYEOF
  run_modes "$work/mut-$c.py" "$work/out/mut-$c"
  for r in "${rows[@]}"; do
    rest=${r#*|}; [[ ${rest%%|*} == "$c" ]] || continue
    tag=${r%%|*}
    if [[ ($tag == pdf || $tag == pdfe) && $have_pdf == 0 ]]; then continue; fi
    if check_row "$work/out/mut-$c" "$r"; then bad "mutant without $c still passes row: $r"; else mutants=$((mutants + 1)); ok; fi
  done
done

# ---- 2. clean inputs pass ----
[[ $have_pdf == 1 ]] && { typo "$fx/clean.pdf" --allow "$A" >/dev/null 2>&1 && ok || bad "clean.pdf has findings"; }
typo "$fx/clean.html" --allow "$A" >/dev/null 2>&1 && ok || bad "clean.html has findings"
[[ $(typo "$fx/faulty.html" --allow "$A" >/dev/null 2>&1; echo $?) == 1 ]] && ok || bad "faulty.html should exit 1"

# ---- 3. bad input never crashes ----
expect_rc "missing file" 2 'cannot read' -- "$work/none.pdf" --allow "$A"
expect_rc "missing allow-list" 2 'cannot read' -- "$fx/clean.html" --allow "$work/none.json"
expect_rc "no allow-list at all" 2 'usage' -- "$fx/clean.html"
expect_rc "no args" 2 'usage' --
expect_rc "flag without value" 2 'needs a value' -- "$fx/clean.html" --allow
expect_rc "flag followed by flag" 2 'needs a value' -- "$fx/clean.html" --allow --json
expect_rc "unknown flag" 2 'unknown option' -- "$fx/clean.html" --allow "$A" --bogus
expect_rc "two files" 2 'only one file' -- "$fx/clean.html" "$fx/clean.html" --allow "$A"
expect_rc "bad limit" 2 '--limit needs' -- "$fx/clean.html" --allow "$A" --limit x
expect_rc "unknown extension" 2 'cannot tell the input type' -- "$work/x.txt" --allow "$A"
expect_rc "browser on a pdf" 2 'only applies to an html' -- "$fx/clean.html" --allow "$A" --type computed --browser
printf 'this is not a pdf' > "$work/garbage.pdf"; : > "$work/empty.pdf"; head -c 700 "$fx/faulty.pdf" > "$work/trunc.pdf"
if [[ $have_pdf == 1 ]]; then
  expect_rc "garbage pdf" 2 'unreadable PDF' -- "$work/garbage.pdf" --allow "$A"
  expect_rc "empty pdf" 2 'unreadable PDF' -- "$work/empty.pdf" --allow "$A"
  out=$(typo "$work/trunc.pdf" --allow "$A" 2>&1); rc=$?
  { [[ $rc -le 2 ]] && ! grep -q Traceback <<<"$out"; } && ok || bad "truncated pdf: rc $rc: $out"
else skipped=$((skipped + 3)); fi
printf '[1,2]' > "$work/a1.json"; printf '{"sizes": 5}' > "$work/a2.json"; printf '{"sizes": []}' > "$work/a3.json"
printf '{"colors": ["zzz"]}' > "$work/a4.json"; printf '{{' > "$work/a5.json"; printf '{"min_contrast": 99}' > "$work/a6.json"
printf '{"families": [5]}' > "$work/a7.json"; printf '{"sizes": [NaN]}' > "$work/a8.json"; printf '{"weights": [true]}' > "$work/a9.json"
printf '{"line_height": {"min": 2, "max": 1}}' > "$work/a10.json"; printf '{"pdf_require_embedded": "yes"}' > "$work/a11.json"
for n in 1 2 3 4 5 6 7 8 9 10 11; do expect_rc "bad allow-list a$n" 2 'allow-list' -- "$fx/clean.html" --allow "$work/a$n.json"; done
printf '{"elements": 5}' > "$work/c1.json"; printf '[]' > "$work/c2.json"; printf '{"elements":[1,null,{"size_px":NaN,"family":5,"color":7}]}' > "$work/c3.json"
expect_rc "computed elements not a list" 2 'elements' -- "$work/c1.json" --allow "$A"
expect_rc "computed not an object" 2 'elements' -- "$work/c2.json" --allow "$A"
expect_rc "computed junk entries are skipped" 0 '' -- "$work/c3.json" --allow "$A"
head -c 6000000 /dev/zero | tr '\0' 'a' > "$work/huge.html"
expect_rc "huge html" 2 'too large' -- "$work/huge.html" --allow "$A"
printf '{"families": ["Inter"]}' > "$work/partial.json"
out=$(typo "$fx/faulty.html" --allow "$work/partial.json" 2>&1)
{ grep -q 'checks off (not in the allow-list): SIZE, WEIGHT, COLOR, LINEHEIGHT, CONTRAST' <<<"$out" && ! grep -q '^SIZE' <<<"$out"; } && ok || bad "partial allow-list: $out"
printf '{"families": ["Inter"], "sizess": [1]}' > "$work/typo.json"
typo "$fx/clean.html" --allow "$work/typo.json" 2>&1 | grep -q 'unknown allow-list keys ignored: sizess' && ok || bad "unknown allow-list key not reported"

# ---- 4. output carries no control characters, is ASCII, and escapes what it shows ----
printf '<style>\n.a\033[31mred\007x\r\177y\302\205z\342\200\256w\303\251 { font-family: Georgia\033]0;t\007 }\n</style>\n<p style="font-family: Arial\033">\303\251</p>\n' > "$work/ctl.html"
out=$(typo "$work/ctl.html" --allow "$A" 2>&1); rc=$?
odd=$(printf '%s\n' "$out" | LC_ALL=C tr -d '\n\040-\176' | wc -c | tr -d ' ')
{ [[ $rc -eq 1 && $odd == 0 ]] && grep -q -F '\x1b' <<<"$out"; } && ok || bad "control characters leaked (rc $rc, $odd odd bytes): $out"
out=$(typo "$work/ctl.html" --allow "$A" --json 2>&1)
odd=$(printf '%s\n' "$out" | LC_ALL=C tr -d '\n\040-\176' | wc -c | tr -d ' ')
{ [[ $odd == 0 ]] && printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["findings"] >= 1'; } && ok || bad "json output bad (odd bytes $odd)"
out=$(typo "$fx/faulty.html" --allow "$A" --limit 2 2>&1)
grep -q 'more finding groups not shown' <<<"$out" && ok || bad "--limit did not truncate with a note"

# ---- 5. allow-list path from the environment with $VAR expanded ----
out=$(FXDIR=$fx SABHA_TYPO_ALLOW='$FXDIR/allow.json' typo "$fx/faulty.html" 2>&1); rc=$?
[[ $rc -eq 1 ]] && ok || bad "SABHA_TYPO_ALLOW with a variable: rc $rc: $out"

# ---- 6. template placeholders and external sheets are not mistaken for missing files ----
printf '<style>@font-face { font-family: "Inter"; src: url("[(${assetBase})]fonts/Inter-400.ttf"); }\nbody { font-family: "Inter"; }</style>\n<link rel="stylesheet" href="https://fonts.example/x.css">\n' > "$work/tpl.html"
out=$(typo "$work/tpl.html" --allow "$A" 2>&1)
{ ! grep -q '^FALLBACK' <<<"$out" && grep -q 'template placeholder' <<<"$out" && grep -q 'external stylesheet not fetched' <<<"$out"; } && ok || bad "placeholder or external sheet reported wrongly: $out"

# ---- 7. the browser path, with a stub runner and a stub heavy gate ----
export SABHA_TYPO_HEAVY=$fx/stub-heavy.sh SABHA_TYPO_RUNNER=$fx/stub-runner.sh STUB_HEAVY_LOG=$work/heavy.log
out=$(typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
{ [[ $rc -eq 1 ]] && grep -q '^WRAP | where: div.over' <<<"$out" && grep -q '(html+browser)' <<<"$out"; } && ok || bad "browser path: rc $rc: $out"
grep -q '^run typography -- .*stub-runner.sh .*clean.html .*computed.json$' "$work/heavy.log" && ok || bad "runner was not started through sabha-heavy run typography --: $(cat "$work/heavy.log")"
out=$(STUB_HEAVY_WAIT=1 typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
{ [[ $rc -eq 75 ]] && grep -q 'heavy gate says wait' <<<"$out"; } && ok || bad "heavy WAIT should exit 75: rc $rc: $out"
for m in "fail|3|runner failed \\(rc 3\\)" "garbage|2|not valid JSON" "nofile|2|wrote no output"; do
  IFS='|' read -r mode _ re <<<"$m"
  out=$(STUB_MODE=$mode typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
  { [[ $rc -eq 2 ]] && grep -q -E "$re" <<<"$out"; } && ok || bad "stub $mode: rc $rc: $out"
done
unset SABHA_TYPO_HEAVY SABHA_TYPO_RUNNER STUB_HEAVY_LOG

# ---- 8. the shipped example allow-list loads ----
typo "$fx/clean.html" --allow "$root/template/typography.example.json" >/dev/null 2>&1; rc=$?
[[ $rc -le 1 ]] && ok || bad "template/typography.example.json does not load (rc $rc)"

# ---- 9. the wrapper picks an interpreter and passes the exit code through ----
"$root/bin/sabha-typography-check" "$fx/clean.html" --allow "$A" >/dev/null 2>&1 && ok || bad "bin/sabha-typography-check wrapper"
[[ $("$root/bin/sabha-typography-check" "$work/none.html" --allow "$A" >/dev/null 2>&1; echo $?) == 2 ]] && ok || bad "wrapper exit code"

# ---- 10. no bytes above 127 in what this change ships ----
for f in "$tool" "$root/bin/sabha-typography-check" "$root/tools/typography-computed.mjs" "$root/tools/typography-requirements.txt" "$root/template/typography.example.json" "$root/skills/sabha-typography-check/SKILL.md" "$0" "$fx"/*; do
  [[ -f $f ]] || continue
  if LC_ALL=C grep -q -E '[^ -~	]' "$f" 2>/dev/null && ! grep -q '^%PDF' "$f"; then bad "non-ASCII byte in $f"; else ok; fi
done

if [[ $skipped -gt 0 ]]; then echo "NOT RUN: $skipped PDF rows (no repo-local .venv with pdfminer.six: uv venv .venv && uv pip install --python .venv/bin/python -r tools/typography-requirements.txt)"; fi
if [[ $fails -gt 0 ]]; then echo "FAILED: $fails of $((passes + fails)) checks"; exit 1; fi
echo "ok: $passes checks, $mutants mutant rows killed (each check removed makes its rows fail), $skipped not run"
