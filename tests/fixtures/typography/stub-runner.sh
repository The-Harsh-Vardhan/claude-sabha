#!/usr/bin/env bash
# Stands in for the browser runner in the tests: runner <html> <out.json> copies a prepared computed-styles dump.
# STUB_MODE: ok (default) | fail | garbage | nofile | nomodule | nochrome
# STUB_RUNNER_LOG, when set, gets the SABHA_TYPO_SCRIPTS value the runner was started with.
here=$(cd "$(dirname "$0")" && pwd)
[[ -n ${STUB_RUNNER_LOG:-} ]] && echo "scripts=${SABHA_TYPO_SCRIPTS:-unset}" >> "$STUB_RUNNER_LOG"
case ${STUB_MODE:-ok} in
  nomodule) printf 'node:internal/modules/cjs/loader:1228\n  throw err;\n  ^\n\nError: Cannot find module '"'"'playwright'"'"'\n    at Function._resolveFilename (node:internal/modules/cjs/loader:1225:15)\n    at require (node:internal/modules/helpers:318:16)\n' >&2; exit 1 ;;
  nochrome) echo 'typography-computed: Chrome could not be started, install Google Chrome: no such file' >&2; exit 4 ;;
  fail) echo "stub runner: boom" >&2; exit 3 ;;
  garbage) echo '{{{' > "$2" ;;
  nofile) : ;;
  *) cp "$here/computed-faulty.json" "$2" ;;
esac
