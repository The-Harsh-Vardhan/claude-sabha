# <Project name>

Replace this section with three lines: what the project is, where the source of truth for what to build lives (spec,
PRD, issue list), and where the repositories are. Read a repository's own guide before the first edit there.

## Sabha rules

The seven working rules are in `RULES.md` of the claude-sabha repository; read them there rather than copying them
here, so this file never drifts from them. The file formats (briefs, acks, dones, the GO token) are in
`docs/inbox-protocol.md` of the same repository, and the short per-session version is `PROTOCOL-core.md` in
`SABHA_IMPL` (in the repo's `.sabha/` when the team shares its files). Your own job is in `protocol/<Name>.md`.

## Files, owners and when they change

A file has one owner role; other roles propose changes through a brief to the owner. Role names are the default roster
(`sabha.<plan>.conf`); every role in the default roster has a card in `protocol/`. On a smaller plan the relay assigns
a missing role's files to the nearest role (without Scribe, Writer keeps `DECISIONS.md`).

| File | Owner role | When it is updated |
| --- | --- | --- |
| `ARCHITECTURE.md` | Architect | When a design changes, in the same change as its decision |
| `DECISIONS.md` | Scribe | When a costly-to-undo choice is made or a question card is answered; append only |
| `LESSONS.md` | Coach | After a mistake that cost time or usage; one rule per entry |

Shared team files: when `SABHA_SHARED` is set, `ARCHITECTURE.md`, `DECISIONS.md`, `LESSONS.md`, `PROTOCOL-core.md`
and `protocol/` live in the repo's `.sabha/`, committed. Edit them in the worktree of the change they belong to, so
they ship and are reviewed with it; never in the main checkout, which cannot commit. Teammates add entries at the same
time, so an entry in `DECISIONS.md` or `LESSONS.md` is headed by who and when, not by a number:
`## <SABHA_USER_ID>_<HH:MM:SS>_<DD>_<MM>_<YYYY>: <title>` (`date +%H:%M:%S_%d_%m_%Y`), and `.sabha/.gitattributes`
merges both logs with `merge=union`. `.sabha/local` is your own sabha folder (status, inboxes, `GOALS.md`); never stage it.
| `TODOS.md` | Relay | Regenerated from the tracker whenever a row changes; never edited by hand |
| `status/<name>.md` | every role, its own file only | After each task and before a restart; the top block is the handoff |
| `GOALS.md` | Writer, on the dispatcher's word | When a step is done: tick the box, keep the history |
