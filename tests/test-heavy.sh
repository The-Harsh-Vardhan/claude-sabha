#!/usr/bin/env bash
# bin/sabha-heavy: the heavy-job gate (load1, memory pressure, slots), the slot files and their cleanup, the
# sandbox fallbacks (uptime, memory_pressure -Q), run releasing its slot on exit and on TERM. sysctl, uptime and
# memory_pressure are stubs on PATH (FAKE_* below). Run: tests/test-heavy.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-heavy.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl" "$dir/ws" "$dir/stubs"
cat > "$dir/stubs/sysctl" <<'EOF'
#!/bin/sh
[ -n "$FAKE_SYSCTL_FAIL" ] && { echo "sysctl: Operation not permitted" >&2; exit 1; }
case $2 in
  hw.ncpu) echo "${FAKE_NCPU:-10}" ;;
  vm.loadavg) echo "{ ${FAKE_LOAD:-1.00} ${FAKE_LOAD5:-1.00} 1.00 }" ;;
  kern.memorystatus_vm_pressure_level) echo "${FAKE_LEVEL:-1}" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\n[ -n "$FAKE_UPTIME_FAIL" ] && exit 1\necho "20:00  up 3 days, 2 users, load averages: ${FAKE_LOAD:-1.00} ${FAKE_LOAD5:-1.00} 1.00"\n' > "$dir/stubs/uptime"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_FREE:-60}%%"\n' > "$dir/stubs/memory_pressure"
printf '#!/bin/sh\necho "${FAKE_NCPU:-10}"\n' > "$dir/stubs/getconf"
chmod +x "$dir/stubs/"*
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_HEAVY_MAX=2\nSABHA_HEAVY_SETTLE=0\nSABHA_HEAVY_POLL=1\n' "$dir/ws" "$dir/impl" > "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf PATH=$dir/stubs:$PATH
slots=$dir/impl/status/heavy
heavy() { "$SH" "$BIN/sabha-heavy" "$@" 2>&1; }

echo "--- the gate"
out=$(FAKE_LOAD=21.0 heavy check); rc=$?
check "load 21 on 10 cores: wait, names load" '(( rc == 75 )) && grep -q "^HEAVY WAIT: load1 21.0 > 20 (10 cores)" <<<"$out"'
out=$(FAKE_LOAD=19.5 FAKE_LEVEL=2 heavy check); rc=$?
check "load 19.5, level 2: wait, names memory" '(( rc == 75 )) && grep -q "memory yellow" <<<"$out" && ! grep -q "load1 19.5 >" <<<"$out"'
out=$(FAKE_LOAD=19.5 heavy check); rc=$?
check "load 19.5, level 1, no slots: go" '(( rc == 0 )) && grep -q "^HEAVY GO: load1 19.5/20; memory green; slots 0/2$" <<<"$out"'
out=$(FAKE_SYSCTL_FAIL=1 FAKE_LOAD=3.2 FAKE_FREE=60 heavy check); rc=$?
check "sandbox fallback: uptime + memory_pressure -Q + getconf" '(( rc == 0 )) && grep -q "load1 3.2/20; memory green" <<<"$out"'
out=$(FAKE_SYSCTL_FAIL=1 FAKE_LOAD=3.2 FAKE_FREE=32 heavy check); rc=$?
check "fallback: free 32% < 40% counts as yellow" '(( rc == 75 )) && grep -q "memory yellow (free 32%)" <<<"$out"'
out=$(FAKE_SYSCTL_FAIL=1 FAKE_UPTIME_FAIL=1 heavy check); rc=$?
check "nothing readable: wait, never a blind go" '(( rc == 75 )) && grep -q "cannot read load" <<<"$out"'

