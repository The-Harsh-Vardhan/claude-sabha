#!/usr/bin/env bash
# The herdr backend against a fake herdr on PATH (tests/fake-herdr.sh; no real herdr, no terminal): the default backend
# builds the workspace and tabs, runs Claude roles with sabha-up.sh and starts other agents with `herdr agent start
# --kind`; SABHA_BACKEND=iterm keeps the osascript path; sabha-nudge prompts the recorded pane with --wait; SABHA_REMOTE=1
# adds --remote-control; the Windows launchers and *.bak files are gone. Run: tests/test-herdr.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-herdr.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

mkdir -p "$dir/impl/status" "$dir/ws" "$dir/stubs" "$dir/fh"
cp "$ROOT/tests/fake-herdr.sh" "$dir/stubs/herdr"
printf '#!/bin/sh\necho "STUB claude $*"\n' > "$dir/stubs/claude"
printf '#!/bin/sh\necho "STUB osascript $*"; [ -t 0 ] || cat\n' > "$dir/stubs/osascript"
chmod +x "$dir/stubs/herdr" "$dir/stubs/claude" "$dir/stubs/osascript"
: > "$dir/ps.txt"
export SABHA_CONF=$dir/sabha.conf SABHA_PS_FILE=$dir/ps.txt FAKE_HERDR_LOG=$dir/herdr.log FAKE_HERDR_DIR=$dir/fh
export PATH=$dir/stubs:$PATH
unset SABHA_BACKEND SABHA_PLAN SABHA_PANES SABHA_REMOTE HERDR_ENV
{ echo "SABHA_WS=$dir/ws"; echo "SABHA_IMPL=$dir/impl"
  echo 'SABHA_ROSTER="V:opus:medium Y:opus:medium A:sonnet:low O:opencode:x:low C:codex:o3:low:gate G:sonnet:low:gate"'; } > "$dir/sabha.conf"
log() { cat "$FAKE_HERDR_LOG" 2>/dev/null; }

echo "--- grid"
out=$("$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "default backend is herdr: no osascript" '(( rc == 0 )) && ! grep -q "STUB osascript" <<<"$out"'
check "one workspace, a Gate tab" 'grep -q "^workspace create --cwd $dir/ws" "$FAKE_HERDR_LOG" && grep -q "^tab create --workspace w1 .*--label Gate" "$FAKE_HERDR_LOG"'
check "Build has Y A O: columns split right, rows down" '[[ $(grep -c "^pane split .*--direction right" "$FAKE_HERDR_LOG") -ge 1 ]] && grep -q "^pane split .*--direction down" "$FAKE_HERDR_LOG"'
check "a Claude role runs sabha-up.sh in its pane" 'grep -q "^pane run p[0-9]* .*sabha-up.sh. A$" "$FAKE_HERDR_LOG"'
check "opencode starts with agent start --kind" 'grep -q "^agent start o --kind opencode --pane p[0-9]*$" "$FAKE_HERDR_LOG"'
check "codex (UNTESTED kind) goes the same way, in the Gate tab" 'grep -q "^agent start c --kind codex --pane p[0-9]*$" "$FAKE_HERDR_LOG"'
check "the opening prompt is submitted without --wait" 'grep "^agent prompt o You are O" "$FAKE_HERDR_LOG" | grep -vq -- "--wait"'
check "pane ids are recorded for nudges" 'grep -q "^A p" "$dir/impl/status/herdr-panes.txt" && grep -q "^O p" "$dir/impl/status/herdr-panes.txt"'
check "attach hint printed" 'grep -q "herdr attach" <<<"$out"'

echo "--- iterm fallback"
: > "$FAKE_HERDR_LOG"
out=$(SABHA_BACKEND=iterm "$SH" "$BIN/sabha-up.sh" 2>&1)
check "SABHA_BACKEND=iterm uses osascript and never calls herdr" 'grep -q "STUB osascript" <<<"$out" && [[ ! -s $FAKE_HERDR_LOG ]]'

echo "--- single non-claude role"
: > "$FAKE_HERDR_LOG"
out=$("$SH" "$BIN/sabha-up.sh" O 2>&1); rc=$?
check "outside herdr it is refused with a hint" '(( rc == 1 )) && grep -q "starts inside a herdr pane" <<<"$out"'
out=$(HERDR_ENV=1 "$SH" "$BIN/sabha-up.sh" O 2>&1); rc=$?
check "inside herdr: split a sibling pane, agent start, prompt" '(( rc == 0 )) && grep -q "^pane split --current --direction right" "$FAKE_HERDR_LOG" && grep -q "^agent start o --kind opencode" "$FAKE_HERDR_LOG" && grep -q "^agent prompt o " "$FAKE_HERDR_LOG"'

echo "--- no herdr"
out=$(PATH=$dir/none:/usr/bin:/bin "$SH" "$BIN/sabha-up.sh" 2>&1); rc=$?
check "missing herdr: install hint, nothing opened" '(( rc == 1 )) && grep -q "herdr not found" <<<"$out"'

echo "--- nudge"
: > "$FAKE_HERDR_LOG"
out=$("$SH" "$BIN/sabha-nudge" A "read inbox/A/001.md" 2>&1); rc=$?
check "nudge prompts the recorded pane and waits" '(( rc == 0 )) && grep -q "^agent prompt p[0-9]* read inbox/A/001.md --wait --timeout 120000$" "$FAKE_HERDR_LOG"'
out=$("$SH" "$BIN/sabha-nudge" Zed "x" 2>&1)
check "an unrecorded role falls back to its lower-case agent name" 'grep -q "^agent prompt zed x --wait" "$FAKE_HERDR_LOG"'
FAKE_HERDR_FAIL_PROMPT=1 "$SH" "$BIN/sabha-nudge" A "x" >/dev/null 2>&1; rc=$?
check "a blocked agent fails the nudge (exit non-zero)" '(( rc != 0 ))'

echo "--- remote control"
out=$("$SH" "$BIN/sabha-up.sh" --print A)
check "default: no --remote-control" '! grep -q -- "--remote-control" <<<"$out"'
out=$(SABHA_REMOTE=1 "$SH" "$BIN/sabha-up.sh" --print A)
check "SABHA_REMOTE=1: --remote-control on the claude line" 'grep -q -- " --remote-control " <<<"$out"'
out=$(SABHA_REMOTE=1 "$SH" "$BIN/sabha-up.sh" A 2>&1)
check "SABHA_REMOTE=1: the started claude gets the flag" 'grep -q "STUB claude .*--remote-control" <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" A 2>&1)
check "default: the started claude has none" '! grep -q -- "--remote-control" <<<"$out"'

echo "--- cleanup"
check "Windows launchers deleted" '[[ ! -e $BIN/sabha-up.ps1 && ! -e $BIN/sabha-up.cmd ]]'
check "no *.bak in the tree" '[[ -z $(find "$ROOT" -name "*.bak" -not -path "*/.git/*" | head -1) ]]'

(( fails == 0 )) && echo "ok: all checks pass" || { echo "$fails check(s) failed"; exit 1; }
