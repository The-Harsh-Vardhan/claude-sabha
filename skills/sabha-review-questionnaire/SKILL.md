---
name: sabha-review-questionnaire
description: "Turn open decisions into a published MCQ page (example, one recommended option, ticket and repository links, copy answers or an Answer-with-Claude prompt), then record the answers. Use for /sabha-review-questionnaire <source or questions.md> [for <who>], or when questions pile up for the human or a reviewer."
argument-hint: "<source doc, delta list, or questions.md> [for <who>]"
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/sabha-review-questionnaire/build.py:*), Bash(ls:*), Bash(cp:*), Bash(grep:*), Read, Write, Edit, Grep, Glob
---

# sabha-review-questionnaire

**You are the person who turns a pile of open questions into one page a busy reviewer can answer in minutes: each question explained in plain words with an example, the options laid out, your recommendation marked, and their answers coming back in a form you can apply.**

If `${CLAUDE_PLUGIN_ROOT}` below appears literally (the variable is empty), use the claude-sabha clone directory (the one that holds `bin/sabha`) in its place.

1. **Collect the questions.** If the argument is already a questions file in the format below, go to move 3. Otherwise read the source (a `.done` report's list of questions for the human, review findings, a spec's open questions) and list each decision the reader owns. Grep each id in its spec or plan and read about 30 lines around it; do not read whole specs. Done when every question has a source line you read.
2. **Write the questions file** beside the work, usually `docs/<topic>/questions/for-<who>-<topic>.md`, in the format below. Order: security and blocking items first, confirm-only items last. Each question gets a `Links:` line (its ticket and the repositories or pull requests it touches; take repository names from `git remote get-url origin`, never from memory), a plain "What it is" (the stake in user-visible or security terms), one concrete "Example", 2-4 options each with its own example, and exactly one `(recommended)` with a one-line reason. The spec's current default is the recommendation unless the source argues otherwise. Done when `grep -c '(recommended)'` equals the question count.
3. **Build the page.** `python3 ${CLAUDE_PLUGIN_ROOT}/skills/sabha-review-questionnaire/build.py <questions.md> <questions.html>`. It refuses to overwrite: on a re-run, version the name (`.v2.html`). Done when it prints `wrote <path>: <M> questions, <K> with recommendation` with K = M. On a parse error, fix the line it names.
4. **Publish and hand it over.** Publishing follows RULES.md rule 6: only the relay or the human publishes; a worker hands the HTML path to the relay and does not publish. Publish the HTML with the Artifact tool (quickstart first for a new page; redeploy the same path to keep the link) and give the link plus the questions file path. Say: pick an option or "Other" per question, add notes, then "Copy answers" (short lines) or "Answer with Claude" (the full questions, options, recommendations and picks, with a task line) into chat. Inside an artifact "Save answers file" does nothing (downloads are blocked there); it works when the HTML is opened as a local file.
5. **Apply the answers** when they come back. Copy the questions file to a new version (`cp -n`), fill each `Answer:` from the answers text (`Q<n> (<id>): <letter or Other: text>` plus an optional `Q<n> note:` line), and give each a decision number in the project's decision log when it has one (for example a `D<nnn>` number in `DECISIONS.md`) in `Decision:`. Done when no answered question has an empty `Answer:`; list any question left unanswered.

Questions file format (`build.py` parses exactly this):

```
# <title>
for: <who answers>
context: <one line, optional>

## Q1 - <id>: <short title>
Source: <spec or doc, line>
What it is: <paragraph>
Example: <concrete scenario>
Links: https://<tracker-host>/browse/<KEY> https://github.com/<org>/<repo>
- A (recommended): <option>. Example: <what changes>. Reason: <one line>
- B: <option>. Example: <what changes>
Answer:
Decision:
```

`Links:` is optional; a `/browse/KEY` URL shows as "Jira KEY", a GitHub URL as "GitHub org/repo" (plus `#n` for a PR). A `## Note ...` section after the questions renders as a plain note card. The page needs no network and keeps a draft in the browser.

Gotchas:
- **A recommendation must be one the source supports.** Mark the spec's default, or say in the reason why you differ; a recommendation that reverses a spec without saying so gets accepted unread.
- **Confirm-only questions still need two options** (A: keep as applied, B: revert); the builder rejects a question with fewer than two.
- **After changing `template.html` or `build.py`, run `tests/test-review-questionnaire.sh`.** It checks the build, the refusal to overwrite, the parse errors and the escaping on a sample file. It does not run the page's JavaScript (buttons, draft, load and save): a change there needs a look in a browser.
- **Paths you hand over go in plain text, not code blocks with arrows or comments**: the human may paste them into a shell.
- **Write about 70 percent of the reader-facing text in ASD-STE100 Simplified Technical English** (use the `SABHA_STE100_PERCENT` number instead when `sabha.conf` sets one): short sentences (about 20 words or fewer), one idea each, active voice, simple common words, no unexplained jargon. Bad: "The fix defaults role-less keys to Admin, widening REST authz." Good: "Keys made without a role get the Admin role. Admin can do everything, so this is a security decision." Commit IDs, error codes, file paths and test logs go in a folded "Technical detail" part, never in the question, the options or the recommendation.

Write for the person answering, in their words, ASCII only. This skill writes the questions file, the HTML and the answered copy; it does not act on the answers (code, specs, plans) beyond recording them. Answers and their decision numbers travel with the pull request the questions came from.
