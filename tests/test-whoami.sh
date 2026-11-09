#!/usr/bin/env bash
# sabha whoami against a fake process list (SABHA_PS_FILE): the one line, the session id the SessionStart hook wrote,
# one copy -> exit 0, two copies -> WARN and exit 3, an unreadable list -> "unknown", never a guess.
# Run: tests/test-whoami.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-whoami.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
unset HERDR_PANE_ID TMUX_PANE
impl=$dir/impl
mkdir -p "$impl/status/whoami" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="%s"\n' "$dir/ws" "$impl" \
  "Relay:claude:opus Dispatcher:claude:opus BuilderHeavy:claude:opus" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf
ps1=$dir/ps-one ps2=$dir/ps-two
{ echo "  101 ttys001 Sat Nov  8 19:00:00 2026 /usr/local/bin/claude -n Relay --model opus"
  echo "  102 ttys002 Sat Nov  8 19:00:05 2026 /usr/local/bin/claude --name Dispatcher"
  echo "  103 ttys003 Sat Nov  8 19:00:09 2026 /bin/zsh -l"; } >"$ps1"
{ cat "$ps1"; echo "  104 ttys004 Sat Nov  8 19:30:00 2026 /usr/local/bin/claude --name=Relay"; } >"$ps2"
printf 'session_id=sess-1234\ncwd=/somewhere\n' >"$impl/status/whoami/Relay.txt"

fail() { echo "FAIL: $*"; exit 1; }
run() { out=$(cd "$dir/ws" && bash "$BIN/sabha" whoami "$@" 2>"$dir/err"); rc=$?; err=$(cat "$dir/err"); }

SABHA_PS_FILE=$ps1 run Relay
[[ $rc == 0 ]] || fail "one copy rc $rc: $out $err"
[[ $out == "role: Relay | session: sess-1234 | cwd: $dir/ws | conf: $dir/sabha.conf | impl: $impl | pane: - | live copies: 1" ]] ||
  fail "line: $out"

SABHA_PS_FILE=$ps2 run Relay
[[ $rc == 3 ]] || fail "two copies must exit 3, got $rc"
[[ $out == *"live copies: 2"* && $out == *"WARN duplicate: 2 live sessions are named Relay"* ]] || fail "duplicate: $out"

SABHA_PS_FILE=$ps1 run Dispatcher
[[ $rc == 0 && $out == *"role: Dispatcher | session: unknown |"* && $out == *"live copies: 1" ]] || fail "no whoami file: $out"

SABHA_PS_FILE=$ps1 run BuilderHeavy
[[ $rc == 0 && $out == *"live copies: 0" ]] || fail "zero copies: $rc $out"

SABHA_PS_FILE=$dir/missing run Relay
[[ $rc == 0 && $out == *"live copies: unknown" && $out != *WARN* ]] || fail "unreadable ps: $rc $out"

SABHA_ROLE=Relay SABHA_PS_FILE=$ps1 run
[[ $rc == 0 && $out == "role: Relay |"* ]] || fail "SABHA_ROLE: $rc $out"

HERDR_PANE_ID=p-7 SABHA_PS_FILE=$ps1 run Relay
[[ $out == *"| pane: p-7 |"* ]] || fail "herdr pane: $out"
TMUX_PANE=%3 SABHA_PS_FILE=$ps1 run Relay
[[ $out == *"| pane: %3 |"* ]] || fail "tmux pane: $out"

SABHA_PS_FILE=$ps1 run
[[ $rc == 2 && $err == *usage* ]] || fail "no role must exit 2: $rc $err"
SABHA_PS_FILE=$ps1 run '../x'
[[ $rc == 1 && $err == *"bad role name"* ]] || fail "bad name: $rc $err"

echo "ok: whoami prints one line, reads the hook's session id, warns and exits 3 on a duplicate name"
