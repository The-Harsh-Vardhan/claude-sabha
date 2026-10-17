# <Project name>

Replace this section with three lines: what the project is, where the source of truth for what to build lives (spec,
PRD, issue list), and where the repositories are. Read a repository's own guide before the first edit there.

## Sabha rules

The seven working rules are in `RULES.md` of the claude-sabha repository; read them there rather than copying them
here, so this file never drifts from them. The file formats (briefs, acks, dones, the GO token) are in
`docs/inbox-protocol.md` of the same repository, and the short per-session version is `PROTOCOL-core.md` in
`SABHA_IMPL`. Your own job is in `protocol/<Name>.md`.

## Files, owners and when they change

A file has one owner role; other roles propose changes through a brief to the owner. Role names are the default roster
(`sabha.<plan>.conf`); the role cards in `protocol/` cover Vidur, Yudhishthira, Bhishma, Bhima, Arjun, Sahadev,
Nakul and Dronacharya (the coach, Max 20x plan). The extra scribe (Sanjaya) has no card yet; on a smaller plan the
relay assigns a missing role's files to the nearest role.

| File | Owner role | When it is updated |
| --- | --- | --- |
| `ARCHITECTURE.md` | architect (Bhishma) | When a design changes, in the same change as its decision |
| `DECISIONS.md` | scribe (Nakul) | When a costly-to-undo choice is made or a question card is answered; append only |
| `LESSONS.md` | coach (Dronacharya) | After a mistake that cost time or usage; one rule per entry |
| `TODOS.md` | relay (Vidur) | Regenerated from the tracker whenever a row changes; never edited by hand |
| `status/<name>.md` | every role, its own file only | After each task and before a restart; the top block is the handoff |
| `GOALS.md` | scribe (Nakul), on the dispatcher's word | When a step is done: tick the box, keep the history |
