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

# ---- G: sabha dispatches to it and keeps the usage line honest
G=$top/g; mkdir -p "$G"; cp -R "$BIN" "$G/bin"; cp "$W/sabha.conf" "$G/sabha.conf"
out=$(SABHA_CONF=$W/sabha.conf bash "$G/bin/sabha" fill 2>&1); rc=$?
[[ $rc -eq 0 && $out == "sabha fill:"* ]] || fail "G: sabha fill: rc $rc: $out"
pass
out=$(SABHA_CONF=$W/sabha.conf bash "$G/bin/sabha" nosuch 2>&1); [[ $out == *"sabha fill"* ]] || fail "G: usage line lacks fill: $out"
pass

echo "test-fill: $n ok"
