# Release checklist

Nothing is pushed, tagged or published until every step passes. Run from the repo root.

1. BLOCKING: the owner confirms that their employer's open-source policy and employment terms allow a personal MIT
   release of this code, and that LICENSE names the right copyright holder. No step below starts without this.
2. Ship set: `git status -uall --short` lists exactly the files meant to ship (count them with `-uall`); everything
   personal (`sabha.conf`, `local/`, design notes, `docs/questions-and-answers.md`, `FOR-ME.*`, `for-me.items`) is
   ignored.
3. Scrub: `git grep --untracked -I -n -i -E '<your name>|<your company>|/Users/|/home/|C:\\Users'` over the ship
   set is empty except the LICENSE line you chose; no email addresses, account ids or tokens
   (`git grep --untracked -I -n -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'`). Plain `git grep` skips untracked
   files, so before the first commit it finds nothing and the gate passes vacuously; `--untracked` searches the
   files `git ls-files -co --exclude-standard` lists and still honours `.gitignore`.
4. History: the scrub of step 3 also runs over every commit (`git log -p --all | grep ...`); a hit means rewriting
   history before the first push, never after.
5. ASCII: `LC_ALL=C git grep --untracked -I -n '[^ -~]' -- . ':!docs/diagrams/'` is empty. `docs/diagrams/` holds
   generated archify exports (middle dots in labels, the viewer's own script); regenerate them, never hand-edit.
6. Checks: the commands in CONTRIBUTING.md pass.
7. Live smoke: `tests/smoke-live.sh` (about 30 s, needs `claude` on PATH, spends no tokens, never touches herdr) runs
   `bin/sabha-loop` in a real pty with plain interactive claude and prints `ok:`. The hermetic suite cannot see launch
   bugs that need a tty (#5, #8); it fails on the 2.0.0 tag (535afbd) and passes on a fixed tree.
8. CHANGELOG.md has the version and date, and the plugin manifest version matches (every fix release bumps it); README status line is current.
9. A reviewer scans the tree and the history and signs off in writing.
10. Only then: create the remote, push, tag.
