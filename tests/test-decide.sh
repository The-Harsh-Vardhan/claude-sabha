#!/usr/bin/env bash
# bin/sabha-decide: one answer becomes an update block, a questions block and a numbered log line, and nothing else
# changes; bad input is refused (never a crash, never a loop); outputs are pure ASCII; two runs at once get two numbers.
# Hermetic: temp workspaces only, no herdr, no network. Run: tests/test-decide.sh
# DECIDE_TEST_BIN=<dir> runs the same rows against another copy of bin/ (used to prove a row fails on a broken copy).
# shellcheck disable=SC1091,SC2015,SC2016  # sourced helper; A && B || fail is the check idiom; conf lines keep $SABHA_IMPL literal
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=${DECIDE_TEST_BIN:-$(cd "$(dirname "$0")/../bin" && pwd)}
top=$(mktemp -d "${TMPDIR:-/tmp}/sabha-decide.XXXXXX") || exit 1
trap 'rm -rf "$top" "$HERMETIC_FAKE_DIR"' EXIT
n=0
fail() { echo "FAIL: $*"; exit 1; }
pass() { n=$((n + 1)); }

# newws <name>: a workspace dir with a conf; sets W and exports the conf for the tool
newws() {
  W=$top/$1; mkdir -p "$W"
  printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Worker:sonnet"\n' "$W" "$W" >"$W/sabha.conf"
  export SABHA_CONF=$W/sabha.conf SABHA_IMPL=$W
  : >"$W/for-me.items"
}
# qitem <id> [question text]: an open question item with two options
qitem() {
  printf -- '---\nid: %s\nutc: 2026-11-01T10:00:00Z\nowner: Relay\nstate: OPEN\ntitle: item %s\nask: Pat\nq: %b\nexplain: why\nopta: develop | newest | x\noptb: release | stable | y\nrec: b\n' \
    "$1" "$1" "${2:-Which branch?}" >>"$W/for-me.items"
}
# run <args>: out = stdout, err = stderr, rc = exit code
run() { out=$(python3 -I "$BIN/sabha-decide" "$@" 2>"$top/err"); rc=$?; err=$(cat "$top/err"); }
board() { python3 -I "$BIN/sabha-for-me" >/dev/null 2>&1; grep -c '^### [0-9]' "$W/FOR-ME.md"; }
nonascii() { LC_ALL=C grep -q -v '^[ -~]*$' "$1"; }

# ---- workspace A: the main path
newws a
qitem 7; qitem 11; qitem 12
printf -- '---\nid: 8\nutc: 2026-11-01T10:00:00Z\nowner: Relay\nstate: OPEN\ntitle: a plain item\n' >>"$W/for-me.items"
printf -- '---\nid: 10\nutc: 2026-11-01T10:00:00Z\nowner: Relay\nstate: OPEN\ntitle: closed\nq: Q?\nopta: a\noptb: b\n---\nid: 10\nutc: 2026-11-01T11:00:00Z\nstate: DONE\n' >>"$W/for-me.items"
before=$(cksum <"$W/for-me.items")
boards_before=$(board)

run "Answer 7: B - release, note: it is stable"
[[ $rc -eq 0 ]] || fail "pasted line: exit $rc, err: $err"
[[ $(cksum <"$W/for-me.items") == "$before" ]] || fail "for-me.items must not change (no live board write)"
upd=$W/board-updates/item-7.update
grep -qx 'state: DONE' "$upd" && grep -qx 'decision: D1' "$upd" && grep -qx 'answer: B' "$upd" \
  && grep -qx 'reply: release' "$upd" && grep -qx 'note: it is stable' "$upd" || fail "update block wrong: $(cat "$upd")"
