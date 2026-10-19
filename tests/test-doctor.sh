#!/usr/bin/env bash
# bin/sabha doctor with fake CLIs on PATH: all present = rc 0; a missing claude, jq, git or python3 = FAIL rc 1; missing herdr,
# statusline hook, optional CLIs = warn only; the Team/Enterprise Remote Control note is a warning and never fails the
# run; the bash version line names what works. No Claude runs. Run: tests/test-doctor.sh   (bash 3.2 and 5)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-doctor.XXXXXX") || exit 1
dir=$(cd "$dir" && pwd)   # $TMPDIR may end in a slash; $PWD never does
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
JQ=$(command -v jq) || fail "jq is needed to run this test"
mkdir -p "$dir/fakebin" "$dir/sysbin" "$dir/impl/status"
for c in grep sed head tr uname dirname git mktemp date awk cat sh env rm mkdir; do p=$(command -v $c) && ln -sf "$p" "$dir/sysbin/$c"; done
ln -s "$JQ" "$dir/fakebin/jq"
mk() { printf '#!/bin/sh\n%s\n' "${2:-exit 0}" >"$dir/fakebin/$1"; chmod +x "$dir/fakebin/$1"; }
mk claude 'echo "Logged in: personal, plan Max"'; mk python3; mk herdr; mk opencode; mk codex; mk agy
echo "SABHA_WS=$dir
SABHA_IMPL=$dir/impl" >"$dir/sabha.conf"
echo '{"statusLine":{"type":"command","command":"bash /x/bin/statusline-sabha.sh"}}' >"$dir/settings.json"
# Git Bash: a copied tool cannot load msys-2.0.dll, so /usr/bin goes first (it holds no git and no agent CLI)
SB=$dir/sysbin
case $(uname -s) in MINGW*|MSYS*) SB=/usr/bin:$dir/sysbin ;; esac
# DC: the claude-sabha copies doctor looks for besides this one (SABHA_DOCTOR_COPIES, empty = none, so the real ones on this machine never count)
DC=""
D() { PATH="$dir/fakebin:$SB" SABHA_CONF=$dir/sabha.conf SABHA_SETTINGS=$dir/settings.json SABHA_DOCTOR_COPIES=$DC "${BASH:-bash}" "$ROOT/bin/sabha" doctor 2>&1; }

o=$(D); rc=$?
[[ $rc -eq 0 ]] || fail "healthy machine should pass, rc=$rc: $o"
echo "$o" | grep -q '^doctor: 0 fail, 0 warn' || fail "healthy machine should have no warnings: $o"
echo "$o" | grep -q "bash ${BASH_VERSION:-?}" || fail "bash version line missing"
case ${BASH_VERSION%%.*} in 3) echo "$o" | grep -q 'written for 3.2' || fail "3.2 note missing" ;; esac

rm "$dir/fakebin/claude"; o=$(D); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q '^FAIL  claude' || fail "missing claude must FAIL with rc 1: rc=$rc"
mk claude 'echo "Logged in: personal, plan Max"'

rm "$dir/fakebin/jq"; o=$(D); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q '^FAIL  jq' || fail "missing jq must FAIL with rc 1: rc=$rc"
ln -s "$JQ" "$dir/fakebin/jq"

rm "$dir/fakebin/python3"; o=$(D); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q '^FAIL  python3' || fail "missing python3 must FAIL with rc 1: rc=$rc"
mk python3
rm "$dir/sysbin/git"; o=$(D); rc=$?
[[ $rc -eq 1 ]] && echo "$o" | grep -q '^FAIL  git' || fail "missing git must FAIL with rc 1: rc=$rc"
ln -sf "$(command -v git)" "$dir/sysbin/git"

rm "$dir/fakebin/herdr" "$dir/fakebin/codex" "$dir/fakebin/agy"; echo '{}' >"$dir/settings.json"
o=$(D); rc=$?
[[ $rc -eq 0 ]] || fail "herdr, codex, agy and the hook are warnings, rc=$rc"
echo "$o" | grep -q '^warn  herdr' && echo "$o" | grep -q '^warn  statusline hook' && echo "$o" | grep -q '^warn  codex' || fail "expected warnings: $o"
mk herdr; mk codex; mk agy; echo '{"statusLine":{"command":"bash /x/statusline-sabha.sh"}}' >"$dir/settings.json"

mk claude 'echo "Account: work (Claude Team)"'
o=$(D); rc=$?
[[ $rc -eq 0 ]] || fail "a Team seat must only warn, rc=$rc: $o"
echo "$o" | grep -q '^warn  Remote Control is blocked on Team/Enterprise' || fail "Team seat warning missing: $o"
mk claude 'echo "Logged in: personal, plan Max"'
o=$(D); echo "$o" | grep -q 'blocked on Team/Enterprise' && fail "a personal Max login must not get the Team warning"
o=$(SABHA_DOCTOR_SEAT=Enterprise D); rc=$?
[[ $rc -eq 0 ]] && echo "$o" | grep -q 'blocked on Team/Enterprise' || fail "SABHA_DOCTOR_SEAT=Enterprise must warn, rc 0"

echo "SABHA_IMPL=$dir/impl
SABHA_REMOTE=1" >>"$dir/sabha.conf"
o=$(D); rc=$?
[[ $rc -eq 0 ]] && echo "$o" | grep -q '^warn  SABHA_REMOTE=1' || fail "SABHA_REMOTE=1 on a personal seat should warn about org policy, rc 0"

