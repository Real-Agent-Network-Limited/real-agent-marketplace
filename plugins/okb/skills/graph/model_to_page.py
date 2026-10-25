"""Draw a state machine page from an OKB model record.

Usage: python3 model_to_page.py <record.json> <page.html>

The record is what `okb_get_record` returns, `{"cutoff", "version", "links"}`, with the
model's version inside `version`. A version on its own, with its `title`,
`version_number` and `payload`, is taken too. The page is drawn with page-shell.html, beside this
script, and needs no network to open. Beside it are its outline and, where a Chromium browser is
found, its picture, as the board skill's `page_check.py` writes them.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "board"))
import page_check  # noqa: E402
import state_machine_page as smp  # noqa: E402


def html_escape(value):
    """Text made safe to put in HTML."""
    return (value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;").replace("'", "&#39;"))


SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "page-shell.html")


def summary(record, graph_data, sm_data):
    """The page's summary line, counted from what the page draws."""
    nodes = graph_data["nodes"]
    edges = graph_data["edges"]
    groups = sum(1 for n in nodes if n["role"] == "group")
    states = sum(1 for n in nodes if n["kind"] == "node" and n["role"] != "group")
    objects = sum(1 for n in nodes if n["kind"] == "object")
    flows = sum(1 for e in edges if e["kind"] == "flow")
    dependencies = sum(1 for e in edges if e["kind"] == "dependency")
    provenance = sm_data["provenance"]
    return (f"Model: {record['title']} (version {record['version_number']}). "
            f"Mode: {provenance['mode']}; stored status: {provenance['storedStatus']}. "
            f"{groups} routines, {states} states, {objects} drawn objects, {flows} transitions, "
            f"{dependencies} dependencies. Drawn from OKB.")


def model_version(result):
    """The model's version, from what okb_get_record or okb_save_version returns."""
    if result is None:
        raise SystemExit("the record does not exist, or you may not read it; no page was drawn")
    if "deleted" in result:
        raise SystemExit("the record was deleted; no page was drawn")
    version = result.get("version", result)
    if not isinstance(version, dict) or "payload" not in version:
        raise SystemExit("the file does not hold a model record's version; no page was drawn")
    undrawable = smp.undrawable_types(version["payload"])
    if undrawable:
        raise SystemExit(f"the model has node types a state machine page cannot draw: {', '.join(undrawable)}; "
                         "draw it with draw_graph; no page was drawn")
    # A page-made model gives every route a key; a model written as a payload may leave it out.
    keyless = [n["label"] for n in version["payload"]["graph"]["nodes"] if n["type"] == "route" and "key" not in n.get("attributes", {})]
    if keyless:
        raise SystemExit(f"the route {', '.join(keyless)} has no key attribute; give each route a key; no page was drawn")
    return version


def fill_shell(shell, title, line, graph_data, sm_data):
    """The page: the shell with its four slots filled."""
    slots = {
        "{{GRAPH_DATA_JSON}}": smp.script_json(graph_data),
        "{{STATE_MACHINE_DATA_JSON}}": smp.script_json(sm_data),
        "{{TITLE}}": html_escape(title),
        "{{SUMMARY}}": html_escape(line),
    }
    body = shell.split("-->", 1)[1].lstrip("\n")  # the shell's own note is not part of a page
    head = shell[:shell.index("<!--")]
    page = head + body
    for slot, value in slots.items():
        if slot not in page:
            raise ValueError(f"page-shell.html has no {slot}")
        page = page.replace(slot, value)
    return page


def render(record, shell):
    graph_data, sm_data = smp.to_blocks(record["payload"])
    return fill_shell(shell, record["title"], summary(record, graph_data, sm_data), graph_data, sm_data)


def check(record, page_path):
    """The page's outline and picture, beside it. Returns a line for the tool's output."""
    graph_data, sm_data = smp.to_blocks(record["payload"])
    return page_check.check_state_machine(page_path, f"{record['title']} (version {record['version_number']})",
                                          summary(record, graph_data, sm_data), graph_data, sm_data)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    record_path, page_path = sys.argv[1:]
    record = model_version(json.load(open(record_path, encoding="utf-8")))
    page = render(record, open(SHELL, encoding="utf-8").read())
    with open(page_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    print(f"wrote {page_path} ({len(page.encode())} bytes); {check(record, page_path)}")


if __name__ == "__main__":
    main()
