#!/usr/bin/env python3
"""Turn a questions markdown file into ONE self-contained HTML questionnaire.

Usage: python3 build.py <questions.md> <out.html>
Stdlib only. Format is documented in SKILL.md (header: title, for:, context:;
sections: "## Q<n> - <id>: <title>" with Source/What it is/Example/options).
"""
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
Q_HEAD = re.compile(r"^## Q(\d+)\b\s*-?\s*(.*)$")
OPT = re.compile(r"^-\s+([A-Z])(\s*\((?:recommended)\))?\s*:\s*(.*)$", re.I)
SRC = re.compile(r"^(?:Source|Specs?):\s*(.*)$")
WHAT = re.compile(r"^What it is:\s*(.*)$")
EXAM = re.compile(r"^Example:\s*(.*)$")
ANS = re.compile(r"^Answer:\s*(.*)$")
DEC = re.compile(r"^Decision:\s*(.*)$")
LINKS = re.compile(r"^Links?:\s*(.*)$")


class BuildError(Exception):
    pass


def esc(text):
    """HTML-escape, then turn `code` spans into <code>."""
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text, quote=True))


def parse(lines):
    title, who, context = "", "", ""
    items = []  # ordered: ("q", dict) or ("note", {"title", "paras"})
    cur_item, field = None, None
    for no, raw in enumerate(lines, 1):
        line = raw.rstrip()
        s = line.strip()
        if line.startswith("# ") and not title:
            title = s[2:].strip()
            continue
        if line.startswith("## "):
            m = Q_HEAD.match(line)
            if m:
                head = m.group(2).strip()
                if ": " in head:
                    qid, qtitle = (p.strip() for p in head.split(": ", 1))
                else:
                    qid, qtitle = "Q" + m.group(1), head
                cur_item = ("q", {"n": int(m.group(1)), "id": qid or "Q" + m.group(1),
                                  "title": qtitle, "line": no, "source": "", "what": "",
                                  "example": "", "extras": [], "opts": [], "answer": "", "links": []})
            else:
                cur_item = ("note", {"title": s[3:].strip(), "paras": [[]], "line": no})
            items.append(cur_item)
            field = None
            continue
        if cur_item is None:
            if re.match(r"^for:", s, re.I):
                who = s.split(":", 1)[1].strip()
            elif re.match(r"^context:", s, re.I):
                context = s.split(":", 1)[1].strip()
            continue
        kind, d = cur_item
        if kind == "note":
            if not s:
                if d["paras"][-1]:
                    d["paras"].append([])
            else:
                d["paras"][-1].append(s)
            continue
        if not s:
            field = None
            continue
        m = None
        for name, rx in (("source", SRC), ("what", WHAT), ("example", EXAM)):
            m = rx.match(s)
            if m:
                d[name] = m.group(1).strip()
                field = name
                break
        if m:
            continue
        m = LINKS.match(s)
        if m:
            d["links"] += [u for u in re.split(r"[\s,]+", m.group(1)) if u]
            field = None
            continue
        m = OPT.match(s)
        if m:
            d["opts"].append({"letter": m.group(1).upper(), "rec": bool(m.group(2)),
                              "text": m.group(3).strip(), "line": no})
            field = "opt"
            continue
        m = ANS.match(s)
        if m:
            d["answer"] = m.group(1).strip()
            field = None
            continue
        if DEC.match(s):
            field = None
            continue
        if field == "opt":
            d["opts"][-1]["text"] += " " + s
        elif field in ("source", "what", "example"):
            d[field] += " " + s
        elif field == "extra":
            d["extras"][-1] += " " + s
        else:
            d["extras"].append(s)
            field = "extra"
    return title, who, context, items


def validate(items):
    seen = set()
    qs = [d for k, d in items if k == "q"]
    if not qs:
        raise BuildError("no questions found (expected '## Q1 - id: title' sections)")
    for q in qs:
        where = "%s (Q%d, line %d)" % (q["id"], q["n"], q["line"])
        if q["n"] in seen:
            raise BuildError("%s: duplicate question number Q%d" % (where, q["n"]))
        seen.add(q["n"])
        if len(q["opts"]) < 2:
            raise BuildError("%s: needs at least 2 options, found %d" % (where, len(q["opts"])))
        letters = [o["letter"] for o in q["opts"]]
        if len(set(letters)) != len(letters):
            raise BuildError("%s: duplicate option letters %s" % (where, "".join(letters)))
        recs = [o for o in q["opts"] if o["rec"]]
        if len(recs) != 1:
            raise BuildError("%s: needs exactly 1 option marked (recommended), found %d%s" % (
                where, len(recs), "" if not recs else " (lines %s)" % ", ".join(str(o["line"]) for o in recs)))
        q["rec"] = recs[0]["letter"]
        a = q["answer"]
        q["pre"] = {"k": "", "o": ""}
        if a:
            m = re.match(r"^other\s*:\s*(.*)$", a, re.I)
            if m:
                q["pre"] = {"k": "O", "o": m.group(1).strip()}
            else:
                m = re.match(r"^([A-Z])\b", a)
                if not m or m.group(1) not in letters:
                    raise BuildError("%s: Answer '%s' is not one of %s or 'Other: text'" % (where, a, "".join(letters)))
                q["pre"] = {"k": m.group(1), "o": ""}
    return qs


def slugify(title):
    s = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:40].strip("-")
    return s or "questions"


def page_title(title):
    seg = re.split(r"\s+[-:]\s+|:\s", title)[0]
    words = seg.split()
    if len(words) < 2:
        words = title.split()
    return " ".join(words[:4]).strip(" ,;:-") or "Questionnaire"


