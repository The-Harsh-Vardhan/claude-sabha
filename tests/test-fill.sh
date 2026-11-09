#!/usr/bin/env bash
# bin/sabha-fill: the proposal follows usage, load and the heavy gate; bad input is refused or reported, never a crash
# and never a blind plan; nothing on disk changes; output is pure ASCII and the same for the same inputs.
# Hermetic: temp workspaces, a fake heavy gate, SABHA_FILL_NOW / SABHA_FILL_LOAD5 pinned; no herdr, no network.
# Run: tests/test-fill.sh. FILL_TEST_BIN=<dir> runs the same rows against another copy of bin/ (to prove a row fails on a
# broken copy).
# shellcheck disable=SC1091,SC2015,SC2016  # sourced helper; A && B || fail is the check idiom; printf formats keep literals
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=${FILL_TEST_BIN:-$(cd "$(dirname "$0")/../bin" && pwd)}
top=$(mktemp -d "${TMPDIR:-/tmp}/sabha-fill.XXXXXX") || exit 1
trap 'rm -rf "$top" "$HERMETIC_FAKE_DIR"' EXIT
n=0
fail() { echo "FAIL: $*"; exit 1; }
pass() { n=$((n + 1)); }
NOW=1800000000

# fake gate: prints a verdict, exits 0 (GO) or 75 (WAIT) by the word in $top/gate
cat >"$top/gate.sh" <<EOF
#!/usr/bin/env bash
if [[ \$(cat "$top/gate") == GO ]]; then echo "GO load 1"; exit 0; fi
echo "WAIT load 99"; exit 75
EOF
chmod +x "$top/gate.sh"
echo GO >"$top/gate"

# newws <name>: a workspace with a conf and a fresh limits file (40% / 55%, both windows ahead)
newws() {
  W=$top/$1; mkdir -p "$W/inbox" "$W/status"
  printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Worker:sonnet"\n' "$W" "$W" >"$W/sabha.conf"
  printf 'five_hour 40 %s %s\nseven_day 55 %s %s\n' $((NOW + 3600)) $((NOW - 60)) $((NOW + 86400)) $((NOW - 60)) >"$W/status/limits.txt"
  export SABHA_CONF=$W/sabha.conf SABHA_IMPL=$W SABHA_FILL_NOW=$NOW SABHA_FILL_LOAD5=5 SABHA_FILL_HEAVY_BIN=$top/gate.sh
  unset SABHA_STOP SABHA_FILL_RESERVE SABHA_FILL_COST_M SABHA_FILL_LIMITS SABHA_LIMITS_FILE
}
# brief <role> <nnn> <slug> <size> [extra header line] [task]: an un-acked brief
brief() {
  mkdir -p "$W/inbox/$1"
  printf 'from: Boss\nsize: %s\n%s\n\n%s\n' "$4" "${5:-slice: none}" "${6:-do the $3 work}" >"$W/inbox/$1/$2-boss-$3.md"
}
run() { out=$(python3 -I "$BIN/sabha-fill" "$@" 2>"$top/err"); rc=$?; err=$(cat "$top/err"); }
tree() { (cd "$W" && find . -type f -o -type l | LC_ALL=C sort | xargs cksum 2>/dev/null | cksum); }
nonascii() { printf '%s' "$1" | LC_ALL=C grep -q -v '^[ -~]*$'; }
line_of() { printf '%s\n' "$out" | grep -n -- "$1" | head -1 | cut -d: -f1; }

