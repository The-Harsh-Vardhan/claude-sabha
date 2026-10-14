# Contributing

- Keep it small: bash, PowerShell and the Python standard library only; no install step, no daemon, no polling loop
  beyond `sabha-for-me --watch`.
- ASCII only in code, docs and commit messages. Comments say why, not what.
- Nothing personal or site-specific in the tree: names, paths, account ids and hosts come from `sabha.conf`.
- `docs/inbox-protocol.md` is the one source of truth for the file formats; change the scripts and that file together.
- `sabha-up.sh` and `sabha-up.ps1` carry the same opening prompt; change both in one commit.
- Before a pull request: `shellcheck bin/sabha-up.sh bin/sabha-watch`, `python3 -m py_compile bin/sabha-for-me`,
  `tests/test-claim.sh`, `bin/sabha-up.sh --print <Name>` and one `bin/sabha-watch` run against a test `SABHA_CONF`.
- Conventional Commits: `<type>(<scope>): <summary>`.
