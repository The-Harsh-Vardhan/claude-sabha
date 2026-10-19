#!/usr/bin/env bash
# Question items on the board: radios, the rec label, the textarea and the copy button; a plain item is unchanged.
# Run: tests/test-forme.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-forme.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
mkdir -p "$dir/impl/status/context"
echo 12 > "$dir/impl/status/context/zed.txt"
echo 33 > "$dir/impl/status/context/old.txt"
touch -t 202601011234 "$dir/impl/status/context/old.txt"
printf 'SABHA_IMPL=%s/impl\nSABHA_ROSTER="Zed:sonnet Old:sonnet"\nSABHA_USER=Pat\n' "$dir" > "$dir/sabha.conf"
cat > "$dir/impl/for-me.items" <<'X'
---
id: 1
utc: 2026-10-14T09:00:00Z
owner: V
title: plain thing
why: because
---
id: 2
utc: 2026-10-14T09:00:00Z
owner: V
title: pick one
ask: Pat
q: Which branch?
explain: freezes the demo
opta: develop | newest | unreviewed
optb: release | stable | reviewed
rec: b
---
id: 3
utc: 2026-10-14T09:00:00Z
owner: V
title: needs sign-off
waiting: Alex
ask: Alex
q: Ship it?
opta: yes | go
optb: no | hold
rec: a
---
id: 4
utc: 2026-10-14T09:00:00Z
owner: V
state: OPEN
title: late question
---
id: 4
utc: 2026-10-14T09:30:00Z
waiting: Pat (parked)
ask: Pat
q: Late?
opta: yes | go
optb: no | hold
X
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render"; exit 1; }
h=$dir/impl/FOR-ME.html; m=$dir/impl/FOR-ME.md
chk() { grep -q -- "$2" "$1" || { echo "FAIL: $3"; exit 1; }; }
chk "$h" "type=radio name=q2 value=A" "radio A"
chk "$h" "type=radio name=q2 value=B" "radio B"
chk "$h" "(Recommended)" "rec label"
chk "$h" "Or type your own answer" "textarea"
chk "$h" "Copy answer" "copy button"
chk "$h" "e.g. reviewed" "example"
[[ $(grep -o 'class=qa' "$h" | wc -l | tr -d ' ') == 3 ]] || { echo "FAIL: plain item got a form"; exit 1; }
chk "$h" "1. plain thing" "plain item still rendered"
chk "$m" "B) release (Recommended) - stable e.g. reviewed" "md option line"
chk "$m" "### 1. plain thing" "md plain item"
chk "$h" "type=radio name=q3 value=A" "waiting item radio"
chk "$h" "Needs: Alex" "waiting item needs line"
chk "$h" "Answered by" "answered-by box for another person"
chk "$h" "Waiting for others" "section label"
[[ $(grep -o 'Answered by' "$h" | wc -l) -le 2 ]] || { echo "FAIL: Pat card got answered-by"; exit 1; }
awk '/Waiting for others/{f=1} f&&/name=q3/{ok=1} END{exit !ok}' "$h" || { echo "FAIL: card not under waiting"; exit 1; }
chk "$m" "needs: Alex" "md waiting question"
grep -q '"name": "Zed", "ctx": 12.0, "old": false' "$h" || { echo "FAIL: fresh ctx not coloured"; exit 1; }
grep -q '"name": "Old", "ctx": 33.0, "old": true, "seen": "12:34"' "$h" || { echo "FAIL: old ctx not grey with time"; exit 1; }
chk "$h" "grey = no reading in 30 min" "legend"
chk "$h" "type=radio name=q4 value=B" "late-appended question renders"
[[ $(grep -o "Copy answer" "$h" | wc -l | tr -d ' ') == 3 ]] || { echo "FAIL: copy buttons"; exit 1; }
[[ $(grep -o '<tr><td class=nm>' "$h" | wc -l | tr -d ' ') == 2 ]] || { echo "FAIL: agents table needs one row per roster role"; exit 1; }
chk "$h" "class=atw" "scroll container"
chk "$h" "not running" "not-running state"
ag=$(grep -n '<h2[^>]*>Agents' "$h" | head -1 | cut -d: -f1); ym=$(grep -n '<h2[^>]*>Your move' "$h" | head -1 | cut -d: -f1)
[[ -n $ag && -n $ym && $ym -lt $ag ]] || { echo "FAIL: Your move must come before Agents when it has open items (html)"; exit 1; }
[[ $(grep -n '^## Agents' "$m" | cut -d: -f1) -lt $(grep -n '^## Your move' "$m" | cut -d: -f1) ]] || { echo "FAIL: md order"; exit 1; }
echo "ok: question item renders radios, rec, textarea, copy button; plain item unchanged"

