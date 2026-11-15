# Release checklist

Nothing is pushed, tagged or published until every step passes. Run from the repo root.

1. Ship set: `git status -uall --short` lists exactly the files meant to ship (count them with `-uall`); everything
   personal (`sabha.conf`, `local/`, design notes, `docs/questions-and-answers.md`, `FOR-ME.*`, `for-me.items`) is
   ignored.
2. Scrub: `git grep --untracked -I -n -i -E '<your name>|<your company>|/Users/|/home/|C:\\Users'` over the ship
   set is empty except the LICENSE line you chose; no email addresses, account ids or tokens
   (`git grep --untracked -I -n -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'`). Plain `git grep` skips untracked
   files, so before the first commit it finds nothing and the gate passes vacuously; `--untracked` searches the
   files `git ls-files -co --exclude-standard` lists and still honours `.gitignore`.
3. History: the scrub of step 2 also runs over every commit (`git log -p --all | grep ...`); a hit means rewriting
   history before the first push, never after.
4. ASCII: `LC_ALL=C git grep --untracked -I -n '[^ -~]' -- . ':!docs/diagrams/'` is empty. `docs/diagrams/` holds
   generated archify exports (middle dots in labels, the viewer's own script); regenerate them, never hand-edit.
5. Checks: the commands in CONTRIBUTING.md pass.
6. Live smoke: `tests/smoke-live.sh` (about 30 s, needs `claude` on PATH, spends no tokens, never touches herdr) runs
   `bin/sabha-loop` in a real pty with plain interactive claude and prints `ok:`. The hermetic suite cannot see launch
   bugs that need a tty (#5, #8); it fails on the 2.0.0 tag (535afbd) and passes on a fixed tree.
7. CHANGELOG.md has the version and date, and the plugin manifest version matches (every fix release bumps it); README status line is current.
8. A reviewer scans the tree and the history and signs off in writing.
9. Only then: create the remote, push, tag.
