#!/usr/bin/env bash
# bin/sabha-chain: blocker chains from an exported board folder (one JSON row per file, or a list per file). A chain runs
# from the open row nobody waits on down to the root blockers; DONE blockers are hidden and counted (--all shows them);
# an id off the board and a cycle are marked; PR refs come from owner/repo#N and from NAME#N / "NAME #N" for a configured
# repo only; --gh adds PR state and base through the fake gh and never sends a write flag; a wrong account stops with
# one line and no table; no --gh means no gh call. GitHub is never reached. Run: tests/test-chain.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-chain.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$FAKE_GH_DIR" "$dir/board"
CALLS=$FAKE_GH_DIR/calls
: > "$CALLS"
# the 367 -> snapshot -> repin -> PR chain, a done blocker, a missing id, a cycle, a bare "PR #12", a lone open row
cat > "$dir/board/Q-1.json" <<'EOF'
{"id":"Q-1","state":"BLOCKED-ME","owner":"Pat","ask":"Message the reviewer to merge acme/lib#367","dependsOn":[]}
EOF
cat > "$dir/board/rows.json" <<'EOF'
[
 {"id":"Q-2","state":"BLOCKED-OTHERS","owner":"Dev","ask":"Cut the snapshot","next":"after lib#367 lands","dependsOn":["Q-1","Q-0"]},
 {"id":"Q-3","state":"RUNNING","owner":"Bot","ask":"Repin the app to the snapshot","dependsOn":["Q-2"]},
 {"id":"Q-4","state":"READY","owner":"Bot","ask":"Ship it: see acme/app#40 and PR #12 and lib #368","dependsOn":["Q-3","Q-9"]},
 {"id":"Q-0","state":"DONE","column":"done","owner":"Dev","ask":"Old prerequisite","dependsOn":[]},
 {"id":"Q-5","state":"READY","owner":"Bot","ask":"cycle a","dependsOn":["Q-6"]},
 {"id":"Q-6","state":"READY","owner":"Bot","ask":"cycle b","dependsOn":["Q-5"]},
 {"id":"Q-7","state":"READY","owner":"Bot","ask":"no deps at all","dependsOn":[]}
]
EOF
echo '{broken' > "$dir/board/bad.json"
echo 'not json either' > "$dir/board/notes.txt"
chain() { python3 "$BIN/sabha-chain" "$@" 2>"$dir/err"; }
export SABHA_GH_CACHE=$dir/cache SABHA_GH_USER=fake-user SABHA_CONF=$dir/none.conf SABHA_CHAIN_REPOS=
REPOS="acme/lib acme/app"

echo "--- the chain"
out=$(chain "$dir/board" --repos "$REPOS"); rc=$?
check "exit 0 and a count line (8 rows with ids: the Q-4 chain and the cycle)" '(( rc == 0 )) && [[ $out == "2 chains from 8 rows (7 open)"* ]]'
check "Q-4 heads a chain: Q-3, Q-2, Q-1 each one level deeper" 'grep -q "^Q-4 \[READY, Bot\]" <<<"$out" && grep -q "^    waits on Q-3 \[RUNNING, Bot\]" <<<"$out" && grep -q "^        waits on Q-2 \[BLOCKED-OTHERS, Dev\]" <<<"$out" && grep -q "^            waits on Q-1 \[BLOCKED-ME, Pat\]" <<<"$out"'
check "a blocker is not also a head (Q-2 and Q-3 never start a line at column 0)" '! grep -q "^Q-[23] " <<<"$out"'
check "the done blocker Q-0 is hidden and counted on Q-2" '[[ $out == *"Q-2 [BLOCKED-OTHERS, Dev]  (+1 done hidden)"* ]] && ! grep -q "waits on Q-0 " <<<"$out"'
check "an id off the board is marked" '[[ $out == *"waits on Q-9 (not on board)"* ]]'
check "unblock first names the roots" '[[ $out == *"unblock first: Q-1, Q-9"* ]]'
check "the lone row and the done row are no chain" '! grep -q "Q-7" <<<"$out"'
check "a cycle is cut and marked" '[[ $out == *"Q-5 [READY, Bot]"*"waits on Q-6"*"waits on Q-5 (cycle: already above, cut here)"* ]]'
check "a file that is not JSON is skipped with a note on stderr, a .txt file is ignored" 'grep -q "skipped bad.json" "$dir/err" && ! grep -q notes.txt "$dir/err"'
check "no --gh: no gh call" '[[ ! -s $CALLS ]]'

