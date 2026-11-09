#!/usr/bin/env bash
# shellcheck disable=SC2015,SC1091,SC2016,SC2034
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
  "htm|FALLBACK|font stack \"Inter\" has none of the allowed fallbacks" "cmp|FALLBACK|p\\.big.*font stack Inter has none of the allowed fallbacks"
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
  expect_rc "empty pdf" 2 'is empty|unreadable PDF' -- "$work/empty.pdf" --allow "$A"
  out=$(typo "$work/trunc.pdf" --allow "$A" 2>&1); rc=$?
  { [[ $rc -eq 2 ]] && ! grep -q Traceback <<<"$out"; } && ok || bad "truncated pdf: rc $rc: $out"
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
printf '<style>@font-face { font-family: "Inter"; src: url("[(${assetBase})]fonts/Inter-400.ttf"); }\nbody { font-family: "Inter", sans-serif; }</style>\n<link rel="stylesheet" href="https://fonts.example/x.css">\n' > "$work/tpl.html"
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
out=$(typo "$fx/clean.html" --allow "$root/template/typography.example.json" 2>&1); rc=$?
{ [[ $rc -le 1 ]] && grep -q '^typography-check clean.html (html): [0-9]* finding' <<<"$out"; } && ok || bad "template/typography.example.json does not load (rc $rc): $out"

# ---- 9. the wrapper picks an interpreter and passes the exit code through ----
"$root/bin/sabha-typography-check" "$fx/clean.html" --allow "$A" >/dev/null 2>&1 && ok || bad "bin/sabha-typography-check wrapper"
[[ $("$root/bin/sabha-typography-check" "$work/none.html" --allow "$A" >/dev/null 2>&1; echo $?) == 2 ]] && ok || bad "wrapper exit code"

# ---- 10. round 2 (review 243): the tool reads only inside the input's folder (M1) ----
px=$work/proj; mkdir -p "$px/sub/fonts"
printf '.leaked-selector { color: #ff0000; }\n' > "$px/secret.css"
printf '.inside-selector { color: #ff0000; }\n' > "$px/sub/own.css"
ln -s ../secret.css "$px/sub/link.css"
cat > "$px/sub/page.html" <<EOF
<link rel="stylesheet" href="$px/secret.css">
<link rel="stylesheet" href="../secret.css">
<link rel="stylesheet" href="link.css">
<link rel="stylesheet" href="own.css">
<style>
@font-face { font-family: "Inter"; src: url(/etc/nonexistent-zzz), url(../x.woff2), url(fonts/none.woff2); }
body { font-family: "Inter", sans-serif; }
</style>
EOF
out=$(typo "$px/sub/page.html" --allow "$A" 2>&1)
r2() { if eval "$2"; then ok; else bad "R2 $1: $out"; fi; }
r2 "M1 outside sheets are not read" '! grep -q "leaked-selector" <<<"$out"'
r2 "M1 a sheet inside the folder is still read" 'grep -q "^COLOR | where: .inside-selector" <<<"$out"'
r2 "M1 absolute href noted" 'grep -q -F "note: not read: outside the input folder: $px/secret.css" <<<"$out"'
r2 "M1 ../ href noted" 'grep -q -F "outside the input folder: ../secret.css" <<<"$out"'
r2 "M1 symlink out of the folder noted" 'grep -q -F "outside the input folder: link.css" <<<"$out"'
r2 "M1 absolute font path is not probed" 'grep -q -F "outside the input folder: /etc/nonexistent-zzz" <<<"$out" && ! grep -q "nonexistent-zzz | nearest" <<<"$out"'
r2 "M1 ../ font path noted" 'grep -q -F "outside the input folder: ../x.woff2" <<<"$out"'
r2 "M1 a font path inside the folder is still checked" 'grep -q "^FALLBACK .*src file not found: fonts/none.woff2" <<<"$out"'
out=$(typo "$px/sub/page.html" --allow "$A" --json 2>&1)
r2 "M1 json carries the notes" 'grep -q "outside the input folder" <<<"$out"'

