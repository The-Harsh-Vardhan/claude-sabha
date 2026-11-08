#!/usr/bin/env bash
# PreToolUse hook for the working rules every session follows, whatever its role. Opt-in: nothing loads it until you
# paste hooks/rules.settings.example.json into a settings file (docs/rule-hooks.md). A safety net for honest mistakes,
# not enforcement: a session set on breaking a rule can get around a text check.
#   ascii         Write/Edit text, and a git commit or gh pr/issue/release message, holds only ASCII
#   attribution   no "Co-Authored-By" or "generated with <AI>" marker in that text
#   shared-push   no git push to a shared branch (SABHA_SHARED_BRANCHES), no --all, no --mirror
#   secret-read   no Read, Grep, Glob or shell command that names a secret file (.env, .npmrc, keys); *.example is fine
# Settings (env wins, else SABHA_CONF): SABHA_RULES (default all four), SABHA_SHARED_BRANCHES (default
# "main master dev develop staging release/*"), SABHA_ASCII_EXEMPT (path globs the ASCII rule skips, e.g. */vendor/*).
# Exit 2 + a reason on stderr denies the call. Hook JSON on stdin. Needs jq; without it every call is denied.
set -uo pipefail

in=$(cat)
deny() { echo "sabha-rules: $1: $2" >&2; exit 2; }
command -v jq >/dev/null || deny setup "jq is missing; install it or remove this hook from your settings"
jqr() { printf '%s' "$in" | jq -r "$1" 2>/dev/null; }

rules=${SABHA_RULES:-} shared=${SABHA_SHARED_BRANCHES:-} exempt=${SABHA_ASCII_EXEMPT:-}
if [[ -n ${SABHA_CONF:-} && -f $SABHA_CONF ]]; then
  # the conf runs in its own bash and hands back only these three values
  # shellcheck disable=SC2016  # expanded by the inner bash
  vals=$("$BASH" -c 'set +u; . "$1" >/dev/null 2>&1; printf "%s\n" "${SABHA_RULES:-}" "${SABHA_SHARED_BRANCHES:-}" "${SABHA_ASCII_EXEMPT:-}"' _ "$SABHA_CONF" 2>/dev/null) || vals=
  [[ -n $rules ]] || rules=$(printf '%s\n' "$vals" | sed -n 1p)
  [[ -n $shared ]] || shared=$(printf '%s\n' "$vals" | sed -n 2p)
  [[ -n $exempt ]] || exempt=$(printf '%s\n' "$vals" | sed -n 3p)
fi
[[ -n $rules ]] || rules="ascii attribution shared-push secret-read"
[[ -n $shared ]] || shared="main master dev develop staging release/*"
on() { case " $rules " in *" $1 "*) return 0 ;; esac; return 1; }

# glob_in <word> <globs>: the word matches one of the space-separated globs
glob_in() {
  local g hit=1
  set -f
  # shellcheck disable=SC2254  # $g is a glob on purpose
  for g in $2; do case $1 in $g) hit=0; break ;; esac; done
  set +f
  return $hit
}

# is_secret <word>: the last part after / : or = names a secret file, in any case (APFS is case-insensitive). Covers
# .env, .env.*, .<name>.env, .envrc, .npmrc, .netrc, .pgpass, .git-credentials, kubeconfig, credentials*, creds, *.pem,
# *.key, id_rsa-style keys, .aws/, .git/config, .docker/config.json. *.example, *.sample and *.template are templates.
is_secret() {
  local n=${1##*[/:=]} hit=1
  shopt -s nocasematch
  case $n in
    *.example|*.sample|*.template) ;;
    .env|.env.*|.*.env|.envrc|.npmrc|.netrc|.pgpass|.git-credentials|kubeconfig|credentials|credentials.*|creds|*.pem|*.key|id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*) hit=0 ;;
  esac
  case /$1 in */.aws|*/.aws/*|*/.git/config|*/.docker/config.json) hit=0 ;; esac
  shopt -u nocasematch
  return $hit
}

# glob_secret <word>: a Grep or Glob tool glob whose last part could match a secret name (.en?, .e*). A bare * or ** is a
# directory listing, not a read of one file, and passes.
# shellcheck disable=SC2254  # $g is a glob on purpose
glob_secret() {
  local g=${1##*/} s hit=1
  case $g in *[*?[]*|*'{'*) ;; *) return 1 ;; esac
  case $g in '*'|'**') return 1 ;; esac
  shopt -s nocasematch
  for s in .env .env.local .envrc .npmrc .netrc .pgpass .git-credentials kubeconfig credentials creds x.pem x.key id_rsa; do
    case $s in $g) hit=0; break ;; esac
  done
  shopt -u nocasematch
  return $hit
}

tool=$(jqr '.tool_name // ""') cwd=$(jqr '.cwd // ""')
text='' path='' cmd='' words=''
case $tool in
  Write) path=$(jqr '.tool_input.file_path // ""'); text=$(jqr '.tool_input.content // ""') ;;
  Edit) path=$(jqr '.tool_input.file_path // ""'); text=$(jqr '.tool_input.new_string // ""') ;;
  MultiEdit) path=$(jqr '.tool_input.file_path // ""'); text=$(jqr '[.tool_input.edits[]?.new_string] | join("\n")') ;;
  Read) words=$(jqr '.tool_input.file_path // ""') ;;
  Grep) words=$(jqr '[.tool_input.path, .tool_input.glob] | map(. // "") | join("\n")') ;;
  Glob) words=$(jqr '[.tool_input.path, .tool_input.pattern] | map(. // "") | join("\n")') ;;
  Bash) cmd=$(jqr '.tool_input.command // ""') ;;
  *) exit 0 ;;
