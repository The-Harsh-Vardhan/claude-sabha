---
title: Load meter (optional)
nav_order: 6.5
---

# Load meter (optional mod)

The heavy-job gate (`bin/sabha-heavy`) decides; a load meter only shows. Sabha does not ship one. A Claude Code mod
that draws a band above the prompt is enough, and it lives outside this repository with your own mods.

## What it shows

| Part | Source | Colours |
| --- | --- | --- |
| load | one-minute load average / cores | green up to cores, amber up to 2 x cores, red above |
| memory | memory pressure level | green, yellow, red |
| slots | heavy jobs held / `SABHA_HEAVY_MAX` | - |

Red load is exactly the gate's WAIT threshold (`SABHA_HEAVY_LOAD_FACTOR`, default 2), so a red band means a heavy job
would wait now.

## Contract

`bin/sabha-heavy status` prints the line the meter needs, with the gate's own reads and fallbacks:

```
load 84.74/10 red | mem green | slots 0/2
load 1.00/10 green | mem yellow | slots 2/2 | build-api e2e-web
```

A meter that runs `sabha-heavy status` every 10 seconds shows the same numbers the gate uses. A meter that reads
`sysctl` and `memory_pressure` itself can disagree on memory: `memory_pressure` prints a free percentage, and on
4 Nov 2026 the pressure level was already yellow at 32% free. Use the pressure level
(`sysctl -n kern.memorystatus_vm_pressure_level`: 1 green, 2 yellow, 4 red) or `sabha-heavy status`.

## Limits

- macOS and Linux reads only; on Windows the line shows `?` for what it cannot read.
- Inside a Claude Code sandbox that denies `sysctl`, `sabha-heavy` falls back to `uptime`, `memory_pressure -Q` and
  `getconf`; the colour of memory then comes from the free percentage (`SABHA_HEAVY_FREE_PCT`, default 40).
