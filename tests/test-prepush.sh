#!/usr/bin/env bash
# hooks/git-pre-push.sh: lines fed on stdin, then real pushes from a made-up clone (hook installed with
# bin/sabha-prepush-install) to a local bare repo under $TMPDIR. Every refused push asserts the remote ref did not move.
# No network, no real remote, no gh, no herdr; git reads no global or system config.
# PREPUSH_NOHOOK=1 runs the same rows with no hook (a no-op for the stdin rows): every refusal row must then FAIL.
# Run: tests/test-prepush.sh
# shellcheck disable=SC2016,SC1091,SC2034,SC2059  # strings run by eval or bash -c; printf formats on purpose (\n, \t)
set -u
. "$(cd "$(dirname "$0")" && pwd)/hermetic.sh" || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
hook=$root/hooks/git-pre-push.sh
dir=$(mktemp -d "${TMPDIR:-/tmp}/sabha-prepush.XXXXXX") || exit 1
dir=$(cd -P "$dir" && pwd -P)
trap 'rm -rf "$dir" "$HERMETIC_FAKE_DIR"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
if [[ -n ${PREPUSH_NOHOOK:-} ]]; then printf '#!/bin/bash\ncat >/dev/null\n' >"$dir/noop.sh"; hook=$dir/noop.sh; fi
fails=0
check() { if eval "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

# ---- stdin rows ----
A=$(printf 'a%.0s' {1..40}) Z=0000000000000000000000000000000000000000
feed() { err=$(printf "$1" | /bin/bash "$hook" origin /x/remote.git 2>&1 >/dev/null); rc=$?; }
refuses() { feed "$1"; (( rc == 1 )) && [[ $err == "sabha pre-push: shared-push:"* ]]; }
passes() { feed "$1"; (( rc == 0 )) && [[ -z $err ]]; }
refuses_c() { err=$(printf "$1" | /bin/bash "$dir/c/hooks/git-pre-push.sh" origin /x/remote.git 2>&1 >/dev/null); rc=$?; (( rc == 1 )) && [[ $err == "sabha pre-push: shared-push:"* ]]; }
for r in refs/heads/main heads/main main :main +main +refs/heads/main HEAD:main refs/heads/master refs/heads/dev \
  refs/heads/develop refs/heads/staging refs/heads/release/x refs/heads/release/arcus-automation-sprint-3; do
  check "stdin: remote ref $r refused" "refuses 'refs/heads/feat/x $A $r $Z\n'"
done
check "stdin: delete of main refused, says delete" 'refuses "(delete) $Z refs/heads/main $A\n" && [[ $err == *"no delete of"* ]]'
check "stdin: a feature line then main refused" 'refuses "refs/heads/feat/x $A refs/heads/feat/x $Z\nrefs/heads/main $A refs/heads/main $A\n"'
check "stdin: last line without a newline judged" 'refuses "refs/heads/main $A refs/heads/main $A"'
check "stdin: feature branch passes" 'passes "refs/heads/feat/x $A refs/heads/feat/x $Z\n"'
check "stdin: delete of a feature branch passes" 'passes "(delete) $Z refs/heads/feat/old $A\n"'
check "stdin: tag passes" 'passes "refs/tags/v1 $A refs/tags/v1 $Z\n"'
for r in Main MAIN mAin Release/x refs/heads/Main +refs/heads/MASTER; do
  check "stdin: case-folded $r refused (APFS moves main for Main)" "refuses 'x $A $r $Z\n'"
done
for r in refs/Heads/Main Heads/Main REFS/HEADS/MAIN Refs/heads/main refs/HEADS/main +refs/Heads/Main; do
  check "stdin: prefix case-folded $r refused (review 244 S1)" "refuses 'x $A $r $Z\n'"
done
check "stdin: refs/heads/feature/main, refs/heads/devops, refs/heads/Devops-x pass (review 244 S1)" 'passes "x $A refs/heads/feature/main $Z\nx $A refs/heads/devops $Z\nx $A refs/heads/Devops-x $Z\n"'
check "stdin: refs/tags/Main and refs/Tags/Main are not branches and pass, as before (review 244 S1)" 'passes "x $A refs/tags/Main $Z\nx $A refs/Tags/Main $Z\n"'
check "stdin: mainline and feat/main pass" 'passes "refs/heads/x $A refs/heads/mainline $Z\nrefs/heads/x $A refs/heads/feat/main $Z\n"'
check "stdin: sha256 ids accepted" 'passes "refs/heads/feat/x ${A}${A:0:24} refs/heads/feat/x ${Z}${Z:0:24}\n"'
check "stdin: empty passes" 'passes ""'
for bad in "refs/heads/main $A refs/heads/main" "refs/heads/x $A refs/heads/x $Z extra" "refs/heads/x zzz refs/heads/x $Z" \
  "refs/heads/x\t$A\trefs/heads/main\t$Z" "refs/heads/x $A refs/heads/x $Z\r" " " "refs/heads/x $A refs/heads/ $Z"; do
  check "stdin: malformed line refused: $bad" "refuses '$bad\n'"
done
check "stdin: SABHA_SHARED_BRANCHES adds to the default list (review 242 M1)" 'SABHA_SHARED_BRANCHES="sprint*" refuses "x $A refs/heads/sprint-9 $Z\n" && SABHA_SHARED_BRANCHES="sprint*" refuses "x $A refs/heads/main $Z\n"'
for v in none qa; do
  check "stdin: SABHA_SHARED_BRANCHES=$v does not switch main off (review 242 M1)" "SABHA_SHARED_BRANCHES=$v refuses 'x $A refs/heads/main $Z\n'"
done
printf 'SABHA_SHARED_BRANCHES="qa"\n' >"$dir/sabha.conf"
check "stdin: SABHA_CONF in the push's environment is ignored by the pre-push hook (review 242 M1); the Claude hook still reads it" 'SABHA_CONF=$dir/sabha.conf passes "x $A refs/heads/qa $Z\n" && SABHA_CONF=$dir/sabha.conf refuses "x $A refs/heads/main $Z\n" && {
  printf "{\"tool_name\":\"Bash\",\"cwd\":\"/\",\"tool_input\":{\"command\":\"git push origin qa\"}}" | SABHA_CONF=$dir/sabha.conf bash "$root/hooks/sabha-rules.sh" 2>/dev/null; [[ $? == 2 ]]; }'
