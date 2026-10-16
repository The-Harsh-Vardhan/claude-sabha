#!/usr/bin/env bash
# A stand-in for herdr, copied to a temp dir as "herdr" by tests/test-herdr.sh: logs every call to $FAKE_HERDR_LOG and
# answers with the JSON shapes `herdr --skill` documents. Ids come from a counter file in $FAKE_HERDR_DIR.
echo "$*" >>"$FAKE_HERDR_LOG"
next() { local n; n=$(cat "$FAKE_HERDR_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$FAKE_HERDR_DIR/n"; echo "$n"; }
case "$1 $2" in
  "status server") echo "server:"; echo "  status: running" ;;
  "workspace create") echo "{\"result\":{\"workspace\":{\"workspace_id\":\"w1\"},\"tab\":{\"tab_id\":\"w1:t1\"},\"root_pane\":{\"pane_id\":\"p$(next)\"}}}" ;;
  "tab create") echo "{\"result\":{\"tab\":{\"tab_id\":\"w1:t2\"},\"root_pane\":{\"pane_id\":\"p$(next)\"}}}" ;;
  "pane split") echo "{\"result\":{\"pane\":{\"pane_id\":\"p$(next)\"}}}" ;;
  "agent get") exit 1 ;;
  "agent prompt") [[ ${FAKE_HERDR_FAIL_PROMPT:-} == 1 ]] && { echo '{"error":"agent_blocked"}'; exit 1; }; echo '{"result":{}}' ;;
  *) echo '{"result":{}}' ;;
esac
