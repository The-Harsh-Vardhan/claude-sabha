#!/usr/bin/env bash
# template/impl/STANDING-RULES.md: bin/sabha init puts it in a new sabha folder, ${SABHA_USER} becomes the environment's
# SABHA_USER (else the conf's) and stays as written when neither is set, an existing folder is not touched, and the role
# opening prompt points at the file once it exists. No Claude runs. Run: tests/test-standing-rules.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
t=${TMPDIR:-/tmp}
dir=$(mktemp -d "${t%/}/sabha-rules.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
mkdir -p "$dir/fakebin" "$dir/sysbin" "$dir/home"
for c in grep sed head tr uname dirname git mktemp date awk cat sh env rm mkdir cp ln basename mv; do p=$(command -v $c) && ln -sf "$p" "$dir/sysbin/$c"; done
for c in claude; do printf '#!/bin/sh\nexit 0\n' >"$dir/fakebin/$c"; chmod +x "$dir/fakebin/$c"; done
P="$dir/fakebin:$dir/sysbin"
S() { HOME=$dir/home PATH=$P "${BASH:-bash}" "$ROOT/bin/sabha" "$@"; }
T=$ROOT/template/impl/STANDING-RULES.md

check "the template is in the kit and names every section 1 to 8" '[[ -f $T ]] && for n in 1 2 3 4 5 6 7 8; do grep -q "^## $n\. " "$T" || exit 1; done'
check "the template is ASCII" '! LC_ALL=C grep -q "[^ -~]" "$T"'
check "the template names the human only as \${SABHA_USER}" 'grep -q "\${SABHA_USER}" "$T"'

echo "--- init, SABHA_USER in the environment"
res=$(SABHA_USER=Alex S init --plan five --tracker html --push off --ws "$dir/w1" --impl "$dir/w1/impl" --out "$dir/a.conf" </dev/null 2>&1) || { echo "FAIL: init: $res"; exit 1; }
f=$dir/w1/impl/STANDING-RULES.md
check "init copied STANDING-RULES.md into the new sabha folder" '[[ -f $f ]]'
check "SABHA_USER became Alex everywhere" '! grep -q "\${SABHA_USER}" "$f" && grep -q "Set by Alex; they hold" "$f"'
check "only the name changed: same line count" '[[ $(wc -l < "$f") == $(wc -l < "$T") ]]'
check "no temp file left behind" '[[ ! -e $f.tmp ]]'

echo "--- init, a name with & and a slash"
res=$(SABHA_USER='A&B/C' S init --plan five --tracker html --push off --ws "$dir/w2" --impl "$dir/w2/impl" --out "$dir/b.conf" </dev/null 2>&1) || { echo "FAIL: init: $res"; exit 1; }
check "& and / in the name are taken literally" 'grep -q "Set by A&B/C; they hold" "$dir/w2/impl/STANDING-RULES.md"'

echo "--- init, SABHA_USER only in the conf (the default conf says \"the user\")"
res=$(env -u SABHA_USER HOME=$dir/home PATH=$P "${BASH:-bash}" "$ROOT/bin/sabha" init --plan five --tracker html --push off --ws "$dir/w3" --impl "$dir/w3/impl" --out "$dir/c.conf" </dev/null 2>&1) || { echo "FAIL: init: $res"; exit 1; }
check "the conf's SABHA_USER is used: no placeholder left" '! grep -q "\${SABHA_USER}" "$dir/w3/impl/STANDING-RULES.md" && grep -q "Set by the user; they hold" "$dir/w3/impl/STANDING-RULES.md"'

echo "--- an existing folder is not touched"
echo "mine" > "$dir/w1/impl/STANDING-RULES.md"
res=$(SABHA_USER=Alex S init --plan five --tracker html --push off --ws "$dir/w1" --impl "$dir/w1/impl" --out "$dir/a.conf" --force </dev/null 2>&1)
check "a folder that already holds GOALS.md keeps its own STANDING-RULES.md" '[[ $(cat "$dir/w1/impl/STANDING-RULES.md") == mine ]]'

echo "--- the opening prompt"
mkdir -p "$dir/impl" "$dir/ws"
printf 'SABHA_WS=%s\nSABHA_IMPL=%s\nSABHA_ROSTER="Relay:opus Dispatcher:opus"\n' "$dir/ws" "$dir/impl" > "$dir/sabha.conf"
out=$(SABHA_CONF=$dir/sabha.conf bash "$ROOT/bin/sabha-up.sh" --print Dispatcher 2>&1)
check "no STANDING-RULES.md: the prompt does not mention it" '! grep -q "STANDING-RULES" <<<"$out"'
echo x > "$dir/impl/STANDING-RULES.md"
out=$(SABHA_CONF=$dir/sabha.conf bash "$ROOT/bin/sabha-up.sh" --print Dispatcher 2>&1)
check "with the file: the prompt names it, for a blocker, a permission or a question to the user" 'grep -q "$dir/impl/STANDING-RULES.md when you are blocked, need a permission or are about to ask the user" <<<"$out"'

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "ok: all checks pass"