echo "--- the PR refs"
check "owner/repo#N is a PR of its row" '[[ $out == *"PR acme/lib#367"* && $out == *"PR acme/app#40"* ]]'
check "NAME #N counts for a configured repo (lib #368), next-text refs count (lib#367 on Q-2)" '[[ $out == *"PR acme/lib#368"* ]] && [[ $(grep -c "PR acme/lib#367" <<<"$out") == 2 ]]'
check "a bare PR #12 is no PR of any repo" '! grep -q "^ *PR .*#12" <<<"$out"'
out2=$(chain "$dir/board"); rc=$?
check "without repos only owner/repo#N is read" '(( rc == 0 )) && [[ $out2 == *"PR acme/lib#367"* ]] && ! grep -q "PR acme/lib#368" <<<"$out2"'
out2=$(SABHA_CHAIN_REPOS=acme/lib chain "$dir/board")
check "SABHA_CHAIN_REPOS from the environment is the default" '[[ $out2 == *"PR acme/lib#368"* ]]'

echo "--- --all"
out2=$(chain "$dir/board" --repos "$REPOS" --all)
check "--all shows the done blocker" '[[ $out2 == *"waits on Q-0 [DONE, Dev]"* ]]'

echo "--- --gh"
echo '{"state":"MERGED","mergedAt":"2026-11-08T00:00:00Z","isDraft":false,"baseRefName":"main"}' > "$dir/pr367.json"
echo '{"state":"OPEN","mergedAt":null,"isDraft":true,"baseRefName":"dev"}' > "$dir/pr40.json"
{
  echo "name=lib -F n=367|$dir/pr367.json"
  echo "name=app -F n=40|$dir/pr40.json"
} > "$FAKE_GH_DIR/map"
out2=$(chain "$dir/board" --repos "$REPOS" --gh); rc=$?
check "merged PR shows MERGED -> its base" '(( rc == 0 )) && [[ $out2 == *"PR acme/lib#367  MERGED -> main"* ]]'
check "open draft PR shows OPEN draft -> base" '[[ $out2 == *"PR acme/app#40  OPEN draft -> dev"* ]]'
check "a PR that gh cannot read is marked, not fatal" '[[ $out2 == *"PR acme/lib#368  ? (gh read failed)"* ]]'
check "each PR is read once (367 appears on two rows, one call)" '[[ $(grep -c "n=367" "$CALLS") == 1 ]]'
check "no gh call carries a write flag" '! grep -Eq -- "(^| )(-X|--method|--input)( |$)" "$CALLS"'
out2=$(chain "$dir/board" --repos "$REPOS" --json); rc=$?
check "--json is valid JSON with the chains and their PR refs" '(( rc == 0 )) && python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert len(d[\"chains\"])==2 and d[\"chains\"][0][\"waitsOn\"]" "$out2"'

echo "--- the account stop"
rm -rf "$SABHA_GH_CACHE"
out2=$(FAKE_GH_LOGIN=someone-else chain "$dir/board" --repos "$REPOS" --gh); rc=$?
check "wrong gh account: exit 1, one line on stderr, no table" '(( rc != 0 )) && [[ -z $out2 ]] && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "someone-else" "$dir/err"'
out2=$(chain "$dir/nope"); rc=$?
check "a missing folder is refused" '(( rc != 0 )) && grep -q "is not a folder" "$dir/err"'
mkdir "$dir/empty"
out2=$(chain "$dir/empty")
check "an empty board prints no blocker chains" '[[ $out2 == *"0 chains from 0 rows"* && $out2 == *"no blocker chains"* ]]'

