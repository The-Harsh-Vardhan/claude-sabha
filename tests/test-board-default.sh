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

echo "--- /sabha-board"
CMD=$ROOT/commands/sabha-board.md
check "/sabha-board reads SABHA_BOARD_URL" 'grep -q "SABHA_BOARD_URL" "$CMD"'
check "/sabha-board tells the user the URL to open and sync, before the FOR-ME run" 'grep -qi "open and sync" "$CMD" && [[ $(grep -n "SABHA_BOARD_URL" "$CMD" | head -1 | cut -d: -f1) -lt $(grep -n "^[0-9]*\. Run " "$CMD" | head -1 | cut -d: -f1) ]]'
check "/sabha-board never publishes or writes an artifact itself" 'grep -qi "never publish" "$CMD" && grep -qi "artifact" "$CMD"'
check "/sabha-board changes nothing when the key is empty" 'grep -qi "empty" "$CMD" && grep -q "unchanged" "$CMD"'
check "/sabha-board still renders FOR-ME.md and walks the open items" 'grep -q "bin/sabha-for-me" "$CMD" && grep -q "FOR-ME.md" "$CMD"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: the board is the default view in the relay text, /sabha-board and the README"