# review 242 M2: a list with no word must fall back to the default, from the env and from a conf
for v in ' ' $'\t' $'\n' $' \t\n'; do
  check "stdin: SABHA_SHARED_BRANCHES=$(printf %q "$v") (no word) falls back to the default (review 242 M2)" 'SABHA_SHARED_BRANCHES=$v refuses "x $A refs/heads/main $Z\n"'
done
if [[ -z ${PREPUSH_NOHOOK:-} ]]; then
  mkdir "$dir/alone" && cp "$hook" "$dir/alone/"
  check "stdin: lib.sh missing refuses" 'err=$(printf "x $A refs/heads/feat/x $Z\n" | /bin/bash "$dir/alone/git-pre-push.sh" 2>&1); [[ $? == 1 && $err == *"lib.sh is missing"* ]]'
  # a sabha.conf beside the scripts is the only conf the pre-push hook reads
  mkdir -p "$dir/c/hooks" && cp "$root/hooks/git-pre-push.sh" "$root/hooks/lib.sh" "$dir/c/hooks/"
  printf 'SABHA_SHARED_BRANCHES="qa"\n' >"$dir/c/sabha.conf"
  check "stdin: conf beside the scripts adds qa and keeps main" 'refuses_c "x $A refs/heads/qa $Z\n" && refuses_c "x $A refs/heads/main $Z\n"'
  for v in ' ' $'\t' $'\n'; do
    printf 'SABHA_SHARED_BRANCHES="%s"\n' "$v" >"$dir/c/sabha.conf"
    check "stdin: conf holding $(printf %q "$v") (no word) falls back to the default (review 242 M2)" 'refuses_c "x $A refs/heads/main $Z\n"'
  done
  printf 'SABHA_SHARED_BRANCHES="none"\n' >"$dir/c/sabha.conf"
  check "stdin: conf holding none does not switch main off" 'refuses_c "x $A refs/heads/main $Z\n"'
  if [[ $(/bin/bash -c 'echo ${BASH_VERSINFO[0]}') == 3 ]]; then
    check "stdin: NUL in a line refused (bash 3.2: read keeps the NUL)" 'refuses "refs/heads/f\0eat $A refs/heads/feat/x $Z\n"'
  fi
