#!/usr/bin/env bash
# Tooltips: tips/tips.txt is well formed, every board element it names is in the rendered page with its tip, and
# `sabha tips`, `sabha help <key>` and the rotating Tip line read the same file. A tip that needs a feature absent from
# this branch (needs field) is skipped with a note. Hermetic: python and bash only, no claude, no herdr.
# Run: tests/test-tips.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-tips.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
TIPS=$here/tips/tips.txt
ELEMENTS=" your-move waiting in-flight inboxes done-today goals agents col-agent col-state col-goal col-task col-next col-ctx col-updated card-question card-plain copy-answer pause state-idle state-busy state-blocked state-stale state-not-running "

# 1. the file
[[ -f $TIPS ]] || fail "tips/tips.txt missing"
LC_ALL=C grep -q '[^ -~]' "$TIPS" && fail "tips.txt is not ASCII"
keys=""; els=""
while IFS='|' read -r key surf text _doc needs; do
  case $key in ''|'#'*) continue ;; esac
  [[ $key =~ ^[a-z][a-z0-9-]*$ ]] || fail "bad key '$key'"
  case " $keys " in *" $key "*) fail "duplicate key $key" ;; esac
  keys="$keys $key"
  (( ${#text} <= 110 )) || fail "$key: ${#text} characters (max 110)"
  [[ -n $text ]] || fail "$key: empty text"
  for s in ${surf//,/ }; do
    case $s in
      cli) ;;
      board:*) el=${s#board:}
        case "$ELEMENTS" in *" $el "*) ;; *) fail "$key: unknown board element $el" ;; esac
        case " $els " in *" $el "*) fail "$key: element $el already has a tip" ;; esac
        # a gated tip is not rendered here, so it does not count for the page check
        els="$els $el"; [[ -n $needs ]] || echo "$el" >>"$dir/expect" ;;
      *) fail "$key: bad surface $s" ;;
    esac
  done
done <"$TIPS"
echo "ok:   tips.txt: $(echo $keys | wc -w | tr -d ' ') tips, keys unique, ASCII, <= 110 characters"

# 2. the rendered board has every named element, with title and a description target
mkdir -p "$dir/impl/status/context" "$dir/impl/inbox/Zed"
printf 'Current: build\nNext: go\n' >"$dir/impl/status/busy.md"
printf 'Blocked: need a key\n' >"$dir/impl/status/blk.md"
printf 'Idle: by design (test)\n' >"$dir/impl/status/idl.md"
printf 'Current: old\n' >"$dir/impl/status/stl.md"; touch -t 202601011234 "$dir/impl/status/stl.md"
printf 'SABHA_IMPL=%s/impl\nSABHA_ROSTER="Busy:sonnet Blk:sonnet Idl:sonnet Stl:sonnet Gone:sonnet"\nSABHA_USER=Pat\n' "$dir" >"$dir/sabha.conf"
printf -- '---\nid: 1\nutc: 2026-10-14T09:00:00Z\nowner: V\ntitle: pick\nask: Pat\nq: Which?\nopta: a | x\noptb: b | y\nrec: a\n' >"$dir/impl/for-me.items"
render() { SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || fail "render"; }
render
h=$dir/impl/FOR-ME.html
if [[ -f $dir/expect ]]; then
  while read -r el; do
    grep -q "data-tip=$el title=\"[^\"]" "$h" || fail "board element $el has no tip in the page"
  done <"$dir/expect"
fi
echo "ok:   every board element in tips.txt is in the page with its title"
grep -q "<h2 data-tip=your-move title=\"[^\"]*\" tabindex=0" "$h" || fail "headings are not keyboard focusable"
grep -q "<th data-tip=col-ctx title=\"[^\"]*\">" "$h" || fail "a column header is a tab stop (or lacks its tip)"
grep -q "<div class=need data-tip=card-question title=\"[^\"]*\"><b>Needs" "$h" || fail "the question tip is not on the Needs line, or the line is focusable"
grep -q "<form class=qa data-id" "$h" || fail "the question form carries a tip"
grep -q "aria-describedby\|<div hidden>" "$h" && fail "tip text is announced twice (title and aria-describedby)"

# 2b. user text that looks like the tip markers is shown as written (the tips are attached inline, not by a page rewrite)
printf -- '---\nid: 2\nutc: 2026-10-14T09:00:00Z\nowner: V\ntitle: use data-t=agents here\nask: Pat\nq: press data-tb=copy-answer then data-t=your-move\nopta: a | x\nrec: a\n' >>"$dir/impl/for-me.items"
render
grep -q "use data-t=agents here" "$h" || fail "item title with data-t= was rewritten"
grep -q "press data-tb=copy-answer then data-t=your-move" "$h" || fail "q: line with data-t= was rewritten"
echo "ok:   text containing data-t= and data-tb= renders unchanged"

# 3. no file, no tooltips, same board
mkdir -p "$dir/bare"; cp -R "$here/bin" "$dir/bare/bin"
SABHA_CONF="$dir/sabha.conf" python3 "$dir/bare/bin/sabha-for-me" || fail "render without tips"
grep -q "data-tip=" "$h" && fail "tooltips rendered without tips.txt"
grep -q "Your move" "$h" || fail "board broken without tips.txt"
echo "ok:   a missing tips.txt renders the board without tooltips"

# 4. the CLI
SB() { "${BASH:-bash}" "$here/bin/sabha" "$@"; }
o=$(SB tips) || fail "sabha tips rc"
echo "$o" | grep -q '^go-token ' || fail "sabha tips lacks go-token"
echo "$o" | grep -q '^waiting ' && fail "sabha tips lists a board-only tip"
o=$(SB help go-token) || fail "help go-token rc"
echo "$o" | grep -q 'Read more: docs/inbox-protocol.md' || fail "help does not name the doc"
[[ -f $here/docs/inbox-protocol.md ]] || fail "help doc path does not exist"
o=$(SB help nope 2>&1); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q 'Keys: .*go-token' || fail "unknown key: rc=$rc $o"
a=$(SABHA_TIP_DAY=3 python3 "$here/bin/sabha-for-me" --tip-of-day); b=$(SABHA_TIP_DAY=4 python3 "$here/bin/sabha-for-me" --tip-of-day)
c=$(SABHA_TIP_DAY=3 python3 "$here/bin/sabha-for-me" --tip-of-day)
[[ $a == Tip:\ * && $a != "$b" && $a == "$c" ]] || fail "tip of the day does not rotate by day: '$a' '$b'"
echo "ok:   sabha tips, help <key>, unknown key and the rotating Tip line"

# 5. a gated tip: absent here, shown once the feature string is in bin/ or hooks/ (the other branches land it)
for k in keep-awake permission-relay; do
  if SB tips | grep -q "^$k "; then echo "note: $k tip is live (its feature is on this branch)"
  else echo "note: $k tip skipped, its feature is not on this branch (lands with feat/sabha-release)"; fi
done
mkdir -p "$dir/g/tips" "$dir/g/bin"; cp "$TIPS" "$dir/g/tips/"; cp "$here/bin/sabha-for-me" "$dir/g/bin/"
python3 "$dir/g/bin/sabha-for-me" --tips | grep -q '^keep-awake ' && fail "gated tip shown without its feature"
echo "caffeinate" >"$dir/g/bin/x"
python3 "$dir/g/bin/sabha-for-me" --tips | grep -q '^keep-awake ' || fail "gated tip hidden although its feature is present"
echo "ok:   needs gating hides a tip until its feature string exists"
echo "PASS"
