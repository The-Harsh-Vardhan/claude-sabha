#!/usr/bin/env python3
"""Build a status review page (HTML) from a JSON spec. Stdlib only.

Usage: python3 build_page.py spec.json out.html
Spec shape: see SKILL.md. Image paths in the spec are the paths the page
references (publish them with the Artifact tool's `files` map).
"""
import html, json, sys

CSS = """
:root{--bg:#f7f8fa;--panel:#fff;--fg:#1b2230;--muted:#5d6779;--line:#e2e6ee;--accent:#2f5bd3;
--ok:#1f7a4a;--ok-bg:#e3f4ea;--warn:#9a5b00;--warn-bg:#fdf1dc;--bad:#b4232c;--bad-bg:#fbe5e6;--info:#2f5bd3;--info-bg:#e6edfc;--gray-bg:#eceff4;
--before:#a2412f;--before-bg:#fbe9e5;--after:#1f6f5c;--after-bg:#e2f3ed;
--display:"Space Grotesk",system-ui,sans-serif;--body:"Inter",system-ui,sans-serif}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#11151c;--panel:#181d26;--fg:#e6e9ef;--muted:#9aa3b2;--line:#2a313d;--accent:#7ea0ff;--ok:#6fd39b;--ok-bg:#16301f;--warn:#f0b65a;--warn-bg:#3a2a10;--bad:#ff8a90;--bad-bg:#3a1a1d;--info:#8fb0ff;--info-bg:#1a2645;--gray-bg:#232a35;--before:#ff9b86;--before-bg:#3a1f19;--after:#7fe0bf;--after-bg:#163027;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#11151c;--panel:#181d26;--fg:#e6e9ef;--muted:#9aa3b2;--line:#2a313d;--accent:#7ea0ff;--ok:#6fd39b;--ok-bg:#16301f;--warn:#f0b65a;--warn-bg:#3a2a10;--bad:#ff8a90;--bad-bg:#3a1a1d;--info:#8fb0ff;--info-bg:#1a2645;--gray-bg:#232a35;--before:#ff9b86;--before-bg:#3a1f19;--after:#7fe0bf;--after-bg:#163027;color-scheme:dark}
body{background:var(--bg);color:var(--fg);font-family:var(--body);font-size:14px;line-height:1.5}
.wrap{max-width:1400px;margin:0 auto;padding-block:28px 56px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:grid;gap:22px}
h1,h2,h3{font-family:var(--display);text-wrap:balance;margin:0}h1{font-size:26px}h2{font-size:19px;margin-top:10px}
h3{font-size:16px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.sub,.note{color:var(--muted);margin:2px 0 0;max-width:85ch;font-size:13px}
a{color:var(--accent)}
.strip,.toc{display:flex;flex-wrap:wrap;gap:10px}.toc{gap:6px 16px;font-size:13px}
.stat{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 14px;min-width:120px}
.stat b{display:block;font-family:var(--display);font-size:22px}.stat span{color:var(--muted);font-size:12px}
.scroll,.tw{overflow-x:auto;background:var(--panel);border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%}.scroll table{min-width:760px}.tw table{min-width:1080px}.tw td,.tw th{width:16%}
.legend{list-style:none;margin:0;padding:0;display:grid;gap:6px;font-size:13px}.legend .pill{min-width:150px;text-align:center;margin-right:8px}
.review{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px}
.review .card h3{font-size:15px}.review ul{margin:0;padding-left:18px;display:grid;gap:5px;font-size:13px}
th,td{text-align:left;vertical-align:top;padding:8px 10px;border-bottom:1px solid var(--line);font-size:13px}
th{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);background:var(--gray-bg)}
tr:last-child td{border-bottom:0}
td.n{color:var(--muted);text-align:right}td.feat{white-space:nowrap;font-weight:500}td.k{white-space:nowrap;font-weight:600}
.pill{display:inline-block;font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px;white-space:nowrap}
.p-highest{background:var(--bad-bg);color:var(--bad)}.p-high{background:var(--warn-bg);color:var(--warn)}.p-medium,.p-low{background:var(--gray-bg);color:var(--muted)}
.s-ok{background:var(--ok-bg);color:var(--ok)}.s-push,.s-ready{background:var(--info-bg);color:var(--info)}.s-block{background:var(--warn-bg);color:var(--warn)}.s-send,.s-back{background:var(--gray-bg);color:var(--fg)}
.meta{font-size:12px;color:var(--muted);font-family:var(--body);font-weight:400}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 18px;display:grid;gap:12px}
.side{margin:0;font-size:13px}.side b{color:var(--fg)}
.verify{border:1px solid var(--line);border-left:3px solid var(--accent);border-radius:6px;padding:8px 12px;background:var(--bg);font-size:13px}
.verify summary{cursor:pointer;font-weight:600}.verify ol{margin:6px 0 0;padding-left:20px;display:grid;gap:3px}
.ba{display:grid;grid-template-columns:1fr 1fr;column-gap:28px;row-gap:14px;align-items:start;background:linear-gradient(var(--fg),var(--fg)) center top/2px 100% no-repeat}
.head{font-family:var(--display);font-weight:600;font-size:.9rem;padding:5px 10px;border-radius:6px;text-align:center}
.head.b{background:var(--before-bg);color:var(--before)}.head.a{background:var(--after-bg);color:var(--after)}
figure{margin:0;display:grid;gap:5px;min-width:0}.frame{border:1px solid var(--line);border-radius:6px;background:var(--bg);overflow:hidden}
.frame{position:relative}
.frame img{display:block;width:100%;height:auto;cursor:zoom-in}
.bx{position:absolute;border:2.5px solid;border-radius:4px;pointer-events:none;box-shadow:0 0 0 1px rgba(255,255,255,.7)}
.bx-b{border-color:#e0402a}.bx-a{border-color:#16a34a}
.bx em{position:absolute;left:-2px;bottom:100%;margin-bottom:2px;font:600 11px/1.3 var(--body);font-style:normal;color:#fff;padding:1px 6px;border-radius:3px;white-space:nowrap;max-width:min(260px,90vw);overflow:hidden;text-overflow:ellipsis}
.bx-b em{background:#e0402a}.bx-a em{background:#16a34a}
.bx.flip em{bottom:auto;top:100%;margin:2px 0 0}
#lb .lbf{position:relative;display:inline-block}
.boxes-off .bx{display:none}
.boxbar{display:flex;gap:8px;align-items:center;font-size:13px}
.frame img:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
#lb{border:0;padding:0;max-width:100vw;max-height:100vh;width:100vw;height:100vh;background:rgba(10,12,16,.92);color:#fff}
#lb[open]{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px}
#lb::backdrop{background:rgba(10,12,16,.92)}
#lbi{max-width:96vw;max-height:88vh;object-fit:contain;cursor:zoom-out;background:#fff}
#lbc{margin:0;font-size:13px;color:#d6dae2;padding-inline:16px;text-align:center}
#lbx{position:fixed;top:max(12px,env(safe-area-inset-top,0px));right:max(12px,env(safe-area-inset-right,0px));font:inherit;font-weight:600;padding:6px 12px;border-radius:6px;border:1px solid #fff;background:transparent;color:#fff;cursor:pointer}figcaption{font-size:12px;color:var(--muted)}
.none{border:1px dashed var(--line);border-radius:6px;color:var(--muted);font-size:12px;padding:14px;text-align:center;align-self:stretch;display:flex;align-items:center;justify-content:center}
"""
COLS = [("asked", "What was asked"), ("cause", "Why it failed earlier / design deviation"), ("todo", "What we had to do"), ("did", "What we did"),
        ("now", "Current state"), ("next", "Next (owner)")]


