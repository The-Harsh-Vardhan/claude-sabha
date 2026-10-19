#!/usr/bin/env bash
# bin/sabha init with fake CLIs on PATH: the plan, tracker and push choices land in sabha.conf, a random ntfy topic is
# generated only for push=ntfy, paths are quoted (space, ~), the sabha folder is set up and never overwritten, an
# existing conf is not replaced without --force, a conf that git would track is refused, a bad plan fails. No Claude runs. Run: tests/test-init.sh   (works under bash 3.2 and 5)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# macOS TMPDIR ends in a slash; ${t%/} keeps a // out of $dir, which init's own paths never carry
t=${TMPDIR:-/tmp}
dir=$(mktemp -d "${t%/}/sabha-init.XXXXXX") || exit 1
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$dir/fakebin" "$dir/sysbin"
for c in grep sed head tr uname dirname git mktemp date awk cat sh env rm mkdir cp ln basename; do p=$(command -v $c) && ln -sf "$p" "$dir/sysbin/$c"; done
for c in claude opencode; do printf '#!/bin/sh\nexit 0\n' >"$dir/fakebin/$c"; chmod +x "$dir/fakebin/$c"; done
P="$dir/fakebin:$dir/sysbin"
# Git Bash: a copied tool cannot load msys-2.0.dll (git its libexec), so use the real dirs; no agent CLI lives there
case $(uname -s) in MINGW*|MSYS*) P="$dir/fakebin:/mingw64/bin:/usr/bin" ;; esac
# a private HOME: the default sabha folder (~/my-claude-sabha) must never land in the real one
H=$dir/home; mkdir -p "$H"
S() { HOME=$H PATH=$P "${BASH:-bash}" "$ROOT/bin/sabha" "$@"; }
# V <conf> <key>: the value a script sees after sourcing the conf
V() { ( HOME=$H; set +u; . "$1" >/dev/null 2>&1; eval "printf '%s' \"\${$2:-}\"" ); }

out=$dir/a.conf
res=$(S init --plan max5 --tracker html --push ntfy --ws "$dir/w" --impl "$dir/w/impl" --out "$out" </dev/null) || fail "init failed: $res"
# the sandbox hint: exact JSON for the sabha folder, valid, and no settings or permission file written anywhere
case $res in *'"allowWrite": ["'"$dir"'/w/impl"]'*) ;; *) fail "init must print the sandbox allowWrite line for the sabha folder: $res" ;; esac
[[ ! -e $H/.claude && ! -e $dir/w/.claude ]] || fail "init must not create a Claude Code settings file"
grep -qx 'SABHA_PLAN=max5' "$out" || fail "plan missing"
grep -qx 'SABHA_TRACKER=html' "$out" || fail "tracker missing"
grep -qx 'SABHA_PUSH=ntfy' "$out" || fail "push missing"
[[ $(V "$out" SABHA_WS) == "$dir/w" ]] || fail "ws not set: $(V "$out" SABHA_WS)"
grep -qx 'SABHA_PROTOCOL_CORE=PROTOCOL-core.md' "$out" && grep -qx 'SABHA_ROLE_DIR=protocol' "$out" || fail "protocol keys missing"
# the sabha folder: starter files and one inbox per role of the plan
for f in PROTOCOL-core.md protocol/Relay.md status/relay.md; do [[ -f $dir/w/impl/$f ]] || fail "starter file $f not copied"; done
for d in status/context status/.bak questions; do [[ -d $dir/w/impl/$d ]] || fail "folder $d missing"; done
roster=$( set +u; . "$ROOT/sabha.max5.conf"; echo "$SABHA_ROSTER" )
for e in $roster; do [[ -d $dir/w/impl/inbox/${e%%:*} ]] || fail "inbox/${e%%:*} missing"; done
# a second init keeps what the team wrote
echo edited >"$dir/w/impl/GOALS.md"
S init --plan max5 --ws "$dir/w" --impl "$dir/w/impl" --out "$dir/a2.conf" </dev/null >/dev/null || fail "re-init failed"
[[ $(cat "$dir/w/impl/GOALS.md") == edited ]] || fail "re-init overwrote an existing file"
grep -q 'agent CLIs found: claude opencode\.' "$out" || fail "detected CLIs wrong: $(grep 'CLIs found' "$out")"
t=$(sed -n 's/^SABHA_NTFY_TOPIC=//p' "$out")
[[ $t =~ ^sabha-[a-z0-9]{20}$ ]] || fail "topic should be sabha-<20 random chars>, got '$t'"
case $res in *"better option"*) ;; *) fail "html default must point at the Google Sheet" ;; esac

