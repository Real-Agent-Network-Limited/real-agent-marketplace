"""The text of a PDF that Chrome, Chromium or Edge printed, page by page, with Python's own library.

Usage: python3 pdf_text.py <file.pdf>

Each page's content streams are inflated, and each string shown is mapped to its characters
through its font's ToUnicode map. A line ends where the text moves down the page. With prose=True,
each line is a dictionary: its text, its prose, which leaves out text in a mono font such as code,
and whether it starts a block, by a gap above it wider than a wrapped line's. This reads the PDFs
the browser writes, and is not a reader for every PDF.
"""
import re
import sys
import zlib

OBJECT = re.compile(rb"(\d+)\s+0\s+obj\b(.*?)\bendobj", re.S)
REF = rb"(\d+)\s+0\s+R"
# A font whose name holds one of these is a mono font, which a page uses for code.
MONO = re.compile(rb"(?i)mono|menlo|consolas|courier|monaco")


def objects(body):
    """Each object's number, its dictionary text and its stream, inflated where it is compressed."""
    found = {}
    for number, text in OBJECT.findall(body):
        stream = None
        at = text.find(b"stream")
        if at >= 0:
            start = at + len(b"stream")
            start += 2 if text[start:start + 2] == b"\r\n" else 1
            raw = text[start:text.rfind(b"endstream")]
            if b"/FlateDecode" in text[:at]:
                try:
                    raw = zlib.decompressobj().decompress(raw)
                except zlib.error:
                    raw = b""
            stream, text = raw, text[:at]
        found[int(number)] = (text, stream)
    return found


def dictionary(text, key, objs):
    """The dictionary text a key names, inline or by reference."""
    m = re.search(rb"/" + key + rb"\s*" + REF, text)
    if m:
        return objs.get(int(m.group(1)), (b"", None))[0]
    m = re.search(rb"/" + key + rb"\s*<<", text)
    if not m:
        return b""
    depth, i = 0, m.end() - 2
    while i < len(text):
        if text[i:i + 2] == b"<<":
            depth += 1; i += 2; continue
        if text[i:i + 2] == b">>":
            depth -= 1; i += 2
            if depth == 0:
                return text[m.end() - 2:i]
            continue
        i += 1
    return text[m.end() - 2:]


def to_unicode(stream):
    """A font's ToUnicode map: each code, as hex, to its characters."""
    table = {}
    text = stream.decode("latin-1")
    for block in re.findall(r"beginbfchar(.*?)endbfchar", text, re.S):
        for src, dst in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            table[src.upper()] = bytes.fromhex(dst).decode("utf-16-be", "replace")
    for block in re.findall(r"beginbfrange(.*?)endbfrange", text, re.S):
        for lo, hi, dst in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]+>|\[[^\]]*\])", block):
            width, a, b = len(lo), int(lo, 16), int(hi, 16)
            if dst.startswith("["):
                for k, d in enumerate(re.findall(r"<([0-9A-Fa-f]+)>", dst)):
                    table[f"{a + k:0{width}X}"] = bytes.fromhex(d).decode("utf-16-be", "replace")
            else:
                start = int(dst[1:-1], 16)
                for k in range(b - a + 1):
                    table[f"{a + k:0{width}X}"] = chr(start + k) if start + k < 0x110000 else ""
    return table


def fonts(page, objs):
    """Each font name on a page to its ToUnicode map, and whether it is a mono font."""
    resources = dictionary(page, b"Resources", objs)
    found = {}
    for name, number in re.findall(rb"/([\w.+-]+)\s*" + REF, dictionary(resources, b"Font", objs)):
        font = objs.get(int(number), (b"", None))[0]
        m = re.search(rb"/ToUnicode\s*" + REF, font)
        stream = objs.get(int(m.group(1)), (b"", None))[1] if m else None
        base = re.search(rb"/BaseFont\s*/(\S+)", font)
        found[name.decode()] = (to_unicode(stream) if stream else {}, bool(base and MONO.search(base.group(1))))
    return found


TOKEN = re.compile(rb"<([0-9A-Fa-f\s]*)>|\((?:\\.|[^\\)])*\)|\[|\]|/[^\s/\[\]()<>]+|[-+]?(?:\d+\.?\d*|\.\d+)|[A-Za-z'\"*]+")


