#!/usr/bin/env python3
"""Add, remove and change rows on named sheets of an .xlsx workbook, into a new workbook.

    edit_workbook.py WORKBOOK NEW EDITS.json

EDITS.json is a list of edits, each {"sheet", "action", "match", "row"}, or an object {"edits", "names",
"formats", "rules"}, as workbook_model.py gives them. `action` is add, remove or change. `match` names
one row by column heading and value; `row` gives a value for each heading an added row fills, or each
heading a change sets. Row 1 of each sheet holds its headings. A value starting with "=" is a formula,
one starting with "'=" is the text after the quote, and a number, true or false is written as one.

A sheet whose rows a formula, a name, an input rule or a format names, such as B2 or Inputs!B2, keeps its row
numbers: an added row goes after its last row, and a remove is refused. A whole column, such as A:A,
names no row. A workbook with a formula or a name recalculates when it opens, and each formula that
names a row has its saved result taken out, so every program works it out again.

Every edit is checked before anything is written. On any problem, nothing is written, every
problem is printed to stderr, and the exit status is 1. Otherwise the new workbook is written and
the rows added, removed and changed on each sheet are printed as JSON.

Only each edited sheet's rows are rewritten, as inline strings; every other byte of the workbook is
copied as it was, except those saved formula results. The sheet's dimension, its filter's range and the filter's defined name follow the
new last row.
"""

import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr, unescape

from workbook_model import Styles, add_names, add_rules, cells_of, formula_cell, formula_problems, is_formula, literal, model_problems, name_sheet, recalculate_on_open, references, without_results

MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
Q = "{%s}" % MAIN
ACTIONS = ("add", "remove", "change")
# Parts of a sheet that name cells by row; a sheet holding one is refused rather than shifted. In a model,
# whose rows keep their numbers, a sheet may hold input rules.
ROW_REFERENCES = ("mergeCells", "hyperlinks", "conditionalFormatting", "dataValidations", "tableParts")
MODEL_REFERENCES = ("mergeCells", "hyperlinks", "conditionalFormatting", "tableParts")


def column_number(letters):
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n


def column_letters(n):
    out = ""
    while n:
        n, rem = divmod(n - 1, 26)
        out = chr(65 + rem) + out
    return out


def split_ref(ref):
    m = re.fullmatch(r"([A-Z]+)(\d+)", ref or "")
    return (m.group(1), int(m.group(2))) if m else (None, None)


def sheet_parts(book):
    """Each sheet's name, in workbook order, with its part's path in the zip."""
    workbook = ET.fromstring(book.read("xl/workbook.xml"))
    rels = ET.fromstring(book.read("xl/_rels/workbook.xml.rels"))
    targets = {r.get("Id"): r.get("Target") for r in rels.iter("{%s}Relationship" % PKG)}
    parts = []
    for sheet in workbook.iter(Q + "sheet"):
        target = targets.get(sheet.get("{%s}id" % REL), "")
        parts.append((sheet.get("name"), target.lstrip("/") if target.startswith("/") else "xl/" + target))
    return parts


