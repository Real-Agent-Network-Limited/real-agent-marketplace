"""Turn a state machine page into the payload of an OKB model record.

Usage: python3 page_to_model.py <page.html> <payload.json> [--description TEXT]

The page is an HTML page with a `graph-data` and a `state-machine-data` JSON block.
The payload is written as JSON, ready to be the `payload` of a model record saved in OKB. The
record's title is the page's heading, printed at the end.
"""
import argparse
import html
import json
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import state_machine_page as smp  # noqa: E402

NODE_LIMITS = {"id": 100, "type": 100, "label": 500}
EDGE_LIMITS = {"id": 100, "source": 100, "target": 100, "type": 100}
# OKB refuses a save request, and a payload, whose text is longer than 262,144 bytes. The request
# wraps the payload with its ids, title, reason and links, so the payload keeps room for them.
PAYLOAD_LIMIT = 262144 - 1024


def heading(page):
    """The page's heading, or its title where an older page has no heading."""
    match = (re.search(r'<h1 class="ttl">(.*?)</h1>', page, re.S)
             or re.search(r"<title>(.*?)</title>", page, re.S))
    if not match or not match.group(1).strip():
        raise ValueError("the page has no heading or title")
    return html.unescape(match.group(1)).strip()


def check(payload):
    """The checks OKB makes on a model's graph, so a refusal shows here first."""
    graph = payload["graph"]
    nodes, edges = graph["nodes"], graph["edges"]
    ids = [n["id"] for n in nodes]
    if len(ids) != len(set(ids)):
        raise ValueError("two nodes share an id")
    if len({e["id"] for e in edges}) != len(edges):
        raise ValueError("two edges share an id")
    # Measured as the database writes JSON as text, with a space after each comma and colon.
    size = len(json.dumps(payload, ensure_ascii=False).encode())
    if size > PAYLOAD_LIMIT:
        raise ValueError(f"the payload is {size} bytes, too near OKB's limit of 262,144 bytes for a save; "
                         f"at most {PAYLOAD_LIMIT} leaves room for the rest of the request")
    if len(nodes) > 1000 or len(edges) > 5000:
        raise ValueError(f"OKB takes at most 1000 nodes and 5000 edges; this has {len(nodes)} and {len(edges)}")
    known = set(ids)
    for e in edges:
        if e["source"] not in known or e["target"] not in known:
            raise ValueError(f"edge {e['id']} has an end that is not a node")
    for items, limits in ((nodes, NODE_LIMITS), (edges, EDGE_LIMITS)):
        for item in items:
            for key, limit in limits.items():
                if not item[key] or len(item[key]) > limit:
                    raise ValueError(f"{key} of {item['id']} is empty or longer than {limit} characters")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("page")
    parser.add_argument("payload")
    parser.add_argument("--description", help="what the model describes; the page's heading if left out")
    args = parser.parse_args()

    raw = open(args.page, "rb").read()
    page = raw.decode("utf-8")
    graph_data, sm_data = smp.read_blocks(page)
    title = heading(page)
    payload = smp.to_payload(graph_data, sm_data, title=title,
                             source_name=os.path.basename(args.page),
                             source_sha256=smp.page_sha256(raw),
                             description=args.description or f"{title}, from the state machine page "
                                                             f"{os.path.basename(args.page)}.")
    check(payload)
    back_graph, back_sm = smp.to_blocks(smp.stored(payload))
    if smp.script_json(back_graph) != smp.script_json(graph_data) or smp.script_json(back_sm) != smp.script_json(sm_data):
        raise SystemExit("the payload would not give the page back unchanged; nothing was written")
    with open(args.payload, "w", encoding="utf-8", newline="\n") as out:
        json.dump(payload, out, ensure_ascii=False, indent=1)

    graph = payload["graph"]
    overrides = sum(1 for n in graph["nodes"] if "page_overrides" in n["attributes"])
    print(f"wrote {args.payload}")
    print(f"title: {title}")
    print(f"nodes: {len(graph['nodes'])} {dict(Counter(n['type'] for n in graph['nodes']))}")
    print(f"edges: {len(graph['edges'])} {dict(Counter(e['type'] for e in graph['edges']))}")
    print(f"nodes drawn differently from the rules, stored as overrides: {overrides}")


if __name__ == "__main__":
    main()
