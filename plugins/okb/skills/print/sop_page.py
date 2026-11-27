"""Write a standard operating procedure (SOP) for one routine as an A4 page, from its version in force.

Usage: python3 sop_page.py <model.json> <glossary.json> <in-force.json> <page.html> --picture NAME [--version-id ID] [--brand=<brand.json>]

The in-force file is what okb_routine_in_force returns for the model and the one routine, naming its version in
force and the approval that put it in force. The model is that version: what okb_get_record returns, {"cutoff",
"version", "links"}, read with the version's change_no as p_cutoff, a version on its own, or a page of
okb_get_history. Any other version is refused. It is a routine model, as the graph skill's "The state machine model"
sets out. The glossary is what okb_get_reference returns for the glossary. NAME is the picture of the routine's state
machine page, a file beside the page, as draw_state_machine writes it.

The SOP names the routine's version and its approval on its first page, and holds the routine's purpose, its trigger,
each of its states with who does it, what they do, the tool, the checks and its run attributes, the handovers, the
exceptions, the drawn state machine, and the glossary terms it uses. It sets @page to A4, for the print skill's print_pdf.py. Beside the page, the board skill's
`page_check.py` writes its outline, and its picture where a Chromium browser is found.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "board"))
import a4  # noqa: E402
import page_check  # noqa: E402
from page_check import run_lines  # noqa: E402

esc = a4.esc
STATE_TYPES = ("start", "activity", "end", "dead_end", "gap")
TYPE_NAMES = {"start": "Start", "activity": "Step", "end": "End", "dead_end": "Dead end", "gap": "Gap"}
KIND_NAMES = {"proposed_target": "approved design", "observed_current": "current state, as confirmed"}


def natural(text):
    return [(0, int(p), "") if p.isdigit() else (1, 0, p.lower()) for p in re.split(r"(\d+)", str(text or "")) if p]


def model_version(value, version_id):
    """The model's version, from what okb_get_record or okb_get_history returns, or a version on its own."""
    if value is None:
        raise SystemExit("the record does not exist, or you may not read it; no page was written")
    if isinstance(value, dict) and isinstance(value.get("items"), list):
        if not version_id:
            raise SystemExit("the model file is a page of okb_get_history, and no version in force is named; no page was written")
        found = [v for v in value["items"] if v.get("version_id") == version_id]
        if not found:
            raise SystemExit(f"the history page holds no version {version_id}; no page was written")
        version = found[0]
    elif isinstance(value, dict) and "deleted" in value and "version" not in value:
        raise SystemExit("the record was deleted; no page was written")
    else:
        version = value.get("version", value) if isinstance(value, dict) else None
        if version_id and isinstance(version, dict) and version.get("version_id") != version_id:
            raise SystemExit(f"the model file holds version {version.get('version_id')}, not {version_id}, the version in force; read it with okb_get_record and its change_no as p_cutoff; no page was written")
    if not isinstance(version, dict) or not isinstance((version.get("payload") or {}).get("graph"), dict):
        raise SystemExit("the file does not hold a model record's version; no page was written")
    return version


def in_force_of(value):
    """The one routine okb_routine_in_force names, with its version in force and its approval."""
    if value is None:
        raise SystemExit("the in-force file names no model you may read; no page was written")
    if not isinstance(value, dict) or not isinstance(value.get("routines"), list):
        raise SystemExit("the in-force file is not okb_routine_in_force's result; no page was written")
    if not value["routines"]:
        raise SystemExit("no version of the routine is in force: no approval of it supports a version; no page was written")
    if len(value["routines"]) > 1:
        names = ", ".join(f"{r['routine'].get('reference', '')} {r['routine'].get('name', '')}".strip() for r in value["routines"])
        raise SystemExit(f"the in-force file names {len(value['routines'])} routines, {names}; call okb_routine_in_force with p_routine "
                         "for the one to print; no page was written")
    return value["routines"][0]


