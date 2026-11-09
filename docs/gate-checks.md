# Workspace checks for the gate

`bin/sabha-gate` shuts the gate on a missing verdict. `--checks FILE` adds a second list: the things your project
wants true before any push or PR, each one a file test (no model judges anything).

    bin/sabha-gate -C <dir> --checks gate-checks.conf                    checks only
    bin/sabha-gate -C <dir> --checks gate-checks.conf --brief <brief>    verdicts and checks, one answer

`SABHA_GATE_CHECKS=<file>` names the list when the flag is absent; the flag wins. Exit 0 = open, 1 = shut, 2 = usage
(a bare option, a missing or over-1-MB config, a missing directory). A list with no check in it shuts the gate.

## The list

One check per line: `<check> <path>`. `#` starts a comment line; blank lines are skipped. A path is read from `-C DIR`
(absolute paths work); a leading `~` and `$VAR` or `${VAR}` expand from the environment (never eval; an unset variable
shuts that check). An unknown check name or a check with no path shuts the gate.

    aikido        aikido-scan.txt
    screenshots   pack.md
    not-in-design spec.md
    questions     questions.md

| Check | Passes when | The file looks like |
| --- | --- | --- |
| `aikido` | the newest line starting `aikido:` carries `high=0` and `critical=0` | `aikido: scanned=4 high=0 critical=0` |
| `screenshots` | the newest `ui:` line is `ui: no`, or `ui: yes` with at least one `screenshot: <image>` line whose file (png, jpg, jpeg, gif, webp) exists beside the pack | `ui: yes` then `screenshot: light.png` |
| `not-in-design` | the lines holding `NOT IN DESIGN` are matched by at least as many lines starting `APPROVED:` | `APPROVED: <who>, <date>` |
| `questions` | the file exists and holds a non-blank line | the questions file that ships with the PR |

Each file is read as bytes (a non-ASCII character never crashes a check) and may be at most 8 MB. Newest wins for
`aikido:` and `ui:`: a rerun appends a line instead of rewriting the file. Everything printed is cleaned to printable
ASCII on one line.
