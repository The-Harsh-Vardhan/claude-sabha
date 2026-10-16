#!/usr/bin/env bash
# bin/sabha-brief: numbering skips taken claims, header block is complete, body is kept, bad input is refused.
# Run: tests/test-brief.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-brief.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
export SABHA_IMPL=$dir

[[ $("$bin/sabha-brief" 2>&1 >/dev/null; echo $?) == *2 ]] || { echo "FAIL: no args should exit 2"; exit 1; }
p1=$(echo "body line" | "$bin/sabha-brief" Worker Boss first-task "do it" --output out.md --go "fold repo abc") || { echo "FAIL: first brief"; exit 1; }
[[ $p1 == "$dir/inbox/Worker/001-boss-first-task.md" ]] || { echo "FAIL: path $p1"; exit 1; }
[[ -e $dir/inbox/Worker/001.claim ]] || { echo "FAIL: no claim file"; exit 1; }
head -n 1 "$p1" | grep -q '^to: Worker$' || { echo "FAIL: header to"; exit 1; }
for k in 'from: boss' 'task: do it' 'output: out.md' 'go: fold repo abc' 'reply: done' 'body line'; do
  grep -q -x -F "$k" "$p1" || { echo "FAIL: missing '$k'"; exit 1; }
done
grep -q -E '^utc: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$p1" || { echo "FAIL: utc"; exit 1; }
# a number claimed by another sender but without a brief yet is skipped
: > "$dir/inbox/Worker/002.claim"
p2=$("$bin/sabha-brief" Worker Boss second "again" </dev/null) || exit 1
[[ $p2 == */003-boss-second.md ]] || { echo "FAIL: expected 003, got $p2"; exit 1; }
printf 'from a file\n' > "$dir/b.txt"
p3=$("$bin/sabha-brief" Worker Boss third "x" --body "$dir/b.txt" --reply ack) || exit 1
grep -q 'from a file' "$p3" && grep -q '^reply: ack$' "$p3" || { echo "FAIL: --body or --reply"; exit 1; }
if "$bin/sabha-brief" Worker 'bad name' s t </dev/null 2>/dev/null; then echo "FAIL: bad name accepted"; exit 1; fi
if "$bin/sabha-brief" Worker boss s t --reply maybe </dev/null 2>/dev/null; then echo "FAIL: bad reply accepted"; exit 1; fi
# closed stdin and no --body: no hang, no error, empty body
p4=$("$bin/sabha-brief" Worker Boss closed "x" <&-) || { echo "FAIL: closed stdin"; exit 1; }
[[ -f $p4 ]] || { echo "FAIL: no brief with closed stdin"; exit 1; }
ls "$dir/inbox/Worker" | grep -q '\.tmp$' && { echo "FAIL: temp file left"; exit 1; }
echo "ok: brief numbering skips taken claims, header block complete, body and options kept, bad input refused"
