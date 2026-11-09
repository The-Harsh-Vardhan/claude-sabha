#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016  # fixture lines hold literal $VAR text; hermetic.sh is sourced by path
# bin/sabha-gate --checks: the workspace checks (aikido, screenshots, not-in-design, questions) are file tests; bad input
# shuts or exits 2, never opens and never loops; nothing printed holds a control or non-ASCII byte.
# Run: tests/test-gate-checks.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
bin=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-gatechk.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
cd "$dir" || exit 1
fails=0
# run <args...>: gate output to $dir/out, rc returned; a run that outlives 5 s is killed (rc 143) so a loop fails the row
run() {
  "$bin/sabha-gate" "$@" >"$dir/out" 2>"$dir/err" & local p=$!
  ( sleep 5; kill "$p" 2>/dev/null ) & local k=$!
  wait "$p"; local r=$?
  kill "$k" 2>/dev/null; wait "$k" 2>/dev/null
  return "$r"
}
want() { # want <rc> <label> <args...>
  local w=$1 l=$2; shift 2; run "$@"; local r=$?
  if [[ $r -ne $w ]]; then echo "FAIL: $l (rc $r, wanted $w)"; sed 's/^/  out: /' "$dir/out" "$dir/err"; fails=$((fails + 1)); fi
}
saw() { # saw <label> <text>: the last run printed the text
  grep -q -F -- "$2" "$dir/out" "$dir/err" || { echo "FAIL: $1 (no '$2')"; sed 's/^/  out: /' "$dir/out" "$dir/err"; fails=$((fails + 1)); }
}
cfg() { printf '%s\n' "$@" > cfg; }

printf 'aikido: scanned=4 high=0 critical=0\n' > scan.txt
printf 'ui: no\n' > pack-noui.md
printf 'ui: yes\nscreenshot: shot.png\n' > pack-ui.md; printf 'x' > shot.png
printf 'plain spec\nNOT IN DESIGN - needs owner approval\nAPPROVED: owner, 4 Nov\n' > spec-ok.md
printf 'questions\n' > q.md

cfg 'aikido scan.txt' 'screenshots pack-ui.md' 'not-in-design spec-ok.md' 'questions q.md'
want 0 "all four pass, checks only" --checks cfg
saw "all four named" "ok   check not-in-design spec-ok.md"
saw "open" "GATE OPEN"

# aikido
cfg 'aikido scan.txt'
printf 'aikido: high=1 critical=0\n' > scan.txt;           want 1 "aikido high=1" --checks cfg
printf 'aikido: high=0 critical=2\n' > scan.txt;           want 1 "aikido critical=2" --checks cfg
printf 'scanned, all good\n' > scan.txt;                   want 1 "aikido no aikido: line" --checks cfg
printf 'aikido: high=x critical=0\n' > scan.txt;           want 1 "aikido high not a number" --checks cfg
printf 'aikido: high=0\n' > scan.txt;                      want 1 "aikido no critical" --checks cfg
printf 'aikido: high=1 critical=0\naikido: high=0 critical=0\n' > scan.txt
want 0 "aikido newest line wins (dirty then clean)" --checks cfg
printf 'aikido: high=0 critical=0\naikido: high=0 critical=1\n' > scan.txt
want 1 "aikido newest line wins (clean then dirty)" --checks cfg
printf 'aikido: high=0000 critical=0\r\n' > scan.txt;      want 0 "aikido CRLF and zero padding" --checks cfg
printf 'aikido: high=0 critical=0\n' > scan.txt
rm -f scan.txt;                                            want 1 "aikido missing file" --checks cfg
mkdir scan.txt;                                            want 1 "aikido path is a directory" --checks cfg
rmdir scan.txt
head -c 9000000 /dev/zero | tr '\0' 'a' > scan.txt
want 1 "aikido file over 8 MB" --checks cfg; saw "size reason" "larger than 8 MB"
printf 'aikido: high=0 critical=0 \200\377 caf\303\251\n' > scan.txt
want 0 "non-ASCII bytes in a checked file do not crash it" --checks cfg
printf 'aikido: scanned=4 high=0 critical=0\n' > scan.txt

