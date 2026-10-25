"""What the print skill's pages share: an A4 page's style, its frame and its text made safe."""
import html
import json
from datetime import datetime, timezone

STYLE = """
@page { size: A4; margin: 16mm 15mm 18mm; }
* { box-sizing: border-box; }
body { margin: 0; color: #111; background: #fff; font: 10.5pt/1.45 "Helvetica Neue", Arial, sans-serif; }
h1 { font-size: 20pt; margin: 0 0 2mm; }
h2 { font-size: 13.5pt; margin: 7mm 0 2mm; border-bottom: 0.4mm solid #333; padding-bottom: 1mm; break-after: avoid; }
h3 { font-size: 11.5pt; margin: 5mm 0 1.5mm; break-after: avoid; }
p { margin: 0 0 2mm; }
p.meta { color: #444; font-size: 9.5pt; }
table { width: 100%; border-collapse: collapse; margin: 0 0 3mm; font-size: 9.5pt; }
th, td { text-align: left; vertical-align: top; border-bottom: 0.2mm solid #bbb; padding: 1.2mm 1.5mm; }
th { background: #eee; }
tr { break-inside: avoid; }
ul { margin: 0 0 2mm; padding-left: 5mm; }
.state { break-inside: avoid; border: 0.3mm solid #999; border-radius: 1.5mm; padding: 2mm 3mm; margin: 0 0 3mm; }
.state dl { display: grid; grid-template-columns: 22mm 1fr; gap: 0.6mm 3mm; margin: 1mm 0 0; }
.state dt { font-weight: 600; } .state dd { margin: 0; }
figure { margin: 2mm 0 4mm; } figure img { width: 100%; border: 0.2mm solid #bbb; }
figcaption { font-size: 9pt; color: #444; }
.none { color: #555; font-style: italic; }
"""


def esc(value):
    return html.escape(str(value if value is not None else ""), quote=True)


def script_json(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return text.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def printed_on(now=None):
    """Today's date as a person reads it, such as 15 October 2026."""
    d = now or datetime.now(timezone.utc)
    return f"{d.day} {d:%B %Y}"


def page(title, body, data_id, data):
    """A whole A4 page, with its data kept in a JSON block for its checks."""
    return "\n".join(["<!doctype html>", '<html lang="en-GB"><head><meta charset="utf-8">', f"<title>{esc(title)}</title>",
                      f"<style>{STYLE}</style></head><body>", body,
                      f'<script type="application/json" id="{data_id}">{script_json(data)}</script>', "</body></html>"]) + "\n"


def read(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)