def build(version, glossary, picture, in_force=None):
    payload = version["payload"]
    graph = payload["graph"]
    nodes = {n["id"]: n for n in graph.get("nodes", [])}
    edges = graph.get("edges", [])
    attr = lambda n: n.get("attributes") or {}
    linked = lambda source, kind: [nodes[e["target"]] for e in edges if e["source"] == source and e.get("type") == kind and e["target"] in nodes]
    states = sorted((n for n in nodes.values() if n.get("type") in STATE_TYPES), key=lambda n: (natural(attr(n).get("reference")), n["label"]))
    part_of = {e["source"]: e["target"] for e in edges if e.get("type") == "part_of"}
    routines = sorted((n for n in nodes.values() if n.get("type") in ("routine", "route_group")), key=lambda n: natural(attr(n).get("reference")))
    # The routine in force alone, of a workflow of several.
    named = (in_force or {}).get("routine") or {}
    if named.get("type") in ("routine", "route_group"):
        routines = [r for r in routines if r["type"] == named["type"] and r["label"] == named.get("name")
                    and str(attr(r).get("reference", "")) == named.get("reference", "")]
        if not routines:
            raise SystemExit(f"the model version holds no routine {named.get('reference', '')} {named.get('name', '')}; no page was written")
        states = [s for s in states if part_of.get(s["id"]) == routines[0]["id"]]
    if not states:
        raise SystemExit("the model has no states: it is not a routine model; no page was written")
    findings = []

    def who(s):
        return [a["label"] for a in linked(s["id"], "performed_by")]

    steps = []
    for s in states:
        checks = [{"name": r["label"], "text": attr(r).get("description", "")} for e in edges
                  if e["source"] == s["id"] and e.get("type") in ("dependency", "consequence") and nodes.get(e["target"], {}).get("type") == "rule"
                  for r in [nodes[e["target"]]]]
        step = {"id": s["id"], "reference": attr(s).get("reference", ""), "name": s["label"], "type": TYPE_NAMES.get(s["type"], s["type"]),
                "routine": nodes[part_of[s["id"]]]["label"] if part_of.get(s["id"]) in nodes else "",
                "who": who(s), "what": attr(s).get("description", ""),
                "tools": [a["label"] for a in linked(s["id"], "occurs_in")],
                "reads": [d["label"] for d in linked(s["id"], "reads_from")], "writes": [d["label"] for d in linked(s["id"], "writes_to")],
                "checks": checks, "run": run_lines(attr(s)),
                "next": [nodes[e["target"]]["label"] for e in edges if e["source"] == s["id"] and e.get("type") in ("flow", "sequence") and e["target"] in nodes]}
        if s["type"] in ("start", "activity") and not step["who"]:
            findings.append(f"{step['reference'] or step['name']} {step['name']}: no one is named as doing it")
        if not step["what"].strip():
            findings.append(f"{step['reference'] or step['name']} {step['name']}: the model says nothing of what is done")
        steps.append(step)
    triggers = [s for s in steps if s["type"] == "Start"]
    if not triggers:
        findings.append("The routine has no start state, so the SOP names no trigger")
    handovers = [{"routine": r["label"], "text": attr(r).get("handoff_text", "")} for r in routines if attr(r).get("handoff_text", "").strip()]
    by_id = {s["id"]: s for s in steps}
    for e in edges:
        if e.get("type") in ("flow", "sequence") and e["source"] in by_id and e["target"] in by_id:
            a, b = by_id[e["source"]], by_id[e["target"]]
            if a["who"] and b["who"] and set(a["who"]) != set(b["who"]):
                handovers.append({"routine": "", "text": f"From {a['name']} ({', '.join(a['who'])}) to {b['name']} ({', '.join(b['who'])})."})
    exceptions = [s for s in steps if s["type"] in ("Dead end", "Gap")]
    rules = [{"name": n["label"], "text": attr(n).get("description", "")} for n in nodes.values() if n.get("type") == "rule"]

    # The glossary terms the SOP uses: each term or other name found as a whole word in its text.
    words = " ".join([version.get("title", ""), payload.get("description", "")]
                     + [" ".join([s["name"], s["what"], *s["who"], *s["tools"], *s["reads"], *s["writes"]] + [c["name"] + " " + c["text"] for c in s["checks"]]) for s in steps]
                     + [h["text"] for h in handovers] + [r["name"] + " " + r["text"] for r in rules]
                     + [attr(r).get("description", "") for r in routines])
    used = []
    for row in glossary:
        for name in [row["term"], *(row.get("other_names") or [])]:
            if name and re.search(r"(?<![\w])" + re.escape(name) + r"(?![\w])", words, re.I):
                used.append(row)
                break
    approval = (in_force or {}).get("approval") or {}
    return {"title": version.get("title", "Routine"), "version_number": version.get("version_number"), "version_id": version.get("version_id"),
            "routine": (f"{named.get('reference', '')} {named.get('name', '')}".strip() if named.get("type") in ("routine", "route_group") else ""),
            "approval": {"title": approval.get("title", ""), "decided_on": approval.get("decided_on", ""), "decided_by": approval.get("decided_by_name") or ""},
            "model_kind": payload.get("model_kind"), "purpose": payload.get("description", ""),
            "routines": [{"name": r["label"], "reference": attr(r).get("reference", ""), "text": attr(r).get("description", "")} for r in routines],
            "triggers": [s["id"] for s in triggers], "steps": steps, "handovers": handovers, "exceptions": [s["id"] for s in exceptions],
            "rules": rules, "terms": [{"term": t["term"], "kind": t.get("kind"), "definition": t.get("definition")} for t in used],
            "picture": picture, "findings": findings}


