#!/usr/bin/env bash
# Stands in for the browser runner in the tests: runner <html> <out.json> copies a prepared computed-styles dump.
# STUB_MODE: ok (default) | fail | garbage | nofile
here=$(cd "$(dirname "$0")" && pwd)
case ${STUB_MODE:-ok} in
  fail) echo "stub runner: boom" >&2; exit 3 ;;
  garbage) echo '{{{' > "$2" ;;
  nofile) : ;;
  *) cp "$here/computed-faulty.json" "$2" ;;
esac
