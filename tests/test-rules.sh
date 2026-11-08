#!/usr/bin/env bash
# hooks/sabha-rules.sh on hook JSON: the ASCII, attribution, shared-push and secret-read rules, each allowed and denied,
# the SABHA_RULES switch and the conf keys. Uses temp git repos only; no network, no claude, no herdr.
# Run: tests/test-rules.sh
# shellcheck disable=SC2016,SC1091,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
hook=$(cd "$(dirname "$0")/../hooks" && pwd)/sabha-rules.sh
command -v jq >/dev/null || { echo "FAIL: jq missing"; exit 1; }
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rules.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

# two repos: one on a shared branch, one on a feature branch
for r in shared feat; do
  git init -q "$dir/$r" && git -C "$dir/$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
done
git -C "$dir/shared" checkout -q -B main
git -C "$dir/feat" checkout -q -B feat/x

# run <tool> <key> <value> [cwd]: sets rc and err
run() {
  local j
  j=$(jq -cn --arg t "$1" --arg k "$2" --arg v "$3" --arg c "${4:-$dir/feat}" '{tool_name: $t, cwd: $c, tool_input: {($k): $v}}')
  err=$(printf '%s' "$j" | bash "$hook" 2>&1 >/dev/null); rc=$?
}
bash_in() { run Bash command "$1" "${2:-}"; }
# raw <stdin text>: feeds the text to the hook as it is, for bad-input rows
raw() { err=$(printf '%s' "$1" | bash "$hook" 2>&1 >/dev/null); rc=$?; }
allows() { "$@"; (( rc == 0 )); }
denies() { "$@"; (( rc == 2 )) && [[ $err == sabha-rules:* ]]; }
rule() { [[ $err == "sabha-rules: $1:"* ]]; }

# ascii
check "Write plain text allowed" 'allows run Write content "hello -> world"'
check "Write with an arrow char denied" 'denies run Write content "a $(printf "\xe2\x86\x92") b" && rule ascii'
check "Edit with an em dash denied" 'denies run Edit new_string "a $(printf "\xe2\x80\x94") b" && rule ascii'
check "commit message with non-ASCII denied" 'denies bash_in "git commit -m \"fix $(printf "\xe2\x80\x94") it\"" && rule ascii'
check "plain non-ASCII text in a bare echo allowed" 'allows bash_in "echo $(printf "\xc3\xa9")"'
j=$(jq -cn '{tool_name:"Write", tool_input:{file_path:"/w/vendor/a.md", content:"caf\u00e9"}}')
check "exempt glob matches the file path" 'printf "%s" "$j" | SABHA_ASCII_EXEMPT="*/vendor/*" bash "$hook" >/dev/null 2>&1'
check "non-exempt path still denied" '! (printf "%s" "$j" | SABHA_ASCII_EXEMPT="*/other/*" bash "$hook" >/dev/null 2>&1)'

# attribution
check "commit with Co-Authored-By denied" 'denies bash_in "git commit -m \"x\" -m \"Co-Authored-By: Someone <a@b.c>\"" && rule attribution'
check "commit heredoc with a generated-with line denied" 'denies bash_in "git commit -F - <<EOF
fix
Generated with Claude Code
EOF" && rule attribution'
check "gh pr create body with the marker denied" 'denies bash_in "gh pr create --body \"Generated with [Claude Code](x)\"" && rule attribution'
check "clean commit allowed" 'allows bash_in "git commit -m \"feat(x): add y\""'
check "file line starting with the marker denied" 'denies run Write content "notes
Co-Authored-By: A <a@b.c>" && rule attribution'
check "file text that discusses the rule allowed" 'allows run Write content "- No Co-Authored-By trailer in commits"'
check "a non-commit command mentioning it allowed" 'allows bash_in "grep -rn co-authored-by docs"'

