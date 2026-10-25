"""The state machine page format, and the conversion between a page and an OKB model payload.

A state machine page is an HTML page that carries its content in two JSON blocks,
`graph-data` and `state-machine-data`. `to_payload` turns those blocks into the
payload of an OKB model record. `to_blocks` turns a payload back into the two blocks.

What the drawing rules below decide (colours, shapes, borders, glyphs) is not stored.
Where a page differs from the rules, as some pages do, the
difference is stored on the node, under `page_overrides`, so the page comes back
unchanged.
"""
import hashlib
import json
import re
import uuid

# Ids the page does not carry are UUID version 5 names in this fixed namespace, made from what
# they name, so they stay the same when anything else on the page changes.
ID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "okb:state-machine")

# The drawing rules.
GROUP_PALETTE = ["#332288", "#88CCEE", "#44AA99", "#117733", "#999933",
                 "#DDCC77", "#CC6677", "#AA4499", "#882255"]
UNGROUPED_FILL = "#DDDDDD"
DARK_INK = "#0B0F18"
LIGHT_INK = "#FFFFFF"
PRECONDITION_DASHES = [2, 2]
SUPPORTING_DASHES = [7, 3]
GLYPH_LIMIT = 8

# Where each page type sits.
ROLE = {
    "Routine": ("node", "group"), "Route": ("node", "group"),
    "Start": ("node", "state"), "Activity": ("node", "state"), "End": ("node", "final"),
    "Dead end": ("node", "state"), "Gap": ("node", "state"),
    "Related machine": ("object", "state"), "Data": ("object", "state"),
    "Rule": ("object", "state"), "Object": ("object", "state"),
}
TYPE_TAG = {"Dead end": "dead-end", "Gap": "gap"}
# From vocabulary.js participationTagOf.
PARTICIPATION_TAG = {"precondition": "precondition", "supporting_process": "supporting"}
# The order a page lists a node's properties in.
PROPERTY_ORDER = ["mode", "stored_status", "future_state_model_id", "design_basis", "description", "handoff_text", "routine",
                  "reference", "evidence_status", "node_type", "actors", "applications",
                  "data_records", "carried_records"]
LINK_CATEGORY = {"actor": "actors", "application": "applications"}
LINK_TYPES = {"performed_by", "occurs_in", "reads_from", "writes_to"}
DRAWN_EDGE_TYPES = {"flow", "sequence", "consequence", "dependency"}


def model_type(type_label):
    # A Route group is a kind of routine; `route` is kept for the page's routes.
    return "route_group" if type_label == "Route" else type_label.lower().replace(" ", "_")


def page_type(node_type):
    for label in ROLE:
        if model_type(label) == node_type:
            return label
    raise ValueError(f"not a page node type: {node_type}")


