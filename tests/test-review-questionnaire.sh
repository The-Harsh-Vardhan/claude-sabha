#!/usr/bin/env bash
# skills/sabha-review-questionnaire: build.py on a sample questions file (page content, refusal to overwrite, parse
# errors, escaping) and the skill's frontmatter. The page's JavaScript is not run. Run: tests/test-review-questionnaire.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SK=$ROOT/skills/sabha-review-questionnaire
FX=$ROOT/tests/fixtures/review-questionnaire
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
T=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rq.XXXXXX") || exit 2
trap 'rm -rf "$T" "$HERMETIC_FAKE_DIR"' EXIT

echo "--- skill file"
check "frontmatter name matches the folder" 'sed -n 2p "$SK/SKILL.md" | grep -qx "name: sabha-review-questionnaire"'
check "description starts with a trigger" 'sed -n 3p "$SK/SKILL.md" | grep -q "^description: .*Use for /sabha-review-questionnaire"'
check "SKILL.md, build.py and template.html are ASCII" '! LC_ALL=C grep -q "[^ -~	]" "$SK/SKILL.md" "$SK/build.py" "$SK/template.html"'

echo "--- build"
out=$(python3 "$SK/build.py" "$FX/sample.md" "$T/q.html" 2>&1); rc=$?
check "sample builds with 3 questions and 3 recommendations" '[[ $rc -eq 0 && $out == *": 3 questions, 3 with recommendation" ]]'
check "no template placeholder is left" '! grep -q "{{" "$T/q.html"'
check "Q2 keeps its pre-filled Other answer" 'grep -q "value=\"ask design first\"" "$T/q.html"'
check "Q3 pre-checks option B" 'grep -q "name=\"q3\" value=\"B\" checked" "$T/q.html"'
check "html in a title is escaped" 'grep -q "&lt;b&gt;not html&lt;/b&gt;" "$T/q.html" && ! grep -q "<b>not html</b>" "$T/q.html"'
check "a backtick span becomes code" 'grep -q "<code>/uploads</code>" "$T/q.html"'
check "the note section renders as a note card" 'grep -q "notecard" "$T/q.html"'
out=$(python3 "$SK/build.py" "$FX/sample.md" "$T/q.html" 2>&1); rc=$?
check "an existing output file is not overwritten" '[[ $rc -eq 1 && $out == *"refusing to overwrite"* ]]'

echo "--- parse errors"
printf '# T\n\n## Q1 - a: one\n- A (recommended): x\n' >"$T/one-option.md"
out=$(python3 "$SK/build.py" "$T/one-option.md" "$T/o1.html" 2>&1); rc=$?
check "one option is rejected" '[[ $rc -eq 1 && $out == *"needs at least 2 options"* ]]'
printf '# T\n\n## Q1 - a: one\n- A: x\n- B: y\n' >"$T/no-rec.md"
out=$(python3 "$SK/build.py" "$T/no-rec.md" "$T/o2.html" 2>&1); rc=$?
check "no recommendation is rejected" '[[ $rc -eq 1 && $out == *"exactly 1 option marked (recommended)"* ]]'
printf '# T\n\nno questions here\n' >"$T/none.md"
out=$(python3 "$SK/build.py" "$T/none.md" "$T/o3.html" 2>&1); rc=$?
check "a file with no questions is rejected" '[[ $rc -eq 1 && $out == *"no questions found"* ]]'

echo "--- README and CHANGELOG"
check "README lists the skill" 'grep -q "^| \`sabha-review-questionnaire\` |" "$ROOT/README.md"'
check "CHANGELOG has a line under Unreleased" 'sed -n "/^## Unreleased/,/^## [0-9]/p" "$ROOT/CHANGELOG.md" | grep -q "sabha-review-questionnaire"'

[[ $fails -eq 0 ]] && echo "ALL OK" || { echo "$fails FAILED"; exit 1; }
