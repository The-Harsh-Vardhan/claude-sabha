#!/usr/bin/env bash
# Brief lifecycle against a fake claude: amendment files NNN.K are read after their brief and never run as briefs,
# "needs:" holds a brief until its needs are done and closes it when they can never be (unknown, self, cycle,
# BLOCKED, CANCELLED), attempts are counted at start and only an infrastructure failure is retried, a dead headless
# run is recovered, sabha-brief --amend numbers and nudges, sabha-watch skips amendments and flags edits after an ack.
# No model, no herdr. Run: tests/test-brief-lifecycle.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-lifecycle.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
cat > "$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$dir/impl
SABHA_PROJECT=Test
SABHA_ROSTER="Relay:opus:medium Yudhi:opus:medium Lazy1:haiku:low:lazy Lazy2:sonnet:medium:lazy"
EOF
# fake claude: FAKE_RC is its exit code; FAKE_DONE=1 writes the brief's .done as a real run would
cat > "$dir/stubs/claude" <<'STUB'
#!/bin/sh
echo "$*" >> "$CALLS"
if [ "$FAKE_DONE" = 1 ]; then
  f=$(printf '%s\n' "$*" | sed -n 's/.*write \(inbox\/[A-Za-z0-9]*\/[0-9]*\.done\).*/\1/p' | head -1)
  printf 'utc: x\nresult: ok\n' > "$IMPL/$f"
fi
exit "${FAKE_RC:-0}"
STUB
chmod +x "$dir/stubs/claude"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH IMPL=$dir/impl CALLS=$dir/calls
export FAKE_DONE=1 FAKE_RC=0
I=$dir/impl/inbox
# brief <Name> <NNN> [needs]: writes a brief with an optional needs: header line
brief() { mkdir -p "$I/$1"; { echo "to: $1"; [[ -n ${3:-} ]] && echo "needs: $3"; echo; echo body; } > "$I/$1/$2-yudhi-task.md"; }
done_with() { printf 'utc: x\nresult: %s\n' "$3" > "$I/$1/$2.done"; }
reset() { rm -rf "$I" "$dir/impl/runs" "$dir/impl/status/done-nudge.log"; : > "$CALLS"; }
run() { out=$("$SH" "$BIN/sabha-run" "$@" 2>&1); rc=$?; }

# --- amendments (Q10)
reset; brief Lazy1 001
echo "amends: 001" > "$I/Lazy1/001.2-yudhi-more.md"; echo "amends: 001" > "$I/Lazy1/001.10-yudhi-last.md"
echo "amends: 001" > "$I/Lazy1/001.1-yudhi-fix.md"
run --print Lazy1
check "an amendment is never a brief of its own" '(( $(grep -c "claude -p" <<<"$out") == 1 )) && grep -q "then the brief [^ ]*/Lazy1/001-yudhi-task.md" <<<"$out"'
check "the prompt lists the amendments in K order (1, 2, 10)" 'grep -q "001.1-yudhi-fix.md, .*001.2-yudhi-more.md, .*001.10-yudhi-last.md\." <<<"$out"'
run --wait Lazy1
run --wait Lazy1
check "once the brief is done, its amendments start nothing" '(( $(wc -l < "$CALLS") == 1 )) && ! grep -q started <<<"$out"'
reset; brief Lazy1 001
run --print Lazy1
check "a brief with no amendments has no amendment sentence" '! grep -q "has amendments" <<<"$out"'

