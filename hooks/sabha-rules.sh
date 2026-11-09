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

# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || deny setup "hooks/lib.sh is missing next to this hook"
hk_rule_conf
rules=$HK_RULES shared=$HK_SHARED exempt=$HK_EXEMPT
all_rules="ascii attribution shared-push secret-read"
[[ -n $rules ]] || rules=$all_rules
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
      ((if $t == "Write" then $i.content elif $t == "Edit" then $i.new_string
        elif $t == "MultiEdit" then [($i.edits // [])[].new_string // ""] | join("\n")
        elif $t == "NotebookEdit" then $i.new_source else "" end // "")
       | if . == "" then "" else
           "\(utf8bytelength - ([explode[] | select(. < 128)] | length)) \(if test("(^|\n)[ \t\r\f\u000b]*(\($mark))"; "i") then 1 else 0 end)"
         end),
      (if $t == "Bash" then (if $size_guard == "1" and ($i.command | utf8bytelength) > 16384 then "SABHA_TOOLONG" else $i.command end) else "" end),
      (if $t == "Read" then $i.file_path
       elif $t == "Grep" then [$i.path // "", $i.glob // ""] | join("\n")
       elif $t == "Glob" then [$i.path // "", $i.pattern // ""] | join("\n") else "" end // "")
    ]
  else empty end
else empty end
| map(gsub("\u001f"; " ")) | join("\u001f")'
# a command over 16 KB is replaced by a marker inside jq: cutting the fields apart below is quadratic on bash 3.2. For the
# same reason file text never reaches bash: jq hands back "<non-ASCII bytes> <1 if a line starts with the marker>".
size_guard=0
if on shared-push || on secret-read; then size_guard=1; fi
mark='co-authored-by:|generated (with|by)[^a-z]*(claude|chatgpt|copilot|gemini|codex|an? ai|ai)|noreply@anthropic\.com'
rec=$(printf '%s' "$in" | jq -er --arg size_guard "$size_guard" --arg mark "$mark" "$jq_prog" 2>/dev/null) ||
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

# Size guard first: bash 3.2 is quadratic on a very long word and a hook that times out lets the call through, so a huge
# command is refused before any pass that scans it.
if [[ $tool == Bash && -n $cmd ]] && { on shared-push || on secret-read; }; then
  if [[ $cmd == SABHA_TOOLONG || ${#cmd} -gt 16384 ]] || printf '%s\n' "$cmd" | awk '{ for (i = 1; i <= NF; i++) if (length($i) > 8192) f = 1 } END { exit !f }'; then
    deny size "the command is too long to check in time (over 16 KB, or one word over 8 KB); split it, or write the data to a file with the Write tool"
  fi
fi

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

# is_secret <word>: the last part after / : = or @ (curl -d @file) names a secret file, in any case (APFS is case-insensitive). Covers
# .env, .env.*, .<name>.env, .envrc, .npmrc, .yarnrc.yml, .pypirc, .netrc, .pgpass, .htpasswd, .vault-token,
# .git-credentials, kubeconfig, credentials*, creds, secrets.y*ml, terraform.tfvars, *.pem, *.key, *.pfx, *.p12,
# *.keystore, id_rsa-style keys, .aws/, .ssh/config, .git/config, .docker/config.json, gh/hosts.yml.
# *.example, *.sample, *.template and *.pub (public keys) are not secrets.
is_secret() {
  local n=${1##*[/:=@]} hit=1
  n=${n#-[A-Za-z]}  # an attached short-option value: wget -i.env
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
  chk=
  [[ $msg_cmd == 1 ]] && chk=$cmd
  if [[ -z $chk && -n $cmd ]] && [[ $cmd == *[!$'\001'-$'\177']* ]]; then
    # a shell command writing a file (heredoc, redirect, tee) is a Write; a bare echo is not
    if printf '%s\n' "$cmd" | sed -E 's#[0-9&]*>>?[[:space:]]*(/dev/null|&[0-9-]+)##g' | grep -Eq '<<[^<]|>|(^|[[:space:]])tee[[:space:]]'; then chk=$cmd; fi
  fi
  if { [[ -n $chk ]] || [[ -n $text ]]; } && ! { [[ -n $path ]] && glob_in "$path" "$exempt"; }; then
    if [[ -n $chk ]]; then bad=$(printf '%s' "$chk" | LC_ALL=C tr -d '\000-\177' | wc -c | tr -d ' '); else bad=${text%% *}; fi
    [[ $bad == 0 ]] || deny ascii "$bad non-ASCII byte(s); use plain ASCII (-> not an arrow, - not a dash, straight quotes)"
  fi
fi

if on attribution; then
  hit=1
  if [[ $msg_cmd == 1 ]]; then
    printf '%s\n' "$cmd" | grep -Eiq "$mark" && hit=0
  elif [[ -n $text ]]; then
    # file text: only a line that starts with the marker, so a note that discusses the rule can be written
    [[ ${text#* } == 1 ]] && hit=0
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
    # a substitution anywhere (remote, option value, refspec) hides where the push goes: git push $(echo origin) HEAD:main
    case $tok in *__SUBST__*) deny shared-push "this push holds a command substitution the hook cannot read; name the remote and your own feature branch literally" ;; esac
    if [[ $skip == 1 ]]; then skip=0; continue; fi
    case $tok in
      --all|--al|--mirror|--mirro|--mirr|--mir|--mi|--m) deny shared-push "git push $tok reaches every branch, shared ones included (git accepts an abbreviated option); push your own branch by name" ;;
      --repo|--rep) skip=1; n=1; continue ;;
      --repo=*|--rep=*) n=1; continue ;;
      -o|--push-option|--receive-pack|--exec) skip=1; continue ;;
      -*) continue ;;
    esac
    n=$((n + 1))
    [[ $n -gt 1 ]] || continue
    refs=$((refs + 1))
    # the whole refspec "$(git branch --show-current)" is the current branch; split_code marks only that form
    [[ $tok == __CURBR__\$ ]] && tok=HEAD
    # a lone : or +: pushes every matching branch, main included when the local one is ahead
    case $tok in :|+:|+) deny shared-push "the refspec '$tok' pushes every matching branch, shared ones included; push your own branch by name" ;; esac
    # before the colon cut: ${B:-main} would otherwise lose its $
    case $tok in *'$'*|*'`'*|*'{'*) deny shared-push "the refspec '$tok' holds a shell expansion the hook cannot read; name your own feature branch literally" ;; esac
    dest=${tok#+}
    case $dest in *:*) dest=${dest##*:} ;; esac
    # git reads refs/heads/x, heads/x and x as the same branch
    while :; do case $dest in refs/*) dest=${dest#refs/} ;; heads/*) dest=${dest#heads/} ;; *) break ;; esac; done
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

# push_key <key=value>: a git config entry that routes a push where the hook cannot read it. git reads section and key
# names in any case.
push_key() {
  local r=1
  shopt -s nocasematch
  case $1 in remote.*.push=*|remote.*.pushurl=*|remote.*.mirror=*|alias.*|push.default=matching*) r=0 ;; esac
  shopt -u nocasematch
  return $r
}

# git_args <words after "git">: skips git's options (-C dir moves the directory), then judges a push
git_args() {
  local d=$cur t
  while [[ $# -gt 0 ]]; do
    case $1 in
      -C) jp "$d" "${2:-}"; d=$JP; shift; [[ $# -gt 0 ]] && shift ;;
      -c)
        push_key "${2:-}" && deny shared-push "git -c ${2:-} can route a push to a shared branch (a configured refspec, a mirror, matching or an alias) where the hook cannot read it; name the refspec on the command line"
        shift; [[ $# -gt 0 ]] && shift ;;
      --config-env|--config-env=*) deny shared-push "git $1 sets config from a variable the hook cannot read (a push refspec or an alias can hide there); use -c with a literal value" ;;
      --namespace|--super-prefix|--exec-path) shift; [[ $# -gt 0 ]] && shift ;;
      config)
        shift
        # a read only when the first word after the scope options is a read: --get x --list is a read, x y --list a write
        while [[ $# -gt 0 ]]; do
          case $1 in --global|--local|--system|--worktree|--includes|--no-includes|--file=*|--blob=*|--type=*) shift ;; --file|-f|--blob|--type) shift; [[ $# -gt 0 ]] && shift ;; *) break ;; esac
        done
        case ${1:-} in --get*|--unset*|--list|-l|get|list|unset) return ;; esac
        while [[ $# -gt 0 ]]; do
          push_key "$1=${2:-}" && deny shared-push "git config $1 can route a push to a shared branch where the hook cannot read it; name the refspec on the command line"
          shift
        done
        return ;;
      --git-dir|--work-tree) d='?'; shift; [[ $# -gt 0 ]] && shift ;;
      --git-dir=*|--work-tree=*) d='?'; shift ;;
      -*) shift ;;
      push) shift; [[ $gd$gw == 00 ]] || d='?'; push_args "$d" "$@"; return ;;
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
      if printf '%s' "$ncmd" | grep -Eiq 'mergePullRequest|createRef|updateRef|deleteRef|CommitOnBranch|mergeBranch'; then
        shopt -u nocasematch; deny shared-push "a gh api graphql mutation that merges or moves a ref moves a shared branch like a push; open a reviewed pull request instead"
      fi ;;
  esac
  shopt -u nocasematch
}

# judge <one command segment>: tracks cd/pushd/popd in cur, then looks at every git and gh word of the segment
judge() {
  local IFS=$' \t\n' t saved=$cur envd=0 inenv=0 allas=1 uf=0
  # shellcheck disable=SC2086  # split on purpose; globbing is off
  set -- $1
  while [[ $# -gt 0 ]]; do
    case $1 in then|do|else|'{'|'!'|time|builtin|command|sudo|exec|nohup) shift ;; *) break ;; esac
  done
  # git config can come from the environment too: a configured push refspec or an alias hides the branch from the hook
  for t; do
    case $t in GIT_CONFIG_*=*) deny shared-push "$t can route a push to a shared branch (a configured refspec or an alias) where the hook cannot read it; name the refspec on the command line" ;; esac
  done
  # GIT_DIR or GIT_WORK_TREE set as a command of its own (export, declare, a bare assignment) holds for the rest of the
  # command, so every later push has an unknown directory until it is unset
  case ${1:-} in
    export|declare|typeset|readonly) for t in "${@:2}"; do case $t in GIT_DIR|GIT_DIR=*) gd=1 ;; GIT_WORK_TREE|GIT_WORK_TREE=*) gw=1 ;; esac; done ;;
    unset) uf=0  # unset -f names a function, so GIT_DIR stays set
      for t in "${@:2}"; do case $t in -v) ;; -*) uf=1 ;; esac; done
      if [[ $uf == 0 ]]; then for t in "${@:2}"; do case $t in GIT_DIR) gd=0 ;; GIT_WORK_TREE) gw=0 ;; esac; done; fi ;;
    *) for t; do case $t in [A-Za-z_]*=*) ;; *) allas=0 ;; esac; done
       if [[ $allas == 1 && $# -gt 0 ]]; then
         for t; do case $t in GIT_DIR=*) gd=1 ;; GIT_WORK_TREE=*) gw=1 ;; esac; done
       fi ;;
  esac
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
    if [[ $inenv == 1 ]]; then
      # env -C dir (--chdir) moves the directory for the command it runs
      case $t in
        -C|--chdir) jp "$cur" "${1:-}"; cur=$JP; envd=1; [[ $# -gt 0 ]] && shift; continue ;;
        --chdir=*) jp "$cur" "${t#*=}"; cur=$JP; envd=1; continue ;;
        -u|--unset) [[ $# -gt 0 ]] && shift; continue ;;
        -*|*=*) continue ;;
        *) inenv=0 ;;
      esac
    fi
    case ${t##*/} in
      env) inenv=1 ;;
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
  { while (match(mask($0), /(^|[ \t;&|(\/])((ba|z|da|k)?sh([ \t]+(--?[A-Za-z][-A-Za-z]*|[-+]O[ \t]+[A-Za-z]+))*[ \t]+-[A-Za-z]*c([ \t]+--)?|(ba|z|da|k)?sh[ \t]+<<<|eval|env[ \t]+(-[A-Za-z]+[ \t]+)*-[A-Za-z]*S)[ \t]*("[^"]*"|'"'"'[^'"'"']*'"'"')/)) {
      st = RSTART; ln = RLENGTH; s = substr($0, st, ln); q = match(s, /["'"'"']/); s = substr(s, q + 1, length(s) - q - 1)
      $0 = substr($0, 1, st - 1) "\n" s "\n" substr($0, st + ln) }
    print }'
}

# split_code: one line per command, subshell and substitution, words split by blanks, for judge. A left-to-right scan
# (a regex pairs a closing quote with the next opening one and swallows the command between them): a quoted word keeps
# its text with blanks as _, so a quoted ; or a message is data and "origin" "main" still reads as origin main. $( and
# backticks, also inside double quotes, start code on a line of their own after a __SUBST__$ word, so the push they
# cut is not read as a bare push; the two substitutions that print the current branch become __CURBR__$ instead. A
# heredoc body is judged line by line with fresh quotes (bash <<EOF runs it; an apostrophe in a message must not leak).
# Exit 3 when a quote or a substitution is left open.
split_code() {
  awk '
  function pop(st) { return substr(st, 1, length(st) - 1) }
  function blank(c) { return (c == " " || c == "\t" || c == "\n") ? "_" : c }
  function scan(s, body,   n, i, j, c, nx, t, st, out, d, k, e, ln, cmp, cb1, cb2, strip) {
    cb1 = "$(git branch --show-current)"; cb2 = "$(git rev-parse --abbrev-ref HEAD)"
    n = length(s); st = "c"; out = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); nx = substr(s, i + 1, 1); t = substr(st, length(st))
      if (t == "q") { if (c == "\047") st = pop(st); else out = out blank(c); continue }
      if (t == "a") { if (c == "\\") { out = out blank(nx); i++ } else if (c == "\047") st = pop(st); else out = out blank(c); continue }
      if (t == "d") {
        if (c == "\\") { out = out blank(nx); i++ }
        else if (c == "\"") st = pop(st)
        else if (c == "$" && nx == "(") {
          if (index(substr(s, i), cb1) == 1) { out = out "__CURBR__$"; i += length(cb1) - 1 }
          else if (index(substr(s, i), cb2) == 1) { out = out "__CURBR__$"; i += length(cb2) - 1 }
          else { out = out " __SUBST__$ \n"; st = st "p"; i++ }
        }
        else if (c == "`") { out = out " __SUBST__$ \n"; st = st "b" }
        else out = out blank(c)
        continue
      }
      # code: c top, p $( ), P ( ), b backticks
      if (c == "\\") { if (nx != "\n") out = out blank(nx); i++ }
      # a comment runs to the end of the line: the shell runs none of it, and an apostrophe there opens nothing
      else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n;&|(]/)) { while (i < n && substr(s, i + 1, 1) != "\n") i++ }
      else if (c == "\047") st = st "q"
      else if (c == "$" && nx == "\047") { out = out "$"; st = st "a"; i++ }
      else if (c == "\"") st = st "d"
      else if (c == "$" && nx == "(") {
        if (index(substr(s, i), cb1) == 1) { out = out "__CURBR__$"; i += length(cb1) - 1 }
        else if (index(substr(s, i), cb2) == 1) { out = out "__CURBR__$"; i += length(cb2) - 1 }
        else { out = out " __SUBST__$ \n"; st = st "p"; i++ }
      }
      else if (c == "`") { if (t == "b") { st = pop(st); out = out "\n" } else { st = st "b"; out = out " __SUBST__$ \n" } }
      else if (c == "(") { st = st "P"; out = out "\n" }
      else if (c == ")") { if (t == "p" || t == "P") st = pop(st); out = out "\n" }
      else if (c == ";" || c == "&" || c == "|") out = out "\n"
      else if (c == "<" && substr(s, i, 3) == "<<<") { out = out "<<<"; i += 2 }
      else if (c == "<" && nx == "<" && !body) {
        j = i + 2; strip = 0
        if (substr(s, j, 1) == "-") { strip = 1; j++ }
        while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
        d = ""
        while (j <= n && substr(s, j, 1) !~ /[ \t\n;&|()<>]/) { if (substr(s, j, 1) !~ /[\\"\047]/) d = d substr(s, j, 1); j++ }
        if (d != "") { hd++; hdd[hd] = d; hdt[hd] = strip }
        out = out " "; i = j - 1
      }
      else if (c == "\n") {
        out = out "\n"
        for (k = 1; k <= hd && i < n; k++) {
          while (i < n) {
            e = index(substr(s, i + 1), "\n"); ln = e ? substr(s, i + 1, e - 1) : substr(s, i + 1); i += e ? e : length(ln)
            cmp = ln; if (hdt[k]) sub(/^\t+/, "", cmp)
            if (cmp == hdd[k]) break
            out = out scan(ln, 1) "\n"
          }
        }
        hd = 0
      }
      else out = out c
    }
    if (st != "c" && !body) OPEN = 1
    return out
  }
  { s = s (NR > 1 ? "\n" : "") $0 }
  END { out = scan(s, 0); if (OPEN) exit 3; print out }'
}

# The two rules that walk a command word by word get it with line continuations joined and every other backslash
# deleted (g\it, pu\sh, .e\nv are the same words to the shell); the size guard near the top has already run.
ncmd=
if [[ -n $cmd ]] && { on shared-push || on secret-read; }; then
  bsnl=$'\\\n'
  ncmd=${cmd//"$bsnl"/}
  ncmd=$(printf '%s\n' "$ncmd" | sed -E 's/\\([^"'"'"'])/\1/g')
fi

if on shared-push && [[ -n $ncmd ]]; then
  bare=${ncmd//[\"\']/}
  case $bare in *push*|*" api"*|*config-env*)
    code=$(printf '%s\n' "$ncmd" | unwrap_sh_c | split_code) ||
      deny shared-push "a quote or a \$( substitution is left open, so the hook cannot tell the words of this command apart; close it"
    cur=${cwd:-.} gd=0 gw=0
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
  local IFS=$' \t\n' t flags=0 pflag=0 pname=0 left=0 s=${1//[\"\']/}
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
    eval) [[ $# -gt 0 ]] && leak_check "$*" ;;
    bash|sh|zsh|dash|ksh)
      # the words after -c are a command line of their own
      while [[ $# -gt 0 ]]; do
        case $1 in
          -O|+O) shift; [[ $# -gt 0 ]] && shift ;;
          --*) shift ;;
          -*c*) shift; [[ $# -gt 0 ]] && leak_check "$*"; return ;;
          -*) shift ;;
          *) break ;;
        esac
      done ;;
    printenv)
      for t; do case $t in -*) ;; *) left=1; secret_var "$t" && deny secret-read "printenv of '$t' prints a secret; never read it, ask the human or the relay" ;; esac; done
      [[ $left == 1 ]] || deny secret-read "a bare printenv prints every variable, secrets included; name the one variable you need or ask the human" ;;
    set) [[ $# -gt 0 ]] || deny secret-read "a bare set prints every variable, secrets included" ;;
    export|declare|typeset)
      for t; do case $t in -*) flags=1; case $t in *p*|*x*) pflag=1 ;; esac; case $t in *p*) pname=1 ;; esac ;; *) left=1 ;; esac; done
      if [[ $left == 0 ]] && { [[ $flags == 0 ]] || [[ $pflag == 1 ]]; }; then
        deny secret-read "$cw without a name lists every exported variable, secrets included"
      fi
      if [[ $pname == 1 ]]; then
        for t; do case $t in -*|*=*) ;; *) secret_var "$t" && deny secret-read "$cw -p of '$t' prints a secret; never read it, ask the human or the relay" ;; esac; done
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
  if [[ -n $ncmd ]]; then
    src=$ncmd
    if [[ $msg_cmd == 1 ]]; then
      # the message argument of a commit or PR command is data
      src=$(printf '%s\n' "$ncmd" | sed -E "s/(-[a-zA-Z]*m|--message|--body|--title|-b|-t)([[:space:]]+|=)?(\"[^\"]*\"|'[^']*')/\\1 Q/g")
    fi
    # the string of sh -c, eval and env -S runs as a command: it gets its own line
    src=$(printf '%s\n' "$src" | unwrap_sh_c)
    copied=
    IFS=$'\n'
    set -f
    # a cp with a substitution in its arguments is judged whole, before the cut at $( leaves it without a destination: a
    # secret named on the line, or a /dev or /proc path, is refused
    for seg in $(printf '%s\n' "$src" | sed -E 's/(&&?|\|\|?|;)/\
/g'); do
      case $seg in *'$('*|*'`'*)
        if printf '%s\n' "$seg" | grep -Eq '(^|[^[:alnum:]_.-])cp[[:space:]]'; then
          unset IFS
          for w in $(printf '%s\n' "$seg" | tr -s " \t\"'(),<>{}@" '\n'); do
            is_secret "$w" && deny secret-read "'$w' is a secret file on a cp line with a substitution the hook cannot read; name the destination literally"
            case $w in /dev/*|/proc/*) deny secret-read "a cp line with a substitution and a '$w' path cannot be judged; name the destination literally" ;; esac
          done
          IFS=$'\n'
        fi ;;
      esac
    done
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
      for w in $(printf '%s\n' "$seg" | tr -s " \t\"'(),<>{}@" '\n'); do
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
