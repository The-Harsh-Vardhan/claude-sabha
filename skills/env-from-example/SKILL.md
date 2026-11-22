---
name: env-from-example
description: Use when a command needs secrets from a dotenv file (API tokens, credentials) - learn variable names from the example file only, then run the command through bin/with-env so values never reach the transcript.
---

# Using dotenv values without seeing them

## Rules

- Read ONLY `.env.example` to learn variable names. Never cat, source, grep, head or otherwise read `.env`.
- Values never go in argv, files, logs or your own output. `with-env` refuses if a value would appear in argv.
- The safety hook stays the real guard. If a hook blocks loading `.env`, stop and report; do not work around it.
- This is a convenience, not a security boundary. A child process can still read its own environment.

## Use

`bin/with-env [--env-file PATH] [--slot N | --try-slots 1,2,3] NAME... -- command args`

- Loads only the named variables from `.env` (default `./.env`) into the child's environment.
- `--slot N` maps `NAME_N` in the file to `NAME` for the child (e.g. `KAGGLE_USERNAME_2` to `KAGGLE_USERNAME`).
- `--try-slots 1,2,3` runs the command once per slot until one exits 0; slot and exit code go to stderr, never values.
- Loaded values appearing in child stdout/stderr are replaced with `***`. The child's exit code is passed through.
- Runs via `uv run --no-project python` (stdlib only).

Example: `bin/with-env --try-slots 1,2,3 KAGGLE_USERNAME KAGGLE_API_TOKEN -- uvx kaggle datasets list --mine`

Test: `tests/test-with-env.sh`
