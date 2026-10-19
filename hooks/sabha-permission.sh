#!/usr/bin/env bash
# PermissionRequest: a worker's permission prompt goes to the human through the relay (docs/inbox-protocol.md
# section 9). Writes <IMPL>/inbox/<relay>/permissions/<Role>-NNN.req with the tool input verbatim, nudges the relay,
# and waits for a decision file that carries the request's nonce. Every other path (not a role, the relay itself,
# an error, no answer in SABHA_RELAY_WAIT seconds) exits 0 with no stdout: the ordinary prompt shows in the pane.
# Never an auto-allow. Bash 3.2 safe; no jq needed (the JSON is cut by the awk below, byte for byte).
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0
hk_init || exit 0
# the relay's own prompts stay the human's, in its own pane
[ "$HK_BASE" = "$HK_RELAY" ] && exit 0

# hp_field <key>: the raw text of a top-level value of the hook JSON (a string keeps its quotes). A scan that knows
# strings and nesting, so a "tool_name" or "permission_mode" inside the tool input can never be read as the real one
hp_field() {
  printf '%s' "$HK_INPUT" | awk -v want="$1" 'BEGIN { RS = "\001" } {
    s = $0; n = length(s); d = 0; i = 1
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\"") {
        j = i + 1
        while (j <= n) { c = substr(s, j, 1); if (c == "\\") j += 2; else if (c == "\"") break; else j++ }
        key = substr(s, i + 1, j - i - 1); i = j + 1
        if (d != 1) continue
        k = i; while (substr(s, k, 1) ~ /[ \t\r\n]/) k++
        if (substr(s, k, 1) != ":" || key != want) continue
        k++; while (substr(s, k, 1) ~ /[ \t\r\n]/) k++
        st = k; vd = 0
        while (k <= n) {
          c = substr(s, k, 1)
          if (c == "\"") { k++; while (k <= n) { c = substr(s, k, 1); if (c == "\\") k += 2; else if (c == "\"") break; else k++ } }
          else if (c == "{" || c == "[") vd++
          else if (c == "}" || c == "]") { if (vd == 0) break; vd-- }
          else if (c == "," && vd == 0) break
          k++
        }
        v = substr(s, st, k - st); sub(/[ \t\r\n]+$/, "", v); printf "%s", v; exit
      }
      if (c == "{" || c == "[") d++; else if (c == "}" || c == "]") d--
      i++
    }
  }' 2>/dev/null
}
hp_str() { local v; v=$(hp_field "$1"); v=${v#\"}; printf '%s' "${v%\"}"; }

mode=$(hp_str permission_mode)
case $mode in bypassPermissions|dontAsk) exit 0 ;; esac
input=$(hp_field tool_input)
[ -n "$input" ] || exit 0
tool=$(hp_str tool_name)
case $tool in ''|*[!A-Za-z0-9_.:-]*) tool=unknown ;; esac
case $mode in *[!A-Za-z]*) mode=unknown ;; esac

# the wait and the push settings come from sabha.conf (env wins when the config does not set them)
conf=$(
  . "$HK_DIR/../bin/sabha-lib.sh" 2>/dev/null || exit 1
  sabha_conf_read hook >/dev/null 2>&1 || exit 1
  printf '%s\n%s\n%s\n%s\n%s\n' "${SABHA_RELAY_WAIT:-}" "${SABHA_PUSH:-}" "${SABHA_NTFY_TOPIC:-}" "${SABHA_NTFY_URL:-}" \
    "$SABHA_CONF"
) 2>/dev/null
conf_line() { printf '%s\n' "$conf" | sed -n "$1p"; }
limit=$(conf_line 1)
case $limit in ''|*[!0-9]*) limit=1500 ;; esac
# the hook must end before Claude Code kills it (hooks.json timeout 1800): a killed hook is a hook failure
[ "$limit" -gt 1780 ] && limit=1780