# GOALS: tagged fixture
cat > "$dir/impl/GOALS.md" <<'X'
# Goals

## Ship viewer [P0] (owner: Zed; helpers: Old) {state: active}
- [x] build it
- [ ] review it @Old
- [ ] merge it
## Plan next [P1] (owner: Old)
- [ ] draft
## Parked idea [P1] (owner: Zed) {state: paused}
- [ ] later
## Finished work [P0] (owner: Old)
- [x] a
- [x] b
## Legacy goal
- [x] one
- [ ] two
X
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render goals"; exit 1; }
chk "$h" "lane-P0" "P0 column"; chk "$h" "lane-P1" "P1 column"; chk "$h" "lane-P2" "P2 column"
chk "$h" "P0 <span class=k>Now" "P0 Now label"
chk "$h" "<span class='chip own'>Zed</span><span class='chip help'>Old</span>" "owner and helper chips"
chk "$h" "<span class=pct>1/3</span>" "progress numbers"
chk "$h" "next:</span> review it <span class='chip help'>@Old" "next step with agent"
chk "$h" "id=s-paused" "paused strip"; chk "$h" "id=s-done" "done strip"
chk "$h" "Done goals <span class=c>1" "done strip count"
awk '/lane-P0/{f=1} /lane-P1/{f=0} f&&/Finished work/{bad=1} END{exit bad}' "$h" || { echo "FAIL: done goal in a column"; exit 1; }
awk '/lane-P2/{f=1} f&&/Legacy goal/{ok=1} END{exit !ok}' "$h" || { echo "FAIL: untagged goal not P2"; exit 1; }
chk "$h" "<th[^>]*>Goal</th>" "Goal column header"
grep -q "<tr><td class=nm>Zed</td>.*<td>Ship viewer</td>" "$h" || { echo "FAIL: Zed goal cell"; exit 1; }
grep -q "<tr><td class=nm>Old</td>.*<td>Ship viewer; Plan next</td>" "$h" || { echo "FAIL: Old goal cell"; exit 1; }
gl=$(grep -n '<h2[^>]*>Goals' "$h" | head -1 | cut -d: -f1)
kp=$(grep -n 'class=kpis' "$h" | head -1 | cut -d: -f1); ch=$(grep -n 'class=charts' "$h" | head -1 | cut -d: -f1)
[[ -n $kp && -n $ch && $kp -lt $ym && $ym -lt $ag && $ag -lt $ch && $ch -lt $gl ]] || { echo "FAIL: order must be tiles, Your move, Agents, charts, Goals (html)"; exit 1; }
chk "$m" "### P0 Now" "md P0"; chk "$m" "### P2 Later" "md P2"
chk "$m" "- Ship viewer: 1/3 (owner: Zed; helpers: Old)" "md goal line"
chk "$m" "- Legacy goal: 1/2 (owner: unassigned)" "md legacy goal"
chk "$m" "| Zed |.* | Ship viewer |" "md agents goal column"
a=$(grep -n '^## Goals' "$m" | cut -d: -f1); b=$(grep -n '^## Agents' "$m" | cut -d: -f1); c=$(grep -n '^## Your move' "$m" | cut -d: -f1)
[[ $b -lt $a && $a -lt $c ]] || { echo "FAIL: md order Agents, Goals, Your move"; exit 1; }
# GOALS: old format, no tags
printf '# G\n\n## Old one\n- [x] a\n- [ ] b\n' > "$dir/impl/GOALS.md"
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render old goals"; exit 1; }
awk '/lane-P2/{f=1} f&&/Old one/{ok=1} END{exit !ok}' "$h" || { echo "FAIL: old-format goal not P2"; exit 1; }
chk "$m" "- Old one: 1/2 (owner: unassigned)" "old format md"
# GOALS: heading parts in any order, fallback for a title with its own parens, @Agent only on the step end
printf '# G\n\n## Odd (D1, D2) {state: paused} (owner: Q; helpers: A, B) [P1]\n- [ ] mid @A text\n- [ ] last @B\n' > "$dir/impl/GOALS.md"
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render odd goals"; exit 1; }
chk "$m" "- Odd (D1, D2): 0/2 (P1, owner: Q)" "tags in any order, title keeps its own parens"
chk "$h" "id=s-paused" "paused goal folded"
chk "$h" "next:</span> mid @A text" "mid-step @A is not an agent"
# configurable owner: with SABHA_USER=Quinn, a question asked of Pat is another person's (answered-by box)
n0=$(grep -o 'Answered by' "$h" | wc -l)
printf 'SABHA_IMPL=%s/impl\nSABHA_ROSTER="Zed:sonnet Old:sonnet"\nSABHA_USER=Quinn\n' "$dir" > "$dir/sabha.conf"
SABHA_CONF="$dir/sabha.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render owner"; exit 1; }
[[ $(grep -o 'Answered by' "$h" | wc -l) -gt $n0 ]] || { echo "FAIL: SABHA_USER not honoured"; exit 1; }
echo "ok: goals columns, chips, progress, next, Goal column, order, old format, any-order tags, configurable owner"

