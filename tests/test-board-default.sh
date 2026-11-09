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

echo "--- README and CHANGELOG"
check "README names the board as the default view and FOR-ME.md as the offline fallback" 'grep -n "SABHA_BOARD_URL" "$ROOT/README.md" | grep -qi "default" && sed -n "/^## Remote control and progress/,/^## Limits/p" "$ROOT/README.md" | grep -q "offline fallback"'
check "CHANGELOG has the board line under Unreleased" 'sed -n "/^## Unreleased/,/^## /p" "$ROOT/CHANGELOG.md" | grep -q "SABHA_BOARD_URL"'

echo "--- board template and sabha-board-create skill"
# tpl_problems <root>: one tag per problem found in <root>/template/board and <root>/skills/sabha-board-create
tpl_problems() {
  local r=$1 t=$1/template/board s=$1/skills/sabha-board-create/SKILL.md f p re pats n=0
  for f in "$t"/index.html "$t"/board-schema.md "$t"/board.capabilities.json "$s"; do
    LC_ALL=C grep -q $'[^\t -~]' "$f" && echo "non-ascii:${f##*/}"
    grep -qE 'claude\.ai/(code/)?artifact' "$f" && echo "artifact-url:${f##*/}"
  done
  # the shipped leak patterns, read from tests/test-leak.sh the way it uses them (local/leak-patterns is not read)
  pats=$(sed -n "/^PATTERNS=(/,/^)/p" "$ROOT/tests/test-leak.sh" | sed -n "s/^  '\(.*\)'\$/\1/p")
  re=$(printf '%s\n' "$pats" | paste -sd'|' -)
  for f in "$t"/index.html "$t"/board-schema.md "$t"/board.capabilities.json "$s"; do
    grep -qiE -e "$re" "$f" && echo "leak-name:${f##*/}"
  done
  python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$t/board.capabilities.json" 2>/dev/null || echo "capabilities-json"
  for p in $(grep -o '__[A-Z_]*__' "$t/index.html" | sort -u); do
    n=$((n + 1)); grep -qF "\`$p\`" "$t/board-schema.md" || echo "undocumented:$p"
  done
  (( n > 0 )) || echo "no-placeholders"
  [[ $(sed -n 2p "$s") == "name: sabha-board-create" ]] || echo "skill-name"
  grep -q SABHA_BOARD_URL "$s" || echo "skill-url-key"
}
got=$(tpl_problems "$ROOT")
check "the template and the skill pass every check (no non-ASCII, artifact URL, leak-pattern name, bad JSON, undocumented placeholder)" '[[ -z $got ]]'
[[ -z $got ]] || printf '      %s\n' $got
BAD=$(mktemp -d "${TMPDIR:-/tmp}/board-bad.XXXXXX") || exit 2
mkdir -p "$BAD/template" "$BAD/skills"
cp -R "$ROOT/template/board" "$BAD/template/board"; cp -R "$ROOT/skills/sabha-board-create" "$BAD/skills/"
{ printf '<p>caf\303\251 https://claude.ai/artifact/abc Har%s __NEW_ONE__</p>\n' sh; cat "$BAD/template/board/index.html"; } >"$BAD/i" && mv "$BAD/i" "$BAD/template/board/index.html"
echo '{' >"$BAD/template/board/board.capabilities.json"
sed -i.bak 's/^name: sabha-board-create/name: other/; s/SABHA_BOARD_URL/X/g' "$BAD/skills/sabha-board-create/SKILL.md"
bad=$(tpl_problems "$BAD")
for tag in non-ascii:index.html artifact-url:index.html leak-name:index.html capabilities-json undocumented:__NEW_ONE__ skill-name skill-url-key; do
  check "a bad copy is caught: $tag" 'grep -qxF "$tag" <<<"$bad"'
done
rm -rf "$BAD"

T=$ROOT/template/board/index.html
check "the page reads the legacy bhishma collection as well as architect" 'grep -q "watch(\"architect\"" "$T" && grep -q "watch(\"bhishma\"" "$T"'
check "the page never writes to bhishma" '! grep -E "bhishma/|collection\(\"bhishma\"\)\.(add|doc)" "$T" | grep -q .'
check "board-schema.md documents bhishma as an alias of architect" 'grep -q "legacy collection .bhishma. is read as an alias of .architect." "$ROOT/template/board/board-schema.md"'

echo "--- sabha.conf.example"
check "sabha.conf.example documents SABHA_BOARD_URL (a comment, then the key)" 'grep -B3 "^SABHA_BOARD_URL=" "$ROOT/sabha.conf.example" | grep -q "^# .*SABHA_BOARD_URL\|^# The progress board"'
check "sabha.conf.example has SABHA_RELAY_ALLOW_TOOLS empty, after SABHA_RELAY_GUARD, naming Artifact,ArtifactData" 'grep -q "^SABHA_RELAY_ALLOW_TOOLS=\"\"$" "$ROOT/sabha.conf.example" && [[ $(grep -n "^SABHA_RELAY_GUARD=" "$ROOT/sabha.conf.example" | cut -d: -f1) -lt $(grep -n "^SABHA_RELAY_ALLOW_TOOLS=" "$ROOT/sabha.conf.example" | cut -d: -f1) ]] && grep -B6 "^SABHA_RELAY_ALLOW_TOOLS=" "$ROOT/sabha.conf.example" | grep -q "Artifact,ArtifactData"'
check "sabha-board-create tells the user to set SABHA_RELAY_ALLOW_TOOLS=Artifact,ArtifactData" 'grep -q "SABHA_RELAY_ALLOW_TOOLS=Artifact,ArtifactData" "$ROOT/skills/sabha-board-create/SKILL.md"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: the board is the default view in the relay text, /sabha-board and the README"
