#!/usr/bin/env bash
# bin/sabha-relay-guard on hook JSON (stdin): each tool class allowed and denied, Bash chaining and redirects refused,
# the "you do it" override for one turn, and sabha-up.sh passing the hooks to the relay only. No claude runs.
# Run: tests/test-relay-guard.sh  (BASH=/bin/bash for 3.2)
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
BIN=$(cd "$(dirname "$0")/../bin" && pwd)
SH=${BASH:-bash}
command -v jq >/dev/null || { echo "FAIL: jq missing"; exit 1; }
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-guard.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

I=$dir/impl
mkdir -p "$I/inbox/Yudhi" "$I/status" "$dir/ws/docs/audit/questions/sub" "$dir/ws/docs/audit/x"
printf 'SABHA_WS=%s/ws\nSABHA_IMPL=%s\nSABHA_ROSTER="Vidur:opus Yudhi:opus Arjun:sonnet"\n' "$dir" "$I" > "$dir/sabha.conf"
printf 'SABHA_RELAY_WRITE="%s/ws/docs/audit/*-review.md %s/ws/docs/audit/questions/*"\n' "$dir" "$dir" >> "$dir/sabha.conf"
export SABHA_CONF=$dir/sabha.conf CLAUDE_CONFIG_DIR=$dir/cc
# hook <mode> <json>: runs the guard, sets rc and err
hook() { err=$(printf '%s' "$2" | "$SH" "$BIN/sabha-relay-guard" "$1" Vidur 2>&1 >/dev/null); rc=$?; }
tool() { hook pre "$(jq -cn --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name: $t, tool_input: {($k): $v}}')"; }
allows() { tool "$@"; (( rc == 0 )); }
denies() { tool "$@"; (( rc == 2 )) && [[ $err == "relay: brief the dispatcher"* ]]; }

for t in Read Glob SendMessage AskUserQuestion ListAgents ToolSearch Skill; do
  check "$t is allowed" 'allows $t pattern x'
done
for t in Agent WebFetch NotebookEdit TaskCreate Monitor mcp__x__y; do
  check "$t is denied" 'denies $t x y'
done
check "Write under inbox/ is allowed" 'allows Write file_path "$I/inbox/Yudhi/001-vidur-x.md"'
slug=$(printf %s "$dir/ws" | sed 's/[^A-Za-z0-9]/-/g')
check "Edit in the relay's own project memory dir is allowed" 'allows Edit file_path "$dir/cc/projects/$slug/memory/MEMORY.md"'
check "memory of another project is denied" 'denies Edit file_path "$dir/cc/projects/-other-project/memory/MEMORY.md"'
check "a nested path under memory is denied" 'denies Write file_path "$dir/cc/projects/$slug/memory/a/b.md"'
check "a path under the project dir but not memory is denied" 'denies Write file_path "$dir/cc/projects/$slug/settings.json"'
check "Write to the relay's own status file is allowed" 'allows Write file_path "$I/status/vidur.md"'
check "Write to the relay's night handoff is allowed" 'allows Write file_path "$I/status/vidur-night-2026-11-04.md"'
check "Write to another role's status file is denied" 'denies Write file_path "$I/status/yudhi.md"'
check "Write to status/vidur-old.md is denied" 'denies Write file_path "$I/status/vidur-old.md"'
check "Write to status/.relay-override is denied" 'denies Write file_path "$I/status/.relay-override"'
check "a nested night path is denied" 'denies Write file_path "$I/status/vidur-night-x/y.md"'
check "Edit of for-me.items is allowed" 'allows Edit file_path "$I/for-me.items"'
check "Write to FOR-ME.md is denied" 'denies Write file_path "$I/FOR-ME.md"'
check "Write to for-me.items.bak is denied" 'denies Write file_path "$I/for-me.items.bak"'
check "SABHA_RELAY_WRITE: a review note is allowed" 'allows Write file_path "$dir/ws/docs/audit/a-review.md"'
check "SABHA_RELAY_WRITE: a question file is allowed" 'allows Write file_path "$dir/ws/docs/audit/questions/q1.md"'
check "SABHA_RELAY_WRITE: a file beside the review notes is denied" 'denies Write file_path "$dir/ws/docs/audit/plan.md"'
check "SABHA_RELAY_WRITE: one directory deep only" 'denies Write file_path "$dir/ws/docs/audit/questions/sub/q.md"'
check "SABHA_RELAY_WRITE: a review note in a subdir is denied" 'denies Write file_path "$dir/ws/docs/audit/x/a-review.md"'
ln -s "$dir/ws" "$I/inbox/link"
check "a symlinked dir under inbox/ is resolved and denied" 'denies Write file_path "$I/inbox/link/main.go"'
ln -s "$dir/ws/main.go" "$I/inbox/Yudhi/f.md"
check "a symlinked file under inbox/ is denied" 'denies Write file_path "$I/inbox/Yudhi/f.md"'
check "a .conf under inbox/ is denied" 'denies Write file_path "$I/inbox/Yudhi/sabha.conf"'
check "inbox/./ is denied" 'denies Write file_path "$I/inbox/./Yudhi/x.md"'
check "Edit of code in the workspace is denied" 'denies Edit file_path "$dir/ws/main.go"'
check "MultiEdit outside is denied" 'denies MultiEdit file_path "$dir/ws/a.txt"'
check "inbox/../ escape is denied" 'denies Write file_path "$I/inbox/../PROTOCOL.md"'
check "a relative path is denied" 'denies Write file_path "inbox/Yudhi/001.md"'
: >"$dir/ws/.env"; ln -s "$dir/ws/.env" "$dir/ws/notes.txt"
for f in .env .env.local .npmrc srv.pem tls.key id_rsa id_ed25519.pub; do
  check "Read of $f is denied" 'denies Read file_path "$dir/ws/$f"'
