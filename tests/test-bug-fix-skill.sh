#!/usr/bin/env bash
# skills/sabha-bug-fix: text checks only (frontmatter, the proof steps and the safety rules are still there, the
# skills it names exist). Nothing runs a tool. Run: tests/test-bug-fix-skill.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SK=$ROOT/skills/sabha-bug-fix/SKILL.md
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

check "frontmatter name matches the folder" 'sed -n 2p "$SK" | grep -qx "name: sabha-bug-fix"'
check "description carries the trigger phrases" 'sed -n 3p "$SK" | grep -q "Use when asked to \"fix <ticket>\""'
check "SKILL.md is ASCII" '! LC_ALL=C grep -q "[^ -~	]" "$SK"'
check "reproduce comes before fix, and verify after it" '[[ $(grep -n "^2\. \*\*Reproduce" "$SK" | cut -d: -f1) -lt $(grep -n "^4\. \*\*Fix" "$SK" | cut -d: -f1) && $(grep -n "^4\. \*\*Fix" "$SK" | cut -d: -f1) -lt $(grep -n "^8\. \*\*Verify" "$SK" | cut -d: -f1) ]]'
check "before and after screenshots are named" 'grep -q "before-<n>.png" "$SK" && grep -q "after-<n>.png" "$SK"'
check "a red test comes before the fix" 'grep -q "Make it red in code" "$SK"'
check "the worker never pushes; a go line moves the push to the relay or the human" 'grep -q "never to the worker" "$SK" && grep -q "rule 6" "$SK" && ! grep -qi "standing yes" "$SK" && ! grep -q "go:. line names" "$SK"'
check "never: merge, deploy, force-push, shared branch, secret files" 'grep -q "Push to a shared branch, force-push, merge, deploy, or read" "$SK"'
check "never: call it fixed before the tester verifies" 'grep -q "Call it fixed before the tester verifies" "$SK"'
check "heavy runs go through sabha-heavy and exit 75 means wait" 'grep -q "bin/sabha-heavy run" "$SK" && grep -q "exit 75" "$SK" && [[ -x "$ROOT/bin/sabha-heavy" ]]'
check "the status page skill it names exists" 'grep -q "sabha-status-review-page" "$SK" && [[ -f "$ROOT/skills/sabha-status-review-page/SKILL.md" ]]'
check "README lists the skill" 'grep -q "^| \`sabha-bug-fix\` |" "$ROOT/README.md"'
check "CHANGELOG has a line under Unreleased" 'sed -n "/^## Unreleased/,/^## [0-9]/p" "$ROOT/CHANGELOG.md" | grep -q "sabha-bug-fix"'

[[ $fails -eq 0 ]] && echo "ALL OK" || { echo "$fails FAILED"; exit 1; }
