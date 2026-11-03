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
P=$impl/permissions
mkdir -p "$impl/status" "$dir/ws" "$dir/stubs" "$dir/nojq"
# the grid writes this map; sabha_nudge stops (set -e) when it is missing
echo "Relay w1:p1" >"$impl/status/herdr-panes.txt"
cat >"$dir/sabha.conf" <<EOF
SABHA_WS=$dir/ws
SABHA_IMPL=$impl
SABHA_ROSTER="Relay:claude:opus Dispatcher:claude:opus BuilderHeavy:claude:opus"
EOF
export SABHA_CONF=$dir/sabha.conf SABHA_RELAY_WAIT=${SABHA_TEST_WAIT:-120}
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
# an event ceiling (SABHA_TEST_WAIT s, default 120), not a fixed budget: under load the hook answers in seconds
waitfor() { local i; for (( i = 0; i < ${SABHA_TEST_WAIT:-120} * 10; i++ )); do eval "$1" && return 0; sleep 0.1; done; return 1; }
done_rc() { waitfor "[[ -s $dir/rc.$1 ]]" && cat "$dir/rc.$1"; }
nonce_of() { sed -n 's/^nonce: //p' "$P/$1.req"; }
write_dec() { printf 'id: %s\nutc: x\nby: Relay\nnonce: %s\nwords: %s\n' "$1" "$3" "$4" >"$P/$1.$2"; }
rp() { SABHA_ROLE=Relay "$perm" "$@"; }
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
check "nudge to the relay names the request" 'grep -q "agent prompt w1:p1 see permissions/BuilderHeavy-001.req" $FAKE_HERDR_LOG'
check "every herdr call carries --session" '! grep -v -- "--session" $FAKE_HERDR_CALLS'
waitfor "[[ -s $dir/curl.calls ]]"
check "ntfy body: role and tool, never the command" 'grep -q "^sabha: BuilderHeavy asks permission (Bash), see Relay$" $dir/curl.calls && ! grep -q "go test" $dir/curl.calls && grep -q "^http://ntfy.invalid/t-test$" $dir/curl.calls'
sleep 1
check "still waiting before a decision" '[[ ! -e $dir/rc.a ]]'
rp allow BuilderHeavy-001 "yes, run the go tests" >/dev/null
rc=$(done_rc a); out=$(cat "$dir/out.a")
check "allow: exit 0" '[[ $rc == 0 ]]'
check "allow: decision JSON" '[[ $(printf "%s" "$out" | jq -r .hookSpecificOutput.decision.behavior) == allow && $(printf "%s" "$out" | jq -r .hookSpecificOutput.hookEventName) == PermissionRequest ]]'
check "allow: log row with the words" '[[ $(grep -c . $P/log.tsv) == 1 ]] && awk -F"\t" "\$3==\"BuilderHeavy-001\" && \$6==\"allow\" && \$7==\"yes, run the go tests\" && \$5==\"$h\"" $P/log.tsv | grep -q .'
sed -i.bak '/^SABHA_PUSH/d; /^SABHA_NTFY/d' "$dir/sabha.conf"

# 6: deny, words with quotes stay valid JSON
hook_bg b "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-002.req ]]"
rp deny BuilderHeavy-002 'no, not "now"' >/dev/null
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
rp allow BuilderHeavy-003 "yes" >/dev/null
rc=$(done_rc c)
check "wrong nonce: then the right one is honoured" '[[ $rc == 0 && $(jq -r .hookSpecificOutput.decision.behavior <$dir/out.c) == allow ]]'

# 8: pane hands back to the ordinary prompt
hook_bg d "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-004.req ]]"
rp pane BuilderHeavy-004 >/dev/null
rc=$(done_rc d)
check "pane: exit 0, no stdout, logged" '[[ $rc == 0 && ! -s $dir/out.d ]] && awk -F"\t" "\$3==\"BuilderHeavy-004\" && \$6==\"pane\"" $P/log.tsv | grep -q .'