# shared-push
check "git push origin main denied" 'denies bash_in "git push origin main" && rule shared-push'
check "git push origin HEAD:dev denied" 'denies bash_in "git push origin HEAD:dev" && rule shared-push'
check "git push origin +feat:release/arcus-sprint-3 denied" 'denies bash_in "git push origin +feat:release/arcus-sprint-3" && rule shared-push'
check "git push origin refs/heads/staging denied" 'denies bash_in "git push origin refs/heads/staging" && rule shared-push'
check "git push --all denied" 'denies bash_in "git push --all origin" && rule shared-push'
check "git push --mirror denied" 'denies bash_in "git push --mirror" && rule shared-push'
check "git push --delete origin dev denied" 'denies bash_in "git push --delete origin dev" && rule shared-push'
check "quoted refspec denied" 'denies bash_in "git push origin \"HEAD:main\"" && rule shared-push'
check "chained push denied" 'denies bash_in "cd a && git -C /x push origin master" && rule shared-push'
check "bare git push on a shared branch denied" 'denies bash_in "git push" "$dir/shared" && rule shared-push'
check "bare push with -C into a shared checkout denied" 'denies bash_in "git -C $dir/shared push -u origin HEAD" && rule shared-push'
check "bare git push on a feature branch allowed" 'allows bash_in "git push"'
check "push of the feature branch allowed" 'allows bash_in "git push -u origin feat/x"'
check "HEAD refspec on a feature branch allowed" 'allows bash_in "git push origin HEAD"'
check "an option value is not a refspec" 'allows bash_in "git push -o ci.skip origin feat/x"'
check "release lookalike allowed" 'allows bash_in "git push origin releases-notes"'
check "commit message naming a push allowed" 'allows bash_in "git commit -m \"docs: never git push origin main\""'
check "git status and log allowed" 'allows bash_in "git status && git log --oneline"'
check "SABHA_SHARED_BRANCHES replaces the list" 'SABHA_SHARED_BRANCHES="trunk" allows bash_in "git push origin main"'
check "SABHA_SHARED_BRANCHES names its own branch" 'SABHA_SHARED_BRANCHES="trunk" denies bash_in "git push origin trunk"'

# secret-read
for f in .env .env.local .npmrc id_rsa x.pem .aws/credentials .testsigma-github.env .ENV creds; do
  check "Read $f denied" 'denies run Read file_path "/w/$f" && rule secret-read'
done
check "Read .env.example allowed" 'allows run Read file_path "/w/.env.example"'
check "Read ordinary file allowed" 'allows run Read file_path "/w/src/env.ts"'
check "Grep glob naming .env denied" 'denies run Grep glob ".env*" && rule secret-read'
check "Glob pattern **/.env denied" 'denies run Glob pattern "**/.env" && rule secret-read'
check "cat .env denied" 'denies bash_in "cat .env" && rule secret-read'
check "source ./.env.local denied" 'denies bash_in "set -a; . ./.env.local" && rule secret-read'
check "grep -f=.npmrc denied" 'denies bash_in "grep x --file=.npmrc" && rule secret-read'
check "quoted .env denied" 'denies bash_in "cat \"/w/.env\"" && rule secret-read'
check "cp of a secret into a worktree allowed" 'allows bash_in "cp /ws/guardians/.npmrc /ws/worktrees/x/"'
check "cp then cat .npmrc denied" 'denies bash_in "cp a b && cat .npmrc" && rule secret-read'
check "process.env in a pattern allowed" 'allows bash_in "grep -rn process.env src"'
check "cat .env.example allowed" 'allows bash_in "cat .env.example"'
check ".gitignore listing allowed" 'allows bash_in "cat .gitignore"'

# review 218 M1: the directory a push runs in (cd, pushd, popd, -C, GIT_DIR); unknown directory + no named branch = denied
bt='`'
check "M1 cd shared && push origin HEAD denied" 'denies bash_in "cd $dir/shared && git push origin HEAD" && rule shared-push'
check "M1 cd shared && bare push denied" 'denies bash_in "cd $dir/shared && git push" && rule shared-push'
check "M1 cd shared; push -u origin HEAD denied" 'denies bash_in "cd $dir/shared; git push -u origin HEAD" && rule shared-push'
check "M1 pushd shared && push denied" 'denies bash_in "pushd $dir/shared && git push" && rule shared-push'
check "M1 relative cd into a shared checkout denied" 'denies bash_in "cd ../shared && git push origin HEAD" && rule shared-push'
check "M1 cd then -C chain denied" 'denies bash_in "cd $dir && git -C shared push" && rule shared-push'
check "M1 cd to a variable then bare push denied" 'denies bash_in "cd \"\$X\" && git push" && rule shared-push'
check "M1 cd - then push origin HEAD denied" 'denies bash_in "cd - && git push origin HEAD" && rule shared-push'
check "M1 cd to a missing dir then bare push denied" 'denies bash_in "cd $dir/nowhere && git push" && rule shared-push'
check "M1 popd then push denied" 'denies bash_in "popd && git push origin HEAD" && rule shared-push'
check "M1 GIT_DIR then push origin HEAD denied" 'denies bash_in "GIT_DIR=$dir/shared/.git git push origin HEAD" && rule shared-push'
check "M1 -C to a missing dir denied" 'denies bash_in "git -C $dir/nowhere push origin HEAD" && rule shared-push'
check "M1 unknown dir but a named own branch allowed" 'allows bash_in "cd \"\$X\" && git push origin feat/y"'
check "M1 cd into a feature checkout from a shared cwd allowed" 'allows bash_in "cd $dir/feat && git push origin HEAD" "$dir/shared"'
check "M1 cd into a feature checkout then bare push allowed" 'allows bash_in "cd $dir/feat && git push" "$dir/shared"'
check "M1 cd away from a shared cwd then back to feature allowed" 'allows bash_in "cd $dir/shared && cd $dir/feat && git push" "$dir/shared"'

