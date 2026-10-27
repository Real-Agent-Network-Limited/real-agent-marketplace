"""Draw a progress board for one OKB plan.

Usage: python3 board_page.py <progress.json> [<progress.json> ...] <page.html> --purpose TEXT [--plan-id ID]

The board is drawn from the plan model `plan_model.py` builds from the progress files, the same
model the graph is drawn from. The plan is the header, and each direct child of the plan is a row,
in index order. A child plan's row holds a card for every activity under it, in index order, and
the plan itself only as the row's heading; a child task's row holds its own card. Each card sits in
the column for its state. With two or more rows, the page has a menu of the rows and All, and
opens on the row `page_check.opening_row` names. Without --plan-id, the board draws the only plan
with no parent. The page is drawn with board-shell.html, beside this script, and needs no network
to open. Beside the page, `page_check.py` writes its outline, and its picture where a Chromium
browser is found.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import page_check  # noqa: E402
import plan_model  # noqa: E402

SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "board-shell.html")


def script_json(value):
    """JSON safe to put inside a script element."""
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return text.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def html_escape(value):
    return (value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;").replace("'", "&#39;"))


def fill_shell(shell, title, data):
    page = shell.replace(shell[shell.index("<!--"):shell.index("-->") + 3] + "\n", "", 1)
    for slot, value in (("{{BOARD_DATA_JSON}}", script_json(data)), ("{{TITLE}}", html_escape(title))):
        if slot not in page:
            raise ValueError(f"board-shell.html has no {slot}")
        page = page.replace(slot, value)
    return page


def main():
    parser = argparse.ArgumentParser(description="Draw a progress board for one OKB plan.")
    parser.add_argument("files", nargs="+", help="the progress files, then the page")
    parser.add_argument("--plan-id", default="")
    parser.add_argument("--purpose", default="", help="the plan's purpose statement, shown at the top of the board")
    args = parser.parse_args()
    if len(args.files) < 2:
        raise SystemExit("name at least one progress file and the page; no page was drawn")
    purpose = " ".join(args.purpose.split())
    if not purpose:
        raise SystemExit("name the plan's purpose statement with purpose; no page was drawn")
    *progress, page_path = args.files

    data = plan_model.load(progress, args.plan_id)
    data["purpose"] = purpose
    data["open_row"] = page_check.opening_row(data)
    page = fill_shell(open(SHELL, encoding="utf-8").read(), data["plan"]["title"], data)
    with open(page_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    checked = page_check.check_board(page_path, data)
    counts = ", ".join(f"{s.replace('_', ' ')} {n}" for s, n in data["counts"].items())
    print(f"wrote {page_path} ({len(page.encode())} bytes): {data['plan']['title']}, save number {data['cutoff']}; "
          f"{len(data['rows'])} rows, {len(data['activities'])} activities: {counts}; {checked}")


if __name__ == "__main__":
    main()
