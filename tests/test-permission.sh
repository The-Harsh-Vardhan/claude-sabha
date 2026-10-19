#!/usr/bin/env bash
# The permission relay: hooks/sabha-permission.sh (request file, nonce, wait, decision, log, nudge, ntfy body) and
# bin/sabha-perm (list, show, allow/deny/pane, audit, snippet). Fake herdr and a fake curl only; no claude, no network.
# Run: tests/test-permission.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
hook=$root/hooks/sabha-permission.sh
perm=$root/bin/sabha-perm
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-perm.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'kill $(jobs -p) 2>/dev/null; [[ -n ${KEEP:-} ]] && echo "kept $dir" || rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
unset SABHA_ROLE SABHA_IMPL SABHA_PLAN SABHA_ROSTER SABHA_PUSH SABHA_NTFY_TOPIC SABHA_PERMISSION_ALLOW SABHA_PERMISSION_MODE
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

impl=$dir/impl
P=$impl/inbox/Relay/permissions
mkdir -p "$impl/status" "$dir/ws" "$dir/stubs" "$dir/nojq"
# the grid writes this map; sabha_nudge stops (set -e) when it is missing
echo "Relay w1:p9" >"$impl/status/herdr-panes.txt"
cat >"$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$impl
SABHA_ROSTER="Relay:claude:opus Dispatcher:claude:opus BuilderHeavy:claude:opus"
EOF
export SABHA_CONF=$dir/sabha.conf SABHA_RELAY_WAIT=20
# a fake curl first on PATH: records its argv; the real one is never reached
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/curl.calls"\n' "$dir" >"$dir/stubs/curl"
chmod +x "$dir/stubs/curl"
PATH=$dir/stubs:$PATH
printf '#!/bin/sh\nexit 1\n' >"$dir/nojq/jq"; chmod +x "$dir/nojq/jq"

TI='{"command":"go test ./... && echo \"done\"","description":"Run the Go tests"}'
req_json() { printf '{"session_id":"s1","cwd":"/w/x","permission_mode":"%s","hook_event_name":"PermissionRequest","tool_name":"%s","tool_input":%s}' \
  "${2:-default}" "${3:-Bash}" "${1:-$TI}"; }
# hook_bg <name> <json>: runs the hook in the background as BuilderHeavy; out/<name>, rc/<name> when it ends
hook_bg() {
  ( printf '%s' "$2" | SABHA_ROLE=${ROLE:-BuilderHeavy} bash "$hook" >"$dir/out.$1" 2>"$dir/err.$1"; echo $? >"$dir/rc.$1" ) &
}
waitfor() { local i; for i in $(seq 1 100); do eval "$1" && return 0; sleep 0.1; done; return 1; }
done_rc() { waitfor "[[ -s $dir/rc.$1 ]]" && cat "$dir/rc.$1"; }
nonce_of() { sed -n 's/^nonce: //p' "$P/$1.req"; }
write_dec() { printf 'id: %s\nutc: x\nby: Relay\nnonce: %s\nwords: %s\n' "$1" "$3" "$4" >"$P/$1.$2"; }
input_of() { sed -n '/^input:$/,$p' "$P/$1.req" | sed 1d; }

# 1-3: silent cases
for c in "nobody" "Relay" "Relay-1"; do
  out=$(req_json | SABHA_ROLE=$c bash "$hook" 2>/dev/null); rc=$?
  check "silent for $c" '[[ $rc == 0 && -z $out && ! -d $P ]]'
done
out=$(req_json | bash "$hook" 2>/dev/null); rc=$?
check "silent with no role" '[[ $rc == 0 && -z $out && ! -d $P ]]'
for m in bypassPermissions dontAsk; do
  out=$(req_json "$TI" "$m" | SABHA_ROLE=BuilderHeavy bash "$hook" 2>/dev/null); rc=$?
  check "silent in $m" '[[ $rc == 0 && -z $out && ! -d $P ]]'
done
# a permission_mode inside the tool input is data, not the session mode
out=$(req_json '{"command":"echo \"permission_mode\":\"dontAsk\""}' default | SABHA_ROLE=BuilderHeavy SABHA_RELAY_WAIT=0 bash "$hook" 2>/dev/null)
check "mode inside tool_input is ignored" '[[ -f $P/BuilderHeavy-001.req ]] && grep -q "^mode: default$" $P/BuilderHeavy-001.req'
waitfor "grep -q BuilderHeavy-001 $FAKE_HERDR_LOG 2>/dev/null"
rm -rf "$P"; : >"$FAKE_HERDR_LOG"

