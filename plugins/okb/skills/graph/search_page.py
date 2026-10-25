"""Draw a page that shows how a file search found its answer.

Usage: python3 search_page.py <search.json> <page.html> --question QUESTION

The search file is what the file-search function's result_file holds, best from a call with
"explain": true. The page draws one card for each hit, the reference hits first, each with the passage
it came from: the question's words marked as with a yellow marker pen, each measured sentence shaded
blue by how near its meaning is to the question's, and each entity the graph walk reached underlined
in green. A green panel plays the graph walk, step by step, from its starting points to the hits.
Positions in the search count characters, as Python's strings do. The page is drawn with
search-shell.html, beside this script, and needs no network to open.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "board"))
import model_to_page as mtp  # noqa: E402
import page_check  # noqa: E402
import state_machine_page as smp  # noqa: E402

SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "search-shell.html")
START, STOP = "", ""
WAYS = ("words", "meaning", "graph")
# The graph panel's columns: the starting points, then each step of the walk.
COLUMN_GAP, ROW_GAP, TOP, LEFT = 300, 30, 40, 20


def marks_of(marked, text):
    """The marked words' places in text, as [start, end] pairs, and whether marked is text with marks."""
    marks, plain, at, opened = [], [], 0, None
    for ch in marked:
        if ch == START:
            opened = at
        elif ch == STOP:
            if opened is not None and at > opened:
                marks.append([opened, at])
            opened = None
        else:
            plain.append(ch)
            at += 1
    return marks, "".join(plain) == text


def names_in(text, entities):
    """Each place in text where an entity's name stands as a word, ignoring case, as [start, end, id].
    A longer name takes a place before a shorter one inside it."""
    found, taken = [], [False] * len(text)
    for entity_id, name in sorted(entities.items(), key=lambda e: -len(e[1])):
        if len(name.strip()) < 2:
            continue
        for m in re.finditer(r"(?<!\w)" + re.escape(name.strip()) + r"(?!\w)", text, re.IGNORECASE):
            if not any(taken[m.start():m.end()]):
                found.append([m.start(), m.end(), entity_id])
                for i in range(m.start(), m.end()):
                    taken[i] = True
    return sorted(found)


def graph_of(stages):
    """The walk laid out once: each entity in the column of the earliest step that reaches it, the
    starting points first, and each edge as the search gave it."""
    seeds = stages.get("graph_seeds") or []
    walk = stages.get("graph_walk") or []
    nodes = {}
    for s in seeds:
        nodes.setdefault(s["entity_id"], {"id": s["entity_id"], "name": s["name"], "type": s.get("type") or "",
                                          "step": 0, "seed": True, "similarity": s.get("similarity")})
    for e in sorted(walk, key=lambda e: e["step"]):
        for end, name, step in ((e["from"], e["from_name"], e["step"] - 1), (e["to"], e["to_name"], e["step"])):
            if end not in nodes:
                nodes[end] = {"id": end, "name": name, "type": "", "step": step, "seed": False, "similarity": None}
    columns = {}
    for n in nodes.values():
        columns.setdefault(n["step"], []).append(n)
    for step, members in columns.items():
        members.sort(key=lambda n: (-(n["similarity"] or 0), n["name"].casefold()))
        for row, n in enumerate(members):
            n["x"], n["y"] = LEFT + step * COLUMN_GAP, TOP + row * ROW_GAP
    edges = [{"from": e["from"], "to": e["to"], "step": e["step"], "keywords": e.get("keywords") or [],
              "weight": e.get("weight"), "relation": e.get("relation")} for e in walk]
    height = TOP + max((len(m) for m in columns.values()), default=0) * ROW_GAP
    return {"nodes": list(nodes.values()), "edges": edges, "steps": max((e["step"] for e in walk), default=0),
            "width": LEFT * 2 + max(columns, default=0) * COLUMN_GAP + 240, "height": height}


