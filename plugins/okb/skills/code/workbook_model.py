"""What create_workbook.py and edit_workbook.py share for a live model: formulas, defined names, number
formats and input rules.

A value starting with "=" is a formula, written as the cell's formula with no cached value. A value
starting with "'=" is the text after the quote. Each formula's shape is checked before anything is
written: its brackets balance, and each sheet and each name it uses exists. A name is
{"name", "ref"}, such as {"name": "growth_rate", "ref": "Inputs!B2"}. A format is
{"sheet", "range", "format"}, such as "0.0%". A rule is {"sheet", "range", "list": [...]} or
{"sheet", "range", "min", "max"}.
"""
import re
from xml.sax.saxutils import escape, unescape

CELL = re.compile(r"\$?([A-Za-z]{1,3})\$?(\d{1,7})")
RANGE = re.compile(r"([A-Za-z]{1,3})(\d{1,7})(?::([A-Za-z]{1,3})(\d{1,7}))?")
NAME = re.compile(r"[A-Za-z_\\][A-Za-z0-9_.]*")
# A sheet named in a formula: 'Any name'! or Plain_name!.
SHEET_REF = re.compile(r"'((?:[^']|'')+)'!|([A-Za-z_][A-Za-z0-9_.]*)!")
# Excel's error values, such as #N/A, which a formula may hold as values.
ERRORS = re.compile(r"#(?:N/A|REF!|DIV/0!|VALUE!|NAME\?|NUM!|NULL!|GETTING_DATA|SPILL!|CALC!)", re.I)
# The formats Excel numbers itself; any other is a custom format, numbered from 164.
BUILT_IN_FORMATS = {"General": 0, "0": 1, "0.00": 2, "#,##0": 3, "#,##0.00": 4, "0%": 9, "0.00%": 10, "0.00E+00": 11, "d/m/yyyy": 14}
# The parts of a worksheet that come after its data validations, in the order the file format sets.
AFTER_RULES = ("hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks",
               "customProperties", "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing",
               "legacyDrawingHF", "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst")
# The parts of a workbook that come after its calculation settings, and after its defined names.
AFTER_CALC = ("oleSize", "customWorkbookViews", "pivotCaches", "smartTagPr", "smartTagTypes", "webPublishing",
              "fileRecoveryPr", "webPublishObjects", "extLst")
AFTER_NAMES = ("calcPr",) + AFTER_CALC


def column_number(letters):
    n = 0
    for ch in letters.upper():
        n = n * 26 + ord(ch) - 64
    return n


def is_cell(text):
    m = CELL.fullmatch(text)
    return bool(m) and column_number(m.group(1)) <= 16384 and 0 < int(m.group(2)) <= 1048576


def is_formula(value):
    return isinstance(value, str) and value.startswith("=")


def literal(value):
    """The text a value starting with '= stands for: the text after the quote."""
    return value[1:] if isinstance(value, str) and value.startswith("'=") else value


def quoted_sheet(name):
    return name if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", name) and not is_cell(name) else "'" + name.replace("'", "''") + "'"


def formula_problems(formula, sheets, names):
    """Every problem with a formula's shape: unbalanced brackets, and each sheet or name it uses that
    the workbook does not have. `sheets` and `names` are compared without case, as Excel does."""
    body, problems = formula[1:], []
    if not body.strip():
        return ["the formula is empty"]
    body = ERRORS.sub(lambda m: " " * len(m.group()), body)
    sheet_set = {s.casefold() for s in sheets}
    name_set = {n.casefold() for n in names}
    depth, i, out = 0, 0, []
    # Text in double quotes is a value, and a sheet in single quotes is a name: neither is read for brackets.
    while i < len(body):
        ch = body[i]
        if ch == '"':
            end = i + 1
            while end < len(body) and not (body[end] == '"' and body[end + 1: end + 2] != '"'):
                end += 2 if body[end] == '"' else 1
            if end >= len(body):
                return problems + ["a text in double quotes is not closed"]
            out.append(" " * (end + 1 - i))
            i = end + 1
            continue
        if ch == "'":
            m = SHEET_REF.match(body, i)
            if not m:
                return problems + ["a sheet name in single quotes is not closed with '!"]
            if m.group(1).replace("''", "'").casefold() not in sheet_set:
                problems.append(f"no sheet is named {m.group(1).replace(chr(39) * 2, chr(39))!r}")
            out.append(" " * (m.end() - i))
            i = m.end()
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return problems + ["a ) closes a bracket that was never opened"]
        out.append(ch)
        i += 1
    if depth:
        problems.append(f"{depth} bracket{'s are' if depth > 1 else ' is'} not closed")
    plain = "".join(out)
    for m in SHEET_REF.finditer(plain):
        if m.group(2) and m.group(2).casefold() not in sheet_set:
            problems.append(f"no sheet is named {m.group(2)!r}")
    # Each word that is not a function, a sheet, a cell, a column or row of a range, true or false, is a name.
    for m in NAME.finditer(plain):
        word, before, after = m.group(), plain[: m.start()], plain[m.end():]
        if (before and (before[-1].isalnum() or before[-1] in "$._#")) or (after and after[0] in "(!"):
            continue
        if is_cell(word) or word.upper() in ("TRUE", "FALSE"):
            continue
        if re.fullmatch(r"[A-Za-z]{1,3}", word) and (after.lstrip()[:1] == ":" or before.rstrip()[-1:] == ":"):
            continue
        if word.casefold() not in name_set:
            problems.append(f"no name {word!r} is defined")
    return problems