# screenshots
cfg 'screenshots pack-noui.md';                            want 0 "ui: no" --checks cfg
cfg 'screenshots pack-ui.md';                              want 0 "ui: yes with an image" --checks cfg
printf 'ui: yes\n' > p.md;                                 cfg 'screenshots p.md'; want 1 "ui: yes, no screenshot line" --checks cfg
printf 'ui: yes\nscreenshot: gone.png\n' > p.md;           want 1 "screenshot file missing" --checks cfg
printf 'ui: yes\nscreenshot: notes.txt\n' > p.md; printf x > notes.txt
want 1 "screenshot is not an image name" --checks cfg
printf 'pack with no ui line\nscreenshot: shot.png\n' > p.md; want 1 "no ui: line fails closed" --checks cfg
printf 'ui: no\nui: yes\n' > p.md;                         want 1 "newest ui: line wins (yes, no shot)" --checks cfg
printf 'ui: maybe\n' > p.md;                               want 1 "ui: maybe" --checks cfg
mkdir sub; printf 'ui: yes\nscreenshot: a.png\nscreenshot: b.png\n' > sub/p.md; printf x > sub/a.png
cfg 'screenshots sub/p.md';                                want 1 "second screenshot missing" --checks cfg
printf x > sub/b.png;                                      want 0 "images are read beside the pack" --checks cfg

# not-in-design
cfg 'not-in-design s.md'
printf 'NOT IN DESIGN: export button\n' > s.md;            want 1 "flag without approval" --checks cfg
saw "counts" "1 NOT IN DESIGN, 0 APPROVED:"
printf 'NOT IN DESIGN: a\nNOT IN DESIGN: b\nAPPROVED: a\n' > s.md; want 1 "two flags, one approval" --checks cfg
printf 'NOT IN DESIGN: a\nNOT IN DESIGN: b\nAPPROVED: a\nAPPROVED: b\n' > s.md; want 0 "two flags, two approvals" --checks cfg
printf 'nothing flagged\n' > s.md;                         want 0 "no flag, no approval needed" --checks cfg
printf 'NOT IN DESIGN: a\n  APPROVED: indented does not count\n' > s.md; want 1 "an indented approval is not a line start" --checks cfg
rm -f s.md;                                                want 1 "spec file missing" --checks cfg

# questions
cfg 'questions qq.md'
want 1 "questions file missing" --checks cfg
: > qq.md;                                                 want 1 "questions file empty" --checks cfg
printf '\n  \n\t\n' > qq.md;                               want 1 "questions file blank lines only" --checks cfg
printf 'Q1: which?\n' > qq.md;                             want 0 "questions file present" --checks cfg

# the config itself
cfg '# the checks of this workspace' '' '   ' 'questions q.md'
want 0 "comments and blank lines skipped" --checks cfg
printf 'questions q.md\r\naikido scan.txt\r\n' > cfg;      want 0 "CRLF config" --checks cfg
printf 'questions q.md' > cfg;                             want 0 "no final newline" --checks cfg
cfg 'questions q.md' 'sast scan.txt';                      want 1 "unknown check shuts" --checks cfg; saw "unknown named" "unknown check"
cfg 'questions';                                           want 1 "check with no path shuts" --checks cfg; saw "no path" "needs a path"
cfg '# only a comment' '';                                 want 1 "a config with no checks never opens" --checks cfg; saw "no checks" "no checks in"
: > cfg;                                                   want 1 "an empty config never opens" --checks cfg
want 2 "missing config file" --checks nope.conf
head -c 1100000 /dev/zero | tr '\0' '#' > cfg;             want 2 "config over 1 MB" --checks cfg
cfg 'questions q.md'
want 2 "--checks with no value" --checks
want 2 "--checks with an empty value" --checks ""
want 2 "-C with no value" -C
want 2 "--brief with no value" --brief
want 2 "unknown option" --checkz cfg
want 2 "no args at all"
HOME=$dir/home; mkdir home; cp q.md home/q.md
cfg 'questions ~/q.md';                                    want 0 "leading ~ expands" --checks cfg
cfg 'questions $HOME/q.md';                                want 0 "\$VAR expands" --checks cfg
cfg 'questions ${HOME}/q.md';                              want 0 "\${VAR} expands" --checks cfg
cfg 'questions $SABHA_NOPE_UNSET/q.md';                    want 1 "unset variable shuts" --checks cfg; saw "unset named" "unset variable"
printf 'questions $(touch %s/pwned)\n' "$dir" > cfg;       want 1 "command substitution is never run" --checks cfg
[[ ! -e pwned ]] || { echo "FAIL: command substitution ran"; fails=$((fails + 1)); }
cfg 'questions q.md'
SABHA_GATE_CHECKS=$dir/cfg run; r=$?
[[ $r -eq 0 ]] || { echo "FAIL: SABHA_GATE_CHECKS (rc $r)"; fails=$((fails + 1)); }
SABHA_GATE_CHECKS=$dir/cfg run --checks "$dir/other-missing"; r=$?
[[ $r -eq 2 ]] || { echo "FAIL: --checks beats the env var (rc $r)"; fails=$((fails + 1)); }

