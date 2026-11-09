# Morning digest

`bin/sabha-for-me --digest [--since <utc>]` writes `DIGEST-<yyyy-mm-dd>.md` and `.html` into `SABHA_FORME_DIR`
(default `SABHA_IMPL`): what finished since the previous day's digest (else the last 12 hours), what is blocked, the
open `for-me.items` that carry a `cmd:`, and each role's state and task.

- Blocked lists a `NNN.blocked*` marker only when the same number has no `.done` and no `.cancel`, the file name does
  not contain `cleared`, the marker is newer than the brief's `.ack` when there is one, and no newer `NNN.parked*` or
  `NNN.cleared*` marker exists for the same number. A role is listed when its
  state is `blocked` (the state the board shows).
- A rerun with nothing new writes nothing. A change on the same day replaces that day's page in place; an earlier day
  is never touched.
- Everything is ASCII: a non-ASCII character shows as `?`, control bytes are dropped.
- `sabha-watch` and `/sabha-status` do not build it, so both stay read-only. Schedule it yourself.

Keep `SABHA_FORME_DIR` outside any git repository, or the daily files land in that tree.

## Example cron line (not installed)

Replace `/path/to` with your clone in both examples.

Every day at 06:15, with the config in `~/.config/sabha/sabha.conf`:

```
15 6 * * * SABHA_CONF=$HOME/.config/sabha/sabha.conf /usr/bin/python3 /path/to/claude-sabha/bin/sabha-for-me --digest
```

## Example launchd plist (not installed)

Save as `~/Library/LaunchAgents/com.example.sabha-digest.plist` and load it with `launchctl load` yourself:

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.sabha-digest</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>/path/to/claude-sabha/bin/sabha-for-me</string>
    <string>--digest</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>SABHA_CONF</key><string>/path/to/sabha.conf</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>15</integer></dict>
</dict>
</plist>
```