# review 218 M2: git as a command word in any position, with any options before the subcommand
check "M2 git -c k=v push denied" 'denies bash_in "git -c push.default=current push origin main" && rule shared-push'
check "M2 path-prefixed git denied" 'denies bash_in "/usr/bin/git push origin main" && rule shared-push'
check "M2 subshell denied" 'denies bash_in "(git push origin main)" && rule shared-push'
check "M2 command substitution denied" 'denies bash_in "echo \$(git push origin main)" && rule shared-push'
check "M2 command substitution in double quotes denied" 'denies bash_in "echo \"\$(git push origin main)\"" && rule shared-push'
check "M2 backticks denied" 'denies bash_in "echo ${bt}git push origin main${bt}" && rule shared-push'
check "M2 --repo=origin main denied" 'denies bash_in "git push --repo=origin main" && rule shared-push'
check "M2 --repo origin main denied" 'denies bash_in "git push --repo origin main" && rule shared-push'
check "M2 --git-dir=x push denied" 'denies bash_in "git --git-dir=$dir/shared/.git push origin main" && rule shared-push'
check "M2 -C and -c together denied" 'denies bash_in "git -C $dir/feat -c a=b push origin main" && rule shared-push'
check "M2 env prefix and wrapper denied" 'denies bash_in "FOO=1 command git push origin main" && rule shared-push'
check "M2 xargs git push denied" 'denies bash_in "echo origin | xargs git push --all" && rule shared-push'
check "M2 sh -c unwrapped denied" 'denies bash_in "sh -c \"git push origin main\"" && rule shared-push'
check "M2 bash -lc unwrapped denied" 'denies bash_in "bash -lc '"'"'git push origin master'"'"'" && rule shared-push'
check "M2 eval unwrapped denied" 'denies bash_in "eval \"git push origin dev\"" && rule shared-push'
check "M2 glob refspec denied" 'denies bash_in "git push origin refs/heads/*:refs/heads/*" && rule shared-push'
check "M2 variable refspec denied" 'denies bash_in "B=main; git push origin \$B" && rule shared-push'
check "M2 git -c k=v push of an own branch allowed" 'allows bash_in "git -c push.default=current push origin feat/x"'
check "M2 path-prefixed git on an own branch allowed" 'allows bash_in "/usr/bin/git push -u origin feat/x"'
check "M2 subshell push of an own branch allowed" 'allows bash_in "(git push origin feat/x)"'
check "M2 --repo with an own branch allowed" 'allows bash_in "git push --repo=origin feat/x"'
check "M2 sh -c push of an own branch allowed" 'allows bash_in "sh -c \"git push origin feat/x\""'
check "M2 commit message naming sh -c push allowed" 'allows bash_in "git commit -m \"docs: sh -c git push origin main is blocked\""'
check "M2 git -c k=v commit allowed" 'allows bash_in "git -c user.name=x commit -m \"feat: x\""'

