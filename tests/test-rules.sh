#!/usr/bin/env bash
# hooks/sabha-rules.sh on hook JSON: the ASCII, attribution, shared-push and secret-read rules, each allowed and denied,
# the SABHA_RULES switch and the conf keys. Uses temp git repos only; no network, no claude, no herdr.
# Run: tests/test-rules.sh
# shellcheck disable=SC2016,SC1091  # the checks are eval strings, expanded when they run
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

# switches and edges
check "SABHA_RULES limits the rules" 'SABHA_RULES="ascii" allows bash_in "git push origin main"'
check "SABHA_RULES keeps the named rule" 'SABHA_RULES="shared-push" denies bash_in "git push origin main"'
check "a tool the hook does not know passes" 'allows run WebFetch url "https://example.com/.env"'
printf 'SABHA_RULES="secret-read"\nSABHA_SHARED_BRANCHES="x"\n' >"$dir/sabha.conf"
check "conf SABHA_RULES is read" 'SABHA_CONF=$dir/sabha.conf allows bash_in "git push origin main"'
check "env wins over the conf" 'SABHA_CONF=$dir/sabha.conf SABHA_RULES=shared-push SABHA_SHARED_BRANCHES=main denies bash_in "git push origin main"'
check "malformed JSON is an unknown tool and passes" 'err=$(printf "{" | bash "$hook" 2>&1 >/dev/null); [[ $? == 0 ]]'
mkdir -p "$dir/nojq"
check "no jq denies" 'err=$(printf "{}" | PATH=$dir/nojq /bin/bash "$hook" 2>&1 >/dev/null); [[ $? == 2 && $err == *"jq is missing"* ]]'

echo
if (( fails == 0 )); then echo "test-rules: all passed"; else echo "test-rules: $fails failed"; exit 1; fi
