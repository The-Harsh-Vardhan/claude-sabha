#!/usr/bin/env bash
# PreToolUse(Bash): only the relay may reach outside the machine; every other role hands the human a brief instead.
# A safety net for honest mistakes, not enforcement (SECURITY.md): a role that wants to push can get around a text check.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0
if ! hk_init; then
  # a session that says it is a sabha role but cannot be matched to the roster must not run unguarded
  if [ -n "${SABHA_ROLE:-}" ]; then
    echo "sabha-guard: SABHA_ROLE=$SABHA_ROLE is set but the role could not be resolved (roster, SABHA_CONF or SABHA_IMPL); fix the config or unset SABHA_ROLE" >&2
    exit 2
  fi
  exit 0
fi
[ "$HK_BASE" = "$HK_RELAY" ] && exit 0

# jq gives the exact command; without it the command field is cut out of the raw JSON and its \n \t \" unescaped
cmd=
command -v jq >/dev/null 2>&1 && cmd=$(printf '%s' "$HK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$cmd" ]; then
  cmd=$(printf '%s' "$HK_INPUT" | tr -d '\n' |
    sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/' | sed 's/\\"/"/g')
  cmd=$(printf '%b' "$cmd")
fi
[ -n "$cmd" ] || exit 0

# heredoc bodies are data, not commands: drop every line between a << marker and its terminator. A here-string (<<<),
# an arithmetic shift ((1 << n)) and a quoted "<<EOF" are not markers, so they are blanked before the marker is looked for
code=$(printf '%s\n' "$cmd" | awk '
  hd != "" { t = $0; sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  { t = $0; gsub(/<<</, " ", t); gsub(/\(\([^)]*\)\)/, " ", t)
    while (match(t, /<<-?[ \t]*["'"'"'][A-Za-z_][A-Za-z0-9_]*["'"'"']/)) {
      w = substr(t, RSTART, RLENGTH); gsub(/[^A-Za-z0-9_]/, "", w); t = substr(t, 1, RSTART - 1) "<<" w substr(t, RSTART + RLENGTH) }
    gsub(/"[^"]*"/, " ", t); gsub(/'"'"'[^'"'"']*'"'"'/, " ", t)
    if (match(t, /<<-?[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) { hd = substr(t, RSTART, RLENGTH); sub(/<<-?[ \t]*/, "", hd) }
    print }')
# sh -c "..." and eval "..." run their string as a command: unquote it onto its own line before the quote strip.
# The match runs on a copy with quoted text masked, so "see: sh -c 'git push'" inside a commit message stays data
# ponytail: one quoting level only; sh -c "$CMD" or a split string is a known gap (SECURITY.md)
code=$(printf '%s\n' "$code" | awk '
  function mask(s,   i, c, q, o) { o = ""; q = ""
    for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
      if (q == "") { if (c == "\"" || c == "'"'"'") q = c; o = o c }
      else if (c == q) { q = ""; o = o c } else o = o "x" }
    return o }
  { while (match(mask($0), /(^|[ \t;&|(])((ba|z|da)?sh[ \t]+-[A-Za-z]*c([ \t]+--)?|eval)[ \t]+("[^"]*"|'"'"'[^'"'"']*'"'"')/)) {
      st = RSTART; ln = RLENGTH; s = substr($0, st, ln); q = match(s, /["'"'"']/); s = substr(s, q + 1, length(s) - q - 1)
      $0 = substr($0, 1, st - 1) "\n" s "\n" substr($0, st + ln) }
    print }')
# quoted strings are data too (commit messages, grep patterns, echo text); ponytail: no escaped-quote handling
code=$(printf '%s\n' "$code" | sed -e "s/\"[^\"]*\"//g" -e "s/'[^']*'//g")
# one command per line: split on the shell operators and keywords, then drop env assignments, wrappers and a path prefix
code=$(printf '%s\n' "$code" | awk '{ gsub(/&&?|\|\|?|;|\$?\(|\)|\{|\}|`/, "\n"); gsub(/(^|[ \t])(then|do|else)([ \t]|$)/, "\n"); print }' |
  sed -E 's/^[[:space:]]+//; s/^(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|exec|time|nohup|env|sudo|nice|timeout[[:space:]]+[0-9]+[a-z]?)[[:space:]]+)*//; s/^\\//; s#^[^[:space:]]*/##')

git_pre='^git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+'
gh_pre='^gh([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+'
git_push="${git_pre}push([[:space:]]|\$)"
# a new or changed remote is the first step of a push somewhere the human did not pick
git_remote="${git_pre}remote[[:space:]]+(add|set-url)([[:space:]]|\$)"
gh_write="${gh_pre}(pr[[:space:]]+(create|merge|comment|edit|review|close|reopen|ready)|issue[[:space:]]+(create|comment|edit|close|reopen|delete|transfer)|release[[:space:]]+(create|edit|delete|upload)|repo[[:space:]]+(create|edit|delete|rename|archive|fork|sync)|gist[[:space:]]+(create|edit|delete)|secret[[:space:]]+(set|delete)|workflow[[:space:]]+run)([[:space:]]|\$)"
# gh api is a read unless it names a write method or sends fields (gh then defaults to POST)
gh_api_write='[[:space:]](-X|--method)([[:space:]]+|=)?(POST|PUT|PATCH|DELETE)|[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]]|=|$)'
# a webhook URL is often quoted, so the host is looked for in the raw command, and only when a network client runs
hook_host='hooks\.slack\.com|slack\.com/api/|discord(app)?\.com/api/webhooks|api\.telegram\.org/bot|webhook\.office\.com|outlook\.office\.com/webhook'
client='^(curl|wget|http|https|xh|python[0-9.]*|node|deno|bun|ruby|perl|php|nc|ncat|pwsh|powershell|Invoke-WebRequest|Invoke-RestMethod|iwr|irm)([[:space:]]|$)'
if printf '%s\n' "$code" | grep -Eq "$git_push|$git_remote|$gh_write" ||
   printf '%s\n' "$code" | grep -E "${gh_pre}api([[:space:]]|\$)" | grep -Eiq -- "$gh_api_write" ||
   { printf '%s' "$cmd" | grep -Eiq "$hook_host" && printf '%s\n' "$code" | grep -Eq "$client"; }; then
  echo "sabha-guard: only the human pushes, publishes or posts; write a brief to the relay ($HK_RELAY)" >&2
  exit 2
fi
exit 0