done
check "Read of a symlink to .env is denied" 'denies Read file_path "$dir/ws/notes.txt"'
check "Grep in .env is denied" 'denies Grep path "$dir/ws/.env"'
check "Glob for .env.* is denied" 'denies Glob glob ".env.*"'
mkdir -p "$dir/ws/.aws"
for f in .envrc .testsigma-github.env .testsigma-client.env .lab-agent.env .netrc credentials .aws/config; do
  check "Read of $f is denied" 'denies Read file_path "$dir/ws/$f"'
done
: >"$dir/ws/a.md"
check "Grep of a named file is allowed" 'allows Grep path "$dir/ws/a.md"'
check "Grep over a directory without a glob is denied" 'denies Grep path "$dir/ws"'
check "Grep with no path (the cwd) is denied" 'denies Grep pattern x'
gr() { hook pre "$(jq -cn --arg p "$1" --arg g "$2" '{tool_name: "Grep", tool_input: {pattern: "x", path: $p, glob: $g}}')"; }
check "Grep over a directory with glob **/*.md is allowed" 'gr "$dir/ws" "**/*.md"; (( rc == 0 ))'
for g in '*' '.env*' '*.env' '*.e[n]v' '{.env,a}' '!*.md' '*.pem'; do
  check "Grep over a directory with glob $g is denied" 'gr "$dir/ws" "$g"; (( rc == 2 ))'
done
check "Grep with a relative path and the hook cwd is judged as that dir" 'hook pre "$(jq -cn --arg c "$dir" '"'"'{tool_name: "Grep", cwd: $c, tool_input: {pattern: "x", path: "ws"}}'"'"')"; (( rc == 2 ))'
check "Glob for .envrc is denied" 'denies Glob glob "**/.envrc"'
check "Read of README.md is allowed" 'allows Read file_path "$dir/ws/README.md"'
for f in .ENV .Env a.KEY .pgpass .git-credentials kubeconfig credentials.json creds .git/config .docker/config.json; do
  check "Read of $f is denied" 'denies Read file_path "$dir/ws/$f"'
done
for f in .environment x.envelope.md .envs-notes 'app/[id]/page.tsx' 'app/{x}/a.md'; do
  check "Read of $f is allowed" 'allows Read file_path "$dir/ws/$f"'
done
check "Grep over a directory with glob .en? is denied" 'gr "$dir/ws" ".en?"; (( rc == 2 ))'
check "Glob for app/[id]/*.tsx is allowed" 'allows Glob glob "app/[id]/*.tsx"'
check "Glob for .e[n]v is denied" 'denies Glob glob "**/.e[n]v"'

