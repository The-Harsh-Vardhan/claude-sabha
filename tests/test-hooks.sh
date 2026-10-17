#!/usr/bin/env bash
# hooks/: role detection, SessionStart context, the push guard (relay exempt), the stale-handoff reminder.
# Run: tests/test-hooks.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
hooks=$(cd "$(dirname "$0")/../hooks" && pwd)
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-hooks.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
unset SABHA_ROLE SABHA_IMPL SABHA_PLAN SABHA_ROSTER SABHA_HANDOFF_MAX_AGE
impl=$dir/impl
mkdir -p "$impl/status" "$impl/inbox/Bhima"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="%s"\n' "$dir" "$impl" \
  "Vidur:claude:opus Yudhishthira:claude:opus Bhima:claude:opus" >"$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf

fail() { echo "FAIL: $*"; exit 1; }
run() { # run <hook> <json>: sets out and rc
  out=$(printf '%s' "$2" | bash "$hooks/$1" 2>"$dir/err"); rc=$?; err=$(cat "$dir/err")
}
bash_json() { # a " in the command is escaped as the hook JSON would carry it
  local c=${2//\"/\\\"}; printf '{"session_name":"%s","tool_input":{"command":"%s"}}' "$1" "$c"; }

printf '# Bhima\n\n## Task\nbuild the export matrix\n\n## Done\nsecret-done-line\n\n## Next\nwrite the tests\n\n## Constraints\nno pushing\n' \
  >"$impl/status/bhima.md"
: >"$impl/inbox/Bhima/001-yudhishthira-first.md"
: >"$impl/inbox/Bhima/001.done"
: >"$impl/inbox/Bhima/002-yudhishthira-second.md"
: >"$impl/inbox/Bhima/002.ack"
: >"$impl/inbox/Bhima/003-yudhishthira-third.md"

# session start
run sabha-session-start.sh '{"session_name":"Bhima","source":"startup"}'
[[ $rc == 0 ]] || fail "start rc $rc"
[[ $out == *"build the export matrix"* && $out == *"write the tests"* && $out == *"no pushing"* ]] || fail "handoff sections: $out"
[[ $out != *secret-done-line* ]] || fail "Done section should not be injected"
[[ $out == *002-yudhishthira-second.md* && $out == *003-yudhishthira-third.md* ]] || fail "open briefs: $out"
[[ $out != *001-yudhishthira-first.md* ]] || fail "done brief listed"
[[ $out == *"Never use --resume"* ]] || fail "resume warning"
# env wins over json; no jq needed path is the same sed
SABHA_ROLE=Bhima run sabha-session-start.sh '{}'
[[ $out == *"build the export matrix"* ]] || fail "SABHA_ROLE detection"
# not sabha: silent
run sabha-session-start.sh '{"session_name":"somebody"}'
[[ $rc == 0 && -z $out ]] || fail "unknown name must be silent"
run sabha-session-start.sh '{"source":"startup"}'
[[ $rc == 0 && -z $out ]] || fail "no name must be silent"
# a missing roster never fails the session
SABHA_CONF=$dir/missing.conf run sabha-session-start.sh '{"session_name":"Bhima"}'
[[ $rc == 0 && -z $out ]] || fail "missing conf must be silent"

# guard
for c in 'git push origin main' 'git push' 'git -C /x push --force' 'cd a && git push' 'gh pr create --title x' \
         'gh pr merge 5' 'gh pr comment 5 -b hi' 'gh pr edit 5' \
         'curl -X POST -d x https://hooks.slack.com/services/T/B/C'; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 2 ]] || fail "guard should block ($rc): $c"
  [[ $err == *"only the human pushes"* ]] || fail "guard reason: $err"
done
# Shakuni B5: the phrase inside quoted text or a heredoc body is data, not a push
for c in 'git status' 'git commit -m push-fix' 'git commit -m "push it"' 'gh pr view 5' 'curl https://example.com' 'git log --oneline' \
         'git commit -m "docs: never git push here"' 'grep -rn "git push" docs' 'echo "run gh pr create later" >> brief.md' \
         'git stash push -m x' 'cat > brief.md <<EOF\nrelay: git push after review\ngh pr create next\nEOF' \
         "cat <<'DONE' > x.md\n\tgit push origin main\nDONE\necho done"; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 0 ]] || fail "guard should allow ($rc): $c"
done
# Shakuni B1 (partly) and B4: quoted -C argument, path prefix, env prefix, a command after a newline
for c in 'git -C "/a b" push' 'FOO=1 git push' 'command git push' '\\git push' '/usr/bin/git push' 'git --git-dir=x push' \
         'git -C /a -C /b push' 'echo hi\ngit push' 'gh -R a/b pr create' 'gh --repo a/b pr merge 3' \
         'cat <<EOF\nbody\nEOF\ngit push'; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 2 ]] || fail "guard should block ($rc): $c"
