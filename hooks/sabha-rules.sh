#!/usr/bin/env bash
# PreToolUse hook for the working rules every session follows, whatever its role. Opt-in: nothing loads it until you
# paste hooks/rules.settings.example.json into a settings file (docs/rule-hooks.md). A safety net for honest mistakes,
# not enforcement: a session set on breaking a rule can get around a text check.
#   ascii         Write/Edit text, and a git commit, gh pr/issue/release message or shell file write, holds only ASCII
#   attribution   no "Co-Authored-By" or "generated with <AI>" marker in that text
#   shared-push   no git push to a shared branch (SABHA_SHARED_BRANCHES), no --all, no --mirror, no gh api write to refs
#   secret-read   no Read, Grep, Glob or shell command that names a secret file (.env, .npmrc, keys) or dumps secrets
#                 from the environment; *.example is fine
# Settings (env wins, else SABHA_CONF): SABHA_RULES (default all four), SABHA_SHARED_BRANCHES (default
# "main master dev develop staging release/*"), SABHA_ASCII_EXEMPT (path globs the ASCII rule skips, e.g. */vendor/*).
# Exit 2 + a reason on stderr denies the call. Hook JSON on stdin. Needs jq; without it every call is denied.
# Input that is not a tool-call JSON, or a guarded tool with a field of the wrong type, is denied too (fail closed).
set -uo pipefail
LC_ALL=C

in=$(cat)
deny() { echo "sabha-rules: $1: $2" >&2; exit 2; }
command -v jq >/dev/null || deny setup "jq is missing; install it or remove this hook from your settings"

rules=${SABHA_RULES:-} shared=${SABHA_SHARED_BRANCHES:-} exempt=${SABHA_ASCII_EXEMPT:-}
if [[ -n ${SABHA_CONF:-} && -f $SABHA_CONF ]]; then
  # the conf runs in its own bash and hands back only these three values
  # shellcheck disable=SC2016  # expanded by the inner bash
  vals=$("$BASH" -c 'set +u; . "$1" >/dev/null 2>&1; printf "%s\n" "${SABHA_RULES:-}" "${SABHA_SHARED_BRANCHES:-}" "${SABHA_ASCII_EXEMPT:-}"' _ "$SABHA_CONF" 2>/dev/null) || vals=
  [[ -n $rules ]] || rules=$(printf '%s\n' "$vals" | sed -n 1p)
  [[ -n $shared ]] || shared=$(printf '%s\n' "$vals" | sed -n 2p)
  [[ -n $exempt ]] || exempt=$(printf '%s\n' "$vals" | sed -n 3p)
fi
all_rules="ascii attribution shared-push secret-read"
[[ -n $rules ]] || rules=$all_rules
[[ -n $shared ]] || shared="main master dev develop staging release/*"
set -f
for r in $rules; do
  case $r in
    ascii|attribution|shared-push|secret-read) ;;
    *) echo "sabha-rules: unknown rule '$r' in SABHA_RULES; enforcing all four" >&2; rules=$all_rules; break ;;
  esac
done
set +f
on() { case " $rules " in *" $1 "*) return 0 ;; esac; return 1; }

