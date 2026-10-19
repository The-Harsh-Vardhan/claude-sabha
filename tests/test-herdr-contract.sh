#!/usr/bin/env bash
# Idea 9: every herdr '<group> <command>' that a script under bin/ or hooks/ calls exists in tests/herdr-commands.txt,
# the command list of the herdr version sabha is checked against (help text of herdr 0.9.5). After a herdr upgrade,
# refresh the list from a plain terminal and rerun; a command herdr dropped then fails here instead of live:
#   for g in workspace tab pane agent notification integration session api status server worktree channel; do herdr $g --help | awk -v g=$g '/^Commands:/{f=1;next} f&&/^  [a-z]/{print g" "$1} f&&/^$/{f=0}'; done | grep -v ' help$'
# Comments and echo lines are not calls. Run: tests/test-herdr-contract.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
list=$ROOT/tests/herdr-commands.txt
fail() { echo "FAIL: $*"; exit 1; }
[[ -s $list ]] || fail "missing $list"
groups=$(grep -v '^#' "$list" | awk '{print $1}' | sort -u | tr '\n' ' ')
calls=$(grep -rhE '(sabha_h|herdr) ' "$ROOT/bin" "$ROOT/hooks" | grep -vE '^[[:space:]]*#|echo ' |
  grep -oE '(sabha_h|herdr( --session +[^ ]+)?) [a-z][a-z-]+ [a-z][a-z-]+' | sed -E 's/^(sabha_h|herdr( --session +[^ ]+)?) //' | sort -u)
n=0 bad=""
while read -r g c; do
  [[ " $groups " == *" $g "* ]] || continue
  n=$((n + 1))
  grep -qx "$g $c" "$list" || bad="$bad $g/$c"
done <<<"$calls"
(( n >= 10 )) || fail "found only $n herdr calls; the scan is broken"
[[ -z $bad ]] || fail "herdr has no:$bad (tests/herdr-commands.txt)"
# a call that the list itself does not know must fail: the check is not vacuous
grep -qx "agent teleport" "$list" && fail "the list should not hold a made-up command"
echo "ok: all $n herdr calls in bin/ and hooks/ exist in herdr $(sed -n 's/^# herdr \([0-9.]*\).*/\1/p' "$list")"
