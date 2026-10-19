# Keep awake

A sleeping Mac runs nothing, the herdr server included, so sabha stops the sleep instead of running through it.
Set `SABHA_KEEP_AWAKE` in `sabha.conf`:

| Value | What it does |
|---|---|
| `auto` (default) | picks by power source, read from `pmset -g ps`: AC power -> `lid`, battery -> `open`. `sabha-loop` checks every poll, so unplugging or plugging in switches live. If you ran `sudo pmset -a disablesleep 1`, auto cannot undo it (only sudo can): on battery a closed lid then keeps running, so `sabha doctor` warns and the loop says once (in its log): run `sudo pmset -a disablesleep 0`. With the iTerm backend there is no herdr server, so keep-awake does nothing. `SABHA_KEEP_AWAKE_AC` and `SABHA_KEEP_AWAKE_BATTERY` (off, open or lid) replace what auto picks for one source. |
| `off` | nothing; ends a caffeinate sabha started |
| `open` | `sabha-up.sh` and `sabha-loop` start `caffeinate -dis -w <herdr server pid>`. Idle sleep is blocked; closing the lid still sleeps. No sudo. It ends when the herdr server ends, and a caffeinate already running for the server is reused. |
| `lid` | `open`, plus the lid may be closed. This needs a system setting that only you can change (below). |

An explicit `off`, `open` or `lid` beats the per-source pair. `sabha keep-awake <mode>` rewrites `SABHA_KEEP_AWAKE` in
your `sabha.conf` (a running `sabha-loop` picks it up on its next poll); with no mode it prints the setting.
`sabha doctor` reports the mode, the power source, the effective mode, `SleepDisabled` and the caffeinate assertions
(read-only).

## lid (and auto on AC power): the sudo step

Run these yourself; sabha never runs sudo.

    sudo pmset -a disablesleep 1
    sudo pmset -a disablesleep 0

The first turns lid-close sleep off, the second restores it. Run the second when the work is done.

Warning: with `disablesleep 1` a closed laptop keeps running at full load with no airflow. It gets hot and drains the
battery. Keep it on a desk, plugged in, and never in a bag.
