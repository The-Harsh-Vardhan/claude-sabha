#!/usr/bin/env bash
# sabha owe: open send-type for-me items, unsent drafts and the board rows they block; done, sent and plain items stay out.
# Run: tests/test-owe.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-owe.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$dir/impl" "$dir/drafts"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s/impl\nSABHA_ROSTER="Relay:opus Worker:sonnet"\nSABHA_OWE_DIRS=drafts\nSABHA_OWE_BOARD=%s/board.json\n' \
  "$dir" "$dir" "$dir" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
cat >"$dir/impl/for-me.items" <<'X'
---
id: 3
utc: 2026-10-01T09:00:00Z
owner: Relay
state: OPEN
title: send Sam the release note
why: Sam cannot start without it
unblocks: the picker for release
---
id: 4
utc: 2026-10-02T09:00:00Z
owner: Relay
state: OPEN
title: send Kim the old note
---
id: 4
utc: 2026-10-03T09:00:00Z
state: DONE sent
---
id: 5
utc: 2026-10-02T09:00:00Z
owner: Relay
state: OPEN
title: pick a branch
---
X
printf '# Update for Sam\nto: Sam\nbody\n' >"$dir/drafts/a.md"
printf '# Already sent\nbody\n' >"$dir/drafts/b.md"
: >"$dir/drafts/b.md.sent"
printf '# Also sent\nsent: 2026-10-05\n' >"$dir/drafts/c.md"
printf 'not a draft\n' >"$dir/drafts/d.bin"
touch -t 202610050900 "$dir/drafts/a.md"
cat >"$dir/board.json" <<'X'
{"rows": [{"id": "Q-1", "dependsOn": "F-3, F-30"}, {"id": "Q-2", "unblocks": "a.md goes out"}, {"id": "Q-3", "dependsOn": "F-30"}]}
X

out=$("$BIN/sabha" owe) || fail "sabha owe exited non-zero"
echo "$out" | grep -q 'for-me 3' || fail "open send item 3 must be listed"
echo "$out" | grep -q 'the picker for release, Q-1' || fail "item 3 must show its unblocks text and Q-1 (not Q-3: F-30 is another id)"
echo "$out" | grep -q 'Sam .*for-me 3' || fail "the person after the verb is the to column"
echo "$out" | grep -q 'for-me 4' && fail "a DONE item must not be listed"
echo "$out" | grep -q 'for-me 5' && fail "an item with no send word must not be listed"
echo "$out" | grep -q 'drafts/a.md.*Q-2' || fail "unsent draft a.md must be listed with Q-2"
echo "$out" | grep -q 'b.md\|c.md\|d.bin' && fail "sent drafts and non-drafts must not be listed"
[[ $(echo "$out" | sed -n 2p) == *"for-me 3"* ]] || fail "oldest first: item 3 (1 Oct) before the draft (5 Oct)"

"$BIN/sabha" owe --sent "$dir/drafts/a.md" || fail "--sent failed"
[[ -f $dir/drafts/a.md.sent ]] || fail "--sent must write the marker"
"$BIN/sabha" owe | grep -q 'a.md' && fail "a draft marked sent must leave the list"
"$BIN/sabha" owe --sent "$dir/drafts/none.md" 2>/dev/null && fail "--sent on a missing file must fail"

printf -- '---\nid: 3\nutc: 2026-10-06T09:00:00Z\nstate: DONE\n' >>"$dir/impl/for-me.items"
[[ $("$BIN/sabha" owe) == "nothing owed" ]] || fail "nothing left must print: nothing owed"