def to_search_data(result, question):
    """The page's search-data block, and its findings."""
    stages = result.get("stages") or {}
    graph = graph_of(stages)
    entity_names = {n["id"]: n["name"] for n in graph["nodes"]}
    hits = [dict(h, reference=True) for h in result.get("reference_hits") or []] + \
           [dict(h, reference=False) for h in result.get("hits") or []]
    findings = []
    sections = []
    for at, s in enumerate(result.get("sections") or []):
        text = s.get("text") or ""
        marks = []
        if s.get("marked") is not None:
            marks, same = marks_of(s["marked"], text)
            if not same:
                findings.append(f"Section {at + 1}, {s.get('file')}: its marked text, without its marks, is not its text.")
        # Each name a hit in this section gives, and each entity the walk reached.
        names = dict(entity_names)
        for h in hits:
            if h.get("section") == at:
                for e in h.get("entities") or []:
                    names.setdefault(e.get("entity_id"), e.get("name") or "")
        sections.append({"file": s.get("file"), "place": s.get("place"), "text": text, "marks": marks,
                         "entities": names_in(text, {k: v for k, v in names.items() if k}),
                         "truncated": bool(s.get("truncated")), "before": s.get("before"), "after": s.get("after")})
    cards = []
    # explain_ms is the function's own sign that it explained the search, with or without sentences.
    explained = "explain_ms" in result
    for n, h in enumerate(hits, 1):
        section = h.get("section")
        if not isinstance(section, int) or not 0 <= section < len(sections):
            findings.append(f"Hit {n}, {h.get('file')}: its section is not in the search.")
            section = None
        length = len(sections[section]["text"]) if section is not None else 0
        sentences = []
        for s in h.get("sentences") or []:
            if not 0 <= s["start"] < s["end"] <= length:
                findings.append(f"Hit {n}, {h.get('file')}: a sentence lies outside its section.")
                continue
            sentences.append(s)
        chunk = h.get("chunk")
        if chunk and not 0 <= chunk["start"] < chunk["end"] <= length:
            findings.append(f"Hit {n}, {h.get('file')}: its chunk lies outside its section.")
            chunk = None
        cards.append({"n": n, "reference": h["reference"], "file": h.get("file"), "place": h.get("place"),
                      "bucket": h.get("bucket"), "score": h.get("fusion_score"), "found": h.get("found") or [],
                      "ranks": h.get("ranks") or {}, "similarity": h.get("similarity"), "graphWeight": h.get("graph_weight"),
                      "section": section, "chunk": chunk, "sentences": sentences,
                      "entities": [{"id": e.get("entity_id"), "name": e.get("name"), "steps": e.get("steps")}
                                   for e in h.get("entities") or []]})
    if not explained:
        findings.append("The search was not explained, so no sentence is shaded. Search again with explain.")
    if "graph_walk" not in stages:
        findings.append("The search gives no graph walk: OKB's file search is older than this page.")
    counts = {way: stages.get(way) for way in WAYS} | {"fused": stages.get("fused"), "returned": stages.get("returned")}
    return {"question": question, "counts": counts, "cards": cards, "sections": sections, "graph": graph,
            "explained": explained, "explainMs": result.get("explain_ms"), "degraded": result.get("degraded"),
            "awaiting": stages.get("awaiting_sentence_vector")}, findings


def counts_line(counts):
    return (f"Words found {counts['words']}, meaning {counts['meaning']} and the graph {counts['graph']}; "
            f"{counts['fused']} merged, {counts['returned']} returned.")


