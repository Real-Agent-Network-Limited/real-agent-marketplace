"""Draw an OKB model record, such as an org chart or a contacts list, as a board of cards.

Usage: python3 model_board.py <record.json> <page.html> --layout group|level --by NAME

The record is what `okb_get_record` returns, or a version on its own, as the graph skill's
`graph_page.py` takes. Each node is a card: its label, a second line from its `role` attribute (or
its `title`, where it has no role), and its `description`. The cards fall into rows:

- `group`: one row per value of the node attribute named with --by, in the order the nodes first
  give them, the attribute's name matched as a relation's is. Nodes without it are in a last row,
  Ungrouped. In a row, a node whose type is a place, such as a site or a warehouse, heads a column,
  and each card linked to it sits under it. A card spans neighbouring places it is linked to, and
  sits under each run of them apart.
- `level`: one row per level of the relation named with --by, such as "reports to". A node with no
  line of that relation is on the top row, and each card sits under the card it points to. A node
  outside the relation is a card above the chart, headed Beside the chart. The levels scroll as one.

A node whose type is `gap`, or whose `gap` attribute is true, is a dashed card. Clicking a card shows
its lines to other nodes and the evidence behind it. The page is drawn with model-board-shell.html,
beside this script, and needs no network to open. Beside the page, `page_check.py` writes its
outline, and its picture where a Chromium browser is found.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import board_page  # noqa: E402
import page_check  # noqa: E402

SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model-board-shell.html")
NODE_LIMIT = 500
UNGROUPED = "Ungrouped"
PLACE_TYPES = {"site", "warehouse", "location", "place", "office", "facility", "depot", "store"}
# Attributes a card shows in its own places, and so leaves out of its panel's details.
SHOWN = {"role", "title", "description", "gap"}
EVIDENCE = ("evidence", "source", "sources", "basis")


def text_of(value):
    if isinstance(value, str):
        return value.strip()
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False)


def plain(value):
    """`reports_to`, `Reports to` and `reports-to` as one name."""
    return " ".join(str(value).replace("_", " ").replace("-", " ").split()).casefold()


def humanise(value):
    text = " ".join(part for part in str(value).replace("-", "_").split("_") if part)
    return text[:1].upper() + text[1:]


def is_gap(node):
    gap = node.get("attributes", {}).get("gap")
    return plain(node.get("type", "")) == "gap" or gap is True or plain(text_of(gap)) in ("true", "yes")


def is_place(node):
    return plain(node.get("type", "")) in PLACE_TYPES


def card_of(node):
    attributes = node.get("attributes", {}) or {}
    details = {humanise(k): text_of(v) for k, v in attributes.items()
               if v is not None and k not in SHOWN and k not in EVIDENCE and text_of(v)}
    return {
        "id": node["id"], "label": text_of(node.get("label")) or node["id"], "type": humanise(node.get("type", "")),
        "role": text_of(attributes.get("role")) or text_of(attributes.get("title")),
        "description": text_of(attributes.get("description")),
        "gap": is_gap(node), "place": is_place(node), "details": details,
        "evidence": [text_of(attributes[k]) for k in EVIDENCE if text_of(attributes.get(k))],
    }


def lines_of(node_id, edges, label):
    """A card's lines to other nodes, each as the panel and outline say it."""
    out = []
    for e in edges:
        note = text_of((e.get("attributes") or {}).get("note")) or text_of((e.get("attributes") or {}).get("label"))
        if e["source"] == node_id:
            out.append({"text": f"{humanise(e['type'])} {label[e['target']]}", "note": note})
        elif e["target"] == node_id:
            out.append({"text": f"{label[e['source']]} {humanise(e['type']).lower()} this", "note": note})
    return out


def attribute(node, by):
    """The node's value of the attribute, its name matched as `plain` matches a relation's."""
    wanted = plain(by)
    for key, value in (node.get("attributes") or {}).items():
        if plain(key) == wanted and text_of(value):
            return text_of(value)
    return ""