def e(x):  # spec text may carry simple inline HTML (links); keep it, escape nothing else
    return x or ""


def boxes_html(boxes, side):
    # Boxes are in percent of the image, so they scale with it at any width.
    return "".join(
        f'<span class="bx bx-{side}" style="left:{b["x"]}%;top:{b["y"]}%;width:{b["w"]}%;height:{b["h"]}%">'
        f'<em>{html.escape(b.get("label", ""))}</em></span>' for b in boxes or [])


def cell(img, cap, boxes=None, side="a"):
    if not img:
        return f'<div class="none">{html.escape(cap or "No shot")}</div>'
    return (f'<figure><div class="frame"><img src="{html.escape(img)}" alt="{html.escape(cap or "")}">'
            f'{boxes_html(boxes, side)}</div><figcaption>{html.escape(cap or "")}</figcaption></figure>')


def cascade(groups):
    """Order items so anything an item builds on ("deps") comes first.
    Kahn's algorithm; among ready items the lowest group, then spec order, wins.
    O(n^2) scan: fine for the tens of items a page holds."""
    items = [(gi, k, it) for gi, g in enumerate(groups) for k, it in enumerate(g["items"])]
    ids = {it["id"] for _, _, it in items}
    for _, _, it in items:
        for d in it.get("deps", []):
            if d not in ids:
                sys.exit(f"spec error: {it['id']} depends on unknown {d}")
    done, out = set(), []
    while len(out) < len(items):
        ready = [x for x in items if x[2]["id"] not in done and all(d in done for d in x[2].get("deps", []))]
        if not ready:
            sys.exit("spec error: dependency cycle among " + ", ".join(x[2]["id"] for x in items if x[2]["id"] not in done))
        pick = min(ready, key=lambda x: (x[0], x[1]))
        done.add(pick[2]["id"])
        out.append(pick)
    return out


