# Delegated writes and kills

A dispatcher or a worker may be refused an action the human already approved: a write to an outside system, or a
process kill, delegated to a helper. The permission check is right to refuse it. This page is the one pattern for what
to do next, so a refusal is a planned stop, not a surprise.

## 1. Classify the action

| Class | Examples | Who does it |
| --- | --- | --- |
| Local and reversible | edit a file in a worktree, run a test, a local commit | the role, at once |
| External write | Jira field, Slack message, `gh pr edit`, `git push`, a comment | the human, from a pack |
| Destructive | SQL that writes, `kill`, `docker compose down -v`, `rm -rf` | the human, from a pack |

## 2. Write a pack, tell the relay

For an external write or a destructive step the dispatcher writes a pack file in its inbox: the exact commands, one per
line, no inline `#` comments, no elided text (`...`). Steps in a UI go in prose, never in a command block. Then it sends
the relay one line naming the pack. The human runs the pack, or the relay session runs it when its own permissions
allow it.

## 3. A refusal is a stop

Do not retry, rephrase or route the action through another role or tab. Record it in the human's queue
(the queue row's blocked-on-human state) and as an open `for-me.items` block carrying the pack
path in `cmd:` or `why:`, and go on with the next local work.

## 4. Optional: an allow rule the human adds

For a narrow command the human runs often, they may add an allow rule to their own Claude Code settings. Shape only:

```json
{ "permissions": { "allow": ["Bash(gh pr edit 12 --base main)"] } }
```

Keep the rule to the exact command. Check it against the current Claude Code permission rule syntax before use. The
human edits their own settings; no agent edits anyone's settings.
