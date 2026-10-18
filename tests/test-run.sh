#!/usr/bin/env bash
# sabha-run against a fake claude: picks the lowest unacked brief, builds the command from the roster flags, keeps one
# run per role and at most SABHA_RUN_MAX runs, writes the ack, the log and a fallback done, and stops a run at the
# timeout. No model is called. Run: tests/test-run.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-run.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs"
cat > "$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$dir/impl
SABHA_PROJECT=Test
SABHA_ROSTER="Vidur:opus:medium Yudhi:opus:medium Arjun:sonnet:high Lazy1:haiku:low:gate,lazy Lazy2:sonnet:medium:lazy,mcp Lazy3:haiku:high:lazy Tutor:opus:medium:ondemand"
EOF
# fake claude: logs its argv; FAKE_SLEEP or FAKE_HOLD holds it running; FAKE_DONE=1 writes the brief's .done as a real run would
cat > "$dir/stubs/claude" <<'STUB'
#!/bin/sh
echo "FAKE claude $*"
echo "$*" >> "$CALLS"
# FAKE_GRANDCHILD: a tool subprocess (a build, a server) that would outlive claude unless its group is killed
[ -n "$FAKE_GRANDCHILD" ] && { sleep 60 & echo $! > "$FAKE_GRANDCHILD"; }
[ -n "$FAKE_SLEEP" ] && exec sleep "$FAKE_SLEEP"
# FAKE_HOLD: stay running while that file exists (at most 120 s), so a test controls when a run ends
if [ -n "$FAKE_HOLD" ]; then i=0; while [ -e "$FAKE_HOLD" ] && [ $i -lt 240 ]; do sleep 0.5; i=$((i+1)); done; exit 0; fi
if [ "$FAKE_DONE" = 1 ]; then
  f=$(printf '%s\n' "$*" | sed -n 's/.*write \(inbox\/[A-Za-z0-9]*\/[0-9]*\.done\).*/\1/p' | head -1)
  printf 'utc: x\nresult: ok\n' > "$IMPL/$f"
fi
exit 0
STUB
chmod +x "$dir/stubs/claude"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt PATH=$dir/stubs:$PATH IMPL=$dir/impl CALLS=$dir/calls
export FAKE_SLEEP="" FAKE_HOLD="" FAKE_DONE=1 FAKE_GRANDCHILD=""
brief() { mkdir -p "$dir/impl/inbox/$1"; echo "to: $1" > "$dir/impl/inbox/$1/$2-yudhi-task.md"; }
reset() { rm -rf "$dir/impl/inbox" "$dir/impl/runs"; : > "$CALLS"; }
run() { out=$("$SH" "$BIN/sabha-run" "$@" 2>&1); rc=$?; }

# 001 acked, 002 cancelled, 003 due, 004 later
reset; brief Lazy1 001; : > "$dir/impl/inbox/Lazy1/001.ack"; brief Lazy1 002; : > "$dir/impl/inbox/Lazy1/002.cancel"
brief Lazy1 003; brief Lazy1 004; brief Arjun 001; brief Lazy2 001
run --print
echo "--- sabha-run --print (rc $rc)"; echo "$out"
check "print picks the lowest due brief (Lazy1 003)" 'grep -q "Lazy1/003-yudhi-task.md" <<<"$out" && ! grep -q "Lazy1/004" <<<"$out"'
check "print: claude -p with the roster model, effort, name" 'grep -q "claude -p -n Lazy1 --model haiku --effort low --strict-mcp-config --permission-prompts none" <<<"$out"'
check "print: an mcp role keeps its MCP servers" 'grep -q "claude -p -n Lazy2 --model sonnet --effort medium --permission-prompts none" <<<"$out"'
check "print: never skips permissions" '! grep -q dangerously <<<"$out"'
check "print: prompt reads the protocol and the status file" 'grep -q "PROTOCOL.md, then status/lazy1.md, then the brief .*/Lazy1/003-yudhi-task.md" <<<"$out"'
check "default serves lazy roles only (Arjun not run)" '! grep -q "Arjun" <<<"$out"'
check "print writes nothing and calls nothing" '[[ ! -e $dir/impl/inbox/Lazy1/003.ack && ! -s $CALLS && ! -e $dir/impl/runs ]]'
run --print Arjun
check "a role named on the command line is served" 'grep -q "claude -p -n Arjun --model sonnet --effort high" <<<"$out"'
run --print Vidur
check "the relay is never run headless" 'grep -q "relay is never run headless" <<<"$out" && ! grep -q "claude -p" <<<"$out"'

run --wait Lazy1
echo "--- sabha-run --wait Lazy1 (rc $rc)"; echo "$out"
log=$(ls "$dir"/impl/runs/Lazy1-003-*.log 2>/dev/null)
check "one run started, ack written by the runner" '(( rc == 0 )) && grep -q "started Lazy1 003" <<<"$out" && grep -q "session: Lazy1 \[headless\]" "$dir/impl/inbox/Lazy1/003.ack"'
check "the log holds the command, the output and the end" '[[ -n $log ]] && grep -q "cd .* claude -p -n Lazy1" "$log" && grep -q "FAKE claude" "$log" && grep -q "end Lazy1 003: exit 0" "$log"'
check "the run's own done stands, the lock is gone" 'grep -q "result: ok" "$dir/impl/inbox/Lazy1/003.done" && [[ ! -e $dir/impl/inbox/Lazy1/run.lock ]]'
run --wait Lazy1
check "next pass takes the next brief (004)" 'grep -q "started Lazy1 004" <<<"$out"'