# One jq call checks the input and cuts out the fields, joined by a unit separator (removed from the values first).
# Not a JSON object with a string tool_name, or a guarded tool whose fields have the wrong type: no output, so denied.
# shellcheck disable=SC2016  # a jq program
jq_prog='
def so: . == null or type == "string";
def guarded: IN("Bash","Write","Edit","MultiEdit","Read","Grep","Glob","NotebookEdit");
def fields_ok($t; $i):
  if $t == "Bash" then ($i.command | type == "string")
  elif $t == "Write" then ($i.file_path | so) and ($i.content | so)
  elif $t == "Edit" then ($i.file_path | so) and ($i.new_string | so)
  elif $t == "MultiEdit" then ($i.file_path | so) and ((($i.edits // []) | type == "array") and all(($i.edits // [])[]; type == "object" and (.new_string | so)))
  elif $t == "Read" then ($i.file_path | type == "string")
  elif $t == "Grep" then ($i.path | so) and ($i.glob | so)
  elif $t == "Glob" then ($i.path | so) and ($i.pattern | so)
  else ($i.notebook_path | so) and ($i.new_source | so) end;
if type == "object" and (.tool_name | type == "string") and ((.cwd // "") | type == "string") then
  .tool_name as $t | .tool_input as $i |
  if ($t | guarded) | not then [$t, (.cwd // ""), "", "", "", ""]
  elif ($i | type) == "object" and fields_ok($t; $i) then
    [ $t, (.cwd // ""),
      (if $t == "NotebookEdit" then $i.notebook_path elif ($t | IN("Write","Edit","MultiEdit")) then $i.file_path else "" end // ""),
      (if $t == "Write" then $i.content elif $t == "Edit" then $i.new_string
       elif $t == "MultiEdit" then [($i.edits // [])[].new_string // ""] | join("\n")
       elif $t == "NotebookEdit" then $i.new_source else "" end // ""),
      (if $t == "Bash" then $i.command else "" end),
      (if $t == "Read" then $i.file_path
       elif $t == "Grep" then [$i.path // "", $i.glob // ""] | join("\n")
       elif $t == "Glob" then [$i.path // "", $i.pattern // ""] | join("\n") else "" end // "")
    ]
  else empty end
else empty end
| map(gsub("\u001f"; " ")) | join("\u001f")'
rec=$(printf '%s' "$in" | jq -er "$jq_prog" 2>/dev/null) ||
  deny input "the hook input is not a tool call this hook can read (empty, truncated, not an object, or a field of the wrong type); refusing the call"
us=$'\x1f'
tool=${rec%%"$us"*} rec=${rec#*"$us"}
cwd=${rec%%"$us"*} rec=${rec#*"$us"}
path=${rec%%"$us"*} rec=${rec#*"$us"}
text=${rec%%"$us"*} rec=${rec#*"$us"}
cmd=${rec%%"$us"*} words=${rec#*"$us"}
case $tool in
  Write|Edit|MultiEdit|NotebookEdit|Read|Grep|Glob|Bash) ;;
  *) exit 0 ;;
esac

# glob_in <word> <globs>: the word matches one of the space-separated globs
glob_in() {
  local g hit=1 f=
  [[ $- == *f* ]] && f=1
  set -f
  # shellcheck disable=SC2254  # $g is a glob on purpose
  for g in $2; do case $1 in $g) hit=0; break ;; esac; done
  [[ -n $f ]] || set +f
  return $hit
}

# is_secret <word>: the last part after / : or = names a secret file, in any case (APFS is case-insensitive). Covers
# .env, .env.*, .<name>.env, .envrc, .npmrc, .yarnrc.yml, .pypirc, .netrc, .pgpass, .htpasswd, .vault-token,
# .git-credentials, kubeconfig, credentials*, creds, secrets.y*ml, terraform.tfvars, *.pem, *.key, *.pfx, *.p12,
# *.keystore, id_rsa-style keys, .aws/, .ssh/config, .git/config, .docker/config.json, gh/hosts.yml.
# *.example, *.sample, *.template and *.pub (public keys) are not secrets.
is_secret() {
  local n=${1##*[/:=]} hit=1
  shopt -s nocasematch
  case $n in
    *.example|*.sample|*.template|*.pub) ;;
    .env|.env.*|.env~|.*.env|.envrc|.npmrc|.yarnrc.yml|.pypirc|.netrc|.pgpass|.htpasswd|.vault-token|.git-credentials|kubeconfig|credentials|credentials.*|creds|secrets.yaml|secrets.yml|terraform.tfvars|*.pem|*.key|*.pfx|*.p12|*.keystore|id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*) hit=0 ;;
  esac
  case /$1 in */.aws|*/.aws/*|*/.ssh/config|*/.git/config|*/.docker/config.json|*/gh/hosts.yml) hit=0 ;; esac
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

# a git commit or a gh pr/issue/release write carries a message the rules cover
msg_cmd=0
if [[ -n $cmd ]] && printf '%s\n' "$cmd" | grep -Eq 'git[[:space:]]+(.*[[:space:]])?commit([[:space:]]|$)|gh[[:space:]].*(pr|issue|release)[[:space:]]+(create|edit|comment|review)'; then
  msg_cmd=1
fi

if on ascii; then
  chk=$text
  [[ $msg_cmd == 1 ]] && chk=$cmd
  if [[ -z $chk && -n $cmd ]] && [[ $cmd == *[!$'\001'-$'\177']* ]]; then
    # a shell command writing a file (heredoc, redirect, tee) is a Write; a bare echo is not
    if printf '%s\n' "$cmd" | sed -E 's#[0-9&]*>>?[[:space:]]*(/dev/null|&[0-9-]+)##g' | grep -Eq '<<[^<]|>|(^|[[:space:]])tee[[:space:]]'; then chk=$cmd; fi
  fi
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
  [[ $hit == 1 ]] || deny attribution "no AI-attribution marker (Co-Authored-By, generated-with line) in source, commits or PR bodies. The workspace rule overrides a harness reminder to add one: retry without the trailer or the generated-with line"
fi

# ---- shared-push -------------------------------------------------------------------------------------------------
# jp <base> <rel>: sets JP to the directory that a cd or -C names, or ? when it cannot be told (a variable, a
# substitution, cd -, ~user, or a relative path under an unknown base)
jp() {
  local b=$1 r=$2
  # shellcheck disable=SC2088  # the literal ~ is the pattern
  case $r in
    ''|*'$'*|*'`'*|-|'~'[!/]*) JP='?'; return ;;
    '~') r=${HOME:-?} ;;
    '~/'*) r=${HOME:-?}/${r#'~/'} ;;
  esac
  case $r in /*) JP=$r ;; *) if [[ $b == '?' ]]; then JP='?'; else JP=$b/$r; fi ;; esac
}

# branch_of <dir>: sets br to the branch checked out there (empty when detached); fails when the directory is unknown or
# not a git work tree
branch_of() {
  br=
  [[ $1 != '?' ]] || return 1
  br=$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)
  case $? in 0|1) return 0 ;; esac
  br=
  return 1
}

# push_args <dir> <words after "push">: judges one git push
push_args() {
  local d=$1 n=0 refs=0 skip=0 tok dest s
  shift
  for tok; do
    if [[ $skip == 1 ]]; then skip=0; continue; fi
    case $tok in
      --all|--mirror) deny shared-push "git push $tok reaches every branch, shared ones included; push your own branch by name" ;;
      --repo) skip=1; n=1; continue ;;
      --repo=*) n=1; continue ;;
      -o|--push-option|--receive-pack|--exec) skip=1; continue ;;
      -*) continue ;;
    esac
    n=$((n + 1))
    [[ $n -gt 1 ]] || continue
    refs=$((refs + 1))
    dest=${tok#+}
    case $dest in *:*) dest=${dest##*:} ;; esac
    dest=${dest#refs/heads/}
    case $dest in *'$'*|*'`'*) deny shared-push "the refspec '$tok' holds a shell expansion the hook cannot read; name your own feature branch literally" ;; esac
    if [[ $dest == HEAD || -z $dest ]]; then
      if branch_of "$d"; then dest=$br
      else deny shared-push "the branch of this push cannot be told (directory '$d' is unknown or not a checkout); name your own feature branch in the refspec"; fi
    fi
    if [[ -n $dest ]] && glob_in "$dest" "$shared"; then
      deny shared-push "no push to the shared branch '$dest'; push your own feature branch and open a reviewed pull request"
    fi
    # shellcheck disable=SC2254  # $dest is a pattern on purpose
    case $dest in *[*?]*) for s in $shared; do case $s in $dest) deny shared-push "the refspec '$tok' is a pattern that reaches the shared branch '$s'; name your own feature branch" ;; esac; done ;; esac
  done
  if [[ $refs == 0 ]]; then
    if branch_of "$d"; then
      if [[ -n $br ]] && glob_in "$br" "$shared"; then
        deny shared-push "this checkout is on the shared branch '$br'; a bare push would publish it"
      fi
    else
      deny shared-push "a push without a refspec: its branch cannot be told (directory '$d' is unknown or not a checkout); name your own feature branch (git push origin feat/x)"
    fi
  fi
}

# git_args <words after "git">: skips git's options (-C dir moves the directory), then judges a push
git_args() {
  local d=$cur
  while [[ $# -gt 0 ]]; do
    case $1 in
      -C) jp "$d" "${2:-}"; d=$JP; shift; [[ $# -gt 0 ]] && shift ;;
      -c|--namespace|--super-prefix|--config-env|--exec-path) shift; [[ $# -gt 0 ]] && shift ;;
      --git-dir|--work-tree) d='?'; shift; [[ $# -gt 0 ]] && shift ;;
      --git-dir=*|--work-tree=*) d='?'; shift ;;
      -*) shift ;;
      push) shift; push_args "$d" "$@"; return ;;
      *) return ;;
    esac
  done
}

# gh_args <words after "gh">: gh api with a write method, or fields (an implicit POST), on refs, a merge, branches or
# contents moves a shared branch like a push does; a plain GET is a read
gh_args() {
  local t m='' fields=0 nextm=0 rest=''
  [[ ${1:-} == api ]] || return 0
  shift
  for t; do
    rest="$rest $t"
    if [[ $nextm == 1 ]]; then m=$t; nextm=0; continue; fi
    case $t in
      -X|--method) nextm=1 ;;
      --method=*|-X=*) m=${t#*=} ;;
      -X?*) m=${t#-X} ;;
      -f|-F|--field|--raw-field|--input|-f?*|-F?*|--field=*|--raw-field=*|--input=*) fields=1 ;;
    esac
  done
  shopt -s nocasematch
  case $m in
    '') [[ $fields == 1 ]] || { shopt -u nocasematch; return 0; } ;;
    POST|PUT|PATCH|DELETE) ;;
    *) shopt -u nocasematch; return 0 ;;
  esac
  case $rest in
    *git/refs*|*/merge*|*/branches*|*/contents*|*refs/heads*|*refs/tags*)
      shopt -u nocasematch; deny shared-push "gh api write on refs, a merge, branches or contents moves a shared branch like a push; open a reviewed pull request instead" ;;
    *graphql*)
      if printf '%s' "$cmd" | grep -Eiq 'mergePullRequest|createRef|updateRef|deleteRef|CommitOnBranch|mergeBranch'; then
        shopt -u nocasematch; deny shared-push "a gh api graphql mutation that merges or moves a ref moves a shared branch like a push; open a reviewed pull request instead"
      fi ;;
  esac
  shopt -u nocasematch
}

# judge <one command segment>: tracks cd/pushd/popd in cur, then looks at every git and gh word of the segment
judge() {
  local IFS=$' \t\n' t saved=$cur envd=0
  # shellcheck disable=SC2086  # split on purpose; globbing is off
  set -- $1
  while [[ $# -gt 0 ]]; do
    case $1 in then|do|else|'{'|'!'|time|builtin|command|sudo|exec|nohup) shift ;; *) break ;; esac
  done
  case ${1:-} in
    cd|pushd)
      local verb=$1
      shift
      while [[ ${1:-} == -* && ${1:-} != - ]]; do shift; done
      if [[ $# -gt 0 ]]; then jp "$cur" "$1"; cur=$JP
      elif [[ $verb == cd ]]; then cur=${HOME:-?}
      else cur='?'; fi
      return ;;
    popd) cur='?'; return ;;
  esac
  while [[ $# -gt 0 ]]; do
    t=${1#\\}; shift
    case $t in GIT_DIR=*|GIT_WORK_TREE=*) cur='?'; envd=1; continue ;; esac
    case ${t##*/} in
      git) git_args "$@" ;;
      gh) gh_args "$@" ;;
    esac
  done
  [[ $envd == 0 ]] || cur=$saved
}

# the unwrap of sh -c "..." and eval "..." is the one in hooks/sabha-guard.sh: the string runs as a command, so it goes on
# its own line before the quotes are masked
unwrap_sh_c() {
  awk '
  function mask(s,   i, c, q, o) { o = ""; q = ""
    for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
      if (q == "") { if (c == "\"" || c == "'"'"'") q = c; o = o c }
      else if (c == q) { q = ""; o = o c } else o = o "x" }
    return o }
  { while (match(mask($0), /(^|[ \t;&|(])((ba|z|da)?sh[ \t]+-[A-Za-z]*c([ \t]+--)?|eval)[ \t]+("[^"]*"|'"'"'[^'"'"']*'"'"')/)) {
      st = RSTART; ln = RLENGTH; s = substr($0, st, ln); q = match(s, /["'"'"']/); s = substr(s, q + 1, length(s) - q - 1)
      $0 = substr($0, 1, st - 1) "\n" s "\n" substr($0, st + ln) }
    print }'
}

if on shared-push && [[ -n $cmd ]]; then
  bare=${cmd//[\"\'\\]/}
  case $bare in *push*|*" api"*)
    src=$cmd
    case $cmd in *eval*|*"sh -"*) src=$(printf '%s\n' "$cmd" | unwrap_sh_c) ;; esac
    # a quoted string with a space is data (a commit message): it becomes Q; other quotes are dropped; a string that holds
    # a $ or a backtick stays, so $(git push ...) inside double quotes is seen. Every command, subshell and substitution
    # goes on its own line.
    code=$(printf '%s\n' "$src" | sed -E \
      -e "s/\"[^\"\$\`]*[[:space:]][^\"\$\`]*\"/Q/g" \
      -e "s/'[^']*[[:space:]][^']*'/Q/g" \
      -e "s/[\"']//g" \
      -e 's/(&&?|\|\|?|;|\$\(|\(|\)|`)/\
/g')
    cur=${cwd:-.}
    set -f
    old_ifs=$IFS
    IFS=$'\n'
    for seg in $code; do
      IFS=$old_ifs
      judge "$seg"
      IFS=$'\n'
    done
    IFS=$old_ifs
    set +f ;;
  esac
fi
# ponytail: a push hidden in a variable (T=push; git $T), an alias, a split string or xargs input is a known gap

# ---- secret-read -------------------------------------------------------------------------------------------------
# secret_var <name>: an environment variable name that looks like it holds a secret
secret_var() {
  local r=1
  shopt -s nocasematch
  case $1 in *token*|*secret*|*password*|*passwd*|*credential*|*apikey*|*api_key*|*_key|*_key_*|key|*private_key*) r=0 ;; esac
  shopt -u nocasematch
  return $r
}

# dollar_secret <word>: the word reads $NAME or ${NAME} of a secret-looking variable
dollar_secret() {
  local n
  case $1 in *'$'*) ;; *) return 1 ;; esac
  # shellcheck disable=SC2016  # a regex, not an expansion
  for n in $(printf '%s\n' "$1" | grep -Eo '\$\{?[A-Za-z_][A-Za-z0-9_]*' | tr -d '${'); do
    secret_var "$n" && return 0
  done
  return 1
}

# leak_check <segment>: a command that dumps the environment or prints a secret variable, or a token out of gh
leak_check() {
  local IFS=$' \t\n' t flags=0 pflag=0 left=0 s=${1//[\"\']/}
  set -f
  # shellcheck disable=SC2086  # split on purpose; globbing is off
  set -- $s
  while [[ $# -gt 0 ]]; do
    case $1 in [A-Za-z_]*=*|command|builtin|exec|sudo|nohup|time|nice|'!'|'{'|then|do|else|\\) shift ;; *) break ;; esac
  done
  local cw=${1:-}
  cw=${cw##*/}
  cw=${cw#\\}
  [[ $# -gt 0 ]] && shift
  case $cw in
    env)
      while [[ $# -gt 0 ]]; do
        case $1 in
          -u|-C|-S|--unset|--chdir|--split-string) shift; [[ $# -gt 0 ]] && shift ;;
          -*|*=*) shift ;;
          *) break ;;
        esac
      done
      if [[ $# -eq 0 ]]; then deny secret-read "a bare env prints every variable, secrets included; name the one variable you need or ask the human"; fi
      leak_check "$*"; return ;;
    printenv)
      for t; do case $t in -*) ;; *) left=1; secret_var "$t" && deny secret-read "printenv of '$t' prints a secret; never read it, ask the human or the relay" ;; esac; done
      [[ $left == 1 ]] || deny secret-read "a bare printenv prints every variable, secrets included; name the one variable you need or ask the human" ;;
    set) [[ $# -gt 0 ]] || deny secret-read "a bare set prints every variable, secrets included" ;;
    export|declare|typeset)
      for t; do case $t in -*) flags=1; case $t in *p*|*x*) pflag=1 ;; esac ;; *) left=1 ;; esac; done
      if [[ $left == 0 ]] && { [[ $flags == 0 ]] || [[ $pflag == 1 ]]; }; then
        deny secret-read "$cw without a name lists every exported variable, secrets included"
      fi ;;
    echo|printf|print|cat|base64|head|tail)
      for t; do dollar_secret "$t" && deny secret-read "'$t' reads a secret variable; never print it, ask the human or the relay"; done ;;
    gh)
      case " $* " in
        *" auth token "*|*" auth status "*" -t "*|*" auth status "*" --show-token "*|*" auth status -t "*|*" auth status --show-token "*)
          deny secret-read "gh auth token prints a login token; never read it, ask the human or the relay" ;;
      esac ;;
  esac
}

if on secret-read; then
  if [[ -n $cmd ]]; then
    src=$cmd
    if [[ $msg_cmd == 1 ]]; then
      # the message argument of a commit or PR command is data
      src=$(printf '%s\n' "$cmd" | sed -E "s/(-[a-zA-Z]*m|--message|--body|--title|-b|-t)([[:space:]]+|=)?(\"[^\"]*\"|'[^']*')/\\1 Q/g")
    fi
    copied=
    IFS=$'\n'
    set -f
    for seg in $(printf '%s\n' "$src" | sed -E 's/(&&?|\|\|?|;|\$\(|\(|\)|`)/\
/g'); do
      leak_check "$seg"
      # cp of a secret file reads nothing only in one shape: one source, a directory named with a trailing slash (or the
      # same file name), as in cp <workspace>/guardians/.npmrc <worktree>/. Anything else (a /dev file, a file that a
      # later command cats) is refused.
      if printf '%s\n' "$seg" | grep -Eq '^[[:space:]]*cp[[:space:]]'; then
        unset IFS
        cps=${seg//[\"\']/}
        # shellcheck disable=SC2086  # split on purpose; globbing is off
        set -- $cps
        shift
        args=() complex=0
        for t; do
          case $t in -[pfvn]|-[pfvn][pfvn]) ;; -*) complex=1 ;; *) args[${#args[@]}]=$t ;; esac
        done
        nargs=${#args[@]} secret_src=0 i=0 lim=$((${#args[@]} - 1))
        [[ $complex == 0 ]] || lim=$nargs
        while [[ $i -lt $lim ]]; do is_secret "${args[$i]}" && secret_src=$((secret_src + 1)); i=$((i + 1)); done
        if [[ $secret_src -gt 0 ]]; then
          src1=${args[0]} dst=${args[$((nargs - 1))]}
          if [[ $complex == 1 || $secret_src -gt 1 || $nargs -ne 2 || $dst == /dev/* || $dst == /proc/* ]] ||
             ! { [[ $dst == */ ]] || [[ ${dst##*/} == "${src1##*/}" ]]; }; then
            deny secret-read "cp of a secret file can print or expose it; the one allowed shape is cp <secret> <directory>/ (a worktree), read by nothing else in the command"
          fi
          dst=${dst%/}
          copied="$copied $dst"
        fi
        IFS=$'\n'
        continue
      fi
      unset IFS
      for w in $(printf '%s\n' "$seg" | tr -s " \t\"'(),<>{}" '\n'); do
        is_secret "$w" && deny secret-read "'$w' is a secret file; never read, list or print it, ask the human or the relay"
        case $w in /proc/*/environ*|*/proc/*/environ*) deny secret-read "'$w' holds the environment, secrets included; never read it" ;; esac
        for c in $copied; do case $w in "$c"|"$c"/*) deny secret-read "'$w' is where a secret file was just copied; do not read it in the same command" ;; esac; done
      done
      IFS=$'\n'
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
