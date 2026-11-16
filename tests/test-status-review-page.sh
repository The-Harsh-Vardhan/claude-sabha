#!/usr/bin/env bash
# skills/sabha-status-review-page: build_page.py on a sample spec (group order, cascade order, before-left and
# after-right, a missing side, escaping, spec errors) and the skill's frontmatter. Run: tests/test-status-review-page.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SK=$ROOT/skills/sabha-status-review-page
FX=$ROOT/tests/fixtures/status-review-page
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
T=$(mktemp -d "${TMPDIR:-/tmp}/sabha-srp.XXXXXX") || exit 2
trap 'rm -rf "$T" "$HERMETIC_FAKE_DIR"' EXIT
pos() { grep -bo -- "$1" "$T/p.html" | head -1 | cut -d: -f1; }

echo "--- skill file"
check "frontmatter name matches the folder" 'sed -n 2p "$SK/SKILL.md" | grep -qx "name: sabha-status-review-page"'
check "description starts with the page and ends with a trigger" 'sed -n 3p "$SK/SKILL.md" | grep -q "^description: Build a status or review page.*Use when asked for a status page"'
check "SKILL.md and build_page.py are ASCII" '! LC_ALL=C grep -q "[^ -~	]" "$SK/SKILL.md" "$SK/build_page.py"'

echo "--- build"
out=$(python3 "$SK/build_page.py" "$FX/spec.json" "$T/p.html" 2>&1); rc=$?
check "sample builds and reports 4 items" '[[ $rc -eq 0 && $out == *": 4 items" ]]'
check "the title is escaped" 'grep -q "<title>Sample &lt;Status&gt; Page</title>" "$T/p.html"'
check "a dep comes before its dependent (BUG-1 numbered 2, BUG-2 numbered 3)" 'grep -q "id=\"i2\"><h3>2. BUG-1 " "$T/p.html" && grep -q "id=\"i3\"><h3>3. <a href=\"https://tracker.example.com/browse/BUG-2\">BUG-2" "$T/p.html"'
check "BUG-2 says it builds on BUG-1" 'grep -q "Builds on:</b> <a href=\"#i2\">2. BUG-1" "$T/p.html"'
check "BUG-1 says it is also visible in BUG-2" 'grep -q "Also visible in:</b> <a href=\"#i3\">3. BUG-2" "$T/p.html"'
check "a group split by a cross-group dep gets a (continued) heading" 'grep -q "1. Fixed, verified by the tester (continued)" "$T/p.html"'
check "BEFORE head comes before AFTER head" '[[ $(pos "head b\">BEFORE") -lt $(pos "head a\">AFTER") ]]'
check "a missing before shot is a dashed cell" 'grep -q "class=\"none\">No before shot" "$T/p.html"'
check "a blast-radius box is drawn from percent values" 'grep -q "left:10%;top:20%;width:30%;height:10%" "$T/p.html"'
check "the legend, verify steps and self review render" 'grep -q "What each status means" "$T/p.html" && grep -q "How to verify it yourself" "$T/p.html" && grep -q "id=\"review\"" "$T/p.html"'

echo "--- spec errors"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s["groups"][0]["items"][1]["deps"]=["NOPE"]; json.dump(s,open(sys.argv[2],"w"))' "$FX/spec.json" "$T/bad-dep.json"
out=$(python3 "$SK/build_page.py" "$T/bad-dep.json" "$T/b1.html" 2>&1); rc=$?
check "an unknown dep exits 1 with a spec error" '[[ $rc -eq 1 && $out == *"spec error: BUG-2 depends on unknown NOPE"* ]]'
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s["groups"][1]["items"][0]["deps"]=["BUG-2"]; json.dump(s,open(sys.argv[2],"w"))' "$FX/spec.json" "$T/cycle.json"
out=$(python3 "$SK/build_page.py" "$T/cycle.json" "$T/b2.html" 2>&1); rc=$?
check "a dependency cycle exits 1 with a spec error" '[[ $rc -eq 1 && $out == *"spec error: dependency cycle"* ]]'

echo "--- README and CHANGELOG"
check "README lists the skill" 'grep -q "^| \`sabha-status-review-page\` |" "$ROOT/README.md"'
check "CHANGELOG has a line under Unreleased" 'sed -n "/^## Unreleased/,/^## [0-9]/p" "$ROOT/CHANGELOG.md" | grep -q "sabha-status-review-page"'

[[ $fails -eq 0 ]] && echo "ALL OK" || { echo "$fails FAILED"; exit 1; }