def runs(columns):
    """Sorted columns as runs of neighbours: [0, 1, 3] as [[0, 1], [3]]."""
    out = []
    for at in columns:
        if out and at == out[-1][-1] + 1:
            out[-1].append(at)
        else:
            out.append([at])
    return out


def group_rows(nodes, edges, by):
    """One row per value of the attribute, in first-seen order, with Ungrouped last."""
    if not any(attribute(n, by) for n in nodes):
        raise SystemExit(f"no node carries the attribute {by}; draw it by level, or add {by} to the model's nodes; no page was drawn")
    names, members = [], {}
    for n in nodes:
        name = attribute(n, by) or UNGROUPED
        if name not in members:
            members[name] = []
            names.append(name)
        members[name].append(n)
    if UNGROUPED in names:
        names.remove(UNGROUPED)
        names.append(UNGROUPED)
    linked = {}
    for e in edges:
        linked.setdefault(e["source"], set()).add(e["target"])
        linked.setdefault(e["target"], set()).add(e["source"])
    rows, findings = [], []
    for name in names:
        row_nodes = members[name]
        places = [n["id"] for n in row_nodes if is_place(n)]
        column = {p: at for at, p in enumerate(places)}
        free, under = [], []
        for n in row_nodes:
            if n["id"] in column:
                continue
            at = sorted(column[p] for p in linked.get(n["id"], ()) if p in column)
            if not at:
                free.append(n["id"])
            # A card sits under each run of neighbouring places it is linked to, and spans no place it has no link to.
            for run in runs(at):
                under.append({"id": n["id"], "from": run[0] + 1, "to": run[-1] + 2,
                              "under": [places[i] for i in run], "linked": [places[i] for i in at]})
        rows.append({"name": name, "cards": free, "places": places, "under": under, "columns": len(places)})
        if name == UNGROUPED:
            count = len(row_nodes)
            findings.append(f"{count} node{'s carry' if count != 1 else ' carries'} no {by}, and {'are' if count != 1 else 'is'} in the row {UNGROUPED}: "
                            f"{', '.join(text_of(n.get('label')) or n['id'] for n in row_nodes)}.")
    return rows, findings


def level_rows(nodes, edges, by):
    """One row per level of the relation, each card under the card it points to."""
    wanted = plain(by)
    ids = {n["id"] for n in nodes}
    label = {n["id"]: text_of(n.get("label")) or n["id"] for n in nodes}
    matching = [e for e in edges if plain(e["type"]) == wanted and e["source"] in ids and e["target"] in ids]
    if not matching:
        kinds = sorted({humanise(e["type"]) for e in edges}, key=str.casefold)
        raise SystemExit(f"no line has the relation {by}; the model's relations are {', '.join(kinds) or 'none'}; no page was drawn")
    findings, parent = [], {}
    for e in matching:
        if e["source"] in parent:
            findings.append(f"{label[e['source']]} {humanise(e['type']).lower()} more than one node; its card is under {label[parent[e['source']]]}.")
            continue
        parent[e["source"]] = e["target"]
    # A line that loops back is cut where it closes, and the node it starts from goes to the top row.
    for n in nodes:
        seen, at = [], n["id"]
        while at in parent and at not in seen:
            seen.append(at)
            at = parent[at]
        if at in seen:
            findings.append(f"{label[at]} {humanise(by).lower()} in a loop; its card is on the top row.")
            del parent[at]
    order = [n["id"] for n in nodes]
    children = {i: [c for c in order if parent.get(c) == i] for i in order}
    width = {}

    def leaves(i):
        if i not in width:
            width[i] = max(1, sum(leaves(c) for c in children[i]))
        return width[i]

    placed, levels = {}, []

    def place(i, depth, start):
        while len(levels) <= depth:
            levels.append([])
        levels[depth].append({"id": i, "from": start, "to": start + leaves(i), "under": [parent[i]] if i in parent else []})
        placed[i] = depth
        at = start
        for c in children[i]:
            place(c, depth + 1, at)
            at += leaves(c)

    # A node outside the relation is a card on the top row, beside the tree, and the tree's columns are its own.
    joined = {end for e in matching for end in (e["source"], e["target"])}
    start = 1
    for i in order:
        if i not in parent and i in joined:
            place(i, 0, start)
            start += leaves(i)
    columns = start - 1
    rows = [{"name": f"Level {d + 1}", "cards": [], "places": [], "under": cards, "columns": columns}
            for d, cards in enumerate(levels)]
    rows[0]["cards"] = [i for i in order if i not in joined]
    return rows, findings