# ---- 11. M2: --browser and page scripts ----
export SABHA_TYPO_HEAVY=$fx/stub-heavy.sh SABHA_TYPO_RUNNER=$fx/stub-runner.sh STUB_HEAVY_LOG=$work/heavy2.log STUB_RUNNER_LOG=$work/runner.log
out=$(typo "$fx/clean.html" --allow "$A" --browser 2>&1)
r2 "M2 default is scripts off (runner env)" 'grep -q "^scripts=0$" "$work/runner.log"'
r2 "M2 default says scripts are off" 'grep -q "note: browser run with page scripts off" <<<"$out"'
: > "$work/runner.log"
out=$(typo "$fx/clean.html" --allow "$A" --browser --allow-scripts 2>&1); rc=$?
r2 "M2 --allow-scripts passes scripts=1" 'grep -q "^scripts=1$" "$work/runner.log"'
r2 "M2 --allow-scripts warns on every run" 'grep -q "warning: --allow-scripts runs the page.s scripts: use only on files you trust" <<<"$out"'
expect_rc "R2 M2 --allow-scripts needs --browser" 2 'only applies with --browser' -- "$fx/clean.html" --allow "$A" --allow-scripts
for v in "--help" "-h"; do
  out=$(typo $v 2>&1); rc=$?
  r2 "M2/M4 $v states scripts, never-run caveat, Chrome exit 2" '[[ $rc -eq 0 ]] && grep -q "Page scripts are OFF unless you add --allow-scripts" <<<"$out" && grep -q "Never run in a real browser" <<<"$out" && grep -q "Chrome or playwright is" <<<"$out"'
done
unset STUB_RUNNER_LOG

