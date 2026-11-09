#!/usr/bin/env bash
# sabha roster --check|--write and sabha stamp (audit Q7): SABHA_ROSTER is the only roster source; the PROTOCOL-core
# table cells and protocol/<Name>.md headings that name another model are reported, then rewritten; a claims file's
# "no <model>" lines are shown as context under a model conflict and never written; doctor counts drift as FAIL. No Claude runs. Run: tests/test-roster-source.sh
# shellcheck disable=SC2016,SC2034  # the checks are eval strings, expanded when they run
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH=${BASH:-bash}
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-rsrc.XXXXXX") || exit 1
[[ -d $dir ]] || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

I=$dir/impl
mkdir -p "$I/protocol" "$I/status"
cat >"$dir/sabha.conf" <<EOF
SABHA_WS=$dir
SABHA_IMPL=$I
SABHA_ROSTER="Vidur:opus:medium Yudh:sonnet:high Bhishma:opus:medium:lazy Duryo:sonnet:medium:gate Dusha:sonnet:medium:gate Shaku:opus:medium:gate Ved:sonnet:low"
EOF
cat >"$I/PROTOCOL-core.md" <<'EOF'
# Core

| Name | Model, effort | Job |
| --- | --- | --- |
| Vidur | Opus, medium | Relay. |
| Yudh | Sonnet, high | Dispatcher. |
| Bhishma | Fable, low | Hard design. |
| Duryo / Dusha / Shaku | Sonnet | Critics. |
| Krishna | - | Not in the roster. |
EOF
echo '# Bhishma (Fable, low): hard design' >"$I/protocol/Bhishma.md"
echo '# Ved (Ved Vyasa; Sonnet, high): keeper' >"$I/protocol/Ved.md"
echo '# Vidur (Opus, medium): relay' >"$I/protocol/Vidur.md"
printf 'cost rules: no Fable anywhere\n' >"$dir/memory.md"
cp -R "$I" "$dir/before"
S() { SABHA_CONF=$dir/sabha.conf "$SH" "$ROOT/bin/sabha" "$@" 2>&1; }

echo "--- check"
out=$(S roster --check); rc=$?
check "drift exits 1" '(( rc == 1 ))'
check "table cell that differs: conf vs file:line" 'grep -qx "FAIL  Bhishma: conf opus medium, PROTOCOL-core.md:7 fable low" <<<"$out"'
check "card heading that differs" 'grep -qx "FAIL  Bhishma: conf opus medium, protocol/Bhishma.md:1 fable low" <<<"$out"'
check "a heading with a note before the model" 'grep -qx "FAIL  Ved: conf sonnet low, protocol/Ved.md:1 sonnet high" <<<"$out"'
check "a shared row: only the role whose model differs" 'grep -qx "FAIL  Shaku: conf opus medium, PROTOCOL-core.md:8 sonnet" <<<"$out" && ! grep -q "Duryo\|Dusha" <<<"$out"'
check "matching rows, a dash and an unknown name stay quiet" '! grep -q "Vidur\|Yudh\|Krishna" <<<"$out"'
check "count line" 'grep -qx "roster: 7 roles, 9 doc claims, 4 drift" <<<"$out"'
out=$(SABHA_ROSTER_CLAIMS=$dir/memory.md S roster --check)
check "a claims line that names either model follows a model conflict as context" 'grep -qx "      Bhishma: $dir/memory.md:1:cost rules: no Fable anywhere" <<<"$out"'
check "claims context is not drift; an effort-only conflict gets none" 'grep -qx "roster: 7 roles, 9 doc claims, 4 drift" <<<"$out" && ! grep -q "Ved: $dir" <<<"$out"'
out=$(SABHA_ROSTER_CLAIMS=$dir/none.md S roster --check)
check "a missing claims file is a FAIL" 'grep -q "FAIL  claims file $dir/none.md not found" <<<"$out"'

echo "--- doctor"
out=$(SABHA_DOCTOR_SEAT=personal SABHA_DOCTOR_COPIES='' SABHA_SETTINGS=$dir/none.json S doctor)
check "doctor reports roster drift as FAIL" 'grep -q "^FAIL  roster drift: Bhishma: conf opus medium, PROTOCOL-core.md:7 fable low (fix: sabha roster --write)" <<<"$out"'

echo "--- write"
out=$(S roster --write)
check "table cell rewritten from the conf" 'grep -qx "| Bhishma | Opus, medium | Hard design. |" "$I/PROTOCOL-core.md"'
check "card heading rewritten, note and job kept" 'grep -qx "# Bhishma (Opus, medium): hard design" "$I/protocol/Bhishma.md" && grep -qx "# Ved (Ved Vyasa; Sonnet, low): keeper" "$I/protocol/Ved.md"'
check "a shared row whose roles differ is left for a hand split" 'grep -q "skip  PROTOCOL-core.md:8: Shaku and Duryo Dusha differ" <<<"$out" && grep -qx "| Duryo / Dusha / Shaku | Sonnet | Critics. |" "$I/PROTOCOL-core.md"'
check "untouched lines stay byte for byte" 'diff <(sed 7d "$dir/before/PROTOCOL-core.md") <(sed 7d "$I/PROTOCOL-core.md") >/dev/null && cmp -s "$dir/before/protocol/Vidur.md" "$I/protocol/Vidur.md"'
check "the claims file is never written" 'grep -qx "cost rules: no Fable anywhere" "$dir/memory.md"'
check "no temp files left" '! ls "$I" "$I/protocol" | grep -q tmp'
out=$(S roster --check); rc=$?
check "after write only the hand-split row drifts" '(( rc == 1 )) && grep -qx "roster: 7 roles, 9 doc claims, 1 drift" <<<"$out"'
out=$(S roster --write)
check "a second write changes nothing" 'grep -qx "roster: 0 line(s) rewritten" <<<"$out"'
out=$(S roster --bogus); rc=$?
check "unknown option refused" '(( rc == 1 )) && grep -q "use --check or --write" <<<"$out"'

echo "--- stamp"
out=$(S stamp)
check "stamp: UTC then local, from the clock" '[[ $out =~ ^20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z\ \(20[0-9-]+\ [0-2][0-9]:[0-5][0-9]\ .+\)$ ]]'

echo "--- no docs"
rm -rf "$I/PROTOCOL-core.md" "$I/protocol"
out=$(S roster --check); rc=$?
check "no docs: nothing to compare, exit 0" '(( rc == 0 )) && grep -qx "roster: 7 roles, 0 doc claims, 0 drift" <<<"$out"'

echo "test-roster-source: $fails fail"
(( fails == 0 ))