# 9: timeout
t0=$SECONDS
out=$(req_json | SABHA_ROLE=BuilderHeavy SABHA_RELAY_WAIT=2 bash "$hook" 2>/dev/null); rc=$?
el=$((SECONDS - t0))
check "timeout: exit 0, no stdout, about the wait ($el s)" '[[ $rc == 0 && -z $out && $el -ge 2 && $el -le 30 ]]'
check "timeout: .expired and log row" '[[ -f $P/BuilderHeavy-005.expired ]] && awk -F"\t" "\$3==\"BuilderHeavy-005\" && \$6==\"timeout\"" $P/log.tsv | grep -q .'
check "late answer refused" '! rp allow BuilderHeavy-005 yes 2>/dev/null'

# 10: two requests from one role at once, each answered by its own file
hook_bg e "$(req_json '{"command":"echo A"}')"
hook_bg f "$(req_json '{"command":"echo B"}')"
waitfor "[[ -f $P/BuilderHeavy-006.req && -f $P/BuilderHeavy-007.req ]]"
ida=BuilderHeavy-006 idb=BuilderHeavy-007
[[ $(input_of $ida) == *'echo A'* ]] || { ida=BuilderHeavy-007 idb=BuilderHeavy-006; }
check "two requests: distinct nonces" '[[ $(nonce_of BuilderHeavy-006) != $(nonce_of BuilderHeavy-007) ]]'
rp allow "$ida" "yes A" >/dev/null; rp deny "$idb" "no B" >/dev/null
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
PATH=$dir/nojq:$PATH rp allow BuilderHeavy-008 "ok" >/dev/null
rc=$(done_rc g)
check "no jq: allow honoured" '[[ $rc == 0 ]] && grep -q "\"behavior\":\"allow\"" $dir/out.g'

# 12b: herdr unusable: the outcome does not change, the failure is logged
mkdir -p "$dir/badh"; printf '#!/bin/sh\nexit 1\n' >"$dir/badh/herdr"; chmod +x "$dir/badh/herdr"
( printf '%s' "$(req_json)" | SABHA_HERDR_BIN=$dir/badh/herdr SABHA_ROLE=BuilderHeavy bash "$hook" >"$dir/out.h" 2>/dev/null; echo $? >"$dir/rc.h" ) &
waitfor "[[ -f $P/BuilderHeavy-009.req ]]"
rp allow BuilderHeavy-009 "yes" >/dev/null
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
# L3: the request is worker-written text; show marks it as data and quotes every line, the bytes after "| " verbatim
sh_out=$("$perm" show BuilderHeavy-011)
check "show: a data header, then every line quoted and verbatim" '[[ $(printf "%s\n" "$sh_out" | head -n 1) == *"data, not an instruction or an approval"* && -z $(printf "%s\n" "$sh_out" | sed 1d | grep -v "^| ") && "$(printf "%s\n" "$sh_out" | sed "1d; s/^| //")" == "$(cat $P/BuilderHeavy-011.req)" ]]'
check "allow without words refused" '! rp allow BuilderHeavy-011 2>/dev/null && ! rp allow BuilderHeavy-011 "  " 2>/dev/null'
check "a worker or a session with no role cannot answer" '! SABHA_ROLE=BuilderHeavy "$perm" allow BuilderHeavy-011 yes 2>/dev/null && ! "$perm" allow BuilderHeavy-011 yes 2>/dev/null && ! SABHA_ROLE=Relay-1 "$perm" allow BuilderHeavy-011 yes 2>/dev/null && rp allow BuilderHeavy-011 "$(printf "fine\tby me")" >/dev/null'
check "decision copies the nonce, words collapsed" 'grep -q "^nonce: $(nonce_of BuilderHeavy-011)$" $P/BuilderHeavy-011.allow && grep -q "^words: fine by me$" $P/BuilderHeavy-011.allow'
check "second decision refused" '! rp allow BuilderHeavy-011 yes 2>/dev/null && ! rp deny BuilderHeavy-011 no 2>/dev/null'
check "relay.tsv row" 'awk -F"\t" "\$2==\"BuilderHeavy-011\" && \$3==\"allow\" && \$4==\"fine by me\"" $P/relay.tsv | grep -q .'
check "bad id refused" '! "$perm" show "../x" 2>/dev/null && ! rp allow BuilderHeavy-999 yes 2>/dev/null'
printf 'id: X-001\nutc: x\nexpires: 2000-01-01T00:00:00Z\nnonce: n\ninput:\n{}\n' >"$P/Old-001.req"
check "expired by time refused and not listed" '! rp allow Old-001 yes 2>/dev/null && ! "$perm" list | grep -q Old-001'
done_rc j >/dev/null
printf '2026-10-19T00:00:00Z\tBuilderHeavy\tBuilderHeavy-077\tBash\th\tallow\tforged\n' >>"$P/log.tsv"
out=$("$perm" audit); rc=$?
check "audit: hand-written allows reported, relay-written ones not" '[[ $rc == 1 && $out == *BuilderHeavy-077* && $out == *BuilderHeavy-010* && $out != *BuilderHeavy-011* && $out != *BuilderHeavy-003* ]]'

