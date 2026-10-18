#!/usr/bin/env bash
# share/claude-settings.json parses and denies push (also git -C), remote add/set-url, gh pr and gh release/repo/issue/api writes, every rm -rf spelling, Bash reads of env and
# npmrc files, and Read of env, npmrc and key files. One line per rule in RULES. Run: tests/test-deny.sh
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
RULES=(
  'Bash(git push:*)'
  'Bash(git -C * push:*)'
  'Bash(gh pr:*)'
  'Bash(git remote add:*)'
  'Bash(git remote set-url:*)'
  'Bash(gh release create:*)'
  'Bash(gh release upload:*)'
  'Bash(gh release delete:*)'
  'Bash(gh repo create:*)'
  'Bash(gh repo edit:*)'
  'Bash(gh repo delete:*)'
  'Bash(gh issue create:*)'
  'Bash(gh issue comment:*)'
  'Bash(gh api -X:*)'
  'Bash(gh api --method:*)'
  'Bash(rm -rf:*)'
  'Bash(rm -fr:*)'
  'Bash(rm -r -f:*)'
  'Bash(rm -f -r:*)'
  'Bash(cat *.env*)'
  'Bash(head *.env*)'
  'Bash(tail *.env*)'
  'Bash(less *.env*)'
  'Bash(grep * *.env*)'
  'Bash(source *.env*)'
  'Bash(cat *.npmrc*)'
  'Read(**/.env)'
  'Read(**/.env.*)'
  'Read(**/.npmrc)'
  'Read(**/*.pem)'
  'Read(**/*.key)'
  'Read(**/id_rsa*)'
  'Read(**/id_ed25519*)'
)
root=$(cd "$(dirname "$0")/.." && pwd) || exit 1
f=$root/share/claude-settings.json
command -v jq >/dev/null || { echo "FAIL: jq missing"; exit 1; }
jq -e . "$f" >/dev/null || { echo "FAIL: $f does not parse"; exit 1; }
fail=0
for rule in "${RULES[@]}"; do
  if ! jq -e --arg r "$rule" '.permissions.deny | index($r)' "$f" >/dev/null; then
    echo "FAIL: missing deny rule $rule"; fail=1
  fi
done
(( fail )) && exit 1
echo "PASS: deny list (${#RULES[@]} rules)"
