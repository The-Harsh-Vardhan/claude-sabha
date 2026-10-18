---
title: How it works
nav_order: 2.5
---

# How it works, in five pictures

Every arrow below is a file on disk or a script in `bin/`. Nothing is hidden in a model's memory: if a session
dies, the next one reads the same files and carries on. Role names are the default ids; a [theme](themes.md) renames
them on screen.

## 1. One brief, end to end

You talk to the relay only. Work moves as numbered files in each role's inbox: a brief, then an `.ack` when a worker
claims it, then a `.done` with the result. A `.cancel` stops it.

```mermaid
sequenceDiagram
    actor You
    participant R as Relay (Vidur)
    participant D as Dispatcher (Yudhishthira)
    participant B as Builder (Bhima)
    participant G as Reviewer and critics
    You->>R: "add CSV export"
    R->>D: inbox/Yudhishthira/007-vidur-csv-export.md
    D->>B: inbox/Bhima/012-yudhishthira-csv-export.md
    B-->>D: 012.ack, then work in a worktree
    B->>G: 012.done names the diff
    G-->>B: questions/csv-review.md, csv-be.md, ...
    B-->>G: csv-be-answer.md (REFUTED / FIXED)
    G-->>D: verdict: ACCEPT, no open BREAK
    D->>R: report: ready to fold
    R->>You: one line + an item in FOR-ME.md
    You->>R: "go"
    R->>D: brief with go: fold repo sha
```

## 2. Fresh context instead of a full one

`bin/sabha-loop` runs in each pane. When a role's context reaches the limit (30 percent by default) and it has
written a fresh handoff to `status/<name>.md`, the loop quits the session and starts a new one with the same opening
prompt. The new session reads the handoff and the open briefs, never `--resume`.

```mermaid
stateDiagram-v2
    [*] --> Running: sabha-up.sh Name
    Running --> Running: context below limit
    Running --> Stale: context file older than 120 s
    Stale --> Running: fresh reading arrives
    Running --> Handoff: context at or over limit
    Handoff --> Running: handoff not newer than last start (wait)
    Handoff --> Restart: status/name.md written after last start
    Restart --> Running: two Ctrl-C, then a fresh session
    Running --> Stopped: two quick exits in a row, or sabha-loop --stop
    Stopped --> [*]
```

## 3. The gate before anything irreversible

A fold, push, PR, tag, release or migration needs a `go:` line in the newest brief, and every verdict file the brief's
`gate:` line names must pass. `bin/sabha-gate` turns that rule into an exit code.

```mermaid
flowchart TD
    A[Brief with go: and gate:] --> B{".cancel or a newer brief<br>on the same target?"}
    B -- yes --> X[Do nothing, add a for-me item]
    B -- no --> C{"*-review.md says<br>verdict: ACCEPT?"}
    C -- no --> X
    C -- yes --> D{"Each critic file:<br>NO BREAK?"}
    D -- yes --> OK[Gate open: do the step]
    D -- "BREAK n / BLOCK n" --> E{"answer file newer than verdict<br>with n REFUTED or FIXED lines?"}
    E -- yes --> OK
    E -- no --> X
```

## 4. Who may reach outside the machine

Three layers, each catching what the one above misses. Details and known gaps: [SECURITY.md](https://github.com/The-Harsh-Vardhan/claude-sabha/blob/main/SECURITY.md).

```mermaid
flowchart LR
    W[Worker runs a command] --> G{"Guard hook:<br>push, gh write, remote change,<br>webhook post?"}
    G -- "yes, not the relay" --> N1[Blocked: write a brief to the relay]
    G -- no --> P{"git pre-push hook:<br>SABHA_ROLE set and not the relay?"}
    P -- yes --> N2[Push refused]
    P -- no --> T{"GitHub token<br>in the environment?"}
    T -- "no (stripped for workers)" --> N3[gh write has nothing to sign in with]
    T -- yes --> H[Only the human or the relay gets here]
```

## 5. Where everything lives

```mermaid
flowchart TB
    subgraph WS["Workspace (SABHA_WS)"]
        CONF[sabha.conf + plan file]
        subgraph IMPL["Project folder (SABHA_IMPL)"]
            PC[PROTOCOL-core.md + protocol/ role cards]
            IN["inbox/Name/ : NNN-from-slug.md, .ack, .done, .cancel"]
            ST["status/name.md : the handoff<br>status/context/ : context percent"]
            Q["questions/ : verdicts and answers"]
            FM["for-me.items to FOR-ME.md board"]
            REC["ARCHITECTURE.md, DECISIONS.md, LESSONS.md, GOALS.md"]
        end
    end
    REPO["Your repository"] --> WT["repo--slug worktrees<br>(sabha-worktree create)"]
    IN -. briefs name .-> WT
```

Next: the [Roster](roster.md) shows all 20 roles side by side in every theme.