def model_version(record):
    if record is None:
        raise SystemExit("the record does not exist, or you may not read it; no page was drawn")
    if "deleted" in record:
        raise SystemExit("the record was deleted; no page was drawn")
    version = record.get("version", record)
    graph = version.get("payload", {}).get("graph") if isinstance(version, dict) else None
    if not isinstance(graph, dict) or "nodes" not in graph or "edges" not in graph:
        raise SystemExit("the file does not hold a model record's version; no page was drawn")
    return version


def board_data(record, layout, by):
    version = model_version(record)
    payload = version["payload"]
    nodes, edges = payload["graph"]["nodes"], payload["graph"]["edges"]
    if len(nodes) > NODE_LIMIT:
        raise SystemExit(f"the model has {len(nodes)} nodes, over the {NODE_LIMIT}-node limit; no page was drawn")
    if layout not in ("group", "level"):
        raise SystemExit("name the layout as group or level; no page was drawn")
    by = by.strip()
    if not by:
        raise SystemExit("name the attribute to group by, or the relation to draw by level, with by; no page was drawn")
    ids = {n["id"] for n in nodes}
    edges = [e for e in edges if e["source"] in ids and e["target"] in ids]
    rows, findings = (group_rows if layout == "group" else level_rows)(nodes, edges, by)
    label = {n["id"]: text_of(n.get("label")) or n["id"] for n in nodes}
    cards = {}
    for n in nodes:
        card = card_of(n)
        card["lines"] = lines_of(n["id"], edges, label)
        cards[n["id"]] = card
    links = (record.get("links") or []) if "version" in record else []
    return {
        "title": version.get("title", ""), "version_number": version.get("version_number"),
        "change_no": version.get("change_no"), "saved_at": version.get("recorded_at"),
        "description": text_of(payload.get("description")),
        "layout": layout, "by": by, "rows": rows, "cards": cards,
        "model_evidence": {
            "status": text_of(payload.get("source_status")), "sources": text_of(payload.get("source_version")),
            "linked": sum(1 for link in links if link.get("relation") == "supports"),
        },
        "findings": findings,
    }


def main():
    parser = argparse.ArgumentParser(description="Draw an OKB model record as a board of cards.")
    parser.add_argument("record")
    parser.add_argument("page")
    parser.add_argument("--layout", default="")
    parser.add_argument("--by", default="")
    args = parser.parse_args()
    data = board_data(json.load(open(args.record, encoding="utf-8")), args.layout, args.by)
    shell = open(SHELL, encoding="utf-8").read()
    page = shell.replace(shell[shell.index("<!--"):shell.index("-->") + 3] + "\n", "", 1)
    for slot, value in (("{{BOARD_DATA_JSON}}", board_page.script_json(data)), ("{{TITLE}}", board_page.html_escape(data["title"]))):
        if slot not in page:
            raise ValueError(f"model-board-shell.html has no {slot}")
        page = page.replace(slot, value)
    with open(args.page, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    checked = page_check.check_model_board(args.page, data)
    how = f"grouped by {data['by']}" if data["layout"] == "group" else f"by level of {data['by']}"
    print(f"wrote {args.page} ({len(page.encode())} bytes): {data['title']}, {len(data['cards'])} cards, "
          f"{len(data['rows'])} rows, {how}; {checked}")


if __name__ == "__main__":
    main()
