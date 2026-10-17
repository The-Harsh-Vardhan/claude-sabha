#!/usr/bin/env python3
# Why: one row per checkout (main + worktrees) of every repo you work with, read-only; feeds the Repos tab.
# Env: WS     workspace root (required)
#      REPOS  space-separated name:path:base (path relative to WS or absolute; base defaults to main)
#      ORG    GitHub org or user for the PR column via gh (empty = no PR lookups)
#      OUT    output CSV (default ./repos.csv)
# Run: WS=~/work REPOS="api:api:main web:web:develop" ORG=my-org python3 tracker/repos-export.py
import csv, json, os, re, subprocess, sys

WS = os.environ.get("WS")
REPOS = os.environ.get("REPOS", "")
ORG = os.environ.get("ORG", "")
OUT = os.environ.get("OUT", "repos.csv")
if not WS or not REPOS.strip():
    sys.exit("set WS and REPOS (name:path:base ...); see the header of this file")
WS = os.path.expanduser(WS)
COLS = ["Repo", "Kind", "Path", "Branch", "Base", "Head", "Last commit", "Ahead of base",
        "Behind base", "Dirty files", "Untracked", "Upstream", "Unpushed commits", "Feature", "PR"]


def run(args, cwd=None, t=20):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=t)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None


def git(d, *a):
    return run(["git", "-C", d] + list(a))


repos = []
for item in REPOS.split():
    name, _, rest = item.partition(":")
    path, _, base = rest.partition(":")
    repos.append((name, path if os.path.isabs(path) else os.path.join(WS, path), base or "main"))

gh_ok = [None]


def pr_for(repo, branch):
    if not ORG:
        return ""
    out = run(["gh", "pr", "list", "-R", ORG + "/" + repo, "--head", branch, "--state", "all",
               "--json", "number,state,url"], t=20)
    if out is None:
        gh_ok[0] = gh_ok[0] or False
        return ""
    gh_ok[0] = True
    try:
        return "; ".join(f"#{x['number']} {x['state']} {x['url']}" for x in json.loads(out))
    except Exception:
        return ""


def feature(path, branch, is_main):
    if is_main:
        return ""
    m = re.search(r"--(.+)$", os.path.basename(path))
    if m:
        return m.group(1)
    return re.sub(r"^(feat|feature|fix)/", "", branch) if branch else ""


rows = []
for repo, d, base in repos:
    if not os.path.isdir(d):
        continue
    wt = git(d, "worktree", "list", "--porcelain")
    if not wt:
        continue
    cks = []
    for blk in wt.split("\n\n"):
        path, br = None, None
        for l in blk.splitlines():
            if l.startswith("worktree "):
                path = l[9:]
            elif l.startswith("branch "):
                br = l[7:].replace("refs/heads/", "")
        if path:
            cks.append((path, br))
    bref = next((r for r in ("origin/" + base, base)
                 if git(d, "rev-parse", "--verify", "-q", "refs/remotes/" + r if r.startswith("origin/") else "refs/heads/" + r)), None)
    grp = []
    for i, (path, br) in enumerate(cks):
        head = git(path, "rev-parse", "--short", "HEAD") or ""
        branch = br or f"detached @ {head}"
        log = git(path, "log", "-1", "--format=%cs|%ct|%s") or "||"
        date, ts, subj = (log.split("|", 2) + ["", ""])[:3]
        last = f"{date} {subj}"[:70]
        ahead = behind = ""
        if bref:
            lr = git(path, "rev-list", "--left-right", "--count", f"{bref}...HEAD")
            if lr:
                behind, ahead = lr.split()
        st = git(path, "status", "--porcelain") or ""
        sl = st.splitlines()
        untr = sum(1 for x in sl if x.startswith("??"))
        up = git(path, "rev-parse", "--abbrev-ref", "@{upstream}") if br else None
        unp = ""
        if br:
            unp = git(path, "rev-list", "--count", "@{upstream}..HEAD") if up else "n/a"
        rel = os.path.relpath(path, WS) if path.startswith(WS + "/") else path
        pr = pr_for(repo, br) if br and br != base else ""
        grp.append((i == 0, -int(ts or 0), [repo, "main" if i == 0 else "worktree", rel, branch, base, head,
                    last, ahead, behind, len(sl) - untr, untr, up or ("none" if br else ""), unp,
                    feature(path, br, i == 0), pr]))
    grp.sort(key=lambda g: (not g[0], g[1]))
    rows += [g[2] for g in grp]

with open(OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(COLS)
    w.writerows(rows)

dirty = sum(1 for r in rows if r[9] or r[10])
unp = sum(1 for r in rows if r[11] == "none" or (str(r[12]).isdigit() and int(r[12]) > 0))
det = sum(1 for r in rows if r[3].startswith("detached"))
print(f"checkouts={len(rows)} dirty={dirty} unpushed_or_never_pushed={unp} detached={det} gh_ok={gh_ok[0]}")
if gh_ok[0] is not True:
    print("note: gh unavailable (blocked or failed); PR column blank", file=sys.stderr)