# ---- A: the main path. budget = 90 - 55 - 10 = 25
newws a
brief Bhima 097 fill M
brief Arjun 031 small S
brief Karna 136 gates L "slice: none" "run the gradle suite and Jest"
brief Nakul 050 docker-note M "heavy: no" "write the docker note"
brief Arjun 032 acked M; : >"$W/inbox/Arjun/032.ack"
brief Arjun 033 finished M; : >"$W/inbox/Arjun/033.done"
brief Arjun 034 stopped M; : >"$W/inbox/Arjun/034.cancel"
: >"$W/inbox/Arjun/035.claim"
printf 'amends: 031\nbody\n' >"$W/inbox/Arjun/031.1-boss-more.md"
before=$(tree)
run
[[ $rc -eq 0 ]] || fail "A: exit $rc, err: $err"
[[ $(tree) == "$before" ]] || fail "A: the workspace changed (must be read-only)"
pass
[[ $out == *"highest 55%"* && $out == *"budget 25 points"* ]] || fail "A: budget line wrong: $out"
pass
for w in 'Bhima/097' 'Arjun/031' 'Nakul/050' 'Karna/136'; do [[ $out == *"$w"* ]] || fail "A: $w missing: $out"; done
for w in 'Arjun/032' 'Arjun/033' 'Arjun/034' 'Arjun/035' '031.1'; do [[ $out != *"$w"* ]] || fail "A: $w must not be listed: $out"; done
pass
l1=$(line_of 'Arjun/031'); l2=$(line_of 'Nakul/050'); l3=$(line_of 'Bhima/097'); l4=$(line_of 'Karna/136')
(( l1 < l2 && l2 < l3 && l3 < l4 )) || fail "A: order must be light by number (031 050 097), heavy last (got $l1 $l2 $l3 $l4): $out"
pass
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'heavy' || fail "A: gradle/Jest brief must be heavy"
printf '%s\n' "$out" | grep 'Nakul/050' | grep -q 'light' || fail "A: heavy: no must override the docker keyword"
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'ready now' || fail "A: heavy must be ready at load5 5 and GO: $out"
pass
[[ $out == *"Planned 18 of 25 points"* ]] || fail "A: 4+2+4+8 = 18: $out"
pass
run; again=$out; run
[[ $again == "$out" ]] || fail "A: two runs with the same inputs differ"
pass

# heavy waits on load, and on the gate
SABHA_FILL_LOAD5=25 run
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'queued until load5 <= 20' || fail "A: load5 25 must queue the heavy brief: $out"
pass
SABHA_FILL_LOAD5=20 run
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'ready now' || fail "A: load5 20 is allowed (<=): $out"
pass
echo WAIT >"$top/gate"; run
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'queued' || fail "A: a WAIT gate must queue the heavy brief: $out"
[[ $out == *"heavy gate: WAIT"* ]] || fail "A: gate verdict not shown: $out"
pass
echo GO >"$top/gate"
SABHA_FILL_HEAVY_BIN=$top/none.sh run
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'queued' || fail "A: a missing gate must not be a GO: $out"
pass
printf 'echo GO; exit 0\n' >"$top/gate-ok.sh"
SABHA_FILL_HEAVY_BIN=$top/gate-ok.sh run
printf '%s\n' "$out" | grep 'Karna/136' | grep -q 'queued' || fail "A: a gate that cannot execute must not be a GO: $out"
pass
SABHA_FILL_LOAD5=nan run
[[ $rc -eq 2 ]] || fail "A: load5 nan must exit 2, got $rc"
pass

# ---- B: the budget
run --reserve 70
[[ $rc -eq 0 && $out == *"budget -35 points"* && $out == *"Plan: none"* && $out == *"Over budget"* ]] || fail "B: no budget must plan nothing: $out"
pass
SABHA_STOP=off run
[[ $out == *"stop line 100"* && $out == *"budget 35 points"* ]] || fail "B: SABHA_STOP=off: $out"
pass
SABHA_FILL_COST_M=20 run
[[ $out == *"Over budget (not planned):"* ]] || fail "B: cost M=20 must push a brief over: $out"
printf '%s\n' "$out" | sed -n '/^Over budget/,$p' | grep -q 'Karna/136' || fail "B: the heavy L brief must be over budget: $out"
pass

# ---- C: usage unreadable means no plan (fail closed)
newws c; brief Bhima 001 x M
rm "$W/status/limits.txt"; run
[[ $rc -eq 3 && $out == *"plan: none"* && $out != *"Bhima/001"* ]] || fail "C: missing limits: rc $rc: $out"
pass
printf 'five_hour 40 %s %s\n' $((NOW + 3600)) $((NOW - 90000)) >"$W/status/limits.txt"; run
[[ $rc -eq 3 ]] || fail "C: a stale reading must give exit 3, got $rc: $out"
pass
printf 'five_hour nan 1 %s\nseven_day 150 %s %s\nfive_hour x\n{"a":1}\n\n' "$NOW" $((NOW + 5)) "$NOW" >"$W/status/limits.txt"; run
[[ $rc -eq 3 ]] || fail "C: malformed readings must give exit 3, got $rc: $out"
pass
: >"$W/status/limits.txt"; run
[[ $rc -eq 3 ]] || fail "C: an empty limits file must give exit 3, got $rc"
pass
head -c 300000 /dev/zero | tr '\0' 'a' >"$W/status/limits.txt"; run
[[ $rc -eq 3 ]] || fail "C: a huge junk limits file must give exit 3, got $rc"
pass
printf 'five_hour 80 %s %s\nseven_day 30 %s %s\n' $((NOW - 10)) $((NOW - 100)) $((NOW + 100)) $((NOW - 100)) >"$W/status/limits.txt"; run
[[ $rc -eq 0 && $out == *"five_hour 80% (window reset)"* && $out == *"highest 30%"* ]] || fail "C: a passed window counts as 0: $out"
pass

