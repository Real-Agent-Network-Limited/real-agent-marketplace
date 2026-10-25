"""Print a page to an A4 PDF, or a deck's page of slides to a PDF of 16:9 pages.

Usage: python3 print_pdf.py <page.html> <page.pdf> [--size=slide]

The page is opened where it is, so the pictures beside it print, in a Chromium browser run
headless: Google Chrome, Chromium or Microsoft Edge, as the board skill's `page_check.py` finds
it. Each picture, style or other file the page loads is a file directly beside it in the agent
folder, or a web address; otherwise the print is refused. The page sets its own paper with
`@page { size: A4 }`; without it the browser prints US Letter, and the print is refused. With --size=slide,
the page is a deck: each `<section class="slide">` prints as one 16:9 page, and the print is refused when the
pages are not 16:9 or their count is not the slides'. The PDF holds a picture for each PNG, JPEG, GIF or WebP file the page names,
or the print is refused; a picture held inside the page counts by its data-file name. Prints the page count, the paper and the pictures, as JSON, with a finding for
each Markdown mark in the printed text: a heading's "#", "**", a backtick, a line starting "- " and
"[text](address)". pdf_text.py reads the text.
"""
import json
import os
import re
import subprocess
import sys
from urllib.parse import unquote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "board"))
import page_check  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdf_text  # noqa: E402

# A4 is 595 by 842 points; the browser rounds it to within a point or two.
A4 = (595, 842)
IMAGE = re.compile(rb"/Subtype\s*/Image\b")
PICTURE = re.compile(r"(?i)\.(png|jpe?g|gif|webp)$")
# A slide in a comment, or inside a <script>, <style>, <template> or <textarea>, prints as no page of its own.
HIDDEN = re.compile(r"<!--.*?-->|<(script|style|template|textarea)\b[^>]*>.*?</\1\s*>", re.I | re.S)
SLIDE = re.compile(r"""<section\b[^>]*\bclass\s*=\s*["'](?:[^"']*\s)?slide(?:\s[^"']*)?["']""", re.I)
MEDIA_BOX = re.compile(rb"/MediaBox\s*\[\s*[-\d.]+\s+[-\d.]+\s+([-\d.]+)\s+([-\d.]+)\s*\]")


# The Markdown marks a printed document never shows, each with the name a finding gives it.
MARKS = [
    (re.compile(r"^#{1,6}\s"), "a heading's #"),
    (re.compile(r"\*\*"), "**"),
    (re.compile(r"`"), "a backtick"),
    (re.compile(r"^-\s"), "a line starting - "),
    (re.compile(r"\[[^\]]+\]\([^)\s]+\)"), "[text](address)"),
]


def markdown_findings(pages):
    """Each Markdown mark in the printed prose, with its page and line. Text in a mono font, such as
    code, is left out, and a line starting "- " counts only where it starts a block, not where a
    paragraph wraps onto it."""
    found = []
    for page, lines in enumerate(pages, 1):
        for line, printed in enumerate(lines, 1):
            prose = printed["prose"].strip()
            for pattern, mark in MARKS:
                if pattern.search(prose) and (mark != "a line starting - " or printed["starts_block"]):
                    found.append({"page": page, "line": line, "mark": mark, "text": printed["text"].strip()[:120]})
    return found


def read_findings(pdf):
    """The Markdown findings, or None where the PDF's text cannot be read."""
    try:
        return markdown_findings(pdf_text.pages(pdf, prose=True))
    except Exception:  # noqa: BLE001 - a PDF the reader does not expect still prints
        return None


def is_a4(width, height):
    short, long = sorted((width, height))
    return abs(short - A4[0]) <= 2 and abs(long - A4[1]) <= 2


def is_slide(width, height):
    """Whether a page is 16:9, landscape, as the print skill's deck.css sets it."""
    return height > 0 and abs(width / height - 16 / 9) <= 0.01


def is_picture(head):
    """Whether a file's first bytes start a PNG, JPEG, GIF or WebP picture."""
    return (head.startswith(b"\x89PNG\r\n\x1a\n") or head.startswith(b"\xff\xd8\xff") or head[:6] in (b"GIF87a", b"GIF89a")
            or (head[:4] == b"RIFF" and head[8:12] == b"WEBP"))