def link_label(url):
    """Jira key for a /browse/ link, org/repo (+ #n) for GitHub, else the URL."""
    m = re.search(r"/browse/([A-Z][A-Z0-9]+-\d+)", url)
    if m:
        return "Jira " + m.group(1)
    m = re.search(r"github\.com/([^/\s]+/[^/\s#?]+)(?:/(?:pull|issues)/(\d+))?", url)
    if m:
        return "GitHub " + m.group(1) + ("#" + m.group(2) if m.group(2) else "")
    return url


def card_html(q):
    n = q["n"]
    out = ['<article class="card" id="q%d" data-n="%d">' % (n, n),
           '<div class="qhead"><span class="qnum">Q%d</span> <span class="qid">%s</span></div>' % (n, esc(q["id"])),
           "<h3>%s</h3>" % esc(q["title"])]
    if q["links"]:
        out.append('<p class="links">%s</p>' % " ".join(
            '<a class="chip" href="%s" target="_blank" rel="noopener">%s</a>' % (html.escape(u, quote=True), esc(link_label(u)))
            for u in q["links"]))
    if q["source"]:
        out.append('<p class="src"><span class="label">Source</span> %s</p>' % esc(q["source"]))
    if q["what"]:
        out.append('<p><span class="label">What it is</span><br>%s</p>' % esc(q["what"]))
    if q["example"]:
        out.append('<div class="example"><span class="label">Example</span><br>%s</div>' % esc(q["example"]))
    for p in q["extras"]:
        out.append("<p>%s</p>" % esc(p))
    out.append('<fieldset class="opts"><legend class="label">Options</legend>')
    for o in q["opts"]:
        text, ex = o["text"], ""
        if " Example: " in text:
            text, ex = text.split(" Example: ", 1)
        elif text.startswith("Example: "):
            text, ex = "", text[9:]
        badge = '<span class="rec">Recommended</span>' if o["rec"] else ""
        chk = " checked" if q["pre"]["k"] == o["letter"] else ""
        out.append('<label class="opt"><input type="radio" name="q%d" value="%s"%s>'
                   '<span class="body"><span class="t"><b>%s.</b> %s%s</span>%s</span></label>' % (
                       n, o["letter"], chk, o["letter"], esc(text.strip()), badge,
                       '<span class="e">Example: %s</span>' % esc(ex.strip()) if ex else ""))
    chk = " checked" if q["pre"]["k"] == "O" else ""
    out.append('<label class="opt"><input type="radio" name="q%d" value="O"%s>'
               '<span class="body"><span class="t"><b>Other</b></span></span></label>' % (n, chk))
    out.append('<input type="text" class="other" aria-label="Your own answer for Q%d" '
               'placeholder="Your own answer" value="%s"%s>' % (
                   n, esc(q["pre"]["o"]), "" if chk else " hidden"))
    out.append("</fieldset>")
    out.append('<div class="row"><button type="button" class="ghost take" data-rec="%s">'
               "Take recommendation (%s)</button></div>" % (q["rec"], q["rec"]))
    out.append('<label class="note"><span class="label">Note (optional)</span>'
               '<textarea rows="2" aria-label="Note for Q%d"></textarea></label>' % n)
    out.append("</article>")
    return "\n".join(out)


def main(argv):
    if len(argv) != 3:
        print("usage: python3 build.py <questions.md> <out.html>", file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    if os.path.exists(dst):
        print("refusing to overwrite existing %s (pick a new versioned name)" % dst, file=sys.stderr)
        return 1
    try:
        with open(src, encoding="utf-8") as f:
            title, who, context, items = parse(f.read().splitlines())
        if not title:
            raise BuildError("missing '# <title>' line")
        qs = validate(items)
    except (BuildError, OSError) as e:
        print("build.py: %s" % e, file=sys.stderr)
        return 1
    cards = []
    for kind, d in items:
        if kind == "q":
            cards.append(card_html(d))
        else:
            paras = "".join("<p>%s</p>" % esc(" ".join(p)) for p in d["paras"] if p)
            cards.append('<aside class="card notecard"><h3>%s</h3>%s</aside>' % (esc(d["title"]), paras))
    meta = []
    if who:
        meta.append('<p class="lead"><span class="label">For</span> %s</p>' % esc(who))
    if context:
        meta.append('<p class="lead">%s</p>' % esc(context))
    slug = slugify(title)
    data = {"slug": slug, "title": title,
            "who": who, "context": context,
            "qs": [{"n": q["n"], "id": q["id"], "rec": q["rec"], "title": q["title"],
                    "what": q["what"], "example": q["example"], "source": q["source"], "links": q["links"],
                    "letters": [o["letter"] for o in q["opts"]],
                    "opts": [{"letter": o["letter"], "rec": o["rec"], "text": o["text"]} for o in q["opts"]]}
                   for q in qs]}
    blob = json.dumps(data).replace("</", "<\\/")
    with open(os.path.join(HERE, "template.html"), encoding="utf-8") as f:
        page = f.read()
    for k, v in (("{{PAGE_TITLE}}", html.escape(page_title(title))), ("{{TITLE}}", esc(title)),
                 ("{{META}}", "\n".join(meta)), ("{{CARDS}}", "\n".join(cards)), ("{{DATA}}", blob)):
        page = page.replace(k, v)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(page)
    print("wrote %s: %d questions, %d with recommendation" % (dst, len(qs), len(qs)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