grep -q '^D1 | .* | item 7 | B | release$' "$W/decisions.log" || fail "log line wrong: $(cat "$W/decisions.log")"
grep -q '^## Answer to item 7 (D1)' "$W/questions/item-7.md" && grep -qx 'Answer: B - release' "$W/questions/item-7.md" \
  && grep -qx 'Recommended: B' "$W/questions/item-7.md" && grep -qx 'Note: it is stable' "$W/questions/item-7.md" || fail "questions block wrong"
[[ $out == *"cat $upd >> $W/for-me.items"* ]] || fail "the close command must be printed: $out"
pass

cat "$upd" >>"$W/for-me.items"
[[ $(board) -eq $((boards_before - 1)) ]] || fail "the appended update must close the item on the board"
pass

run 11 A --note "second"
[[ $rc -eq 0 ]] && grep -q '^D2 | .* | item 11 | A | develop$' "$W/decisions.log" || fail "second decision must be D2: rc $rc $(cat "$W/decisions.log")"
pass

run 12 "do something else | entirely"
[[ $rc -eq 0 ]] && grep -qx 'answer: text' "$W/board-updates/item-12.update" \
  && grep -q '^D3 | .* | item 12 | text | do something else / entirely$' "$W/decisions.log" || fail "free text answer: rc $rc $(cat "$W/decisions.log")"
pass

lines=$(wc -l <"$W/decisions.log")
run 11 B
[[ $rc -eq 1 && $err == *"already decided as D2"* ]] || fail "a second answer for item 11 must be refused: rc $rc $err"
[[ $(wc -l <"$W/decisions.log") -eq $lines && $(grep -c '^## Answer' "$W/questions/item-11.md") -eq 1 ]] || fail "a refused rerun must write nothing"
[[ ! -d $W/decisions.log.lock ]] || fail "the lock must be released after a refusal"
pass

run 8 A;  [[ $rc -eq 1 && $err == *"not a question item"* ]] || fail "plain item: rc $rc $err"
run 10 A; [[ $rc -eq 1 && $err == *"already DONE"* ]] || fail "closed item: rc $rc $err"
run 99 A; [[ $rc -eq 1 && $err == *"no item 99"* ]] || fail "unknown item: rc $rc $err"
pass

# ---- bad input: usage errors exit 2 and write nothing
newws b
qitem 5
for args in "" "x A" "5" "5 A --note" "5 A --log" "5 A --log --note x" "5 A --bogus 1" "Answer 5:" "Answer x: A"; do
  # shellcheck disable=SC2086  # the rows are word lists on purpose
  run $args
  [[ $rc -eq 2 ]] || fail "args '$args' must exit 2, got $rc ($err)"
done
run 5 Z; [[ $rc -eq 2 && $err == *"options: A, B"* ]] || fail "a letter with no option must exit 2 naming the options: $rc $err"
[[ ! -e $W/decisions.log && ! -e $W/board-updates ]] || fail "usage errors must write nothing"
pass

# ---- a missing and a huge for-me.items are refused, not crashed on
newws c
rm -f "$W/for-me.items"
run 1 A; [[ $rc -eq 1 && $err == *"could not read"* ]] || fail "missing for-me.items: rc $rc $err"
python3 -I -c "import sys; open(sys.argv[1], 'w').truncate(9 * 1024 * 1024)" "$W/for-me.items"
run 1 A; [[ $rc -eq 1 && $err == *"could not read"* && $err == *"larger"* ]] || fail "huge for-me.items: rc $rc $err"
pass

# ---- control characters and non-ASCII never reach a terminal or a file
newws d
qitem 9 'Which \xc3\xa9 \x1b]0;pwn\x07 \xe2\x80\xae \xc2\x9b31m?'
run 9 A --note "$(printf 'a\033[31m\rb\nstate: DROPPED\n---\n')"
[[ $rc -eq 0 ]] || fail "hostile item: rc $rc $err"
for f in "$W/board-updates/item-9.update" "$W/questions/item-9.md" "$W/decisions.log"; do
  nonascii "$f" && fail "$f holds a byte outside printable ASCII"