# ---- D: usage errors exit 2, never loop
newws d; brief Bhima 001 x M
for args in "--reserve" "--reserve abc" "--reserve -5" "--reserve 101" "--reserve --reserve" "--bogus" "stray" "--reserve nan" "--reserve inf"; do
  # shellcheck disable=SC2086  # the args are split on purpose
  timeout 20 python3 -I "$BIN/sabha-fill" $args >/dev/null 2>&1; rc=$?
  [[ $rc -eq 2 ]] || fail "D: 'sabha-fill $args' exited $rc, want 2"
done
pass
SABHA_FILL_COST_M=-1 run; [[ $rc -eq 2 ]] || fail "D: negative cost must exit 2, got $rc"
SABHA_FILL_COST_M=abc run; [[ $rc -eq 2 ]] || fail "D: bad cost must exit 2, got $rc"
SABHA_STOP=abc run; [[ $rc -eq 2 ]] || fail "D: bad SABHA_STOP must exit 2, got $rc"
pass
run --help; [[ $rc -eq 0 && $out == usage:* ]] || fail "D: --help: $out"
pass

# ---- E: hostile and odd briefs and role names
newws e
mkdir -p "$W/inbox/Ro"$'\t'"le" "$W/inbox/Plain"
printf 'from: x\nsize: L, with notes\ntask: do \033]0;pwn\007 the \033[31mred\033[0m thing \xe2\x80\xae\r\x9b done\n\nbody\n' >"$W/inbox/Ro"$'\t'"le/001-x-evil.md"
printf '' >"$W/inbox/Plain/002-x-empty.md"
printf '\000\001\002binary\000\n' >"$W/inbox/Plain/003-x-binary.md"
head -c 200000 /dev/zero | tr '\0' 'z' >"$W/inbox/Plain/004-x-huge.md"
printf 'from: x\nsize: ?\ntask: caf\xc3\xa9 \xff\n' >"$W/inbox/Plain/005-x-latin.md"
printf 'no header at all, just text\n' >"$W/inbox/Plain/006-x-nohead.md"
printf 'from: x\nsize: S\nheavy: yes\n\nbody\n' >"$W/inbox/Plain/007-x-flag.md"
mkdir -p "$top/elsewhere"; printf 'from: x\n\nsecret\n' >"$top/elsewhere/008-x-out.md"
ln -s "$top/elsewhere/008-x-out.md" "$W/inbox/Plain/008-x-link.md"
ln -s "$top/elsewhere" "$W/inbox/LinkRole"
mkdir "$W/inbox/Plain/009-x-dir.md"
before=$(tree)
run
[[ $rc -eq 0 ]] || fail "E: exit $rc, err: $err"
nonascii "$out" && fail "E: output has a byte outside printable ASCII: $(printf '%s' "$out" | od -c | head -5)"
[[ $out != *$'\033'* && $out != *$'\r'* && $out != *$'\007'* ]] || fail "E: a control character reached the output"
pass
for w in 'Plain/002' 'Plain/003' 'Plain/004' 'Plain/005' 'Plain/006' 'Plain/007'; do [[ $out == *"$w"* ]] || fail "E: $w missing: $out"; done
[[ $out != *"008"* && $out != *"LinkRole"* && $out != *"009"* ]] || fail "E: a symlink or directory must be skipped: $out"
pass
printf '%s\n' "$out" | grep 'Plain/007' | grep -q 'heavy' || fail "E: heavy: yes must make it heavy"
printf '%s\n' "$out" | grep 'Plain/005' | grep -q ' M ' || fail "E: size ? must default to M: $out"
pass
[[ $(tree) == "$before" ]] || fail "E: the workspace changed"
pass
[[ $err == "" ]] || fail "E: stderr must be empty: $err"
pass

