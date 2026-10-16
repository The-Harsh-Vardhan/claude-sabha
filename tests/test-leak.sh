#!/usr/bin/env bash
# Fails when a tracked file carries an owner name, a home path, an employer or product name, a sheet id, a token or a
# peer id. Patterns are shapes or public names only; add new ones to PATTERNS. Run: tests/test-leak.sh
set -u
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
self=tests/test-leak.sh
ALLOW_LICENSE='3:Copyright (c) 2026 Harsh Vardhan'
re=$(IFS='|'; echo "${PATTERNS[*]}")
fail=0
while IFS= read -r f; do
  [[ $f == "$self" || ! -f $f ]] && continue
  hits=$(grep -I -n -i -E -e "$re" -- "$f" | cut -c1-120)
  # the only allowed hit: the owner's name on the LICENSE copyright line
  [[ $f == LICENSE ]] && hits=$(printf '%s\n' "$hits" | grep -v -x -F "$ALLOW_LICENSE")
  if [[ -n $hits ]]; then
    printf 'LEAK %s\n%s\n' "$f" "$hits"
    fail=1
  fi
done < <(git ls-files)
if (( fail )); then echo "FAIL: leak test"; exit 1; fi
echo "PASS: leak test"
