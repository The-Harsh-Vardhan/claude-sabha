#!/usr/bin/env bash
# bin/sabha-prune: report content, rerun stability, control characters and bad bytes, a failed or missing inventory,
# no --apply ever, caps, flag errors, ~ and $HOME in config, the lock, a non-regular target, the front door.
# Fixtures and a fake inventory script only; no gh, no herdr, no real worktrees. Run: tests/test-prune.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-prune.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

impl=$dir/impl out=$dir/out
mkdir -p "$impl"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus Worker:sonnet"\n' "$dir" "$impl" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
fake=$dir/inv.sh
# the fake inventory: logs its arguments, prints what FAKE_MODE asks for, exits FAKE_RC
cat >"$fake" <<'X'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_LOG"
case ${FAKE_MODE:-basic} in
  basic) echo "WORKTREE SAFE worktrees/a/repo--one feat/one dirty 0 last commit 2026-11-01"
         echo "UNPUSHED 2026-11-02 (2 commits) git -C /x push -u origin feat/two" ;;
  other) echo "MAIN backend/repo main base dev HEAD not on base" ;;
  nasty) printf 'WORKTREE UNIQUE caf\303\251 \377 \033]0;pwn\007 end \342\200\256 \342\200\250 x\r\n\tlast\n\n\0junk\n' ;;
  empty) : ;;
  many) i=0; while [ $i -lt 150 ]; do echo "row $i"; i=$((i + 1)); done ;;
  long) head -c 5000 /dev/zero | tr '\0' 'a'; echo ;;
  huge) head -c 2500000 /dev/zero | tr '\0' 'b' ;;
esac
exit "${FAKE_RC:-0}"
X
chmod +x "$fake"
export FAKE_LOG=$dir/calls SABHA_PRUNE_CMD=$fake
P() { "$BIN/sabha-prune" "$@"; }
reset() { rm -rf "$out"; : >"$FAKE_LOG"; }

reset
P --out "$out" --date 2026-11-09 >"$dir/o1" 2>&1
check "report file written, named by the date" '[[ -f $out/2026-11-09.md ]] && grep -q "^wrote " "$dir/o1"'
check "both candidate lines listed with their count" 'grep -q "^## Candidates (2)" "$out/2026-11-09.md" && grep -q "^- WORKTREE SAFE worktrees/a/repo--one" "$out/2026-11-09.md" && grep -q "^- UNPUSHED " "$out/2026-11-09.md"'
check "the inventory got --actions and nothing else, never --apply" '[[ $(cat "$FAKE_LOG") == "--actions" ]] && ! grep -q -- "--apply" "$FAKE_LOG"'
check "the report says it changed nothing" 'grep -q "Nothing was archived or removed" "$out/2026-11-09.md"'

P --out "$out" --date 2026-11-09 >"$dir/o2" 2>&1
check "rerun with the same lines is unchanged" 'grep -q "^unchanged " "$dir/o2"'
FAKE_MODE=other P --out "$out" --date 2026-11-09 >"$dir/o3" 2>&1
check "same-day rerun with new lines replaces that day" 'grep -q "^updated " "$dir/o3" && grep -q "^- MAIN backend/repo" "$out/2026-11-09.md" && ! grep -q "UNPUSHED" "$out/2026-11-09.md"'
cp "$out/2026-11-09.md" "$dir/keep"
P --out "$out" --date 2026-11-10 >/dev/null 2>&1
check "another day writes its own file and leaves the first alone" 'cmp -s "$dir/keep" "$out/2026-11-09.md" && [[ -f $out/2026-11-10.md ]]'

reset
FAKE_MODE=nasty P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "control, bidi, NUL and bad bytes never reach the report" '[[ -f $out/2026-11-09.md ]] && ! LC_ALL=C grep -q "[^[:print:][:space:]]" "$out/2026-11-09.md" && ! LC_ALL=C grep -q "[^ -~]" "$out/2026-11-09.md"'
check "the text around the bad bytes survives" 'grep -q "^- WORKTREE UNIQUE caf" "$out/2026-11-09.md" && grep -q "^- last" "$out/2026-11-09.md"'

reset
FAKE_MODE=empty P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "an empty inventory is none (0)" 'grep -q "^## Candidates (0)" "$out/2026-11-09.md" && grep -q "^- none" "$out/2026-11-09.md"'
reset
FAKE_MODE=many P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "150 lines are capped at 100 with a count of the rest" '[[ $(grep -c "^- row " "$out/2026-11-09.md") == 100 ]] && grep -q "^- and 50 more" "$out/2026-11-09.md"'
reset
FAKE_MODE=long P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "a 5000 byte line is cut" '[[ $(awk "{ if (length(\$0) > m) m = length(\$0) } END { print m }" "$out/2026-11-09.md") -le 205 ]]'
reset
FAKE_MODE=huge P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "a 2.5 MB inventory is read to a cap and handled" '[[ -f $out/2026-11-09.md ]] && [[ $(wc -c <"$out/2026-11-09.md") -lt 2000 ]]'

