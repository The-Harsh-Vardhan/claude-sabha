#!/usr/bin/env python3
"""sabha-typography-check: check fonts and text styling against an allow-list (run it through bin/sabha-typography-check).

  sabha-typography-check <file.pdf | page.html | computed.json> --allow ALLOW.json [--browser] [--json] [--limit N]
  sabha-typography-check --self-test

Inputs, cheapest first:
  *.pdf         every text span: face, size, weight (from the face name), colour, background fill, page edge. No browser.
  *.html, *.htm static CSS lint of <style>, local <link> sheets and style="" attributes. No browser.
                --browser also runs a runner under `sabha-heavy run typography --` and checks the computed styles it dumps.
  *.json        a computed-styles dump written by a runner (see tools/typography-computed.mjs for the format).
Exit 0 = no findings, 1 = findings, 2 = usage or unreadable input, 75 = the heavy gate says wait (browser not run).
A finding is a question for the owner or designer, never an auto-fix.
"""
import difflib
import json
import math
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = "usage: sabha-typography-check <file.pdf|page.html|computed.json> --allow ALLOW.json [--browser] [--json] [--limit N] [--type pdf|html|computed]"
LIMITS = {"pdf": 50 * 1024 * 1024, "html": 5 * 1024 * 1024, "json": 5 * 1024 * 1024}
CHECKS = ["FAMILY", "FALLBACK", "SIZE", "WEIGHT", "COLOR", "CONTRAST", "LINEHEIGHT", "WRAP", "ROLE"]
GENERIC = {"serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-serif", "ui-sans-serif",
           "ui-monospace", "ui-rounded", "emoji", "math", "fangsong"}
NAMED = {"black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "green": (0, 128, 0),
         "blue": (0, 0, 255), "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192),
         "yellow": (255, 255, 0), "orange": (255, 165, 0), "purple": (128, 0, 128), "navy": (0, 0, 128),
         "teal": (0, 128, 128), "maroon": (128, 0, 0), "lime": (0, 255, 0)}
MAX_PAGES = 300
MAX_ELEMENTS = 20000


class Fail(Exception):
    def __init__(self, msg, rc=2):
        Exception.__init__(self, msg)
        self.rc = rc


def clean(s):
    """The one function every printed value goes through: printable ASCII only, the rest escaped."""
    s = s if isinstance(s, str) else str(s)
    out = []
    for ch in s:
        o = ord(ch)
        if 0x20 <= o < 0x7F:
            out.append(ch)
        elif o < 0x100:
            out.append("\\x%02x" % o)
        elif o < 0x10000:
            out.append("\\u%04x" % o)
        else:
            out.append("\\U%08x" % o)
    return "".join(out)


def fnum(x):
    s = ("%.2f" % x).rstrip("0").rstrip(".")
    return s or "0"