# -C: checks are read from DIR, the config from where the caller stands
mkdir ws; printf 'x\n' > ws/q.md
cfg 'questions q.md';                                      want 0 "-C reads paths from DIR" -C ws --checks "$dir/cfg"
rm ws/q.md;                                                want 1 "-C: file absent in DIR shuts" -C ws --checks "$dir/cfg"
want 2 "-C to a missing dir" -C nowhere --checks cfg

# verdict files and checks together
printf 'verdict: ACCEPT\n' > t-review.md; printf 'verdict: NO BREAK\n' > t-sec.md
cfg 'questions q.md'
want 0 "verdicts and checks both ok" --checks cfg t-review.md t-sec.md
cfg 'questions nope.md'
want 1 "verdicts ok, check fails" --checks cfg t-review.md t-sec.md
cfg 'questions q.md'; printf 'verdict: REVISE\n' > r-review.md
want 1 "check ok, reviewer not ACCEPT" --checks cfg r-review.md t-sec.md
want 1 "check ok, critics only, no reviewer file" --checks cfg t-sec.md
printf 'gate: t-review.md, t-sec.md\n' > brief.md
want 0 "--brief with --checks" --checks cfg --brief brief.md
printf 'gate:\n' > brief0.md
want 2 "an empty gate: line is usage even with checks" --checks cfg --brief brief0.md
want 2 "an empty gate: line is usage" --brief brief0.md
want 2 "--brief file missing" --checks cfg --brief nope.md
want 1 "verdict files alone are still gated (no checks)" t-sec.md
want 0 "verdict files alone still open" t-review.md t-sec.md

# output: only printable ASCII and newlines, whatever the data holds
ESC=$(printf '\033'); BEL=$(printf '\007')
printf 'questions q%s]0;title%s.md\n' "$ESC" "$BEL" > cfg
run --checks cfg
if LC_ALL=C grep -q "[^ -~]" <(tr -d '\n' < "$dir/out"); then echo "FAIL: control byte in the check line"; fails=$((fails + 1)); fi
printf 'verdict: BREAK 1 %s[31m caf\303\251\r\n' "$ESC" > t-be.md
cfg 'questions q.md'
run --checks cfg t-review.md t-be.md
if LC_ALL=C grep -q "[^ -~]" <(tr -d '\n' < "$dir/out"); then echo "FAIL: control or non-ASCII byte in the verdict line"; fails=$((fails + 1)); fi
saw "verdict still shown" "SHUT t-be.md"
run -C "$(printf 'no%sdir' "$ESC")" --checks cfg
if LC_ALL=C grep -q "[^ -~]" <(cat "$dir/err" "$dir/out" | tr -d '\n'); then echo "FAIL: control byte on stderr"; fails=$((fails + 1)); fi

if (( fails )); then echo "FAILED: $fails row(s)"; exit 1; fi
echo "ok: --checks runs aikido, screenshots, not-in-design and questions as file tests; bad input shuts or exits 2; output is clean ASCII"
