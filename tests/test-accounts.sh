#!/usr/bin/env bash
# Roles on different Claude accounts (SABHA_ACCOUNT_<Role>, CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_<NAME>) with a fake claude on
# PATH and a fake env file of obviously fake tokens: each role's claude gets its own account's token and no other, the
# default login gets none, a missing token refuses with the variable's name, --print / check / logs never hold a token
# value, and with no accounts configured nothing changes. No real claude, herdr or token is used.
# Run: tests/test-accounts.sh (about 10 s)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-accounts.XXXXXX") || exit 1
dir=$(cd "$dir" && pwd)
lp=""
trap '[[ -n $lp ]] && kill -TERM "$lp" 2>/dev/null; rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
unset SABHA_CONF SABHA_IMPL SABHA_WS SABHA_PLAN SABHA_PANES SABHA_STOP SABHA_ACCOUNTS SABHA_ENV_FILE SABHA_MODEL SABHA_CHROME
unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_HV

mkdir -p "$dir/bin" "$dir/ws" "$dir/impl/status/context" "$dir/impl/inbox/BuilderHeavy" "$dir/impl/inbox/Writer"
# the fake claude reports which account's token it got (it compares, it never prints the value) and how many other
# accounts' variables it can still see
cat >"$dir/bin/claude" <<'FAKE'
#!/bin/bash
t=${CLAUDE_CODE_OAUTH_TOKEN-unset}
case $t in fake-token-AAAA) v=AU ;; fake-token-BBBB) v=HV ;; fake-token-ENVV) v=ENV ;; fake-token-INHERIT) v=INHERIT ;; unset) v=none ;; *) v=other ;; esac
n=$(env | grep -c '^CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_')
echo "token=$v accountvars=$n args: $*" >>"$FAKE_OUT"
if [ -n "${FAKE_STAY:-}" ]; then trap 'exit 0' TERM; sleep 25 & wait; fi
FAKE
chmod +x "$dir/bin/claude"
# a decoy variable with the same prefix, an unrelated secret, and a line that would run if the file were sourced
printf 'OTHER_SECRET=fake-secret-ZZZZ\r\nCLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AUX=fake-token-DECOY\r\nX=$(touch "%s/pwned")\r\nexport CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_HV='"'"'fake-token-BBBB'"'"'\r\nCLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU="fake-token-AAAA"\r\nCLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_EMPTY=\r\n' "$dir" >"$dir/fake.env"
: >"$dir/ps.txt"
roster='Relay:opus:medium BuilderHeavy:opus:high BuilderPrecise:sonnet:medium Writer:sonnet:low Runner:sonnet:low Oc:opencode:medium'
base() { printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="%s"\nSABHA_NOTIFY_DESKTOP=0\nSABHA_KEEP_AWAKE=off\n' "$dir/ws" "$dir/impl" "$roster"; }
{ base; printf 'SABHA_ACCOUNTS="HV AU EMPTY NOTOK"\nSABHA_ENV_FILE=%s\nSABHA_ACCOUNT_BuilderHeavy=AU\nSABHA_ACCOUNT_BuilderPrecise=HV\nSABHA_ACCOUNT_Runner=NOTOK\nSABHA_ACCOUNT_Oc=AU\n' "$dir/fake.env"; } >"$dir/acc.conf"
base >"$dir/plain.conf"
export SABHA_NOTIFY_DESKTOP=0 SABHA_PS_FILE=$dir/ps.txt FAKE_OUT=$dir/claude.out SABHA_LOOP_INTERVAL=1 SABHA_LOOP_MIN_UP=3 SABHA_LOOP_GRACE=2
P=$dir/bin:$PATH
# run <conf> <env assignments...> -- <command...>: output to $dir/out, status in $rc
run() { local c=$1; shift; env SABHA_CONF="$dir/$c.conf" PATH="$P" "$@" >"$dir/out" 2>&1; rc=$?; }
last() { tail -1 "$dir/claude.out" 2>/dev/null; }

# 1. each role gets its own account's token; the default login gets none; the other accounts' variables are gone
: >"$dir/claude.out"
run acc "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "a role on AU gets AU's token (file: quotes and CR stripped) and no account variables" '(( rc == 0 )) && [[ $(last) == "token=AU accountvars=0 args: -n BuilderHeavy "* ]]'
run acc "$SH" "$BIN/sabha-up.sh" BuilderPrecise
check "a role on HV gets HV's token (export line, single quotes)" '(( rc == 0 )) && [[ $(last) == "token=HV accountvars=0 "* ]]'
run acc CLAUDE_CODE_OAUTH_TOKEN=fake-token-INHERIT "$SH" "$BIN/sabha-up.sh" Writer
check "a role with no account gets the default login: an inherited token is dropped" '(( rc == 0 )) && [[ $(last) == "token=none "* ]]'
run acc CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU=fake-token-ENVV "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "the environment wins over the env file" '(( rc == 0 )) && [[ $(last) == "token=ENV "* ]]'
check "the env file is parsed, never sourced" '[[ ! -e $dir/pwned ]]'
check "a decoy with the same prefix is not matched (AU is not AUX)" '! grep -q "token=other" "$dir/claude.out"'
run acc "$SH" "$BIN/sabha-up.sh" BuilderPrecise-2
check "a copy follows its base role's account" '(( rc == 0 )) && [[ $(last) == "token=HV "* ]]'

# 2. no accounts configured: nothing changes (an inherited token reaches claude, no account lookup, no extra output)
run plain CLAUDE_CODE_OAUTH_TOKEN=fake-token-INHERIT "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "no accounts configured: the inherited token is left alone" '(( rc == 0 )) && [[ $(last) == "token=INHERIT "* ]]'
run plain "$SH" "$BIN/sabha-up.sh" --print BuilderHeavy
check "no accounts configured: --print is the old line" '[[ $(head -1 "$dir/out") == "cd \"$dir/ws\" && claude -n BuilderHeavy --model opus --effort high --strict-mcp-config \""* ]]'

# 3. a named account without a token refuses; the message names the variable and nothing is started
: >"$dir/claude.out"
run acc "$SH" "$BIN/sabha-up.sh" Runner
check "missing token: sabha-up refuses, naming the variable" '(( rc != 0 )) && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_NOTOK" "$dir/out" && grep -q "not starting it" "$dir/out"'
check "...and starts no claude, no other account" '[[ ! -s $dir/claude.out ]]'
run acc CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU=fake-token-ENVV "$SH" "$BIN/sabha-up.sh" Runner
check "...even with another account's token in the environment" '(( rc != 0 )) && [[ ! -s $dir/claude.out ]]'
{ base; printf 'SABHA_ACCOUNTS="EMPTY"\nSABHA_ENV_FILE=%s\nSABHA_ACCOUNT_Runner=EMPTY\n' "$dir/fake.env"; } >"$dir/empty.conf"
run empty "$SH" "$BIN/sabha-up.sh" Runner
check "an empty value counts as missing" '(( rc != 0 )) && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_EMPTY" "$dir/out"'
{ base; printf 'SABHA_ACCOUNTS="HV"\nSABHA_ENV_FILE=%s\nSABHA_ACCOUNT_Runner=AU\n' "$dir/fake.env"; } >"$dir/notlisted.conf"
run notlisted "$SH" "$BIN/sabha-up.sh" Runner
check "an account not in SABHA_ACCOUNTS is refused" '(( rc != 0 )) && grep -q "not in SABHA_ACCOUNTS" "$dir/out" && [[ ! -s $dir/claude.out ]]'
{ base; printf 'SABHA_ENV_FILE=%s\nSABHA_ACCOUNT_Runner=fake-token-AAAA\n' "$dir/fake.env"; } >"$dir/badname.conf"
run badname "$SH" "$BIN/sabha-up.sh" Runner
check "a token pasted as the account name is refused and not echoed" '(( rc != 0 )) && grep -q "not an account name" "$dir/out" && ! grep -q "fake-token" "$dir/out"'
{ base; printf 'SABHA_ENV_FILE=\nSABHA_ACCOUNT_BuilderHeavy=AU\n'; } >"$dir/noenvfile.conf"
run noenvfile "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "SABHA_ENV_FILE empty = environment only: the file is not read" '(( rc != 0 )) && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU" "$dir/out"'
# the default env file is $SABHA_WS/.env
cp "$dir/fake.env" "$dir/ws/.env"
{ base; printf 'SABHA_ACCOUNT_BuilderHeavy=AU\n'; } >"$dir/wsenv.conf"
run wsenv "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "the default env file is \$SABHA_WS/.env" '(( rc == 0 )) && [[ $(last) == "token=AU "* ]]'
rm -f "$dir/ws/.env"

# 4. --print never holds a token value; it reads the variable when pasted and stops when it is unset
run acc "$SH" "$BIN/sabha-up.sh" --print BuilderHeavy
check "--print: the line names the variable, holds no value" 'grep -qF "CLAUDE_CODE_OAUTH_TOKEN=\"\${CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU:?}\" claude -n BuilderHeavy" "$dir/out" && ! grep -q "fake-token" "$dir/out"'
run acc "$SH" "$BIN/sabha-up.sh" --print Writer
check "--print: a default-login role has no token prefix" '! grep -q "CLAUDE_CODE_OAUTH_TOKEN" "$dir/out"'
: >"$dir/claude.out"
run acc "$SH" "$BIN/sabha-up.sh" --print BuilderHeavy; line=$(head -1 "$dir/out")
env -u CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU PATH="$P" FAKE_OUT="$dir/claude.out" bash -c "$line" >"$dir/out" 2>&1
check "--print: pasted with the variable unset it stops, no claude" '[[ ! -s $dir/claude.out ]] && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU" "$dir/out"'
CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_AU=fake-token-AAAA PATH="$P" FAKE_OUT="$dir/claude.out" bash -c "$line" >"$dir/out" 2>&1
check "--print: pasted with the variable set it starts on that account" '[[ $(last) == "token=AU "* ]]'

# 5. chrome and the model override
run acc "$SH" "$BIN/sabha-up.sh" --chrome --print Writer
check "--chrome adds --chrome to the claude line" 'grep -q "claude -n Writer --model sonnet --effort low --strict-mcp-config --chrome \"" "$dir/out"'
run acc SABHA_CHROME=1 SABHA_MODEL=opus "$SH" "$BIN/sabha-up.sh" --print Writer
check "SABHA_CHROME=1 and SABHA_MODEL=opus: --chrome and the replaced model" 'grep -q "claude -n Writer --model opus --effort low --strict-mcp-config --chrome \"" "$dir/out"'
run acc SABHA_MODEL='opus;x' "$SH" "$BIN/sabha-up.sh" --print Writer
check "a SABHA_MODEL with a shell character is refused" '(( rc != 0 ))'
: >"$dir/claude.out"
run acc "$SH" "$BIN/sabha-up.sh" --chrome BuilderHeavy
check "--chrome reaches the started claude, on the role's account" '(( rc == 0 )) && [[ $(last) == "token=AU accountvars=0 args: -n BuilderHeavy --model opus --effort high --strict-mcp-config --chrome "* ]]'
run plain "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "no --chrome by default" '(( rc == 0 )) && [[ $(last) != *--chrome* ]]'

# 6. the per-account stop line: SABHA_STOP_AU lets AU start where the shared SABHA_STOP holds HV back
printf 'five_hour 92 %s %s\n' $(( $(date +%s) + 3600 )) "$(date +%s)" >"$dir/impl/status/limits.txt"
{ cat "$dir/acc.conf"; printf 'SABHA_STOP=90\nSABHA_STOP_AU=95\n'; } >"$dir/stop.conf"
: >"$dir/claude.out"
run stop "$SH" "$BIN/sabha-up.sh" BuilderPrecise
check "HV at 92% is held by SABHA_STOP=90" '(( rc == 3 )) && grep -q "SABHA_STOP: five-hour at 92%" "$dir/out" && [[ ! -s $dir/claude.out ]]'
run stop "$SH" "$BIN/sabha-up.sh" BuilderHeavy
check "AU at 92% starts under SABHA_STOP_AU=95" '(( rc == 0 )) && [[ $(last) == "token=AU "* ]]'
rm -f "$dir/impl/status/limits.txt"

# 7. the loop: every start of a role gets the role's account; a missing token ends it at once
wait_for() { local i; for (( i = 0; i < $3; i++ )); do grep -Eq "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }
loop_role() {
  : >"$dir/claude.out"
  SABHA_CONF=$dir/$1.conf PATH=$P FAKE_STAY=1 "$SH" "$BIN/sabha-loop" "$2" >"$dir/loop.out" 2>&1 &
  lp=$!
  wait_for "$dir/claude.out" 'token=' 15
  kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""
}
loop_role acc BuilderHeavy
check "sabha-loop starts BuilderHeavy on AU's token (loop -> sabha-up.sh -> claude)" '[[ $(head -1 "$dir/claude.out") == "token=AU accountvars=0 args: -n BuilderHeavy "* ]]'
loop_role acc Writer
check "sabha-loop starts a default-login role with no token" '[[ $(head -1 "$dir/claude.out") == "token=none "* ]]'
: >"$dir/claude.out"
SABHA_CONF=$dir/acc.conf PATH=$P "$SH" "$BIN/sabha-loop" Runner >"$dir/loop.out" 2>&1; rc=$?
check "sabha-loop refuses a role whose token is missing, naming the variable (exit 2)" '(( rc == 2 )) && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_NOTOK" "$dir/loop.out" && [[ ! -s $dir/claude.out ]]'
# the loop's own stop line: the log says which window held it, and the role's account decides the line
printf 'five_hour 92 %s %s\n' $(( $(date +%s) + 3600 )) "$(date +%s)" >"$dir/impl/status/limits.txt"
: >"$dir/claude.out"
SABHA_CONF=$dir/stop.conf PATH=$P FAKE_STAY=1 "$SH" "$BIN/sabha-loop" BuilderPrecise >"$dir/loop.out" 2>&1 &
lp=$!
wait_for "$dir/loop.out" 'SABHA_STOP: five-hour at 92% \(>= 90%\)' 10
kill -TERM "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; lp=""
check "sabha-loop on HV holds at SABHA_STOP=90 and starts nothing" 'grep -q "(>= 90%)" "$dir/loop.out" && [[ ! -s $dir/claude.out ]]'
loop_role stop BuilderHeavy
check "sabha-loop on AU starts at 92% under SABHA_STOP_AU=95" '[[ $(head -1 "$dir/claude.out") == "token=AU "* ]]'
rm -f "$dir/impl/status/limits.txt"

# 8. sabha-check: names only; MISSING warns and fails; roles without an account say so; no accounts, no section
run acc "$SH" "$BIN/sabha-check"
check "check: one line per role, names and present|MISSING only" 'grep -q "^BuilderHeavy -> account AU (token variable present)$" "$dir/out" && grep -q "^BuilderPrecise -> account HV (token variable present)$" "$dir/out" && grep -q "^Runner -> account NOTOK (token variable MISSING)$" "$dir/out" && grep -q "^Writer -> default login$" "$dir/out" && grep -q "^Oc -> not a claude role (opencode)$" "$dir/out"'
check "check: a named account without a token variable warns and exits 1" '(( rc == 1 )) && grep -q "^WARN: .*CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_<NAME>" "$dir/out"'
run plain "$SH" "$BIN/sabha-check"
check "check: no accounts configured prints no account lines and exits 0" '(( rc == 0 )) && ! grep -q -- " -> " "$dir/out"'

# 8b. the grid: a pane role with no token refuses before any pane opens; otherwise the panes run sabha-loop (which applies
# the account itself), so the pane command carries the env file's path and no token
{ cat "$dir/acc.conf"; printf 'SABHA_PANES="Relay BuilderHeavy Runner"\n'; } >"$dir/gridbad.conf"
{ cat "$dir/acc.conf"; printf 'SABHA_PANES="Relay BuilderHeavy BuilderPrecise"\n'; } >"$dir/gridok.conf"
: >"$FAKE_HERDR_LOG"
run gridbad SABHA_ATTACH=0 "$SH" "$BIN/sabha-up.sh"
check "grid: a pane role with no token refuses before the workspace is created" '(( rc != 0 )) && grep -q "CLAUDE_CODE_OAUTH_TOKEN_ACCOUNT_NOTOK" "$dir/out" && ! grep -q "^workspace create" "$FAKE_HERDR_LOG"'
: >"$FAKE_HERDR_LOG"
run gridok SABHA_ATTACH=0 "$SH" "$BIN/sabha-up.sh"
check "grid: panes run sabha-loop with the env file path, no token in any herdr call" '(( rc == 0 )) && grep -q "^pane run .*sabha-loop. BuilderHeavy" "$FAKE_HERDR_LOG" && grep -q "SABHA_ENV_FILE=" "$FAKE_HERDR_LOG" && ! grep -q "fake-token" "$FAKE_HERDR_LOG"'

# 9. leak test: no fake token value in any output, log, status or cost file the run left behind (the fake env file and
# the fake claude, which hold the values by design, and the test's own *.conf inputs are the only exceptions)
run acc "$SH" "$BIN/sabha-up.sh" --print BuilderHeavy
leaks=$(grep -rlE 'fake-token-|fake-secret-' "$dir" --exclude=fake.env --exclude=claude --exclude='*.conf' 2>/dev/null)
check "leak: no fake token or secret in anything the run wrote ($(find "$dir" -type f | wc -l | tr -d ' ') files scanned)${leaks:+ [$leaks]}" '[[ -z $leaks ]]'
check "leak: the leak scan can see a value (a planted copy is found)" 'printf "fake-token-AAAA" >"$dir/planted.txt"; grep -rlE "fake-token-" "$dir" --exclude=fake.env --exclude=claude --exclude="*.conf" | grep -q planted'

if (( fails )); then echo "$fails check(s) failed"; exit 1; fi
echo "all ok"