S init --plan pro --push ntfy --out "$dir/b.conf" </dev/null >/dev/null || fail "second init failed"
t2=$(sed -n 's/^SABHA_NTFY_TOPIC=//p' "$dir/b.conf")
[[ -n $t2 && $t2 != "$t" ]] || fail "topics must differ between runs"

S init --out "$dir/c.conf" </dev/null >/dev/null || fail "defaults init failed"
grep -qx 'SABHA_PLAN=pro' "$dir/c.conf" && grep -qx 'SABHA_TRACKER=html' "$dir/c.conf" && grep -qx 'SABHA_PUSH=off' "$dir/c.conf" || fail "defaults should be pro, html, off"
[[ $(V "$dir/c.conf" SABHA_IMPL) == "$H/my-claude-sabha/work" ]] || fail "default sabha folder should be ~/my-claude-sabha/<workspace name>, got $(V "$dir/c.conf" SABHA_IMPL)"
[[ -f $H/my-claude-sabha/work/PROTOCOL-core.md && -d $H/my-claude-sabha/work/inbox/Relay ]] || fail "default sabha folder not set up"

# a project that is a git repo, shared (the default when the workspace exists): your conf in <home>/<name>/sabha.conf,
# the team's committed <ws>/.sabha/, and the link <ws>/.sabha/local kept out of git through .git/info/exclude
p="$dir/My Proj"; mkdir -p "$p"; git init -q "$p" 2>/dev/null || fail "git init failed"
res=$(S init --plan pro --tracker sheet --ws "$p" --home "$dir/hub" </dev/null) || fail "project init failed: $res"
pc="$dir/hub/my-proj/sabha.conf"
[[ -f $pc ]] || fail "conf should be in <home>/<slug of workspace>/sabha.conf; init said: $res"
[[ -f $p/.sabha/local/sabha.conf && $p/.sabha/local/sabha.conf -ef $pc ]] || fail "link $p/.sabha/local missing or wrong: $res"
grep -qxF /.sabha/local "$p/.git/info/exclude" || fail "link not in .git/info/exclude"
for f in config PROTOCOL-core.md protocol/Relay.md ARCHITECTURE.md DECISIONS.md LESSONS.md .gitattributes; do
  [[ -e $p/.sabha/$f ]] || fail "team file .sabha/$f missing"
done
for f in PROTOCOL-core.md DECISIONS.md; do [[ -e $dir/hub/my-proj/$f ]] && fail "shared $f also copied into the personal folder"; done
[[ -f $dir/hub/my-proj/GOALS.md && -d $dir/hub/my-proj/inbox/Relay ]] || fail "personal folder lacks GOALS.md or inboxes"
grep -qx 'SABHA_PROJECT="my-proj"' "$p/.sabha/config" && grep -qx 'SABHA_TRACKER=sheet' "$p/.sabha/config" || fail "team config: $(cat "$p/.sabha/config")"
grep -q '^SABHA_TRACKER=\|^SABHA_PROJECT=\|^SABHA_ROSTER=' "$pc" && fail "team keys left active in the personal conf"
[[ $(V "$pc" SABHA_SHARED) == "$p/.sabha" ]] || fail "SABHA_SHARED: $(V "$pc" SABHA_SHARED)"
[[ -n $(V "$pc" SABHA_USER_ID) ]] || fail "SABHA_USER_ID empty"
grep -qx 'DECISIONS.md merge=union' "$p/.sabha/.gitattributes" || fail "no merge=union for DECISIONS.md"
# git sees the team files (to commit) and nothing of yours
st=$(git -C "$p" status --porcelain --untracked-files=all)
case $st in *.sabha/local*) fail "git sees .sabha/local: $st" ;; esac
case $st in *".sabha/config"*) ;; *) fail "git should see the team's .sabha/config: $st" ;; esac
echo team-rule >>"$p/.sabha/PROTOCOL-core.md"
S init --plan pro --ws "$p" --home "$dir/hub" --force </dev/null >/dev/null || fail "re-init of the project failed"
[[ $(grep -cxF /.sabha/local "$p/.git/info/exclude") == 1 ]] || fail "exclude line added twice"
[[ $(tail -1 "$p/.sabha/PROTOCOL-core.md") == team-rule ]] || fail "re-init overwrote a team file"
S init --plan pro --ws "$p" --home "$dir/hub" --name other </dev/null | grep -q 'link: skipped' || fail "a link to another folder must be left alone"
# the scripts find the conf through the link, export it, and a conf in its sabha folder still finds the plan file;
# the docs come from the team folder
L() { ( cd "$p" && unset SABHA_CONF && HOME=$H bash -c '. "$1/bin/sabha-lib.sh"; sabha_load t; echo "$SABHA_CONF|${#ROLES[@]}|$SABHA_PROJECT|${PANES[*]}|$SABHA_IMPL|$SABHA_DOCS"' _ "$ROOT" ); }
got=$(L) || fail "sabha_load from the project failed"
IFS='|' read -r g_conf g_n g_proj g_panes g_impl g_docs <<<"$got"
[[ $g_conf == "$p/.sabha/local/sabha.conf" && $g_n == 7 && $g_proj == my-proj && $g_docs == "$p/.sabha" ]] || fail "lookup through the link: got $got"
# the team file is parsed, never run: no $( ) runs, a personal key is ignored, a shared key beats the plan file
printf 'SABHA_PROJECT="$(touch %s/pwned)"\nSABHA_IMPL=/elsewhere\nSABHA_PANES="Relay Dispatcher"\n' "$dir" >"$p/.sabha/config"
got=$(L 2>/dev/null) || fail "sabha_load with a hostile team config failed"
IFS='|' read -r g_conf g_n g_proj g_panes g_impl g_docs <<<"$got"
[[ ! -e $dir/pwned ]] || fail "the team config was executed"
[[ $g_proj == "\$(touch $dir/pwned)" ]] || fail "SABHA_PROJECT should be the literal text, got $g_proj"
[[ $g_impl == "$dir/hub/my-proj" ]] || fail "a personal key in the team config was applied: SABHA_IMPL=$g_impl"
[[ $g_panes == "Relay Dispatcher" ]] || fail "team SABHA_PANES should beat the plan file, got $g_panes"
# your own key wins over the team's
echo 'SABHA_PANES="Relay"' >>"$pc"
got=$(L 2>/dev/null); IFS='|' read -r g_conf g_n g_proj g_panes g_impl g_docs <<<"$got"
[[ $g_panes == Relay ]] || fail "your SABHA_PANES should beat the team's, got $g_panes"
# doctor FAILs a personal key in the team config
d=$(SABHA_CONF=$pc S doctor </dev/null 2>&1)
grep -q 'FAIL  personal keys in the committed .*SABHA_IMPL' <<<"$d" || fail "doctor should FAIL SABHA_IMPL in .sabha/config: $(grep -i 'team\|personal' <<<"$d")"
grep -q 'ok    .*\.sabha/local is ignored by git' <<<"$d" || fail "doctor should confirm .sabha/local is ignored: $(grep -i 'sabha/local' <<<"$d")"
grep -q '^SABHA_NTFY_TOPIC=' "$dir/c.conf" && fail "no topic without ntfy"

