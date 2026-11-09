#!/usr/bin/env bash
# UserPromptSubmit, relay only: stdout becomes context, so the relay sees its own role, session id and cwd before each
# turn (it once confused its session id with another, and a cwd drift ran a command in the wrong folder). Fails soft.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0
hk_init || exit 0
[ "$HK_BASE" = "$HK_RELAY" ] || exit 0
cwd=$(hk_field cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] && { cd "$cwd" 2>/dev/null || :; }
bash "$HK_DIR/../bin/sabha" whoami "$HK_ROLE" 2>/dev/null
exit 0
