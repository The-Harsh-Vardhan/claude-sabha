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
5. ASCII: `LC_ALL=C git grep --untracked -I -n '[^ -~]' -- . ':!*.cmd'` is empty (`.cmd` files keep CRLF line
   endings, which this pattern counts).
6. Checks: the commands in CONTRIBUTING.md pass.
7. CHANGELOG.md has the version and date; README status line is current.
8. A reviewer scans the tree and the history and signs off in writing.
9. Only then: create the remote, push, tag.