def num(v):
    """A finite number from a number or a '12px' string, else None (never raises)."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) if math.isfinite(v) else None
    if isinstance(v, str):
        m = re.fullmatch(r"\s*(-?[0-9]*\.?[0-9]+)(?:px)?\s*", v)
        if m:
            return float(m.group(1))
    return None


def read_file(path, kind):
    path = os.path.expanduser(os.path.expandvars(path))
    try:
        st = os.stat(path)
    except OSError as e:
        raise Fail("cannot read %s: %s" % (clean(path), clean(e.strerror or e)))
    if not stat.S_ISREG(st.st_mode):
        raise Fail("not a regular file: %s" % clean(path))
    if st.st_size > LIMITS[kind]:
        raise Fail("too large (%d bytes, limit %d): %s" % (st.st_size, LIMITS[kind], clean(path)))
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as e:
        raise Fail("cannot read %s: %s" % (clean(path), clean(e.strerror or e)))


def parse_json(raw, what):
    try:
        return json.loads(raw.decode("utf-8", "replace"))
    except (ValueError, RecursionError) as e:
        raise Fail("%s is not valid JSON: %s" % (what, clean(e)))


# ---------- colour and unit helpers ----------

def parse_color(s):
    if not isinstance(s, str):
        return None
    s = s.strip().lower()
    if s in NAMED:
        return NAMED[s]
    m = re.fullmatch(r"#([0-9a-f]{3,8})", s)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h[:3])
        elif len(h) in (6, 8):
            h = h[:6]
        else:
            return None
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    m = re.fullmatch(r"rgba?\(\s*([0-9.]+)[ ,]+([0-9.]+)[ ,]+([0-9.]+)(?:[ ,/]+([0-9.]+%?))?\s*\)", s)
    if m:
        a = m.group(4)
        try:
            if a is not None and float(a.rstrip("%")) == 0:
                return None
            return tuple(max(0, min(255, int(round(float(m.group(i)))))) for i in (1, 2, 3))
        except ValueError:
            return None
    return None


def hexs(rgb):
    return "#%02x%02x%02x" % rgb


def luminance(rgb):
    def ch(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(rgb[0]) + 0.7152 * ch(rgb[1]) + 0.0722 * ch(rgb[2])


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


UNIT_PX = {"px": 1.0, "pt": 4.0 / 3.0, "rem": 16.0, "pc": 16.0, "in": 96.0, "cm": 96 / 2.54, "mm": 96 / 25.4}


def css_len_px(v):
    m = re.fullmatch(r"\s*([0-9]*\.?[0-9]+)(px|pt|rem|pc|in|cm|mm)\s*", str(v).lower())
    return float(m.group(1)) * UNIT_PX[m.group(2)] if m else None


def norm_family(f):
    return re.sub(r"[^a-z0-9]", "", str(f).strip().strip("\"'").lower())


STYLE_TAIL = r"(regular|roman|book|bold|semibold|demibold|extrabold|ultrabold|black|heavy|medium|light|extralight|ultralight|thin|italic|oblique|mt|psmt|ps)*"


# ---------- the allow-list ----------

def load_allow(path):
    d = parse_json(read_file(path, "json"), "allow-list")
    if not isinstance(d, dict):
        raise Fail("allow-list must be a JSON object")
    A = {"families": None, "sizes": None, "weights": None, "colors": None, "line_height": None,
         "min_contrast": None, "tol": 0.3, "bg": None, "embed": False, "off": [], "unknown": []}
    known = {"families", "sizes", "weights", "colors", "line_height", "min_contrast", "tolerance",
             "page_background", "pdf_require_embedded", "comment", "name"}
    A["unknown"] = sorted(k for k in d if k not in known)

    def lst(key):
        v = d[key]
        if not isinstance(v, list) or not v:
            raise Fail("allow-list: '%s' must be a non-empty list" % key)
        return v

    if "families" in d:
        fams = []
        for e in lst("families"):
            if isinstance(e, str):
                e = {"name": e}
            if not isinstance(e, dict) or not isinstance(e.get("name"), str) or not e["name"].strip():
                raise Fail("allow-list: each family is a name or an object with a 'name'")
            fb = e.get("fallbacks", [])
            if not isinstance(fb, list) or not all(isinstance(x, str) for x in fb):
                raise Fail("allow-list: 'fallbacks' must be a list of names")
            if not isinstance(e.get("system", False), bool):
                raise Fail("allow-list: 'system' must be true or false")
            fams.append({"name": e["name"].strip(), "norm": norm_family(e["name"]), "fallbacks": fb,
                         "system": bool(e.get("system", False))})
        A["families"] = fams
    if "sizes" in d:
        out = []
        for v in lst("sizes"):
            if isinstance(v, str):
                m = re.fullmatch(r"\s*([0-9]*\.?[0-9]+)\s*(px|pt|rem|em)?\s*", v.lower())
                px = float(m.group(1)) * {"px": 1, "pt": 4.0 / 3.0, "rem": 16, "em": 16, None: 1}[m.group(2)] if m else None
            else:
                px = num(v)
            if px is None or not 0 < px < 1000:
                raise Fail("allow-list: bad size %s" % clean(repr(v)))
            out.append(px)
        A["sizes"] = sorted(set(out))
    if "weights" in d:
        out = []
        for v in lst("weights"):
            if isinstance(v, bool) or not isinstance(v, int) or not 1 <= v <= 1000:
                raise Fail("allow-list: bad weight %s" % clean(repr(v)))
            out.append(v)
        A["weights"] = sorted(set(out))
    if "colors" in d:
        cols = []
        c = d["colors"]
        items = sorted(c.items()) if isinstance(c, dict) and c else (c if isinstance(c, list) and c else None)
        if items is None:
            raise Fail("allow-list: 'colors' must be a non-empty list or object")
        for it in items:
            name, val = (it if isinstance(it, tuple) else (it, it))
            rgb = parse_color(val)
            if rgb is None:
                raise Fail("allow-list: bad colour %s" % clean(repr(val)))
            cols.append((str(name), rgb))
        A["colors"] = cols
    if "line_height" in d:
        lh = d["line_height"]
        lo, hi = (num(lh.get("min")), num(lh.get("max"))) if isinstance(lh, dict) else (None, None)
        if lo is None or hi is None or not 0 < lo <= hi:
            raise Fail("allow-list: 'line_height' must be {\"min\": n, \"max\": n} with 0 < min <= max")
        A["line_height"] = (lo, hi)
    if "min_contrast" in d:
        mc = num(d["min_contrast"])
        if mc is None or not 1 <= mc <= 21:
            raise Fail("allow-list: 'min_contrast' must be a number from 1 to 21")
        A["min_contrast"] = mc
    if "tolerance" in d:
        t = d["tolerance"]
        v = num(t.get("size_px")) if isinstance(t, dict) else None
        if v is None or not 0 <= v <= 5:
            raise Fail("allow-list: 'tolerance' must be {\"size_px\": n} with 0 <= n <= 5")
        A["tol"] = v
    if "page_background" in d:
        bg = parse_color(d["page_background"])
        if bg is None:
            raise Fail("allow-list: bad 'page_background'")
        A["bg"] = bg
    if "pdf_require_embedded" in d:
        if not isinstance(d["pdf_require_embedded"], bool):
            raise Fail("allow-list: 'pdf_require_embedded' must be true or false")
        A["embed"] = d["pdf_require_embedded"]
    for key, label in (("families", "FAMILY"), ("sizes", "SIZE"), ("weights", "WEIGHT"), ("colors", "COLOR"),
                       ("line_height", "LINEHEIGHT"), ("min_contrast", "CONTRAST")):
        if A[key] is None:
            A["off"].append(label)
    return A


# ---------- the report ----------

class Report:
    def __init__(self):
        self.groups = {}
        self.order = []
        self.notes = []

    def add(self, check, where, found, allowed=""):
        key = (check, found, allowed)
        if key not in self.groups:
            self.groups[key] = []
            self.order.append(key)
        if where not in self.groups[key]:
            self.groups[key].append(where)

    def note(self, msg):
        if msg not in self.notes:
            self.notes.append(msg)

    def count(self):
        return sum(len(w) for w in self.groups.values())


def fam_ok(A, name, pdf=False):
    n = norm_family(name)
    for f in A["families"]:
        if n == f["norm"]:
            return True
        if pdf and n.startswith(f["norm"]) and re.fullmatch(STYLE_TAIL, n[len(f["norm"]):]):
            return True
    return False


def nearest_family(A, name):
    norms = [f["norm"] for f in A["families"]]
    m = difflib.get_close_matches(norm_family(name), norms, 1, 0.5)
    f = A["families"][norms.index(m[0])] if m else A["families"][0]
    return ", ".join([f["name"]] + f["fallbacks"])


def sz(px):
    return "%spx (%spt)" % (fnum(px), fnum(px * 0.75))


def check_style(R, A, where, family=None, size=None, weight=None, color=None, bg=None, lh=None, pdf=False):
    if family is not None and A["families"] and not fam_ok(A, family, pdf):
        R.add("FAMILY", where, "family %s" % family, nearest_family(A, family))
    if size is not None and A["sizes"]:
        near = min(A["sizes"], key=lambda s: abs(s - size))
        if abs(near - size) > A["tol"]:
            R.add("SIZE", where, sz(size), sz(near))
    if weight is not None and A["weights"] and weight not in A["weights"]:
        near = min(A["weights"], key=lambda w: abs(w - weight))
        R.add("WEIGHT", where, "weight %d" % weight, "weight %d" % near)
    if color is not None and A["colors"]:
        best = min(A["colors"], key=lambda c: sum((c[1][i] - color[i]) ** 2 for i in range(3)))
        if max(abs(best[1][i] - color[i]) for i in range(3)) > 2:
            label = hexs(best[1]) if best[0] == hexs(best[1]) else "%s (%s)" % (hexs(best[1]), best[0])
            R.add("COLOR", where, "colour %s" % hexs(color), label)
    if color is not None and bg is not None and A["min_contrast"]:
        r = contrast(color, bg)
        if r < A["min_contrast"] - 0.005:
            R.add("CONTRAST", where, "contrast %s:1 (%s on %s)" % (fnum(r), hexs(color), hexs(bg)),
                  "at least %s:1" % fnum(A["min_contrast"]))
    if lh is not None and A["line_height"] and not A["line_height"][0] - 0.005 <= lh <= A["line_height"][1] + 0.005:
        R.add("LINEHEIGHT", where, "line height %s" % fnum(lh), "%s to %s" % (fnum(A["line_height"][0]), fnum(A["line_height"][1])))


# ---------- static CSS lint ----------

def parse_body(t):
    """Split a CSS block into declarations [(prop, value)] and nested blocks [(prelude, body)]."""
    decls, nested = [], []
    i, n, start, dp, q = 0, len(t), 0, 0, None

    def decl(chunk):
        if ":" not in chunk:
            return
        p, v = chunk.split(":", 1)
        p = p.strip()
        if not re.fullmatch(r"-{0,2}[A-Za-z_][A-Za-z0-9_-]*", p):
            return
        p = p if p.startswith("--") else p.lower()
        decls.append((p, re.sub(r"\s*!important\s*$", "", v.strip(), flags=re.I)))

    while i < n:
        c = t[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "(":
            dp += 1
        elif c == ")":
            dp = max(0, dp - 1)
        elif dp == 0 and c == ";":
            decl(t[start:i])
            start = i + 1
        elif dp == 0 and c == "{":
            j, depth, qq = i + 1, 1, None
            while j < n and depth:
                cj = t[j]
                if qq:
                    if cj == "\\":
                        j += 1
                    elif cj == qq:
                        qq = None
                elif cj in "\"'":
                    qq = cj
                elif cj == "{":
                    depth += 1
                elif cj == "}":
                    depth -= 1
                j += 1
            nested.append((" ".join(t[start:i].split()), t[i + 1:j - 1 if depth == 0 else j]))
            i = j - 1
            start = j
        i += 1
    decl(t[start:])
    return decls, nested


def walk_css(css, ctx, rules, fontfaces, imports, depth=0):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    for m in re.finditer(r"@import\s+(?:url\()?\s*['\"]?([^'\")\s;]+)", css, re.I):
        imports.append(m.group(1))
    decls, nested = parse_body(css)
    for prelude, body in nested:
        p = prelude.lower()
        if p.startswith("@font-face"):
            fontfaces.append(dict(parse_body(body)[0]))
        elif p.startswith(("@media", "@supports", "@layer", "@container")):
            if depth < 8:
                walk_css(body, ctx or p.split()[0], rules, fontfaces, imports, depth + 1)
        elif p.startswith("@page"):
            d, nst = parse_body(body)
            rules.append((prelude, d, ctx))
            for sp, sb in nst:
                rules.append((prelude + " " + sp, parse_body(sb)[0], ctx))
        elif p.startswith("@"):
            continue
        else:
            rules.append((prelude, parse_body(body)[0], ctx))


def resolve_vars(val, cvars):
    for _ in range(6):
        if "var(" not in val:
            return val
        val = re.sub(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^()]*))?\)",
                     lambda m: cvars.get(m.group(1), m.group(2) if m.group(2) is not None else m.group(0)), val)
    return None if "var(" in val else val


def first_family(val):
    if not val:
        return None
    m = re.match(r"\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]+))", val)
    if not m:
        return None
    f = (m.group(1) or m.group(2) or m.group(3) or "").strip()
    if not f or f.lower() in ("inherit", "initial", "unset", "revert") or "var(" in f:
        return None
    return f


def split_commas(s):
    out, depth, cur = [], 0, []
    for c in s:
        if c in "([":
            depth += 1
        elif c in ")]":
            depth = max(0, depth - 1)
        if c == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    out.append("".join(cur))
    return [x.strip() for x in out if x.strip()]


def static_rule(R, A, where, decls, cvars, state, tag_roles=None, ctx=None, is_body=False):
    d = {}
    for p, v in decls:
        if not p.startswith("--"):
            r = resolve_vars(v, cvars)
            if r is not None:
                d[p] = r
    fam = size = weight = None
    if "font" in d:
        m = re.match(r"^(?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|[1-9]00)\s+)*"
                     r"([0-9.]+(?:px|pt|rem|em))(?:/[^\s]+)?\s+(.+)$", d["font"], re.I)
        if m:
            size = css_len_px(m.group(1))
            fam = first_family(m.group(2))
            wm = re.search(r"\b(bold|[1-9]00)\b", d["font"].split(m.group(1))[0], re.I)
            if wm:
                weight = 700 if wm.group(1).lower() == "bold" else int(wm.group(1))
    if "font-family" in d:
        fam = first_family(d["font-family"])
    if "font-size" in d:
        size = css_len_px(d["font-size"])
        if size is None:
            state["unchecked"] += 1
    if "font-weight" in d:
        w = d["font-weight"].strip().lower()
        weight = 400 if w == "normal" else 700 if w == "bold" else int(w) if re.fullmatch(r"[1-9][0-9]{0,2}", w) else None
    color = parse_color(d["color"]) if "color" in d else None
    bg = None
    for key in ("background-color", "background"):
        if key in d:
            m = re.search(r"#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|\b(?:%s)\b" % "|".join(NAMED), d[key], re.I)
            if m:
                bg = parse_color(m.group(0))
    lh = None
    if "line-height" in d:
        v = d["line-height"].strip().lower()
        if re.fullmatch(r"[0-9]*\.?[0-9]+", v):
            lh = float(v)
        elif v.endswith("%") and num(v[:-1]) is not None:
            lh = float(v[:-1]) / 100
        elif v.endswith("em") and not v.endswith("rem") and num(v[:-2]) is not None:
            lh = float(v[:-2])
        elif size and css_len_px(v):
            lh = css_len_px(v) / size
    label = where if not ctx else "%s (in %s)" % (where, ctx)
    fam_for_check = fam
    if fam and A["families"] and fam.lower() in GENERIC:
        R.add("FAMILY", label, "family %s" % fam, nearest_family(A, fam))
        fam_for_check = None
    elif fam and A["families"] and fam_ok(A, fam):
        entry = [f for f in A["families"] if f["norm"] == norm_family(fam)][0]
        if not entry["system"] and not state["remote_css"] and norm_family(fam) not in state["declared"]:
            R.add("FALLBACK", label, "family %s is used but no @font-face declares it" % fam,
                  "an @font-face for it, or \"system\": true in the allow-list")
    contrast_bg = bg if (bg is not None and color is not None) else (
        (bg or A["bg"]) if (is_body and color is not None) else None)
    check_style(R, A, label, family=fam_for_check, size=size, weight=weight, color=color, bg=contrast_bg, lh=lh)
    if d.get("text-overflow", "").lower().startswith("ellipsis"):
        R.add("WRAP", label, "text-overflow: ellipsis cuts text instead of wrapping", "wrap the text or approve the cut")
    if d.get("overflow", d.get("overflow-y", "")).lower() in ("hidden", "clip") and "height" in d \
            and css_len_px(d["height"]) is not None and "-webkit-line-clamp" not in d:
        R.add("WRAP", label, "fixed height %s with overflow hidden can clip wrapped text" % d["height"],
              "min-height, or approve the clip")
    if tag_roles is not None and not ctx:
        for part in split_commas(where):
            last = re.split(r"[\s>+~]+", part.strip())[-1]
            if re.fullmatch(r"h[1-6]", last, re.I):
                tag_roles.setdefault(last.lower(), []).append((part.strip(), size, weight))


def role_findings(R, roles):
    for tag, rows in sorted(roles.items()):
        for idx, what, fmt in ((1, "sizes", sz), (2, "weights", lambda v: "weight %d" % v)):
            seen = {}
            for r in rows:
                if r[idx] is not None:
                    seen.setdefault(r[idx], []).append(r[0])
            if len(seen) > 1:
                found = "%s styled with %d %s: %s" % (tag, len(seen), what, "; ".join(
                    "%s in %s" % (fmt(v), ", ".join('"%s"' % s for s in sels)) for v, sels in sorted(seen.items())))
                R.add("ROLE", tag, found, "one %s per heading level" % what[:-1])


def check_html_static(R, A, path, data):
    base = os.path.dirname(os.path.abspath(os.path.expanduser(os.path.expandvars(path))))
    html = data.decode("utf-8", "replace")
    chunks = [m.group(1) for m in re.finditer(r"<style\b[^>]*>(.*?)</style>", html, re.S | re.I)]
    remote = False
    for m in re.finditer(r"<link\b[^>]*>", html, re.I):
        tag = m.group(0)
        if not re.search(r"rel\s*=\s*[\"']?[^\"'>]*stylesheet", tag, re.I):
            continue
        hm = re.search(r"href\s*=\s*[\"']([^\"']+)[\"']", tag, re.I)
        if not hm:
            continue
        href = hm.group(1)
        if re.match(r"(https?:)?//", href, re.I):
            remote = True
            R.note("external stylesheet not fetched: %s" % clean(href))
        elif "$" in href or "[(" in href or "{{" in href:
            R.note("stylesheet link is a template placeholder, not read: %s" % clean(href))
        else:
            try:
                chunks.append(read_file(os.path.join(base, href.split("?")[0].split("#")[0]), "html").decode("utf-8", "replace"))
            except Fail as e:
                R.note("stylesheet not read: %s" % e)
    rules, fontfaces, imports = [], [], []
    for c in chunks:
        walk_css(c, None, rules, fontfaces, imports)
    for imp in imports:
        if re.match(r"(https?:)?//", imp, re.I):
            remote = True
            R.note("external @import not fetched: %s" % clean(imp))
    cvars = {}
    for sel, decls, ctx in rules:
        if not ctx and any(p.strip() in (":root", "html") for p in split_commas(sel)):
            for p, v in decls:
                if p.startswith("--"):
                    cvars[p] = v
    state = {"unchecked": 0, "remote_css": remote,
             "declared": set(norm_family(f.get("font-family", "")) for f in fontfaces)}
    for ff in fontfaces:
        fam = ff.get("font-family", "?").strip("\"' ")
        for um in re.finditer(r"url\(\s*(?:\"([^\"]*)\"|'([^']*)'|([^)]*))\s*\)", ff.get("src", "")):
            u = (um.group(1) or um.group(2) or um.group(3) or "").strip()
            if re.match(r"(data:|https?:|//)", u, re.I):
                continue
            if "$" in u or "[(" in u or "{{" in u:
                R.note("@font-face src is a template placeholder, not checked: %s" % clean(u))
                continue
            if not os.path.exists(os.path.join(base, u.split("?")[0].split("#")[0])):
                R.add("FALLBACK", "@font-face %s" % fam, "src file not found: %s" % u,
                      "a file next to the page, or the face does not load")
    roles = {}
    for sel, decls, ctx in rules:
        if sel.startswith("@page"):
            static_rule(R, A, sel, decls, cvars, state, None, ctx)
            continue
        is_body = any(p.strip().lower() in ("body", "html") for p in split_commas(sel))
        static_rule(R, A, sel[:90], decls, cvars, state, roles, ctx, is_body)
    for m in re.finditer(r"<([a-zA-Z][\w-]*)\b([^>]*?)\sstyle\s*=\s*(?:\"([^\"]*)\"|'([^']*)')", html):
        label = "<%s> style attribute" % m.group(1)
        idm = re.search(r"\bid\s*=\s*[\"']([^\"']+)", m.group(2))
        if idm:
            label += " #" + idm.group(1)
        static_rule(R, A, label, parse_body(m.group(3) if m.group(3) is not None else m.group(4))[0], cvars, state)
    role_findings(R, roles)
    if state["unchecked"]:
        R.note("%d font-size values in em, percent or keywords were not checked (use --browser for computed sizes)" % state["unchecked"])
    R.note("static contrast needs a rule that sets both colours (or body); page width and real wrapping need --browser")


# ---------- computed styles (browser runner output) ----------

def check_computed(R, A, data):
    if not isinstance(data, dict) or not isinstance(data.get("elements"), list):
        raise Fail("computed-styles JSON must be an object with an \"elements\" list")
    els = data["elements"]
    if len(els) > MAX_ELEMENTS:
        R.note("only the first %d of %d elements were checked" % (MAX_ELEMENTS, len(els)))
        els = els[:MAX_ELEMENTS]
    bad = 0
    roles = {}
    for el in els:
        if not isinstance(el, dict):
            bad += 1
            continue
        where = str(el.get("selector") or "?")
        if isinstance(el.get("text"), str) and el["text"].strip():
            where += " '%s'" % el["text"].strip()[:40]
        fam = first_family(el["family"]) if isinstance(el.get("family"), str) else None
        size, weight = num(el.get("size_px")), num(el.get("weight"))
        weight = int(weight) if weight is not None else None
        bg = parse_color(el.get("bg")) or A["bg"] or (255, 255, 255)
        lh_px = num(el.get("line_height_px"))
        lh = lh_px / size if lh_px is not None and size else None
        check_style(R, A, where, family=fam, size=size, weight=weight, color=parse_color(el.get("color")), bg=bg, lh=lh)
        if fam and fam.lower() not in GENERIC and el.get("face_loaded") is False:
            R.add("FALLBACK", where, "declared face %s did not load" % fam, "a face that loads (check the @font-face src)")
        sw, cw, sh, ch = (num(el.get(k)) for k in ("scroll_w", "client_w", "scroll_h", "client_h"))
        ox = str(el.get("overflow_x", "visible")).lower()
        oy = str(el.get("overflow_y", "visible")).lower()
        if sw is not None and cw is not None and sw > cw + 1:
            if str(el.get("text_overflow", "")).lower().startswith("ellipsis"):
                R.add("WRAP", where, "ellipsised: text is cut, %s px longer than its box" % fnum(sw - cw), "wrap the text or approve the cut")
            elif ox in ("hidden", "clip"):
                R.add("WRAP", where, "clipped: %s px of text hidden sideways" % fnum(sw - cw), "let the text wrap or widen the box")
            else:
                R.add("WRAP", where, "overflows its box by %s px" % fnum(sw - cw), "text inside the box")
        elif sh is not None and ch is not None and sh > ch + 1 and oy in ("hidden", "clip"):
            R.add("WRAP", where, "clipped: %s px of text hidden vertically" % fnum(sh - ch), "let the box grow")
        tag = str(el.get("tag", "")).lower()
        if re.fullmatch(r"h[1-6]", tag):
            roles.setdefault(tag, []).append((str(el.get("selector") or tag), size, weight))
    page = data.get("page") if isinstance(data.get("page"), dict) else {}
    ps, pi = num(page.get("scroll_w")), num(page.get("inner_w"))
    if ps is not None and pi is not None and ps > pi + 1:
        R.add("WRAP", "page", "page is %s px wide in a %s px window (sideways scroll)" % (fnum(ps), fnum(pi)), "no wider than the window")
    role_findings(R, roles)
    if bad:
        R.note("%d computed entries were not objects and were skipped" % bad)


# ---------- PDF ----------

def pdf_color(c):
    try:
        if c is None:
            return (0, 0, 0)
        vals = [float(c)] if isinstance(c, (int, float)) and not isinstance(c, bool) else [float(x) for x in c]
        vals = [max(0.0, min(1.0, v)) for v in vals]
        if len(vals) == 1:
            return (int(round(vals[0] * 255)),) * 3
        if len(vals) == 3:
            return tuple(int(round(v * 255)) for v in vals)
        if len(vals) == 4:
            return tuple(int(round(255 * (1 - v) * (1 - vals[3]))) for v in vals[:3])
    except (TypeError, ValueError):
        pass
    return None


def pdf_weight(name):
    n = name.lower()
    for key, w in (("extrabold", 800), ("ultrabold", 800), ("semibold", 600), ("demibold", 600), ("extralight", 200),
                   ("ultralight", 200), ("black", 900), ("heavy", 900), ("bold", 700), ("medium", 500),
                   ("light", 300), ("thin", 100)):
        if key in n:
            return w
    return 400


def pdf_chars(data):
    try:
        from io import BytesIO
        from pdfminer.pdfdevice import PDFTextDevice
        from pdfminer.pdfinterp import PDFPageInterpreter, PDFResourceManager
        from pdfminer.pdfpage import PDFPage
        from pdfminer.utils import apply_matrix_pt
    except ImportError:
        raise Fail("reading a PDF needs pdfminer.six in a repo-local .venv: "
                   "uv venv .venv && uv pip install --python .venv/bin/python -r tools/typography-requirements.txt")

    class Dev(PDFTextDevice):
        def __init__(self, rsrc):
            PDFTextDevice.__init__(self, rsrc)
            self.chars, self.rects, self.pages = [], [], 0
            self.box, self.size = (0, 0, 612, 792), (612, 792)

        def begin_page(self, page, ctm):
            self.pages += 1
            self.box = page.mediabox if page.mediabox else (0, 0, 612, 792)
            self.size = (self.box[2] - self.box[0], self.box[3] - self.box[1])

        def paint_path(self, gstate, stroke, fill, evenodd, path):
            if not fill or self.ctm is None:
                return
            pts = [apply_matrix_pt(self.ctm, (float(s[-2]), float(s[-1]))) for s in path if s[0] != "h" and len(s) >= 3]
            if len(pts) >= 3:
                xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                self.rects.append((self.pages, min(xs), min(ys), max(xs), max(ys), pdf_color(gstate.ncolor)))

        def render_char(self, matrix, font, fontsize, scaling, rise, cid, ncs, gs):
            try:
                text = font.to_unichr(cid)
                text = text if isinstance(text, str) else "?"
            except Exception:
                text = "?"
            adv = font.char_width(cid) * fontsize * scaling
            name = str(getattr(font, "basefont", None) or getattr(font, "fontname", "unknown"))
            desc = getattr(font, "descriptor", None) or {}
            emb = type(font).__name__ == "PDFType3Font" or any(k in desc for k in ("FontFile", "FontFile2", "FontFile3"))
            x0, y0 = matrix[4] - self.box[0], matrix[5] - self.box[1]
            self.chars.append({"page": self.pages, "x0": x0, "y0": y0, "x1": x0 + adv * matrix[0], "y1": y0 + adv * matrix[1],
                               "text": text, "font": name, "size": fontsize * math.hypot(matrix[0], matrix[1]),
                               "color": pdf_color(gs.ncolor), "emb": emb, "w": self.size[0], "h": self.size[1]})
            return adv

    n = 0
    try:
        rsrc = PDFResourceManager()
        dev = Dev(rsrc)
        interp = PDFPageInterpreter(rsrc, dev)
        for page in PDFPage.get_pages(BytesIO(data), caching=False, check_extractable=False):
            n += 1
            if n > MAX_PAGES:
                break
            interp.process_page(page)
    except Exception as e:
        raise Fail("unreadable PDF: %s: %s" % (type(e).__name__, clean(e)))
    if dev.pages == 0:
        raise Fail("unreadable PDF: no pages found")
    return dev, n > MAX_PAGES


def check_pdf(R, A, data):
    dev, cut = pdf_chars(data)
    if cut:
        R.note("only the first %d pages were checked" % MAX_PAGES)
    spans = []
    for ch in dev.chars:
        prev = spans[-1] if spans else None
        key = (ch["page"], ch["font"], round(ch["size"], 2), ch["color"])
        if prev and prev["key"] == key and abs(ch["y0"] - prev["y0"]) <= 0.3 * ch["size"] and ch["x0"] >= prev["x0"] - 1:
            prev["text"] += ch["text"]
            prev["x1"] = ch["x1"]
        else:
            spans.append(dict(ch, key=key))
    if not dev.chars:
        R.note("the PDF has no text spans (an image-only page cannot be checked)")
    seen_sizes = {}
    for sp in spans:
        text = sp["text"].strip()
        if not text:
            continue
        where = "p%d '%s'" % (sp["page"], text[:40])
        base = re.sub(r"^[A-Z]{6}\+", "", sp["font"])
        size_px = sp["size"] * 4.0 / 3.0
        cx, cy = (sp["x0"] + sp["x1"]) / 2.0, sp["y0"] + sp["size"] * 0.3
        bg = A["bg"] or (255, 255, 255)
        for pg, rx0, ry0, rx1, ry1, rc in reversed(dev.rects):
            if pg == sp["page"] and rc is not None and rx0 <= cx <= rx1 and ry0 <= cy <= ry1 and (rx1 - rx0) * (ry1 - ry0) > 1:
                bg = rc
                break
        check_style(R, A, where, family=base, size=size_px, weight=pdf_weight(base), color=sp["color"], bg=bg, pdf=True)
        if A["embed"] and A["families"] and fam_ok(A, base, True) and not sp["emb"]:
            R.add("FALLBACK", where, "face %s is not embedded, a viewer may substitute it" % base, "an embedded face")
        if sp["x1"] > sp["w"] + 0.5 or min(sp["x0"], sp["x1"]) < -0.5 or sp["y0"] > sp["h"] + 0.5 or sp["y0"] < -0.5:
            R.add("WRAP", where, "text runs off the page edge (reaches %s pt on a %s pt wide page)" % (fnum(max(sp["x0"], sp["x1"])), fnum(sp["w"])),
                  "inside the page")
        seen_sizes.setdefault(round(size_px, 2), []).append(where)
    allsz = sorted(seen_sizes)
    for a, b in zip(allsz, allsz[1:]):
        if 0.05 < b - a <= 0.6:
            R.add("ROLE", "; ".join((seen_sizes[a][:1] + seen_sizes[b][:1])), "two near-identical sizes %s and %s" % (sz(a), sz(b)),
                  "one size for one role")
    R.note("PDF background is the fill behind each span, else the page background (white unless the allow-list says otherwise)")


# ---------- browser runner ----------

def run_browser(path):
    heavy = os.environ.get("SABHA_TYPO_HEAVY") or os.path.join(os.path.dirname(HERE), "bin", "sabha-heavy")
    runner = shlex.split(os.environ.get("SABHA_TYPO_RUNNER") or "node %s" % shlex.quote(os.path.join(HERE, "typography-computed.mjs")))
    try:
        timeout = int(os.environ.get("SABHA_TYPO_TIMEOUT", "180"))
    except ValueError:
        timeout = 180
    tmp = tempfile.mkdtemp(prefix="sabha-typo.")
    try:
        out = os.path.join(tmp, "computed.json")
        cmd = [heavy, "run", "typography", "--"] + runner + [os.path.abspath(path), out]
        try:
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise Fail("browser runner timed out after %d s (browser check not run)" % timeout)
        except OSError as e:
            raise Fail("cannot start the browser runner: %s" % clean(e))
        if r.returncode == 75:
            raise Fail("the heavy gate says wait (rc 75); the browser check did not run, try again later", 75)
        if r.returncode != 0:
            raise Fail("browser runner failed (rc %d): %s" % (r.returncode, clean(r.stdout.decode("utf-8", "replace").strip()[-300:])))
        if not os.path.exists(out):
            raise Fail("browser runner wrote no output file")
        return parse_json(read_file(out, "json"), "runner output")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------- output ----------

def render(R, A, target, mode, as_json, limit):
    total = R.count()
    lines, groups = [], []
    for key in sorted(R.order, key=lambda k: (CHECKS.index(k[0]), R.order.index(k)))[:limit]:
        check, found, allowed = key
        wheres = R.groups[key]
        groups.append({"check": check, "found": found, "nearest_allowed": allowed, "count": len(wheres), "where": wheres[:5]})
        more = " (+%d more)" % (len(wheres) - 3) if len(wheres) > 3 else ""
        lines.append("%s | where: %s%s | found: %s | nearest allowed: %s" % (check, "; ".join(wheres[:3]), more, found, allowed or "-"))
    notes = list(R.notes)
    if A["unknown"]:
        notes.append("unknown allow-list keys ignored: %s" % ", ".join(A["unknown"]))
    if len(R.order) > limit:
        notes.append("%d more finding groups not shown (raise --limit)" % (len(R.order) - limit))
    if as_json:
        txt = json.dumps({"target": target, "mode": mode, "findings": total, "groups": groups, "notes": notes,
                          "checks_off": A["off"]}, ensure_ascii=True, indent=1)
        return txt.replace("\x7f", "\\u007f"), total
    body = [clean("typography-check %s (%s): %d finding%s" % (target, mode, total, "" if total == 1 else "s"))]
    body += [clean(l) for l in lines]
    if A["off"]:
        body.append("checks off (not in the allow-list): " + ", ".join(A["off"]))
    body += ["note: " + clean(n) for n in notes]
    return "\n".join(body), total


def main(argv):
    if argv and argv[0] == "--self-test":
        os.execv("/bin/bash", ["bash", os.path.join(os.path.dirname(HERE), "tests", "test-typography-check.sh")])
    target = allow = kind = None
    as_json = browser = False
    limit = 200
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--allow", "--limit", "--type"):
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                raise Fail("%s needs a value" % a)
            v = argv[i + 1]
            i += 2
            if a == "--allow":
                allow = v
            elif a == "--type":
                kind = v
            else:
                if not v.isdigit() or int(v) < 1:
                    raise Fail("--limit needs a positive number")
                limit = int(v)
            continue
        if a == "--json":
            as_json = True
        elif a == "--browser":
            browser = True
        elif a.startswith("--"):
            raise Fail("unknown option %s" % clean(a))
        elif target is None:
            target = a
        else:
            raise Fail("only one file at a time")
        i += 1
    allow = allow or os.environ.get("SABHA_TYPO_ALLOW")
    if target is None or not allow:
        raise Fail(USAGE + " (the allow-list comes from --allow or SABHA_TYPO_ALLOW)")
    if kind is None:
        kind = {".pdf": "pdf", ".html": "html", ".htm": "html", ".json": "computed"}.get(os.path.splitext(target)[1].lower())
        if kind is None:
            raise Fail("cannot tell the input type from %s; pass --type pdf|html|computed" % clean(target))
    if kind not in ("pdf", "html", "computed"):
        raise Fail("--type must be pdf, html or computed")
    if browser and kind != "html":
        raise Fail("--browser only applies to an html input")
    A = load_allow(allow)
    R = Report()
    raw = read_file(target, "json" if kind == "computed" else kind)
    if kind == "pdf":
        check_pdf(R, A, raw)
    elif kind == "computed":
        check_computed(R, A, parse_json(raw, "computed-styles file"))
    else:
        check_html_static(R, A, target, raw)
        if browser:
            check_computed(R, A, run_browser(target))
    text, total = render(R, A, os.path.basename(target), kind + ("+browser" if browser else ""), as_json, limit)
    sys.stdout.write(text + "\n")
    return 1 if total else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Fail as e:
        sys.stderr.write("sabha-typography-check: %s\n" % clean(e))
        sys.exit(e.rc)
    except RecursionError:
        sys.stderr.write("sabha-typography-check: input too deeply nested\n")
        sys.exit(2)