# ---- F: a brief with a huge header line or many files does not hang
newws f
mkdir -p "$W/inbox/Many"
i=0; while (( i < 60 )); do printf 'from: x\n\nt\n' >"$W/inbox/Many/$(printf '%03d' $((i + 100)))-x-m.md"; i=$((i + 1)); done
SABHA_FILL_RESERVE=0 SABHA_FILL_COST_M=0 run
[[ $rc -eq 0 && $out == *"60 of 60 briefs"* ]] || fail "F: 60 briefs: $out"
pass

# ---- G: sabha dispatches to it
G=$top/g; mkdir -p "$G"; cp -R "$BIN" "$G/bin"; cp "$W/sabha.conf" "$G/sabha.conf"
out=$(SABHA_CONF=$W/sabha.conf bash "$G/bin/sabha" fill 2>&1); rc=$?
[[ $rc -eq 0 && $out == "sabha fill:"* ]] || fail "G: sabha fill: rc $rc: $out"
pass
out=$(SABHA_CONF=$W/sabha.conf bash "$G/bin/sabha" fill --reserve 2>&1); rc=$?
[[ $rc -eq 2 ]] || fail "G: sabha fill with a bare option must exit 2, got $rc: $out"
pass

# lim <five pct> <five reset> <five written> <seven pct> <seven reset> <seven written>: the limits file of the current workspace
lim() { printf 'five_hour %s %s %s\nseven_day %s %s %s\n' "$@" >"$W/status/limits.txt"; }
F=$((NOW + 3600)); S=$((NOW + 86400)); OK=$((NOW - 60))

# ---- H: settings come from sabha.conf too; the environment wins (review 233 MUST 1)
newws h; brief Bhima 001 x M
printf 'SABHA_FILL_RESERVE=95\n' >>"$W/sabha.conf"; run
[[ $rc -eq 0 && $out == *"reserve 95,"* ]] || fail "H: SABHA_FILL_RESERVE set only in sabha.conf must count: $out"
pass
SABHA_FILL_RESERVE=5 run
[[ $out == *"reserve 5,"* && $out == *"budget 30 points"* ]] || fail "H: the environment must win over sabha.conf: $out"
pass
newws h; printf 'SABHA_FILL_RESERVE=5\n' >>"$W/sabha.conf"
SABHA_FILL_RESERVE=5 run
[[ $out == *"reserve 5,"* ]] || fail "H: a key set in both: $out"
pass
newws h; printf 'SABHA_STOP=80\n' >>"$W/sabha.conf"; run
[[ $out == *"stop line 80"* && $out == *"budget 15 points"* ]] || fail "H: SABHA_STOP set only in sabha.conf (the grid stops there too): $out"
pass
SABHA_STOP=70 run
[[ $out == *"stop line 70"* ]] || fail "H: SABHA_STOP in the environment must win: $out"
pass
newws h; printf 'SABHA_FILL_COST_M=9\n' >>"$W/sabha.conf"; brief Bhima 001 x M; run
printf '%s\n' "$out" | grep -q '9 pts' || fail "H: SABHA_FILL_COST_M set only in sabha.conf: $out"
pass
newws h; printf 'SABHA_FILL_NOW=1000\nSABHA_FILL_LOAD5=99\n' >>"$W/sabha.conf"; unset SABHA_FILL_LOAD5; run
[[ $rc -eq 0 && $out == *"proposal at 2027-"* && $out == *"load5: "* && $out != *"load5: 99.0"* ]] || fail "H: the test hooks must not be read from sabha.conf: $out"
export SABHA_FILL_NOW=$NOW SABHA_FILL_LOAD5=5
pass

