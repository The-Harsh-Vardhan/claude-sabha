# Decisions

Owner: the scribe role. Append-only: a decision is never edited; a change is a new decision that says "supersedes
<id>". Record a decision when it is costly to undo or when someone could reasonably ask "why".
The id is who and when, `<SABHA_USER_ID>_<HH:MM:SS>_<DD>_<MM>_<YYYY>`: teammates append at the same time, so a number
would clash. Shared in the repo's `.sabha/`, this file merges with `merge=union` (`.sabha/.gitattributes`).

Entry shape:

```
## <SABHA_USER_ID>_<HH:MM:SS>_<DD>_<MM>_<YYYY>: <title>
Context: <what forced a choice>
Options: <A: ...; B: ...; C: ...>
Decision: <the option chosen>
Decided by: <the human, or the role, and the brief or card it came from>
Consequences: <what gets easier, what gets harder, what must change now>
```

## sabha_09:00:00_05_01_2026: Keep session state in files, not chat
Context: Sessions restart when their context fills, and a restart that depends on chat history loses work.
Options: A: resume the old session; B: summarise in chat and continue; C: write a handoff to a status file and start a
fresh session that reads it.
Decision: C.
Decided by: the human, answering the first question card.
Consequences: Every role updates `status/<name>.md` after each task, so a restart costs nothing. A role that skips it
loses its work at the next restart; the reviewer checks the status file is current before accepting a done.