# single flight: a live lock (this shell) holds the role; a dead one is cleared
reset; brief Lazy1 001; echo $$ > "$dir/impl/inbox/Lazy1/run.lock"
run --wait Lazy1
check "a live run.lock keeps a second run off the role" 'grep -q "already on Lazy1" <<<"$out" && [[ ! -s $CALLS && ! -e $dir/impl/inbox/Lazy1/001.ack ]]'
echo 999999 > "$dir/impl/inbox/Lazy1/run.lock"
run --wait Lazy1
check "a stale run.lock (dead pid) is cleared" 'grep -q "started Lazy1 001" <<<"$out"'
reset; brief Lazy1 001
echo "  111 ttys001  Tue Oct 13 09:00:01 2026     claude -n Lazy1 --model haiku" > "$dir/ps-live.txt"
out=$(SABHA_PS_FILE=$dir/ps-live.txt "$SH" "$BIN/sabha-run" --wait 2>&1)
check "a live interactive claude -n Lazy1 keeps the runner off" 'grep -q "live claude -n Lazy1" <<<"$out" && [[ ! -s $CALLS ]]'

# cap: three due roles, cap 2, runs held open by FAKE_HOLD
reset; brief Lazy1 001; brief Lazy2 001; brief Lazy3 001
# the held runs stay up until the test removes the hold file: a fixed sleep raced on slow machines (Git Bash)
: > "$dir/hold"
out=$(FAKE_HOLD=$dir/hold SABHA_RUN_MAX=2 "$SH" "$BIN/sabha-run" 2>&1)
echo "--- cap 2 (rc $rc)"; echo "$out"
check "cap 2: two started, the third waits" '(( $(grep -c "^sabha-run: started" <<<"$out") == 2 )) && grep -q "Lazy3 001: cap of 2" <<<"$out"'
out=$(SABHA_RUN_MAX=2 "$SH" "$BIN/sabha-run" 2>&1)
check "cap counts runs started by an earlier pass" 'grep -q "Lazy3 001: cap of 2" <<<"$out" && ! grep -q "^sabha-run: started" <<<"$out"'
rm -f "$dir/hold"
for _ in $(seq 1 30); do ls "$dir"/impl/inbox/*/run.lock >/dev/null 2>&1 || break; sleep 1; done
out=$(SABHA_RUN_MAX=2 "$SH" "$BIN/sabha-run" --wait 2>&1)
check "after the runs end the third starts" 'grep -q "started Lazy3 001" <<<"$out"'

# timeout: the fake never ends; the runner stops it and writes a BLOCKED done
reset; brief Lazy1 001
out=$(FAKE_SLEEP=60 SABHA_RUN_TIMEOUT=1 "$SH" "$BIN/sabha-run" --wait Lazy1 2>&1)
log=$(ls "$dir"/impl/runs/Lazy1-001-*.log 2>/dev/null)
check "timeout: done says BLOCKED with the reason and the log" 'grep -q "result: BLOCKED .*timeout after 1s" "$dir/impl/inbox/Lazy1/001.done" && grep -q "end Lazy1 001: timeout after 1s" "$log"'
check "timeout: lock released" '[[ ! -e $dir/impl/inbox/Lazy1/run.lock ]]'

# timeout kills the whole process group, so a tool subprocess of claude goes too
reset; brief Lazy1 001
out=$(FAKE_SLEEP=60 FAKE_GRANDCHILD=$dir/grand.pid SABHA_RUN_TIMEOUT=1 "$SH" "$BIN/sabha-run" --wait Lazy1 2>&1)
gp=$(cat "$dir/grand.pid" 2>/dev/null)
check "timeout: claude's grandchild is killed with it" '[[ -n $gp ]] && ! kill -0 "$gp" 2>/dev/null'
[[ -n $gp ]] && kill "$gp" 2>/dev/null

# a child that never starts: no ack left hanging, a BLOCKED done names the failure, no lock
reset; brief Lazy1 001
out=$(SABHA_RUN_SELF=$dir/missing-runner "$SH" "$BIN/sabha-run" --wait Lazy1 2>&1)
echo "--- failed spawn"; echo "$out"
check "failed spawn: BLOCKED done, lock removed, reported" 'grep -q "result: BLOCKED headless run did not start" "$dir/impl/inbox/Lazy1/001.done" && [[ ! -e $dir/impl/inbox/Lazy1/run.lock ]] && grep -q "did not start" <<<"$out"'

# a child that ends at once: the lock it held is gone afterwards (its pid, not the pass's, was in it)
reset; brief Lazy1 001; brief Lazy2 001
out=$("$SH" "$BIN/sabha-run" 2>&1)
for _ in $(seq 1 20); do ls "$dir"/impl/inbox/*/run.lock >/dev/null 2>&1 || break; sleep 1; done
check "a fast run leaves no lock behind, and both report started" '! ls "$dir"/impl/inbox/*/run.lock >/dev/null 2>&1 && (( $(grep -c "^sabha-run: started" <<<"$out") == 2 ))'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
