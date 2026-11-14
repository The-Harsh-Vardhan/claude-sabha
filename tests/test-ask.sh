#!/usr/bin/env bash
# bin/sabha-ask: the question lands in inbox/<Elephant>/ask-NNN.md, a fake Elephant writes replies/ask-NNN.md and the
# answer is printed; no reply in time says so and names the file to read; the counter counts answers and cited sources. SABHA_ASK_NUDGE=0: no pane is woken. Run: tests/test-ask.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-ask.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1: $out"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Elephant:opus"\nSABHA_ELEPHANT=Elephant\n' "$dir/ws" "$dir/impl" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_ASK_NUDGE=0 SABHA_ASK_POLL=1 SABHA_ROLE=Karna
ed=$dir/ws/docs/sabha/bhishma
ask() { "$SH" "$BIN/sabha-ask" "$@" 2>&1; }

echo "--- answered"
( sleep 2; printf 'The brief 2057 is open.\nSource: impl/status/yudhishthira.md:12 and impl/inbox/Vidur/2057.md:3 (same file impl/status/yudhishthira.md:40)\n' > "$ed/replies/ask-001.md" ) &
out=$(SABHA_ASK_TIMEOUT=20 ask "which briefs are open?"); rc=$?
wait
check "the reply is printed, exit 0" '(( rc == 0 )) && grep -q "^The brief 2057 is open.$" <<<"$out"'
check "the question is in the Elephant inbox with asker, utc and reply path" 'grep -q "^from: Karna$" "$dir/impl/inbox/Elephant/ask-001.md" && grep -q "^reply: $ed/replies/ask-001.md$" "$dir/impl/inbox/Elephant/ask-001.md" && grep -q "^which briefs are open?$" "$dir/impl/inbox/Elephant/ask-001.md"'
check "counter.tsv: answered with 2 distinct files cited" 'grep -qP "^\S+\t001\tanswered\t2$" "$ed/counter.tsv" 2>/dev/null || awk -F"\t" '"'"'$2 == "001" && $3 == "answered" && $4 == 2 { f = 1 } END { exit !f }'"'"' "$ed/counter.tsv"'

echo "--- no source"
( sleep 1; echo "I think it is open." > "$ed/replies/ask-002.md" ) &
out=$(SABHA_ASK_TIMEOUT=20 ask "is X open?"); rc=$?
wait
check "an answer with no file:line is printed with a warning, id 002" '(( rc == 0 )) && grep -q "I think it is open." <<<"$out" && grep -q "ask-002 has no file:line source" <<<"$out"'

echo "--- timeout"
out=$(SABHA_ASK_TIMEOUT=2 ask "anyone there?"); rc=$?
check "timeout: exit 3, says so, names INDEX.md and the question file" '(( rc == 3 )) && grep -q "no answer from Elephant for ask-003 within 2s" <<<"$out" && grep -q "$ed/INDEX.md" <<<"$out" && [[ -f $dir/impl/inbox/Elephant/ask-003.md ]]'
check "counter.tsv: timeout row, 0 avoided" 'awk -F"\t" '"'"'$2 == "003" && $3 == "timeout" && $4 == 0 { f = 1 } END { exit !f }'"'"' "$ed/counter.tsv"'

echo "--- counter"
out=$(ask --counter)
check "counter: 2 answered today, 2 cited sources" '[[ $out == "questions answered today: 2; cited sources: 2" ]]'
out=$(ask --counter --md)
check "counter --md: the INDEX.md line" 'grep -q "^Counter (20[0-9-]* UTC): 2 questions answered, 2 cited sources$" <<<"$out"'
yesterday="2020-01-01T10:00:00Z"
printf '%s\t900\tanswered\t9\n' "$yesterday" >> "$ed/counter.tsv"
out=$(ask --counter)
check "counter ignores earlier days" '[[ $out == "questions answered today: 2; cited sources: 2" ]]'

echo "--- usage"
out=$(ask); rc=$?
check "no question: usage, exit 2" '(( rc == 2 ))'
out=$(SABHA_ASK_TIMEOUT=abc ask "q"); rc=$?
check "a bad timeout is refused" '(( rc == 2 ))'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
