#!/usr/bin/env bash
# Usage: secret-scan.sh DIR   -> exit 0 clean, exit 1 findings (file:line only, never the value)
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
DIR="${1:?usage: secret-scan.sh DIR}"
rc=0
if command -v gitleaks >/dev/null; then
  if gitleaks help 2>&1 | grep -q '^ *dir '; then
    gitleaks dir "$DIR" --redact --no-banner -l warn >/dev/null 2>&1 || { echo "gitleaks: findings in $DIR (run it by hand with --redact)"; rc=1; }
  else
    gitleaks detect --no-git --source "$DIR" --redact --no-banner -l warn >/dev/null 2>&1 || { echo "gitleaks: findings in $DIR (run it by hand with --redact)"; rc=1; }
  fi
fi
# Strict grep as a second opinion. Prints file and line number only.
PAT='AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}|(pass(word|wd)?|secret|token|api[_-]?key|private[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_.=-]{8,}'
hits=$(grep -rInEi --exclude-dir=.git -e "$PAT" "$DIR" 2>/dev/null | grep -viE '\$\{[A-Z_]+|<[A-Za-z_ -]+>|(password|secret|token|api[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?(env|none|null|false|true|REDACTED|your[-_])' | cut -d: -f1,2 )
if [ -n "$hits" ]; then echo "grep: key-like strings at:"; echo "$hits"; rc=1; fi
exit $rc