# snippet (Q1-B: per-user mode and allow list, shipped list as the default)
# covers <path> <kind> <snippet> [allow|deny]: true when a rule of that kind in that list (allow by default) matches
# the path, compared case-insensitively (APFS folds case; Claude Code's matcher is UNVERIFIED either way).
# Rule //abs/** -> glob /abs/*
covers() {
  local r g t
  t=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r r; do
    g=${r#"$2("}; g=${g%)}; g=${g#/}; g=${g//\*\*/*}
    g=$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')
    # shellcheck disable=SC2053  # g is a glob on purpose
    [[ $t == $g ]] && return 0
  done < <(printf '%s' "$3" | jq -r ".permissions.${4:-allow}[] | select(startswith(\"$2(\"))")
  return 1
}
# writable <path> <snippet>: an allow covers it for Edit and Write and no deny does (no prompt for that write)
writable() { local k; for k in Edit Write; do covers "$1" $k "$2" && ! covers "$1" $k "$2" deny || return 1; done; }
in_deny() { printf '%s' "$2" | jq -e --arg r "$1" '.permissions.deny | index($r)' >/dev/null; }
s=$("$perm" snippet)
check "snippet: JSON, default mode, routine writes" 'printf "%s" "$s" | jq -e ".permissions.defaultMode == \"default\"" >/dev/null && covers "$impl/inbox/Dispatcher/001-x.md" Write "$s" && covers "$impl/status/relay.md" Edit "$s" && covers "$impl/questions/a.md" Write "$s" && covers "$impl/for-me.items" Edit "$s" && covers "$dir/ws/repo--feat/a.go" Edit "$s"'
# SecurityCritic 1: a write to the sourced config is code in every hook
check "F1: no allow covers the config or a new file under IMPL; the running sabha copy is denied" '! covers "$SABHA_CONF" Write "$s" && ! covers "$SABHA_CONF" Edit "$s" && ! covers "$impl/sabha.conf" Write "$s" && in_deny "Write(/$root/**)" "$s" && in_deny "Edit(/$root/**)" "$s" && ! covers "$impl/evil.sh" Write "$s"'
cp "$dir/sabha.conf" "$impl/sabha.conf"
s2=$(SABHA_CONF=$impl/sabha.conf "$perm" snippet)
check "F1: the resolved config and the plan files are denied" 'in_deny "Write(/$impl/sabha.conf)" "$s2" && in_deny "Edit(/$impl/sabha.conf)" "$s2" && in_deny "Write(/$root/sabha.*.conf)" "$s2"'
rm -f "$impl/sabha.conf"
# SecurityCritic 2, 3, 4, 7: no shipped rule that writes files or runs new code
check "F2-4,7: no git log/diff/show, test, find or mkdir rule" '[[ -z $(printf "%s" "$s" | jq -r ".permissions.allow[]" | grep -E "^Bash\((git (log|diff|show)|bash |tests/|find|mkdir)") ]]'
# SecurityCritic 5: the permissions folder sits outside every allowed tree, in any case
check "F5: no allow covers the permissions folder in any case" '[[ $P != "$impl"/inbox/* ]] && ! covers "$P/BuilderHeavy-001.allow" Write "$s" && ! covers "$(printf "%s" "$P" | tr "[:lower:]" "[:upper:]")/x.allow" Edit "$s" && in_deny "Write(/$P/**)" "$s"'
# SecurityCritic 9: Read is scoped and secrets are denied
check "F9: no bare Read; .env, key files and ~/.ssh denied" '! printf "%s" "$s" | jq -e ".permissions.allow | index(\"Read\")" >/dev/null && for r in "Read(//**/.env)" "Read(//**/.env.*)" "Read(**/.env)" "Read(//**/.npmrc)" "Read(//**/*.pem)" "Read(//**/id_rsa*)" "Read(~/.ssh/**)"; do in_deny "$r" "$s" || exit 1; done'
check "git metadata and .sabha config denied to Edit/Write" 'in_deny "Edit(//**/.git)" "$s" && in_deny "Write(//**/.git/**)" "$s" && in_deny "Write(//**/.sabha/config)" "$s"'
# SecurityCritic round 2, N1: a git hook in a worktree runs as the user on the next commit; N2: a repo's .claude/
# hooks and settings, .mcp.json and .envrc run in the next session or shell started there
check "N1: git hooks in a worktree are not writable" '! writable "$dir/ws/repo--x/.githooks/pre-commit" "$s" && ! writable "$dir/ws/a--b/.husky/pre-commit" "$s" && ! writable "$dir/ws/a--b/.git/hooks/pre-commit" "$s" && writable "$dir/ws/repo--x/src/a.go" "$s"'
mkdir -p "$dir/ws/hk"; git -C "$dir/ws/hk" init -q && git -C "$dir/ws/hk" config core.hooksPath scripts/hooks
s3=$("$perm" snippet)
check "N1: a clone's own core.hooksPath is denied in it and its worktrees" '! writable "$dir/ws/hk--x/scripts/hooks/pre-commit" "$s3" && ! writable "$dir/ws/hk/scripts/hooks/pre-commit" "$s3" && writable "$dir/ws/hk--x/scripts/a.sh" "$s3"'
rm -rf "$dir/ws/hk"
# round 3, L4: the "--" worktree test looks at the clone's name, not at a WS path that itself contains "--"
mkdir -p "$dir/w--s/hk"; git -C "$dir/w--s/hk" init -q && git -C "$dir/w--s/hk" config core.hooksPath scripts/hooks
sed "s|^SABHA_WS=.*|SABHA_WS=$dir/w--s|" "$dir/sabha.conf" >"$dir/sabha4.conf"
s4=$(SABHA_CONF=$dir/sabha4.conf "$perm" snippet)
check "L4: a WS path containing -- still denies each clone's core.hooksPath" '! writable "$dir/w--s/hk--x/scripts/hooks/pre-commit" "$s4" && ! writable "$dir/w--s/hk/scripts/hooks/pre-commit" "$s4"'
rm -rf "$dir/w--s"
check "L5: .vscode, .mise.toml and .tool-versions in a worktree are not writable" '! writable "$dir/ws/a--b/.vscode/tasks.json" "$s" && ! writable "$dir/ws/a--b/.mise.toml" "$s" && ! writable "$dir/ws/a--b/.tool-versions" "$s"'
check "N2: .claude, .mcp.json and .envrc in a worktree are not writable" '! writable "$dir/ws/a--b/.claude/hooks/x.sh" "$s" && ! writable "$dir/ws/a--b/.claude/settings.local.json" "$s" && ! writable "$dir/ws/a--b/.mcp.json" "$s" && ! writable "$dir/ws/a--b/.envrc" "$s"'
check "L1: <name>.env secrets are denied to Read" 'covers "$dir/ws/.github-token.env" Read "$s" deny && covers "$dir/ws/a--b/.env" Read "$s" deny'
wt=$(dirname "$root")/$(basename "$root" | sed "s/--.*//")--other
check "L2: a sibling sabha worktree is readable, not writable by default" 'covers "$wt/hooks/x.sh" Read "$s" && ! covers "$wt/hooks/x.sh" Write "$s" && ! covers "$wt/bin/sabha-lib.sh" Edit "$s"'
s=$(SABHA_PERMISSION_MODE=acceptEdits SABHA_PERMISSION_ALLOW='default; Bash(make test)' "$perm" snippet)
check "snippet: user mode, default plus own rule" 'printf "%s" "$s" | jq -e ".permissions.defaultMode == \"acceptEdits\" and (.permissions.allow | index(\"Bash(ls:*)\")) and .permissions.allow[-1] == \"Bash(make test)\"" >/dev/null'
s=$(SABHA_PERMISSION_ALLOW='Read;Bash(echo "x")' "$perm" snippet)
check "snippet: own list replaces the default, quotes escaped, deny kept" 'printf "%s" "$s" | jq -e ".permissions.allow == [\"Read\", \"Bash(echo \\\"x\\\")\"]" >/dev/null && in_deny "Write(/$P/**)" "$s"'

# SecurityCritic 7: the unsandboxed hook never writes through a planted symlink or folder, and never takes a symlinked
# or copied request as a decision
hook_bg k "$(req_json)"
waitfor "[[ -f $P/BuilderHeavy-012.req ]]"
ln -s BuilderHeavy-012.req "$P/BuilderHeavy-012.allow"
# wait for the log row, not the .bad-* file: the hook renames first and logs second
waitfor "awk -F'\t' '\$3==\"BuilderHeavy-012\" && \$6==\"nonce-mismatch\"' $P/log.tsv | grep -q ."
check "F7: a symlink to the .req is not an allow" '[[ ! -s $dir/out.k && ! -e $dir/rc.k ]] && awk -F"\t" "\$3==\"BuilderHeavy-012\" && \$6==\"nonce-mismatch\"" $P/log.tsv | grep -q .'
cp "$P/BuilderHeavy-012.req" "$P/BuilderHeavy-012.allow"
waitfor "[[ \$(awk -F'\t' '\$3==\"BuilderHeavy-012\" && \$6==\"nonce-mismatch\"' $P/log.tsv | grep -c .) == 2 ]]"
check "F7: a copy of the .req is not an allow" '[[ ! -s $dir/out.k && ! -e $dir/rc.k && $(ls $P | grep -c "^BuilderHeavy-012.bad-") == 2 ]]'
rp deny BuilderHeavy-012 "no" >/dev/null; done_rc k >/dev/null
mkdir "$P/BuilderHeavy-013.req.tmp"
out=$(req_json | SABHA_ROLE=BuilderHeavy bash "$hook" 2>/dev/null); rc=$?
check "F7: a planted .req.tmp folder: fail safe, nothing written" '[[ $rc == 0 && -z $out && ! -e $P/BuilderHeavy-013.req ]]'
: >"$dir/victim"; mv "$P/log.tsv" "$dir/log.keep"; ln -s "$dir/victim" "$P/log.tsv"
out=$(req_json | SABHA_ROLE=BuilderHeavy SABHA_RELAY_WAIT=0 bash "$hook" 2>/dev/null); rc=$?
check "F7: log.tsv as a symlink: no request, no write through it" '[[ $rc == 0 && -z $out && ! -s $dir/victim ]]'
mv "$P/relay.tsv" "$dir/relay.keep"; ln -s "$dir/victim" "$P/relay.tsv"
printf 'id: Fake-001\nutc: x\nexpires: 2999-01-01T00:00:00Z\nnonce: n\ninput:\n{}\n' >"$P/Fake-001.req"
check "F7: sabha-perm refuses a symlinked relay.tsv" '! rp pane Fake-001 2>/dev/null && [[ ! -s $dir/victim && ! -e $P/Fake-001.pane ]]'
rm -f "$P/log.tsv" "$P/relay.tsv" "$P/Fake-001.req"; mv "$dir/log.keep" "$P/log.tsv"; mv "$dir/relay.keep" "$P/relay.tsv"

# 15: hooks.json and syntax
check "hooks.json: four events, PermissionRequest timeout 1800, no onFailure" 'jq -e "(.hooks | keys) == [\"PermissionRequest\",\"PreToolUse\",\"SessionStart\",\"Stop\"] and .hooks.PermissionRequest[0].hooks[0].timeout == 1800 and (.hooks.PermissionRequest[0].hooks[0] | has(\"onFailure\") | not) and (.hooks.PermissionRequest[0] | has(\"matcher\") | not)" $root/hooks/hooks.json >/dev/null'
check "bash -n both scripts" 'bash -n "$hook" && bash -n "$perm"'

if [[ $fails -gt 0 ]]; then echo "FAIL: $fails check(s)"; exit 1; fi
echo "ok: permission relay (hook request, nonce, wait, decisions, log, nudge, ntfy body; sabha-perm list/show/decide/audit/snippet)"