# --- needs: (Q9a)
reset; brief Lazy1 001 002; brief Lazy1 002
run --print Lazy1
check "needs: an open need waits; the next brief runs instead" 'grep -q "Lazy1 001: waiting on 002" <<<"$out" && grep -q "Lazy1/002-yudhi-task.md" <<<"$out"'
done_with Lazy1 002 ok
run --print Lazy1
check "needs: met once the need is done" 'grep -q "Lazy1/001-yudhi-task.md" <<<"$out"'
reset; brief Lazy1 001 "Lazy2/005, Lazy2/006"; brief Lazy2 005; brief Lazy2 006; done_with Lazy2 005 ok
run --print Lazy1
check "needs: Name/NNN across inboxes, comma list, waits on the open one" 'grep -q "Lazy1 001: waiting on Lazy2/006" <<<"$out" && ! grep -q "claude -p -n Lazy1" <<<"$out"'
done_with Lazy2 006 "BLOCKED no access"
run --print Lazy1
check "print mode closes nothing" '[[ ! -e $I/Lazy1/001.done ]] && grep -q "Lazy2/006 ended BLOCKED" <<<"$out"'
run --wait Lazy1
check "needs: a BLOCKED need closes the brief with a BLOCKED done" 'grep -q "^result: BLOCKED needs: Lazy2/006 ended BLOCKED" "$I/Lazy1/001.done" && [[ ! -s $CALLS ]]'
reset; brief Lazy1 001 002; brief Lazy1 002; : > "$I/Lazy1/002.cancel"
run --wait Lazy1
check "needs: a cancelled need blocks" 'grep -q "needs: 002 was cancelled" "$I/Lazy1/001.done"'
reset; brief Lazy1 001 Lazy2/099
run --wait Lazy1
check "needs: an unknown brief blocks (never taken as met)" 'grep -q "needs: unknown brief Lazy2/099" "$I/Lazy1/001.done"'
reset; brief Lazy1 001 Lazy2/099; mkdir -p "$I/Lazy2"; : > "$I/Lazy2/099.claim"
run --wait Lazy1
check "needs: a claimed number with no brief yet waits" 'grep -q "waiting on Lazy2/099" <<<"$out" && [[ ! -e $I/Lazy1/001.done ]]'
reset; brief Lazy1 001 001
run --wait Lazy1
check "needs: a brief that needs itself blocks" 'grep -q "needs: it needs itself" "$I/Lazy1/001.done"'
reset; brief Lazy1 001 Lazy2/001; brief Lazy2 001 Lazy1/002; brief Lazy1 002 Lazy1/001
run --wait Lazy1
check "needs: a cycle blocks" 'grep -q "needs: a cycle through" "$I/Lazy1/001.done"'
reset; brief Lazy1 001 "../x"
run --wait Lazy1
check "needs: a bad id blocks" 'grep -q "needs: bad id ../x" "$I/Lazy1/001.done"'
reset; brief Lazy1 001; printf 'to: Lazy1\n\nneeds: 777\n' > "$I/Lazy1/002-yudhi-body.md"
run --print Lazy1
check "needs: only the header block counts, not the body" 'grep -q "Lazy1/001-yudhi-task.md" <<<"$out"'

# --- attempts and retries (Q9b, Q9c)
reset; brief Lazy1 001
FAKE_DONE=0 FAKE_RC=1 run --wait Lazy1
check "default 1 attempt: a failed exit is a BLOCKED done at once (old behaviour)" 'grep -q "result: BLOCKED headless run ended without a done (exit 1)" "$I/Lazy1/001.done" && (( $(grep -c . "$I/Lazy1/001.attempts") == 1 ))'
reset; brief Lazy1 001
export SABHA_RUN_ATTEMPTS=2 SABHA_RUN_BACKOFF=0
FAKE_DONE=0 FAKE_RC=1 run --wait Lazy1
check "attempts 2: a failed exit queues a retry (ack removed, retry file, no done)" '[[ ! -e $I/Lazy1/001.ack && -e $I/Lazy1/001.retry && ! -e $I/Lazy1/001.done ]] && grep -q "queued for a retry (1 of 2" "$dir"/impl/runs/Lazy1-001-*.log'
FAKE_DONE=0 FAKE_RC=1 run --wait Lazy1
check "attempts 2: the second failure is final" 'grep -q "result: BLOCKED" "$I/Lazy1/001.done" && (( $(grep -c . "$I/Lazy1/001.attempts") == 2 ))'
reset; brief Lazy1 001
FAKE_DONE=0 FAKE_RC=0 run --wait Lazy1
check "exit 0 with no done is the agent's end, never retried" 'grep -q "result: BLOCKED headless run ended without a done (exit 0)" "$I/Lazy1/001.done"'
reset; brief Lazy1 001
printf '#!/bin/sh\necho "$*" >> "$CALLS"; printf "utc: x\\nresult: BLOCKED no access\\n" > "$IMPL/inbox/Lazy1/001.done"; exit 1\n' > "$dir/stubs/claude-blocked"
chmod +x "$dir/stubs/claude-blocked"; cp "$dir/stubs/claude" "$dir/stubs/claude.bak"; cp "$dir/stubs/claude-blocked" "$dir/stubs/claude"
run --wait Lazy1
cp "$dir/stubs/claude.bak" "$dir/stubs/claude"
check "an agent's own BLOCKED done is never retried" 'grep -q "result: BLOCKED no access" "$I/Lazy1/001.done" && [[ ! -e $I/Lazy1/001.retry ]]'
reset; brief Lazy1 001
SABHA_RUN_BACKOFF=300 FAKE_DONE=0 FAKE_RC=1 run --wait Lazy1
run --wait Lazy1
check "backoff: the next pass waits until the retry time" 'grep -q "Lazy1 001: waiting, retry in [0-9]*s" <<<"$out" && ! grep -q started <<<"$out" && (( $(wc -l < "$CALLS") == 1 ))'
reset; brief Lazy1 001
out=$(SABHA_RUN_SELF=$dir/missing-runner "$SH" "$BIN/sabha-run" --wait Lazy1 2>&1)
check "a spawn that fails is retried too, and counts an attempt" 'grep -q "did not start; queued for a retry" <<<"$out" && [[ ! -e $I/Lazy1/001.done && ! -e $I/Lazy1/run.lock ]] && (( $(grep -c . "$I/Lazy1/001.attempts") == 1 ))'