fi

# ---- real pushes ----
git init -q -b main "$dir/seed" && cd "$dir/seed" || exit 1
git commit -q --allow-empty -m c0
for b in master dev develop staging release/x release/arcus-automation-sprint-3 feat/old; do git branch "$b"; done
git commit -q --allow-empty -m c1
git clone -q --bare "$dir/seed" "$dir/remote.orig" || exit 1
git clone -q "$dir/remote.orig" "$dir/clone" && cd "$dir/clone" || exit 1
git remote set-url origin "$dir/remote.git"
git commit -q --allow-empty -m m3                        # local main one ahead of origin main
git checkout -q -b div origin/dev && git commit -q --allow-empty -m z  # not a descendant of main: non-fast-forward
git checkout -q --no-track -b feat/x origin/main && git commit -q --allow-empty -m f1
git init -q -b main "$dir/onmain" && git -C "$dir/onmain" commit -q --allow-empty -m o  # a cwd that sits on main
if [[ -z ${PREPUSH_NOHOOK:-} ]]; then "$root/bin/sabha-prepush-install" "$dir/clone" >/dev/null || exit 1; fi

reset_remote() { rm -rf "$dir/remote.git" && cp -R "$dir/remote.orig" "$dir/remote.git"; }
rref() { git -C "$dir/remote.git" rev-parse -q --verify "$1" 2>/dev/null; }
# push <cwd> <command>: a fresh remote, then runs the command in bash; sets rc and err
push() { reset_remote; err=$(cd "$1" && bash -c "$2" 2>&1); rc=$?; }
# refused <ref> <command> [cwd]: the push fails, the hook said why, and the remote ref did not move
# (rc is not asserted: a command may run on after the refused push, e.g. "; echo y")
refused() { local before; reset_remote; before=$(rref "$1"); push "${3:-$dir/clone}" "$2"; [[ $err == *"sabha pre-push: shared-push:"* && $(rref "$1") == "$before" ]]; }
landed() { push "${3:-$dir/clone}" "$2"; (( rc == 0 )) && [[ $(rref "$1") == "$(git -C "$dir/clone" rev-parse "${4:-$1}")" ]]; }

M=refs/heads/main
check "push: HEAD:main refused" 'refused $M "git push origin HEAD:main"'
check "push: HEAD:refs/heads/main refused" 'refused $M "git push origin HEAD:refs/heads/main"'
check "push: HEAD:heads/main refused" 'refused $M "git push origin HEAD:heads/main"'
check "push: :main (delete) refused" 'refused $M "git push origin :main"'
check "push: --delete main refused" 'refused $M "git push origin --delete main"'
check "push: +main refused" 'refused $M "git push origin +main"'
check "push: +div:main (non-fast-forward force) refused" 'refused $M "git push origin +div:main"'
check "push: -f div:main refused" 'refused $M "git push -f origin div:main"'
check "push: bare git push origin main refused" 'refused $M "git push origin main"'
for b in master dev develop staging release/x release/arcus-automation-sprint-3; do
  check "push: HEAD:$b refused" "refused refs/heads/$b 'git push origin HEAD:$b'"