# review 218 M3: gh api writes that move a ref or merge; a plain read passes
check "M3 gh api -X PUT pulls merge denied" 'denies bash_in "gh api -X PUT repos/o/r/pulls/1/merge" && rule shared-push'
check "M3 gh api --method DELETE refs denied" 'denies bash_in "gh api --method DELETE repos/o/r/git/refs/heads/dev" && rule shared-push'
check "M3 gh api -X POST refs -f denied" 'denies bash_in "gh api -X POST repos/o/r/git/refs -f ref=refs/heads/dev -f sha=abc" && rule shared-push'
check "M3 gh api -X PATCH refs denied" 'denies bash_in "gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc" && rule shared-push'
check "M3 gh api implicit POST through -f denied" 'denies bash_in "gh api repos/o/r/git/refs -f ref=refs/heads/dev -f sha=abc" && rule shared-push'
check "M3 gh api implicit POST through -F denied" 'denies bash_in "gh api repos/o/r/merges -F base=main -F head=x" && rule shared-push'
check "M3 gh api --method=PUT merge denied" 'denies bash_in "gh api --method=PUT repos/o/r/pulls/1/merge" && rule shared-push'
check "M3 gh api -XPUT merge denied" 'denies bash_in "gh api -XPUT repos/o/r/pulls/1/merge" && rule shared-push'
check "M3 gh api contents write denied" 'denies bash_in "gh api -X PUT repos/o/r/contents/a.txt -f message=x" && rule shared-push'
check "M3 gh api graphql merge mutation denied" 'denies bash_in "gh api graphql -f query=\"mutation { mergePullRequest(input: {pullRequestId: x}) { clientMutationId } }\"" && rule shared-push'
check "M3 /usr/bin/gh api write denied" 'denies bash_in "/usr/bin/gh api -X PUT repos/o/r/pulls/1/merge" && rule shared-push'
check "M3 gh api plain GET allowed" 'allows bash_in "gh api repos/o/r/pulls/1"'
check "M3 gh api GET of refs allowed" 'allows bash_in "gh api repos/o/r/git/refs/heads/main"'
check "M3 gh api -X GET with -f allowed" 'allows bash_in "gh api -X GET search/issues -f q=x"'
check "M3 gh api POST comment (not a ref) allowed" 'allows bash_in "gh api -X POST repos/o/r/issues/1/comments -f body=x"'
check "M3 gh pr merge (the reviewed route) allowed" 'allows bash_in "gh pr merge 5 --squash"'
check "M3 gh api graphql query allowed" 'allows bash_in "gh api graphql -f query=\"query { viewer { login } }\""'

# review 218 M4: secrets from the environment
check "M4 env | grep TOKEN denied" 'denies bash_in "env | grep TOKEN" && rule secret-read'
check "M4 bare env denied" 'denies bash_in "env" && rule secret-read'
check "M4 env -0 denied" 'denies bash_in "env -0" && rule secret-read'
check "M4 (env) denied" 'denies bash_in "(env)" && rule secret-read'
check "M4 printenv NPM_TOKEN denied" 'denies bash_in "printenv NPM_TOKEN" && rule secret-read'
check "M4 printenv GITHUB_TOKEN denied" 'denies bash_in "printenv GITHUB_TOKEN" && rule secret-read'
check "M4 bare printenv denied" 'denies bash_in "printenv | sort" && rule secret-read'
check "M4 echo \$NPM_TOKEN denied" 'denies bash_in "echo \$NPM_TOKEN" && rule secret-read'
check "M4 echo quoted \$GH_TOKEN denied" 'denies bash_in "echo \"\$GH_TOKEN\"" && rule secret-read'
check "M4 echo braced token denied" 'denies bash_in "echo \${GITHUB_TOKEN}" && rule secret-read'
check "M4 printf of a secret var denied" 'denies bash_in "printf %s \$AWS_SECRET_ACCESS_KEY" && rule secret-read'
check "M4 echo of a password var denied" 'denies bash_in "echo \$DB_PASSWORD" && rule secret-read'
check "M4 substitution of printenv denied" 'denies bash_in "x=\$(printenv NPM_TOKEN)" && rule secret-read'
check "M4 env VAR=x printenv TOKEN denied" 'denies bash_in "env A=1 printenv NPM_TOKEN" && rule secret-read'
check "M4 set | grep -i token denied" 'denies bash_in "set | grep -i token" && rule secret-read'
check "M4 export -p denied" 'denies bash_in "export -p" && rule secret-read'
check "M4 bare export denied" 'denies bash_in "export" && rule secret-read'
check "M4 declare -x denied" 'denies bash_in "declare -x" && rule secret-read'
check "M4 declare -p denied" 'denies bash_in "declare -p | grep KEY" && rule secret-read'
check "M4 cat /proc/self/environ denied" 'denies bash_in "cat /proc/self/environ" && rule secret-read'
check "M4 tr on /proc/PID/environ denied" 'denies bash_in "tr \"\\0\" \"\\n\" < /proc/123/environ" && rule secret-read'
check "M4 gh auth token denied" 'denies bash_in "gh auth token" && rule secret-read'
check "M4 gh auth status --show-token denied" 'denies bash_in "gh auth status --show-token" && rule secret-read'
check "M4 cat ~/.config/gh/hosts.yml denied" 'denies bash_in "cat ~/.config/gh/hosts.yml" && rule secret-read'
check "M4 Read gh hosts.yml denied" 'denies run Read file_path "/u/.config/gh/hosts.yml" && rule secret-read'
check "M4 env VAR=x cmd allowed" 'allows bash_in "env FOO=1 ls"'
check "M4 env -i VAR=x cmd allowed" 'allows bash_in "env -i FOO=1 ls"'
check "M4 printenv HOME allowed" 'allows bash_in "printenv HOME"'
check "M4 echo \$HOME allowed" 'allows bash_in "echo \$HOME \$PWD"'
check "M4 export NAME=value allowed" 'allows bash_in "export FOO=bar"'
check "M4 set -e allowed" 'allows bash_in "set -e"'
check "M4 declare -A allowed" 'allows bash_in "declare -A m"'
check "M4 gh auth status allowed" 'allows bash_in "gh auth status"'
check "M4 the word env in a grep allowed" 'allows bash_in "grep -rn env docs"'