# ---- 12. M4: Chrome or playwright missing says so and exits 2; the cause survives ----
out=$(STUB_MODE=nochrome typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
r2 "M4 Chrome missing (runner rc 4) exits 2 and says the check did not run" '[[ $rc -eq 2 ]] && grep -q "the browser check did not run: typography-computed: Chrome could not be started" <<<"$out"'
out=$(STUB_MODE=nomodule typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
r2 "SHOULD4 runner failure keeps the cause line, no escaped newlines" '[[ $rc -eq 2 ]] && grep -q -F "Cannot find module '"'"'playwright'"'"'" <<<"$out" && ! grep -q -F "\\x0a" <<<"$out"'
unset SABHA_TYPO_HEAVY SABHA_TYPO_RUNNER STUB_HEAVY_LOG

# ---- 13. the real runner script against a fake playwright (no browser): options, request blocking, missing pieces ----
mjs=$root/tools/typography-computed.mjs
if command -v node >/dev/null 2>&1; then
  node --check "$mjs" && ok || bad "node --check $mjs"
  mkdir -p "$work/pw/node_modules" "$work/nopw"; cp -R "$fx/fake-playwright" "$work/pw/node_modules/playwright"
  export FAKE_PW_LOG=$work/pw.log; : > "$FAKE_PW_LOG"
  SABHA_TYPO_PLAYWRIGHT_DIR=$work/pw node "$mjs" "$fx/clean.html" "$work/pw.json" >/dev/null 2>&1; rc=$?
  out=$(cat "$FAKE_PW_LOG")
  r2 "M2 runner: JavaScript is off by default" '[[ $rc -eq 0 ]] && grep -q "^context .*\"javaScriptEnabled\":false" <<<"$out"'
  r2 "M2 runner: a file next to the page is allowed" '[[ $(grep -c "^continue file://" <<<"$out") -eq 2 ]]'
  r2 "M2 runner: a file outside the folder is aborted" 'grep -q "^abort file:///etc/hosts$" <<<"$out"'
  r2 "M2 runner: a remote request is aborted" 'grep -q "^abort https://example.invalid/x$" <<<"$out"'
  r2 "M2 runner: data: is allowed" 'grep -q "^continue data:text/css,a$" <<<"$out"'
  : > "$FAKE_PW_LOG"
  SABHA_TYPO_SCRIPTS=1 SABHA_TYPO_PLAYWRIGHT_DIR=$work/pw node "$mjs" "$fx/clean.html" "$work/pw.json" >/dev/null 2>&1
  out=$(cat "$FAKE_PW_LOG")
  r2 "M2 runner: SABHA_TYPO_SCRIPTS=1 turns JavaScript on" 'grep -q "^context .*\"javaScriptEnabled\":true" <<<"$out"'
  out=$(FAKE_PW_MODE=nochrome SABHA_TYPO_PLAYWRIGHT_DIR=$work/pw node "$mjs" "$fx/clean.html" "$work/pw.json" 2>&1); rc=$?
  r2 "M4 runner: Chrome missing exits 4 with a plain sentence" '[[ $rc -eq 4 ]] && grep -q "^typography-computed: Chrome could not be started, install Google Chrome: " <<<"$out"'
  out=$(SABHA_TYPO_PLAYWRIGHT_DIR=$work/nopw node "$mjs" "$fx/clean.html" "$work/pw.json" 2>&1); rc=$?
  r2 "M4 runner: playwright missing exits 4 with a plain sentence" '[[ $rc -eq 4 ]] && grep -q "^typography-computed: playwright not found" <<<"$out" && ! grep -q "    at " <<<"$out"'
  out=$(SABHA_TYPO_HEAVY=$fx/stub-heavy.sh SABHA_TYPO_PLAYWRIGHT_DIR=$work/nopw typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
  r2 "M4 end to end: playwright missing -> exit 2, says so" '[[ $rc -eq 2 ]] && grep -q "the browser check did not run: typography-computed: playwright not found" <<<"$out"'
  out=$(SABHA_TYPO_HEAVY=$fx/stub-heavy.sh FAKE_PW_MODE=nochrome SABHA_TYPO_PLAYWRIGHT_DIR=$work/pw typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
  r2 "M4 end to end: Chrome missing -> exit 2, says so" '[[ $rc -eq 2 ]] && grep -q "the browser check did not run: typography-computed: Chrome could not be started" <<<"$out"'
  out=$(SABHA_TYPO_HEAVY=$fx/stub-heavy.sh SABHA_TYPO_PLAYWRIGHT_DIR=$work/pw typo "$fx/clean.html" --allow "$A" --browser 2>&1); rc=$?
  r2 "M2 end to end: tool + real runner + fake playwright is clean and says scripts are off" '[[ $rc -eq 0 ]] && grep -q "page scripts off" <<<"$out"'
  unset FAKE_PW_LOG
else skipped=$((skipped + 12)); echo "NOT RUN: node is missing (runner rows)"; fi

# ---- 14. M3: every colour form is resolved or reported UNKNOWN, never dropped; real source mutants must be killed ----
printf '{"min_contrast": 4.5, "page_background": "#ffffff"}' > "$work/cc-allow.json"
cc() { # cc <tool.py> <css> <FAIL|PASS|UNKNOWN|STRICT>
  local t=$1 want=$3 out rc extra=()
  [[ $want == STRICT ]] && extra=(--strict)
  printf '<style>%s</style>' "$2" > "$work/cc.html"
  out=$("$PY" "$t" "$work/cc.html" --allow "$work/cc-allow.json" ${extra[@]+"${extra[@]}"} 2>&1); rc=$?
  case $want in
    FAIL) [[ $rc -eq 1 ]] && grep -q '^CONTRAST' <<<"$out" ;;
    PASS) [[ $rc -eq 0 ]] && ! grep -q -E '^(CONTRAST|UNKNOWN)' <<<"$out" ;;
    UNKNOWN) [[ $rc -eq 0 ]] && grep -q '^UNKNOWN' <<<"$out" && ! grep -q '^CONTRAST' <<<"$out" ;;
    STRICT) [[ $rc -eq 1 ]] && grep -q '^UNKNOWN' <<<"$out" && grep -q -- '--strict counts them as findings' <<<"$out" ;;
  esac
}
cases=()
tc() { cases+=("body{color:$1;background:#fff}|$2"); }
bc() { cases+=("body{color:$1;background:$2}|$3"); }
tc '#aaa' FAIL; tc '#333' PASS; tc '#0000' FAIL; tc '#000f' PASS; tc '#0000001a' FAIL; tc '#00000099' PASS
tc 'rgba(0,0,0,0.1)' FAIL; tc 'rgba(0,0,0,0.9)' PASS; tc 'rgb(0 0 0 / 10%)' FAIL; tc 'rgb(0 0 0 / 90%)' PASS
tc 'rgb(60%,60%,60%)' FAIL; tc 'rgb(10%,10%,10%)' PASS
tc 'hsl(0,0%,60%)' FAIL; tc 'hsl(0,0%,10%)' PASS; tc 'hsl(120,100%,50%)' FAIL; tc 'hsl(60,100%,50%)' FAIL; tc 'hsl(240,100%,50%)' PASS
tc 'hsl(0,100%,25%)' PASS; tc 'hsla(0,0%,0%,0.1)' FAIL; tc 'hsla(0,0%,0%,0.9)' PASS; tc 'hsl(0.5turn 100% 50%)' FAIL
tc 'currentColor' UNKNOWN; tc 'rebeccapurple' UNKNOWN; tc 'inherit' PASS; tc 'white' FAIL; tc 'navy' PASS
bc '#000' 'rgba(0,0,0,0.05)' PASS; bc '#888' 'rgba(0,0,0,0.05)' FAIL; bc '#000' '#ffffffcc' PASS; bc '#888' '#0000000d' FAIL
bc '#000' 'hsl(0,0%,0%)' FAIL; bc '#000' 'hsl(0,0%,100%)' PASS; bc '#fff' 'rgb(10%,10%,10%)' PASS; bc '#fff' 'rgb(90%,90%,90%)' FAIL
bc '#000' 'linear-gradient(#000,#111)' UNKNOWN; bc '#000' 'url(x.png) #fff' UNKNOWN; bc '#000' 'currentColor' UNKNOWN
bc '#000' 'rebeccapurple' UNKNOWN; bc '#000' 'transparent' PASS; bc '#000' 'no-repeat #fff' PASS; bc '#000' '#fff 10px 20px no-repeat' PASS
cases+=(".x{color:rgba(0,0,0,.1)}|UNKNOWN" ".x{color:var(--nope)}|UNKNOWN" "body{color:currentColor;background:#fff}|STRICT")
colour_suite() { # colour_suite <tool.py>: 0 when every case holds, else 1 after printing the first that does not
  local t=$1 r
  for r in "${cases[@]}"; do cc "$t" "${r%|*}" "${r##*|}" || { echo "$r"; return 1; }; done
}
if first=$(colour_suite "$tool"); then for _ in "${cases[@]}"; do ok; done; else bad "R2 M3 colour case failed on the real tool: $first"; fi
mutate() { # mutate <out.py> <old> <new>: replace every occurrence; a missing pattern fails loudly
  "$PY" - "$tool" "$1" "$2" "$3" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
assert sys.argv[3] in src, "mutant pattern not found: " + sys.argv[3]
open(sys.argv[2], "w").write(src.replace(sys.argv[3], sys.argv[4]))
PYEOF
}
cmut=0 cmut_total=0
kill_mut() { # kill_mut <name> <old> <new>
  cmut_total=$((cmut_total + 1))
  if ! mutate "$work/cm.py" "$2" "$3" 2>"$work/cm.err"; then bad "R2 colour mutant $1 does not apply: $(tail -1 "$work/cm.err")"; return; fi
  if colour_suite "$work/cm.py" >/dev/null; then bad "R2 colour mutant SURVIVED: $1"; else cmut=$((cmut + 1)); ok; fi
}
kill_mut hex3-not-expanded 'if len(h) in (3, 4):' 'if len(h) in (4,):'
kill_mut hex-alpha-dropped 'a = int(h[6:8], 16) / 255.0 if len(h) == 8 else 1.0' 'a = 1.0'
kill_mut percent-channel-unscaled 'float(t[:-1]) * 2.55' 'float(t[:-1])'
kill_mut percent-alpha-unscaled 'float(t[:-1]) / 100.0 if t.endswith("%") else float(t)))' 'float(t[:-1]) if t.endswith("%") else float(t)))'
kill_mut hsl-hue-doubled '(deg % 360.0) / 360.0' '(deg % 360.0) / 180.0'
kill_mut hsl-args-swapped 'colorsys.hls_to_rgb((deg % 360.0) / 360.0, lig, sat)' 'colorsys.hls_to_rgb((deg % 360.0) / 360.0, sat, lig)'
kill_mut alpha-not-blended 'fg[3] * fg[i] + (1 - fg[3]) * bg[i]' 'fg[i]'
kill_mut bg-alpha-not-blended 'bg = bg_c[:3] if bg_c[3] >= 1 else over(bg_c, A["bg"] or (255, 255, 255))' 'bg = bg_c[:3]'
kill_mut unknown-dropped-silently '    if c is None:
        R.unknown(where, "%s %s: %s"' '    if False:
        R.unknown(where, "%s %s: %s"'
kill_mut image-bg-not-detected 'gradient\(|url\(|image\(|image-set\(' 'zzzz\('
kill_mut bg-keywords-read-as-colours 'if t not in BG_WORDS]' 'if True]'
kill_mut strict-ignored 'total + (unk if strict else 0)' 'total'

# ---- 15. M3 in the computed path, and --strict output ----
cmp3() { # cmp3 <bg json> <color json> <expect rc> <regex>
  printf '{"elements":[{"selector":"p.t","tag":"p","text":"t","family":"Inter, sans-serif","size_px":16,"weight":400,"color":%s,"bg":%s}]}' "$2" "$1" > "$work/c3x.json"
  out=$(typo "$work/c3x.json" --allow "$work/cc-allow.json" 2>&1); rc=$?
  if [[ $rc -eq $3 ]] && grep -q -E "$4" <<<"$out"; then ok; else bad "R2 M3 computed bg=$1 color=$2: rc $rc: $out"; fi
}
cmp3 '"rgb(255, 255, 255)"' '"rgba(0, 0, 0, 0.1)"' 1 '^CONTRAST .*p\.t'
cmp3 '"rgb(255, 255, 255)"' '"rgba(0, 0, 0, 0.9)"' 0 'typography-check .*: 0 findings$'
cmp3 'null' '"rgb(0, 0, 0)"' 0 '^UNKNOWN .*background image or gradient'
cmp3 '"rgb(255, 255, 255)"' '"color(srgb 0 0 0)"' 0 '^UNKNOWN .*text colour color\(srgb 0 0 0\)'
cmp3 '"rgba(0, 0, 0, 0.05)"' '"rgb(136, 136, 136)"' 1 '^CONTRAST'
printf '<style>body{color:currentColor;background:#fff}</style>' > "$work/s1.html"
out=$(typo "$work/s1.html" --allow "$work/cc-allow.json" --strict --json 2>&1); rc=$?
{ [[ $rc -eq 1 ]] && printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["unknown"]==1 and d["strict"] is True and d["findings"]==0 and d["unknown_groups"]'; } && ok || bad "R2 M3 --strict json: rc $rc: $out"
out=$(typo "$work/s1.html" --allow "$work/cc-allow.json" 2>&1); rc=$?
{ [[ $rc -eq 0 ]] && grep -q ': 0 findings, 1 unknown$' <<<"$out" && grep -q 'add --strict to count them as findings' <<<"$out"; } && ok || bad "R2 M3 unknown without --strict: rc $rc: $out"

# ---- 16. SHOULD 1: empty, truncated or non-HTML input is a tool error, never a clean pass ----
: > "$work/empty.html"; printf '   \n\t\n' > "$work/blank.html"; printf 'this is plain text, not a page\n' > "$work/plain.html"
expect_rc "R2 empty html" 2 'is empty: nothing was checked' -- "$work/empty.html" --allow "$A"
expect_rc "R2 blank html" 2 'is empty: nothing was checked' -- "$work/blank.html" --allow "$A"
expect_rc "R2 html with no CSS at all" 2 'no CSS found' -- "$work/plain.html" --allow "$A"
printf '<style>p{color:#' > "$work/cut.html"
out=$(typo "$work/cut.html" --allow "$work/cc-allow.json" 2>&1); rc=$?
{ [[ $rc -le 1 ]] && grep -q 'has no closing tag' <<<"$out" && grep -q '^UNKNOWN' <<<"$out"; } && ok || bad "R2 truncated style block: rc $rc: $out"
printf '{"elements": []}' > "$work/c0.json"
expect_rc "R2 computed dump with no elements" 2 'no elements' -- "$work/c0.json" --allow "$A"
: > "$work/empty.json"
expect_rc "R2 empty computed json" 2 'empty' -- "$work/empty.json" --allow "$A"
if [[ $have_pdf == 1 ]]; then
  LC_ALL=C sed 's/ Tf/ Xf/g' "$fx/clean.pdf" > "$work/corrupt.pdf"
  expect_rc "R2 pdf whose text operators are corrupt" 2 'no text spans' -- "$work/corrupt.pdf" --allow "$A"
else skipped=$((skipped + 1)); fi

# ---- 17. SHOULD 3: the shipped docs carry the caveats ----
sk=$root/skills/sabha-typography-check/SKILL.md; rd=$root/README.md
r2 "M4 SKILL.md says the browser path and a real Chrome PDF never ran" 'grep -q -i "never run in a real browser" "$sk" && grep -q -i "real Chrome PDF" "$sk"'
r2 "M4 README entry says it" 'grep -i "sabha-typography-check <file>" "$rd" | grep -q -i "never run in a real browser"'
r2 "M2 SKILL.md says --browser runs scripts only with --allow-scripts" 'grep -q -- "--allow-scripts" "$sk" && grep -q -i "only on files you trust" "$sk"'
r2 "M1 SKILL.md says which files are opened" 'grep -q -i "outside the input folder" "$sk"'
r2 "M3 SKILL.md explains UNKNOWN and --strict" 'grep -q "UNKNOWN" "$sk" && grep -q -- "--strict" "$sk"'

# ---- 19. round 3 (review 245): NUL paths, any crash exits 2, @import followed inside the folder, URL schemes, honest docs ----
# A NUL byte cannot sit in the input file's NAME or in an env value: the OS refuses to start a process with one, so only
# stylesheet hrefs, @import and font url() values can carry it.
q=$work/r3; mkdir -p "$q/sub"
cp "$fx/clean.html" "$q/base.html"
{ cat "$q/base.html"; printf '<link rel="stylesheet" href="a\000b.css">\n'; } > "$q/nul-href.html"
{ cat "$q/base.html"; printf '<style>@import "a\000b.css";</style>\n'; } > "$q/nul-import.html"
{ cat "$q/base.html"; printf '<style>@font-face { font-family: "Inter"; src: url("a\000b.woff2"); }</style>\n'; } > "$q/nul-font.html"
for k in href import font; do
  out=$(typo "$q/nul-$k.html" --allow "$A" 2>&1); rc=$?
  r2 "R3 MUST NUL in a $k: rc 0, a visible note, no traceback, no false finding" '[[ $rc -eq 0 ]] && grep -q -F "note: not read: bad path (NUL byte): a\\x00b" <<<"$out" && ! grep -q -E "Traceback|src file not found" <<<"$out"'
done
cat > "$work/boom.py" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
marker = "def check_html_static(R, A, path, data):\n"
assert marker in src
src = src.replace(marker, marker + "    raise RuntimeError('forced')\n", 1)
sys.argv = sys.argv[1:]
exec(compile(src, sys.argv[0], "exec"), {"__name__": "__main__", "__file__": sys.argv[0]})
PYEOF
out=$("$PY" "$work/boom.py" "$tool" "$fx/clean.html" --allow "$A" 2>&1 >/dev/null); rc=$?
r2 "R3 MUST a forced internal error exits 2 (not 1), one line with the cause, no traceback" '[[ $rc -eq 2 && $(wc -l <<<"$out" | tr -d " ") -eq 1 ]] && grep -q "internal error (RuntimeError): forced" <<<"$out" && ! grep -q Traceback <<<"$out"'
out=$(SABHA_TYPO_DEBUG=1 "$PY" "$work/boom.py" "$tool" "$fx/clean.html" --allow "$A" 2>&1 >/dev/null); rc=$?
r2 "R3 MUST SABHA_TYPO_DEBUG=1 keeps the traceback available" '[[ $rc -eq 2 ]] && grep -q "Traceback" <<<"$out" && grep -q "RuntimeError: forced" <<<"$out"'
# SHOULD 1: a local @import is followed with the same folder fence as a <link> sheet
printf 'p { font-size: 99px; }\n@import "sub/deep.css";\n' > "$q/main.css"
printf '.deepsel { color: #ff0000; }\n@import "../../outside-up.css";\n' > "$q/sub/deep.css"
printf '.leaked-up { color: #00ff00; }\n' > "$work/outside-up.css"
printf '<style>@import "main.css"; @import url(a-loop.css);</style>\n' > "$q/imp.html"
printf '@import "b-loop.css"; .la { color: #111111; }\n' > "$q/a-loop.css"; printf '@import "a-loop.css"; .lb { color: #222222; }\n' > "$q/b-loop.css"
out=$(typo "$q/imp.html" --allow "$A" 2>&1)
r2 "R3 SHOULD1 an @import file is read (its finding appears)" 'grep -q "^SIZE | where: p | found: 99px" <<<"$out"'
r2 "R3 SHOULD1 an @import of an @import is read, relative to its own folder" 'grep -q "^COLOR | where: .deepsel" <<<"$out"'
r2 "R3 SHOULD1 an @import leaving the folder is noted and not read" 'grep -q -F "outside the input folder: ../../outside-up.css" <<<"$out" && ! grep -q "leaked-up" <<<"$out"'
r2 "R3 SHOULD1 an @import loop ends with a note" 'grep -q -F "@import loop: " <<<"$out" && grep -q "^COLOR | where: .lb" <<<"$out"'
for i in 1 2 3 4 5 6 7; do printf '@import "d%d.css"; .x%d { font-size: 99px; }\n' $((i + 1)) "$i" > "$q/d$i.css"; done
printf '.x8 { font-size: 98px; }\n' > "$q/d8.css"; printf '<style>@import "d1.css";</style>\n' > "$q/deep.html"
out=$(typo "$q/deep.html" --allow "$A" --json 2>&1)
r2 "R3 SHOULD1 depth 5 stops the chain with a note" 'grep -q -F "@import nested deeper than 5: d6.css" <<<"$out" && ! grep -q "\.x6" <<<"$out"'
printf '<style>@import "https://x.invalid/a.css"; @import "%s/outside-up.css";</style>\n' "$work" > "$q/imp-abs.html"
out=$(typo "$q/imp-abs.html" --allow "$A" 2>&1)
r2 "R3 SHOULD1 remote and absolute @import are noted, not read" 'grep -q "external @import not fetched" <<<"$out" && grep -q -F "outside the input folder: $work/outside-up.css" <<<"$out" && ! grep -q "leaked-up" <<<"$out"'
# SHOULD 2: a URL scheme is not a file name
{ cat "$q/base.html"; printf '<link rel="stylesheet" href="ftp://x.invalid/a.css"><link rel="stylesheet" href="data:text/css,a{}"><style>@import "file:///etc/hosts"; @font-face { font-family: "Inter"; src: url(file:///etc/hosts), url(ftp://x.invalid/f.woff); }</style>\n'; } > "$q/scheme.html"
out=$(typo "$q/scheme.html" --allow "$A" 2>&1); rc=$?
r2 "R3 SHOULD2 ftp:, data:, file: are skipped with 'not read: URL scheme' (4 distinct notes, the same file: URL is one) and no false 'src file not found'" '[[ $rc -eq 0 ]] && [[ $(grep -c -F "note: not read: URL scheme:" <<<"$out") -eq 4 ]] && ! grep -q "src file not found" <<<"$out"'
# SHOULD 3: the fake-playwright caveat is stated wherever the request block is
for f in "$sk" "$rd" "$mjs"; do
  r2 "R3 SHOULD3 $(basename "$f") says tested only against a fake playwright; not run in a real Chrome" 'tr "\n" " " <"$f" | tr -s " " | grep -q -F "tested only against a fake playwright; not run in a real Chrome"'
done
out=$(typo --help 2>&1)
r2 "R3 SHOULD3 --help says tested only against a fake playwright; not run in a real Chrome" 'tr "\n" " " <<<"$out" | tr -s " " | grep -q -F "tested only against a fake playwright; not run in a real Chrome"'

# ---- 18. no bytes above 127 in what this change ships ----
for f in "$tool" "$root/bin/sabha-typography-check" "$root/tools/typography-computed.mjs" "$root/tools/typography-requirements.txt" "$root/template/typography.example.json" "$root/skills/sabha-typography-check/SKILL.md" "$0" "$fx"/* "$fx"/fake-playwright/*; do
  [[ -f $f ]] || continue
  if LC_ALL=C grep -q -E '[^ -~	]' "$f" 2>/dev/null && ! grep -q '^%PDF' "$f"; then bad "non-ASCII byte in $f"; else ok; fi
done

if [[ $skipped -gt 0 ]]; then echo "NOT RUN: $skipped PDF rows (no repo-local .venv with pdfminer.six: uv venv .venv && uv pip install --python .venv/bin/python -r tools/typography-requirements.txt)"; fi
if [[ $fails -gt 0 ]]; then echo "FAILED: $fails of $((passes + fails)) checks"; exit 1; fi
echo "ok: $passes checks, $mutants mutant rows killed (each check removed makes its rows fail), $cmut of $cmut_total colour-parser source mutants killed, $skipped not run"
