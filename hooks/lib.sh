# Sourced by the sabha hooks, never run. Every function fails soft: a hook must never break a session.
# shellcheck shell=bash disable=SC2034  # HK_* are read by the hooks that source this file

HK_DIR=${BASH_SOURCE[0]}
if [[ $HK_DIR == */* ]]; then HK_DIR=${HK_DIR%/*}; HK_DIR=${HK_DIR:-/}; else HK_DIR=.; fi  # no dirname: PATH must not pick the lib
HK_DIR=$(cd "$HK_DIR" && pwd)

# hk_lower <text>: bash 3.2 has no ${x,,}
hk_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# hk_rule_conf: the one place the rule hooks (sabha-rules.sh, git-pre-push.sh) read their settings. Sets HK_RULES,
# HK_SHARED and HK_EXEMPT from the environment, else SABHA_CONF; HK_SHARED falls back to the default list when it is
# empty or has no non-space character. "hk_rule_conf prepush" does not trust the push's own environment: SABHA_CONF is
# ignored (only the sabha.conf beside the scripts is read) and SABHA_SHARED_BRANCHES and that conf can only ADD to the
# default list, never replace it.
hk_rule_conf() {
  local vals conf=${SABHA_CONF:-} def="main master dev develop staging release/*" envs=${SABHA_SHARED_BRANCHES:-} cfgs=
  [[ ${1:-} == prepush ]] && conf=$HK_DIR/../sabha.conf
  HK_RULES=${SABHA_RULES:-} HK_SHARED=$envs HK_EXEMPT=${SABHA_ASCII_EXEMPT:-}
  if [[ -n $conf && -f $conf ]]; then
    # the conf runs in its own bash and hands back only these three values
    # shellcheck disable=SC2016  # expanded by the inner bash
    vals=$("$BASH" -c 'set +u; . "$1" >/dev/null 2>&1; printf "%s\n" "${SABHA_RULES:-}" "${SABHA_SHARED_BRANCHES:-}" "${SABHA_ASCII_EXEMPT:-}"' _ "$conf" 2>/dev/null) || vals=
    # lines 1-3 of $vals by expansion: no sed (PATH is not trusted in the pre-push hook) and no here-string (it needs a temp file)
    local v1 v2 v3 r nl=$'\n'
    v1=${vals%%"$nl"*}; r=${vals#"$v1"}; r=${r#"$nl"}
    v2=${r%%"$nl"*}; r=${r#"$v2"}; r=${r#"$nl"}
    v3=${r%%"$nl"*}
    [[ -n $HK_RULES ]] || HK_RULES=$v1
    cfgs=$v2
    [[ -n $HK_SHARED ]] || HK_SHARED=$cfgs
    [[ -n $HK_EXEMPT ]] || HK_EXEMPT=$v3
  fi
  [[ ${1:-} == prepush ]] && HK_SHARED="$def $envs $cfgs"
  [[ $HK_SHARED == *[![:space:]]* ]] || HK_SHARED=$def
}

# hk_init: reads the hook JSON from stdin into HK_INPUT, then sets HK_ROLE (as written in the roster, or Name-N for a
# copy), HK_IMPL and HK_RELAY. Returns 1 when this session is not a sabha role, so callers exit 0 untouched.
# Role order: $SABHA_ROLE, then .session_name of the hook JSON (jq when present, sed otherwise).
hk_init() {
  HK_INPUT=
  [ -t 0 ] || HK_INPUT=$(cat 2>/dev/null) || HK_INPUT=
  HK_ROLE=${SABHA_ROLE:-}
  if [ -z "$HK_ROLE" ] && [ -n "$HK_INPUT" ]; then
    if command -v jq >/dev/null 2>&1; then
      HK_ROLE=$(printf '%s' "$HK_INPUT" | jq -r '.session_name // empty' 2>/dev/null) || HK_ROLE=
    else
      HK_ROLE=$(printf '%s' "$HK_INPUT" |
        sed -n 's/.*"session_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    fi
  fi
  [ -n "$HK_ROLE" ] || return 1
  case $HK_ROLE in *[!A-Za-z0-9_-]*) return 1 ;; esac

  # the roster comes from sabha-lib.sh in a subshell: its failures call exit, which must not reach the hook
  local lib=$HK_DIR/../bin/sabha-lib.sh out impl_env=${SABHA_IMPL:-}
  [ -f "$lib" ] || return 1
  out=$(
    # shellcheck source=/dev/null
    . "$lib" 2>/dev/null || exit 1
    sabha_load hook >/dev/null 2>&1 || exit 1
    printf '%s\n%s\n%s\n' "$RELAY" "${impl_env:-$SABHA_IMPL}" "${NAMES[*]}"
  ) 2>/dev/null || return 1
  [ -n "$out" ] || return 1
  HK_RELAY=$(printf '%s\n' "$out" | sed -n 1p)
  HK_IMPL=$(printf '%s\n' "$out" | sed -n 2p)
  local names base
  names=$(printf '%s\n' "$out" | sed -n 3p)
  base=$HK_ROLE
  case " $names " in *" $base "*) ;; *)
    base=${HK_ROLE%-*}
    case ${HK_ROLE##*-} in ''|*[!0-9]*) return 1 ;; esac
    case " $names " in *" $base "*) ;; *) return 1 ;; esac
    ;;
  esac
  HK_BASE=$base
  [ -n "$HK_IMPL" ] && [ -d "$HK_IMPL" ] || return 1
  return 0
}

# hk_open_briefs <all|acked>: prints the number and file name of each brief in the role's inbox that has no .done and
# no .cancel; "acked" keeps only those the role already acknowledged.
hk_open_briefs() {
  local dir=$HK_IMPL/inbox/$HK_ROLE f b n
  [ -d "$dir" ] || return 0
  for f in "$dir"/[0-9][0-9][0-9]*-*.md; do
    [ -f "$f" ] || continue
    b=${f##*/}
    n=${b%%-*}
    [ -e "$dir/$n.done" ] || [ -e "$dir/$n.cancel" ] && continue
    [ "$1" = acked ] && [ ! -e "$dir/$n.ack" ] && continue
    printf '%s\n' "$b"
  done
}

hk_status_file() { printf '%s/status/%s.md' "$HK_IMPL" "$(hk_lower "$HK_ROLE")"; }