echo "--- slots"
out=$(heavy acquire build-a 0); rc=$?
check "acquire takes a slot (pid 0 for a Bash-tool job)" '(( rc == 0 )) && grep -q "^pid: 0$" "$slots/build-a.slot"'
heavy acquire e2e-b 0 >/dev/null
out=$(heavy acquire third 0); rc=$?
check "a third acquire waits on slots 2/2" '(( rc == 75 )) && grep -q "slots 2/2" <<<"$out" && [[ ! -e $slots/third.slot ]]'
out=$(SABHA_HEAVY_FORCE=1 SABHA_ROLE=Tester heavy acquire forced 0); rc=$?
check "SABHA_HEAVY_FORCE=1 takes it anyway and records who" '(( rc == 0 )) && grep -q "^forced: Tester$" "$slots/forced.slot"'
out=$(heavy status)
check "status: one line with load, colour, memory, slots and labels" '[[ $out == "load 1.00/10 green | mem green | slots 3/2 | build-a e2e-b forced" ]]'
heavy release forced >/dev/null; heavy release e2e-b >/dev/null
check "release frees the slot" '[[ ! -e $slots/e2e-b.slot && -e $slots/build-a.slot ]]'
touch -t 202001010000 "$slots/build-a.slot"
printf 'pid: 999999\nlabel: dead\n' > "$slots/dead.slot"
out=$(heavy check)
check "an expired pid-0 slot and a dead pid's slot are removed and do not count" '[[ ! -e $slots/build-a.slot && ! -e $slots/dead.slot ]] && grep -q "slots 0/2" <<<"$out"'
out=$(heavy acquire 'bad label' 0); rc=$?
check "a label with a space is refused" '(( rc == 2 ))'
printf 'SABHA_HEAVY_SETTLE=600\n' >> "$dir/sabha.conf"
heavy acquire first 0 >/dev/null
out=$(heavy acquire second 0); rc=$?
check "settle: a second job waits while the first loads the box" '(( rc == 75 )) && grep -q "settle" <<<"$out"'
heavy release first >/dev/null
sed -i.bak '/SETTLE=600/d' "$dir/sabha.conf"

echo "--- run"
out=$(heavy run job1 -- sh -c 'ls "$1"' _ "$slots"); rc=$?
check "run holds the slot while the command runs, frees it after" '(( rc == 0 )) && grep -q "job1.slot" <<<"$out" && [[ ! -e $slots/job1.slot ]]'
heavy run job2 -- false >/dev/null; rc=$?
check "run passes the command's exit code" '(( rc == 1 )) && [[ ! -e $slots/job2.slot ]]'
"$SH" "$BIN/sabha-heavy" run job3 -- sleep 30 >/dev/null 2>&1 &
w=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -e $slots/job3.slot ]] && break; sleep 0.5; done
held=0; [[ -e $slots/job3.slot ]] && held=1
kill -TERM "$w"; wait "$w" 2>/dev/null
check "TERM to run frees the slot" '(( held == 1 )) && [[ ! -e $slots/job3.slot ]]'

echo "--- memory first"
out=$(FAKE_LOAD=21.0 FAKE_LEVEL=2 heavy check)
check "memory and load both bad: the WAIT line names memory before load" 'grep -q "^HEAVY WAIT: memory yellow; load1 21.0" <<<"$out"'

echo "--- queue: order, priority, aging"
q=$slots/queue
setep() { sed -i.bak "s/^epoch: .*/epoch: $(( $(date +%s) - $2 ))/" "$q/$1" && rm -f "$q/$1.bak"; }
order() { heavy queue list | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $2 } END { print "" }'; }
heavy queue add a >/dev/null; setep a 100
heavy queue add b >/dev/null; setep b 50
heavy queue add c >/dev/null
check "same priority: first in, first out" '[[ $(order) == "a b c" ]]'
heavy queue add d --prio 9 >/dev/null
check "a higher priority goes first" '[[ $(order) == "d a b c" ]]'
setep a 3000
check "aging: a job that waited 50 min passes a fresh prio 9" '[[ $(order) == "a d b c" ]]'
out=$(heavy queue add a); rc=$?
check "queueing a label twice is refused (it would reset its age)" '(( rc == 1 )) && grep -q "already queued" <<<"$out"'
out=$(heavy queue add e --prio 0); rc=$?
check "a prio outside 1 to 9 is refused" '(( rc == 2 ))'
setep c 90000
check "an entry older than the queue TTL is dropped" '[[ $(order) == "a d b" && ! -e $q/c ]]'
out=$(heavy status)
check "status shows the queue depth" '[[ $out == *" | queue 3" ]]'

