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

echo "ok: owe lists open send items and unsent drafts oldest first with the board rows they block; done, sent and plain items stay out; --sent marks a draft"
