"""Draw an OKB plan as a graph page, from the same plan model its board is drawn from.

Usage: python3 plan_graph.py <progress.json> [<progress.json> ...] <page.html> [--plan-id ID]

The plan model is what `plan_model.py`, beside the board skill, builds from the progress files
`okb_get_progress` wrote. Each part of the plan, a direct child of it, is a group, headed by its
title, in index order. The plan itself and any task directly under it are in the plan's own group,
first. Each activity is a node carrying its index, in index order: a plan is an ellipse, a task a
circle, a deliverable a box, and a blocker a circle with a flagged border. Each activity has a Part
of link to its parent and a Waits on link to each activity it depends on. Beside the page,
`page_check.py` writes its outline, and its picture where a Chromium browser is found.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "board"))
import model_to_page as mtp  # noqa: E402
import page_check  # noqa: E402
import plan_model  # noqa: E402
import state_machine_page as smp  # noqa: E402

STATE_NAMES = {"pending": "Pending", "in_progress": "In progress", "paused": "Paused",
               "completed": "Completed", "cancelled": "Cancelled"}
SHAPES = [
    {"name": "Plan", "shape": "ellipse", "flagged": False,
     "text": "an ellipse in its group's colour carrying the plan's index. The Groups panel names each part of the plan."},
    {"name": "Task", "shape": "circle", "flagged": False,
     "text": "a circle in its group's colour carrying the task's index. The Index names every index."},
    {"name": "Deliverable", "shape": "box", "flagged": False,
     "text": "a box in its group's colour carrying the deliverable's index. Its task waits on it."},
    {"name": "Blocker", "shape": "circle", "flagged": True,
     "text": "a circle with a red border carrying the blocker's index. The task it holds up waits on it."},
]


def type_of(a):
    if a["kind"] == "plan":
        return "Plan"
    return {"deliverable": "Deliverable", "blocker": "Blocker"}.get(a["task_type"], "Task")


def lines(text):
    return "\n".join(line.rstrip() for line in text.strip().splitlines())


def properties(a):
    """What the node's panel lists under its description, as the board's panel shows it."""
    out = {"state": STATE_NAMES.get(a["state"], a["state"])}
    if a["start"] or a["finish"]:
        out["dates"] = page_check.span(a)
    out["deliverables"] = lines(a["completion_requirements"]) or "None written"
    if a["blockers"]:
        out["blockers"] = "\n".join(b["name"] or b["description"] for b in a["blockers"])
    if a["deliverables"]:
        out["deliverable_records"] = "\n".join(f"{d['title']} ({STATE_NAMES.get(d['state'], d['state']).lower()})" for d in a["deliverables"])
    if a["dependencies"]:
        out["waits_on"] = "\n".join(d["title"] for d in a["dependencies"])
    if a["evidence"]:
        out["evidence"] = "\n".join(e["title"] for e in a["evidence"])
    if a["owner"]:
        out["owner"] = a["owner"]
    if a["kind"] != "plan" and a.get("assignee"):
        out["assigned_to"] = a["assignee"]
    if a["completion_note"].strip():
        out["completion_note"] = lines(a["completion_note"])
    out["record_id"] = a["id"]
    return out


def to_graph_data(model):
    plan, activities = model["plan"], model["activities"]
    by_id = {a["id"]: a for a in [plan] + activities}
    group_of = {plan["id"]: plan["id"]}
    for row in model["rows"]:
        head = by_id[row["activity"]]
        key = head["id"] if head["kind"] == "plan" else plan["id"]
        for member in [row["activity"]] + row["cards"]:
            group_of[member] = key
    keys = [plan["id"]] + [r["activity"] for r in model["rows"] if by_id[r["activity"]]["kind"] == "plan"]
    groups = []
    for rank, key in enumerate(keys):
        fill = smp.GROUP_PALETTE[rank % len(smp.GROUP_PALETTE)]
        groups.append({"key": key, "nodeId": None, "number": rank + 1, "reference": "",
                       "name": by_id[key]["title"], "fill": fill, "ink": smp.ink_for(fill),
                       "count": sum(1 for k in group_of.values() if k == key)})
    group = {g["key"]: g for g in groups}

    nodes = []
    for key in keys:
        for a in [plan] + activities:
            if group_of.get(a["id"]) != key:
                continue
            g, kind = group[key], type_of(a)
            shape = next(s for s in SHAPES if s["name"] == kind)
            nodes.append({
                "id": a["id"], "name": a["title"], "reference": a["index"], "glyph": a["index"],
                "groupKey": key, "kind": "node", "role": "state", "shape": shape["shape"], "typeLabel": kind,
                "fill": g["fill"], "ink": g["ink"], "border": smp.DARK_INK, "borderWidth": 1, "dashes": False,
                "description": lines(a["description"]), "tags": ["blocker"] if shape["flagged"] else [],
                "properties": properties(a),
            })
    edges = []
    for a in activities:
        if a["parent_id"] in by_id:
            edges.append({"id": f"part-{a['id']}", "from": a["id"], "to": a["parent_id"], "kind": "link",
                          "type": "part_of", "typeName": "Part of", "label": "Part of"})
        for d in a["waits_on"]:
            if d in by_id:
                edges.append({"id": f"wait-{a['id']}-{d}", "from": a["id"], "to": d,
                              "kind": "link", "type": "depends_on", "typeName": "Waits on", "label": "Waits on"})
    return {"subject": "graph", "groups": groups, "nodes": nodes, "edges": edges, "shapes": SHAPES}


def main():
    parser = argparse.ArgumentParser(description="Draw an OKB plan as a graph page.")
    parser.add_argument("files", nargs="+", help="the progress files, then the page")
    parser.add_argument("--plan-id", default="")
    args = parser.parse_args()
    if len(args.files) < 2:
        raise SystemExit("name at least one progress file and the page; no page was drawn")
    *progress, page_path = args.files

    model = plan_model.load(progress, args.plan_id)
    graph_data = to_graph_data(model)
    title = model["plan"]["title"]
    line = (f"Plan: {title}, read at save number {model['cutoff']}. {len(graph_data['nodes'])} activities, "
            f"{len(graph_data['edges'])} links, {len(graph_data['groups'])} groups, one for each part of the plan. "
            f"Drawn from OKB.")
    page = mtp.fill_shell(open(mtp.SHELL, encoding="utf-8").read(), title, line, graph_data, {})
    with open(page_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    checked = page_check.check_graph(page_path, title, graph_data, model["findings"])
    print(f"wrote {page_path} ({len(page.encode())} bytes): {title}, save number {model['cutoff']}; "
          f"{len(graph_data['nodes'])} activities, {len(graph_data['edges'])} links, "
          f"{len(graph_data['groups'])} groups, one for each part of the plan; {checked}")


if __name__ == "__main__":
    main()