def page_text(content, font_maps):
    """The lines of text a page's content stream shows: each its text, its prose and whether it starts a block."""
    lines, full, prose, stack = [], [], [], []
    table, mono, size, in_array, array = {}, False, 0.0, False, []
    last_y, gap_above, width, line_size = None, None, 4, 0.0

    def show(codes):
        nonlocal line_size
        if not full:
            line_size = size
        hexes = codes.decode().replace(" ", "").upper()
        text = "".join(table.get(hexes[i:i + width], "") for i in range(0, len(hexes), width))
        full.append(text)
        prose.append(" " * len(text) if mono else text)

    def end_line(gap):
        nonlocal gap_above
        if full:
            lines.append({"text": "".join(full), "prose": "".join(prose), "gap": gap_above, "size": line_size})
            full.clear(); prose.clear()
        gap_above = gap

    def move(new_y):
        nonlocal last_y
        if new_y is None:
            return
        if last_y is None:
            end_line(None)
        elif abs(new_y - last_y) > 1:
            end_line(abs(new_y - last_y))
        last_y = new_y

    for m in TOKEN.finditer(content):
        tok = m.group(0)
        if tok == b"[":
            in_array, array = True, []; continue
        if tok == b"]":
            in_array = False; stack.append(array); continue
        if m.group(1) is not None:
            (array if in_array else stack).append(("hex", m.group(1))); continue
        if in_array:
            continue
        if tok[:1] == b"/" or tok[:1] == b"(" or re.match(rb"[-+.\d]", tok):
            stack.append(tok); continue
        op = tok
        try:
            if op == b"Tf" and len(stack) >= 2:
                table, mono = font_maps.get(stack[-2][1:].decode(), ({}, False))
                size = float(stack[-1])
                width = max((len(k) for k in table), default=4)
            elif op == b"Tm" and len(stack) >= 6:
                move(float(stack[-1]))
            elif op in (b"Td", b"TD") and len(stack) >= 2:
                dy = float(stack[-1])
                if dy:
                    move((last_y or 0) + dy)
            elif op == b"Tj" and stack and isinstance(stack[-1], tuple):
                show(stack[-1][1])
            elif op == b"TJ" and stack and isinstance(stack[-1], list):
                for part in stack[-1]:
                    if isinstance(part, tuple):
                        show(part[1])
        except (TypeError, ValueError, AttributeError):
            pass
        stack = []
    end_line(None)
    result = []
    for line in lines:
        if not line["text"].strip():
            continue
        # A wrapped line sits one line's pitch below the line before it, at most about 1.6 times
        # the type's size; a new block, after a paragraph's or a list's margin, sits further down.
        starts = line["gap"] is None or not line["size"] or line["gap"] > 1.6 * line["size"]
        result.append({"text": line["text"].rstrip(), "prose": line["prose"].rstrip(), "starts_block": starts})
    return result


def pages(path, prose=False):
    """The text of each page, in order, as a list of lines: strings, or with prose=True, dictionaries."""
    with open(path, "rb") as f:
        body = f.read()
    objs = objects(body)
    # The page objects in the order the page tree gives them.
    order = []
    def walk(number):
        text = objs.get(number, (b"", None))[0]
        if re.search(rb"/Type\s*/Page\b", text):
            order.append(number); return
        m = re.search(rb"/Kids\s*\[(.*?)\]", text, re.S)
        for kid in re.findall(REF, m.group(1)) if m else []:
            walk(int(kid))
    roots = [n for n, (t, _) in objs.items() if re.search(rb"/Type\s*/Pages\b", t) and not re.search(rb"/Parent\b", t)]
    for root in roots:
        walk(root)
    result = []
    for number in order:
        page = objs[number][0]
        m = re.search(rb"/Contents\s*(\[(.*?)\]|" + REF + rb")", page, re.S)
        refs = re.findall(REF, m.group(0)) if m else []
        content = b"\n".join(objs.get(int(r), (b"", b""))[1] or b"" for r in refs)
        result.append(page_text(content, fonts(page, objs)))
    # Where most of the text is in a mono font, the body is mono, and its text is prose too.
    count = lambda key: sum(len(re.sub(r"\s", "", line[key])) for lines in result for line in lines)
    if count("prose") * 2 < count("text"):
        for lines in result:
            for line in lines:
                line["prose"] = line["text"]
    return result if prose else [[line["text"] for line in lines] for lines in result]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for at, lines in enumerate(pages(sys.argv[1]), 1):
        print(f"--- page {at}")
        print("\n".join(lines))