def references(formula, names=None):
    """What a formula names by row: whether it names cells of its own sheet, such as B2, the other sheets it names
    cells of, such as Inputs!B2, and whether it uses a defined name. names maps each defined name, without case,
    to its sheet. A whole column, such as A:A, names no row."""
    names = names or {}
    plain = re.sub(r'"(?:[^"]|"")*"', '""', formula[1:] if formula.startswith("=") else formula)
    plain = ERRORS.sub(lambda m: " " * len(m.group()), plain)
    sheets, named = set(), False
    for m in list(SHEET_REF.finditer(plain))[::-1]:
        rest = plain[m.end():]
        if re.match(r"\$?[A-Za-z]{1,3}\$?\d|\$?\d", rest):
            sheets.add((m.group(1) or "").replace("''", "'") or m.group(2))
        cell = re.match(r"[$A-Za-z0-9:]*", rest)
        plain = plain[: m.start()] + " " * (m.end() - m.start() + cell.end()) + plain[m.end() + cell.end():]
    own = False
    for m in NAME.finditer(plain):
        before, after = plain[: m.start()], plain[m.end():]
        if (before and (before[-1].isalnum() or before[-1] in "._#")) or (after and after[0] in "(!"):
            continue
        if is_cell(m.group()):
            own = True
        elif m.group().casefold() in names:
            named = True
            sheets.add(names[m.group().casefold()])
    # A range of whole rows, such as 2:2, names rows too.
    own = own or bool(re.search(r"(?<![\w.$])\$?\d+:\$?\d+", plain))
    return own, sheets, named


def name_sheet(ref):
    """The sheet a defined name's range is on, such as Inputs for 'Inputs'!$B$2."""
    sheet = ref.rpartition("!")[0].lstrip("=")
    return sheet[1:-1].replace("''", "'") if sheet.startswith("'") and sheet.endswith("'") else sheet


def range_problems(text, what):
    m = RANGE.fullmatch(str(text or "").replace("$", ""))
    if not m or not is_cell(m.group(1) + m.group(2)) or (m.group(3) and not is_cell(m.group(3) + m.group(4))):
        return [f"{what}: {text!r} is not a cell or a range of cells, such as B2 or B2:D10."]
    return []


def cells_of(text):
    """Each (column, row) of a range such as B2:D10, as numbers."""
    m = RANGE.fullmatch(str(text).replace("$", ""))
    c1, r1 = column_number(m.group(1)), int(m.group(2))
    c2, r2 = (column_number(m.group(3)), int(m.group(4))) if m.group(3) else (c1, r1)
    return [(c, r) for r in range(min(r1, r2), max(r1, r2) + 1) for c in range(min(c1, c2), max(c1, c2) + 1)]


def absolute(ref):
    """A name's range with each cell made absolute, as a defined name holds it: Inputs!$B$2."""
    sheet, _, cells = ref.rpartition("!")
    fixed = ":".join(re.sub(r"\$?([A-Za-z]{1,3})\$?(\d+)", lambda m: f"${m.group(1).upper()}${m.group(2)}", c) for c in cells.split(":"))
    return f"{sheet}!{fixed}"


