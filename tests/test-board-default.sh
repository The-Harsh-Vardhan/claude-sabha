#!/usr/bin/env bash
# The progress board as the default view: the relay text (skill and conf prompt), /sabha-board, the README. Text checks
# only; nothing runs a tool. Run: tests/test-board-default.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
KEEP='keep the board current: write each human decision the same turn, read remote edits at every status check'

echo "--- relay text"
check "the sabha-relay skill says to keep the board current" 'tr "\n" " " <"$ROOT/skills/sabha-relay/SKILL.md" | tr -s " " | grep -qF "$KEEP"'
check "the relay prompt in sabha.conf.example says it" 'grep "^SABHA_PROMPT_Relay=" "$ROOT/sabha.conf.example" | grep -qF "$KEEP"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: the board is the default view in the relay text, /sabha-board and the README"