def main(spec_path, out_path):
    s = json.load(open(spec_path))
    order = cascade(s["groups"])
    num = {it["id"]: i + 1 for i, (_, _, it) in enumerate(order)}
    shown_in = {}
    for _, _, it in order:
        for d in it.get("deps", []):
            shown_in.setdefault(d, []).append(it["id"])
    a = lambda i: f'<a href="#i{num[i]}">{num[i]}. {html.escape(i)}</a>'
    o = [f'<title>{html.escape(s["title"])}</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;600&display=swap">\n'
         f'<style>{CSS}</style>\n<div class="wrap">\n<header><h1>{html.escape(s["title"])}</h1><p class="sub">{e(s.get("intro"))}</p></header>\n']
    o.append('<section class="strip">' + "".join(
        f'<div class="stat"><b>{len(g["items"])}</b><span>{html.escape(g.get("short", g["title"]))}</span></div>'
        for g in s["groups"]) + "</section>\n")
    o.append('<nav class="toc">' + "".join(f'<a href="#g{i}">{html.escape(g["title"])}</a>'
                                          for i, g in enumerate(s["groups"])) +
             ('<a href="#review">Self review</a>' if s.get("review") else "") + "</nav>\n")
    has_feat = any(it.get("feature") for _, _, it in order)
    o.append('<h2>All items</h2><div class="scroll"><table><thead><tr><th>S. No</th><th>Item</th>' +
             ('<th>Feature</th>' if has_feat else '') + '<th>Title</th>'
             '<th>Priority</th><th>Tracker status</th><th>Current state</th><th>PR</th><th>Waiting on</th></tr></thead><tbody>')
    for gi, _, it in order:
        o.append(f'<tr><td class="n">{num[it["id"]]}</td><td class="k"><a href="#i{num[it["id"]]}">{html.escape(it["id"])}</a></td>'
                 + (f'<td class="feat">{html.escape(it.get("feature", ""))}</td>' if has_feat else '') +
                 f'<td>{e(it["title"])}</td>'
                 f'<td><span class="pill p-{it.get("priority","Medium").lower()}">{it.get("priority","")}</span></td>'
                 f'<td>{e(it.get("tracker",""))}</td><td><span class="pill s-{it.get("st","send")}">{e(it["state"])}</span></td>'
                 f'<td>{e(it.get("pr") or "-")}</td><td>{e(it.get("waiting") or "-")}</td></tr>')
    o.append("</tbody></table></div>\n")
    if s.get("legend"):
        o.append('<div class="card"><h3>What each status means</h3><ul class="legend">' + "".join(
            f'<li><span class="pill s-{x.get("st","send")}">{html.escape(x["state"])}</span> {e(x["meaning"])}</li>'
            for x in s["legend"]) + "</ul></div>\n")
    seen, last = set(), None
    for gi, _, it in order:
        n = num[it["id"]]
        if gi != last:
            g = s["groups"][gi]
            cont = " (continued)" if gi in seen else ""
            gid = "" if gi in seen else f' id="g{gi}"'
            o.append(f'<h2{gid}>{html.escape(g["title"])}{cont}</h2>' + ("" if cont else f'<p class="note">{e(g.get("sub"))}</p>') + "\n")
            seen.add(gi)
            last = gi
        if True:
            link = f'<a href="{it["url"]}">{html.escape(it["id"])}</a>' if it.get("url") else html.escape(it["id"])
            meta = " | ".join(x for x in [it.get("tracker") and "Tracker: " + it["tracker"], it.get("pr") and "PR: " + it["pr"]] if x)
            o.append(f'<article class="card" id="i{n}"><h3>{n}. {link} {e(it["title"])} '
                     f'<span class="pill p-{it.get("priority","Medium").lower()}">{it.get("priority","")}</span>'
                     f'<span class="pill s-{it.get("st","send")}">{e(it["state"])}</span><span class="meta">{meta}</span></h3>')
            o.append('<div class="tw"><table><thead><tr>' + "".join(f"<th>{h}</th>" for _, h in COLS) +
                     "</tr></thead><tbody><tr>" + "".join(f"<td>{e(it.get(k,'-'))}</td>" for k, _ in COLS) + "</tr></tbody></table></div>")
            if it.get("side"):
                o.append(f'<p class="side"><b>Side effects / risks:</b> {e(it["side"])}</p>')
            if it.get("deps"):
                o.append('<p class="side"><b>Builds on:</b> ' + ", ".join(a(d) for d in it["deps"]) + " (shown above)</p>")
            if shown_in.get(it["id"]):
                o.append('<p class="side"><b>Also visible in:</b> ' + ", ".join(a(d) for d in shown_in[it["id"]]) + "</p>")
            if it.get("verify"):
                o.append('<details class="verify" open><summary>How to verify it yourself</summary><ol>' +
                         "".join(f"<li>{e(v)}</li>" for v in it["verify"]) + "</ol></details>")
            if it.get("shots_note"):
                o.append(f'<p class="side"><b>Screenshots:</b> {e(it["shots_note"])}</p>')
            if it.get("shots"):
                hb, ha = it.get("shot_heads", ["BEFORE", "AFTER"])
                o.append(f'<div class="ba"><div class="head b">{html.escape(hb)}</div><div class="head a">{html.escape(ha)}</div>')
                for sh in it["shots"]:
                    o.append(cell(sh.get("before"), sh.get("before_cap"), sh.get("before_boxes"), "b") +
                             cell(sh.get("after"), sh.get("after_cap"), sh.get("after_boxes"), "a"))
                o.append("</div>")
            o.append("</article>\n")
    if s.get("review"):
        r = s["review"]
        o.append(f'<h2 id="review">{html.escape(r.get("title", "Self review"))}</h2><p class="note">{e(r.get("sub"))}</p><div class="review">')
        for sec in r["sections"]:
            o.append(f'<div class="card"><h3>{html.escape(sec["title"])}</h3><ul>' +
                     "".join(f"<li>{e(x)}</li>" for x in sec["items"]) + "</ul></div>")
        o.append("</div>\n")
    o.append(f'<p class="note">{e(s.get("sources"))}</p>\n</div>\n')
    # Click any screenshot to see it full screen; Esc, the close button or a click closes it.
    o.append('<dialog id="lb" aria-label="Screenshot, full size"><button type="button" id="lbx" aria-label="Close">Close</button>'
             '<div class="lbf" id="lbf"><img id="lbi" alt=""></div><p id="lbc"></p></dialog>\n'
             '<script>(function(){var d=document.getElementById("lb"),i=document.getElementById("lbi"),c=document.getElementById("lbc"),lf=document.getElementById("lbf");'
             'document.querySelectorAll(".bx").forEach(function(b){if(parseFloat(b.style.top)<6)b.classList.add("flip")});'
             'document.querySelectorAll(".frame img").forEach(function(im){im.tabIndex=0;im.title="Click to open full screen";'
             'function open(){i.src=im.src;i.alt=im.alt;var f=im.closest("figure");c.textContent=f&&f.querySelector("figcaption")?f.querySelector("figcaption").textContent:"";'
             'lf.querySelectorAll(".bx").forEach(function(x){x.remove()});im.parentNode.querySelectorAll(".bx").forEach(function(x){lf.appendChild(x.cloneNode(true))});'
             'if(d.showModal)d.showModal();else d.setAttribute("open","")}'
             'im.addEventListener("click",open);im.addEventListener("keydown",function(ev){if(ev.key==="Enter"||ev.key===" "){ev.preventDefault();open()}})});'
             'function close(){d.close?d.close():d.removeAttribute("open")}'
             'document.getElementById("lbx").addEventListener("click",close);d.addEventListener("click",function(ev){if(ev.target===d||ev.target===i)close()})})();</script>\n')
    open(out_path, "w").write("".join(o))
    print(f"built {out_path}: {len(order)} items")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