echo "--- queue: next and acquire"
out=$(FAKE_LEVEL=2 heavy queue next); rc=$?
check "next under memory pressure: wait, names the head" '(( rc == 75 )) && grep -q "memory yellow.*(head: a)" <<<"$out"'
out=$(heavy queue next); rc=$?
check "next when the gate is open: NEXT is the head, nothing is taken" '(( rc == 0 )) && grep -q "^NEXT: a$" <<<"$out" && [[ -e $q/a && ! -e $slots/a.slot ]]'
out=$(heavy acquire b 0); rc=$?
check "a queued label behind the head waits" '(( rc == 75 )) && grep -q "queue: a is ahead" <<<"$out" && [[ ! -e $slots/b.slot ]]'
out=$(heavy acquire free-job 0); rc=$?
check "an unqueued label is not held by the queue" '(( rc == 0 )) && [[ -e $slots/free-job.slot ]]'
heavy release free-job >/dev/null
out=$(heavy acquire a 0); rc=$?
check "the head takes its slot and leaves the queue" '(( rc == 0 )) && [[ -e $slots/a.slot && ! -e $q/a ]]'
heavy release a >/dev/null
heavy queue remove d >/dev/null
check "remove drops an entry" '[[ $(order) == "b" ]]'
heavy queue remove b >/dev/null
out=$(heavy queue next); rc=$?
check "next on an empty queue: exit 1" '(( rc == 1 )) && grep -q "queue empty" <<<"$out"'

echo "--- per-label settle"
heavy queue add jest --settle 600 >/dev/null
heavy acquire jest 0 >/dev/null
check "the queued settle is stored in the slot" 'grep -q "^settle: 600$" "$slots/jest.slot"'
out=$(heavy acquire next-job 0); rc=$?
check "the next job waits out the label's own settle, not the default 0" '(( rc == 75 )) && grep -q "settle: next slot in" <<<"$out"'
heavy release jest >/dev/null
out=$(SABHA_HEAVY_SETTLE_FOR=600 heavy acquire viaenv 0); rc=$?
check "SABHA_HEAVY_SETTLE_FOR does the same without the queue" '(( rc == 0 )) && grep -q "^settle: 600$" "$slots/viaenv.slot"'
heavy release viaenv >/dev/null

echo "--- acquire with a pid"
sleep 30 & sp=$!
heavy acquire withpid 0 "$sp" >/dev/null
check "acquire <label> 0 <pid> writes that pid" 'grep -q "^pid: $sp$" "$slots/withpid.slot"'
kill "$sp"; wait "$sp" 2>/dev/null
out=$(heavy check)
check "a slot whose pid died is reaped at once, not after the TTL" '[[ ! -e $slots/withpid.slot ]] && grep -q "slots 0/2" <<<"$out"'
out=$(heavy acquire badpid 0 x); rc=$?
check "a non-numeric pid is refused" '(( rc == 2 ))'

echo "--- jobs.tsv"
rm -f "$slots/jobs.tsv"
T=$'\t'
FAKE_LOAD=3.5 FAKE_LOAD5=7.25 heavy run rec1 -- false >/dev/null
FAKE_LOAD=1.0 FAKE_LEVEL=2 heavy acquire rec2 0 >/dev/null
FAKE_LOAD5=2.5 heavy acquire rec3 0 >/dev/null
heavy release rec3 passed >/dev/null
f=$slots/jobs.tsv
check "run: a start line with load1, load5 and memory at the start" 'grep -q "${T}rec1${T}start${T}3.5${T}7.25${T}green${T}waited=" "$f"'
check "run: an end line with the exit code" 'grep -q "${T}rec1${T}end${T}.*${T}rc=1 dur=" "$f"'
check "a give-up (memory yellow) is logged with the reason" 'grep -q "${T}rec2${T}giveup${T}.*${T}HEAVY WAIT: memory yellow" "$f"'
check "release logs the outcome it was given" 'grep -q "${T}rec3${T}end${T}.*${T}outcome=passed dur=" "$f"'
check "every line has 7 tab-separated columns" '[[ -z $(awk -F "\t" "NF != 7" "$f") ]]'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
