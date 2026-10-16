# Contributing

- Keep it small: bash, PowerShell and the Python standard library only; no install step, no daemon, no polling loop
  beyond `sabha-for-me --watch`.
- ASCII only in code, docs and commit messages. Comments say why, not what.
- Nothing personal or site-specific in the tree: names, paths, account ids and hosts come from `sabha.conf`.
- `docs/inbox-protocol.md` is the one source of truth for the file formats; change the scripts and that file together.
- `sabha-up.sh` and `sabha-run` build the same opening prompt from `sabha-lib.sh`; change the shared parts there.
- Before a pull request: `shellcheck -x bin/sabha-up.sh bin/sabha-watch bin/sabha-run bin/sabha-lib.sh`, `python3 -m py_compile bin/sabha-for-me`,
  every `tests/test-*.sh`, `bin/sabha-up.sh --print <Name>`, `bin/sabha-run --print <Name>` and one `bin/sabha-watch` run against a test `SABHA_CONF`.
- Conventional Commits: `<type>(<scope>): <summary>`.