# review 218 M5: a copy of a secret file lets it out unless it is the one intended shape
check "M5 cp .env /dev/stdout denied" 'denies bash_in "cp .env /dev/stdout" && rule secret-read'
check "M5 cp .env /dev/fd/1 denied" 'denies bash_in "cp .env /dev/fd/1" && rule secret-read'
check "M5 cp .env t && cat t denied" 'denies bash_in "cp .env t && cat t" && rule secret-read'
check "M5 cp .npmrc /tmp/n; cat /tmp/n denied" 'denies bash_in "cp .npmrc /tmp/n; cat /tmp/n" && rule secret-read'
check "M5 cp .env dir/ then cat dir/* denied" 'denies bash_in "cp .env x/ && cat x/*" && rule secret-read'
check "M5 cp -a of a secret denied" 'denies bash_in "cp -a .env t" && rule secret-read'
check "M5 cp -t dir .env denied" 'denies bash_in "cp -t d .env" && rule secret-read'
check "M5 cp of two sources with a secret denied" 'denies bash_in "cp a .env d/" && rule secret-read'
check "M5 cp to /dev/ dir denied" 'denies bash_in "cp .npmrc /dev/" && rule secret-read'
check "M5 path-prefixed cp of a secret denied" 'denies bash_in "/bin/cp .env /dev/stdout" && rule secret-read'
check "M5 cp .npmrc into a worktree then an unrelated command allowed" 'allows bash_in "cp /ws/guardians/.npmrc /ws/worktrees/x/ && ls /ws/other"'
check "M5 cp keeping the secret name allowed" 'allows bash_in "cp /a/.npmrc /b/.npmrc"'
check "M5 cp of a template to .env allowed" 'allows bash_in "cp .env.example .env"'
check "M5 cp of ordinary files allowed" 'allows bash_in "cp -r src dist/"'

# review 218 M6: bad input fails closed; an unknown tool passes only after a good parse
check "M6 empty stdin denied" 'denies raw ""'
check "M6 lone { denied" 'denies raw "{"'
check "M6 truncated JSON denied" 'denies raw "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\""'
check "M6 JSON array root denied" 'denies raw "[]"'
check "M6 JSON string root denied" 'denies raw "\"Bash\""'
check "M6 empty object denied" 'denies raw "{}"'
check "M6 tool_name a number denied" 'denies raw "{\"tool_name\":5}"'
check "M6 Bash tool_input null denied" 'denies raw "{\"tool_name\":\"Bash\",\"tool_input\":null}"'
check "M6 Bash command a number denied" 'denies raw "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":5}}"'
check "M6 Bash command an array denied" 'denies raw "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":[\"ls\"]}}"'
check "M6 Bash command missing denied" 'denies raw "{\"tool_name\":\"Bash\",\"tool_input\":{}}"'
check "M6 Read file_path an object denied" 'denies raw "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":{}}}"'
check "M6 Write content an array denied" 'denies raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"a\",\"content\":[1]}}"'
check "M6 MultiEdit edits not an array denied" 'denies raw "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"a\",\"edits\":5}}"'
check "M6 lone surrogate denied" 'denies raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"a\",\"content\":\"\\ud800\"}}"'
check "M6 cwd a number denied" 'denies raw "{\"tool_name\":\"Bash\",\"cwd\":5,\"tool_input\":{\"command\":\"ls\"}}"'
check "M6 unknown tool after a good parse passes" 'allows raw "{\"tool_name\":\"WebFetch\",\"tool_input\":null}"'
check "M6 unknown tool with no tool_input passes" 'allows raw "{\"tool_name\":\"Task\"}"'
check "M6 a unit separator in a value does not shift fields" 'allows raw "{\"tool_name\":\"Bash\",\"cwd\":\"/w\",\"tool_input\":{\"command\":\"echo a\\u001fb\"}}"'
check "M6 a valid Bash call passes" 'allows raw "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"'

