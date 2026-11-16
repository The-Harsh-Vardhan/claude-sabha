---
name: sabha-bug-fix
description: Fix a bug ticket end to end with proof - reproduce it in the browser (Claude in Chrome extension) with a screenshot, fix it in a worktree, run it locally, verify in the browser that it is gone with a screenshot, then prepare the PR with before/after screenshots, a status page and a ticket progress comment. Use when asked to "fix <ticket>", "do the tickets", "fix <person>'s bugs", or when handed a bug ticket list.
---

# Bug fix (reproduce -> fix -> verify -> PR)

Rule: no fix without seeing the bug first and seeing it gone after. Built on the feedback-loop idea of a tight
red/green signal before any theory, with the browser as the loop.

## The loop, per ticket (do not skip a step; say so if one cannot run)

1. **Read the ticket fully.** Description, every comment, attachments, linked tickets (through the tracker tools, only
   when the request names the tracker: RULES.md rule 6). Write the ask in the tester's own words. Note priority; work
   Highest -> High -> Medium. If the ticket has no real symptom (template text unfilled, only an unreadable
   screen recording), first try to reproduce it from the title in the browser (common platforms, the obvious steps).
   Only if that shows nothing, draft one question to the reporter (error text, platform, device, steps) and move on.
   **Never get stuck on "not in design", "not our code" or "nobody decided":** build what the ticket asks, label it
   ("NOT IN DESIGN - needs owner approval" / "needs <owner>'s decision"), tag the owner as reviewer, prepare the PR.
   Approval gates the merge, never the build. Where owners might prefer another option, build the ticket's ask and
   list the alternative in the PR body; do not build option menus.
2. **Reproduce in the browser whenever it is reproducible.** Skip the browser only when the bug depends on something
   the local stack or browser cannot reach: SSL/TLS settings, cloud services (object storage, queues, IAM), parameter
   stores, a cloud lab device, a third-party service. Then say "not reproducible locally: <reason>" and prove it with
   tests only (step 3 becomes the whole before/after proof). Otherwise: load the `claude-in-chrome` skill, open the
   page the ticket names (the environment the tester used, or the local stack, started as the project's own run
   instructions say), follow the steps. **Screenshot the bug** and save it as
   `docs/<project>/bugs/<ticket>/before-<n>.png`. If it does not reproduce, record what you saw (screenshot) and ask
   the reporter before fixing anything. Wrong bug = wrong fix.
3. **Make it red in code.** Add a failing test at the closest seam (unit/component/e2e) that asserts the tester's
   exact symptom. Run it; show the failing line.
4. **Fix**, with the minimal-change ladder first: before writing any code, ask of the planned fix: does it need to
   exist, is it already in the codebase, does the standard library cover it, can it be one line (the `ponytail` skill
   does this when it is installed). Pick the smallest root-cause fix. Then write it in a worktree beside the checkout
   (RULES.md rule 7) on a branch from the repo's current base (fetch with an explicit refspec; the base can move or
   be deleted). Read the repo's own guide first. Other teams' repos only when the ticket needs it. Anything not in
   the design: build it, label it "NOT IN DESIGN - needs owner approval" in the commit and PR body.
5. **Clean the code after it is written, before the gates**, on the diff: `simplify` (reuse, simplify, efficiency; it
   applies the fixes), then `code-review` (correctness bugs; fix what it confirms). Re-run the failing test after
   each pass. Note in the PR body what the minimal-change pass chose and what simplify and code-review changed.
6. **Gates:** the repo's build, vet/lint, typecheck, the new test green, the touched suites green. Heavy runs one at
   a time through `bin/sabha-heavy run <label> -- <command>`; exit 75 means the gate said wait: nothing ran, say so
   and try later, never force the slot.
7. **Run it locally:** start the fixed build on the local stack (or fold it into the main checkout uncommitted if
   that is how the stack picks it up; one session does that and commits later, RULES.md rule 7).
8. **Verify in the browser** (or, when step 2 was skipped, the test from step 3 now passing). Same page, same steps.
   **Screenshot the fixed state** as `after-<n>.png`. Also check dark mode and one nearby case. If it is not fixed,
   back to step 4.
9. **Prepare the PR.** Write the PR body: what the tester saw, root cause, the fix, gates run and not run (state
   "security scan NOT RUN" if its tool is down), and the before/after screenshots. Name the reviewer the repo or the
   brief names. Stop at the local commit and hand over the push block as text (exact `git push` and `gh pr create`
   commands, branch `fix/<ticket>-<slug>`, no force, against the current base) for the human to run: RULES.md rule 6,
   and the guard blocks push and `gh` writes for every role. A `go:` line in the newest brief moves the push to the
   relay or the human, never to the worker. Never merge, never deploy, never force-push.
10. **Status page:** add or update the ticket on the `sabha-status-review-page` artifact (before/after shots with
    boxes, verify steps, PR link, waiting on).
11. **Progress comment on the ticket**, only with the human's explicit yes for that comment, and posted by the relay
    or the human, not the worker: PR link + page link + "fix ready, to verify on <environment> after deploy". Never write "fixed" and never
    transition the ticket without the human's yes; Ready to Test comes after the deploy and a re-check there.

## Output per ticket (one line each to the human)

`<ticket>: reproduced (before.png) -> root cause file:line -> fix sha -> verified (after.png) -> PR #n -> waiting on <who>`
or `<ticket>: blocked: <what is missing>, question drafted for <reporter>`.

## Never

- Fix a reproducible bug without a reproduced screenshot, or open its PR without an after screenshot.
  (Not reproducible locally - SSL, cloud services, parameter stores, lab device: a red-then-green test is the proof,
  and the PR says why.)
- Write the fix before the minimal-change pass has shaped it, or open a PR before simplify and code-review have run
  on the diff.
- Call it fixed before the tester verifies; post anywhere except the PR and the ticket's progress comment.
- Push to a shared branch, force-push, merge, deploy, or read `.env*` / secret files.
