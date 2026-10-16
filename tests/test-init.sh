#!/usr/bin/env bash
# bin/sabha init with fake CLIs on PATH: the plan, tracker and push choices land in sabha.conf, a random ntfy topic is
# generated only for push=ntfy, an existing conf is not replaced without --force, a conf that git would track is
# refused, a bad plan fails. No Claude runs. Run: tests/test-init.sh   (works under bash 3.2 and 5)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-init.XXXXXX") || exit 1
trap 'rm -rf "$dir"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$dir/fakebin" "$dir/sysbin"
for c in grep sed head tr uname dirname git mktemp date awk cat sh env rm mkdir; do p=$(command -v $c) && ln -sf "$p" "$dir/sysbin/$c"; done
for c in claude opencode; do printf '#!/bin/sh\nexit 0\n' >"$dir/fakebin/$c"; chmod +x "$dir/fakebin/$c"; done
P="$dir/fakebin:$dir/sysbin"
S() { PATH=$P "${BASH:-bash}" "$ROOT/bin/sabha" "$@"; }

out=$dir/a.conf
res=$(S init --plan max5 --tracker html --push ntfy --ws /w --impl /w/impl --out "$out" </dev/null) || fail "init failed: $res"
grep -qx 'SABHA_PLAN=max5' "$out" || fail "plan missing"
grep -qx 'SABHA_TRACKER=html' "$out" || fail "tracker missing"
grep -qx 'SABHA_PUSH=ntfy' "$out" || fail "push missing"
grep -qx 'SABHA_WS=/w' "$out" || fail "ws not set"
grep -q 'agent CLIs found: claude opencode\.' "$out" || fail "detected CLIs wrong: $(grep 'CLIs found' "$out")"
t=$(sed -n 's/^SABHA_NTFY_TOPIC=//p' "$out")
[[ $t =~ ^sabha-[a-z0-9]{20}$ ]] || fail "topic should be sabha-<20 random chars>, got '$t'"
case $res in *"better option"*) ;; *) fail "html default must point at the Google Sheet" ;; esac

S init --plan pro --push ntfy --out "$dir/b.conf" </dev/null >/dev/null || fail "second init failed"
t2=$(sed -n 's/^SABHA_NTFY_TOPIC=//p' "$dir/b.conf")
[[ -n $t2 && $t2 != "$t" ]] || fail "topics must differ between runs"

S init --out "$dir/c.conf" </dev/null >/dev/null || fail "defaults init failed"
grep -qx 'SABHA_PLAN=pro' "$dir/c.conf" && grep -qx 'SABHA_TRACKER=html' "$dir/c.conf" && grep -qx 'SABHA_PUSH=off' "$dir/c.conf" || fail "defaults should be pro, html, off"
grep -q '^SABHA_NTFY_TOPIC=' "$dir/c.conf" && fail "no topic without ntfy"

S init --out "$out" </dev/null >/dev/null 2>&1 && fail "existing conf must not be replaced"
S init --force --out "$out" </dev/null >/dev/null || fail "--force should replace"
S init --plan gold --out "$dir/d.conf" </dev/null >/dev/null 2>&1 && fail "bad plan must fail"
[[ -e $dir/d.conf ]] && fail "bad plan wrote a file"

git init -q "$dir/repo" 2>/dev/null && {
  S init --push ntfy --out "$dir/repo/sabha.conf" </dev/null >/dev/null 2>&1 && fail "a conf git would track must be refused"
  [[ -e $dir/repo/sabha.conf ]] && fail "refused conf was written"
  echo sabha.conf >"$dir/repo/.gitignore"
  S init --out "$dir/repo/sabha.conf" </dev/null >/dev/null || fail "ignored path should be accepted"
}
echo "ok: init writes plan, tracker, push, detected CLIs; random ntfy topic only for ntfy; no overwrite, no tracked path, bad plan fails"