S init --out "$out" </dev/null >/dev/null 2>&1 && fail "existing conf must not be replaced"
S init --force --out "$out" </dev/null >/dev/null || fail "--force should replace"
# the workspace is only written, never created, so it can hold | \ " (not valid in a Windows file name); the sabha
# folder is created, so it gets a space and & only
w="$dir/a b|c&d\\e\"f" i="$dir/D Drive & co/my-claude-sabha"
S init --plan pro --ws "$w" --impl "$i" --out "$dir/e.conf" </dev/null >/dev/null || fail "init with a space, | & \\ and a quote in the path failed"
[[ $(V "$dir/e.conf" SABHA_WS) == "$w" && $(V "$dir/e.conf" SABHA_IMPL) == "$i" ]] || fail "path was mangled: $(grep '^SABHA_WS=\|^SABHA_IMPL=' "$dir/e.conf")"
[[ -d $i/inbox/Relay ]] || fail "sabha folder with a space in its path not set up"
S init --plan pro --ws '~/Work' --out "$dir/f.conf" </dev/null >/dev/null || fail "init with ~ failed"
[[ $(V "$dir/f.conf" SABHA_WS) == "$H/Work" ]] || fail "~ should expand to HOME, got $(V "$dir/f.conf" SABHA_WS)"
S init --plan gold --out "$dir/d.conf" </dev/null >/dev/null 2>&1 && fail "bad plan must fail"
[[ -e $dir/d.conf ]] && fail "bad plan wrote a file"

git init -q "$dir/repo" 2>/dev/null && {
  S init --push ntfy --out "$dir/repo/sabha.conf" </dev/null >/dev/null 2>&1 && fail "a conf git would track must be refused"
  [[ -e $dir/repo/sabha.conf ]] && fail "refused conf was written"
  echo sabha.conf >"$dir/repo/.gitignore"
  S init --out "$dir/repo/sabha.conf" </dev/null >/dev/null || fail "ignored path should be accepted"
}
echo "ok: init writes plan, tracker, push, detected CLIs, quoted paths; sets up the sabha folder and the team's .sabha/ without overwriting either; .sabha/local excluded from git; team config parsed not run, personal keys ignored, your keys win; doctor FAILs personal keys; random ntfy topic only for ntfy; no tracked path, bad plan fails"
