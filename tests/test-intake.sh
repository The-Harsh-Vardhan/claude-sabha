#!/usr/bin/env bash
# bin/sabha-intake: a note becomes a digest, one brief and one board row per ask; a dry run writes nothing; a rerun
# files nothing twice; bad input is refused loudly; two runs at once do not double-file; a stale lock is taken over.
# Run: tests/test-intake.sh
# shellcheck disable=SC1091,SC2015,SC2012  # hermetic.sh is sourced by every test; A && B || fail is a check chain
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-intake.XXXXXX") || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf SABHA_IMPL=$dir
fail() { echo "FAIL: $*"; exit 1; }
I=$BIN/sabha-intake
inbox() { find "$dir/inbox/Dispatcher" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
rows() { grep -c '^id: ' "$dir/for-me.items" 2>/dev/null; }

cat >"$dir/meeting.md" <<'X'
# Weekly sync
chit chat that belongs to no section

## Facts
- The export job runs at 02:00
- Load peaked at 40

## Decisions:
1. Ship the report behind a flag
Decision: no push before review

## Action items
- [ ] Draft the rollout note
- [x] Check the flag default

Ask: confirm the flag name with the owner
X

# dry run: parsed, listed, nothing written
out=$("$I" "$dir/meeting.md") || fail "dry run failed: $out"
echo "$out" | grep -q '2 facts, 2 decisions, 3 asks, 2 lines skipped' || fail "counts wrong: $out"
echo "$out" | grep -q 'dry run: nothing written' || fail "dry run must say so"
[[ ! -e $dir/inbox && ! -e $dir/for-me.items && ! -e $dir/intake ]] || fail "dry run wrote something"

# apply: digest, 3 briefs, 3 rows, ledger of 6
out=$("$I" --apply "$dir/meeting.md") || fail "apply failed: $out"
[[ $(inbox) -eq 3 ]] || fail "3 briefs expected, got $(inbox)"
[[ $(rows) -eq 3 ]] || fail "3 board rows expected, got $(rows)"
grep -q 'Draft the rollout note' "$dir/inbox/Dispatcher/"001-intake-intake-*-1.md || fail "brief 1 must carry the ask"
grep -q '^to: Dispatcher$' "$dir/inbox/Dispatcher/"001-*.md && grep -q '^from: intake$' "$dir/inbox/Dispatcher/"001-*.md || fail "brief header"
grep -q '^owner: intake$' "$dir/for-me.items" && grep -q '^title: Draft the rollout note$' "$dir/for-me.items" || fail "row owner and title"
dg=$(ls "$dir/intake/digests/"meeting-*.md) || fail "no digest"
grep -q '^- The export job runs at 02:00$' "$dg" && grep -q '^- Ship the report behind a flag$' "$dg" || fail "digest content"
[[ $(wc -l <"$dir/intake/ledger") -eq 6 ]] || fail "ledger must hold 6 lines"
python3 -I "$BIN/sabha-for-me" >/dev/null 2>&1 && grep -q 'Draft the rollout note' "$dir/FOR-ME.md" || fail "the board must show the row"

# rerun: nothing twice, digest untouched
before=$(cksum <"$dg")
out=$("$I" --apply "$dir/meeting.md") || fail "rerun failed"
[[ $(inbox) -eq 3 && $(rows) -eq 3 && $(wc -l <"$dir/intake/ledger") -eq 6 ]] || fail "a rerun must file nothing"
[[ $(cksum <"$dg") == "$before" ]] || fail "digest changed on rerun"
echo "$out" | grep -q 'brief already filed' || fail "rerun must say already filed"

# a different note is new content: new digest, new brief; the old digest stays
printf 'Ask: one more thing\n' >"$dir/second.txt"
"$I" --apply "$dir/second.txt" >/dev/null || fail "second note"
[[ $(inbox) -eq 4 && $(ls "$dir/intake/digests" | wc -l) -eq 2 ]] || fail "second note: 4 briefs, 2 digests"

# drop folder: the transcript of a screenshot is read, a bare image waits; an image is never parsed
mkdir -p "$dir/intake/drop"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00' >"$dir/intake/drop/shot.png"
printf '\x89PNG\x00\x01' >"$dir/intake/drop/lonely.png"
printf 'Fact: seen in Slack\nAsk: reply to the customer\n' >"$dir/intake/drop/shot.txt"
out=$("$I") || fail "drop scan failed: $out"
echo "$out" | grep -q 'lonely.png: waiting for a transcript' || fail "a bare image must wait"
echo "$out" | grep -q '1 facts, 0 decisions, 1 asks' || fail "transcript not read: $out"
if "$I" "$dir/intake/drop/lonely.png" >/dev/null 2>&1; then fail "a binary file must be refused"; fi

# hostile text: ESC, OSC, CR, bidi, DEL and non-ASCII never reach the terminal or a file as raw bytes
printf 'Ask: do \033]0;pwned\007it\r now \xe2\x80\xae evil \x7f caf\xc3\xa9\nFact: ok\n' >"$dir/evil.txt"
out=$("$I" --apply "$dir/evil.txt") || fail "evil note"
printf '%s' "$out" | LC_ALL=C grep -q $'\033' && fail "ESC reached the terminal"
printf '%s' "$out" | LC_ALL=C grep -q $'\r' && fail "CR reached the terminal"
for f in "$dir"/intake/digests/evil-*.md "$dir"/inbox/Dispatcher/*evil* "$dir/for-me.items" "$dir/intake/ledger"; do
  [[ -e $f ]] || continue
  [[ -z $(LC_ALL=C tr -d '\11\12\40-\176' <"$f") ]] || fail "non-ASCII or control byte in $f"
done
grep -rq 'evil' "$dir/inbox/Dispatcher" || fail "evil brief not filed"

# bad input
: >"$dir/empty.txt"
if "$I" "$dir/empty.txt" >/dev/null 2>&1; then fail "empty file must exit 1"; fi
printf '{"asks": 5}\n[1,2,3]\n' >"$dir/json.txt"
out=$("$I" --apply "$dir/json.txt" 2>&1) && fail "wrong-type JSON must exit 1"
echo "$out" | grep -q 'nothing found' || fail "JSON note must say nothing found"
out=$("$I" "$dir/missing.txt" 2>&1) && fail "missing file must exit 1"
echo "$out" | grep -q 'could not read' || fail "missing file must say could not read"
head -c 2000000 /dev/zero | tr '\0' 'a' >"$dir/huge.txt"
out=$("$I" "$dir/huge.txt" 2>&1) && fail "a huge file must exit 1"
echo "$out" | grep -q 'larger than' || fail "huge file message"
for bad in "--to" "--from" "--dir"; do
  "$I" "$bad" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "$bad with no value must exit 2"
done
"$I" --to --apply "$dir/second.txt" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "--to followed by a flag must exit 2"
"$I" --nope >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "unknown option must exit 2"
"$I" --to 'bad name' "$dir/second.txt" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "bad role name must exit 2"
n=$(inbox); "$I" --apply "$dir/empty.txt" >/dev/null 2>&1; [[ $(inbox) -eq $n ]] || fail "a refused file must file nothing"

# half-way stop: the board cannot be written (status/item-ids is a file), the brief is filed, the rerun adds the row only
rm -rf "$dir/for-me.items" "$dir/status/item-ids" "$dir/intake/ledger"
mkdir -p "$dir/status"; : >"$dir/status/item-ids"
printf 'Ask: half way ask\n' >"$dir/half.txt"
b=$(inbox)
if "$I" --apply "$dir/half.txt" >/dev/null 2>&1; then fail "a failed board write must exit 1"; fi
[[ $(inbox) -eq $((b + 1)) ]] || fail "the brief must be filed before the row fails"
rm -f "$dir/status/item-ids"
"$I" --apply "$dir/half.txt" >/dev/null || fail "resume failed"
[[ $(inbox) -eq $((b + 1)) ]] || fail "resume must not file the brief twice"
[[ $(rows) -eq 1 ]] || fail "resume must file the row, got $(rows)"

# two runs at once on one new note: each ask filed once
printf 'Ask: race one\nAsk: race two\nAsk: race three\n' >"$dir/race.txt"
b=$(inbox)
"$I" --apply "$dir/race.txt" >/dev/null 2>&1 & p1=$!
"$I" --apply "$dir/race.txt" >/dev/null 2>&1 & p2=$!
wait $p1; wait $p2
[[ $(inbox) -eq $((b + 3)) ]] || fail "two runs at once must file 3 briefs, got $(( $(inbox) - b ))"
[[ ! -d $dir/intake/ledger.lock ]] || fail "lock left behind"

# a stale lock (dead run) is taken over
printf 'Ask: after stale lock\n' >"$dir/stale.txt"
mkdir "$dir/intake/ledger.lock"; touch -t 202001010000 "$dir/intake/ledger.lock"
b=$(inbox)
"$I" --apply "$dir/stale.txt" >/dev/null 2>&1 || fail "stale lock must be taken over"
[[ $(inbox) -eq $((b + 1)) && ! -d $dir/intake/ledger.lock ]] || fail "stale lock run result"

# a symlinked digest folder is refused
rm -rf "$dir/intake/digests"; mkdir "$dir/elsewhere"; ln -s "$dir/elsewhere" "$dir/intake/digests"
printf 'Ask: symlink ask\n' >"$dir/sym.txt"
if "$I" --apply "$dir/sym.txt" >/dev/null 2>&1; then fail "symlinked digests dir must be refused"; fi
[[ -z $(ls "$dir/elsewhere") ]] || fail "wrote through a symlink"
echo "ok: intake parses notes, dry run writes nothing, apply files digest + brief + row once, bad input refused, locks and resume hold"
