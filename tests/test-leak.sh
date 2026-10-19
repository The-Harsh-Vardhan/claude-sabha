#!/usr/bin/env bash
# Fails when a tracked file carries an owner name, a home path, an employer or product name, a sheet id, a token or a
# peer id. Patterns are shapes or public names only; add new ones to PATTERNS. Run: tests/test-leak.sh
set -u
export LC_ALL=C
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
PATTERNS=(
  'harsh'
  'vardhan'
  '/Users/[A-Za-z0-9._-]+'
  '/home/[A-Za-z0-9._-]+'
  'C:\\Users\\'
  'product-name'
  'employer-name'
  'docs\.google\.com/(spreadsheets|document)/d/[A-Za-z0-9_-]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'xox[abprs]-[A-Za-z0-9-]{10,}'
  'AKIA[0-9A-Z]{16}'
  'sk-[A-Za-z0-9_-]{20,}'
  'AIza[0-9A-Za-z_-]{30,}'
  '[Pp]eer[_-]?[Ii][Dd][:= "]+[A-Za-z0-9]{6,}'
)
root=$(cd "$(dirname "$0")/.." && pwd) || exit 1
cd "$root" || exit 1
# real employer, product and owner names live in an untracked file (one ERE per line, # comments allowed), so no tracked
# file names them. Default local/leak-patterns (gitignored); SABHA_LEAK_PATTERNS points other worktrees at one shared file
local_patterns=${SABHA_LEAK_PATTERNS:-$root/local/leak-patterns}
if [[ -f $local_patterns ]]; then
  while IFS= read -r p; do [[ -n $p && $p != \#* ]] && PATTERNS+=("$p"); done < "$local_patterns"
else
  echo "note: $local_patterns missing, so employer and product names are not checked"
fi
self=tests/test-leak.sh
ALLOW_LICENSE='3:Copyright (c) 2026 Harsh Vardhan'
# the plugin manifests may carry the owner's name in their author/owner "name" field and nowhere else
ALLOW_AUTHOR='^[0-9]+: *"name": "Harsh Vardhan",?$'
re=$(IFS='|'; echo "${PATTERNS[*]}")
# allow <file> <hits>: drops the allowed hits for that file, prints the rest
allow() {
  case $1 in
    LICENSE) printf '%s\n' "$2" | grep -v -x -F "$ALLOW_LICENSE" ;;
    .claude-plugin/plugin.json|.claude-plugin/marketplace.json) printf '%s\n' "$2" | grep -v -E "$ALLOW_AUTHOR" ;;
    *) printf '%s\n' "$2" ;;
  esac
}
# self-check: the name stays caught outside the allowed fields and files
[[ -n $(allow .claude-plugin/plugin.json '7:    "description": "by Harsh Vardhan"') ]] || { echo "FAIL: author allow is too wide"; exit 1; }
[[ -n $(allow README.md '1:    "name": "Harsh Vardhan"') ]] || { echo "FAIL: author allow leaks into other files"; exit 1; }
fail=0
while IFS= read -r f; do
  [[ $f == "$self" || ! -f $f ]] && continue
  # the repo slug, the Pages host and the owner's profile link carry the public handle by design; strip exactly those
  hits=$(sed -e 's#The-Harsh-Vardhan/claude-sabha##g' -e 's#the-harsh-vardhan\.github\.io##g' \
    -e 's#\[@The-Harsh-Vardhan\](https://github\.com/The-Harsh-Vardhan)##g' -- "$f" | grep -I -n -i -E -e "$re" | cut -c1-120)
  hits=$(allow "$f" "$hits")
  if [[ -n $hits ]]; then
    printf 'LEAK %s\n%s\n' "$f" "$hits"
    fail=1
  fi
done < <(git ls-files)
if (( fail )); then echo "FAIL: leak test"; exit 1; fi
echo "PASS: leak test"