done
# Shakuni B6: a here-string, a shift or a quoted "<<EOF" is not a heredoc start; B7: sh -c / eval run their string;
# N6: keywords, $( ) and sudo/env wrappers are command positions too
for c in 'cat <<< hi\ngit push' 'read a <<< "x y"\ngit push' 'echo $((1 << n))\ngit push' 'echo "<<EOF"\ngit push' \
         "sh -c 'git push'" 'bash -c "git push"' "eval 'git push'" 'zsh -c "cd a && git push"' \
         'if true; then git push; fi' 'x=$(git push)' 'sudo git push' 'env FOO=1 git push' 'timeout 10 git push'; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 2 ]] || fail "guard should block ($rc): $c"
done
# Shakuni RECHECK 2: combined -lc flags and a lone & are command positions (N8, N9); sh -c inside quoted text is data (B8)
for c in "bash -lc 'git push'" "sh -ec 'git push'" "bash -c -- 'git push'" 'true & git push'; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 2 ]] || fail "guard should block ($rc): $c"
done
for c in "sh -c 'echo \"git push\"'" 'eval "echo git push"' 'cat <<< "git push"' 'echo "<<EOF"\ngit status' \
         "git commit -m \"see: sh -c 'git push'\"" "git commit -m \"note: eval 'git push' is blocked\"" \
         "echo \"run sh -c 'git push' later\"" "git commit -m 'run bash -c \"git push\" later'" 'make build 2>&1 | tail'; do
  run sabha-guard.sh "$(bash_json Bhima "$c")"
  [[ $rc == 0 ]] || fail "guard should allow ($rc): $c"
done
# B4 without jq (a failing jq stub): the raw-JSON path unescapes \n and \" before matching
mkdir -p "$dir/nojq"; printf '#!/bin/sh\nexit 1\n' >"$dir/nojq/jq"; chmod +x "$dir/nojq/jq"
PATH=$dir/nojq:$PATH SABHA_ROLE=Bhima run sabha-guard.sh "$(bash_json Bhima 'echo hi\ngit push')"
[[ $rc == 2 ]] || fail "no-jq multi-line push should block ($rc): $err"
PATH=$dir/nojq:$PATH SABHA_ROLE=Bhima run sabha-guard.sh "$(bash_json Bhima 'git commit -m "git push"')"
[[ $rc == 0 ]] || fail "no-jq quoted phrase should pass ($rc): $err"
run sabha-guard.sh "$(bash_json Vidur 'git push origin main')"
[[ $rc == 0 ]] || fail "relay must be allowed to push"
run sabha-guard.sh "$(bash_json other 'git push')"
[[ $rc == 0 ]] || fail "non-sabha session must be untouched"
run sabha-guard.sh '{"tool_input":{"command":"git push"}}'
[[ $rc == 0 ]] || fail "no session name must be untouched"
SABHA_ROLE=Bhima run sabha-guard.sh '{"tool_input":{"command":"git push"}}'
[[ $rc == 2 ]] || fail "SABHA_ROLE must be guarded"
# N1: SABHA_ROLE set but unresolvable (missing config) blocks instead of running unguarded
SABHA_ROLE=Bhima SABHA_CONF=$dir/missing.conf run sabha-guard.sh "$(bash_json Bhima 'git status')"
[[ $rc == 2 && $err == *"could not be resolved"* ]] || fail "unresolved SABHA_ROLE must block ($rc): $err"
SABHA_ROLE=Nobody run sabha-guard.sh "$(bash_json Nobody 'git status')"
[[ $rc == 2 ]] || fail "SABHA_ROLE outside the roster must block ($rc)"
run sabha-guard.sh "$(bash_json Bhima-1 'git push')"
[[ $rc == 2 ]] || fail "a copy of a worker must be guarded"

# stop hook
touch -t 202001010000 "$impl/status/bhima.md"
run sabha-stop.sh '{"session_name":"Bhima"}'
[[ $rc == 0 && $out == *"status/bhima.md"* && $out == *002-yudhishthira-second.md* ]] || fail "stale reminder: $rc $out"
touch "$impl/status/bhima.md"
run sabha-stop.sh '{"session_name":"Bhima"}'
[[ $rc == 0 && -z $out ]] || fail "fresh status must be silent: $out"
touch -t 202001010000 "$impl/status/bhima.md"
SABHA_HANDOFF_MAX_AGE=99999999 run sabha-stop.sh '{"session_name":"Bhima"}'
[[ $rc == 0 && -z $out ]] || fail "age override: $out"
: >"$impl/inbox/Bhima/002.done"
run sabha-stop.sh '{"session_name":"Bhima"}'
[[ $rc == 0 && -z $out ]] || fail "no acked open brief must be silent: $out"
run sabha-stop.sh '{"session_name":"nobody"}'
[[ $rc == 0 && -z $out ]] || fail "non-sabha stop must be silent"

echo "ok: hooks detect the role, inject handoff and open briefs, block pushes for non-relay roles, remind on a stale handoff"