# the Bash checks run from a cwd this test owns, so a dir named like a grep operand in the caller's cwd does not count
cw=$dir/ws/cw; mkdir -p "$cw/docs" "$cw/sub/.git" "$dir/out"
: >"$cw/.env"; ln -s "$cw/.env" "$cw/lnk"; ln -s "$dir/out" "$cw/outlnk"
cd "$cw" || exit 1
for c in 'grep docs a.md' 'grep -e docs a.md' 'git log --all -p' 'git -C sub branch --show-current' \
         "git -C $cw/sub log -1" 'git -C docs/.. log' "cd sub; git -C $cw log"; do
  check "Bash read-only: $c" 'allows Bash command "$c"'
done
for c in 'cat .ENV' 'head .Env' 'cat a.KEY' 'grep S .ENV' 'cat .pgpass' 'cat .git-credentials' 'cat kubeconfig' \
         'cat credentials.json' 'cat creds' 'cat .git/config' 'cat .docker/config.json' 'cat .aws/x' \
         'grep -f /etc/passwd x' 'grep -e x -f /etc/hosts' 'grep --file=/etc/hosts x' 'grep -f/etc/hosts x f' \
         'grep -ef x a.md' 'grep x docs' 'grep -e x docs' 'cat lnk' 'grep S lnk' 'git -C outlnk log' \
         'cd docs; git -C sub log' 'git -C missing log' 'git -C sub push'; do
  check "Bash denied: $c" 'denies Bash command "$c"'
done
for c in 'ls -la inbox''cat status/x.md | head -5' 'git log --oneline -3 2>/dev/null' 'git status && git diff' \
         'git branch --show-current' 'echo a=b' 'grep x docs/a.md' 'grep -n -i foo a.md | wc -l' 'git log -1' 'git diff HEAD~1' \
         'git log -p -1' 'tail -20 a >/dev/null 2>&1' 'echo hi 2>&1'; do
  check "Bash read-only: $c" 'allows Bash command "$c"'
done
for c in 'rm -rf x' 'ls; rm -rf x' 'ls && touch x' 'cat a | tee b' 'echo $(rm x)' 'echo `id`' 'echo x > f' \
         'echo x >> f' 'cat <(rm x)' 'git branch -D main' 'git -c core.pager=sh log' 'git diff --output=f' \
         'X=1 ls' 'ls >/dev/nullx' 'git push' 'git -C /r push' 'bin/sabha-run' 'sed -i s/a/b/ f' $'ls\nrm x' 'ls & rm x' \
         'cat =(touch F)' 'ls *(e:'"'"'touch F'"'"':)' 'echo ${(e):-\$\(touch F\)}' 'echo ${x@P}' 'echo $HOME' 'ls {a,b}' \
         'echo a\;touch F' '=ls' 'ls =ls' 'ls a\ b' 'ls $'"'"'a\tb'"'"'' 'echo a=b b=(c)' 'echo hi2>&1x' 'cd /r; echo hi2>&1x' 'echo hi >f' 'echo hi 2>&1x' 'ls 2>/dev/nullx' \
         "git log '--output=T/x' -1" 'git diff HEAD~1 "--output=T/y"' "git log '--ext-diff'" "git '-c' x=y log" \
         'grep -rn "foo bar" docs' 'cat .env' 'cat ws/.npmrc' 'head -1 a/b/id_rsa' 'git show HEAD:.env' 'cat .e*' 'ls ~' \
         'grep -r x .' 'grep -rh S .' 'grep -R x docs' 'grep -hr x a.md' 'grep --recursive x a.md' 'grep -d recurse x a.md' \
         'grep --directories=recurse x a.md' 'grep --include=a.md x a.md' 'grep x .' 'grep x docs/' 'cat .envrc' \
         'cat .testsigma-github.env' 'cat ws/.lab-agent.env' 'cat .netrc' 'cat .aws/credentials' 'cat --file=.envrc' \
         'git diff --no-index /dev/null .envrc' 'git diff --no-index /dev/null a.md' 'git log -O/etc/passwd' \
         'git diff -O a.md' 'ls ~1' 'ls a~b' 'git log HEAD~1x' 'git -C /tmp log' 'git -C /r push' 'git --git-dir=/r log'; do
  check "Bash denied: $c" 'denies Bash command "$c"'