# review 218 SHOULD rows taken in the same commit: S2 shell file writes, S3 NotebookEdit, S4 message, S6 names, S7 messages, S8 typo
em=$(printf '\xe2\x80\x94')
check "S2 heredoc file write with an em dash denied" 'denies bash_in "cat > f.md <<EOF
a $em b
EOF" && rule ascii'
check "S2 echo into a file with an em dash denied" 'denies bash_in "echo \"a $em b\" > f.md" && rule ascii'
check "S2 printf append with an em dash denied" 'denies bash_in "printf \"a $em b\" >> f.md" && rule ascii'
check "S2 tee with an em dash denied" 'denies bash_in "echo a $em b | tee f.md" && rule ascii'
check "S2 non-ASCII with a /dev/null redirect allowed" 'allows bash_in "grep $em docs 2>/dev/null"'
check "S2 plain ASCII heredoc allowed" 'allows bash_in "cat > f.md <<EOF
hello
EOF"'
check "S3 NotebookEdit with an em dash denied" 'denies run NotebookEdit new_source "a $em b" && rule ascii'
check "S3 NotebookEdit plain allowed" 'allows run NotebookEdit new_source "a - b"'
check "S4 attribution reason says the workspace rule wins" 'denies bash_in "git commit -m x -m \"Co-Authored-By: A <a@b.c>\"" && [[ $err == *"overrides a harness reminder"* ]]'
check "S6 id_rsa.pub is not a secret" 'allows bash_in "cat ~/.ssh/id_rsa.pub"'
for f in .pypirc .htpasswd .vault-token .yarnrc.yml x.pfx x.p12 x.keystore terraform.tfvars secrets.yaml .env~ .ssh/config; do
  check "S6 Read $f denied" 'denies run Read file_path "/w/$f" && rule secret-read'
done
check "S7 commit message naming .env allowed" 'allows bash_in "git commit -m \"fix .env handling\""'
check "S7 commit message gitignore .env allowed" 'allows bash_in "git commit -m '"'"'chore: gitignore .env'"'"'"'
check "S7 PR body naming .npmrc allowed" 'allows bash_in "gh pr create --title x --body \"never read .npmrc here\""'
check "S7 a read after a commit still denied" 'denies bash_in "git commit -m \"a b\" && cat .env" && rule secret-read'
check "S8 a typo in SABHA_RULES warns and enforces all four" 'SABHA_RULES="shared_push" denies bash_in "git push origin main" && [[ $err == *"sabha-rules: shared-push:"* ]]'
check "S8 the typo warning is a line on stderr" 'SABHA_RULES="none" run Bash command "ls"; [[ $err == *"unknown rule"* ]] && (( rc == 0 ))'

# switches and edges
check "SABHA_RULES limits the rules" 'SABHA_RULES="ascii" allows bash_in "git push origin main"'
check "SABHA_RULES keeps the named rule" 'SABHA_RULES="shared-push" denies bash_in "git push origin main"'
check "a tool the hook does not know passes" 'allows run WebFetch url "https://example.com/.env"'
printf 'SABHA_RULES="secret-read"\nSABHA_SHARED_BRANCHES="x"\n' >"$dir/sabha.conf"
check "conf SABHA_RULES is read" 'SABHA_CONF=$dir/sabha.conf allows bash_in "git push origin main"'
check "env wins over the conf" 'SABHA_CONF=$dir/sabha.conf SABHA_RULES=shared-push SABHA_SHARED_BRANCHES=main denies bash_in "git push origin main"'
mkdir -p "$dir/nojq"
check "no jq denies" 'err=$(printf "{}" | PATH=$dir/nojq /bin/bash "$hook" 2>&1 >/dev/null); [[ $? == 2 && $err == *"jq is missing"* ]]'

echo
if (( fails == 0 )); then echo "test-rules: all passed"; else echo "test-rules: $fails failed"; exit 1; fi
