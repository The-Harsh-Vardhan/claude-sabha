---
name: sabha-status-review-page
description: Build a status or review page (Claude Artifact) for a set of tickets, PR review asks or QA issues - grouped Fixed / In review / Still open, one block per item with a 6-column table (asked, why it failed, had to do, did, current state, next owner), side effects, then before-left / after-right screenshots split by a line. Use when asked for a status page, review page, ticket report, before/after page, or "the format of the page I want" for tickets, a reviewer's comments, or QA findings.
---

# Status review page

The page for showing work on a list of items (tickets, a reviewer's asks, QA findings) to the human, a reviewer or QA.
If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`) in its place.

## Format (do not change without the human's yes)

1. Title, one-line intro with the date and time, and what "fixed" means.
2. Summary strip: one count per group.
3. Groups in this order: **1. Fixed, verified by the tester**, **2. Fixed by us, in review / not deployed**, **3. Still open** (blocked on a decision, replies to send, hand-backs).
4. One index table at the top (S. No, item, **feature** (`"feature"`, for example the product area; shown when any item has it), title, priority, tracker status, current state, **PR** link, **Waiting on** = who or what it is stuck on; `"waiting"` in the spec), then one block per item. No Group column (it repeats the state).
5. Per item block:
   - Heading: number, linked id, title, priority pill, state pill, tracker status and PR link.
   - A 6-column table: **What was asked** (the asker's words) | **Why it failed earlier / design deviation** (`cause`: the real root cause, or "not our code", or "not a failure") | **What we had to do** | **What we did** | **Current state** | **Next (owner)**.
   - **Side effects / risks** line when there are any.
   - Screenshots: **BEFORE strictly left, AFTER strictly right**, a line down the middle. A missing side is a dashed "No before shot" cell, never an empty slot that shifts the other image. Option comparisons (A vs B) relabel the heads; mockups are labelled "mockup, not shipped".
6. Sources line at the end, saying which images could not be obtained.
7. **Status legend**: below the index table, one line per status used on the page (`"legend": [{"st", "state", "meaning"}]`). Write states in plain words ("PR open, checks passed"), never jargon like "Pushed, CI ok".
8. **Blast-radius boxes**: draw boxes on screenshots around what is wrong (before, red) or what changed (after, green), each with a 2-6 word label. Spec: `before_boxes` / `after_boxes` = [{x, y, w, h, label}] in PERCENT of the image (read real pixel sizes from the PNG header, never guess). Boxes show in the full-screen view too. A helper agent can measure them: give it the image list and ask for percent boxes in one JSON file.
9. **Full-screen screenshots**: every screenshot opens full screen on click or Enter (built in; Esc, Close or a click closes it), with its caption under it.
10. **Name the reviewer and quote them**: wherever a reviewer, owner or tester shaped the outcome, name them in bold and quote their exact words with the source (chat, PR number with link, ticket date). Look them up (`gh api .../pulls/<n>/comments`, ticket comments, notes under the project's docs folder), never paraphrase as "a reviewer".
11. **Self review** at the end: top-level `"review": {"title", "sub", "sections": [{"title", "items": [...]}]}` with sections What I did / What went wrong / How I will improve / Questions for my mentor. Facts only from the session and evidence files; label it a draft for the human to edit, never a verdict.
12. **How to verify it yourself**: every item gets numbered manual steps (`verify`) with a link to the exact page on the shared test environment (`<env-base-url>/...`; confirm routes in the app's route files), each check starting "Check:". Items not yet deployed start with the step "Only after <PR> merges and the environment is redeployed." Not-ours items say who verifies.
13. **Cascade order**: when one item's change is also visible in another item's screenshots or behaviour, the source item comes first. Give the dependent item `"deps": ["<source id>"]`. The builder orders items so every dep comes before its dependents (lowest group first otherwise), numbers them 1..n in that order, splits a group with a "(continued)" heading when a cross-group dep forces it, and adds "Builds on" / "Also visible in" links. Example: item B's after shot uses item A's picker fix, so A is shown before B.

Optional, for decision pages: open questions as radio-button MCQs (recommended preselected, note box, "Copy answers" button). Use the `sabha-review-questionnaire` skill.

## Steps

1. Gather facts. Read the tickets or comments the user names (the tracker only when the user named it). Every state must be verified: "fixed" only when the tester verified it; "pushed" only after `gh`/`git ls-remote` shows it.
2. Find screenshots on disk (`find docs -iname "*<ticket>*" -name "*.png"`, owner-shots, environment folders). Open a few with Read to check captions; say which ones you did not open.
3. Write the spec JSON (shape below) next to the page, e.g. `<page>-spec.json`.
4. Build: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/sabha-status-review-page/build_page.py <spec.json> <page.html>`. It prints `built <page.html>: <n> items`; a bad `deps` id or a dependency cycle exits with a `spec error` line.
5. Publish with the Artifact tool; pass every image through `files` (`root` = the folder the spec paths are relative to). Republish to the same file path to keep the URL. Publishing follows RULES.md rule 6: only the relay or the human publishes; a worker hands the page path to the relay.
6. Tell the human the link, what is in each group, what could not be shown, and that the page is private until they share it.

## Spec shape

```json
{
  "title": "Sprint Bug Tickets",
  "intro": "All 21 ... as of <date and time, zone>. ...",
  "sources": "Tracker (read <date>), GitHub, docs/<project>/ ...",
  "groups": [
    {"title": "1. Fixed: verified by the tester", "short": "verified", "sub": "Nothing left to do.",
     "items": [
       {"id": "BUG-101", "url": "https://<tracker-host>/browse/BUG-101",
        "title": "Upload popup not as per design", "priority": "Medium", "tracker": "Verified on Staging",
        "st": "ok", "state": "Verified", "pr": "<repo> #123",
        "asked": "...", "todo": "...", "did": "...", "now": "...", "next": "None",
        "side": "optional",
        "deps": ["BUG-105"],
        "shots_note": "optional one line above the screenshots",
        "verify": ["Open <a href=\"https://<env-base-url>/settings/uploads\">Settings > Uploads</a>.", "Check: ..."],
        "shot_heads": ["BEFORE", "AFTER"],
        "shots": [{"before": "img/101-before.png", "before_cap": "Side sheet",
                   "after": "img/101-after.png", "after_cap": "Centred popup"}]}
     ]}
  ]
}
```

`st` picks the state colour: `ok` (green), `push` / `ready` (blue), `block` (amber), `send` / `back` (grey). Text fields may hold simple inline HTML links.

## Rules

- Plain words, short sentences; ASCII in the spec text.
- Never claim "fixed" for anything not verified by the tester; say "in review" or "ready to push".
- Mark anything outside the design "NOT IN DESIGN - needs owner approval".
- Do not send the page to anyone; the human shares it.
