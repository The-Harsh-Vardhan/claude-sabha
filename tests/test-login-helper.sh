#!/usr/bin/env bash
# bin/sabha-login-helper with a stub browser (a sleep child): a fake successful login exits 0 with the session at mode
# 600 and no browser left, even one the script forgot to close; a login that never finishes exits 124 after the
# timeout with no process left; the session contents are never printed. Run: tests/test-login-helper.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-login.XXXXXX") || exit 1
trap 'for p in $(cat "$dir"/*.pid 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
alive() { kill -0 "$(cat "$1")" 2>/dev/null; }

# success: the stub "browser" is left running by the script, as login-once.mjs did on 4 Nov
cat >"$dir/ok.sh" <<'X'
sleep 300 & echo $! >"$1/browser-ok.pid"
echo 'secret-cookie-value' >"$1/state.json"
exit 0
X
o=$(bash "$BIN/sabha-login-helper" --session "$dir/state.json" --timeout 10 --pidfile "$dir/helper-ok.pid" -- bash "$dir/ok.sh" "$dir" 2>&1); rc=$?
[[ $rc -eq 0 ]] || fail "a fake successful login must exit 0, rc=$rc: $o"
alive "$dir/browser-ok.pid" && fail "the browser the script left open must be stopped"
[[ $(stat -f %Lp "$dir/state.json" 2>/dev/null || stat -c %a "$dir/state.json") == 600 ]] || fail "the session file must be mode 600"
case $o in *secret-cookie-value*) fail "the session contents must never be printed: $o" ;; esac
grep -q "pid $(cat "$dir/helper-ok.pid")" <<<"$o" || fail "the pid must be printed and match --pidfile: $o"

# timeout: the login never completes
cat >"$dir/hang.sh" <<'X'
sleep 300 & echo $! >"$1/browser-hang.pid"
sleep 300
X
o=$(bash "$BIN/sabha-login-helper" --session "$dir/none.json" --timeout 2 --pidfile "$dir/helper-hang.pid" -- bash "$dir/hang.sh" "$dir" 2>&1); rc=$?
[[ $rc -eq 124 ]] || fail "a login past the timeout must exit 124, rc=$rc: $o"
alive "$dir/browser-hang.pid" && fail "no browser may be left after the timeout"
alive "$dir/helper-hang.pid" && fail "no login script may be left after the timeout"

# the script exits 0 but saved nothing
o=$(bash "$BIN/sabha-login-helper" --session "$dir/empty.json" --timeout 5 -- true 2>&1); [[ $? -eq 1 ]] || fail "no session file must exit 1: $o"
echo "ok: login helper exits 0 with mode 600 and no browser left, 124 on timeout with nothing left, 1 without a session"