done
long="touch X # $(printf '2>&1 %.0s' $(seq 4000))"
SECONDS=0; tool Bash command "$long"; took=$SECONDS
check "a 20 KB command is denied in a few seconds" '(( rc == 2 && took <= 3 ))'
hook pre 'not json'
check "unreadable input is denied" '(( rc == 2 ))'

# SABHA_RELAY_ALLOW_TOOLS: exact extra tool names; only tools that fall to the default deny, malformed fails closed
allowconf() { { cat "$dir/sabha.conf"; printf 'SABHA_RELAY_ALLOW_TOOLS=%q\n' "$1"; } > "$dir/allow.conf"; }
with() { SABHA_CONF=$dir/allow.conf "$@"; }
for t in Artifact ArtifactData; do check "empty allow list: $t is denied" 'denies $t x y'; done
allowconf "Artifact,ArtifactData"
check "allow Artifact,ArtifactData: Artifact is allowed" 'with allows Artifact x y'
check "allow Artifact,ArtifactData: ArtifactData is allowed" 'with allows ArtifactData x y'
check "allow Artifact,ArtifactData: WebFetch is still denied" 'with denies WebFetch x y'
allowconf "  Artifact,ArtifactData  "
check "surrounding spaces are trimmed" 'with allows ArtifactData x y'
allowconf "Artifact"
check "allow Artifact: ArtifactData is denied" 'with denies ArtifactData x y'
allowconf "Artifact,Bash,Write,Edit,WebFetch"
check "a listed Bash does not widen the read-only Bash rule" 'with denies Bash command "touch x"'
check "a listed Write does not widen the Write paths" 'with denies Write file_path "$dir/ws/main.go"'
check "a listed Edit does not widen the Edit paths" 'with denies Edit file_path "$dir/ws/main.go"'
check "a listed tool still allows Artifact" 'with allows Artifact x y'
allowconf "Artifact,ArtifactData"
check "an unlisted tool is denied with a list set" 'with denies Agent x y'
allowconf "Artifac"
check "a prefix of a name does not allow it" 'with denies Artifact x y'
allowconf "artifact"
check "names are case-sensitive" 'with denies Artifact x y'
for v in "Artifact,,ArtifactData" "Artifact ArtifactData" "Artifact*" "*" "Artifact,ArtifactData," "'Artifact'" \
         $'Artifact\nArtifactData' $'Artifact,ArtifactData\n' "Artifact;ArtifactData"; do
  allowconf "$v"
  check "malformed allow list fails closed: $(printf %q "$v")" \
    'with denies Artifact x y && [[ $err == *"SABHA_RELAY_ALLOW_TOOLS is malformed"* ]]'
done
allowconf "  "
check "a blank allow list allows nothing extra" 'with denies Artifact x y'

hook prompt '{"prompt":"Ok, you do it this time"}'
check "\"you do it\" inside a sentence does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"please do not let me say you do it"}'
check "\"... say you do it\" does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"brief this:\nyou do it"}'
check "\"you do it\" on a later line does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"you do it."}'
check "\"you do it.\" alone lifts the guard" '[[ -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"  you do it\nrun the build"}'
check "\"you do it\" as the first line lifts the guard" '[[ -e $I/status/.relay-override ]]'
check "override: Edit of workspace code passes" 'allows Edit file_path "$dir/ws/main.go"'
check "override: Bash write passes" 'allows Bash command "touch x"'
hook stop '{}'
check "Stop ends the turn: marker gone" '[[ ! -e $I/status/.relay-override ]]'
check "after the turn the guard is back" 'denies Edit file_path "$dir/ws/main.go"'
hook prompt '{"prompt":"you do it"}'; touch -t 202001010000 "$I/status/.relay-override"
check "an override older than 10 minutes does not lift the guard" 'denies Edit file_path "$dir/ws/main.go"'
hook prompt '{"prompt":"you do it"}'; hook start '{}'
check "SessionStart clears the override" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"please you do items 3 and 4"}'
check "\"you do items\" does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"doyou do itch"}'
check "\"you do itch\" does not lift the guard" '[[ ! -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"You Do It."}'
check "\"You Do It.\" (case, punctuation) lifts the guard" '[[ -e $I/status/.relay-override ]]'
hook prompt '{"prompt":"YOU DO IT"}'; hook prompt '{"prompt":"thanks, now brief it"}'
check "the next prompt without the words clears the marker" '[[ ! -e $I/status/.relay-override ]]'