def listed(items):
    return ", ".join(items) if items else "None named"


def fill(data):
    by_id = {s["id"]: s for s in data["steps"]}
    kind = KIND_NAMES.get(data["model_kind"], data["model_kind"] or "model")
    a = data["approval"]
    b = [f"<h1>{esc(data['title'])}{(': ' + esc(data['routine'])) if data['routine'] else ''}</h1>",
         f'<p class="meta">Standard operating procedure, printed from OKB on {esc(a4.printed_on())}, from model version '
         f"{esc(data['version_number'])}, the {esc(kind)}.</p>",
         f'<p class="meta">Version {esc(data["version_number"])} is the version in force: approved by {esc(a["decided_by"] or "an approver OKB does not name")}'
         f" on {esc(a['decided_on'])}, in the decision {esc(a['title'])}.</p>",
         "<h2>Purpose</h2>", f"<p>{esc(data['purpose']) or '<span class=none>The model states no purpose.</span>'}</p>"]
    for r in data["routines"]:
        if r["text"]:
            b.append(f"<p><b>{esc((r['reference'] + ' ') if r['reference'] else '')}{esc(r['name'])}:</b> {esc(r['text'])}</p>")
    b.append("<h2>Trigger</h2>")
    if data["triggers"]:
        b.append("<ul>" + "".join(f"<li><b>{esc(by_id[t]['name'])}</b>: {esc(by_id[t]['what'])} ({esc(listed(by_id[t]['who']))})</li>" for t in data["triggers"]) + "</ul>")
    else:
        b.append('<p class="none">The routine has no start state.</p>')
    b += ["<h2>The state machine</h2>", f'<figure><img src="{esc(data["picture"])}" alt="The state machine of {esc(data["title"])}">'
          f"<figcaption>The routine's state machine, drawn from model version {esc(data['version_number'])}.</figcaption></figure>",
          "<h2>Each state</h2>"]
    for s in data["steps"]:
        checks = "".join(f"<li><b>{esc(c['name'])}</b>{(': ' + esc(c['text'])) if c['text'] else ''}</li>" for c in s["checks"])
        b.append(f'<div class="state"><h3>{esc((s["reference"] + " ") if s["reference"] else "")}{esc(s["name"])} · {esc(s["type"])}</h3><dl>'
                 f"<dt>Who</dt><dd>{esc(listed(s['who']))}</dd><dt>What</dt><dd>{esc(s['what']) or '<span class=none>Not stated</span>'}</dd>"
                 f"<dt>Tool</dt><dd>{esc(listed(s['tools']))}</dd>"
                 f"<dt>Checks</dt><dd>{'<ul>' + checks + '</ul>' if checks else 'None named'}</dd>"
                 + (f"<dt>Reads</dt><dd>{esc(', '.join(s['reads']))}</dd>" if s["reads"] else "")
                 + (f"<dt>Writes</dt><dd>{esc(', '.join(s['writes']))}</dd>" if s["writes"] else "")
                 + "".join(f"<dt>{esc(label)}</dt><dd>{esc(text)}</dd>" for label, text in s["run"])
                 + (f"<dt>Next</dt><dd>{esc(', '.join(s['next']))}</dd>" if s["next"] else "") + "</dl></div>")
    b.append("<h2>Handovers</h2>")
    b.append("<ul>" + "".join(f"<li>{('<b>' + esc(h['routine']) + ':</b> ') if h['routine'] else ''}{esc(h['text'])}</li>" for h in data["handovers"]) + "</ul>"
             if data["handovers"] else '<p class="none">The model names no handover.</p>')
    b.append("<h2>Exceptions</h2>")
    ex = [f"<li><b>{esc(by_id[x]['name'])}</b> ({esc(by_id[x]['type'].lower())}): {esc(by_id[x]['what'])}</li>" for x in data["exceptions"]]
    b.append("<ul>" + "".join(ex) + "</ul>" if ex else '<p class="none">The model names no dead end or gap.</p>')
    if data["rules"]:
        b.append("<h3>Rules the routine keeps</h3><ul>" + "".join(f"<li><b>{esc(r['name'])}</b>{(': ' + esc(r['text'])) if r['text'] else ''}</li>" for r in data["rules"]) + "</ul>")
    b.append("<h2>Terms</h2>")
    b.append("<table><thead><tr><th>Term</th><th>Meaning</th></tr></thead><tbody>"
             + "".join(f"<tr><td><b>{esc(t['term'])}</b></td><td>{esc(t['definition'])}</td></tr>" for t in data["terms"]) + "</tbody></table>"
             if data["terms"] else '<p class="none">The SOP uses no term from the glossary.</p>')
    return "\n".join(b)