# Colour and contrast, from vocabulary.js relativeLuminance, contrastRatio and labelInkFor.
def _luminance(hex_colour):
    def channel(value):
        value = int(value, 16) / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    h = hex_colour.lstrip("#")
    r, g, b = (channel(h[i:i + 2]) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _contrast(one, other):
    a, b = _luminance(one), _luminance(other)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def ink_for(fill):
    return LIGHT_INK if _contrast(fill, LIGHT_INK) >= _contrast(fill, DARK_INK) else DARK_INK


def group_number(reference):
    digits = re.findall(r"\d+", str(reference or ""))
    return int(digits[-1]) if digits else None


def glyph_for(reference):
    value = str(reference or "").strip()
    return "" if len(value) > GLYPH_LIMIT else value


def dashes_for(participation):
    if participation == "precondition":
        return list(PRECONDITION_DASHES)
    if participation == "supporting_process":
        return list(SUPPORTING_DASHES)
    return False


def participation_of(dashes):
    if dashes == PRECONDITION_DASHES:
        return "precondition"
    if dashes == SUPPORTING_DASHES:
        return "supporting_process"
    return None


def script_json(value):
    """JSON as a page holds it in a script block, with <, > and & escaped."""
    text = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    return text.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def read_blocks(page):
    blocks = {}
    for block_id in ("graph-data", "state-machine-data"):
        match = re.search(rf'<script type="application/json" id="{block_id}">(.*?)</script>', page, re.S)
        if not match:
            raise ValueError(f"the page has no {block_id} block")
        blocks[block_id] = json.loads(match.group(1))
    return blocks["graph-data"], blocks["state-machine-data"]


def ordered_properties(properties):
    known = [k for k in PROPERTY_ORDER if k in properties]
    return {k: properties[k] for k in known + sorted(k for k in properties if k not in PROPERTY_ORDER)}


# Building the two blocks from a payload.

def undrawable_types(payload):
    """The node types in a payload that a state machine page cannot draw, in name order."""
    drawable = {model_type(label) for label in ROLE} | {"state_machine", "actor", "application", "route"}
    return sorted({n["type"] for n in payload["graph"]["nodes"]} - drawable)


def to_blocks(payload):
    """The page's graph-data and state-machine-data, built from a model payload."""
    graph = payload["graph"]
    nodes, edges = graph["nodes"], graph["edges"]
    by_id = {n["id"]: n for n in nodes}
    machine = next((n for n in nodes if n["type"] == "state_machine"), None)
    # A model written as a payload, such as a routine from an interview, has no state machine
    # node. Its mode is its model kind, and each state shows the links it has.
    m = machine["attributes"] if machine else {"mode": payload["model_kind"].replace("_", " ")}
    linked = {e["source"] for e in edges if e["type"] in LINK_TYPES}
    drawn = [n for n in nodes if n["type"] not in ("state_machine", "actor", "application", "route")
             and n["type"] != "state_machine"]

    group_of = {e["source"]: e["target"] for e in edges if e["type"] == "part_of"}
    members = {}
    for source, target in group_of.items():
        members[target] = members.get(target, 0) + 1

    group_nodes = [n for n in drawn if ROLE[page_type(n["type"])][1] == "group"]
    ranked = sorted(group_nodes, key=lambda n: (group_number(n["attributes"].get("reference")) is None,
                                                 group_number(n["attributes"].get("reference")) or 0))
    rank = {n["id"]: i for i, n in enumerate(ranked)}
    style = {}
    for n in group_nodes:
        fill = GROUP_PALETTE[rank[n["id"]] % len(GROUP_PALETTE)]
        style[n["id"]] = (fill, ink_for(fill))

    links_of = {}
    for e in edges:
        if e["type"] in LINK_TYPES:
            target = by_id[e["target"]]
            category = LINK_CATEGORY.get(target["type"], "data")
            links_of.setdefault(e["source"], {"actors": [], "applications": [], "data": []})[category].append(
                {"id": e["target"], "name": e["attributes"].get("name", target["label"]),
                 "relationship": e["type"]})

    groups, page_nodes, detail = [], [], {}
    for n in drawn:
        a = dict(n["attributes"])
        overrides = a.pop("page_overrides", {})
        participation = a.pop("participation", None)
        has_links = a.pop("has_links", False) if machine else n["id"] in linked
        type_label = page_type(n["type"])
        kind, role = ROLE[type_label]
        group_key = n["id"] if role == "group" else group_of.get(n["id"], "")
        fill, ink = style.get(group_key, (UNGROUPED_FILL, DARK_INK))
        properties = ordered_properties(a)
        entry = {"name": n["label"], "type": type_label, "properties": properties}
        if has_links:
            entry["links"] = links_of.get(n["id"], {"actors": [], "applications": [], "data": []})
        detail[n["id"]] = {**entry, **overrides.get("detail", {})}

        weight = ("supporting" if type_label == "Route" else "primary") if role == "group" else None
        if kind == "object":
            shape = "box"
        elif role == "group":
            shape = "box" if weight == "supporting" else "circle"
        elif participation == "precondition":
            shape = "ellipse"
        else:
            shape = "box" if role == "final" else "circle"
        tags = [TYPE_TAG[type_label]] if type_label in TYPE_TAG else []
        tags += [PARTICIPATION_TAG[participation]] if participation in PARTICIPATION_TAG else []
        page = {"id": n["id"], "name": n["label"], "reference": a.get("reference", ""),
                "glyph": glyph_for(a.get("reference", "")), "groupKey": group_key,
                "kind": kind, "role": role}
        if weight:
            page["weight"] = weight
        page.update({"shape": shape, "typeLabel": type_label, "fill": fill, "ink": ink,
                     "border": DARK_INK, "borderWidth": 2, "dashes": dashes_for(participation),
                     "description": a.get("description", ""), "tags": tags,
                     "properties": {k: v for k, v in properties.items() if k != "description" and v != ""}})
        for key, value in overrides.get("node", {}).items():
            if value is None:
                page.pop(key, None)
            else:
                page[key] = value
        page = {k: page[k] for k in overrides.get("node_order", list(page))}
        page_nodes.append(page)

        if role == "group":
            group = {"key": n["id"], "nodeId": n["id"], "number": group_number(a.get("reference")),
                     "reference": a.get("reference", ""), "name": n["label"], "fill": fill, "ink": ink,
                     "count": members.get(n["id"], 0)}
            group.update(overrides.get("group", {}))
            groups.append(group)
    group_order = m.get("group_order")
    if group_order:
        groups.sort(key=lambda g: group_order.index(g["key"]))

    page_edges = [{"id": e["id"], "from": e["source"], "to": e["target"], "kind": e["type"],
                   "label": e["attributes"].get("label", "")}
                  for e in edges if e["type"] in DRAWN_EDGE_TYPES]

    routes = []
    for n in nodes:
        if n["type"] != "route":
            continue
        states = [e["source"] for e in edges if e["type"] == "in_route" and e["target"] == n["id"]]
        routes.append({"key": n["attributes"]["key"], "name": n["label"], "states": states,
                       "outcome": n["attributes"].get("outcome", "")})
    applications = []
    listed_apps = sorted((n for n in nodes if n["type"] == "application" and "listed" in n["attributes"]),
                         key=lambda n: n["attributes"]["listed"])
    for n in listed_apps:
        listed = [e["source"] for e in edges if e["type"] == "listed_in" and e["target"] == n["id"]]
        applications.append({"key": n["id"], "name": n["label"], "nodeIds": listed})

    # The page's own version value, where it had one, is kept as data and written back first.
    graph_data = {"version": m["template"]} if "template" in m else {}
    if "subject" in m:
        graph_data["subject"] = m["subject"]
    graph_data.update({"groups": groups, "nodes": page_nodes, "edges": page_edges})
    provenance = {"mode": m["mode"], "storedStatus": payload.get("source_status", "")}
    if "design" in m:
        provenance["design"] = dict(m["design"])  # stored as [key, value] pairs, to keep their order
    sm_data = {"provenance": provenance,
               "routes": routes, "applications": applications, "byId": detail}
    return graph_data, sm_data


# Building a payload from the two blocks.

def _id(*parts):
    return str(uuid.uuid5(ID_NAMESPACE, "|".join(parts)))


def to_payload(graph_data, sm_data, *, title, source_name, source_sha256, description):
    """A model payload that to_blocks turns back into the same two blocks."""
    by_detail = sm_data["byId"]
    machine_attributes = {"mode": sm_data["provenance"]["mode"]}
    if "version" in graph_data:
        machine_attributes["template"] = graph_data["version"]
    if "design" in sm_data["provenance"]:
        machine_attributes["design"] = [[k, v] for k, v in sm_data["provenance"]["design"].items()]
    if "subject" in graph_data:
        machine_attributes["subject"] = graph_data["subject"]
    nodes = [{"id": _id(title, "state-machine"), "type": "state_machine", "label": title,
              "attributes": machine_attributes}]
    edges = []
    known = set()
    for n in graph_data["nodes"]:
        d = by_detail[n["id"]]
        attributes = dict(d["properties"])
        participation = participation_of(n["dashes"])
        if participation:
            attributes["participation"] = participation
        if "links" in d:
            attributes["has_links"] = True
        nodes.append({"id": n["id"], "type": model_type(n["typeLabel"]), "label": n["name"],
                      "attributes": attributes})
        known.add(n["id"])
        if n["groupKey"] and n["groupKey"] != n["id"]:
            edges.append({"id": _id(n["id"], "part_of", n["groupKey"]), "source": n["id"],
                          "target": n["groupKey"], "type": "part_of", "attributes": {}})
    for e in graph_data["edges"]:
        edges.append({"id": e["id"], "source": e["from"], "target": e["to"], "type": e["kind"],
                      "attributes": {"label": e["label"]} if e["label"] else {}})

    extra = {}
    for d in by_detail.values():
        for category, links in d.get("links", {}).items():
            for link in links:
                if link["id"] not in known:
                    extra.setdefault(link["id"], ({"actors": "actor", "applications": "application"}
                                                  .get(category, "data"), link["name"]))
    for a in sm_data.get("applications", []):
        if a["key"] not in known:
            extra.setdefault(a["key"], ("application", a["name"]))
    for node_id, (node_type, name) in extra.items():
        nodes.append({"id": node_id, "type": node_type, "label": name, "attributes": {}})
        known.add(node_id)
    by_node = {n["id"]: n for n in nodes}
    for source, d in by_detail.items():
        for category, links in d.get("links", {}).items():
            for link in links:
                attributes = {} if by_node[link["id"]]["label"] == link["name"] else {"name": link["name"]}
                edges.append({"id": _id(source, link["relationship"], link["id"], category),
                              "source": source, "target": link["id"], "type": link["relationship"],
                              "attributes": attributes})
    for position, a in enumerate(sm_data.get("applications", [])):
        by_node[a["key"]]["attributes"]["listed"] = position
        for node_id in a["nodeIds"]:
            edges.append({"id": _id(node_id, "listed_in", a["key"]), "source": node_id,
                          "target": a["key"], "type": "listed_in", "attributes": {}})
    for r in sm_data["routes"]:
        route_id = _id(title, "route", r["key"])
        nodes.append({"id": route_id, "type": "route", "label": r["name"],
                      "attributes": {"key": r["key"], "outcome": r["outcome"]}})
        for position, state in enumerate(r["states"]):
            edges.append({"id": _id(state, "in_route", route_id, str(position)), "source": state,
                          "target": route_id, "type": "in_route", "attributes": {}})

    payload = {"model_kind": "proposed_target" if sm_data["provenance"]["mode"] == "proposal" else "observed_current",
               "source_version": f"{source_name}, sha256 {source_sha256}",
               "source_status": sm_data["provenance"]["storedStatus"],
               "description": description,
               "graph": {"format_version": 1, "nodes": nodes, "edges": edges}}

    # Record where the page differs from what the rules draw, so it comes back unchanged.
    graph_back, sm_back = to_blocks(stored(payload))
    back_nodes = {n["id"]: n for n in graph_back["nodes"]}
    back_groups = {g["key"]: g for g in graph_back["groups"]}
    for n in graph_data["nodes"]:
        overrides = {}
        built = back_nodes[n["id"]]
        node_diff = {k: v for k, v in n.items() if built.get(k, object()) != v}
        node_diff.update({k: None for k in built if k not in n})
        if node_diff:
            overrides["node"] = node_diff
        if list(n) != list({**built, **{k: v for k, v in node_diff.items() if v is not None}}):
            overrides["node_order"] = list(n)
        if json.dumps(by_detail[n["id"]]) != json.dumps(sm_back["byId"][n["id"]]):
            overrides["detail"] = {k: v for k, v in by_detail[n["id"]].items()
                                   if json.dumps(sm_back["byId"][n["id"]].get(k)) != json.dumps(v)}
        g = next((g for g in graph_data["groups"] if g["key"] == n["id"]), None)
        if g:
            group_diff = {k: v for k, v in g.items() if back_groups[g["key"]].get(k) != v}
            if group_diff:
                overrides["group"] = group_diff
        if overrides:
            by_node[n["id"]]["attributes"]["page_overrides"] = overrides
    if [g["key"] for g in graph_data["groups"]] != [g["key"] for g in graph_back["groups"]]:
        machine_attributes["group_order"] = [g["key"] for g in graph_data["groups"]]
    return payload


def stored(payload):
    """The payload as OKB gives it back: JSON objects lose their key order."""
    def canonical(value):
        if isinstance(value, dict):
            return {k: canonical(value[k]) for k in sorted(value, key=lambda k: (len(k.encode()), k.encode()))}
        if isinstance(value, list):
            return [canonical(v) for v in value]
        return value
    return canonical(json.loads(json.dumps(payload)))


def page_sha256(page_bytes):
    return hashlib.sha256(page_bytes).hexdigest()
