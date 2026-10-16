#!/usr/bin/env bash
# Sourced by sabha-up.sh and sabha-nudge, never run: the herdr terminal backend (the default on every OS).
# SABHA_BACKEND=iterm keeps the old iTerm2/osascript path (macOS only, frozen). Panes are made with
# `herdr workspace|tab create` and `herdr pane split`; a Claude role runs `sabha-up.sh <Name>` in its pane, any other
# agent (opencode tested; codex, agy, muse UNTESTED) is started with `herdr agent start --kind`. The files under
# SABHA_IMPL stay the source of truth: herdr only nudges and waits. status/herdr-panes.txt maps "Name pane_id".
# Windows: herdr is native beta there and bash scripts run in Git Bash (Claude Code on Windows needs Git for Windows
# as far as we know; UNTESTED, no Windows machine here). `herdr attach` (VS Code integrated terminal) is Mac/Linux only.
# The JSON keys read below (workspace_id, tab_id, pane_id, root_pane) follow `herdr --skill`; checked against a fake
# herdr only, no live server was run; so is the "status: running" line `herdr status server` prints (UNTESTED live).

sabha_backend() { echo "${SABHA_BACKEND:-herdr}"; }

# sabha_jid <json> <key>: the first "<key>":"value" in the JSON, one line or pretty-printed
sabha_jid() { grep -o "\"$2\" *: *\"[^\"]*\"" <<<"$1" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

# sabha_herdr_ready: herdr is installed and its server runs (started headless when it does not)
sabha_herdr_ready() {
  command -v herdr >/dev/null 2>&1 || {
    echo "sabha: herdr not found (brew install herdr, or curl -fsSL https://herdr.dev/install.sh | sh; SABHA_BACKEND=iterm keeps the old macOS path)" >&2
    return 1
  }
  herdr status server 2>&1 | grep -q 'status: running' && return 0
  herdr server >/dev/null 2>&1 &
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    herdr status server 2>&1 | grep -q 'status: running' && return 0
  done
  echo "sabha: the herdr server did not start" >&2
  return 1
}

# sabha_pane_note <Name> <pane_id>: records which pane holds a role (replaces an older line for that Name)
sabha_pane_note() {
  local f=$SABHA_IMPL/status/herdr-panes.txt
  mkdir -p "$SABHA_IMPL/status"
  { grep -v "^$1 " "$f" 2>/dev/null; echo "$1 $2"; } >"$f.tmp" && mv "$f.tmp" "$f"
}

# sabha_nudge <Name> <text>: submits text to that role's agent and waits until it settles (idle, done or blocked)
sabha_nudge() {
  local t
  t=$(awk -v n="$1" '$1 == n { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null)
  [[ -n $t ]] || t=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  herdr agent prompt "$t" "$2" --wait --timeout "${SABHA_NUDGE_TIMEOUT:-120000}"
}