done
check "push: --all touching main refused" 'refused $M "git push --all origin"'
check "push: --mirror refused" 'refused $M "git push --mirror origin"'
check "push: -C <dir> from a shared checkout refused" 'refused $M "git -C \"$dir/clone\" push origin HEAD:main" "$dir/onmain"'
check "push: \$(git branch --show-current) under -C from a cwd on main refused (review 235 M3)" 'refused $M "git -C \"$dir/clone\" push origin \"\$(git branch --show-current)\"" "$dir/onmain"'
check "push: backslashes g\\it pu\\sh HEAD:ma\\in refused" 'refused $M "g\\it pu\\sh origin HEAD:ma\\in"'
check "push: echo \\#; git push refused (review 235 M1a)" 'refused $M "echo \\#; git push origin HEAD:main"'
check "push: echo \"x\\\\\"; git push refused (review 235 M1b)" 'refused $M "echo \"x\\\\\"; git push origin HEAD:main; echo \"y\\\\\""'
check "push: \$((1<<2)) then a multi-line string refused (review 235 M2)" 'refused $M "echo \$((1<<2))
echo \"a
b\"; git push origin HEAD:main; echo \"c
d\""'
check "push: verb from an uppercase variable refused" 'refused $M "P=PUSH; git \$(echo \$P | tr A-Z a-z) origin HEAD:main"'
check "push: alias refused" 'refused $M "git -c alias.p=push p origin HEAD:main"'
check "push: command word from a variable refused" 'refused $M "G=git; \$G push origin HEAD:main"'
check "push: string piped into bash refused" 'refused $M "echo \"git push origin HEAD:main\" | bash"'
check "push: eval of a split string refused" 'refused $M "eval \"git push origin\" HEAD:main"'
check "push: config remote.origin.Push then a plain push refused (review 235 M4)" 'refused $M "git config remote.origin.Push HEAD:main; git push origin; r=\$?; git config --unset remote.origin.push; exit \$r"'
check "push: config remote.origin.mirror then a plain push refused" 'refused $M "git config remote.origin.mirror true; git push origin; r=\$?; git config --unset remote.origin.mirror; exit \$r"'
check "push: push.default=upstream with branch.merge=main refused" 'refused $M "git -c push.default=upstream -c branch.feat/x.remote=origin -c branch.feat/x.merge=refs/heads/main push"'
check "push: feature branch lands" 'landed refs/heads/feat/x "git push origin feat/x"'
check "push: feature branch lands from -C" 'landed refs/heads/feat/x "git -C \"$dir/clone\" push origin HEAD:feat/x" "$dir/onmain" feat/x'
check "push: delete of a feature branch lands" 'push "$dir/clone" "git push origin :feat/old"; (( rc == 0 )) && [[ -z $(rref refs/heads/feat/old) ]]'
git -C "$dir/clone" tag v1
check "push: tag lands" 'landed refs/tags/v1 "git push origin v1"'
git clone -q "$dir/remote.orig" "$dir/clone2" && git -C "$dir/clone2" remote set-url origin "$dir/remote.git"
git -C "$dir/clone2" checkout -q -b feat/y && git -C "$dir/clone2" branch -q -D main
git -C "$dir/clone2" commit -q --allow-empty -m y
[[ -n ${PREPUSH_NOHOOK:-} ]] || "$root/bin/sabha-prepush-install" "$dir/clone2" >/dev/null
check "push: --all with feature branches only lands" 'push "$dir/clone2" "git push --all origin"; (( rc == 0 )) && [[ $(rref refs/heads/feat/y) == "$(git -C "$dir/clone2" rev-parse feat/y)" ]]'
# known gaps, written down in docs/rule-hooks.md: these skip the hook, so the push lands
check "known gap: --no-verify skips the hook" 'landed $M "git push --no-verify origin HEAD:main" "" feat/x'
check "known gap: -c core.hooksPath skips the hook" 'landed $M "git -c core.hooksPath=/nonexistent push origin HEAD:main" "" feat/x'
# review 242 M1: the push's own environment no longer switches the hook off
check "push: SABHA_SHARED_BRANCHES=none in the push's environment refused (review 242 M1)" 'refused $M "SABHA_SHARED_BRANCHES=none git push origin HEAD:main" "" feat/x'
printf 'SABHA_SHARED_BRANCHES="none"\n' >"$dir/none.conf"
check "push: SABHA_CONF=<conf holding none> in the push's environment refused (review 242 M1)" 'refused $M "SABHA_CONF=$dir/none.conf git push origin HEAD:main" "" feat/x'
printf 'exit 0\n' >"$dir/exit0.sh"
check "push: BASH_ENV=<file holding exit 0> in the push's environment refused (review 242 M1, bash -p stub)" 'refused $M "BASH_ENV=$dir/exit0.sh git push origin HEAD:main" "" feat/x'
check "push: --atomic refused" 'refused $M "git push --atomic origin HEAD:main"'
check "push: --force-with-lease=main:<the remote sha> refused (git's own lease check passes, so the hook decides)" 'refused $M "git push --force-with-lease=main:\$(git -C \"$dir/remote.orig\" rev-parse main) origin HEAD:main"'
check "push: a tag named main lands (judged by its full ref)" 'git -C "$dir/clone2" tag main && push "$dir/clone2" "git push origin refs/tags/main"; (( rc == 0 )) && [[ $(rref refs/tags/main) == "$(git -C "$dir/clone2" rev-parse refs/tags/main)" ]]'
check "push: a second ref (main) after a feature ref refused" 'refused $M "git push origin feat/x HEAD:main"'
if [[ -z ${PREPUSH_NOHOOK:-} ]]; then
  check "install: the stub runs under bash -p (BASH_ENV is not read)" '[[ $(sed -n 1p "$dir/clone/.git/hooks/pre-push") == "#!/bin/bash -p" ]]'
  check "install: a second run says already installed, rc 0" 'out=$("$root/bin/sabha-prepush-install" "$dir/clone" 2>&1); [[ $? == 0 && $out == "already installed:"* ]]'
  check "install: a path that is not a repository fails with no stray mkdir error" 'out=$("$root/bin/sabha-prepush-install" "$dir" 2>&1); [[ $? != 0 && $out == *"not a git repository"* && $out != *mkdir* ]]'
  git init -q -b main "$dir/hp" && git -C "$dir/hp" config core.hooksPath .githooks && mkdir "$dir/hp/.githooks"
  check "install: follows core.hooksPath and says so" 'out=$("$root/bin/sabha-prepush-install" "$dir/hp" 2>&1); [[ $? == 0 && $out == *"core.hooksPath is set (.githooks)"* && -x $dir/hp/.githooks/pre-push && ! -e $dir/hp/.git/hooks/pre-push ]]'
