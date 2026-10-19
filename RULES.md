# Rules for your Claude

Seven working rules that make a sabha cheap, calm and safe. They are written to be pasted into the `CLAUDE.md` of
your workspace (or the relay's), so every session reads them. Each has the reason, so you can drop one knowingly.
The same text, in shorter form, is in `template/impl/PROTOCOL-core.md`.

## 1. Restart fresh above 30 percent context

Every session, the relay included, restarts once its context passes 30 percent, and saves its progress to files after
each task so a fresh session loses nothing. A restart is a FRESH session that reads the state files, never
`--resume`, because a resume brings the whole context back. Write the handoff first (`Task`, `Done`, `Next`,
`Constraints` in `status/<name>.md`), and never stop a session mid-task for this. `sabha-loop` does it for you when
the statusline hook is on.

Why: small contexts are cheaper and sharper, and a restart that loses nothing costs nothing.

## 2. The relay talks to you; the dispatcher dispatches; workers work

You talk to one session, the relay. It does no work itself, which keeps its context small: it turns each request into
a brief for the dispatcher and relays the answers. The dispatcher assigns briefs to workers by difficulty, tracks
them and reports at milestones. Pages, reviews and reading reports belong to workers, not the relay. While the
dispatcher is up, the relay starts no helpers of its own.

Why: one conversation partner and one dispatcher, with the work in sessions that follow the cost rules, not in your chat.

## 3. Cheapest model that fits, state in files

Start every brief at the cheapest model and a medium effort; step up only with a reason written in the brief. Strong
models for new hard design and for code gates; a mid model for finishing, fixing, reviewing, coordinating and docs; the
smallest model for mechanical runs (never at low effort). Keep state in short status files that a restart prompt
points at, let workers keep their results rather than their dumps, batch your questions, freeze a design and make
each change a numbered decision.

Why: a week of usage is finite, and several strong sessions at once hit the limit together.

## 4. Never queue behind a busy role

A role is a label for a model and an effort, not a person. When a role is busy, above 30 percent or down, run the
work as a subagent with that role's model, or start a copy (`BuilderPrecise-2`), and run independent briefs side by side.
Stay cost-aware: the cheapest model that fits, no strong model for docs.

Why: waiting for one session to restart costs wall-clock time, and the roles are cheap to copy.

## 5. Ask in MCQ shape, one question at a time

A question for you is written as: the question, a line on why it matters, options A/B/C each with its consequence
and a concrete example, the recommended option, and a free-text way to answer. On the board each open question is a
card with radios and a "Copy answer" button that yields a line such as `Answer 7: B - <text>` to paste back to
Claude. In chat ask one question per message, wait for the answer, then ask the next. Record each answer in the file
that ships with the change, so the approver can see what was decided and why.

Why: you answer faster from a page than from chat, and copy-paste keeps the answer exact.

## 6. Nothing leaves the machine without your word

No push, pull request, release, post, message or comment on a connected service (chat, tickets, email, drives, docs)
without your explicit yes for that specific action. Do not read a connected service either unless you named it for
the task; when the context lives there, the agent asks you for it instead of searching. A draft is the safe way to
prepare wording; you send it yourself. Repository files, the repository's own `gh` and public documentation are not
connected services. Briefed subagents inherit the same limits, so say so in their prompts. Commands that you must run
carry no inline `#` comments, because a shell may pass them as arguments, and UI click paths are prose, not code.

Why: a message or a push in your name is hard to take back, and a draft costs nothing.

## 7. Helpers stage, one session commits

Workers do their work in a worktree beside the checkout and stage it; they never push and never commit in the main
checkout. One session (the relay, or you) commits, after review, one feature at a time. Fold a reviewed change into
the main checkout uncommitted, test it there, then make one commit per repository per feature. In a low-memory
setup, run each role as a subagent of the relay instead of a pane; the rule does not change.

Why: it keeps every commit reviewed and attributable, and a worker's mistake never reaches the main line.

## Also worth a line

- Keep a single task list (`tracker`): every request you make becomes a row with a priority, a deadline and a status;
  a mirror (Google Sheet or local HTML) lets you answer from your phone. See the README, "Tracker".
- Never read or print `.env*`, `.npmrc` or key files. `share/claude-settings.json` denies the common ways to do it.