# 4, 5, 12, 13: request written, nudge sent, allowed with the right nonce
printf 'SABHA_PUSH=ntfy\nSABHA_NTFY_TOPIC=t-test\nSABHA_NTFY_URL=http://ntfy.invalid\n' >>"$dir/sabha.conf"
hook_bg a "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-001.req ]]"
r=$P/BuilderHeavy-001.req
check "claim and request exist" '[[ -f $P/BuilderHeavy-001.claim && -f $r ]]'
for k in id utc role tool cwd mode nonce hash expires; do
  check "req has $k:" 'grep -q "^$k: ." "$r"'
done
check "req role, tool, cwd" 'grep -q "^role: BuilderHeavy$" $r && grep -q "^tool: Bash$" $r && grep -q "^cwd: /w/x$" $r'
check "input is the tool_input, byte for byte" '[[ "$(input_of BuilderHeavy-001)" == "$TI" ]]'
check "nonce is 32 hex" '[[ $(nonce_of BuilderHeavy-001) =~ ^[0-9a-f]{32}$ ]]'
h=$(printf '%s' "$TI" | shasum -a 256 | cut -d" " -f1)
check "hash is sha256 of the input" 'grep -q "^hash: $h$" $r'
waitfor "grep -q 'permissions/BuilderHeavy-001.req' $FAKE_HERDR_LOG 2>/dev/null"
check "nudge to the relay names the request" 'grep -q "agent prompt w1:p9 see inbox/Relay/permissions/BuilderHeavy-001.req" $FAKE_HERDR_LOG'
check "every herdr call carries --session" '! grep -v -- "--session" $FAKE_HERDR_CALLS'
waitfor "[[ -s $dir/curl.calls ]]"
check "ntfy body: role and tool, never the command" 'grep -q "^sabha: BuilderHeavy asks permission (Bash), see Relay$" $dir/curl.calls && ! grep -q "go test" $dir/curl.calls && grep -q "^http://ntfy.invalid/t-test$" $dir/curl.calls'
sleep 1
check "still waiting before a decision" '[[ ! -e $dir/rc.a ]]'
"$perm" allow BuilderHeavy-001 "yes, run the go tests" >/dev/null
rc=$(done_rc a); out=$(cat "$dir/out.a")
check "allow: exit 0" '[[ $rc == 0 ]]'
check "allow: decision JSON" '[[ $(printf "%s" "$out" | jq -r .hookSpecificOutput.decision.behavior) == allow && $(printf "%s" "$out" | jq -r .hookSpecificOutput.hookEventName) == PermissionRequest ]]'
check "allow: log row with the words" '[[ $(grep -c . $P/log.tsv) == 1 ]] && awk -F"\t" "\$3==\"BuilderHeavy-001\" && \$6==\"allow\" && \$7==\"yes, run the go tests\" && \$5==\"$h\"" $P/log.tsv | grep -q .'
sed -i.bak '/^SABHA_PUSH/d; /^SABHA_NTFY/d' "$dir/sabha.conf"

# 6: deny, words with quotes stay valid JSON
hook_bg b "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-002.req ]]"
"$perm" deny BuilderHeavy-002 'no, not "now"' >/dev/null
rc=$(done_rc b); out=$(cat "$dir/out.b")
check "deny: behavior and message" '[[ $rc == 0 && $(printf "%s" "$out" | jq -r .hookSpecificOutput.decision.behavior) == deny && $(printf "%s" "$out" | jq -r .hookSpecificOutput.decision.message) == *"no, not \"now\""* ]]'
check "deny: log row" 'awk -F"\t" "\$3==\"BuilderHeavy-002\" && \$6==\"deny\"" $P/log.tsv | grep -q .'
check "no curl without SABHA_PUSH=ntfy" '[[ $(grep -c "^sabha:" $dir/curl.calls) == 1 ]]'

# 7: a wrong nonce is set aside and logged; the request stays answerable
hook_bg c "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-003.req ]]"
write_dec BuilderHeavy-003 allow 0123456789abcdef0123456789abcdef forged
waitfor "ls $P | grep -q '^BuilderHeavy-003.bad-'"
check "wrong nonce: file renamed .bad-*" '[[ ! -e $P/BuilderHeavy-003.allow ]] && ls $P | grep -q "^BuilderHeavy-003.bad-"'
check "wrong nonce: logged, still waiting" 'awk -F"\t" "\$3==\"BuilderHeavy-003\" && \$6==\"nonce-mismatch\"" $P/log.tsv | grep -q . && [[ ! -e $dir/rc.c ]]'
"$perm" allow BuilderHeavy-003 "yes" >/dev/null
rc=$(done_rc c)
check "wrong nonce: then the right one is honoured" '[[ $rc == 0 && $(jq -r .hookSpecificOutput.decision.behavior <$dir/out.c) == allow ]]'

# 8: pane hands back to the ordinary prompt
hook_bg d "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-004.req ]]"
"$perm" pane BuilderHeavy-004 >/dev/null
rc=$(done_rc d)
check "pane: exit 0, no stdout, logged" '[[ $rc == 0 && ! -s $dir/out.d ]] && awk -F"\t" "\$3==\"BuilderHeavy-004\" && \$6==\"pane\"" $P/log.tsv | grep -q .'