fi
if [[ -z ${PREPUSH_NOHOOK:-} ]]; then
  git init -q -b main "$dir/foreign" && printf '#!/bin/sh\nexit 0\n' >"$dir/foreign/.git/hooks/pre-push"
  check "install: refuses when a different pre-push hook exists, and keeps it" '! "$root/bin/sabha-prepush-install" "$dir/foreign" 2>/dev/null && grep -q "exit 0" "$dir/foreign/.git/hooks/pre-push"'
  check "install: the foreign-hook message says it was kept, nothing changed, and how to chain or replace it (review 244 S3b)" 'out=$("$root/bin/sabha-prepush-install" "$dir/foreign" 2>&1); [[ $out == *"kept the existing pre-push hook $dir/foreign/.git/hooks/pre-push"* && $out == *"nothing was installed or changed"* && $out == *"add a line to that hook"* && $out == *"move it aside"* && $out != *"remove it first"* ]]'
  git init -q -b main "$dir/gl" && printf '[core]\n\thooksPath = %s\n' "$dir/shared-hooks" >"$dir/global.gitconfig" && mkdir "$dir/shared-hooks"
  check "install: a global core.hooksPath says where it installed and warns the directory is shared (review 244 S3a)" 'out=$(GIT_CONFIG_GLOBAL=$dir/global.gitconfig "$root/bin/sabha-prepush-install" "$dir/gl" 2>&1); [[ $? == 0 && -x $dir/shared-hooks/pre-push && $out == *"installed $dir/shared-hooks/pre-push -> "* && $out == *"WARNING: core.hooksPath comes from a global or system git config (file:$dir/global.gitconfig)"* && $out == *"shared by every repository that uses it"* ]]'
  check "install: a repository-local core.hooksPath gives no shared-directory warning (review 244 S3a)" 'rm -f "$dir/hp/.githooks/pre-push"; out=$("$root/bin/sabha-prepush-install" "$dir/hp" 2>&1); [[ $out == *"installed $dir/hp/.githooks/pre-push"* && $out != *WARNING* ]]'
  # review 244 S2: the pre-push path runs no external command that a PATH prefix could replace
  mkdir "$dir/fakebin" "$dir/fakelib" && printf 'hk_rule_conf() { HK_SHARED=zzz; HK_RULES=; HK_EXEMPT=; }\n' >"$dir/fakelib/lib.sh"
  printf '#!/bin/sh\necho "%s"\n' "$dir/fakelib" >"$dir/fakebin/dirname"; printf '#!/bin/sh\nexit 0\n' >"$dir/fakebin/sed"
  for c in tr cat awk cut head grep; do printf '#!/bin/sh\nexit 0\n' >"$dir/fakebin/$c"; done
  chmod +x "$dir"/fakebin/*
  check "install: fake dirname, sed, tr, cat, awk, cut, head, grep ahead on PATH: the installed hook still refuses main (review 244 S2)" 'err=$(printf "x $A refs/heads/main $Z\n" | PATH=$dir/fakebin:$PATH "$dir/clone/.git/hooks/pre-push" origin u 2>&1); [[ $? == 1 && $err == "sabha pre-push: shared-push:"* ]]'
  check "install: the same fake PATH, a feature line still passes (review 244 S2)" 'err=$(printf "x $A refs/heads/feat/x $Z\n" | PATH=$dir/fakebin:$PATH "$dir/clone/.git/hooks/pre-push" origin u 2>&1); [[ $? == 0 && -z $err ]]'
  printf 'SABHA_SHARED_BRANCHES="qa"\n' >"$dir/c/sabha.conf"
  check "stdin: fake sed on PATH does not drop the conf's qa (review 244 S2)" 'err=$(printf "x $A refs/heads/qa $Z\n" | PATH=$dir/fakebin:$PATH /bin/bash "$dir/c/hooks/git-pre-push.sh" origin u 2>&1); [[ $? == 1 && $err == "sabha pre-push: shared-push:"* ]]'
  check "stdin: a bare script name (no slash) still finds lib.sh; main refused, feature passes (review 244 S2, coverage)" '(cd "$dir/c/hooks" && printf "x $A refs/heads/main $Z\n" | /bin/bash git-pre-push.sh origin u 2>/dev/null; [[ $? == 1 ]] && printf "x $A refs/heads/feat/x $Z\n" | /bin/bash git-pre-push.sh origin u 2>/dev/null)'
  times=
  for _ in 1 2 3 4 5; do
    t=$( { TIMEFORMAT=%3R; time printf "refs/heads/feat/x $A refs/heads/feat/x $Z\n" | /bin/bash "$hook" origin u; } 2>&1 >/dev/null)
    t=${t/./}; times="$times $((10#$t))"
  done
  read -r best _ median _ worst <<<"$(printf '%s' "$times" | tr ' ' '\n' | grep . | sort -n | tr '\n' ' ')"
  # wall time of the hook alone, 5 runs at the load of the day: the row asserts the best, the label shows the spread
  check "hook time on a feature line: best of 5 under 100 ms (best $best, median $median, worst $worst ms; load: $(uptime | sed 's/.*averages*: //'))" '(( best < 100 ))'
fi

echo
if (( fails == 0 )); then echo "test-prepush: all passed"; else echo "test-prepush: $fails failed"; exit 1; fi
