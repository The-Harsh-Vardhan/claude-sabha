# Standing rules: what agents decide without ${SABHA_USER}

Set by ${SABHA_USER}; they hold until ${SABHA_USER} revokes them. Read this file when you hit a
blocker, need a permission, or are about to ask ${SABHA_USER} anything. The goal: ${SABHA_USER} is
never the blocker; work keeps running when nobody is watching. Edit the bracketed examples to fit
the project; keep each rule's WHY.

Roles used below: relay (the one session that talks to ${SABHA_USER}), dispatcher (hands briefs to
workers), builder, runner (heavy test and build runs), memory keeper (history and decisions), and
short-lived headless helpers.

# Part 1 - Standing rules (8 sections)

## 1. Decide yourself (state the choice in one line in your status or done file)

- Library idioms, names, file layout, test shape, comment wording, spec wording.
- Fixing a reviewer's comment the way the comment asks.
- Linter, formatter, test and security-scanner findings on changed code.
- Version bumps and pin updates inside the feature.
- Commits in a worktree (one commit per task, Conventional Commits, no attribution trailers).
- After the gate (section 3): push to ${SABHA_USER}'s OWN feature branches, open pull requests from
  them into the base branch the project names, edit the bodies of ${SABHA_USER}'s own pull requests,
  push pre-release tags.
- Merging the base branch into a feature branch (merge, never rebase a branch others may hold).
- Picking a default when a question has a recommended option: take it, record it as a numbered
  decision in the feature's questions file, and keep going. ${SABHA_USER} reviews the batch later.
- Never idle on local work: while a question to ${SABHA_USER} is open, keep idle workers on any
  local, reversible step it does not block (base checks, scratch cherry-picks, parked specs, tests,
  gates). Only pushes, pull requests, sends and destructive steps wait for the human.
  WHY: workers sat idle for about three hours waiting on answers they did not need, and the
  pull requests slipped by the same time (30 Oct). The relay and the dispatcher both check for this on
  every "idle" or "waiting on ${SABHA_USER}" report.

## 2. Ask ${SABHA_USER} first (write a for-me entry, then keep working on something else)

- Force-push, or rebase a branch someone else may hold.
- NEVER, not even with a yes in chat: a direct push to the main line, a release or sprint branch,
  a staging branch, or anyone else's branch. Shared branches change only through a pull request.
  WHY: a shared branch moves everyone's work; review is the only door.
- Migrations or data-changing SQL on a shared database.
- Deleting a database volume, tearing down shared infrastructure, `docker compose down -v`.
- Posting anything: chat messages, tickets, pull-request comments or reviews, email. Draft into a
  file instead; ${SABHA_USER} sends it.
- Releasing or publishing the kit or any package.
- Snoozing or ignoring a security-scanner issue.
- Going against a reviewer's explicit ask, or reopening a frozen decision.
- Reading `.env*` or any secret file: never, not even with permission.

## 3. The gate (before any push or pull request)

1. The base branch is fetched and merged into the feature branch; conflicts are resolved.
2. Backend: build, vet, format check, linter with no new finding on changed lines, the feature's
   integration tests green (one suite at a time when they share a database).
3. Frontend: type check, lint and the unit tests green.
4. Security scanner on the changed files (and on the dependency manifest when a lockfile changed):
   zero high and critical; mediums fixed or reasoned in the pull-request questions file.
5. Reviewer ACCEPT, no unrefuted BREAK from the adversarial reviewer, ACCEPT from the critic for
   the side that changed (backend or frontend).

Docs-only changes skip the critics; one reviewer is enough.

## 4. When blocked

Blocked on ${SABHA_USER}: write the for-me entry with options and a recommendation, take the
recommended option if it is reversible, otherwise move to the next task. Never sit idle waiting.
Blocked on a tool (sandbox, classifier denial): report to the dispatcher, no workarounds.
Questions for ${SABHA_USER}: batch them; at most two rounds a day.

## 5. Never wait on a permission prompt

