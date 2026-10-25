"""Turns Markdown into the blocks of a printed page, for the executive report.

It converts headings, paragraphs, lists one level deep, quotations, tables, fenced code, bold,
italic, code and links. A block that starts with "<", such as a report's figure of `.shots` and
`.crop`, passes through unchanged up to the next blank line. The first "# " heading is the title.
"""
import html
import re

LIST = re.compile(r"^(- |\* |\d+\. )")
SUB = re.compile(r"^\s+(- |\* |\d+\. )")


def inline(text):
    """A line's text as HTML: code first, so nothing inside code is read as a mark."""
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if len(part) > 1 and part.startswith("`") and part.endswith("`"):
            out.append("<code>" + html.escape(part[1:-1], quote=False) + "</code>")
            continue
        t = html.escape(part, quote=False)
        t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
        t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", t)
        # The text is escaped already, so the address takes only its quote marks escaped.
        t = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>', t)
        out.append(t)
    return "".join(out)


def plain_heading(level, text):
    """The default heading: "## " is h2 and "### " is h3."""
    return f"<h{level}>{inline(text)}</h{level}>"


def plain_paragraph(text):
    return f"<p>{inline(text)}</p>"


def convert(markdown, heading=plain_heading, paragraph=plain_paragraph, quote_class=""):
    """The page's title and its blocks of HTML. `heading` and `paragraph` give a page its own classes."""
    lines = markdown.replace("\r\n", "\n").split("\n")
    body, title, i = [], "", 0

    def para_end(j):
        return (j >= len(lines) or not lines[j].strip() or re.match(r"^(#{1,6} |>|\||```)", lines[j])
                or LIST.match(lines[j]) or SUB.match(lines[j]))

    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1; continue
        if line.startswith("```"):
            j, buf = i + 1, []
            while j < len(lines) and not lines[j].startswith("```"):
                buf.append(lines[j]); j += 1
            body.append("<pre>" + html.escape("\n".join(buf)) + "</pre>"); i = j + 1; continue
        if line.startswith("<"):
            buf = []
            while i < len(lines) and lines[i].strip():
                buf.append(lines[i]); i += 1
            body.append("\n".join(buf)); continue
        m = re.match(r"^(#{1,6}) +(.*?)(?:\s+#+)?\s*$", line)
        if m:
            level, text = len(m.group(1)), m.group(2)
            if level == 1 and not title:
                title = text
            else:
                body.append(heading(level, text))
            i += 1; continue
        if line.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].startswith(">"):
                buf.append(lines[i][1:].strip()); i += 1
            cls = f' class="{quote_class}"' if quote_class else ""
            body.append(f"<blockquote{cls}>" + inline(" ".join(b for b in buf if b)) + "</blockquote>"); continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
            head = rows[0]
            data = [r for r in rows[1:] if not all(re.match(r"^:?-+:?$", c) for c in r)]
            t = "<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
            t += "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in data) + "</tbody></table>"
            body.append(t); continue
        if LIST.match(line):
            tag = "ol" if re.match(r"^\d+\. ", line) else "ul"
            items = []
            while i < len(lines) and (LIST.match(lines[i]) or lines[i].startswith("  ")
                                      or (not lines[i].strip() and i + 1 < len(lines) and lines[i + 1].startswith("  "))):
                cur = lines[i]
                if LIST.match(cur):
                    items.append({"text": LIST.sub("", cur), "sub": [], "extra": []})
                elif SUB.match(cur):
                    items[-1]["sub"].append((re.match(r"^\s+\d+\. ", cur) is not None, SUB.sub("", cur)))
                elif cur.strip():
                    items[-1]["extra"].append(cur.strip())
                i += 1
            out = f"<{tag}>"
            for it in items:
                out += "<li>" + inline(it["text"])
                if it["sub"]:
                    sub = "ol" if it["sub"][0][0] else "ul"
                    out += f"<{sub}>" + "".join(f"<li>{inline(s)}</li>" for _, s in it["sub"]) + f"</{sub}>"
                for extra in it["extra"]:
                    out += f"<p>{inline(extra)}</p>"
                out += "</li>"
            body.append(out + f"</{tag}>"); continue
        buf = [line]; i += 1
        while not para_end(i):
            buf.append(lines[i]); i += 1
        body.append(paragraph(" ".join(x.strip() for x in buf)))
    return title, body
