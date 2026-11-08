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
  vm.loadavg) echo "{ ${FAKE_LOAD:-1.00} 1.00 1.00 }" ;;
  kern.memorystatus_vm_pressure_level) echo "${FAKE_LEVEL:-1}" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\n[ -n "$FAKE_UPTIME_FAIL" ] && exit 1\necho "20:00  up 3 days, 2 users, load averages: ${FAKE_LOAD:-1.00} 1.00 1.00"\n' > "$dir/stubs/uptime"
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

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
