---
name: sabha-typography-check
description: Use when a reviewer or builder must check fonts and text styling (family, size, weight, colour, contrast, wrapping) of a UI change, an export (PDF or HTML) or an artifact before it ships, or when asked about typography inconsistencies.
---

# Typography check

Source: `bin/sabha-typography-check` (header of `tools/typography-check.py`), `template/typography.example.json`,
RULES.md rule 6 (nothing leaves the machine without a yes).

## When to run it

- A UI pull request that touches CSS, styles or a component's text: run it on the built page or the changed HTML.
- An export before it is handed on: a PDF report or an HTML report. Run it on the file, not on the template, so the
  faces that really loaded are what is checked.
- An artifact before it is published: save the page to a file first, then run it on the file.
- When someone reports "the font looks different" or "text is cut off": the report says which rule or span.

Not for: screenshots (version 1 reads files, not pixels), spelling, copy, layout beyond text wrapping.

## Run it

1. Find the allow-list: the project's own, or copy `template/typography.example.json` and put the project's tokens in.
   A key left out switches that check off, and the report says so ("checks off"); read that line.
2. PDF: `bin/sabha-typography-check report.pdf --allow typography.json`. Needs the repo-local `.venv` with
   `pdfminer.six` (the README gives the `uv` line); never a global install. No browser is started.
3. HTML or artifact, no browser: `bin/sabha-typography-check page.html --allow typography.json`. This lints the CSS
   (`<style>`, local `<link>` sheets, `style=""`). It opens the named file and the allow-list, and a linked stylesheet or
   `@font-face` file only when it stays inside the folder of the named file (symlinks resolved); anything outside is
   skipped with the note "not read: outside the input folder". Remote URLs are never fetched; images and `@import`
   files are never opened.
4. HTML with computed styles: add `--browser`. It is a heavy job; the tool runs the runner only through
   `sabha-heavy run typography --`. Exit 75 means the gate said wait: nothing ran, say so and try later; never force
   the slot. A dump from an earlier run can be checked without a browser: `... computed.json --allow ...`.
   Page scripts are OFF by default and the runner aborts every request that leaves the page's folder. `--allow-scripts`
   turns the page's JavaScript on (for styles that scripts set) and prints a warning on every run: use it
   only on files you trust. If Chrome or playwright is missing the tool says so and exits 2.
5. `--json` gives the same report as data; `--limit N` caps the groups shown (the count stays whole); `--strict` makes
   UNKNOWN lines count as findings; `--help` prints the full usage.

Exit 0 = no findings, 1 = findings (or UNKNOWN under `--strict`), 2 = bad input (missing file, empty file, a page with
no CSS, a PDF with no text, unreadable PDF, bad allow-list, Chrome missing), 75 = wait.

## Read the report

One line per group of equal findings: `CHECK | where: ... | found: ... | nearest allowed: ...`.

| Check | Means | Look at |
| --- | --- | --- |
| FAMILY | the first family is not on the list | the selector or the PDF page and text |
| FALLBACK | the declared face did not load: `@font-face` file missing, family used but never declared, face not embedded in the PDF; also a font stack that holds none of the fallbacks the allow-list names for its first family | the font files, the `src` paths and the stack |
| SIZE, WEIGHT, COLOR | off the scale; the nearest allowed value is shown | the token the author meant |
| CONTRAST | text against its background is below the minimum ratio | both colours; the background of a PDF span is the fill behind it |
| LINEHEIGHT | outside the allowed range | the rule or element |
| UNKNOWN | a colour that could not be resolved (`currentColor` with no value, a gradient or image background, an alpha colour over an unknown background, a form the tool does not read): its contrast is NOT checked | the value; it does not change the exit code unless `--strict` |
| WRAP | text runs off the page, is clipped, is cut with an ellipsis where it should wrap, or the page scrolls sideways | the box width and `overflow` |
| ROLE | one role styled two ways: two sizes or weights for one heading level, or two near-identical sizes in a PDF | which of the two the design means |

Check the "note:" lines too. They name what was not checked (external stylesheets, template placeholders, sizes in em,
page width without `--browser`). A clean result is clean only for what was checked.

## What to do with a finding

A finding is a question for the owner or the designer, never an auto-fix. The design is the owner's: a size that is off
the list may be a missing token, not a mistake. Do not edit the styles to silence the report, and do not add a value to
the allow-list yourself. Write the finding as a question (what was found, where, the nearest allowed value, your
recommendation) in the PR notes or the questions file, and let the owner answer. A change to the allow-list is its own
change, approved by whoever owns the design.

## Limits

Static lint cannot see inherited sizes in em, media-query results, or JavaScript-set styles; the computed path can
(JavaScript-set styles only with `--allow-scripts`).
Colours: hex (3, 4, 6, 8 digits), `rgb()`/`rgba()` with numbers or percent, `hsl()`/`hsla()`, 15 named colours and
`transparent` are resolved; alpha is blended over the known background (a translucent background over the page
background). Everything else is reported UNKNOWN, never passed silently. A PDF span drawn with a pattern colour is not
checked and not reported. Font stacks: only the first family and the allow-list's fallbacks for it are checked.
PDF weight is read from the face name (Bold, SemiBold, Medium ...); a face with no style word counts as 400.
Never run in a real browser: `tools/typography-computed.mjs` was only run against a fake playwright (tests), never
against a real Chrome. The PDF path never ran on a real Chrome PDF (the fixtures are base-14 PDFs written by a script).
The first real run on each removes the matching sentence here, in the README entry, in `--help` and in the PR text.
