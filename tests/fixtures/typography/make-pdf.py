#!/usr/bin/env python3
"""Writes the two fixture PDFs (stdlib only, base-14 faces, uncompressed streams). Run: python3 make-pdf.py <outdir>
faulty.pdf carries one known fault per line; clean.pdf carries only allowed text."""
import os
import sys


def text(font, size, rgb, x, y, s):
    r, g, b = rgb
    return "BT /%s %s Tf %s %s %s rg %s %s Td (%s) Tj ET\n" % (font, size, r, g, b, x, y, s)


NAVY = (0.09, 0.173, 0.31)
RED = (1, 0, 0)
PALE = (0.8, 0.8, 0.8)
SLATE = (0.263, 0.325, 0.439)


def build(pages):
    objs = {}
    n_pages = len(pages)
    objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    kids = " ".join("%d 0 R" % (10 + i) for i in range(n_pages))
    objs[2] = "<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, n_pages)
    objs[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    objs[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>"
    objs[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"
    for i, content in enumerate(pages):
        objs[10 + i] = ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font "
                        "<< /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> >>" % (30 + i))
        objs[30 + i] = "<< /Length %d >>\nstream\n%sendstream" % (len(content), content)
    out = "%PDF-1.4\n"
    offs = {}
    for k in sorted(objs):
        offs[k] = len(out)
        out += "%d 0 obj\n%s\nendobj\n" % (k, objs[k])
    top = max(objs) + 1
    xref = len(out)
    out += "xref\n0 %d\n0000000000 65535 f \n" % top
    for k in range(1, top):
        out += ("%010d 00000 n \n" % offs[k]) if k in offs else "0000000000 65535 f \n"
    out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (top, xref)
    return out.encode("ascii")


faulty1 = (
    text("F1", 12, NAVY, 50, 740, "Clean body text")
    + text("F2", 12, NAVY, 50, 710, "Serif intruder")
    + text("F1", 13.3, NAVY, 50, 680, "Off scale size")
    + text("F3", 12, NAVY, 50, 650, "Bold weight")
    + text("F1", 12, RED, 50, 620, "Red text")
    + text("F1", 12, PALE, 50, 590, "Pale grey text")
    + "0.12 0.176 0.31 rg 40 545 300 22 re f\n"
    + text("F1", 12, NAVY, 50, 551, "Dark on dark")
    + text("F1", 12, NAVY, 560, 500, "Runs off the page edge")
    + text("F1", 18, NAVY, 50, 460, "Heading A")
    + text("F1", 18.2, NAVY, 50, 430, "Heading B")
)
faulty2 = text("F1", 12, SLATE, 50, 740, "Second page text")
clean1 = text("F1", 12, NAVY, 50, 740, "Clean body text") + text("F1", 18, SLATE, 50, 700, "Clean heading")

out = sys.argv[1] if len(sys.argv) > 1 else "."
for name, pages in (("faulty.pdf", [faulty1, faulty2]), ("clean.pdf", [clean1])):
    with open(os.path.join(out, name), "wb") as fh:
        fh.write(build(pages))