# --- a headless run that died (Q9f): ack [headless], no done, no live run.lock
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"; echo 1 > "$I/Lazy1/001.attempts"
echo 999999 > "$I/Lazy1/run.lock"
run --wait Lazy1
check "a dead headless run is re-queued and run again while attempts are left" 'grep -q "started Lazy1 001" <<<"$out" && grep -q "result: ok" "$I/Lazy1/001.done"'
unset SABHA_RUN_ATTEMPTS SABHA_RUN_BACKOFF
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"; echo 1 > "$I/Lazy1/001.attempts"
run --wait Lazy1
check "with no attempts left it is closed BLOCKED, not left open forever" 'grep -q "result: BLOCKED headless run died" "$I/Lazy1/001.done" && [[ ! -s $CALLS ]]'
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"; echo $$ > "$I/Lazy1/run.lock"
run --wait Lazy1
check "a live run.lock is left alone" '[[ ! -e $I/Lazy1/001.done && -e $I/Lazy1/001.ack ]]'
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [ab12]\n' > "$I/Lazy1/001.ack"
run --wait Lazy1
check "a pane ack is never touched" '[[ ! -e $I/Lazy1/001.done && -e $I/Lazy1/001.ack && ! -s $CALLS ]]'
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"
echo "111 ttys001  Tue Oct 13 09:00:01 2026     claude -n Lazy1 --model haiku" > "$dir/ps.txt"
run --wait Lazy1
: > "$dir/ps.txt"
check "a headless ack with a live claude -n pane is left to the pane" '[[ -e $I/Lazy1/001.ack && ! -e $I/Lazy1/001.retry && ! -e $I/Lazy1/001.done && ! -s $CALLS ]]'
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"
run --wait Lazy1
check "an ack from before attempts were counted (no .attempts) used its one attempt: closed BLOCKED" 'grep -q "result: BLOCKED headless run died" "$I/Lazy1/001.done" && [[ ! -e $I/Lazy1/001.retry && ! -s $CALLS ]]'
reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"
SABHA_RUN_ATTEMPTS=2 SABHA_RUN_BACKOFF=0 run --wait Lazy1
check "with no .attempts and 2 allowed, it runs once more and counts both" 'grep -q "result: ok" "$I/Lazy1/001.done" && (( $(grep -c . "$I/Lazy1/001.attempts") == 2 ))'

# --- backoff series: 60, 120, 240, 480, 960, then flat (cap 16x)
for k in 1 2 3 4 5 6 7; do
  reset; brief Lazy1 001; printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/001.ack"
  for _ in $(seq 1 "$k"); do echo x; done > "$I/Lazy1/001.attempts"
  now=$(date +%s)
  SABHA_RUN_ATTEMPTS=10 SABHA_RUN_BACKOFF=60 run --wait Lazy1
  got=$(( $(sed -n 's/^after: *//p' "$I/Lazy1/001.retry") - now ))
  want=$(( 60 << (k > 5 ? 4 : k - 1) ))
  check "backoff after $k attempt(s) is ${want}s" '(( got >= want && got <= want + 2 ))'
done

# --- 4-digit brief numbers
reset; brief Lazy1 1000 1001; brief Lazy1 1001
run --print Lazy1
check "1000+: a 4-digit brief runs and a 4-digit need holds it" 'grep -q "Lazy1 1000: waiting on 1001" <<<"$out" && grep -q "Lazy1/1001-yudhi-task.md" <<<"$out"'
done_with Lazy1 1001 ok
run --wait Lazy1
check "1000+: runs once its need is done" 'grep -q "result: ok" "$I/Lazy1/1000.done"'
reset; mkdir -p "$I/Lazy1"; : > "$I/Lazy1/999.claim"
p=$(SABHA_IMPL=$dir/impl "$SH" "$BIN/sabha-brief" Lazy1 Yudhi big "x" </dev/null)
check "1000+: sabha-brief numbers past 999" '[[ $p == */1000-yudhi-big.md ]]'

