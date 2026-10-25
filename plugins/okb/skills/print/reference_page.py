"""Write the glossary, with its classes and relationships, or the data dictionary, as an A4 page.

Usage: python3 reference_page.py <reference.json> <page.html>

The input is what okb_get_reference returns: {"part": "glossary", "rows": [...]} or
{"part": "dictionary", "tables": [...], "columns": [...], "sources": [...]}. The page is printed from
the rows as they stand, so it holds the current glossary or data dictionary. It sets @page to A4, for
the print skill's print_pdf.py. Beside the page, the board skill's `page_check.py` writes its
outline, and its picture where a Chromium browser is found.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "board"))
import a4  # noqa: E402
import page_check  # noqa: E402

esc = a4.esc


def names(row):
    return ", ".join(row.get("other_names") or [])


def glossary(rows):
    classes = [r for r in rows if r.get("kind") == "class"]
    relationships = [r for r in rows if r.get("kind") == "relationship"]
    terms = [r for r in rows if r.get("kind") == "term"]
    body = [f"<h1>Glossary</h1>",
            f'<p class="meta">Printed from OKB on {esc(a4.printed_on())}: {len(terms)} terms, {len(classes)} classes and '
            f"{len(relationships)} relationships. A class is a kind of thing records and the file search graph are about. "
            f"A relationship names the classes at its two ends.</p>"]
    lines = ["# Glossary", "", f"{len(terms)} terms, {len(classes)} classes, {len(relationships)} relationships.", ""]
    for heading, items, ends in (("Classes", classes, False), ("Relationships", relationships, True), ("Terms", terms, False)):
        body.append(f"<h2>{heading}</h2>")
        lines += [f"## {heading}", ""]
        if not items:
            body.append(f'<p class="none">No {heading.lower()} yet.</p>')
            lines += [f"None.", ""]
            continue
        head = "<tr><th>Name</th>" + ("<th>From</th><th>To</th>" if ends else "") + "<th>Meaning</th><th>Other names</th></tr>"
        cells = []
        for r in items:
            cells.append(f"<tr><td><b>{esc(r['term'])}</b></td>" + (f"<td>{esc(r.get('from_class'))}</td><td>{esc(r.get('to_class'))}</td>" if ends else "")
                         + f"<td>{esc(r.get('definition'))}</td><td>{esc(names(r))}</td></tr>")
            lines.append(f"- {r['term']}" + (f" ({r.get('from_class')} to {r.get('to_class')})" if ends else "") + f": {r.get('definition')}"
                         + (f" Other names: {names(r)}." if names(r) else ""))
        body.append(f"<table><thead>{head}</thead><tbody>{''.join(cells)}</tbody></table>")
        lines.append("")
    findings = [] if rows else ["The glossary holds no terms yet. It grows as terms are approved in interviews and sessions."]
    counts = {"terms": len(terms), "classes": len(classes), "relationships": len(relationships)}
    return "Glossary", "\n".join(body), lines, findings, counts


def dictionary(value):
    tables, columns, sources = value.get("tables") or [], value.get("columns") or [], value.get("sources") or []
    body = [f"<h1>Data dictionary</h1>",
            f'<p class="meta">Printed from OKB on {esc(a4.printed_on())}: {len(tables)} record kinds and {len(columns)} fields. '
            f"Each record kind holds one glossary class, and each field its type, whether it is required, the glossary term it holds and the systems it comes from.</p>"]
    lines = ["# Data dictionary", "", f"{len(tables)} record kinds, {len(columns)} fields.", ""]
    for t in tables:
        mine = [c for c in columns if c.get("table") == t.get("table")]
        body.append(f"<h2>{esc(t.get('table'))}</h2><p>Class: <b>{esc(t.get('class'))}</b>. {esc(t.get('meaning'))}</p>")
        lines += [f"## {t.get('table')}", "", f"Class: {t.get('class')}. {t.get('meaning')}", ""]
        if not mine:
            body.append('<p class="none">No fields yet.</p>')
            lines += ["No fields yet.", ""]
            continue
        cells = []
        for c in mine:
            came = "; ".join(f"{s.get('system')}: {s.get('field')}" for s in sources if s.get("table") == c.get("table") and s.get("column") == c.get("column"))
            cells.append(f"<tr><td><b>{esc(c.get('column'))}</b></td><td>{esc(c.get('type'))}</td><td>{'Yes' if c.get('required') else 'No'}</td>"
                         f"<td>{esc(c.get('term') or '')}</td><td>{esc(c.get('meaning'))}</td><td>{esc(came)}</td></tr>")
            lines.append(f"- {c.get('column')} · {c.get('type')} · {'required' if c.get('required') else 'optional'}"
                         + (f" · term {c.get('term')}" if c.get("term") else "") + f": {c.get('meaning')}" + (f" From {came}." if came else ""))
        body.append("<table><thead><tr><th>Field</th><th>Type</th><th>Required</th><th>Term</th><th>Meaning</th><th>Comes from</th></tr></thead>"
                    f"<tbody>{''.join(cells)}</tbody></table>")
        lines.append("")
    findings = [] if tables else ["The data dictionary holds no record kinds yet."]
    return "Data dictionary", "\n".join(body), lines, findings, {"record_kinds": len(tables), "fields": len(columns)}


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    source, page_path = sys.argv[1:]
    value = a4.read(source)
    part = value.get("part") if isinstance(value, dict) else None
    if part == "glossary" and isinstance(value.get("rows"), list):
        title, body, lines, findings, counts = glossary(value["rows"])
    elif part == "dictionary" and isinstance(value.get("tables"), list):
        title, body, lines, findings, counts = dictionary(value)
    else:
        raise SystemExit("the file is not okb_get_reference's result for the glossary or the dictionary; no page was written")
    page = a4.page(title, body, "reference-data", {"part": part, "counts": counts})
    with open(page_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    page_check.write(page_path, lines + page_check.findings_lines(findings))
    checked = f"outline written; {len(findings)} findings; {page_check.picture(page_path, 1600)}"
    print(f"wrote {page_path} ({len(page.encode())} bytes): {title}, " + ", ".join(f"{n} {k.replace('_', ' ')}" for k, n in counts.items()) + f"; {checked}")


if __name__ == "__main__":
    main()