# review 208 fixes: --sent confinement, send-word filter, asked: age, hostile board and draft text
mkdir -p "$dir/other" "$dir/m2/impl" "$dir/m2/drafts"
printf 'x\n' >"$dir/other/notadraft.txt"
"$BIN/sabha" owe --sent "$dir/other/notadraft.txt" 2>/dev/null && fail "--sent outside SABHA_OWE_DIRS must fail"
[[ -e $dir/other/notadraft.txt.sent ]] && fail "--sent outside SABHA_OWE_DIRS must write no marker"
cat >"$dir/m2/impl/for-me.items" <<'ITEMS'
---
id: ask-a
utc: 2026-10-01T09:00:00Z
title: we ask a bit about colours
---
id: sup
utc: 2026-10-01T09:00:00Z
title: send Zed the note
state: SUPERSEDED (by 9)
---
id: why-only
utc: 2026-10-01T09:00:00Z
title: check the logs
why: we may send later
---
id: quest
utc: 2026-10-01T09:00:00Z
title: what may it send?
---
id: no-title
utc: 2026-10-01T09:00:00Z
why: send Ann the pack now
---
id: asked-only
asked: 2026-11-05 18:32 IST
title: send Lee the file
---
id: ask-name
utc: 2026-10-02T09:00:00Z
title: ask Priya for the key
---
id: ask-cap
utc: 2026-10-02T09:00:00Z
title: Ask Priya for the key
---
id: ask-why
utc: 2026-10-02T09:00:00Z
title: check the key
why: Ask Sam for the key
---
id: ask-why-a
utc: 2026-10-02T09:00:00Z
title: check the lock
why: ask a locksmith
---
ITEMS
printf '# Hi\nREADME text\n' >"$dir/m2/drafts/README.md"
printf '# Note\nto: Sam\033[31mRED\n' >"$dir/m2/drafts/n.md"
touch -t 202609010900 "$dir/m2/drafts/n.md"
ln -s "$dir/m2/drafts/n.md" "$dir/m2/drafts/lnk.md"
printf '5\n' >"$dir/m2/board.json"
printf 'SABHA_WS=%s/m2\nSABHA_IMPL=%s/m2/impl\nSABHA_ROSTER="Relay:opus Worker:sonnet"\nSABHA_OWE_DIRS=drafts\nSABHA_OWE_BOARD=%s/m2/board.json\n' \
  "$dir" "$dir" "$dir" >"$dir/m2.conf"
m2=$(SABHA_CONF=$dir/m2.conf "$BIN/sabha" owe 2>&1) || fail "owe with a non-list board export must exit 0: $m2"
echo "$m2" | grep -q 'Traceback' && fail "a non-list board export must not traceback"
echo "$m2" | grep -q 'for-me ask-a' && fail "'ask a ...' must not match the ask <Name> rule"
echo "$m2" | grep -q 'for-me sup' && fail "a SUPERSEDED item must not be listed"
echo "$m2" | grep -q 'for-me why-only' && fail "a send word inside why must not list an item"
echo "$m2" | grep -q 'for-me quest' && fail "a title ending in ? is a question, not a send"
echo "$m2" | grep -q '| send Ann the pack now |' || fail "an item with only why: must show it in the what column"
echo "$m2" | grep -q 'for-me ask-name' || fail "ask Priya must still match"
echo "$m2" | grep -q 'for-me ask-cap' || fail "a capital Ask Priya title must be listed"
echo "$m2" | grep -q 'for-me ask-why ' || fail "a why starting with Ask Sam must be listed"
echo "$m2" | grep -q 'for-me ask-why-a' && fail "a why starting with ask a must not be listed"
echo "$m2" | grep -q 'for-me asked-only' || fail "an asked: item must be listed"
[[ $(echo "$m2" | tail -n 1) == *"for-me asked-only"* ]] || fail "the asked: item (5 Nov) must sort after the utc: items (1-2 Oct)"
echo "$m2" | grep 'for-me asked-only' | grep -q '^-' && fail "asked: must give an age, not -"
echo "$m2" | grep -q 'lnk.md' && fail "a symlink in a draft folder must not be listed"
SABHA_CONF=$dir/m2.conf "$BIN/sabha" owe --sent "$dir/m2/drafts/lnk.md" 2>/dev/null && fail "--sent on a symlink must fail"
echo "$m2" | grep -q 'README.md' && fail "README.md is not a draft"
printf '%s\n' "$m2" | grep -q "$(printf '\033')" && fail "control characters must be stripped from the output"
echo "$m2" | grep -q 'Sam\[31mRED' || fail "the draft to: column must still show the name"

echo "ok: owe lists open send items and unsent drafts oldest first with the board rows they block; done, sent and plain items stay out; --sent marks a draft"
