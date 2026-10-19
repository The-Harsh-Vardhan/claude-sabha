# Goals

`bin/sabha-for-me` reads this file. One heading per goal; every tag is optional and may come in any order:

    ## <goal title> [P0|P1|P2] (owner: BuilderPrecise; helpers: BuilderHeavy, Reviewer) {state: active|paused|done}

A missing priority means P2, a missing owner "unassigned", a missing state active (done once every box is ticked).
Steps are checkboxes, `- [x] done` or `- [ ] open`; a step may end with `@Name` to name the agent doing it. The board
shows one column per priority (P0 Now, P1 Next, P2 Later) and folds paused and done goals.

## Say hello from a worktree [P1] (owner: BuilderPrecise; helpers: Reviewer) {state: active}

- [ ] BuilderPrecise creates `hello.txt` in a worktree with one line @BuilderPrecise
- [ ] Reviewer reviews the diff and writes a verdict @Reviewer
- [ ] The user folds it into the main checkout and commits
