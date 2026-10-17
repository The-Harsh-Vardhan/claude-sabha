#!/usr/bin/env python3
"""Local tracker page (SABHA_TRACKER=html, the default): one offline HTML file from the tracker CSVs, no login.

  python3 tracker/build-html.py [CSV_DIR] [OUT.html]
CSV_DIR defaults to $SABHA_CSV_DIR, then the header-only templates; OUT defaults to CSV_DIR/tracker.html.
A missing CSV shows an empty tab. Every cell is escaped; the only script is the tab switcher.
"""
import csv
import html
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tabs


def table(path):
    try:
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))
    except OSError:
        return "<p>No file.</p>"
    if not rows:
        return "<p>No file.</p>"
    th = "".join("<th>%s</th>" % html.escape(h) for h in rows[0])
    body = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % html.escape(c) for c in r) for r in rows[1:])
    if not rows[1:]:
        body = '<tr><td colspan="%d" class="none">No rows yet.</td></tr>' % len(rows[0])
    return "<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (th, body)


def build(csv_dir, out):
    names = [(t, c) for t, c, _ in tabs.TABS]
    nav = "".join('<button data-t="t%d">%s (%d)</button>' % (i, html.escape(t), max(0, _count(csv_dir, c)))
                  for i, (t, c) in enumerate(names))
    secs = "".join('<section id="t%d"%s>%s</section>' % (i, "" if i == 0 else " hidden",
                                                         table(os.path.join(csv_dir, c)))
                   for i, (t, c) in enumerate(names))
    page = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Sabha tracker</title>
<style>
body{font:14px system-ui,sans-serif;margin:1rem;color:#222}
nav button{margin:0 .3rem .5rem 0;padding:.3rem .7rem;border:1px solid #888;background:#f4f4f4;cursor:pointer}
nav button.on{background:#d9e2f3;font-weight:bold}
table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:.25rem .5rem;text-align:left;vertical-align:top}
th{background:#d9e2f3;position:sticky;top:0}.none{color:#888}
</style></head><body><h1>Sabha tracker</h1><nav>%s</nav>%s
<script>
var b=document.querySelectorAll("nav button");function show(id){document.querySelectorAll("section").forEach(function(s){s.hidden=s.id!==id});b.forEach(function(x){x.className=x.dataset.t===id?"on":""})}
b.forEach(function(x){x.onclick=function(){show(x.dataset.t)}});show("t0");
</script></body></html>
""" % (nav, secs)
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)


def _count(csv_dir, name):
    try:
        with open(os.path.join(csv_dir, name), newline="", encoding="utf-8") as f:
            return sum(1 for _ in csv.reader(f)) - 1
    except OSError:
        return 0


if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("SABHA_CSV_DIR") or tabs.TEMPLATES
    o = sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "tracker.html")
    build(d, o)
    print("wrote", o)
