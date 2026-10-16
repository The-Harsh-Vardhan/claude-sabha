# Quickstart: a 10-minute demo

You will run one small job through the whole loop: you ask the relay, the relay briefs the dispatcher, the dispatcher
briefs a builder, a reviewer reads the diff, a session is restarted fresh from its handoff, and the board shows it all.
The job is trivial on purpose (create one file in a worktree); the loop is what you are testing.

Status: written to be followed literally, but not yet run end to end on a real herdr with a real Claude. Steps 1-3 and
the mechanical equivalent of steps 4-7 (the shipped scripts) have been run only against a fake herdr and fake agents;
a real herdr was exercised for the server start, workspace and session calls only, not for starting agents or panes
(see [known-gaps.md](known-gaps.md)). Steps 4-7 as written need a real Claude.
Treat any step that fails as a bug in this page and report it. Windows is beta ([windows.md](windows.md)).

You need: `claude` on your PATH and logged in, `git`, `python3`, `jq`, and `herdr` (`brew install herdr`). Step 2 (`sabha doctor`)
checks all five: a missing `claude`, `git`, `python3` or `jq` is a FAIL, a missing `herdr` a warning. Run every command from a plain terminal, not from inside a Claude session (a Claude sandbox blocks the
terminal automation the launcher uses). All commands start in the sabha repository.

## 1. Write the config (1 minute)

The demo workspace is `$HOME/sabha-demo`; change the path if you like, but keep it the same in every step.

```
mkdir -p "$HOME/sabha-demo/repo"
git -C "$HOME/sabha-demo/repo" init
git -C "$HOME/sabha-demo/repo" commit --allow-empty -m "init"
cp -R template/impl "$HOME/sabha-demo/impl"
cd "$HOME/sabha-demo/impl"
mkdir -p inbox/Vidur inbox/Yudhishthira inbox/Bhima inbox/Arjun inbox/Sahadev inbox/Nakul status/context status/.bak questions
cd -
bin/sabha init --plan pro --tracker html --push off --ws "$HOME/sabha-demo" --impl "$HOME/sabha-demo/impl"
printf 'SABHA_PROTOCOL_CORE=PROTOCOL-core.md\nSABHA_ROLE_DIR=protocol\n' >> sabha.conf
```

Expected: `wrote .../sabha.conf (plan pro, tracker html, push off, os ..., CLIs: ...)`. The two `SABHA_` lines make every
role read the generic `PROTOCOL-core.md` and its own `protocol/<Name>.md`.

## 2. Check the machine (30 seconds)

```
bin/sabha doctor
```

Fix every line that starts with FAIL (a warning does not stop the demo). Doctor tells you if the statusline hook is
missing: set `statusLine.command` in your Claude settings to `bash <this repo>/bin/statusline-sabha.sh`, because the
context percent, the restart rule and the usage alerts all read what that hook writes.

## 3. Start the grid (1 minute)

```
bin/sabha-up.sh --plan pro
```

herdr opens a workspace with one pane each for Vidur (the relay, the session you talk to), Yudhishthira, Bhima,
Arjun and Nakul. Then start the reviewer, which has no pane on the Pro plan: `bin/sabha-up.sh Sahadev` (or print its
line with `bin/sabha-up.sh --print Sahadev` and run it where you like).

If it stops with `already running` because a claude session holds one of those names (for example a real sabha on
the same machine), stop that one first; `--force` skips the check and is only for a machine you know is clear.

Expected: each pane greets with its name, reads `PROTOCOL-core.md` and its own card, and checks its inbox.

## 4. Brief to worker (3 minutes)

Paste this into the Vidur session (it is a chat prompt for Claude, not a shell command):

```
Demo job. In the git repository at ~/sabha-demo/repo, Arjun creates a file hello.txt that holds one line, "hello from sabha", in a worktree named repo--hello, and stages it. Then Sahadev reviews the diff. Nothing is committed in the main checkout and nothing is pushed. Brief Yudhishthira.
```

Check each hop from a second terminal (the number is the next free one, usually 001):

```
ls "$HOME/sabha-demo/impl/inbox/Yudhishthira"
ls "$HOME/sabha-demo/impl/inbox/Arjun"
```

Expected within a minute or two: `001.claim`, `001-vidur-<slug>.md` and `001.ack` under Yudhishthira; then a brief,
an ack and, when Arjun finishes, a `.done` under Arjun. Read the done: `cat "$HOME/sabha-demo/impl/inbox/Arjun/001.done"`
(the first brief to Arjun may carry another number). `git -C "$HOME/sabha-demo/repo" worktree list` shows
`repo--hello`, and `cat "$HOME/sabha-demo/repo--hello/hello.txt"` prints the line.

## 5. Review (2 minutes)

The dispatcher briefs Sahadev with the `.done`. Expected: a file `questions/<topic>-review.md` in the demo impl whose
first line is `verdict: ACCEPT` (or `verdict: BREAK <n>` with a finding). If it is BREAK, the builder answers in
`questions/<topic>-review-answer.md` and the dispatcher asks for a new verdict. Check:

```
head -3 "$HOME/sabha-demo/impl/questions/"*-review.md
```

## 6. Handoff and restart (2 minutes)

A session restarts fresh from its handoff; this is the part that keeps contexts small. Paste into the Arjun pane:

```
Save your handoff in status/arjun.md now, in the handoff shape, then stop.
```

Check that the top of `status/arjun.md` holds a `Current:` or `Idle:` line followed by `Task:`, `Done:`, `Next:`:

```
head -8 "$HOME/sabha-demo/impl/status/arjun.md"
```

Then exit the Arjun session (type `/exit` in its pane) and start it again with the same opening prompt:

```
bin/sabha-up.sh Arjun
```

Expected: the new Arjun reads its card and `status/arjun.md`, says what it was doing and what is next, and does not
redo the finished brief. Never use `--resume`: it would bring back the full context and defeat the restart.
In normal use `bin/sabha-loop <Name>` does this for you at 30 percent context once the handoff is newer than the last
start (see the README, "Restart loop"); this demo does it by hand so you see the mechanism. The automatic path is
exercised in `tests/test-loop.sh` (a fake agent at 35 percent context restarts once the handoff is newer).

## 7. Look at the board (1 minute)

```
bin/sabha-for-me
bin/sabha-watch
```

`FOR-ME.md` and `FOR-ME.html` appear in `$HOME/sabha-demo/impl`. Expected: the Agents table shows each role's state,
the goal "Say hello from a worktree" with its steps, and your open items (the sample items from the template are
there: answer the sample question to see the "Copy answer" button). `sabha-watch` prints each role's context
percent and any brief nobody has acked.

## Done when

- `hello.txt` exists in the `repo--hello` worktree and nothing is committed or pushed in `repo`.
- The brief chain has `.claim`, brief, `.ack`, `.done` at both hops.
- A review file starts with `verdict: ACCEPT`.
- A restarted Arjun continues from `status/arjun.md` without redoing the work.
- The board lists the agents, the goal and the open items.

Clean up when you are finished: close the herdr workspace and remove `$HOME/sabha-demo` yourself (nothing in sabha
deletes it for you).