reset
P --out "$out" --date 2026-11-09 >/dev/null 2>&1
cp "$out/2026-11-09.md" "$dir/keep"
FAKE_MODE=other FAKE_RC=3 P --out "$out" --date 2026-11-09 >"$dir/o4" 2>&1; rc=$?
check "a failing inventory exits 1 and says could not read" '[[ $rc == 1 ]] && grep -q "could not read the inventory" "$dir/o4"'
check "a failing inventory leaves the stored report as it was" 'cmp -s "$dir/keep" "$out/2026-11-09.md"'
reset
FAKE_RC=3 P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "a failing first run writes no file at all" '[[ ! -e $out/2026-11-09.md ]]'
( SABHA_PRUNE_CMD=$dir/missing.sh P --out "$out" >/dev/null 2>&1 ); rc=$?
check "a missing inventory script exits 1" '[[ $rc == 1 ]]'
printf '#!/bin/sh\nexit 0\n' >"$dir/noexec.sh"; chmod 644 "$dir/noexec.sh"
( SABHA_PRUNE_CMD=$dir/noexec.sh P --out "$out" >/dev/null 2>&1 ); rc=$?
check "a script that is not executable exits 1" '[[ $rc == 1 ]]'
( unset SABHA_PRUNE_CMD; P --out "$out" >/dev/null 2>&1 ); rc=$?
check "no SABHA_PRUNE_CMD exits 1" '[[ $rc == 1 ]]'

P --out >/dev/null 2>&1; r1=$?
P --date >/dev/null 2>&1; r2=$?
P --date 2026-13-45 >/dev/null 2>&1; r3=$?
P --date notadate >/dev/null 2>&1; r4=$?
P --bogus >/dev/null 2>&1; r5=$?
P --out --stdout >/dev/null 2>&1; r6=$?
P --date --out x >/dev/null 2>&1; r7=$?
check "six usage errors and a bare option exit 2" '[[ $r1$r2$r3$r4$r5$r6$r7 == 2222222 ]]'

reset
P --stdout --date 2026-11-09 >"$dir/o5" 2>&1
check "--stdout prints the report and writes nothing" 'grep -q "^# Worktree prune candidates 2026-11-09" "$dir/o5" && [[ ! -e $out ]]'

reset
mkdir -p "$out/.prune.lock"
P --out "$out" --date 2026-11-09 >/dev/null 2>&1; rc=$?
check "a fresh lock blocks a second run" '[[ $rc == 1 && ! -e $out/2026-11-09.md ]]'
touch -t 202001010000 "$out/.prune.lock"
P --out "$out" --date 2026-11-09 >/dev/null 2>&1; rc=$?
check "a stale lock is reaped and the run goes through" '[[ $rc == 0 && -f $out/2026-11-09.md ]]'
check "the lock is released on exit" '[[ ! -e $out/.prune.lock ]]'
reset
FAKE_RC=3 P --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "the temp folder is gone after a failure" '! ls "${TMPDIR:-/tmp}" 2>/dev/null | grep -q "^sabha-prune\.[A-Za-z0-9]*$" || true'

reset
mkdir -p "$out/2026-11-09.md"
P --out "$out" --date 2026-11-09 >/dev/null 2>&1; rc=$?
check "a directory in the report slot is refused" '[[ $rc == 1 && -d $out/2026-11-09.md ]]'
rm -rf "$out"; mkdir -p "$out"; : >"$dir/victim"; ln -s "$dir/victim" "$out/2026-11-09.md"
P --out "$out" --date 2026-11-09 >/dev/null 2>&1; rc=$?
check "a symlink in the report slot is refused and its target untouched" '[[ $rc == 1 && ! -s $dir/victim ]]'

home=$dir/home; mkdir -p "$home"
( HOME=$home SABHA_PRUNE_DIR='$HOME/reports' P --date 2026-11-09 >/dev/null 2>&1 )
check "\$HOME in SABHA_PRUNE_DIR is expanded" '[[ -f $home/reports/2026-11-09.md ]]'
tilde='~'
( HOME=$home SABHA_PRUNE_DIR=$tilde/rep2 P --date 2026-11-09 >/dev/null 2>&1 )
check "a leading ~ in SABHA_PRUNE_DIR is expanded" '[[ -f $home/rep2/2026-11-09.md ]]'
( SABHA_PRUNE_DIR='' P --date 2026-11-09 >/dev/null 2>&1 )
check "the default folder is SABHA_IMPL/prune" '[[ -f $impl/prune/2026-11-09.md ]]'

reset
"$BIN/sabha" prune --out "$out" --date 2026-11-09 >/dev/null 2>&1
check "bin/sabha prune is the front door" '[[ -f $out/2026-11-09.md ]]'

check "the changed files are pure ASCII" '! LC_ALL=C grep -q "[^ -~	]" "$BIN/sabha-prune" "$BIN/../tests/test-prune.sh"'
check "bash -n is clean" 'bash -n "$BIN/sabha-prune" && bash -n "$BIN/../tests/test-prune.sh"'

echo
((fails == 0)) && echo "all ok" || echo "$fails FAILED"
exit $((fails > 0))
