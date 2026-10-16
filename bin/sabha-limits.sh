# Sourced by statusline-sabha.sh, sabha-loop and sabha-watch, never run: the account-wide Claude usage windows
# (statusLine JSON rate_limits.five_hour / seven_day) and the alerts on them.
# Files under $SABHA_IMPL/status: limits.txt (one line per window: "<window> <used pct> <resets_at epoch> <written
# epoch>"), alerts.log (one line per fired alert), alerts/ (one marker per fired step, see sabha_limits_alert).
# shellcheck shell=bash

sabha_limits_file()  { echo "${SABHA_LIMITS_FILE:-$SABHA_IMPL/status/limits.txt}"; }
sabha_alerts_log()   { echo "${SABHA_ALERTS_LOG:-$SABHA_IMPL/status/alerts.log}"; }
sabha_alerts_dir()   { echo "${SABHA_ALERTS_DIR:-$SABHA_IMPL/status/alerts}"; }
sabha_utc()          { date -u +%Y-%m-%dT%H:%M:%SZ; }

# sabha_fmt_epoch <epoch>: local HH:MM (BSD date first, GNU date second)
sabha_fmt_epoch() {
  date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo "$1"
}

# sabha_limits_write <window> <pct> <resets_at>: the limit is account-wide, so any session's reading is the current
# one; the newest write wins. Written to a temp file and moved so a reader never sees a half line.
sabha_limits_write() {
  local f tmp
  f=$(sabha_limits_file); mkdir -p "$(dirname "$f")" || return 1
  tmp="$f.$$"
  { [[ -f $f ]] && grep -v "^$1 " "$f"; printf '%s %s %s %s\n' "$1" "$2" "$3" "$(date +%s)"; } >"$tmp" 2>/dev/null
  mv -f "$tmp" "$f"
}

# sabha_limits_read <window>: prints "<pct> <resets_at> <written>" or nothing
sabha_limits_read() {
  local f; f=$(sabha_limits_file)
  [[ -f $f ]] && awk -v w="$1" '$1 == w { print $2, $3, $4 }' "$f"
}

# sabha_notify <text>: alerts.log line, then the desktop (macOS notification; Windows toast, UNTESTED) and the phone
# (SABHA_PUSH=ntfy, one curl, UNTESTED delivery). SABHA_NOTIFY_DESKTOP=0 keeps it to the log (tests, headless hosts).
sabha_notify() {
  local log msg=$1
  log=$(sabha_alerts_log); mkdir -p "$(dirname "$log")" 2>/dev/null
  printf '%s %s\n' "$(sabha_utc)" "$msg" >>"$log"
  [[ ${SABHA_NOTIFY_DESKTOP:-1} == 1 ]] || return 0
  case $(uname -s) in
    # the text travels as an argv item, never inside the AppleScript source, so quotes and backslashes cannot break or inject
    Darwin) osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "sabha"' -e 'end run' -- "$msg" >/dev/null 2>&1 ;;
    MINGW*|MSYS*|CYGWIN*)
      # UNTESTED: WinRT toast from PowerShell, no module needed
      powershell.exe -NoProfile -Command "[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]; \$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText01); [void]\$t.GetElementsByTagName('text').Item(0).AppendChild(\$t.CreateTextNode('${msg//\'/}')); [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('sabha').Show([Windows.UI.Notifications.ToastNotification]::new(\$t))" >/dev/null 2>&1 ;;
  esac
  if [[ ${SABHA_PUSH:-off} == ntfy && -n ${SABHA_NTFY_TOPIC:-} ]]; then
    curl -fsS -m 5 -H "Title: sabha" -d "$msg" "${SABHA_NTFY_URL:-https://ntfy.sh}/$SABHA_NTFY_TOPIC" >/dev/null 2>&1
  fi
  return 0
}

# sabha_limits_alert: for each window, every SABHA_NOTIFY step the usage has crossed fires once per window reset.
# The marker alerts/<window>-<step>-<resets_at> is created with noclobber, so concurrent hooks fire it exactly once;
# a new resets_at means a new window and the steps fire again.
sabha_limits_alert() {
  local dir w line pct reset p step mark
  dir=$(sabha_alerts_dir); mkdir -p "$dir" 2>/dev/null || return 0
  for w in five_hour seven_day; do
    line=$(sabha_limits_read "$w"); [[ -n $line ]] || continue
    read -r pct reset _ <<<"$line"
    p=${pct%.*}; [[ $p =~ ^[0-9]+$ ]] || continue
    for step in ${SABHA_NOTIFY:-10 20 30 40 50 60 70 80 90}; do
      (( p >= step )) || continue
      mark="$dir/$w-$step-${reset:-0}"
      (set -C; : >"$mark") 2>/dev/null || continue
      sabha_notify "${w/_/-} usage ${pct}% (crossed ${step}%), resets $(sabha_fmt_epoch "${reset:-0}")"
    done
  done
  return 0
}

# sabha_limits_stopped: true while SABHA_STOP (default 90; 0 or off disables) holds: a window at or over it whose
# resets_at is still ahead. Callers start no new session then; nothing running is touched. Prints the reason.
sabha_limits_stopped() {
  local stop=${SABHA_STOP:-90} w line pct reset now
  [[ $stop == off || $stop == 0 ]] && return 1
  now=$(date +%s)
  for w in five_hour seven_day; do
    line=$(sabha_limits_read "$w"); [[ -n $line ]] || continue
    read -r pct reset _ <<<"$line"
    [[ ${pct%.*} =~ ^[0-9]+$ ]] || continue
    if (( ${pct%.*} >= stop )) && (( ${reset:-0} > now )); then
      echo "SABHA_STOP: ${w/_/-} at ${pct}% (>= ${stop}%), no new sessions until $(sabha_fmt_epoch "$reset")"
      return 0
    fi
  done
  return 1
}

# sabha_limits_banner: one line for sabha-watch, or nothing when no reading exists
sabha_limits_banner() {
  local w line pct reset written out="" now
  now=$(date +%s)
  for w in five_hour seven_day; do
    line=$(sabha_limits_read "$w"); [[ -n $line ]] || continue
    read -r pct reset written <<<"$line"
    out+="${w/_/-} ${pct}% (resets $(sabha_fmt_epoch "${reset:-0}"), read $(( (now - ${written:-now}) / 60 ))m ago)  "
  done
  [[ -n $out ]] && echo "limits: $out"
  sabha_limits_stopped || true
}