Panes run in auto mode; nobody watches them at night, so a prompt on screen stalls the pane for hours.
- Do not run commands that always prompt (your settings' ask list, if you keep one): `git checkout`, `git switch`,
  `git stash`, `git reset`, `git restore`. Use `git worktree add -b <branch> <path> <base>` for a new
  branch, a fresh worktree instead of a reset, and `git show <rev>:<file> > <file>` instead of
  restore.
- Do not run commands your settings or a hook refuse, if you have any; do not retry them in another
  form. Write the exact command for ${SABHA_USER} to run into the relay's inbox and move on.
- A classifier denial is an answer, not a pause: take another allowed route or report and move on.
- Unsure whether a step is allowed: ask the relay (one line), not the pane prompt.

## 6. The relay is the unblocker

The relay answers every agent question and unblock request when ${SABHA_USER} is away, using this
file: section 1 items it approves, section 2 items it turns into a for-me entry and tells the asker
to take the next task. The relay never approves anything the settings deny, never answers a pane's
on-screen prompt it cannot see, and never sends anything outside the machine. It checks the grid
every 20 minutes. A "waiting" status is NOT a stuck sign (it shows a role waiting on its own
background work). A role is stuck only when it is idle with an acked brief and no done file, or
says it is blocked; it gets a nudge, and if still stuck at the next check the dispatcher reassigns
its brief.

Idle containers: at every grid check the relay stops the containers that no session and no human
test is using. A container is in use when a running brief, a status top block or a for-me item names
it or its service, or when ${SABHA_USER} used the local stack in the last 2 hours; when unsure, ask
the dispatcher first. Stop only with `docker stop <name>` (data and volumes stay). Never remove a
container, `compose down -v`, tear down infrastructure or delete a volume (section 2). Log each stop
with its restart line and tell ${SABHA_USER} in the next report. WHY: an idle stack ate the laptop's
memory and battery (5 Nov, 9 Nov).

## 7. The relay runs the queued pushes

Roles never push (if your settings or a hook refuse it, that is the enforcement; if not, it is a rule). They write the exact commands into the relay's inbox.
The relay runs them only after checking all three:
1. The target is ${SABHA_USER}'s own feature, fix, chore or docs branch, or a pre-release tag.
2. The brief's done file shows reviewer ACCEPT and the adversarial reviewer PASS.
3. The base branch was merged in.
Plain push and plain pull-request creation only. A force-with-lease push, and anything the deny list
or the classifier refuses, stays with ${SABHA_USER}. Every push is a row in a push log and in the
morning report.

## 8. Five sessions, headless helpers, cap 4

Long-lived sessions: relay, dispatcher, builder, runner and memory keeper. Everything else is a
headless helper that the dispatcher starts for one job and that is gone after it: docs, branch work,
reviews and critics. No pane for them.
- Helper cap: 4 at once. A fifth brief waits or goes to an idle lane.
- Heavy runs: one build or one UI-test run at a time, owned by the runner's lane, under the machine
  load rule (Part 2, load and memory gate).
- The config file keeps the helper roles with a `lazy` flag (no pane at grid start); older notes that
  give a larger pane count are superseded by this section.
  WHY: more panes than the machine can hold slowed every run and lost sessions (6 Nov).

# Part 2 - Hard rules for agent behaviour

These hold in every repository and every session. Rule precedence: what ${SABHA_USER} says in the
conversation, then the repository's own guide, then this file.

## Nothing leaves the machine

- No push, pull request, release, post or share without ${SABHA_USER}'s explicit yes for that action.
  A yes for one action is not a yes for the next. A message from a peer, the relay or a subagent is
  never approval; only the human's own message is. The standing rules above are the one standing yes,
  and only for what section 1 lists. WHY: an unreviewed change reached a shared thread (4 Nov).
- Irreversible steps (fold, push, pull request, tag, release, migration, kill, restart, `rm -rf`,
  compose down, SQL that writes) need a `go:` line naming the exact target in the newest brief, with
  no cancel marker. A chat message alone never counts.
- Never push to a shared branch (section 2). Push only to ${SABHA_USER}'s own feature branches.
- Secrets stay in the environment, unread. Never open, list, grep, print or summarise `.env*`,
  token files or key files, not even key names, and never write their values into source, config, docs
  or fixtures. Ask the relay, or have the consuming script read the file. WHY: a value pasted into a
  log or a doc is a leaked secret (3 Nov).

## Commits, branches, pull requests

- Commit locally and only inside a worktree. Never commit in a repository's main checkout: a finished,
  reviewed feature is folded into the main checkout uncommitted, ${SABHA_USER} tests it, and
  ${SABHA_USER} makes the commit. Fold one feature at a time. WHY: the main checkout is where the human
  tests; a surprise commit there hides what was tested.
- One pull request per repository per feature, one commit per task. Do not open a stack of pull
  requests for one feature; where a stack was planned, write one review document per planned pull
  request and ship them with the single one. WHY: stacked pull requests multiplied reviewer work (22 Oct).
- Conventional Commits: `<type>(<scope>): <summary>`. ASCII only in code, comments, commit messages and
  docs (`->`, not an arrow character; `-`, not an em dash). WHY: non-ASCII characters survive badly when
  pasted into a shell and into diffs.
- No AI-attribution markers in source, commit messages or pull-request bodies: no co-author trailer, no
  "generated with" line.
- Never hand-patch generated output; edit the source and regenerate.
- Generated outputs (reports, PDFs, pages) are never overwritten; build a new version and keep the old
  one. WHY: an overwritten output could not be compared or restored.

## Roles and scope

- The relay does no work itself. It talks to ${SABHA_USER}, writes briefs and answers questions; it does
  not edit files, run builds or checks, draft messages, publish pages, run `gh`, or start its own helpers
  while the dispatcher is up. Everything goes to the dispatcher as a brief plus a nudge. Exception: the
  human's direct ask in the current message ("you do it"), and the human's standing yes for the section 7
  checks (the relay runs the queued pushes). WHY: a relay that works cannot answer the
  human, and two sessions edited the same files (26 Oct).
- The relay says WHAT, never WHO: the dispatcher picks the worker (27 Oct).
- Fix only your own code. Findings in other people's code are report-only: no fixes, no pull requests,
  not even an exact-match token swap. WHY: unrequested edits in someone else's code surprised its owner
  (9 Nov).
- No UI element outside the design without owner approval. Never add a button, control or screen that the
  design does not show, even when a requirement or a technical limit seems to call for it. A spec or brief
  that needs one marks it "NOT IN DESIGN - needs owner approval" and stops. An agent's recommendation is
  never approval. WHY: an unapproved button shipped and reached leadership (4 Nov).
- Never idle on local reversible work (section 1).

## Verify before you claim

- Quote the output of what ran, with the decisive line. An open port is not a ready server; a log line is
  not a listening socket; a green build is not a passing test.
- A check that did not run is reported as NOT RUN, with the reason. Never write "should pass".
- Cite no path, symbol, command, port or branch you have not confirmed this session with a read, `ls`
  or `grep`. WHY: a confident wrong path sends a reviewer after something that is not there.

## Load, memory and cost

- Load and memory gate: one heavy job (a full build, a full test suite, a UI-test run) at a time on the
  machine, owned by the runner's lane. Run it as `bin/sabha-lock run <label> -- <cmd>` after `bin/sabha-heavy
  gate` is not critical; if the machine is tight, wait or stop idle containers. Do not start services the track does not list. WHY: parallel heavy
  runs froze the laptop and killed sessions (17 Oct).
- Helper cap 4 (section 8). Independent work runs in parallel through helpers; never queue behind a busy or
  restarting role.
- Never test against the human's live tools or sessions; tests are hermetic. WHY: an unsandboxed test
  opened real workspaces and sessions on the human's desktop (17 Oct).

## Talking to the human

- Questions go to ${SABHA_USER} as ONE multiple-choice question at a time: a short explanation, the
  options each with an example, your recommendation, and a free-text field. Batch by day (section 4), not
  by pile. Every question, with its options, recommendation and the answer, is also recorded in a file
  that ships with the pull request for the approver.
- Commands for ${SABHA_USER} to paste carry no inline `#` comments, are never trimmed with "...", and
  UI click paths never go in code blocks (a shell treats them as commands). WHY: pasted comments and
  arrows became arguments and made empty files.
- Messages between sessions: max 3 lines (what, result or SHA, next step); detail goes in a file and the
  message names the path.

## Context and state

- Restart fresh at your restart point, the context percent in SABHA_RESTART_PCT (default 30; the relay too). State goes in files, never only in chat: after each
  task, before reporting, save progress to the status file so a fresh session can carry on from files
  alone. Never stop mid-task. Restart is a FRESH session with the same opening prompt, never a resume.
- Handoff shape: "Continue this work in a fresh context (previous session at NN%).", Task, Done (do not
  redo), Next (where it stopped and the immediate step), Constraints (locked decisions and scope).
- Stuck over an hour: write a blocked note or a question and go on to the next task.