# 9: timeout
t0=$SECONDS
out=$(req_json | SABHA_ROLE=BuilderHeavy SABHA_RELAY_WAIT=2 bash "$hook" 2>/dev/null); rc=$?
el=$((SECONDS - t0))
check "timeout: exit 0, no stdout, about the wait ($el s)" '[[ $rc == 0 && -z $out && $el -ge 2 && $el -le 5 ]]'
check "timeout: .expired and log row" '[[ -f $P/BuilderHeavy-005.expired ]] && awk -F"\t" "\$3==\"BuilderHeavy-005\" && \$6==\"timeout\"" $P/log.tsv | grep -q .'
check "late answer refused" '! "$perm" allow BuilderHeavy-005 yes 2>/dev/null'

# 10: two requests from one role at once, each answered by its own file
hook_bg e "$(req_json '{"command":"echo A"}')"
hook_bg f "$(req_json '{"command":"echo B"}')"
waitfor "[[ -f $P/BuilderHeavy-006.req && -f $P/BuilderHeavy-007.req ]]"
ida=BuilderHeavy-006 idb=BuilderHeavy-007
[[ $(input_of $ida) == *'echo A'* ]] || { ida=BuilderHeavy-007 idb=BuilderHeavy-006; }
check "two requests: distinct nonces" '[[ $(nonce_of BuilderHeavy-006) != $(nonce_of BuilderHeavy-007) ]]'
"$perm" allow "$ida" "yes A" >/dev/null; "$perm" deny "$idb" "no B" >/dev/null
done_rc e >/dev/null; done_rc f >/dev/null
check "two requests: each gets its own decision" '[[ $(jq -r .hookSpecificOutput.decision.behavior <$dir/out.e) == allow && $(jq -r .hookSpecificOutput.decision.behavior <$dir/out.f) == deny ]]'

# 11: no jq anywhere on the path the hook takes; pretty-printed JSON keeps its nested input verbatim
NESTED='{
  "file_path": "/w/a.md",
  "edits": [{"old": "x}", "new": "y\"]"}]
}'
pretty=$(printf '{\n  "permission_mode": "default",\n  "tool_name": "MultiEdit",\n  "tool_input": %s,\n  "cwd": "/w"\n}' "$NESTED")
( printf '%s' "$pretty" | PATH=$dir/nojq:$PATH SABHA_ROLE=BuilderHeavy bash "$hook" >"$dir/out.g" 2>/dev/null; echo $? >"$dir/rc.g" ) &
waitfor "[[ -f $P/BuilderHeavy-008.req ]]"
check "no jq: nested, pretty input verbatim" '[[ "$(input_of BuilderHeavy-008)" == "$NESTED" ]] && grep -q "^tool: MultiEdit$" $P/BuilderHeavy-008.req'
PATH=$dir/nojq:$PATH "$perm" allow BuilderHeavy-008 "ok" >/dev/null
rc=$(done_rc g)
check "no jq: allow honoured" '[[ $rc == 0 ]] && grep -q "\"behavior\":\"allow\"" $dir/out.g'

# 12b: herdr unusable: the outcome does not change, the failure is logged
mkdir -p "$dir/badh"; printf '#!/bin/sh\nexit 1\n' >"$dir/badh/herdr"; chmod +x "$dir/badh/herdr"
( printf '%s' "$(req_json)" | SABHA_HERDR_BIN=$dir/badh/herdr SABHA_ROLE=BuilderHeavy bash "$hook" >"$dir/out.h" 2>/dev/null; echo $? >"$dir/rc.h" ) &
waitfor "[[ -f $P/BuilderHeavy-009.req ]]"
"$perm" allow BuilderHeavy-009 "yes" >/dev/null
rc=$(done_rc h)
check "nudge failure: still allowed" '[[ $rc == 0 && $(jq -r .hookSpecificOutput.decision.behavior <$dir/out.h) == allow ]]'
waitfor "grep -q 'refusing to touch a real herdr' $P/nudge.log 2>/dev/null"
check "nudge failure: logged" 'grep -q "refusing to touch a real herdr" $P/nudge.log'

check "audit: every honoured decision so far came through sabha-perm" '"$perm" audit >/dev/null'

# 16: tabs and newlines in words collapse; one row per decision
hook_bg i "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-010.req ]]"
write_dec BuilderHeavy-010 allow "$(nonce_of BuilderHeavy-010)" "$(printf 'a\tb')"
done_rc i >/dev/null
check "log: words tab collapsed, 7 fields" 'awk -F"\t" "\$3==\"BuilderHeavy-010\" { print NF, \$7 }" $P/log.tsv | grep -qx "7 a b"'
check "log: every row has 7 fields" '[[ -z $(awk -F"\t" "NF != 7" $P/log.tsv) ]]'

