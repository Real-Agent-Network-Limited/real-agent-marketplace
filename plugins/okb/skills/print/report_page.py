"""Builds an executive report's page from its Markdown, for print_pdf to print.

Usage: python3 report_page.py <report.md> <report.html> --for=<audience> --by=<name> --read-at=<when>
       --owner=<name>

The page carries the report's header lines, and its style inlined from report.css, in the plain
style. The figure blocks of the report skill's section 6 pass through as they are written.
"""
import argparse
import html
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from md_page import convert, inline  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source"); ap.add_argument("out")
    ap.add_argument("--for", dest="audience", required=True)
    ap.add_argument("--by", dest="author", required=True)
    ap.add_argument("--read-at", dest="read_at", required=True)
    ap.add_argument("--owner", required=True)
    args = ap.parse_args()
    if os.path.exists(args.out):
        sys.exit(f"{args.out} already exists. Name a new file; nothing is replaced.")
    with open(args.source, encoding="utf-8") as f:
        title, body = convert(f.read())
    if not title:
        sys.exit("the report has no title: start it with a '# ' heading")
    with open(os.path.join(HERE, "report.css"), encoding="utf-8") as f:
        css = f.read()
    page = f'''<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
{css}
</style>
</head>
<body>
<main>
  <h1>{inline(title)}</h1>
  <p class="meta"><strong>Prepared for:</strong> {html.escape(args.audience)}<br>
  <strong>Prepared by:</strong> {html.escape(args.author)}<br>
  <strong>Read from OKB (organisational knowledge base):</strong> {html.escape(args.read_at)}<br>
  <strong>Project owner:</strong> {html.escape(args.owner)}</p>
{chr(10).join("  " + b for b in body)}
</main>
</body>
</html>
'''
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print(f"written {args.out}; {len(body)} blocks; plain style")


if __name__ == "__main__":
    main()
