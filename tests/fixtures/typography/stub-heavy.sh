#!/usr/bin/env bash
# Stands in for bin/sabha-heavy in the tests: logs its arguments, answers WAIT (75) when STUB_HEAVY_WAIT=1, else runs the command.
echo "$*" >> "${STUB_HEAVY_LOG:-/dev/null}"
[[ ${STUB_HEAVY_WAIT:-0} == 1 ]] && exit 75
[[ $1 == run && $3 == -- ]] || exit 64
shift 3
exec "$@"