echo "--- each PR is read once by chain itself"
: > "$CALLS"
chain "$dir/board" --repos "$REPOS" --gh --fresh > /dev/null
check "with --fresh (sabha-gh's own cache off) 367 on two rows is still one call: chain's cache" '[[ $(grep -c "n=367" "$CALLS") == 1 ]]'

echo "--- control characters never reach the terminal"
mkdir "$dir/esc"
cat > "$dir/esc/rows.json" <<'EOF'
[
 {"id":"E-1","state":"R\u001b]0;pwn\u0007","owner":"o\u001b[2J","ask":"\u001b[31mred ‮rtl\u0085","dependsOn":["E-0\u001b[1m"]},
 {"id":"E-0\u001b[1m","state":"BLOCKED","owner":"x\u009bP","ask":"root\u007f","dependsOn":["E-9\u0007"]}
]
EOF
echo '{broken' > "$dir/esc/$(printf 'bad\033[2J').json"
nocc() { python3 -c 'import sys,re; b=sys.stdin.buffer.read(); sys.exit(1 if re.search(rb"[\x00-\x09\x0b-\x1f\x7f]|\xc2[\x80-\x9f]|\xe2\x80[\x8e\x8f\xaa-\xae]|\xe2\x81[\xa6-\xa9]", b) else 0)'; }
out2=$(chain "$dir/esc"); rc=$?
check "text output: no control, C1 or bidi byte (ESC, BEL, OSC, DEL, U+0085, U+202E) in id, state, owner, ask or the missing id" '(( rc == 0 )) && printf %s "$out2" | nocc && [[ $out2 == *"E-1"*"red"*"waits on E-0"* ]]'
check "stderr notes (a file name with an ESC) are clean too" 'grep -q "skipped bad" "$dir/err" && nocc < "$dir/err"'
out2=$(chain "$dir/esc" --json); rc=$?
check "--json stays valid JSON and its decoded strings hold no control character" '(( rc == 0 )) && python3 -c "
import json,re,sys
d=json.loads(sys.argv[1])
bad=re.compile(u\"[\\x00-\\x1f\\x7f-\\x9f\\u202a-\\u202e]\")
def walk(o):
    if isinstance(o,str): assert not bad.search(o), repr(o)
    elif isinstance(o,list): [walk(x) for x in o]
    elif isinstance(o,dict): [walk(x) for x in list(o.keys())+list(o.values())]
walk(d); assert d[\"chains\"]
" "$out2"'

echo "--- dependsOn of the wrong type"
mkdir "$dir/deps"
cat > "$dir/deps/rows.json" <<'EOF'
[
 {"id":"D-1","state":"READY","ask":"int deps","dependsOn":5},
 {"id":"D-2","state":"READY","ask":"bool deps","dependsOn":true},
 {"id":"D-3","state":"READY","ask":"dict deps","dependsOn":{"D-5":1}},
 {"id":"D-4","state":"READY","ask":"string deps","dependsOn":"D-5"},
 {"id":"D-5","state":"READY","ask":"the root","dependsOn":[]}
]
EOF
out2=$(chain "$dir/deps"); rc=$?
check "int, bool and dict dependsOn: no crash, one warning line per bad row, no dependency taken" '(( rc == 0 )) && [[ $out2 == "1 chain from 5 rows (5 open)"* ]] && ! grep -q Traceback "$dir/err" && [[ $(grep -c "dependsOn" "$dir/err") == 3 ]] && grep -q "D-1" "$dir/err" && grep -q "D-2" "$dir/err" && grep -q "D-3" "$dir/err"'
check "dependsOn as one string is one dependency" '[[ $out2 == *"D-4 [READY"*"waits on D-5 [READY"* ]]'

echo "--- shapes: self dependency, duplicate ids, DONE by column, a diamond, ids glued to text"
mkdir "$dir/misc"
cat > "$dir/misc/a.json" <<'EOF'
[
 {"id":"S-1","state":"READY","ask":"depends on itself","dependsOn":["S-1"]},
 {"id":"DUP","state":"READY","ask":"first copy","dependsOn":["S-2"]},
 {"id":"S-2","state":"READY","ask":"open root","dependsOn":[]},
 {"id":"C-1","column":"done","ask":"done by its column only","dependsOn":[]},
 {"id":"C-2","state":"READY","ask":"waits on a column-done row and S-2","dependsOn":["C-1","S-2"]},
 {"id":"L-1","state":"READY","ask":"see xlib#1 and a/b/lib#2","dependsOn":["S-2"]},
 {"id":"T","state":"READY","ask":"diamond top","dependsOn":["A","B"]},
 {"id":"A","state":"READY","ask":"left","dependsOn":["R"]},
 {"id":"B","state":"READY","ask":"right","dependsOn":["R"]},
 {"id":"R","state":"READY","ask":"shared root","dependsOn":[]}
]
EOF
echo '{"id":"DUP","state":"READY","ask":"second copy","dependsOn":[]}' > "$dir/misc/b.json"
out2=$(chain "$dir/misc" --repos acme/lib); rc=$?
check "a self dependency is one node and one cut marker" '(( rc == 0 )) && [[ $(grep -c "^S-1 " <<<"$out2") == 1 ]] && [[ $(grep -c "waits on S-1" <<<"$out2") == 1 ]] && [[ $out2 == *"waits on S-1 (cycle: already above, cut here)"* ]]'
check "a duplicate id is reported once on stderr (the later file wins)" '[[ $(grep -c "duplicate id DUP" "$dir/err") == 1 ]] && grep -q "b.json" "$dir/err"'
check "a row done by its column alone is hidden and counted" '[[ $out2 == *"C-2 [READY]  (+1 done hidden)"* ]] && ! grep -q "waits on C-1" <<<"$out2"'
check "NAME#N glued to a longer word or path is no PR (xlib#1, a/b/lib#2)" '! grep -q "PR " <<<"$out2"'
check "a shared blocker is expanded once, the second sighting is marked" '[[ $(grep -c "R \[READY" <<<"$out2") == 1 ]] && [[ $out2 == *"waits on R (seen above)"* ]] && grep -q "unblock first: R$" <<<"$out2"'
out3=$(chain "$dir/misc" --repos acme/lib --all)
check "--all shows the DONE blocker but never lists a DONE row under unblock first" '[[ $out3 == *"waits on C-1 ["* ]] && grep "unblock first" <<<"$out3" | grep -q "S-2" && ! grep "unblock first" <<<"$out3" | grep -q "C-1"'
mkdir "$dir/diam"
python3 - "$dir/diam" <<'EOF'
import json, sys
n = 30
rows = [{"id": "ZT", "state": "READY", "ask": "top", "dependsOn": ["L0a", "L0b"]}]
for i in range(n):
    nxt = ["L%da" % (i + 1), "L%db" % (i + 1)] if i < n - 1 else []
    for side in "ab":
        rows.append({"id": "L%d%s" % (i, side), "state": "READY", "ask": "layer", "dependsOn": nxt})
json.dump(rows, open(sys.argv[1] + "/rows.json", "w"))
EOF
check "30 diamond layers (2^30 paths) finish within 20 s" 'python3 -c "
import subprocess,sys
p=subprocess.run([\"python3\",sys.argv[1],sys.argv[2]],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
sys.exit(p.returncode)
" "$BIN/sabha-chain" "$dir/diam"'

echo "--- a very deep chain"
mkdir "$dir/deep"
python3 - "$dir/deep" <<'EOF'
import json, sys
rows = [{"id": "N-%d" % i, "state": "READY", "ask": "x", "dependsOn": ["N-%d" % (i + 1)] if i < 1499 else []} for i in range(1500)]
json.dump(rows, open(sys.argv[1] + "/rows.json", "w"))
EOF
out2=$(chain "$dir/deep"); rc=$?
check "1500 levels: one clear line on stderr, a non-zero exit, no traceback" '(( rc != 0 )) && ! grep -q Traceback "$dir/err" && [[ $(wc -l < "$dir/err" | tr -d " ") == 1 ]] && grep -q "too deep" "$dir/err"'

echo
if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "all checks passed"