def outline(page_path, data, findings):
    """The page's outline, in the order the page draws it, and its picture. Returns a line for the tool's output."""
    by_id = {n["id"]: n for n in data["graph"]["nodes"]}
    lines = [f"# Search: {data['question']}", "", counts_line(data["counts"]), ""]
    if data["degraded"]:
        lines += [f"Degraded: {data['degraded']}", ""]
    if data["explained"] and not any(c["sentences"] for c in data["cards"]):
        lines += [f"No hit's sentences have their vectors yet: {data['awaiting']} are waiting.", ""]
    lines += ["Each card in order: its number, file and place, fusion score, then each way that found it with its rank.",
              "Under it are its similarity, its marked words, its shaded sentences and the entities it names.", ""]
    for c in data["cards"]:
        ways = ", ".join(f"{w} {c['ranks'].get(w)}" for w in WAYS if w in c["found"])
        lines.append(f"## {c['n']}. {c['file']}{' · ' + c['place'] if c['place'] else ''}{' · reference' if c['reference'] else ''}")
        lines.append(f"Fusion score {c['score']} · {ways}")
        if c["similarity"] is not None:
            lines.append(f"Similarity {c['similarity']}")
        if c["section"] is not None:
            s = data["sections"][c["section"]]
            words = sorted({s["text"][a:b].lower() for a, b in s["marks"]})
            lines.append(f"Marked words: {', '.join(words) if words else 'none'}")
            if c["chunk"] is None:
                lines.append("Its chunk lies outside the part of the section returned.")
            if s["truncated"]:
                lines.append(f"Part of the section: {s['before']} characters before and {s['after']} after are left out.")
        if c["sentences"]:
            top = max(c["sentences"], key=lambda x: x["similarity"])
            text = data["sections"][c["section"]]["text"][top["start"]:top["end"]]
            lines.append(f"Sentences shaded: {len(c['sentences'])}, nearest {top['similarity']}: {' '.join(text.split())[:160]}")
        if c["entities"]:
            lines.append("Entities: " + ", ".join(f"{e['name']} (step {e['steps']})" for e in c["entities"]))
        lines.append("")
    g = data["graph"]
    lines += ["## Graph walk", "", f"{sum(1 for n in g['nodes'] if n['seed'])} starting points, {len(g['nodes'])} entities, "
              f"{len(g['edges'])} relations, {g['steps']} steps.", ""]
    for n in g["nodes"]:
        if n["seed"]:
            lines.append(f"- Start: {n['name']} · similarity {n['similarity']}")
    for e in g["edges"]:
        lines.append(f"- Step {e['step']}: {by_id[e['from']]['name']} → {by_id[e['to']]['name']}"
                     + (f" ({', '.join(e['keywords'])})" if e["keywords"] else ""))
    lines.append("")
    lines.extend(page_check.findings_lines(findings))
    page_check.write(page_path, lines)
    # The picture starts from the first card with shaded sentences, under the question and beside the graph panel.
    shaded = next((c["n"] for c in data["cards"] if c["sentences"]), None)
    return f"outline written; {len(findings)} findings; {page_check.picture(page_path, 1400, f'#from-{shaded}' if shaded else '')}"


def fill(shell, title, data):
    body = shell.split("-->", 1)[1].lstrip("\n")
    page = shell[:shell.index("<!--")] + body
    for slot, value in (("{{SEARCH_DATA_JSON}}", smp.script_json(data)), ("{{TITLE}}", mtp.html_escape(title))):
        if slot not in page:
            raise ValueError(f"search-shell.html has no {slot}")
        page = page.replace(slot, value)
    return page


def main():
    parser = argparse.ArgumentParser(description="Draw a page that shows how a file search found its answer.")
    parser.add_argument("search")
    parser.add_argument("page")
    parser.add_argument("--question", default="")
    args = parser.parse_args()
    question = " ".join(args.question.split())
    if not question:
        raise SystemExit("give the question the search was asked; no page was drawn")
    result = json.load(open(args.search, encoding="utf-8"))
    if isinstance(result, dict) and isinstance(result.get("body"), dict):
        result = result["body"]
    if not isinstance(result, dict) or "hits" not in result or "sections" not in result:
        raise SystemExit("the file does not hold a file search's result; no page was drawn")
    data, findings = to_search_data(result, question)
    page = fill(open(SHELL, encoding="utf-8").read(), f"How the search found: {question}", data)
    with open(args.page, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    checked = outline(args.page, data, findings)
    c, g = data["counts"], data["graph"]
    shaded = sum(len(card["sentences"]) for card in data["cards"])
    print(f"wrote {args.page} ({len(page.encode())} bytes): {len(data['cards'])} hits, {shaded} sentences shaded, "
          f"{len(g['nodes'])} entities and {len(g['edges'])} relations in {g['steps']} steps; {counts_line(c)} {checked}")


if __name__ == "__main__":
    main()
