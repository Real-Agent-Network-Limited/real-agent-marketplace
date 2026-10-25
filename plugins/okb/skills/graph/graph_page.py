"""Draw a graph page from any OKB model record.

Usage: python3 graph_page.py <record.json> <page.html> [--group-by ATTRIBUTE]

The record is what `okb_get_record` returns, or a version on its own, as `model_to_page.py` takes.
Each node is a circle in its group's colour, carrying a short reference the Index names. Nodes are
grouped by their type, or by the attribute named with --group-by. Each edge is an arrow with a
small sign for its type at its middle, and the key names each sign. The page is drawn with page-shell.html, beside this
script, and needs no network to open.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "board"))
import model_to_page as mtp  # noqa: E402
import page_check  # noqa: E402
import plan_model  # noqa: E402
import state_machine_page as smp  # noqa: E402

NODE_LIMIT = 500
UNGROUPED = "Ungrouped"


def humanise(value):
    """`order_line` as `Order line`."""
    text = " ".join(part for part in str(value).split("_") if part)
    return text[:1].upper() + text[1:]


def text_of(value):
    if isinstance(value, str):
        return value
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False)


def group_of(node, group_by):
    if not group_by:
        return humanise(node["type"]) or UNGROUPED
    value = text_of(node.get("attributes", {}).get(group_by)).strip()
    return value or UNGROUPED


def index_of(node):
    return " ".join(text_of(node.get("attributes", {}).get("index")).split())


def to_graph_data(nodes, edges, group_by):
    """The page's graph-data block: groups, then each node in the order drawn, then each edge.

    Where nodes carry an `index` attribute, it is each node's reference and sets its order, and
    groups run in the order of their lowest index, each headed by its name alone. Otherwise groups
    are numbered in name order, and each node's reference is its group's number and its place in
    the group by label.
    """
    key_of = {n["id"]: group_of(n, group_by) for n in nodes}
    counts = {}
    for key in key_of.values():
        counts[key] = counts.get(key, 0) + 1
    indexed = any(index_of(n) for n in nodes)
    if indexed:
        lowest = {}
        for n in nodes:
            k = (0, plan_model.index_key(index_of(n))) if index_of(n) else (1, ())
            lowest[key_of[n["id"]]] = min(lowest.get(key_of[n["id"]], k), k)
        ordered = sorted((k for k in counts if k != UNGROUPED), key=lambda k: (lowest[k], k.casefold()))
    else:
        ordered = sorted((k for k in counts if k != UNGROUPED), key=str.casefold)
    if UNGROUPED in counts:
        ordered.append(UNGROUPED)

    groups = []
    for rank, key in enumerate(ordered):
        number = None if key == UNGROUPED else rank + 1
        fill = smp.UNGROUPED_FILL if number is None else smp.GROUP_PALETTE[rank % len(smp.GROUP_PALETTE)]
        groups.append({"key": key, "nodeId": None, "number": number,
                       "reference": "" if number is None or indexed else str(number),
                       "name": key, "fill": fill, "ink": smp.ink_for(fill), "count": counts[key]})
    group = {g["key"]: g for g in groups}

    reference, drawn = {}, []
    for g in groups:
        members = [n for n in nodes if key_of[n["id"]] == g["key"]]
        if indexed:
            members.sort(key=lambda n: ((0, plan_model.index_key(index_of(n))) if index_of(n) else (1, ()),
                                        n.get("label", "").casefold(), n["id"]))
            for n in members:
                reference[n["id"]] = index_of(n)
        else:
            members.sort(key=lambda n: (n.get("label", "").casefold(), n["id"]))
            for at, n in enumerate(members, 1):
                reference[n["id"]] = f"{g['number'] or '·'}.{at}"
        drawn.extend(members)

    page_nodes = []
    for n in drawn:
        g = group[key_of[n["id"]]]
        attributes = n.get("attributes", {})
        # The node's type is its typeLabel, which the page shows first; attributes keep their own names.
        properties = {k: text_of(v) for k, v in attributes.items() if v is not None and k not in ("description", "index")}
        page_nodes.append({
            "id": n["id"], "name": n.get("label") or n["id"], "reference": reference[n["id"]],
            "glyph": reference[n["id"]], "groupKey": g["key"], "kind": "node", "role": "state",
            "shape": "circle", "typeLabel": humanise(n["type"]), "fill": g["fill"], "ink": g["ink"],
            "border": smp.DARK_INK, "borderWidth": 1, "dashes": False,
            "description": text_of(attributes.get("description")).strip(), "tags": [],
            "properties": properties,
        })

    page_edges = [{"id": e["id"], "from": e["source"], "to": e["target"], "kind": "link",
                   "type": e["type"], "typeName": humanise(e["type"]),
                   "label": text_of(e.get("attributes", {}).get("label")).strip() or humanise(e["type"])}
                  for e in edges]
    return {"subject": "graph", "groups": groups, "nodes": page_nodes, "edges": page_edges}


def findings_of(graph_data):
    """Where nodes carry indexes: a node with none, and two nodes with one. A group with a number
    means the nodes carry no index, and the page numbers them itself."""
    found, seen = [], {}
    if any(g["reference"] for g in graph_data["groups"]):
        return found
    for n in graph_data["nodes"]:
        if not n["reference"]:
            found.append(f"{n['name']} has no index.")
        elif n["reference"] in seen:
            found.append(f"{seen[n['reference']]} and {n['name']} share the index {n['reference']}.")
        else:
            seen[n["reference"]] = n["name"]
    return found


def main():
    parser = argparse.ArgumentParser(description="Draw a graph page from an OKB model record.")
    parser.add_argument("record")
    parser.add_argument("page")
    parser.add_argument("--group-by", default="")
    args = parser.parse_args()

    record = json.load(open(args.record, encoding="utf-8"))
    if record is None:
        raise SystemExit("the record does not exist, or you may not read it; no page was drawn")
    if "deleted" in record:
        raise SystemExit("the record was deleted; no page was drawn")
    version = record.get("version", record)
    graph = version.get("payload", {}).get("graph") if isinstance(version, dict) else None
    if not isinstance(graph, dict) or "nodes" not in graph or "edges" not in graph:
        raise SystemExit("the file does not hold a model record's version; no page was drawn")
    nodes, edges = graph["nodes"], graph["edges"]
    if len(nodes) > NODE_LIMIT:
        raise SystemExit(f"the model has {len(nodes)} nodes, over the {NODE_LIMIT}-node limit; no page was drawn")

    group_by = args.group_by.strip()
    graph_data = to_graph_data(nodes, edges, group_by)
    grouping = f"grouped by {group_by}" if group_by else "grouped by type"
    line = (f"Model: {version['title']} (version {version['version_number']}). "
            f"{len(nodes)} nodes, {len(edges)} links, {len(graph_data['groups'])} groups, {grouping}. "
            f"Drawn from OKB.")
    page = mtp.fill_shell(open(mtp.SHELL, encoding="utf-8").read(), version["title"], line, graph_data, {})
    with open(args.page, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    checked = page_check.check_graph(args.page, f"{version['title']} (version {version['version_number']})",
                                     graph_data, findings_of(graph_data))
    print(f"wrote {args.page} ({len(page.encode())} bytes): {len(nodes)} nodes, {len(edges)} links, "
          f"{len(graph_data['groups'])} groups, {grouping}; {checked}")


if __name__ == "__main__":
    main()