def outline(data):
    by_id = {s["id"]: s for s in data["steps"]}
    a = data["approval"]
    lines = [f"# SOP: {data['title']}{(': ' + data['routine']) if data['routine'] else ''}", "", f"Model version {data['version_number']}, {data['model_kind']}.", "",
             f"In force: approved by {a['decided_by'] or 'an approver OKB does not name'} on {a['decided_on']}, in the decision {a['title']}.", "",
             "## Purpose", "", data["purpose"] or "None stated.", "", "## Trigger", ""]
    lines += [f"- {by_id[t]['name']}: {by_id[t]['what']}" for t in data["triggers"]] or ["None."]
    lines += ["", "## The state machine", "", f"Picture: {data['picture']}", "", "## Each state", ""]
    for s in data["steps"]:
        lines.append(f"- {(s['reference'] + ' ') if s['reference'] else ''}{s['name']} · {s['type']} · who: {listed(s['who'])} · tool: {listed(s['tools'])}"
                     + f" · checks: {', '.join(c['name'] for c in s['checks']) or 'none'}"
                     + "".join(f" · {label.lower()}: {text}" for label, text in s["run"]))
    lines += ["", "## Handovers", ""] + ([f"- {h['text']}" for h in data["handovers"]] or ["None."])
    lines += ["", "## Exceptions", ""] + ([f"- {by_id[x]['name']}" for x in data["exceptions"]] or ["None."])
    lines += ["", "## Terms", ""] + ([f"- {t['term']}" for t in data["terms"]] or ["None."]) + [""]
    return lines


def main():
    parser = argparse.ArgumentParser(description="Write an SOP for one routine from its model version.")
    parser.add_argument("model")
    parser.add_argument("glossary")
    parser.add_argument("in_force")
    parser.add_argument("page")
    parser.add_argument("--picture", required=True, help="the state machine page's picture, beside the page")
    parser.add_argument("--version-id", default="")
    parser.add_argument("--brand", default="", help="the firm's brand, as the okb plugin writes it")
    args = parser.parse_args()
    if "/" in args.picture or "\\" in args.picture or args.picture.startswith("."):
        raise SystemExit("the picture is named by its file name alone, beside the page; no page was written")
    in_force = in_force_of(a4.read(args.in_force))
    if args.version_id and args.version_id != in_force["version_id"]:
        raise SystemExit(f"version {args.version_id} is not the version in force, {in_force['version_id']}; no page was written")
    version = model_version(a4.read(args.model), in_force["version_id"])
    glossary = a4.read(args.glossary)
    if not isinstance(glossary, dict) or glossary.get("part") != "glossary" or not isinstance(glossary.get("rows"), list):
        raise SystemExit("the glossary file is not okb_get_reference's result for the glossary; no page was written")
    data = build(version, glossary["rows"], args.picture, in_force)
    brand = a4.read_brand(args.brand)
    page = a4.page(f"SOP: {data['title']}", fill(data), "sop-data", data, brand)
    with open(args.page, "w", encoding="utf-8", newline="\n") as out:
        out.write(page)
    page_check.write(args.page, outline(data) + page_check.findings_lines(data["findings"]))
    checked = f"outline written; {len(data['findings'])} findings; {page_check.picture(args.page, 1600)}"
    print(f"wrote {args.page} ({len(page.encode())} bytes): SOP for {data['title']} version {data['version_number']}, "
          f"{len(data['steps'])} states, {len(data['handovers'])} handovers, {len(data['exceptions'])} exceptions, {len(data['terms'])} terms; {checked}")


if __name__ == "__main__":
    main()