dir=$HK_IMPL/inbox/$HK_RELAY/permissions
mkdir -p "$dir" 2>/dev/null || exit 0
cd "$dir" 2>/dev/null || exit 0
# the brief-number claim (docs/inbox-protocol.md section 2), per role: two roles or two subagents never share an id
# shellcheck disable=SC2010  # names are <Role>-NNN.<ext>, plain ASCII
n=$(ls | grep -E "^$HK_ROLE-[0-9]{3,}\." | sed "s/^$HK_ROLE-\([0-9]*\)\..*/\1/" | sort -n | tail -1)
n=$(printf '%03d' $(( 10#${n:-0} + 1 )))
tries=0
until (set -C; : > "$HK_ROLE-$n.claim") 2>/dev/null; do
  n=$(printf '%03d' $(( 10#$n + 1 ))); tries=$((tries + 1))
  [ "$tries" -lt 1000 ] || exit 0
done
id=$HK_ROLE-$n

nonce=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
case $nonce in ????????????????????????????????) ;; *) exit 0 ;; esac
hash=$( { printf '%s' "$input" | shasum -a 256 2>/dev/null || printf '%s' "$input" | sha256sum; } | cut -d' ' -f1)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expires=$(date -u -r $(( $(date +%s) + limit )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -d "@$(( $(date +%s) + limit ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
{
  printf 'id: %s\nutc: %s\nrole: %s\ntool: %s\ncwd: %s\nmode: %s\nnonce: %s\nhash: %s\nexpires: %s\ninput:\n%s\n' \
    "$id" "$now" "$HK_ROLE" "$tool" "$(hp_str cwd)" "$mode" "$nonce" "$hash" "$expires" "$input"
} > "$id.req.tmp" 2>/dev/null && mv "$id.req.tmp" "$id.req" 2>/dev/null || exit 0

log() { # log <decision> [words]: one line per printf, under PIPE_BUF, so concurrent hooks append whole lines
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HK_ROLE" "$id" "$tool" "$hash" "$1" "${2:-}" \
    >> log.tsv 2>/dev/null
}
words_of() { local w; w=$(sed -n 's/^words: //p' "$1" 2>/dev/null | head -n 1); printf '%s' "$w" | tr '\t\r\n' '   ' | tr -d '\000-\037' | cut -c1-500; }

# wake the relay; detached (no fd of ours) so Claude Code never waits on it, and its failure is only logged
c=$(conf_line 5); [ -n "$c" ] && export SABHA_CONF="$c"
( SABHA_NUDGE_TIMEOUT=10000 "$HK_DIR/../bin/sabha-nudge" "$HK_RELAY" "see inbox/$HK_RELAY/permissions/$id.req" ) \
  </dev/null >>nudge.log 2>&1 &
push=$(conf_line 2) topic=$(conf_line 3) url=$(conf_line 4)
if [ "$push" = ntfy ] && [ -n "$topic" ]; then
  # a public topic: role and tool only, never the tool input
  ( curl -fsS -m 5 -H "Title: sabha" -d "sabha: $HK_ROLE asks permission ($tool), see $HK_RELAY" \
      "${url:-https://ntfy.sh}/$topic" ) </dev/null >/dev/null 2>&1 &
fi

end=$((SECONDS + limit))
while :; do
  for d in deny allow; do
    f=$id.$d
    [ -f "$f" ] || continue
    if [ "$(sed -n 's/^nonce: //p' "$f" | head -n 1)" != "$nonce" ]; then
      mv "$f" "$id.bad-$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM" 2>/dev/null || rm -f "$f"
      log nonce-mismatch "$d"
      continue
    fi
    w=$(words_of "$f")
    log "$d" "$w"
    if [ "$d" = allow ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
    else
      m=$(printf '%s' "denied via $HK_RELAY: $w" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"%s"}}}\n' "$m"
    fi
    exit 0
  done
  if [ -f "$id.pane" ]; then log pane; exit 0; fi
  if [ "$SECONDS" -ge "$end" ]; then
    printf 'utc: %s\nby: hook\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$id.expired" 2>/dev/null
    log timeout
    exit 0
  fi
  sleep 1
done
