#!/usr/bin/env bash
# SessionStart: stdout becomes context. A role restarts from its files, so the handoff and open briefs are injected.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0
hk_init || exit 0

sf=$(hk_status_file)
echo "[sabha] You are $HK_ROLE. Resume from the files below. Never use --resume; state lives in $HK_IMPL, not in chat."
if [ -f "$sf" ]; then
  body=$(awk '
    /^#+[[:space:]]/ { show = ($0 ~ /^#+[[:space:]]*(Task|Next|Constraints)/) }
    show' "$sf" 2>/dev/null | head -n 60)
  [ -n "$body" ] || body=$(head -n 60 "$sf")
  printf '\nHandoff (%s):\n%s\n' "$sf" "$body"
else
  printf '\nNo handoff file yet at %s.\n' "$sf"
fi
open=$(hk_open_briefs all)
if [ -n "$open" ]; then
  printf '\nOpen briefs in %s/inbox/%s (no .done yet):\n' "$HK_IMPL" "$HK_ROLE"
  printf '%s\n' "$open" | sed 's/^/- /'
else
  printf '\nNo open briefs in your inbox.\n'
fi
exit 0
