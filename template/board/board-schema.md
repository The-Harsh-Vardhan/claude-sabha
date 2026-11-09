# Board template: placeholders, data layout, write rules

`index.html` is the page; `board.capabilities.json` is the capability block to publish it with (a shared database
and the viewer's profile, which stamps who changed a row). The page holds no row data: every row lives in the
artifact's shared database and the page reads it live.

## Placeholders

The `sabha-board-create` skill replaces each of these, everywhere it appears in `index.html`, before publishing.
Nothing else in the file is edited.

| Placeholder | Filled with | Where it shows |
| --- | --- | --- |
| `__BOARD_TITLE__` | the board name | page title and heading |
| `__HUMAN_NAME__` | the person the board is for | the "Blocked on me" wait lines, who marked a daily line, the default "decided by" |
| `__RELAY_NAME__` | the relay role's name (the only writer of decisions) | banners, the "decided for you" tab, the daily highlights |
| `__ARCHITECT_NAME__` | the name of the role other roles ask for hard calls (SABHA roster: the Architect) | the Agents tab section and its flow chart |
| `__TIMEZONE__` | an IANA time zone, default `UTC` (for example `Europe/London`, `America/New_York`) | every displayed time, the hour chart, day boundaries, new-task ids |
| `__LANES__` | a JSON array of project names: board filter chips | `["Alpha", "Beta", "Other"]` |
| `__PROJECTS__` | a JSON array of project names: review groups and the add-task form | `["Alpha", "Beta", "Other"]` |

`__LANES__` and `__PROJECTS__` are written as bare JSON, quotes and brackets included. Keep `Other` last: rows whose
project is not in the list land in it, and unknown projects are appended after the listed ones.

The time zone offset is read once when the page loads, so a clock change inside the viewed day shifts that day by an
hour. Free text of the form `4 Nov approx 20:10 (...)` in `lastChange` is read in this zone, with the current year.

## Collections

| Collection | Page reads | Page writes | Relay writes |
| --- | --- | --- | --- |
| `queue` | board, timeline, "Do this next" | `set` for a new task; `update` for a move, priority or note | every task the human asks for; every state change |
| `review` | Review tab | `update` when the human picks an option | the questions for the human |
| `decisions` | Decisions tab | none | every decision, the same turn it is made |
| `activity` | feed, hour chart, agent cards | none | one row per event |
| `architect` | Agents tab: who asked, how it ended | none | one row per request to the architect role |
| `agents` | agent cards (name, task line) | none | the current task line per agent |
| `artifacts` | Artifacts tab (links) | none | one row per page or file made |
| `daily` | Daily work tab | `update` of `marked` only | one doc per day; append lines only |
| `device` | the device strip: doc `now`, doc `history` | none | at status checks |

A collection that is empty shows a short "nothing here yet" line, not an error. The device strip shows
"no sample yet" until the relay writes `device/now`.

## `queue` row

- `id`: free text; rows added on the page get `H-yyyymmdd-hhmm` plus two random characters (board time zone).
- `ask`, `asked`, `details`, `due` (date), `owner`, `brief`, `project` (one of the lanes), `lane`, `next`, `note`, `links`.
- `priority`: `P0` (now), `P1` (today), `P2` (this week), `P3` (later).
- `state`: `BLOCKED-HUMAN`, `READY`, `RUNNING`, `BLOCKED-OTHERS`, `DONE`; the first word counts, so a trailing
  note is allowed. `BLOCKED-<NAME>` (the human's name, upper-cased, non-letters as `-`) is read as `BLOCKED-HUMAN`,
  so rows written before the rename still sort.
- `column`: `blocked-me`, `ready`, `running`, `blocked-others`, `done`. It wins over `state`; the page writes both on a move.
- `lastChange` (text), `lastChangeAt` (ISO, UTC; the age on every card), `eta` (ISO), `etaBasis`, `effortH` (hours),
  `dependsOn` (ids; a review id means "released once that question is answered").
- `history`: array of `{at, by, byName, what}`; the last 50 are kept.
- `updatedAt`, `updatedBy`, `updatedByName`: stamped on every write.

Page rules: Done shows the last 24 hours; a "Blocked on me" row older than 2 hours is flagged aged; more than 2 rows in
Running raises the work-in-progress warning; order is priority, then oldest change.

## `review` row

`id`, `project`, `q`, `why`, `options` (each: `label`, `consequence`, `example`), `rec`, `default`, `state` (`open`,
then `ANSWERED` or `APPLIED`), `answer`, `source` (text; `Q-nnn` ids in it are released when the answer is saved).

## `decisions` row

`id`, `project`, `title`, `answer`, `why`, `rec` (`y` = the human picked the recommended option, `n` = another),
`by` (empty for the human; `<relay name>-s1` when the relay decided under a standing rule), `via` (bulk
decisions), `status` (`OPEN-APPLY`, `APPLIED`, `SUPERSEDED`), `ref`, `cited`, `citedCount`, `at` (ISO),
`atPrecision` (`day` when only the date is known), `source`, `statusBasis`.

## Other collections

- `activity`: `at` (ISO), `agent`, `kind` (`done`, `verdict`, `blocked`, `cancel`, `restart`, `nudge`, `ack`, or other), `project`, `ref`, `line`.
- `architect`: `ref`, `from`, `askedAt` (ISO), `state` (`done`, `cancelled`, `open`), `pushback` (true when the role flagged a conflict), `minutesToDone`, `project`, `title`.
- `agents`: `agent`, `task`, `statusMtime`.
- `artifacts`: `title`, `url` (shown as a link only when it is an `https` artifact URL), `kind`, `project`, `audience` (`shared: <who>` or empty), `status` (`superseded`), `supersededBy`, `note`, `createdAt`, `updatedAt`.
- `daily`: one doc per day with `date`, `projects` (each: `project`, `highlights`, `moved`, `blockers` as arrays of text), `tomorrow` (array of text), `marked` (array of `project|section|index` keys). Only append lines: the keys are positions, so reordering moves the human's highlights.
- `device`: doc `now` (`at` ISO, `cpuUserPct`, `cpuSysPct`, `cpuIdlePct`, `load1`, `load5`, `load15`, `cores`, `memTotalGB`, `memUsedGB`, `memFreePct`, `gpuPct`, `battPct`, `plugged`, `ssdFreeGB`, `ssdTotalGB`, `ssdUsedGB`, `note`); doc `history` (`samples`: array of the same numbers).

## Write rules

- Stamp every time from the real clock (`date -u +%Y-%m-%dT%H:%M:%SZ`), never a guess.
- Every `update` passes `if_version` with the version just read, so an edit the human made on the page is not overwritten. On a conflict, read again and redo the change.
- Read the human's edits from the page at every status check before writing.
- The relay is the only writer of decisions; a worker never writes the board.
- The page itself writes only new `queue` rows, `queue` moves, priority and notes, `review` answers, and `daily` marks.
- No secrets, tokens or personal data in any row. A row is visible to everyone the page is shared with.