def shared_strings(book):
    try:
        root = ET.fromstring(book.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    return ["".join(t.text or "" for t in si.iter(Q + "t")) for si in root.iter(Q + "si")]


def cell_text(cell, strings):
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(t.text or "" for t in cell.iter(Q + "t"))
    value = cell.find(Q + "v")
    text = value.text if value is not None and value.text is not None else ""
    if kind == "s" and text.isdigit() and int(text) < len(strings):
        return strings[int(text)]
    return text


def serialise(element, prefixes):
    """An element as XML, with the sheet's own prefixes and the main namespace as the default."""
    def name(tag):
        if tag.startswith(Q):
            return tag[len(Q):]
        m = re.fullmatch(r"\{(.*)\}(.*)", tag)
        return f"{prefixes[m.group(1)]}:{m.group(2)}" if m else tag
    attrs = "".join(f" {name(k)}={quoteattr(v)}" for k, v in element.attrib.items())
    inner = escape(element.text or "") + "".join(serialise(child, prefixes) + escape(child.tail or "") for child in element)
    return f"<{name(element.tag)}{attrs}>{inner}</{name(element.tag)}>" if inner else f"<{name(element.tag)}{attrs} />"


def value_cell(ref, cell):
    """A cell an edit wrote: a formula, a number, true or false, or text."""
    value, style = cell.get("value", cell["text"]), cell["style"]
    if is_formula(value):
        return formula_cell(ref, value, style)
    s = f' s="{style}"' if style is not None else ""
    if isinstance(value, bool):
        return f'<c r="{ref}"{s} t="b"><v>{1 if value else 0}</v></c>'
    if isinstance(value, (int, float)):
        return f'<c r="{ref}"{s}><v>{value!r}</v></c>'
    if cell["text"]:
        return inline_cell(ref, literal(cell["text"]), style)
    return f'<c r="{ref}"{s}/>' if style is not None and cell.get("formatted") else ""


def inline_cell(ref, text, style):
    s = f' s="{style}"' if style is not None else ""
    space = ' xml:space="preserve"' if text != text.strip() else ""
    return f'<c r="{ref}"{s} t="inlineStr"><is><t{space}>{escape(text)}</t></is></c>'


class Sheet:
    def __init__(self, name, xml, strings, model=False, sheets=(), names=()):
        self.name = name
        # A sheet whose rows are named keeps their numbers; sheets and names are what formulas may use.
        self.model, self.sheets, self.names = model, sheets, names
        self.xml = xml
        # The prefixes the sheet's root tag declares. A sheet may start with an XML declaration, so the
        # root tag is found by name, not as the first tag.
        root = xml.find("<worksheet")
        self.prefixes = {uri: p for p, uri in re.findall(r'xmlns:(\w+)="([^"]+)"', xml[root: xml.find(">", root)])}
        # The xml prefix is built into XML, as in xml:space, and is never declared.
        self.prefixes["http://www.w3.org/XML/1998/namespace"] = "xml"
        self.problems = []
        m = re.search(r"<sheetData\s*/>|<sheetData>.*?</sheetData>", xml, re.S)
        self.span = m.span()
        # The sheet's root tag, closed, so the rows parse with every prefix the sheet declares.
        head = xml[xml.find("<worksheet"): xml.find(">", xml.find("<worksheet")) + 1].rstrip("/>").rstrip() + ">"
        data = ET.fromstring(head + m.group(0) + "</worksheet>").find(Q + "sheetData")
        self.rows = []  # each: {"attrs", "cells": {column: {"element" or "text", "style"}}}
        for row in data.findall(Q + "row"):
            cells = {}
            for cell in row.findall(Q + "c"):
                col, _ = split_ref(cell.get("r"))
                cells[column_number(col)] = {"element": cell, "text": cell_text(cell, strings), "style": cell.get("s")}
            attrs = {k: v for k, v in row.attrib.items() if k not in ("r", "spans")}
            self.rows.append({"number": int(row.get("r")), "attrs": attrs, "cells": cells})
        # Row 1 holds the headings, and every row after it is a row of the sheet's data.
        has_heading = bool(self.rows) and self.rows[0]["number"] == 1
        self.head = self.rows[:1] if has_heading else []
        self.body = self.rows[1:] if has_heading else self.rows
        heading = self.head[0]["cells"] if self.head else {}
        self.headings = {c["text"].strip(): col for col, c in heading.items() if c["text"].strip()}
        firsts = [self.text(r, 1).casefold() for r in self.body if self.text(r, 1)]
        self.ordered = firsts == sorted(firsts)
        self.counts = {"added": 0, "removed": 0, "changed": 0}

    @staticmethod
    def text(row, col):
        cell = row["cells"].get(col)
        return cell["text"].strip() if cell else ""

    def values(self, row):
        return tuple(self.text(row, col) for col in sorted(self.headings.values()))

    def columns(self, fields, what, raw=False):
        if not isinstance(fields, dict) or not fields:
            self.problems.append(f"{self.name}: {what} must name at least one column heading and its value.")
            return None
        unknown = [h for h in fields if str(h).strip() not in self.headings]
        if unknown:
            self.problems.append(f"{self.name}: no column is headed {', '.join(map(repr, unknown))}. The headings are {', '.join(map(repr, self.headings))}.")
            return None
        for h, v in fields.items():
            if is_formula(v):
                self.problems += [f"{self.name}: {h} {v}: {p}." for p in formula_problems(v, self.sheets, self.names)]
            elif v is not None and not isinstance(v, (str, int, float, bool)):
                self.problems.append(f"{self.name}: {h} {v!r} is not text, a number, true, false or null.")
        if raw:
            return {self.headings[str(h).strip()]: v for h, v in fields.items()}
        return {self.headings[str(h).strip()]: "" if v is None else str(v).strip() for h, v in fields.items()}

    @staticmethod
    def entry(value, style):
        """A cell an edit writes, keeping a number, true or false, or a formula as it was given."""
        if isinstance(value, (bool, int, float)) or is_formula(value):
            return {"value": value, "text": str(value), "style": style}
        return {"text": "" if value is None else str(value).strip(), "style": style}

    def find(self, match):
        wanted = self.columns(match, "match")
        if wanted is None:
            return None
        found = [r for r in self.body if all(self.text(r, col) == v for col, v in wanted.items())]
        if len(found) != 1:
            shown = ", ".join(f"{h} {v!r}" for h, v in match.items())
            self.problems.append(f"{self.name}: {'no row has' if not found else f'{len(found)} rows have'} {shown}. A match finds exactly one row.")
            return None
        return found[0]

    def style_above(self, at, col):
        for row in reversed(self.body[:at]):
            if col in row["cells"]:
                return row["cells"][col]["style"]
        for row in self.body[at:]:
            if col in row["cells"]:
                return row["cells"][col]["style"]
        return None

    def apply(self, edit):
        action = edit.get("action")
        if action == "remove" and self.model:
            self.problems.append(f"{self.name}: a formula, a name or an input rule names this sheet's rows, so no row of it is removed. Change its values instead, or remove it in a spreadsheet program.")
        elif action == "remove":
            row = self.find(edit.get("match"))
            if row is not None:
                self.body.remove(row)
                self.counts["removed"] += 1
        elif action == "change":
            row = self.find(edit.get("match"))
            values = self.columns(edit.get("row"), "row", raw=True)
            if row is not None and values is not None:
                for col, value in values.items():
                    style = row["cells"][col]["style"] if col in row["cells"] else self.style_above(self.body.index(row), col)
                    row["cells"][col] = self.entry(value, style)
                self.counts["changed"] += 1
        elif action == "add":
            raw = self.columns(edit.get("row"), "row", raw=True)
            if raw is None:
                return
            values = {col: "" if v is None else str(v).strip() for col, v in raw.items()}
            if not values.get(1):
                self.problems.append(f"{self.name}: an added row fills the {self.heading_of(1)!r} column.")
                return
            new = {"number": None, "attrs": dict(self.body[-1]["attrs"]) if self.body else {}, "cells": {}}
            key = tuple(values.get(col, "") for col in sorted(self.headings.values()))
            if any(self.values(r) == key for r in self.body):
                self.problems.append(f"{self.name}: the row {', '.join(repr(v) for v in key)} is already on the sheet.")
                return
            at = len(self.body)
            if self.ordered and not self.model:
                first = values[1].casefold()
                at = next((i for i, r in enumerate(self.body) if self.text(r, 1).casefold() > first), len(self.body))
            for col, value in raw.items():
                new["cells"][col] = self.entry(value, self.style_above(at, col))
            self.body.insert(at, new)
            self.counts["added"] += 1
        else:
            self.problems.append(f"{self.name}: action {action!r} is not one of {', '.join(ACTIONS)}.")

    def heading_of(self, col):
        return next((h for h, c in self.headings.items() if c == col), column_letters(col))

    def numbered(self):
        """Each row with its number. The data rows are numbered from row 2 on, one after another; in a model,
        each row keeps its number, and an added row goes after the last."""
        if not self.model:
            return list(enumerate(self.head + self.body, start=1 if self.head else 2))
        last = max([r["number"] or 0 for r in self.head + self.body] + [1])
        for row in self.body:
            if row["number"] is None:
                last += 1
                row["number"] = last
        return sorted(((r["number"], r) for r in self.head + self.body), key=lambda pair: pair[0])

    def format(self, styles, ranges):
        """Gives each cell of the ranges a style with its number format, making any cell or row it needs."""
        self.numbered()
        for cells, code in ranges:
            for col, number in cells:
                row = next((r for r in self.head + self.body if r["number"] == number), None)
                if row is None:
                    row = {"number": number, "attrs": {}, "cells": {}}
                    (self.head if number == 1 else self.body).append(row)
                cell = row["cells"].setdefault(col, {"text": "", "style": None})
                current = cell["element"].get("s") if "element" in cell else cell["style"]
                style = styles.style(current, code)
                if "element" in cell:
                    cell["element"].set("s", style)
                else:
                    cell["formatted"] = True
                cell["style"] = style

    def written(self):
        """The sheet's XML with its new rows, and the new last row."""
        out, last, widest = [], 0, 1
        for number, row in self.numbered():
            attrs = "".join(f" {k if not k.startswith('{') else self.prefixes[k[1:k.index('}')]] + ':' + k[k.index('}') + 1:]}={quoteattr(v)}" for k, v in row["attrs"].items())
            cells = []
            for col in sorted(row["cells"]):
                cell = row["cells"][col]
                ref = f"{column_letters(col)}{number}"
                if "element" in cell:
                    cell["element"].set("r", ref)
                    cells.append(serialise(cell["element"], self.prefixes))
                else:
                    cells.append(value_cell(ref, cell))
                widest = max(widest, col)
            out.append(f'<row r="{number}"{attrs}>{"".join(cells)}</row>')
            last = number
        xml = self.xml[: self.span[0]] + "<sheetData>" + "".join(out) + "</sheetData>" + self.xml[self.span[1]:]
        end = f"{column_letters(widest)}{last}"
        xml = re.sub(r'(<dimension ref=")[A-Z]+\d+(?::[A-Z]+\d+)?(")', lambda m: f"{m.group(1)}A1:{end}{m.group(2)}", xml, count=1)
        xml = re.sub(r'(<autoFilter ref="[A-Z]+\d+:[A-Z]+)\d+(")', lambda m: f"{m.group(1)}{last}{m.group(2)}", xml, count=1)
        return xml, last


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: edit_workbook.py WORKBOOK NEW EDITS.json")
    source, target, edits_file = sys.argv[1:]
    try:
        given = json.load(open(edits_file, encoding="utf-8"))
    except (OSError, ValueError) as err:
        sys.exit(f"The edits are not JSON: {err}")
    model = given if isinstance(given, dict) else {"edits": given}
    edits, defs, formats, rules = model.get("edits"), model.get("names"), model.get("formats"), model.get("rules")
    # Each is checked by model_problems; one that is not a list is a problem there, and taken as none here.
    listed = lambda items: [i for i in items if isinstance(i, dict)] if isinstance(items, list) else []
    if not isinstance(edits, list) or not edits or not all(isinstance(e, dict) for e in edits):
        sys.exit("The edits are a list of at least one edit, each an object with sheet, action, match and row.")
    try:
        book = zipfile.ZipFile(source)
        parts = sheet_parts(book)
    except (zipfile.BadZipFile, KeyError, ET.ParseError) as err:
        sys.exit(f"The workbook is not an .xlsx workbook: {err}")
    names = [n for n, _ in parts]
    strings = shared_strings(book)
    workbook = book.read("xl/workbook.xml").decode("utf-8")
    defined = [n for n in re.findall(r'<definedName\b[^>]*\bname="([^"]+)"', workbook) if not n.startswith("_xlnm.")]
    xmls = {name: book.read(part).decode("utf-8") for name, part in parts}
    problems = model_problems(defs, formats, rules, names, defined)
    defs, formats, rules = listed(defs), listed(formats), listed(rules)
    new_names = [n["name"] for n in defs or [] if isinstance(n, dict) and isinstance(n.get("name"), str)]
    # The sheet each name is on, the names this call gives among them.
    on = {m.group(1).casefold(): name_sheet(m.group(2)) for m in re.finditer(r'<definedName\b[^>]*\bname="([^"]+)"[^>]*>([^<]*)</definedName>', workbook)
          if not m.group(1).startswith("_xlnm.")}
    on.update({n["name"].casefold(): name_sheet(str(n.get("ref", ""))) for n in defs or [] if isinstance(n, dict) and isinstance(n.get("name"), str)})
    # The sheets whose rows are named, and so keep their numbers, and the sheets whose formulas name a row.
    pinned, fed = set(on.values()), set()
    pinned |= {n for n, x in xmls.items() if re.search(r"<dataValidations\b", x)} | {r.get("sheet") for r in (rules or []) + (formats or []) if isinstance(r, dict)}
    given = [(n, unescape(f)) for n, x in xmls.items() for f in re.findall(r"<f\b[^>]*>([^<]*)</f>", x)]
    given += [(e.get("sheet"), v) for e in edits if isinstance(e.get("row"), dict) for v in e["row"].values() if is_formula(v)]
    for sheet, formula in given:
        own, others, named = references(formula, on)
        pinned |= others | ({sheet} if own else set())
        if own or others or named:
            fed.add(sheet)
    has_formulas = bool(given or on)
    sheets = {}

    def load(name, at):
        if name not in sheets:
            xml = xmls[name]
            held = [p for p in (MODEL_REFERENCES if name in pinned else ROW_REFERENCES) if re.search(rf"<{p}\b", xml)]
            if held:
                problems.append(f"{at}: the {name!r} sheet holds {', '.join(held)}, which name cells by row. Edit it in a spreadsheet program.")
                return None
            sheets[name] = Sheet(name, xml, strings, name in pinned, names, defined + new_names)
        return sheets[name]

    for at, edit in enumerate(edits, start=1):
        name = edit.get("sheet")
        if name not in names:
            problems.append(f"Edit {at}: no sheet is named {name!r}. The sheets are {', '.join(map(repr, names))}.")
            continue
        if load(name, f"Edit {at}") is None:
            continue
        sheet = sheets[name]
        before = len(sheet.problems)
        sheet.apply(edit)
        problems += [f"Edit {at}: {p}" for p in sheet.problems[before:]]
    if not problems:
        for item in (formats or []) + (rules or []):
            load(item["sheet"], f"The {item['sheet']!r} sheet")
    if problems:
        sys.stderr.write("\n".join(problems) + "\n")
        sys.exit(1)

    replaced, lasts = {}, {}
    if formats:
        styles = Styles(book.read("xl/styles.xml").decode("utf-8"))
        for name, sheet in sheets.items():
            sheet.format(styles, [(cells_of(f["range"]), f["format"]) for f in formats if f["sheet"] == name])
        replaced["xl/styles.xml"] = styles.written().encode("utf-8")
    for name, sheet in sheets.items():
        xml, lasts[name] = sheet.written()
        xml = add_rules(xml, [r for r in rules or [] if r["sheet"] == name])
        replaced[dict(parts)[name]] = xml.encode("utf-8")
    for name, last in lasts.items():
        index = names.index(name)
        pattern = rf'(<definedName name="_xlnm\._FilterDatabase" localSheetId="{index}"[^>]*>[^<]*!\$[A-Z]+\$\d+:\$[A-Z]+\$)\d+(</definedName>)'
        workbook = re.sub(pattern, lambda m: f"{m.group(1)}{last}{m.group(2)}", workbook)
    if has_formulas:
        workbook = recalculate_on_open(add_names(workbook, defs))
        for name, part in parts:
            if name in fed:
                replaced[part] = without_results(replaced[part].decode("utf-8") if part in replaced else xmls[name]).encode("utf-8")
    replaced["xl/workbook.xml"] = workbook.encode("utf-8")

    with zipfile.ZipFile(target, "w") as out:
        for info in book.infolist():
            out.writestr(info, replaced.get(info.filename, book.read(info.filename)))
    print(json.dumps({"sheets": {name: sheet.counts for name, sheet in sheets.items()}}))


if __name__ == "__main__":
    main()