# 14: sabha-perm
hook_bg j "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-011.req ]]"
check "list: the open request only" '[[ $("$perm" list | cut -f1) == BuilderHeavy-011 ]]'
check "show: verbatim" '[[ "$("$perm" show BuilderHeavy-011)" == "$(cat $P/BuilderHeavy-011.req)" ]]'
check "allow without words refused" '! "$perm" allow BuilderHeavy-011 2>/dev/null && ! "$perm" allow BuilderHeavy-011 "  " 2>/dev/null'
check "a worker cannot answer" '! SABHA_ROLE=BuilderHeavy "$perm" allow BuilderHeavy-011 yes 2>/dev/null && SABHA_ROLE=Relay "$perm" allow BuilderHeavy-011 "$(printf "fine\tby me")" >/dev/null'
check "decision copies the nonce, words collapsed" 'grep -q "^nonce: $(nonce_of BuilderHeavy-011)$" $P/BuilderHeavy-011.allow && grep -q "^words: fine by me$" $P/BuilderHeavy-011.allow'
check "second decision refused" '! "$perm" allow BuilderHeavy-011 yes 2>/dev/null && ! "$perm" deny BuilderHeavy-011 no 2>/dev/null'
check "relay.tsv row" 'awk -F"\t" "\$2==\"BuilderHeavy-011\" && \$3==\"allow\" && \$4==\"fine by me\"" $P/relay.tsv | grep -q .'
check "bad id refused" '! "$perm" show "../x" 2>/dev/null && ! "$perm" allow BuilderHeavy-999 yes 2>/dev/null'
printf 'id: X-001\nutc: x\nexpires: 2000-01-01T00:00:00Z\nnonce: n\ninput:\n{}\n' >"$P/Old-001.req"
check "expired by time refused and not listed" '! "$perm" allow Old-001 yes 2>/dev/null && ! "$perm" list | grep -q Old-001'
done_rc j >/dev/null
printf '2026-10-19T00:00:00Z\tBuilderHeavy\tBuilderHeavy-077\tBash\th\tallow\tforged\n' >>"$P/log.tsv"
out=$("$perm" audit); rc=$?
check "audit: hand-written allows reported, relay-written ones not" '[[ $rc == 1 && $out == *BuilderHeavy-077* && $out == *BuilderHeavy-010* && $out != *BuilderHeavy-011* && $out != *BuilderHeavy-003* ]]'

# snippet (Q1-B: per-user mode and allow list, shipped list as the default)
s=$("$perm" snippet)
check "snippet: JSON, default mode, routine rules" 'printf "%s" "$s" | jq -e ".permissions.defaultMode == \"default\" and (.permissions.allow | index(\"Read\")) and (.permissions.allow | index(\"Edit(/$impl/**)\")) and (.permissions.allow | index(\"Write(/$impl/**)\"))" >/dev/null'
check "snippet: decision files denied to Edit/Write" 'printf "%s" "$s" | jq -e ".permissions.deny == [\"Edit(/$P/**)\", \"Write(/$P/**)\"]" >/dev/null'
s=$(SABHA_PERMISSION_MODE=acceptEdits SABHA_PERMISSION_ALLOW='default; Bash(make test)' "$perm" snippet)
check "snippet: user mode, default plus own rule" 'printf "%s" "$s" | jq -e ".permissions.defaultMode == \"acceptEdits\" and (.permissions.allow | index(\"Read\")) and .permissions.allow[-1] == \"Bash(make test)\"" >/dev/null'
s=$(SABHA_PERMISSION_ALLOW='Read;Bash(echo "x")' "$perm" snippet)
check "snippet: own list replaces the default, quotes escaped" 'printf "%s" "$s" | jq -e ".permissions.allow == [\"Read\", \"Bash(echo \\\"x\\\")\"]" >/dev/null'

# 15: hooks.json and syntax
check "hooks.json: four events, PermissionRequest timeout 1800, no onFailure" 'jq -e "(.hooks | keys) == [\"PermissionRequest\",\"PreToolUse\",\"SessionStart\",\"Stop\"] and .hooks.PermissionRequest[0].hooks[0].timeout == 1800 and (.hooks.PermissionRequest[0].hooks[0] | has(\"onFailure\") | not) and (.hooks.PermissionRequest[0] | has(\"matcher\") | not)" $root/hooks/hooks.json >/dev/null'
check "bash -n both scripts" 'bash -n "$hook" && bash -n "$perm"'

if [[ $fails -gt 0 ]]; then echo "FAIL: $fails check(s)"; exit 1; fi
echo "ok: permission relay (hook request, nonce, wait, decisions, log, nudge, ntfy body; sabha-perm list/show/decide/audit/snippet)"
