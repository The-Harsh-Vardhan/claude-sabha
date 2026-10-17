# Lessons

Owner: the coach role. Every mistake that cost time or money becomes a rule here, so it is made once. Newest first.
A lesson with no rule is a story; if no rule follows, say why. When a rule moves into PROTOCOL-core.md or a role card,
note it on the entry.

Entry shape:

```
## <YYYY-MM-DD>: <title>
What happened: <facts, no blame>
Cost: <time, usage, or damage>
Rule now: <one sentence a session can follow>
```

## 2026-01-05: A resumed session brought the whole context back
What happened: A session over its context limit was resumed instead of restarted, so the new session started with the
same full context.
Cost: The restart saved nothing; the session hit the limit again within the same task.
Rule now: Restart fresh from the status file and the same opening prompt; never `--resume`.

## 2026-01-05: A test opened real sessions on the user's terminal backend
What happened: A test ran without a fake terminal backend and created real workspaces and started real agent
sessions on the user's own setup.
Cost: Dozens of stray sessions and panes to close by hand, and the user's own work disturbed.
Rule now: Tests are hermetic: source the hermetic helper, put the fake backend first on `PATH`, and refuse to run when
the real one would be found.

## 2026-01-05: Piping a command broke its sandbox exclusion
What happened: A command allowed to run outside the sandbox was piped into another command, so the permission match no
longer recognised it and it ran inside the sandbox and failed.
Cost: A confusing failure that looked like a bug in the tool, and a retry loop.
Rule now: Run an excluded command on its own, with no pipe or chain; filter its output in a second step.
