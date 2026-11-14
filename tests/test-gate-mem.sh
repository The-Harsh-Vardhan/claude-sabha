#!/usr/bin/env bash
# bin/sabha-heavy gate: memory pressure level (normal, warn, critical) plus swap growth, load5 as the secondary signal
# (soft 2 x cores warns, hard 3 x cores stops), SABHA_GATE_* thresholds, the status line. sysctl, memory_pressure and
# uptime are stubs on PATH. Run: tests/test-gate-mem.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-gate.XXXXXX") || exit 1
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
  vm.swapusage) [ -n "$FAKE_SWAP_FAIL" ] && exit 1; echo "total = 3072.00M  used = ${FAKE_SWAP:-100}.25M  free = 1269.75M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_FREE:-60}%%"\n' > "$dir/stubs/memory_pressure"
printf '#!/bin/sh\necho "20:00  up 3 days, 2 users, load averages: ${FAKE_LOAD:-1.00} ${FAKE_LOAD5:-1.00} 1.00"\n' > "$dir/stubs/uptime"
printf '#!/bin/sh\necho "${FAKE_NCPU:-10}"\n' > "$dir/stubs/getconf"
chmod +x "$dir/stubs/"*
conf() { { echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"; echo "SABHA_HEAVY_MAX=1"; echo "SABHA_HEAVY_SETTLE=0"; printf '%s\n' "$@"; } > "$dir/sabha.conf"; }
export SABHA_CONF=$dir/sabha.conf PATH=$dir/stubs:$PATH
heavy() { "$SH" "$BIN/sabha-heavy" "$@" 2>&1; }
swapreset() { rm -f "$dir/impl/status/heavy/.swap"; }
conf

echo "--- memory pressure level"
out=$(heavy gate); rc=$?
check "level 1 (normal), calm load: normal, exit 0" '(( rc == 0 )) && grep -q "^GATE normal: memory green; load5 1.00 (soft 20, hard 30, 10 cores)" <<<"$out"'
out=$(FAKE_LEVEL=2 heavy gate); rc=$?
check "level 2 (warn): warn, exit 0, names memory" '(( rc == 0 )) && grep -q "^GATE warn: .*memory yellow" <<<"$out"'
out=$(FAKE_LEVEL=4 heavy gate); rc=$?
check "level 4 (critical): critical, exit 75" '(( rc == 75 )) && grep -q "^GATE critical: .*memory red" <<<"$out"'
out=$(FAKE_SYSCTL_FAIL=1 FAKE_FREE=60 heavy gate); rc=$?
check "sandbox fallback: memory_pressure -Q free 60% is normal" '(( rc == 0 )) && grep -q "^GATE normal: memory green" <<<"$out"'
out=$(FAKE_SYSCTL_FAIL=1 FAKE_FREE=30 heavy gate); rc=$?
check "fallback: free 30% counts as warn" '(( rc == 0 )) && grep -q "^GATE warn: memory yellow (free 30%)" <<<"$out"'
out=$(FAKE_LEVEL=2 heavy check); rc=$?
check "check: memory yellow only warns, GO (exit 0), memory named" '(( rc == 0 )) && grep -q "^HEAVY GO: .*memory yellow" <<<"$out"'
out=$(FAKE_LEVEL=4 heavy check); rc=$?
check "check: memory red is WAIT (75), memory named" '(( rc == 75 )) && grep -q "^HEAVY WAIT: memory red" <<<"$out"'
out=$(FAKE_LEVEL=2 heavy acquire yel 0); rc=$?
check "acquire: memory yellow takes a slot" '(( rc == 0 )) && [[ -f $dir/impl/status/heavy/yel.slot ]]'
heavy release yel >/dev/null

echo "--- load5 is secondary: soft warn at 2 x cores, hard stop at 3 x cores"
out=$(FAKE_LOAD=69 FAKE_LOAD5=25 heavy gate); rc=$?
check "load1 69 does not matter; load5 25 (between 20 and 30) is a warn only" '(( rc == 0 )) && grep -q "^GATE warn: .*load5 25 > 20 (soft)" <<<"$out"'
out=$(FAKE_LOAD=69 FAKE_LOAD5=25 heavy check); rc=$?
check "check: GO at load5 25 (soft) even with load1 69" '(( rc == 0 )) && grep -q "^HEAVY GO: load5 25/30; memory green" <<<"$out"'
out=$(FAKE_LOAD5=31 heavy check); rc=$?
check "check: WAIT at load5 31 > 30, names load5" '(( rc == 75 )) && grep -q "load5 31 > 30 (10 cores)" <<<"$out"'
out=$(FAKE_LOAD5=31 heavy gate); rc=$?
check "gate: critical at load5 31" '(( rc == 75 )) && grep -q "^GATE critical:" <<<"$out"'
conf SABHA_GATE_LOAD_HARD=4 SABHA_GATE_LOAD_SOFT=1
out=$(FAKE_LOAD5=31 heavy gate); rc=$?
check "SABHA_GATE_LOAD_HARD=4 SOFT=1: 31 is warn (soft 10, hard 40)" '(( rc == 0 )) && grep -q "^GATE warn: .*(soft 10, hard 40, 10 cores)" <<<"$out"'
conf SABHA_HEAVY_LOAD_FACTOR=2
out=$(FAKE_LOAD=21 heavy check); rc=$?
check "an explicit SABHA_HEAVY_LOAD_FACTOR keeps the older load1 rule" '(( rc == 75 )) && grep -q "load1 21 > 20" <<<"$out"'
conf

echo "--- swap growth"
swapreset
out=$(FAKE_SWAP=100 heavy gate); rc=$?
check "first sample: no growth, normal" '(( rc == 0 )) && grep -q "^GATE normal" <<<"$out"'
out=$(FAKE_SWAP=700 heavy gate); rc=$?
check "swap +600 MB (over half of 1024): warn" '(( rc == 0 )) && grep -q "^GATE warn: .*swap +600MB" <<<"$out"'
out=$(FAKE_SWAP=1300 heavy gate); rc=$?
check "swap +1200 MB in the window: critical" '(( rc == 75 )) && grep -q "swap grew 1200MB in 600s" <<<"$out"'
out=$(FAKE_SWAP=1300 heavy check); rc=$?
check "check: WAIT names the swap growth" '(( rc == 75 )) && grep -q "swap grew" <<<"$out"'
swapreset
conf SABHA_GATE_SWAP_MB=100
FAKE_SWAP=100 heavy gate >/dev/null
out=$(FAKE_SWAP=250 heavy gate); rc=$?
check "SABHA_GATE_SWAP_MB=100: +150 is critical" '(( rc == 75 ))'
conf; swapreset
out=$(FAKE_SWAP_FAIL=1 heavy gate); rc=$?
check "swap unreadable: not a stop" '(( rc == 0 )) && grep -q "^GATE normal" <<<"$out"'
mkdir -p "$dir/impl/status/heavy"
printf '%s 5000\n' "$(( $(date +%s) - 3000 ))" > "$dir/impl/status/heavy/.swap"
out=$(FAKE_SWAP=100 heavy gate); rc=$?
check "a sample older than the window is not a base" '(( rc == 0 )) && grep -q "^GATE normal" <<<"$out"'

echo "--- status line"
swapreset
out=$(heavy status)
check "status shows the gate state first" '[[ $out == "gate normal | load5 1.00/10 green | mem green | slots 0/1" ]]'
out=$(FAKE_LEVEL=2 heavy status)
check "status: warn" 'grep -q "^gate warn | " <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