done
printf '%s\n' "$out" >"$top/out"; nonascii "$top/out" && fail "stdout holds a byte outside printable ASCII"
[[ $(grep -c '^state:' "$W/board-updates/item-9.update") -eq 1 && $(grep -c '^---$' "$W/board-updates/item-9.update") -eq 1 ]] || fail "a note must stay one line: $(cat "$W/board-updates/item-9.update")"
pass

# ---- an existing log with non-ASCII bytes and no final newline: numbering continues, the new line starts on its own line
newws e
qitem 3
printf 'D41 | 2026-11-01T10:00:00Z | item 1 | A | caf\xc3\xa9\nnoise\nD7 | x | item 2 | A | old' >"$W/decisions.log"
run 3 B
[[ $rc -eq 0 && $(tail -n 1 "$W/decisions.log") == D42\ \|* ]] || fail "numbering after a hand-edited log: rc $rc $err $(cat "$W/decisions.log")"
[[ $(wc -l <"$W/decisions.log") -eq 4 ]] || fail "the new line must start on its own line"
pass

# ---- two runs at once: distinct numbers, no lost line, lock gone
newws f
for i in 1 2 3 4 5 6; do qitem "$i"; done
for i in 1 2 3 4 5 6; do python3 -I "$BIN/sabha-decide" "$i" A >/dev/null 2>&1 & done; wait
[[ $(wc -l <"$W/decisions.log") -eq 6 && $(cut -d' ' -f1 "$W/decisions.log" | sort -u | wc -l) -eq 6 ]] || fail "six parallel decides need six lines and six numbers: $(cat "$W/decisions.log")"
[[ $(cut -d' ' -f1 "$W/decisions.log" | sort | tr '\n' ' ') == "D1 D2 D3 D4 D5 D6 " ]] || fail "numbers must be D1..D6"
[[ ! -d $W/decisions.log.lock ]] || fail "the lock must be gone after the runs"
pass

# ---- a stale lock from a dead run is taken over; a symlinked target is refused
newws g
qitem 1; qitem 2
mkdir "$W/decisions.log.lock"; touch -t 202001010000 "$W/decisions.log.lock"
run 1 A; [[ $rc -eq 0 && ! -d $W/decisions.log.lock ]] || fail "a stale lock must be taken over and released: rc $rc $err"
ln -s "$top/elsewhere" "$W/questions/item-2.md"
run 2 A; [[ $rc -eq 1 && $err == *symlink* && ! -e $top/elsewhere ]] || fail "a symlinked questions file must be refused: rc $rc $err"
pass

# ---- config values expand $VAR and ~ like the other readers; --questions beats the config
newws h
qitem 4; qitem 6
mkdir -p "$W/cfg"
printf 'SABHA_DECIDE_OUT=~/out\nSABHA_DECISION_LOG=$SABHA_IMPL/logs/dec.log\nSABHA_DECIDE_QUESTIONS=pr-questions.md\n' >>"$W/sabha.conf"
HOME=$W/cfg run 4 A
[[ $rc -eq 0 && -f $W/cfg/out/item-4.update && -f $W/logs/dec.log && -f $W/pr-questions.md ]] || fail "conf paths: rc $rc $err $(ls -R "$W")"
HOME=$W/cfg run 6 B --questions "$W/mine.md" --log "$W/own.log" --out "$W/own"
[[ $rc -eq 0 && -f $W/mine.md && -f $W/own.log && -f $W/own/item-6.update ]] || fail "command-line paths must win: rc $rc $err"
pass

# ---- the front door: bin/sabha decide reaches the tool with the same config
newws i
qitem 2
out=$("$BIN/sabha" decide "Answer 2: A" 2>&1); rc=$?
[[ $rc -eq 0 && -f $W/board-updates/item-2.update ]] || fail "bin/sabha decide: rc $rc $out"
pass

echo "ok: $n checks (update/questions/log files, no live write, refusals, ascii-only, parallel numbering, locks, config paths)"