def model_problems(names, formats, rules, sheets, existing_names=()):
    """Every problem with the names, formats and rules, given the workbook's sheets and the names it already has."""
    problems, sheet_set = [], {s.casefold(): s for s in sheets}
    if names is not None and not isinstance(names, list):
        problems.append("names must be a list, each {\"name\", \"ref\"}.")
        names = []
    seen = {n.casefold() for n in existing_names}
    for at, item in enumerate(names or [], start=1):
        name, ref = (item.get("name"), item.get("ref")) if isinstance(item, dict) else (None, None)
        if not isinstance(name, str) or not NAME.fullmatch(name) or is_cell(name) or len(name) > 255 \
                or name.upper() in ("TRUE", "FALSE", "R", "C"):
            problems.append(f"Name {at}: {name!r} is not a name. A name starts with a letter or _, holds letters, digits, _ and ., and is not a cell such as B2.")
            continue
        if name.casefold() in {n.casefold() for n in existing_names}:
            problems.append(f"Name {at}: {name!r} is already a name in the workbook.")
        elif name.casefold() in seen:
            problems.append(f"Name {at}: {name!r} is named twice.")
        seen.add(name.casefold())
        sheet, bang, cells = str(ref or "").rpartition("!")
        sheet = sheet[1:-1].replace("''", "'") if sheet.startswith("'") and sheet.endswith("'") else sheet
        if not bang or sheet.casefold() not in sheet_set:
            problems.append(f"Name {at} ({name}): {ref!r} does not name a sheet of the workbook and its cells, such as Inputs!B2.")
            continue
        problems += range_problems(cells, f"Name {at} ({name})")
    for label, items in (("Format", formats), ("Rule", rules)):
        if items is not None and not isinstance(items, list):
            problems.append(f"{label.lower()}s must be a list.")
            continue
        for at, item in enumerate(items or [], start=1):
            if not isinstance(item, dict) or item.get("sheet") not in sheets:
                problems.append(f"{label} {at}: {item.get('sheet') if isinstance(item, dict) else item!r} is not a sheet of the workbook.")
                continue
            problems += range_problems(item.get("range"), f"{label} {at}")
            if label == "Format":
                fmt = item.get("format")
                if not isinstance(fmt, str) or not fmt.strip() or len(fmt) > 255:
                    problems.append(f"Format {at}: the format is text, such as 0.0% or #,##0.")
            elif "list" in item:
                choices = item["list"]
                if not isinstance(choices, list) or not choices or not all(isinstance(c, (str, int, float)) and not isinstance(c, bool) for c in choices):
                    problems.append(f"Rule {at}: list is a list of at least one choice, each text or a number.")
                elif any("," in str(c) or '"' in str(c) for c in choices) or len(",".join(map(str, choices))) > 255:
                    problems.append(f"Rule {at}: the choices hold no comma or double quote, and 255 characters at most together.")
            elif "min" in item and "max" in item:
                low, high = item["min"], item["max"]
                if not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in (low, high)) or low > high:
                    problems.append(f"Rule {at}: min and max are numbers, and min is no more than max.")
            else:
                problems.append(f"Rule {at}: a rule gives list, or min and max.")
    return problems


def defined_name(item):
    sheet, _, cells = item["ref"].rpartition("!")
    sheet = sheet[1:-1].replace("''", "'") if sheet.startswith("'") and sheet.endswith("'") else sheet
    return f'<definedName name="{escape(item["name"])}">{escape(quoted_sheet(sheet) + "!" + absolute(cells).lstrip("!"))}</definedName>'


def rule_xml(rule):
    sqref = str(rule["range"]).replace("$", "").upper()
    if "list" in rule:
        choices = ",".join(str(c) for c in rule["list"])
        return (f'<dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="{sqref}">'
                f'<formula1>{escape(chr(34) + choices + chr(34))}</formula1></dataValidation>')
    return (f'<dataValidation type="decimal" operator="between" allowBlank="1" showErrorMessage="1" sqref="{sqref}">'
            f'<formula1>{rule["min"]!r}</formula1><formula2>{rule["max"]!r}</formula2></dataValidation>')


def rules_xml(rules):
    return f'<dataValidations count="{len(rules)}">{"".join(rule_xml(r) for r in rules)}</dataValidations>' if rules else ""


def formula_cell(ref, formula, style=None):
    s = f' s="{style}"' if style else ""
    return f'<c r="{ref}"{s}><f>{escape(formula[1:])}</f></c>'


def without_results(sheet):
    """A sheet's XML with each formula's saved result taken out, so every program works it out again on opening,
    as LibreOffice does only for a formula with no saved result."""
    def bare(m):
        cell = m.group()
        head_end = cell.index(">") + 1
        head = re.sub(r'\s+t="[^"]*"', "", cell[:head_end])
        return head + re.sub(r"<v>[^<]*</v>|<v\s*/>", "", cell[head_end:])
    return re.sub(r"<c\b[^>]*[^/]>(?:(?!</c>).)*?<f\b(?:(?!</c>).)*</c>", bare, sheet, flags=re.S)


def insert_before(xml, tags, piece, closing):
    """xml with piece put before the first of tags it holds, or else before closing."""
    at = [m.start() for t in tags for m in [re.search(rf"<{t}[\s/>]", xml)] if m]
    where = min(at) if at else xml.rindex(closing)
    return xml[:where] + piece + xml[where:]


