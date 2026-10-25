"""Creates a new .xlsx workbook from named sheets of rows.

Run with: python3 create_workbook.py <new workbook> <sheets.json>

sheets.json is a list of sheets, each {"name": "<sheet>", "rows": [[<value>, ...], ...]}, or an object
{"sheets", "names", "formats", "rules"}, as workbook_model.py gives them. Row 1 of a sheet is its
column headings. A value is text, a whole or decimal number, true or false, or null for an empty
cell. A value starting with "=" is a formula, and one starting with "'=" is the text after the quote.
The workbook recalculates every formula when it opens. Every sheet is checked first; on any problem,
nothing is written and every problem is printed. A value holding a character XML refuses, such as U+0007 from a pasted mail, is a problem. Text is written into each cell, so the workbook needs no shared strings, and edit_workbook
can edit it. Prints the rows written on each sheet, as JSON.
"""
import json
import re
import sys
import zipfile
from xml.sax.saxutils import escape

from workbook_model import Styles, add_names, cells_of, formula_cell, formula_problems, is_formula, literal, model_problems, recalculate_on_open, rules_xml

MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
FORBIDDEN = set('[]:*?/\\')
# The characters XML 1.0 refuses: controls other than tab, newline and carriage return, and U+FFFE and U+FFFF.
NOT_XML = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]")


def column_letters(index):
    letters = ""
    while index:
        index, rest = divmod(index - 1, 26)
        letters = chr(65 + rest) + letters
    return letters


def problems_of(sheets, names=None):
    problems, seen = [], set()
    if not isinstance(sheets, list) or not sheets:
        return ["Give at least one sheet."]
    sheet_names = [s["name"] for s in sheets if isinstance(s, dict) and isinstance(s.get("name"), str)]
    name_list = [n["name"] for n in names or [] if isinstance(n, dict) and isinstance(n.get("name"), str)]
    for at, sheet in enumerate(sheets, start=1):
        if not isinstance(sheet, dict) or not isinstance(sheet.get("name"), str):
            problems.append(f"Sheet {at} has no name.")
            continue
        name = sheet["name"]
        if not name.strip() or len(name) > 31 or FORBIDDEN & set(name) or name.startswith("'") or name.endswith("'"):
            problems.append(f"Sheet {at}: {name!r} is not a sheet name. A name has 1 to 31 characters, none of [ ] : * ? / \\, and does not start or end with '.")
        bad = NOT_XML.search(name)
        if bad:
            problems.append(f"Sheet {at}: its name holds the character U+{ord(bad.group()):04X}, which a workbook cannot hold.")
        if name.casefold() in seen:
            problems.append(f"Sheet {at}: {name!r} is named twice.")
        seen.add(name.casefold())
        rows = sheet.get("rows")
        if not isinstance(rows, list):
            problems.append(f"Sheet {at} ({name}): rows must be a list of rows.")
            continue
        for number, row in enumerate(rows, start=1):
            if not isinstance(row, list):
                problems.append(f"Sheet {at} ({name}), row {number}: a row is a list of values.")
                continue
            for col, value in enumerate(row, start=1):
                if value is not None and not isinstance(value, (str, int, float, bool)):
                    problems.append(f"Sheet {at} ({name}), row {number}, column {col}: {value!r} is not text, a number, true, false or null.")
                elif isinstance(value, str) and NOT_XML.search(value):
                    problems.append(f"Sheet {at} ({name}), row {number}, column {col}: the value holds the character U+{ord(NOT_XML.search(value).group()):04X}, which a workbook cannot hold. Remove it.")
                elif isinstance(value, str) and len(value) > 32767:
                    problems.append(f"Sheet {at} ({name}), row {number}, column {col}: a cell holds at most 32,767 characters.")
                elif is_formula(value):
                    problems += [f"Sheet {at} ({name}), row {number}, column {col}: {value}: {p}." for p in formula_problems(value, sheet_names, name_list)]
    return problems