esac

# a git commit or a gh pr/issue/release write carries a message the rules cover
msg_cmd=0
if [[ -n $cmd ]] && printf '%s\n' "$cmd" | grep -Eq 'git[[:space:]]+(.*[[:space:]])?commit([[:space:]]|$)|gh[[:space:]].*(pr|issue|release)[[:space:]]+(create|edit|comment|review)'; then
  msg_cmd=1
fi

if on ascii; then
  chk=$text
  [[ $msg_cmd == 1 ]] && chk=$cmd
  if [[ -n $chk ]] && ! { [[ -n $path ]] && glob_in "$path" "$exempt"; }; then
    bad=$(printf '%s' "$chk" | LC_ALL=C tr -d '\000-\177' | wc -c | tr -d ' ')
    [[ $bad == 0 ]] || deny ascii "$bad non-ASCII byte(s); use plain ASCII (-> not an arrow, - not a dash, straight quotes)"
  fi
fi

if on attribution; then
  mark='co-authored-by:|generated (with|by)[^a-z]*(claude|chatgpt|copilot|gemini|codex|an? ai|ai)|noreply@anthropic\.com'
  hit=1
  if [[ $msg_cmd == 1 ]]; then
    printf '%s\n' "$cmd" | grep -Eiq "$mark" && hit=0
  elif [[ -n $text ]]; then
    # file text: only a line that starts with the marker, so a note that discusses the rule can be written
    printf '%s\n' "$text" | grep -Eiq "^[[:space:]]*($mark)" && hit=0
  fi
  [[ $hit == 1 ]] || deny attribution "no AI-attribution marker (Co-Authored-By, generated-with line) in source, commits or PR bodies"
fi

if on shared-push && [[ -n $cmd ]]; then
  # a quoted string with a space is data (a commit message): it becomes Q; other quotes are dropped. One command per line.
  code=$(printf '%s\n' "$cmd" | sed -E "s/\"[^\"]*[[:space:]][^\"]*\"/Q/g; s/'[^']*[[:space:]][^']*'/Q/g; s/[\"']//g; s/(&&?|\\|\\|?|;)/\\
/g")
  git_push='(^|[[:space:]])git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)'
  IFS=$'\n'
  set -f
  for seg in $code; do
    printf '%s\n' "$seg" | grep -Eq "$git_push" || continue
    args=$(printf '%s\n' "$seg" | sed -nE "s/^.*$git_push//p")
    dir=$(printf '%s\n' "$seg" | sed -nE 's/.*[[:space:]]-C[[:space:]]+([^[:space:]]+)[[:space:]]+push.*/\1/p')
    [[ -n $dir ]] || dir=.
    [[ $dir == /* ]] || dir=${cwd:-.}/$dir
    n=0 skip=0 refs=0
    unset IFS
    for tok in $args; do
      if [[ $skip == 1 ]]; then skip=0; continue; fi
      case $tok in
        --all|--mirror) deny shared-push "git push $tok reaches every branch, shared ones included; push your own branch by name" ;;
        -o|--push-option|--repo|--receive-pack|--exec) skip=1; continue ;;
        -*) continue ;;
      esac
      n=$((n + 1))
      [[ $n -gt 1 ]] || continue
      refs=$((refs + 1))
      dest=${tok#+}
      case $dest in *:*) dest=${dest##*:} ;; esac
      dest=${dest#refs/heads/}
      if [[ $dest == HEAD || -z $dest ]]; then dest=$(git -C "$dir" branch --show-current 2>/dev/null); fi
      if [[ -n $dest ]] && glob_in "$dest" "$shared"; then
        deny shared-push "no push to the shared branch '$dest'; push your own feature branch and open a reviewed pull request"
      fi
    done
    if [[ $refs == 0 ]]; then
      cur=$(git -C "$dir" branch --show-current 2>/dev/null)
      if [[ -n $cur ]] && glob_in "$cur" "$shared"; then
        deny shared-push "this checkout is on the shared branch '$cur'; a bare push would publish it"
      fi
    fi
    IFS=$'\n'
  done
  unset IFS
  set +f
fi
# ponytail: a push hidden in sh -c "$X", a split string or a quoted refspec with a space is a known gap; add the
# sh -c unquoting of sabha-guard.sh when it matters

if on secret-read; then
  if [[ -n $cmd ]]; then
    IFS=$'\n'
    set -f
    for seg in $(printf '%s\n' "$cmd" | sed -E 's/(&&?|\|\|?|;)/\
/g'); do
      # copying a secret file into a worktree reads nothing; the rest is refused
      printf '%s\n' "$seg" | grep -Eq '^[[:space:]]*cp[[:space:]]' && continue
      for w in $(printf '%s\n' "$seg" | tr -s " \t\"'(),<>{}" '\n'); do
        is_secret "$w" && deny secret-read "'$w' is a secret file; never read, list or print it, ask the human or the relay"
      done
    done
    unset IFS
    set +f
  fi
  if [[ -n $words ]]; then
    IFS=$'\n'
    for w in $words; do
      { is_secret "$w" || glob_secret "$w"; } && deny secret-read "'$w' is a secret file; never read, list or print it, ask the human or the relay"
    done
    unset IFS
  fi
fi
exit 0
