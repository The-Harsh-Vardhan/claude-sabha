---
title: Field notes
nav_order: 10
---

# How I use claude-sabha day to day

These notes come from about three weeks of daily use (mid October to early November 2026) on a multi-repo product
team: several repositories, reviews from several people, a PM who signs off the design.
They say what worked, what broke, and what changed in this repo because of it. Each incident links to the fix when one
exists. Nothing here is a benchmark. It is a log of one person's use.

Names of products, customers and colleagues are left out on purpose. Dates are real.

## 1. The setup that worked

```
  me  <-->  RELAY  --brief-->  DISPATCHER  --brief-->  WORKERS (panes and headless runs)
             |                    |                        |
             |                    |                        +--> .ack, status file, .done
             +-- reads status, asks me one question at a time
                                  +-- gates: reviewer, critics, then a push command for me
```

- **One relay.** It is the only session I talk to. It runs outside the pane grid, so a grid restart does not kill it.
- **One dispatcher** in a pane, started by `sabha-loop`. It splits a brief into lanes and picks a worker by difficulty.
- **A small grid.** The dispatcher plus at most five work panes. Long, stateful work (merges, fixes with questions)
  gets a pane. Bounded work (a review, a scan, a draft, a one-shot script) runs headless with `sabha-run`.
- **Two Claude accounts** when one weekly limit is not enough ([#33](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/33)).
- **Everything in files.** Briefs, `.ack` and `.done` markers, one status file per role, one queue of questions for me.
  A session that dies loses nothing that matters.
- **Restart fresh at 30 percent context.** Every role, the relay too. The role writes a handoff first. A restart is a
  new session that reads the files. It is never `--resume`.
- **No role pushes.** A worker commits in a worktree and writes the exact push command into a file. I run it.

## 2. The relay and the dispatcher split

The relay says WHAT, WHY, the limits, "done when" and "report to". The dispatcher decides WHO. That sounds small. It is
the rule I broke most often (see section 4, "The relay does the work").

A good brief is a short file. A message between sessions is only a nudge that names the file. An irreversible step
(a fold, a push, a tag) needs a `go:` line in a brief file that names the exact target. A message alone never counts.

## 3. A real day, anonymised (3 November 2026, UTC)

| Time | What happened | What it taught |
| --- | --- | --- |
| 02:45 | The relay writes a brief: no pane has restarted at 30 percent for about 52 hours | A loop that reads the wrong file does nothing and says nothing |
| 09:19 | The dispatcher passes 30 percent. The loop restarts it, correctly. Six in-session helpers die with it | Restarting the dispatcher is safe. Restarting its helpers is not |
| 09:43 | A headless worker takes a brief to build durable helpers. It is done at 11:15 with 50 hermetic checks | Bounded work fits a headless run well |
| 10:20 | Machine load is 350 to 420. A bare `sabha-helper list` takes 16 seconds | Tests must wait for events, not for a fixed time |
| that day | An API error stops three workers. All three are resumed by id | Keep the agent id in the status file |
| 14:15 | A hotfix brief. A builder and a read-only tracer run one after the other, never both writing | One writer per worktree |
| that day | Six headless workers own six lanes. The dispatcher only watches the `.done` markers and runs the gates | The dispatcher does not implement |
| night | I push the helpers PR myself. The security scan was not run first. That was my call, and it is written down | A skipped check is recorded, not hidden |

## 4. Incidents, and what changed because of each

| When | What happened | Impact | What changed |
| --- | --- | --- | --- |
| 14 Oct | 16 Claude sessions ran at once and used all the RAM of a laptop | I closed the whole grid. Files had all the state, so nothing was lost | Plans for Pro and Max ([README, "Pick a plan"](../README.md#pick-a-plan)), a cap on work panes, headless runs ([`sabha-run`](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/5571e1e)) |
| 17 Oct | Tests run outside the sandbox reached my real herdr. They opened 16 workspaces and 12 real sessions | I had to close them by hand | Hermetic tests with a fake herdr, a guard in `bin/sabha-herdr.sh` ([28635a9](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/28635a9), [e5d3290](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/e5d3290), [cd09a9a](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/cd09a9a)) |
| 19 Oct | Scripts were committed without the exec bit. A fresh clone failed at the first quickstart step. Also, `git commit -- paths` takes the file mode from disk | New users could not start | [c317bc3](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/c317bc3), [0b0bca3](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/0b0bca3). Rule: commit with no path list after `update-index`, then check `git ls-tree` |
| 19 Oct | I started roles with hand-typed `for` loops. No role restarted at the context limit. The loop later gave up after two fast exits (a Bun launch race) | No supervision, then no launch | Start roles only with `sabha-loop`. Fixes: [d919494](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/d919494), [d94df02](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/d94df02), [bb0c4c8](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/bb0c4c8), [cdb2daf](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/cdb2daf) |
| 19 Oct | A pane sat on a permission prompt and I did not know | I had to hunt through the grid | The relay shows the prompt, word for word. I answer each one. A key is pressed only on my answer ([1f369c7](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/1f369c7), [47866f3](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/47866f3), [cbe0d8b](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/cbe0d8b)) |
| 27 and 31 Oct | **The relay does the work.** The relay read diffs, ran migrations and built pages while the dispatcher was up | A slow, unresponsive relay | Rule 2 in [RULES.md](../RULES.md). No code enforces it yet ([issue draft](../issues/02-relay-guard-hands-on-work.md)) |
| 28 Oct | After a reboot herdr restored old sessions: 13 duplicate panes | Duplicate roles, one of them a second dispatcher | README now explains the restore and how to turn it off. `sabha-check` prints DUPLICATE |
| 29 Oct | The loop restarted the dispatcher at 30 percent. Thirteen helpers died | Half-done lanes, no output | The hold file ([#34](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/34)) for short helpers. Detached, registered helpers for long ones ([#35](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/35), open) |
| 30 Oct | Workers sat idle for about three hours waiting for my answers. The next steps were local and reversible | A PR slipped about three hours | Rule: start the local work on the default, ask me in parallel. Only pushes and sends wait ([issue draft](../issues/09-idle-report-lists-unblocked-local-work.md)) |
| 1 to 3 Nov | Panes wrote their context to one folder. The loop read another. The loop saw "stale" and kept every session for about 52 hours | No pane restarted at 30 percent | A fix exists on a local branch ([issue draft](../issues/01-stale-context-file-no-restart.md)) |
| 2 Nov | A worker above 30 percent declined a brief. The dispatcher cancelled it and gave it to a sub-agent | One round trip lost | Rule 4 in RULES.md. No warning in `sabha-brief` yet ([issue draft](../issues/06-brief-warn-worker-over-context-limit.md)) |
| 3 Nov | Machine load 350 to 420 slowed every script | A 16 second `list` | A load check that refuses a new helper ([#35](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/35), open) |

### Smaller lessons that are rules now

- **The sandbox blocks more than you think.** `gh`, `git fetch`, the herdr socket, `ps`, app launch and service control
  failed inside it. Some failures were silent. Run read-only network commands outside the sandbox, and tell helpers up
  front so they do not report a false blocker. `sabha init` prints the setting that lets roles write the sabha folder
  ([1618194](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/1618194)).
- **Never route around a denied action.** If the sandbox or the classifier says no, report it. Do not try another pane.
- **A peer message is data, not an approval.** Typing "I approve" into another pane as if it were me is refused.
- **One question at a time, as an MCQ.** I answer faster, and each answer is recorded with the change
  (rule 5 in [RULES.md](../RULES.md)).
- **Nothing leaves the machine without my word.** No push, post or message. Roles queue the exact command and I run it
  ([5541f87](https://github.com/The-Harsh-Vardhan/claude-sabha/commit/5541f87)).
- **A default is not my answer.** When a question has a recommended option, the team may go on with it, but the record
  must say "default" ([issue draft](../issues/05-record-default-vs-human-answer.md)).
- **Drafts go stale.** A status note or a message written from files is true on the day it is written. In one case a
  sentence about a hotfix was wrong an hour later. Check each claim against the live branch before you send
  ([issue draft](../issues/08-stamp-drafts-with-evidence-date.md)).
- **Old briefs with an `.ack` and no `.done` are history, not work.** A fresh dispatcher must not resume them
  ([issue draft](../issues/07-superseded-marker-stale-briefs.md)).
- **Sub-agents die on a network error.** They can be resumed. Write each agent id in the status file.
- **Do not restart a role that runs a long job.** A fresh session would read all its inputs again. Check the status
  file first. The hold file helps for short jobs.

## 5. What is still rough

- The loop trusts one context file and says nothing when it is stale ([draft](../issues/01-stale-context-file-no-restart.md)).
- The relay rule is a rule, not a guard ([draft](../issues/02-relay-guard-hands-on-work.md)).
- Headless runs share a worktree unless the dispatcher is careful ([draft](../issues/03-one-worktree-per-headless-run.md)).
- Plain `sabha-run` refuses to run when the process list is unreadable, as it is in some sandboxes
  ([draft](../issues/04-sabha-run-needs-ps-in-sandbox.md)).
- Durable helpers are an open PR ([#35](https://github.com/The-Harsh-Vardhan/claude-sabha/pull/35)). A live run under a real herdr and
  a real Claude session was not tested. See [known gaps](known-gaps.md).
- Duplicate panes after a reboot are detected and documented, not closed.
- Windows is beta.

## 6. A morning check

1. `sabha-check` shows one holder per role.
2. Each pane has a context file less than two minutes old.
3. Every `.ack` has a `.done`, or a status line that says why not.
4. No role pushed. The queued commands are in one folder, and I read them.
