"""One column list for every tracker script: tab name, template CSV, data range written by sheet-sync.

Tab names: Tasks, Progress, Agents, Repos, Agent inboxes, Decisions, Inbox, Dashboard (8). The CSV headers in
templates/ are the single source of the column letters; the ranges below are derived from them.
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATES = os.path.join(HERE, "templates")

# (tab, csv file, extra columns that only the human writes, after the CSV columns)
TABS = [
    ("Tasks", "tracker.csv", ["Your note"]),
    ("Progress", "progress.csv", []),
    ("Agents", "agents.csv", ["Your note", "Your ask"]),
    ("Repos", "repos.csv", []),
    ("Agent inboxes", "inbox.csv", []),
    ("Decisions", "for-me.csv", []),
]

# Human -> agents form. Written by the human, read by the agents; no CSV feeds it.
INBOX_HEADERS = ["ID", "Created", "Type", "About", "Message", "Priority", "Status", "Picked up by", "Note",
                 "Picked up (UTC)"]

PRIORITIES = ["P0", "P1", "P2", "P3"]
STATUSES = ["Not started", "In progress", "Waiting", "Waiting on others", "Committed", "Pushed", "Done"]


def header(csv_name):
    with open(os.path.join(TEMPLATES, csv_name), newline="", encoding="ascii") as f:
        return next(csv.reader(f))


def col(n):
    """1 -> A, 27 -> AA"""
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def data_range(tab, csv_name):
    """A2:K for Tasks: header row kept, data from row 2, as many columns as the CSV has."""
    return "%s!A2:%s" % (quote(tab), col(len(header(csv_name))))


def quote(tab):
    return "'%s'" % tab if " " in tab else tab