# --- needs: result case and globbing
reset; brief Lazy1 001 002; brief Lazy1 002; done_with Lazy1 002 "Blocked no access"
run --wait Lazy1
check "needs: a lower-case Blocked need still blocks" 'grep -q "needs: 002 ended BLOCKED" "$I/Lazy1/001.done"'
reset; brief Lazy1 001 "00*"; : > "$dir/ws/002"
(cd "$dir/ws" && "$SH" "$BIN/sabha-run" --wait Lazy1 >/dev/null 2>&1)
check "needs: a glob in an id is not expanded" 'grep -q "needs: bad id 00\*" "$I/Lazy1/001.done"'

# --- sabha-brief --amend and --needs
reset; export SABHA_IMPL=$dir/impl
printf '#!/bin/sh\necho "$1|$2" >>"%s/nudges"\n' "$dir" > "$dir/fake-nudge"; chmod +x "$dir/fake-nudge"
export SABHA_NUDGE_BIN=$dir/fake-nudge; rm -f "$dir/nudges"
p=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi base "do it" --needs "Lazy2/004 005" </dev/null)
check "--needs writes the header line" 'grep -q -x "needs: Lazy2/004 005" "$p"'
check "--needs refuses a bad id at write time" '! "$SH" "$BIN/sabha-brief" Lazy1 Yudhi bad "x" --needs "../x" </dev/null 2>/dev/null && [[ ! -e $I/Lazy1/002.claim ]]'
a1=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi fix "change step 2" --amend 001 </dev/null)
a2=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi more "change step 3" --amend 001 </dev/null)
check "--amend numbers 001.1 then 001.2 and writes amends:" '[[ $a1 == */001.1-yudhi-fix.md && $a2 == */001.2-yudhi-more.md ]] && grep -q -x "amends: 001" "$a2"'
check "an unacked brief gets no nudge" '[[ ! -e $dir/nudges ]]'
p2=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi next "x" </dev/null)
check "the next plain brief number skips past the amendments" '[[ $p2 == */002-yudhi-next.md ]]'
printf 'utc: x\nsession: Lazy1 [ab12]\n' > "$I/Lazy1/001.ack"
a3=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi pane "x" --amend 001 </dev/null)
for _ in $(seq 1 50); do [[ -s $dir/nudges ]] && break; sleep 0.1; done
check "an acked pane brief: the worker is nudged with the new file" 'grep -q -x "Lazy1|see inbox/Lazy1/001.3-yudhi-pane.md (amends 001)" "$dir/nudges"'
printf 'utc: x\nsession: Lazy1 [headless]\n' > "$I/Lazy1/002.ack"
err=$("$SH" "$BIN/sabha-brief" Lazy1 Yudhi hl "x" --amend 002 </dev/null 2>&1 >/dev/null); sleep 0.3
check "an acked headless brief: a warning, no nudge" 'grep -q "headless run holds 002" <<<"$err" && (( $(wc -l < "$dir/nudges") == 1 ))'
: > "$I/Lazy1/002.done"
check "--amend refuses a closed brief and a missing one" '! "$SH" "$BIN/sabha-brief" Lazy1 Yudhi x "x" --amend 002 </dev/null 2>/dev/null && ! "$SH" "$BIN/sabha-brief" Lazy1 Yudhi x "x" --amend 050 </dev/null 2>/dev/null'

# --- sabha-watch: amendments are not unacked briefs; an edit after the ack is reported
reset; mkdir -p "$I/Lazy1"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Yudhi:opus Lazy1:haiku"\n' "$dir/ws" "$dir/impl" > "$dir/watch.conf"
brief Lazy1 001; : > "$I/Lazy1/001.ack"; echo x > "$I/Lazy1/001.1-yudhi-fix.md"
touch -t 202601010000 "$I/Lazy1/001.ack" "$I/Lazy1/001.1-yudhi-fix.md"
w=$(SABHA_CONF=$dir/watch.conf SABHA_NOTIFY_DESKTOP=0 "$SH" "$BIN/sabha-watch" 2>&1)
check "watch: an amendment is not an unacked brief" 'grep -q "^unacked briefs: none" <<<"$w"'
check "watch: a brief edited after its ack is reported" 'grep -q "edited after ack .*inbox/Lazy1/001" <<<"$w"'

# --- hooks: an amendment is listed while its brief is open, and closes with it
ob=$(HK_IMPL=$dir/impl HK_ROLE=Lazy1 "$SH" -c '. "$1/hooks/lib.sh"; hk_open_briefs all' _ "$BIN/..")
check "hooks: the open brief lists its amendment" 'grep -q -x "001.1-yudhi-fix.md" <<<"$ob"'
: > "$I/Lazy1/001.done"
ob=$(HK_IMPL=$dir/impl HK_ROLE=Lazy1 "$SH" -c '. "$1/hooks/lib.sh"; hk_open_briefs all' _ "$BIN/..")
check "hooks: a closed brief takes its amendments with it" '[[ -z $ob ]]'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
