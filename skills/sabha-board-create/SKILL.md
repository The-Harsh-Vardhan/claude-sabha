---
name: sabha-board-create
description: Use when the human wants a progress board for their sabha for the first time, or asks to create, publish or set up the board, the Sabha Manager page, or SABHA_BOARD_URL, and no board exists yet (SABHA_BOARD_URL empty).
---

# Create the progress board (first time only)

Source: `template/board/index.html`, `template/board/board.capabilities.json`, `template/board/board-schema.md` (read the
schema first: placeholders, collections, write rules), RULES.md rule 6 (nothing leaves the machine without a yes).

## Who runs this

The relay, only when `SABHA_RELAY_ALLOW_TOOLS` lists Artifact,ArtifactData in `sabha.conf` (with `SABHA_RELAY_GUARD=1`
the relay guard denies the Artifact tools otherwise), or the human. Without that line the human starts the prompt with
"you do it" (one turn), or the dispatcher briefs it. A worker never publishes: it hands the relay a brief. Publish
only from the human's own account, so the page is theirs; never create a board for someone else's account.

## Steps

1. Stop if `SABHA_BOARD_URL` in `sabha.conf` is already set: a board exists. Update it through the Artifact tool, do not make a second one.
2. Ask the human, one question at a time, with a default: board title (default "Sabha board"), their name, the relay
   and architect role names (read them from the theme in `sabha.conf` when set), the time zone (default `UTC`), the lanes,
   and the project list (default `["General", "Other"]`). Get a yes before publishing: it creates a page on their account.
3. Copy `template/board/index.html` to a scratch file and replace every placeholder from `board-schema.md`. Replace
   `__LANES__` and `__PROJECTS__` with JSON arrays, the other placeholders (`__HUMAN_NAME__`, `__RELAY_NAME__`,
   `__ARCHITECT_NAME__`, `__TIMEZONE__`, `__BOARD_TITLE__`) with plain text with no quotes, angle brackets, backslash
   or newline. Each JSON array must pass `python3 -I -c 'import json,sys; json.loads(sys.argv[1])' '<array>'` and
   contain no `<`. Check that no placeholder remains: `grep -c '__[A-Z_]*__' <file>` must print 0.
4. Artifact `quickstart` (intent `other`), then load the `artifact-design` and `artifact-capabilities` skills as it says.
   Publish the scratch file with `capabilities` set to the contents of `template/board/board.capabilities.json`, an
   icon such as `board`, and a one-line description.
5. Seed rows with one `ArtifactData` `batch`: `set` each row in `queue`, nothing in the other collections.
   - From open items: the OPEN blocks in `FOR-ME.md` (run `bin/sabha-for-me` once first) become rows with state
     `BLOCKED-HUMAN`; each brief in `$SABHA_IMPL/inbox/<Name>/` with an ack and no done becomes a `RUNNING` row.
   - With nothing open: one row whose `ask` starts with `EXAMPLE`, state `READY`, so the page shows a card. The human deletes it.
   Fill the fields of each row as the queue row section (`## queue row`) of `board-schema.md` lists them. `lastChangeAt` comes from `date -u +%Y-%m-%dT%H:%M:%SZ`.
6. The human adds the artifact URL to `sabha.conf` as `SABHA_BOARD_URL="<url>"` (edit the existing line; keep the
   quotes). Give them the exact line: the guarded relay cannot edit `sabha.conf`.
7. The human also sets `SABHA_RELAY_ALLOW_TOOLS=Artifact,ArtifactData` in `sabha.conf` before the relay publishes
   (the relay guard denies these tools otherwise; it re-reads the conf on each call). Restart the relay once the URL is
   set, so its prompt tells it to keep the board current.
8. Tell the human the URL and ask them to pin the page in their sidebar. Do not pin it yourself.

## Rules

- No secrets, tokens or real personal data in a row; a row is visible to everyone the page is shared with.
- Stamps come from the real clock (`date -u`), never a guess.
- Every later `update` passes `if_version` with the version just read.
- Share the page only on the human's word; it is private by default.
- Do not change the page's views or add controls: only the placeholders change. A change to the design goes to the template, in a pull request.

## When it fails

- `quickstart` or publish refused: say so and stop. Do not try other hosting.
- A placeholder is left, or `SABHA_BOARD_URL` is not writable: report it, and leave the artifact as it is.
