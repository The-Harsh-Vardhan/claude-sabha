#!/usr/bin/env bash
# Sourced by sabha-up.sh and sabha-nudge, never run: the herdr terminal backend (the default on every OS).
# SABHA_BACKEND=iterm keeps the old iTerm2/osascript path (macOS only, frozen). Panes are made with
# `herdr workspace|tab create` and `herdr pane split`; a Claude role runs `sabha-up.sh <Name>` in its pane, any other
# agent (opencode tested; codex, agy, muse UNTESTED) is started with `herdr agent start --kind`. The files under
# SABHA_IMPL stay the source of truth: herdr only nudges and waits. status/herdr-panes.txt maps "RoleId pane_id": emptied
# at grid start, filled as each pane is made, added to by a role that starts inside a pane, pruned against `pane list`
# before each nudge.
# Windows: herdr is native beta there and bash scripts run in Git Bash (Claude Code on Windows needs Git for Windows
# as far as we know; UNTESTED, no Windows machine here). `herdr attach` (VS Code integrated terminal) is Mac/Linux only.
# The JSON keys read below (workspace_id, tab_id, pane_id, root_pane) follow `herdr --skill`; checked against a fake
# herdr only for agent start/prompt/read, send-keys and pane split (UNTESTED live); a real herdr 0.9.4 session confirmed
# the server start, the "status: running" line, workspace create/list, pane list, agent list, workspace close and
# session stop/delete.

sabha_backend() { echo "${SABHA_BACKEND:-herdr}"; }

# sabha_jid <json> <key>: the first "<key>":"value" in the JSON, one line or pretty-printed
sabha_jid() { grep -o "\"$2\" *: *\"[^\"]*\"" <<<"$1" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

# Sabha runs in its OWN herdr session (SABHA_HERDR_SESSION, default "sabha"), never the default one, which holds the
# user's own workspaces. A named session has no server until it is started (sabha_herdr_ready does that). Every herdr
# call goes through sabha_h so it carries --session; `session stop|delete <name>` is the only call that takes the
# name as an argument instead.
# Unset = "sabha"; set-but-empty is refused, not defaulted.
sabha_session() { echo "${SABHA_HERDR_SESSION-sabha}"; }
# sabha_session_valid: the name is [A-Za-z0-9_-]+, does not start with "-" (it would read as a herdr option), and not "default" in any case (herdr's own session, which holds the
# user's workspaces: stopping or deleting it would destroy them). Prints why on stderr and returns 1 otherwise.
sabha_session_valid() {
  local s lower
  s=$(sabha_session)
  lower=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  if [[ -z $s || $s == -* || $s == *[!A-Za-z0-9_-]* || $lower == default ]]; then
    echo "sabha: SABHA_HERDR_SESSION='$s' is refused: use letters, digits, - and _ (not a leading -), and never \"default\" (herdr's own session)" >&2
    return 1
  fi
}
sabha_h() { sabha_session_valid || return 1; herdr --session "$(sabha_session)" "$@"; }

# sabha_herdr_guard: with SABHA_TEST=1 only the herdr binary named by SABHA_HERDR_BIN (tests/hermetic-bin/herdr, a
# fake) may be used; the real one would open workspaces and start real claude sessions on the default herdr session.
sabha_herdr_guard() {
  sabha_session_valid || return 1
  [[ ${SABHA_TEST:-} == 1 ]] || return 0
  [[ -n ${SABHA_HERDR_BIN:-} && $(command -v herdr 2>/dev/null) == "$SABHA_HERDR_BIN" ]] && return 0
  echo "sabha: SABHA_TEST=1 and herdr ($(command -v herdr 2>/dev/null)) is not SABHA_HERDR_BIN (${SABHA_HERDR_BIN:-unset}); refusing to touch a real herdr" >&2
  return 1
}

# sabha_herdr_ready: herdr is installed and its server runs (started headless when it does not)
sabha_herdr_ready() {
  command -v herdr >/dev/null 2>&1 || {
    echo "sabha: herdr not found (brew install herdr, or curl -fsSL https://herdr.dev/install.sh | sh; SABHA_BACKEND=iterm keeps the old macOS path)" >&2
    return 1
  }
  sabha_herdr_guard || return 1
  sabha_h status server 2>&1 | grep -q 'status: running' && return 0
  sabha_h server >/dev/null 2>&1 &
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    sabha_h status server 2>&1 | grep -q 'status: running' && return 0
  done
  echo "sabha: the herdr server did not start" >&2
  return 1
}

# sabha_session_stop: stops and deletes the sabha session and nothing else (the default session is never touched)
sabha_session_stop() {
  local s
  s=$(sabha_session)
  sabha_herdr_guard || return 1
  herdr session stop "$s" >/dev/null 2>&1; herdr session delete "$s" >/dev/null 2>&1
}

# sabha_pane_note <Name> <pane_id>: records which pane holds a role (replaces an older line for that Name)
sabha_pane_note() {
  local f=$SABHA_IMPL/status/herdr-panes.txt
  mkdir -p "$SABHA_IMPL/status"
  { grep -v "^$1 " "$f" 2>/dev/null; echo "$1 $2"; } >"$f.tmp" && mv "$f.tmp" "$f"
}

# sabha_pane_reset: an empty map, for a grid start: the roles of an older grid and their pane ids are gone
sabha_pane_reset() {
  mkdir -p "$SABHA_IMPL/status"
  : >"$SABHA_IMPL/status/herdr-panes.txt"
}

# sabha_pane_prune: drops the map lines whose pane herdr no longer lists (a closed pane id is never reused, so a line
# for a missing id is dead for good), and says so on stderr. A failed `pane list`, or one with no pane id we can read,
# proves nothing and leaves the map alone.
sabha_pane_prune() {
  local f=$SABHA_IMPL/status/herdr-panes.txt out live name pane
  [[ -s $f ]] || return 0
  out=$(sabha_h pane list 2>/dev/null) || return 0
  live=$(grep -o '"pane_id" *: *"[^"]*"' <<<"$out" | sed 's/.*: *"\(.*\)"/\1/') || true
  [[ -n $live ]] || return 0
  : >"$f.tmp"
  while read -r name pane; do
    [[ -n $name ]] || continue
    if grep -qxF "$pane" <<<"$live"; then echo "$name $pane" >>"$f.tmp"
    else echo "sabha: pane $pane of $name is gone; dropped from the pane map" >&2; fi
  done <"$f"
  mv "$f.tmp" "$f"
}

# sabha_nudge <Name> <text>: submits text to that role's agent and waits until it settles (idle, done or blocked).
# The target is the role's live pane from the map, else the lower-case agent name (a role started with `agent start`).
sabha_nudge() {
  local t
  sabha_herdr_guard || return 1
  sabha_pane_prune
  # awk exits 2 on a missing map, which under set -e would end the caller before the fallback below
  t=$(awk -v n="$1" '$1 == n { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null) || t=
  [[ -n $t ]] || t=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  sabha_h agent prompt "$t" "$2" --wait --timeout "${SABHA_NUDGE_TIMEOUT:-120000}"
}

# sabha_target <Name>: the herdr target for a role, its recorded pane, else its lower-case agent name (as sabha_nudge)
sabha_target() {
  local t
  t=$(awk -v n="$1" '$1 == n { p = $2 } END { print p }' "$SABHA_IMPL/status/herdr-panes.txt" 2>/dev/null)
  if [[ -n $t ]]; then echo "$t"; else tr '[:upper:]' '[:lower:]' <<<"$1"; fi
}