# ---- I: a stale, missing or odd window is never ignored in the safe direction (MUST 2)
newws i; brief Bhima 001 x S
lim 10 "$F" "$OK" 88 "$S" $((NOW - 99999)); run
[[ $rc -eq 3 && $out == *"seven_day stale"* && $out != *"Bhima/001"* ]] || fail "I: stale seven_day 88 with fresh five_hour 10: rc $rc: $out"
pass
lim 88 "$F" $((NOW - 99999)) 10 "$S" "$OK"; run
[[ $rc -eq 3 && $out == *"five_hour stale"* ]] || fail "I: stale five_hour 88 with fresh seven_day 10: rc $rc: $out"
pass
lim 10 "$F" $((NOW - 99999)) 10 "$S" $((NOW - 99999)); run
[[ $rc -eq 3 && $out == *"five_hour stale"* && $out == *"seven_day stale"* ]] || fail "I: both stale must name both: rc $rc: $out"
pass
printf 'five_hour 10 %s %s\n' "$F" "$OK" >"$W/status/limits.txt"; run
[[ $rc -eq 3 && $out == *"seven_day missing"* ]] || fail "I: a missing seven_day must give exit 3 and name it: rc $rc: $out"
pass
printf 'seven_day 10 %s %s\n' "$S" "$OK" >"$W/status/limits.txt"; run
[[ $rc -eq 3 && $out == *"five_hour missing"* ]] || fail "I: a missing five_hour: rc $rc: $out"
pass
lim 10 "$F" $((NOW - 21600)) 10 "$S" "$OK"; run
[[ $rc -eq 0 ]] || fail "I: a reading exactly SABHA_FILL_STALE old is still fresh: rc $rc: $out"
pass
lim 10 "$F" $((NOW - 21601)) 10 "$S" "$OK"; run
[[ $rc -eq 3 ]] || fail "I: a reading one second over SABHA_FILL_STALE is stale: rc $rc: $out"
pass
lim 10 "$F" $((NOW + 60)) 10 "$S" "$OK"; run
[[ $rc -eq 0 ]] || fail "I: a stamp 60 s ahead is clock skew, accepted: rc $rc: $out"
pass
lim 10 "$F" $((NOW + 61)) 10 "$S" "$OK"; run
[[ $rc -eq 3 && $out == *"future"* ]] || fail "I: a stamp from the future must give exit 3: rc $rc: $out"
pass

# ---- J: odd numbers fail closed with one line, never a traceback (MUST 3, SHOULD 2 and 4)
for bad in 99999999999999999999 -5 1.5 abc 1_0 0x10 ""; do
  lim 10 "$bad" "$OK" 10 "$S" "$OK"; run
  [[ $rc -eq 3 && $err == "" && $out != *Traceback* && $out == *"five_hour "* ]] || fail "J: resets_at '$bad': rc $rc, err $err: $out"
  lim 10 "$F" "$bad" 10 "$S" "$OK"; run
  [[ $rc -eq 3 && $err == "" && $out != *Traceback* ]] || fail "J: written '$bad': rc $rc, err $err: $out"
done
pass
for bad in -50 101 100.5 nan inf 1e2 abc 1_0; do
  lim "$bad" "$F" "$OK" 10 "$S" "$OK"; run
  [[ $rc -eq 3 && $err == "" && $out != *Traceback* ]] || fail "J: percent '$bad': rc $rc, err $err: $out"
done
pass
lim 0 "$F" "$OK" 0 "$S" "$OK"; run
[[ $rc -eq 0 && $out == *"highest 0%"* && $out == *"budget 80 points"* ]] || fail "J: 0 percent is valid: $out"
lim 100 "$F" "$OK" 3 "$S" "$OK"; run
[[ $rc -eq 0 && $out == *"highest 100%"* && $out == *"budget -20 points"* && $out == *"Plan: none"* ]] || fail "J: 100 percent is valid and leaves no budget: $out"
pass
lim 80 "$NOW" "$OK" 3 "$S" "$OK"; run
[[ $out == *"five_hour 80% (window reset)"* && $out == *"highest 3%"* ]] || fail "J: resets_at exactly now is a passed window: $out"
lim 80 $((NOW + 1)) "$OK" 3 "$S" "$OK"; run
[[ $out == *"highest 80%"* ]] || fail "J: resets_at one second ahead is not passed: $out"
pass
lim 10 100000000001 "$OK" 10 "$S" "$OK"; run
[[ $rc -eq 3 && $out == *"five_hour out of range"* ]] || fail "J: resets_at above the epoch bound: rc $rc: $out"
lim 10 "$F" 100000000001 10 "$S" "$OK"; run
[[ $rc -eq 3 && $out == *"five_hour out of range"* ]] || fail "J: written above the epoch bound: rc $rc: $out"
pass
lim 88 0 "$OK" 10 "$S" "$OK"; run
[[ $rc -eq 0 && $out == *"five_hour 88% (reset time unknown)"* && $out == *"highest 88%"* && $out == *"budget -8 points"* ]] || fail "J: resets_at 0 is an unknown reset time, not a passed window: rc $rc: $out"
lim 10 "$F" "$OK" 88 0 "$OK"; run
[[ $rc -eq 0 && $out == *"seven_day 88% (reset time unknown)"* && $out == *"highest 88%"* ]] || fail "J: seven_day resets_at 0: rc $rc: $out"
pass
lim 10 "$F" "$OK" 10 "$S" "$OK"
{ head -c 100000 /dev/zero | tr '\0' 'a'; echo; cat "$W/status/limits.txt"; } >"$W/status/limits.big"; mv "$W/status/limits.big" "$W/status/limits.txt"; run
[[ $rc -eq 3 && $out == *"five_hour missing"* ]] || fail "J: readings after the 64 KB cut are not read: rc $rc: $out"
pass