def cell(ref, value, style=None):
    s = f' s="{style}"' if style else ""
    if value is None or value == "":
        return f'<c r="{ref}"{s}/>' if style else ""
    if isinstance(value, bool):
        return f'<c r="{ref}"{s} t="b"><v>{1 if value else 0}</v></c>'
    if isinstance(value, (int, float)):
        return f'<c r="{ref}"{s}><v>{value!r}</v></c>'
    if is_formula(value):
        return formula_cell(ref, value, style)
    return f'<c r="{ref}"{s} t="inlineStr"><is><t xml:space="preserve">{escape(literal(value))}</t></is></c>'


def sheet_xml(rows, styles=None, rules=()):
    """A sheet's XML. styles gives a cell style for each (column, row) a format names."""
    styles = styles or {}
    out, widest = [], max([1] + [c for c, _ in styles])
    last = max([len(rows)] + [r for _, r in styles])
    for number in range(1, last + 1):
        row = rows[number - 1] if number <= len(rows) else []
        columns = sorted(set(range(1, len(row) + 1)) | {c for c, r in styles if r == number})
        cells = "".join(cell(f"{column_letters(col)}{number}", row[col - 1] if col <= len(row) else None, styles.get((col, number))) for col in columns)
        widest = max(widest, len(row))
        out.append(f'<row r="{number}">{cells}</row>')
    end = f"{column_letters(widest)}{max(last, 1)}"
    frozen = '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' if rows else ""
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="{MAIN}" xmlns:r="{REL}">'
            f'<dimension ref="A1:{end}"/>{frozen}<sheetData>{"".join(out)}</sheetData>{rules_xml(list(rules))}</worksheet>')


def main():
    if len(sys.argv) != 3:
        sys.exit("Run with: python3 create_workbook.py <new workbook> <sheets.json>")
    target, sheets_file = sys.argv[1:]
    with open(sheets_file, encoding="utf-8") as f:
        given = json.load(f)
    model = given if isinstance(given, dict) else {"sheets": given}
    sheets, names, formats, rules = model.get("sheets"), model.get("names"), model.get("formats"), model.get("rules")
    problems = problems_of(sheets, names if isinstance(names, list) else None)
    if isinstance(sheets, list):
        problems += model_problems(names, formats, rules, [s["name"] for s in sheets if isinstance(s, dict) and isinstance(s.get("name"), str)])
    if problems:
        sys.exit("\n".join(problems))
    count = len(sheets)
    files = {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            + "".join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(1, count + 1))
            + "</Types>",
        "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="{MAIN}" xmlns:r="{REL}"><sheets>'
            + "".join(f'<sheet name="{escape(s["name"], {chr(34): "&quot;"})}" sheetId="{i}" r:id="rId{i}"/>' for i, s in enumerate(sheets, start=1))
            + "</sheets></workbook>",
        "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(f'<Relationship Id="rId{i}" Type="{REL}/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1, count + 1))
            + f'<Relationship Id="rId{count + 1}" Type="{REL}/styles" Target="styles.xml"/></Relationships>',
        "xl/styles.xml": f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="{MAIN}">'
            '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
            '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>',
    }
    files["xl/workbook.xml"] = recalculate_on_open(add_names(files["xl/workbook.xml"], names))
    styles = Styles(files["xl/styles.xml"])
    for i, sheet in enumerate(sheets, start=1):
        cell_styles = {}
        for fmt in formats or []:
            if fmt["sheet"] == sheet["name"]:
                for at in cells_of(fmt["range"]):
                    cell_styles[at] = styles.style(cell_styles.get(at), fmt["format"])
        files[f"xl/worksheets/sheet{i}.xml"] = sheet_xml(sheet["rows"], cell_styles, [r for r in rules or [] if r["sheet"] == sheet["name"]])
    files["xl/styles.xml"] = styles.written()
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as book:
        for name, body in files.items():
            book.writestr(name, body)
    print(json.dumps({"sheets": {s["name"]: {"rows": len(s["rows"])} for s in sheets}}))


if __name__ == "__main__":
    main()
