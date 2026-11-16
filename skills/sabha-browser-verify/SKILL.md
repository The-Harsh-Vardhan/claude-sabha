---
name: sabha-browser-verify
description: Use when a tester or runner role must check a change in a real browser - reproduce a bug (BEFORE), confirm the fix (AFTER), take screenshots, sign in, or get a site approved in Claude in Chrome.
---

# Browser verify

Source: RULES.md rule 6 (nothing leaves the machine without a yes), `sabha.conf.example` (`SABHA_CHROME_<Name>`),
`bin/sabha-up.sh`. The role that uses this skill is the Runner (or any tester role you give `SABHA_CHROME_<Name>=1`).

## 1. Setup, once per machine

1. Install the Claude in Chrome extension in the browser the human uses.
2. In a Claude session run `/chrome`: set "Enabled by default" to Yes and tick the browser.
3. A role started with `--strict-mcp-config` (the default for a worker role) gets no
   browser unless it is also started with `--chrome`. Put `SABHA_CHROME_Runner=1` in `sabha.conf` and restart the role
   (`sabha-up.sh --print Runner` shows `--chrome` in the line).
4. Check: in the role, `/chrome` shows Status Enabled and the browser ticked. If not, stop and tell the relay; do not
   work around it.

## 2. Site approval

The extension asks per site on the first action. The human clicks "always allow" once per host. Before the first
step, list every host you need (`<app-host>`, `<api-host>`, ...) and ask the relay once, in one message.

## 3. Logins

- Never type a password through the browser. Never read `.env*` or any key file.
- The human signs in once in their own Chrome. Assume no "remember me".
- If a sign-in page shows up, stop and ask the relay. Do not guess, retry or reset anything.
- Headless Playwright runs use your own script that reads the credentials from the env file inside its own process and
  saves a storage state (email and password accounts only). An SSO account falls back to a one-time human sign-in.

## 4. Evidence

- Pick the environment where the code really runs: a merged change on the shared environment, an unmerged one on a
  local or preview build. Say which, with the build or sha.
- BEFORE shot (bug present), AFTER shot (fix build). Light and dark when the screen has both.
- Path: `verify-<date>/<item>-before.png`, `<item>-after.png`, `<item>-before-dark.png`, `<item>-after-dark.png`.
- One line per item in `verify-<date>/results.md`: `item | env | build/sha | PASS/FAIL/NOT-SEEN | why`.
  NOT-SEEN means the bug did not show; it is never a PASS.

## 5. Safety

- Read-only on shared environments. No data-changing click on anyone else's data.
- Your own test data carries a prefix (for example `verify-<date>-`) and is listed in `results.md` for cleanup.
- A screenshot that fails with "Detached": retry, at most 3 times, then record NOT-SEEN with the reason.
- Load rule: one stack at a time (`sabha-heavy`); a second browser job waits.
- A browser you opened is closed when you finish; a headless run records its pid in the brief's output folder.
