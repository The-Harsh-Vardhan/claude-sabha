#!/bin/sh
# tests/hermetic-bin/gh after a pause, so two runs of sabha-upstream overlap (SABHA_GH_BIN points here, never PATH).
sleep "${FAKE_GH_SLEEP:-0.3}"
exec "$(dirname "$0")/hermetic-bin/gh" "$@"