# item 5: two copies, a stale statusline copy, a copy whose config belongs to another project: warnings only, nothing is touched
other=$dir/other-impl; mkdir -p "$other"
cp "$ROOT/bin/statusline-sabha.sh" "$dir/good-statusline-sabha.sh"
printf '#!/bin/bash\nCTX_DIR="/somewhere/else/status/context"\ninput=$(cat)\n' > "$dir/statusline-sabha.sh"
echo "{\"statusLine\":{\"type\":\"command\",\"command\":\"bash $dir/statusline-sabha.sh\"}}" >"$dir/settings.json"
o=$(D); rc=$?
[[ $rc -eq 0 ]] && echo "$o" | grep -q "^warn  statusLine runs $dir/statusline-sabha.sh, an old standalone copy" || fail "a statusline script with no sabha.conf lookup must WARN (rc 0): rc=$rc: $o"
[[ -f $dir/statusline-sabha.sh ]] || fail "doctor must never delete or move a copy"
mkdir -p "$dir/goodsl"; cp "$ROOT/bin/statusline-sabha.sh" "$dir/goodsl/statusline-sabha.sh"
echo "{\"statusLine\":{\"type\":\"command\",\"command\":\"bash $dir/goodsl/statusline-sabha.sh\"}}" >"$dir/settings.json"
o=$(D)
echo "$o" | grep -q 'old standalone copy' && fail "the repo's own statusline script must not be called stale: $o"
echo '{"statusLine":{"type":"command","command":"bash /x/bin/statusline-sabha.sh"}}' >"$dir/settings.json"
o=$(D)
echo "$o" | grep -q 'old standalone copy' && fail "a statusLine script that does not exist is not reported as a stale copy: $o"

mkdir -p "$dir/copy1/bin"; : > "$dir/copy1/bin/sabha-lib.sh"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\n' "$dir/otherws" "$other" > "$dir/copy1/sabha.conf"
DC="$dir/copy1"; o=$(D); rc=$?
[[ $rc -eq 0 ]] && echo "$o" | grep -q "^warn  a second claude-sabha copy at $dir/copy1 (this one is $ROOT)" || fail "a second copy must WARN (rc 0): rc=$rc: $o"
echo "$o" | grep -q "copy1.*sabha.conf names SABHA_IMPL=$other, not $dir/impl" || fail "the copy's own config pointing elsewhere must be named: $o"
[[ -d $dir/copy1 ]] || fail "doctor must never delete or move a copy"
DC="$ROOT"; o=$(D)
echo "$o" | grep -q 'second claude-sabha copy' && fail "this copy is not a second copy: $o"
DC="$dir/nothere"; o=$(D)
echo "$o" | grep -q 'second claude-sabha copy' && fail "a path with no scripts is not a copy: $o"
DC=""

# run from a copy whose own sabha.conf belongs to another project, in a directory outside it, with no .sabha/local above
mkdir -p "$dir/runcopy/bin" "$dir/elsewhere"; cp "$ROOT"/bin/sabha "$ROOT"/bin/sabha-lib.sh "$dir/runcopy/bin/"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\n' "$dir/otherws" "$other" > "$dir/runcopy/sabha.conf"
o=$(cd "$dir/elsewhere" && env -u SABHA_CONF PATH="$dir/fakebin:$SB" SABHA_SETTINGS=$dir/settings.json SABHA_DOCTOR_COPIES= "${BASH:-bash}" "$dir/runcopy/bin/sabha" doctor 2>&1); rc=$?
echo "$o" | grep -q "^warn  running from $dir/elsewhere with $dir/runcopy/sabha.conf, which belongs to another project (SABHA_WS=$dir/otherws)" || fail "a copy's own config used outside its workspace must WARN: $o"
[[ $rc -eq 0 ]] || fail "that warning must not fail doctor, rc=$rc"
o=$(cd "$dir/otherws" 2>/dev/null || mkdir -p "$dir/otherws"; cd "$dir/otherws" && env -u SABHA_CONF PATH="$dir/fakebin:$SB" SABHA_SETTINGS=$dir/settings.json SABHA_DOCTOR_COPIES= "${BASH:-bash}" "$dir/runcopy/bin/sabha" doctor 2>&1)
echo "$o" | grep -q 'belongs to another project' && fail "inside its own workspace the copy's config is the right one: $o"
# the active config is another project's and this copy's own sabha.conf names a different SABHA_IMPL
o=$(cd "$dir/elsewhere" && PATH="$dir/fakebin:$SB" SABHA_CONF=$dir/sabha.conf SABHA_SETTINGS=$dir/settings.json SABHA_DOCTOR_COPIES= "${BASH:-bash}" "$dir/runcopy/bin/sabha" doctor 2>&1)
echo "$o" | grep -q "^warn  this copy's own $dir/runcopy/sabha.conf names SABHA_IMPL=$other, but the active config $dir/sabha.conf names $dir/impl" || fail "a copy with its own config for another project must WARN when another config is active: $o"

rm "$dir/sabha.conf"; o=$(D); rc=$?
[[ $rc -eq 0 ]] && echo "$o" | grep -q '^warn  no config' || fail "no config is a warning"
echo "ok: doctor passes a healthy machine, FAILs on a missing claude, jq, git or python3, warns (rc 0) on herdr, hook, optional CLIs, Team/Enterprise and SABHA_REMOTE, a stale statusline copy, a second copy and a copy whose config is another project's"