# BOARD QUICK WINS (critique items 1, 3, 6, 8, 9, 10)
w=$dir/w; mkdir -p "$w/status"
ago=$(python3 -c 'import datetime as d;print((d.datetime.utcnow()-d.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
printf -- '---\nid: 5\nutc: %s\nowner: V\ntitle: Same words\nq: Same words\nexplain: because\nopta: yes | go | you reply "Answer 5: A"\noptb: no | hold | a real example\n' "$ago" > "$w/for-me.items"
printf 'Current: building\nNext: do the thing\n' > "$w/status/bz.md"
printf 'Current: old work\n' > "$w/status/st.md"; touch -t 202601011234 "$w/status/st.md"
printf 'Idle: by design (waits)\n' > "$w/status/id.md"
printf 'Blocked: needs a key\n' > "$w/status/bl.md"
printf '# G\n\n## Only now [P0] (owner: Bz)\n- [ ] a\n' > "$w/GOALS.md"
printf 'Current: old busy\nNext: n\n' > "$w/status/s2.md"; touch -t 202601011234 "$w/status/s2.md"
printf 'SABHA_IMPL=%s\nSABHA_ROSTER="Bz:sonnet St:sonnet Id:sonnet Bl:sonnet S2:sonnet"\n' "$w" > "$dir/w.conf"
SABHA_CONF="$dir/w.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render quick wins"; exit 1; }
h=$w/FOR-ME.html
chk "$h" "<title>(1) Sabha - 1 for you</title>" "count in tab title"
chk "$h" "Copy answer" "copy button"; chk "$h" "class='ans primary'" "copy button is primary"
chk "$h" "Copied" "copied feedback"; chk "$h" ".opt:has(input:checked)" "selected option style"
chk "$h" "accent-color" "dark-mode radios"
chk "$h" ">V, 2h ago</div>" "relative time"
[[ $(grep -o 'Same words' "$h" | wc -l | tr -d ' ') == 1 ]] || { echo "FAIL: title must appear once"; exit 1; }
! grep -q 'e.g. you reply' "$h" || { echo "FAIL: reply example repeated"; exit 1; }
chk "$h" "e.g. a real example" "real example kept"
chk "$h" "class=why" "explain text class"
chk "$h" "<h2[^>]*>In flight <span class=c>2" "In flight agrees with Busy + Blocked, not with stale"
chk "$h" "<div class=n>1</div><div class=l>Busy" "busy tile"
chk "$h" "<div class=n>2</div><div class=l>Stale" "stale tile counts an old busy file once"
chk "$h" "<div class=n>1</div><div class=l>Idle" "idle tile excludes stale"
[[ $(grep -o "<div class=n>[0-9]*</div><div class=l>\(Busy\|Blocked\|Stale\|Idle\)" "$h" | grep -o "n>[0-9]*" | tr -d "n>" | awk '{s+=$1} END {print s}') == 5 ]] || { echo "FAIL: agent tiles must add up to the 5 roster agents"; exit 1; }
chk "$h" "IST'>V, 2h ago" "hover time in IST"
chk "$h" "class='ans primary' disabled" "copy button starts disabled"; chk "$h" "qen(" "copy button enabled by input"
chk "$h" "href=#your-move" "tile links to Your move"; chk "$h" "id=your-move" "Your move anchor"
chk "$h" "id=flight" "flight anchor"; chk "$h" "id=agents" "agents anchor"; chk "$h" "id=goals" "goals anchor"
! grep -q 'lane-P1' "$h" || { echo "FAIL: empty P1 column rendered"; exit 1; }
chk "$h" "P1 Next: none" "empty priority chip"
chk "$h" ".goal.P0{" "P0 accent"
: > "$w/for-me.items"
SABHA_CONF="$dir/w.conf" python3 "$here/bin/sabha-for-me" || { echo "FAIL: render empty"; exit 1; }
chk "$h" "<title>Sabha board</title>" "plain title when nothing is open"
chk "$h" "Nothing needs you" "one-line empty state"
echo "ok: board quick wins"
