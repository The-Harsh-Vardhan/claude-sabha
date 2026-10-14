#!/usr/bin/env bash
# The brief-number claim of docs/inbox-protocol.md section 2: a second claim of a number fails, and a sender that
# finds its number taken moves to the next one. Run: tests/test-claim.sh
set -u
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-claim.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir"' EXIT
cd "$dir" || exit 1

claim() {
  local n
  # shellcheck disable=SC2010  # names are NNN.claim and NNN-<from>-<slug>.md, plain ASCII by the protocol
  n=$(ls | grep -E '^[0-9]{3}[.-]' | cut -c1-3 | sort | tail -1)
  n=$(printf '%03d' $(( 10#${n:-0} + 1 )))
  until (set -C; : > "$n.claim") 2>/dev/null; do n=$(printf '%03d' $(( 10#$n + 1 ))); done
  echo "$n"
}

a=$(claim); [[ $a == 001 ]] || { echo "FAIL: first claim got $a"; exit 1; }
if (set -C; : > 001.claim) 2>/dev/null; then echo "FAIL: second claim of 001 succeeded"; exit 1; fi
# another sender already holds 002 but has not written its brief yet
(set -C; : > 002.claim)
b=$(claim); [[ $b == 003 ]] || { echo "FAIL: expected 003 after a taken 002, got $b"; exit 1; }
echo "ok: second claim fails, a taken number is skipped"