def add_names(workbook, names):
    """workbook.xml with the names added to its defined names."""
    if not names:
        return workbook
    pieces = "".join(defined_name(n) for n in names)
    if re.search(r"<definedNames\s*/>", workbook):
        return re.sub(r"<definedNames\s*/>", f"<definedNames>{pieces}</definedNames>", workbook, count=1)
    if "</definedNames>" in workbook:
        return workbook.replace("</definedNames>", pieces + "</definedNames>", 1)
    return insert_before(workbook, AFTER_NAMES, f"<definedNames>{pieces}</definedNames>", "</workbook>")


def recalculate_on_open(workbook):
    """workbook.xml set to recalculate every formula when it opens."""
    m = re.search(r"<calcPr\b[^>]*?/?>", workbook)
    if m:
        tag = re.sub(r'\s+fullCalcOnLoad="[^"]*"', "", m.group())
        tag = tag[:-2].rstrip() + ' fullCalcOnLoad="1"/>' if tag.endswith("/>") else tag[:-1].rstrip() + ' fullCalcOnLoad="1">'
        return workbook[: m.start()] + tag + workbook[m.end():]
    return insert_before(workbook, AFTER_CALC, '<calcPr fullCalcOnLoad="1"/>', "</workbook>")


def add_rules(sheet, rules):
    """A sheet's XML with the rules added to its data validations."""
    if not rules:
        return sheet
    m = re.search(r'<dataValidations\b[^>]*>(.*?)</dataValidations>', sheet, re.S)
    if m:
        count = len(re.findall(r"<dataValidation\b", m.group(1))) + len(rules)
        return sheet[: m.start()] + f'<dataValidations count="{count}">{m.group(1)}{"".join(rule_xml(r) for r in rules)}</dataValidations>' + sheet[m.end():]
    return insert_before(sheet, AFTER_RULES, rules_xml(rules), "</worksheet>")


class Styles:
    """A workbook's styles.xml, with a cell style added for each number format a cell is given."""

    def __init__(self, xml):
        self.xml = xml
        block = re.search(r"<cellXfs\b[^>]*>(.*?)</cellXfs>", xml, re.S)
        self.xfs = re.findall(r"<xf\b[^>]*/>|<xf\b[^>]*>.*?</xf>", block.group(1), re.S) if block else ['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>']
        # Each custom format's attributes are read by name, in whatever order a program wrote them.
        self.formats = {}
        for tag in re.findall(r"<numFmt\b[^>]*>", xml):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', tag))
            if attrs.get("numFmtId", "").isdigit() and "formatCode" in attrs:
                self.formats[unescape(attrs["formatCode"], {"&quot;": '"', "&apos;": "'"})] = int(attrs["numFmtId"])
        self.added_formats, self.made = {}, {}

    def style(self, current, code):
        """The index of a cell style like the cell's current one, with the number format."""
        key = (current or "0", code)
        if key in self.made:
            return self.made[key]
        number = BUILT_IN_FORMATS.get(code, self.formats.get(code))
        if number is None:
            number = max([163] + list(self.formats.values())) + 1
            self.formats[code] = self.added_formats[code] = number
        base = self.xfs[int(current or 0)] if int(current or 0) < len(self.xfs) else self.xfs[0]
        xf = re.sub(r'\s+(numFmtId|applyNumberFormat)="[^"]*"', "", base)
        xf = re.sub(r"^<xf\b", f'<xf numFmtId="{number}" applyNumberFormat="1"', xf)
        self.xfs.append(xf)
        self.made[key] = str(len(self.xfs) - 1)
        return self.made[key]

    def written(self):
        xml = self.xml
        if self.added_formats:
            pieces = "".join(f'<numFmt numFmtId="{n}" formatCode="{escape(c, {chr(34): "&quot;"})}"/>' for c, n in self.added_formats.items())
            m = re.search(r"<numFmts\b[^>]*>(.*?)</numFmts>", xml, re.S)
            if m:
                inner = m.group(1) + pieces
                xml = xml[: m.start()] + f'<numFmts count="{len(re.findall(r"<numFmt ", inner))}">{inner}</numFmts>' + xml[m.end():]
            else:
                xml = re.sub(r"(<styleSheet\b[^>]*>)", lambda m: m.group(1) + f'<numFmts count="{len(self.added_formats)}">{pieces}</numFmts>', xml, count=1)
        block = f'<cellXfs count="{len(self.xfs)}">{"".join(self.xfs)}</cellXfs>'
        if re.search(r"<cellXfs\b", xml):
            return re.sub(r"<cellXfs\b[^>]*>.*?</cellXfs>", lambda m: block, xml, count=1, flags=re.S)
        return xml.replace("</styleSheet>", block + "</styleSheet>")