out=$(SABHA_CONF=$dir/none.conf "$SH" "$BIN/sabha-relay-guard" pre <<<'{"tool_name":"Edit"}' 2>&1); rc=$?
check "no config: pre fails closed and names the escape" '(( rc == 2 )) && [[ $out == *"SABHA_RELAY_GUARD=0"* ]]'
out=$(SABHA_CONF=$dir/none.conf "$SH" "$BIN/sabha-relay-guard" pre <<<'{"tool_name":"Read"}' 2>&1); rc=$?
check "no config: even Read is denied (the guard cannot judge)" '(( rc == 2 ))'

# fail closed: any crash or odd input is a deny, never the non-blocking exit 1 of a hook
EDIT_IN='{"tool_name":"Edit","tool_input":{"file_path":"/x"}}'
badconf() { printf '%s\nSABHA_IMPL=%s\n' "$1" "$I" > "$dir/bad.conf"; out=$(SABHA_CONF=$dir/bad.conf "$SH" "$BIN/sabha-relay-guard" pre <<<"${2:-$EDIT_IN}" 2>&1); rc=$?; }
badconf 'SABHA_X=$NOPE_UNSET_VAR'
check "conf with an unbound variable: pre denies (rc 2)" '(( rc == 2 )) && [[ $out == *"brief the dispatcher"* ]]'
badconf 'exit 3'
check "conf that exits: pre denies (rc 2)" '(( rc == 2 )) && [[ $out == *"brief the dispatcher"* ]]'
badconf 'exit 100' '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}'
check "conf that exits 100 (the allow code): pre denies" '(( rc == 2 ))'
badconf 'exit 0' '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
check "conf that exits 0 early: pre denies (no values came back)" '(( rc == 2 ))'
badconf "trap 'exit 100' EXIT" '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}'
check "conf with an exit-100 trap: pre denies" '(( rc == 2 ))'
badconf 'false' '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
check "conf with a failing command still lets Read through" '(( rc == 0 ))'
hook pre ''
check "empty stdin: pre denies" '(( rc == 2 )) && [[ $err == "relay: brief the dispatcher"* ]]'
hook pre '{"tool_name":"Bash","tool_input":{}}'
check "Bash with no command field: denied" '(( rc == 2 ))'
hook pre '{"tool_name":"Write","tool_input":{}}'
check "Write with no file_path: denied" '(( rc == 2 ))'
hook pre '{"tool_name":"Bash","tool_input":{"command":5}}'
check "Bash with a non-string command: denied" '(( rc == 2 ))'
hook pre '[1,2'
check "truncated JSON: denied" '(( rc == 2 ))'

out=$(SABHA_RELAY_GUARD=1 "$SH" "$BIN/sabha-up.sh" --print Vidur 2>&1)
json=$(sed -n "s/.* --settings '\([^']*\)'.*/\1/p" <<<"$out")
check "sabha-up --print: the relay gets --settings with the guard hooks" '[[ -n $json ]] && jq -e --arg g "\"$BIN/sabha-relay-guard\" pre Vidur" --arg s "\"$BIN/sabha-relay-guard\" start" ".hooks.PreToolUse[0].matcher == \"*\" and .hooks.PreToolUse[0].hooks[0].command == \$g and (.hooks.UserPromptSubmit | length) == 1 and (.hooks.Stop | length) == 1 and .hooks.SessionStart[0].hooks[0].command == \$s" <<<"$json" >/dev/null'
out=$(SABHA_RELAY_GUARD=1 "$SH" "$BIN/sabha-up.sh" --print Yudhi 2>&1)
check "sabha-up --print: the dispatcher gets no guard" '! grep -q -- --settings <<<"$out"'
out=$("$SH" "$BIN/sabha-up.sh" --print Vidur 2>&1)
check "flag off: the relay gets no guard" '! grep -q -- --settings <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