# ---- K: the budget edges (SHOULD 2)
newws k; brief Bhima 001 x M
SABHA_FILL_COST_M=25 run
[[ $out == *"Planned 25 of 25 points, 1 of 1"* ]] || fail "K: a brief that fits the budget exactly must be planned: $out"
pass
SABHA_FILL_COST_M=26 run
[[ $out == *"Plan: none"* && $out == *"Over budget"* ]] || fail "K: one point over must not be planned: $out"
pass
SABHA_FILL_RESERVE=35 SABHA_FILL_COST_M=0 run
[[ $out == *"budget 0 points"* && $out == *"Plan: none"* && $out == *"Planned 0 of 0 points, 0 of 1"* ]] || fail "K: no spare plans nothing even at cost 0: $out"
pass

# ---- L: briefs: none at all, hostile header, unreadable (SHOULD 3)
newws l; run
[[ $rc -eq 0 && $out == *"backlog: no un-acked briefs"* ]] || fail "L: no briefs: rc $rc: $out"
pass
mkdir -p "$W/inbox/Bhima"
printf 'from: x\nsize: S\ngo: rm -rf %s/marker\ntask: `touch %s/marker` $(touch %s/marker) ../../etc/passwd\n\nbody\n' "$top" "$top" "$top" >"$W/inbox/Bhima/001-x-hostile.md"
run
[[ $rc -eq 0 && ! -e "$top/marker" && $out == *"Bhima/001"* ]] || fail "L: a hostile header must be printed, never run: $out"
pass
brief Bhima 002 secret S; chmod 000 "$W/inbox/Bhima/002-boss-secret.md"; run; chmod 644 "$W/inbox/Bhima/002-boss-secret.md"
[[ $rc -eq 0 && $out == *"1 brief file(s) could not be read"* && $out != *"Bhima/002"* ]] || fail "L: an unreadable brief must be reported: $out"
pass

# ---- M: a heavy brief that must wait spends no budget and sits apart (SHOULD 5)
newws m; brief Karna 136 gates L "slice: none" "run the gradle suite"; brief Bhima 001 x S
echo WAIT >"$top/gate"; run
echo GO >"$top/gate"
[[ $out == *"Queued (heavy"* && $out == *"Planned 2 of 25 points, 1 of 2"* && $out == *"Queued 8 points, 1 briefs"* ]] || fail "M: a queued heavy brief must sit apart and spend nothing: $out"
printf '%s\n' "$out" | sed -n '/^Plan, light first/,/^Queued/p' | grep -q 'Karna/136' && fail "M: a queued heavy brief must not be in the plan: $out"
pass

# ---- N: what the docs say (SHOULD 1, 6, 7): fill must not claim read-only for the gate, and must name what it does not check
grep -q 'removes stale slots' "$BIN/sabha-fill" || fail "N: the header must say sabha-heavy check removes stale slots"
grep -q 'TESTS ONLY' "$BIN/sabha-fill" || fail "N: the header must say SABHA_FILL_NOW and SABHA_FILL_LOAD5 are tests only"
grep -q 'Not checked: battery' "$BIN/sabha-fill" || fail "N: the header must say battery is not checked"
pass

echo "test-fill: $n ok"
