# Decisions

Owner: the scribe role. Append-only: a decision is never edited; a change is a new decision that says "supersedes D<n>".
Numbers are never reused. Record a decision when it is costly to undo or when someone could reasonably ask "why".

Entry shape:

```
## D<n>: <title>
Date: <YYYY-MM-DD>
Context: <what forced a choice>
Options: <A: ...; B: ...; C: ...>
Decision: <the option chosen>
Decided by: <the human, or the role, and the brief or card it came from>
Consequences: <what gets easier, what gets harder, what must change now>
```

## D1: Keep session state in files, not chat
Date: 2026-01-05
Context: Sessions restart when their context fills, and a restart that depends on chat history loses work.
Options: A: resume the old session; B: summarise in chat and continue; C: write a handoff to a status file and start a
fresh session that reads it.
Decision: C.
Decided by: the human, answering the first question card.
Consequences: Every role updates `status/<name>.md` after each task, so a restart costs nothing. A role that skips it
loses its work at the next restart; the reviewer checks the status file is current before accepting a done.