def files(page):
    """The pictures the page loads beside it, and the problems with the files it loads: each must be
    a file directly beside the page, or a web address."""
    with open(page, encoding="utf-8", errors="replace") as f:
        text = f.read()
    # The files the browser loads: each tag's src, quoted or not, a <link>'s href, and each CSS url().
    # An <a>'s href is a link in the text, which printing never fetches.
    names = []
    for tag, attributes in re.findall(r"<([A-Za-z][\w-]*)\b([^>]*)>", text):
        for attribute, double, single, bare in re.findall(r"""\b(src|href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""", attributes):
            if attribute.lower() == "href" and tag.lower() != "link":
                continue
            names.append(double or single or bare)
    names += [a or b for a, b in re.findall(r"""url\(\s*(?:["']([^"']+)["']|([^"')\s]+))\s*\)""", text)]
    problems, found = [], set()
    # A picture held inside the page, as report_page and embed_pictures write it, is named by its data-file.
    for attributes in re.findall(r"<img\b([^>]*)>", text, re.I):
        held = re.search(r"""\bdata-file\s*=\s*["']([^"']+)["']""", attributes)
        if held and re.search(r"""\bsrc\s*=\s*["']data:image/""", attributes, re.I):
            found.add(held.group(1))
    for name in names:
        name = unquote(name.strip())
        if re.match(r"(?i)^(https?:|data:|mailto:|#)", name):
            continue
        name = re.split(r"[?#]", name)[0]
        if re.match(r"(?i)^file:", name) or "/" in name or "\\" in name or name in (".", "..") or name.startswith("."):
            problems.append(f"{name} is not a file directly beside the page")
        elif not os.path.isfile(os.path.join(os.path.dirname(os.path.abspath(page)), name)):
            problems.append(f"{name} is not in the agent folder")
        elif PICTURE.search(name):
            with open(os.path.join(os.path.dirname(os.path.abspath(page)), name), "rb") as f:
                head = f.read(12)
            if is_picture(head):
                found.add(name)
            else:
                problems.append(f"{name} is not a PNG, JPEG, GIF or WebP picture")
    return found, sorted(set(problems))


def main(page, pdf, size="A4"):
    named, problems = files(page)
    if problems:
        sys.exit("the page names files it cannot print: " + "; ".join(problems))
    found = page_check.browser()
    if not found:
        sys.exit("no Chrome, Chromium or Edge on this computer")
    url = "file:///" + os.path.abspath(page).replace(os.sep, "/").lstrip("/")
    page_check.clear(pdf)
    try:
        # The two keychain switches keep the browser off the macOS keychain, as page_check.py does.
        # Both header switches are given: older browsers know only the first.
        subprocess.run([found, "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
                        "--use-mock-keychain", "--password-store=basic",
                        "--print-to-pdf-no-header", "--no-pdf-header-footer",
                        "--virtual-time-budget=10000", f"--print-to-pdf={os.path.abspath(pdf)}", url],
                       capture_output=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as err:
        sys.exit(f"the browser did not finish ({err})")
    if not page_check.written(pdf):
        sys.exit("the browser wrote no PDF")
    with open(pdf, "rb") as f:
        body = f.read()
    sizes = [(float(w), float(h)) for w, h in MEDIA_BOX.findall(body)]
    if not sizes:
        sys.exit("the PDF holds no pages")
    if size == "slide":
        with open(page, encoding="utf-8", errors="replace") as f:
            slides = len(SLIDE.findall(HIDDEN.sub("", f.read())))
        wrong = [s for s in sizes if not is_slide(*s)]
        if wrong:
            w, h = wrong[0]
            sys.exit(f"the deck printed at {round(w)} by {round(h)} points, not 16:9. "
                     "Put the print skill's deck.css in the page's style, then print it again")
        if len(sizes) != slides:
            sys.exit(f"the deck printed {len(sizes)} pages for its {slides} slides. "
                     "Keep each slide's content inside its section, then print it again")
    wrong = [] if size == "slide" else [s for s in sizes if not is_a4(*s)]
    if wrong:
        w, h = wrong[0]
        sys.exit(f"the page printed at {round(w)} by {round(h)} points, not A4. "
                 "Put @page { size: A4; } in the page's style, then print it again")
    printed = len(IMAGE.findall(body))
    if printed < len(named):
        sys.exit(f"the PDF holds {printed} of the {len(named)} pictures the page names: {', '.join(sorted(named))}")
    w, h = sizes[0]
    paper = "16:9 slide" if size == "slide" else f"A4 {'landscape' if w > h else 'portrait'}"
    print(json.dumps({"pages": len(sizes), "paper": paper, "pictures": sorted(named),
                      "markdown": read_findings(pdf)}))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] != "--size=slide"):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], "slide" if len(sys.argv) == 4 else "A4")
