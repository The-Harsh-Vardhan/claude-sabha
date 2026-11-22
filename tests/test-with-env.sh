#!/usr/bin/env bash
# bin/with-env: loads named vars, slots, masking, argv refusal, exit codes. Run: tests/test-with-env.sh
set -u
bin=$(cd "$(dirname "$0")/../bin" && pwd)
d=$(mktemp -d "${TMPDIR:-/tmp}/with-env.XXXXXX"); trap 'rm -rf "$d"' EXIT
f="$d/fakevars"
printf 'TOK_1=bad-secret-111\nTOK_2=good-secret-222\nOTHER=not-loaded\n' > "$f"
W=("$bin/with-env" --env-file "$f")
py='import os,sys;print(os.environ.get("TOK"),os.environ.get("OTHER"));sys.exit(0 if os.environ["TOK"].endswith("222") else 1)'
PY=python3; command -v python3 >/dev/null || PY=python
out=$("${W[@]}" --slot 2 TOK -- $PY -c "$py" 2>&1); rc=$?
[[ $out == "*** None" && $rc == 0 ]] || { echo "FAIL slot/mask: $out rc=$rc"; exit 1; }
out=$("${W[@]}" --try-slots 1,2 TOK -- $PY -c "$py" 2>&1); rc=$?
[[ $rc == 0 && $out != *secret* ]] || { echo "FAIL try-slots: rc=$rc"; exit 1; }
"${W[@]}" --slot 1 TOK -- $PY -c "$py" >/dev/null 2>&1; [[ $? == 1 ]] || { echo "FAIL exit passthrough"; exit 1; }
"${W[@]}" --slot 2 TOK -- echo good-secret-222 >/dev/null 2>&1; [[ $? == 2 ]] || { echo "FAIL argv refusal"; exit 1; }
"${W[@]}" --slot 9 TOK -- true >/dev/null 2>&1; [[ $? != 0 ]] || { echo "FAIL missing var"; exit 1; }
echo "PASS test-with-env"
# encoded forms are masked too
enc=$("${W[@]}" --slot 2 TOK -- $PY -c 'import os,base64,urllib.parse as u,json;v=os.environ["TOK"]+" &x";print(u.quote(v));print(base64.b64encode(v.encode()).decode());print(json.dumps(v))' 2>&1)
[[ $enc != *good* && $enc != *Z29vZ* ]] || { echo "FAIL encoded masking: $enc"; exit 1; }
printf 'SHORT=ab\n' > "$f"
"${W[@]}" SHORT -- true 2>&1 | grep -q 'shorter than 8' || { echo "FAIL short warning"; exit 1; }
echo "PASS encoded"
