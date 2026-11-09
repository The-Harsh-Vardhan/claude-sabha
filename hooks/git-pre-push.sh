#!/usr/bin/env bash
# git pre-push hook: refuses a push whose remote ref is a shared branch (SABHA_SHARED_BRANCHES, the same list the Claude
# rule hook uses, read by hk_rule_conf in lib.sh; here the push's environment can only add branches to the default list
# and SABHA_CONF is ignored). Git hands it the real refs of the push, not the command text, so
# quoting, aliases, config and command words built at run time do not matter here. Opt-in for one repository:
# bin/sabha-prepush-install <repo> (docs/rule-hooks.md). Not a boundary: git push --no-verify skips it.
# Stdin: one line per ref, "<local ref> <local sha> <remote ref> <remote sha>"; args: remote name, url.
set -u
shopt -s nocasematch  # a case-insensitive remote disk moves main for Main, so names are compared case-folded
hk_d=${BASH_SOURCE[0]}; if [[ $hk_d == */* ]]; then hk_d=${hk_d%/*}; hk_d=${hk_d:-/}; else hk_d=.; fi  # no dirname: a fake one on PATH must not pick lib.sh
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$hk_d/lib.sh" || { echo "sabha pre-push: hooks/lib.sh is missing; push refused" >&2; exit 1; }
hk_rule_conf prepush

refuse() { echo "sabha pre-push: shared-push: $1" >&2; while read -r _; do :; done; exit 1; }
re='^([^ ]+) ([0-9a-f]{40}|[0-9a-f]{64}) ([^ ]+) ([0-9a-f]{40}|[0-9a-f]{64})$'
set -f
while IFS= read -r line || [[ -n $line ]]; do
  [[ $line =~ $re ]] || refuse "a line from git is not '<local ref> <sha> <remote ref> <sha>' ('$line'); push refused"
  lsha=${BASH_REMATCH[2]} rref=${BASH_REMATCH[3]}
  # git sends refs/heads/<b>; the short forms are accepted too, so a hand-fed line is judged the same way
  b=${rref#+}; b=${b##*:}; b=${b#+}
  case $b in
    refs/heads/*) b=${b:11} ;;  # by length: nocasematch matches Refs/Heads/ but ${b#refs/heads/} would not strip it
    heads/*) b=${b:6} ;;
    refs/*) continue ;;
  esac
  [[ -n $b ]] || refuse "the remote ref '$rref' names no branch; push refused"
  what=push; [[ $lsha == *[!0]* ]] || what=delete
  for s in $HK_SHARED; do
    # shellcheck disable=SC2254  # $s is a glob on purpose (release/*)
    case $b in $s) refuse "no $what of the shared branch '$b' (remote ref '$rref', remote '${1:-?}'); push your own feature branch and open a reviewed pull request" ;; esac
  done
done
exit 0
