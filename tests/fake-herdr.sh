#!/usr/bin/env bash
# A stand-in for herdr (reached through tests/hermetic-bin/herdr, or copied as "herdr" by a test): logs every call
# with the --session flag stripped to $FAKE_HERDR_LOG (the command), and the raw argv to $FAKE_HERDR_CALLS, so a test
# can check that no call lacks --session. Answers with the JSON shapes observed on a real herdr 0.9.4 (workspace
# create, workspace list, pane list, agent list, the server_not_running error); agent start/prompt/read, send-keys and
# pane split are still guesses (UNTESTED). A named session has no server until `server` runs: state is a file per
# session under $FAKE_HERDR_DIR. Ids come from a counter file there.
: "${FAKE_HERDR_LOG:=/dev/null}" "${FAKE_HERDR_CALLS:=/dev/null}"
echo "$*" >>"$FAKE_HERDR_CALLS"
S=""
if [[ ${1:-} == --session ]]; then S=$2; shift 2; fi
echo "$*" >>"$FAKE_HERDR_LOG"
# a herdr that reads its stdin (FAKE_HERDR_EAT_STDIN=1): a caller inside a `while read` loop must give it /dev/null
[[ ${FAKE_HERDR_EAT_STDIN:-} == 1 ]] && cat >/dev/null
state=$FAKE_HERDR_DIR/server-${S:-default}
next() { local n; n=$(cat "$FAKE_HERDR_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$FAKE_HERDR_DIR/n"; echo "$n"; }
case "$1 $2" in
  "session stop"|"session delete") rm -f "$FAKE_HERDR_DIR/server-$3"; exit 0 ;;
  "session list") echo "NAME STATUS"; exit 0 ;;
esac
if [[ $1 == server ]]; then : >"$state"; exit 0; fi
if [[ ! -e $state ]]; then
  echo '{"id":"x","error":{"code":"server_not_running","message":"the herdr server is not running"}}'; exit 1
fi
case "$1 $2" in
  "status server") echo "server:"; echo "  status: running" ;;
  "workspace create") echo "{\"result\":{\"workspace\":{\"workspace_id\":\"w1\"},\"tab\":{\"tab_id\":\"w1:t1\"},\"root_pane\":{\"pane_id\":\"w1:p$(next)\",\"tab_id\":\"w1:t1\",\"terminal_id\":\"t\",\"workspace_id\":\"w1\",\"cwd\":\"/\",\"agent_status\":\"unknown\"}}}" ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"x","number":1,"pane_count":1,"tab_count":1,"agent_status":"unknown","active_tab_id":"w1:t1","focused":true}],"type":"workspace_list"}}' ;;
  "workspace close") echo '{"result":{}}' ;;
  "tab create") echo "{\"result\":{\"tab\":{\"tab_id\":\"w1:t2\"},\"root_pane\":{\"pane_id\":\"w1:p$(next)\"}}}" ;;
  "pane split") echo "{\"result\":{\"pane\":{\"pane_id\":\"w1:p$(next)\"}}}" ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","terminal_id":"t","workspace_id":"w1","cwd":"/","foreground_cwd":"/","agent_status":"unknown"}],"type":"pane_list"}}' ;;
  "agent list") echo '{"result":{"agents":[],"type":"agent_list"}}' ;;
  "agent get") exit 1 ;;
  "agent read") [[ ${FAKE_HERDR_FAIL_READ:-} == 1 ]] && { echo '{"error":{"code":"agent_not_found","message":"no such agent"}}'; exit 1; }
    echo "${FAKE_HERDR_SCREEN:-Allow Bash(ls)? 1. Yes 2. No}" ;;
  "agent wait") [[ ${FAKE_HERDR_FAIL_WAIT:-} == 1 ]] && { echo '{"error":"timeout"}'; exit 1; }
    [[ ${FAKE_HERDR_GONE_PANES:-} == 1 && $3 == *:* ]] && { echo '{"error":{"code":"pane_not_found"}}'; exit 1; }
    [[ -n ${FAKE_HERDR_WAIT_SLEEP:-} ]] && { echo $$ >>"$FAKE_HERDR_DIR/wait-pids"; exec sleep "$FAKE_HERDR_WAIT_SLEEP"; }
    echo '{"result":{}}' ;;
  "agent prompt") [[ ${FAKE_HERDR_FAIL_PROMPT:-} == 1 ]] && { echo '{"error":"agent_blocked"}'; exit 1; }; echo '{"result":{}}' ;;
  *) echo '{"result":{}}' ;;
esac
