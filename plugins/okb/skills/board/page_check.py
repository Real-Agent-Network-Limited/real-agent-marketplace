"""The outline and picture of a drawn page, for the agent to check before giving it to a person.

The outline is the page's text in the order the page draws it, written from the same data block
the page draws, then the findings. Beside a page `<name>.html` it is `<name>.outline.md`. The
picture is `<name>.png`, the page's first screen, 1,600 pixels wide, taken with a Chromium
browser run headless where one is found: Google Chrome, Chromium or Microsoft Edge.
"""
import os
import shutil
import subprocess
import sys
import time
import re
from datetime import datetime, timedelta, timezone

# Where a Chromium browser is installed, in the order tried. A name without a separator is looked
# for on PATH, which is where Chromium and the Linux packages put theirs.
BROWSERS = {
    "darwin": [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    ],
    "linux": [
        "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge",
        "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
    ],
    "win32": [
        "chrome.exe", "msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ],
}
STATE_NAMES = {"pending": "Pending", "in_progress": "In progress", "paused": "Paused",
               "completed": "Completed", "cancelled": "Cancelled"}


def browser():
    """The Chromium browser this computer takes pictures with, or None."""
    for candidate in BROWSERS.get(sys.platform, BROWSERS["linux"]):
        if os.sep in candidate or (os.altsep and os.altsep in candidate):
            if os.path.exists(candidate):
                return candidate
        else:
            found = shutil.which(candidate)
            if found:
                return found
    return None


def companions(page_path):
    stem = page_path[:-5] if page_path.lower().endswith(".html") else page_path
    return stem + ".outline.md", stem + ".png"


def clear(path):
    """Removes a file an earlier draw or print left, so only the browser's new file counts."""
    if os.path.exists(path):
        os.remove(path)


def written(path, windows=sys.platform == "win32", appear=10, finish=30, steady=1.0):
    """True once the browser has written a file at path, and it has stopped growing. Elsewhere the file
    is whole when the browser returns. On Windows, Edge can hand the work to another of its processes
    and return at once, and that process writes the file a second or two later: the file has `appear`
    seconds to start, and `finish` seconds to hold one size for `steady` seconds."""
    if not windows:
        return os.path.exists(path) and os.path.getsize(path) > 0
    start, last, since = time.monotonic(), -1, None
    while True:
        now = time.monotonic()
        size = os.path.getsize(path) if os.path.exists(path) else 0
        if size != last:
            last, since = size, now
        elif size and now - since >= steady:
            return True
        if (not size and now - start >= appear) or now - start >= finish:
            return False
        time.sleep(0.25)


def picture(page_path, height, fragment=""):
    """Takes the page's picture, loaded with the fragment after its address. Returns a line for the tool's output."""
    _, png = companions(page_path)
    found = browser()
    if not found:
        return "no picture: no Chrome, Chromium or Edge on this computer"
    url = "file:///" + os.path.abspath(page_path).replace(os.sep, "/").lstrip("/") + fragment
    clear(png)
    try:
        # The two keychain switches keep the browser off the macOS keychain, whose dialog a home
        # folder without one raises, as the okb command's tests give it.
        subprocess.run([found, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                        "--no-default-browser-check", "--use-mock-keychain", "--password-store=basic",
                        f"--window-size=1600,{height}",
                        "--virtual-time-budget=8000", f"--screenshot={os.path.abspath(png)}", url],
                       capture_output=True, timeout=90, check=False)
    except (OSError, subprocess.TimeoutExpired) as err:
        return f"no picture: the browser did not finish ({err})"
    if not written(png):
        return "no picture: the browser wrote none"
    return "picture taken"


GMT = timezone.utc
BST = timezone(timedelta(hours=1), "BST")


def uk_time(value):
    """A stored time in UK time, as OKB shows it, with the standard library alone. The instant is
    unchanged; only its clock reads UK time, at +01:00 in summer and +00:00 in winter."""
    t = parse_iso(value).astimezone(GMT)

    def last_sunday(month):
        end = datetime(t.year, month, 31, 1, tzinfo=GMT)
        return end - timedelta(days=(end.weekday() + 1) % 7)

    # British Summer Time runs from 01:00 UTC on March's last Sunday to 01:00 UTC on October's.
    return t.astimezone(BST if last_sunday(3) <= t < last_sunday(10) else GMT)


def day(value):
    """The day of a stored time in UK time: `2 Jul`."""
    if not value:
        return ""
    t = uk_time(value)
    return f"{t.day} {t:%b}"


def read_at(value):
    """The time OKB was read, in UK time: `2 Jul 2026 00:30 UK time`."""
    t = uk_time(value)
    return f"{t.day} {t:%b %Y %H:%M} UK time"


def span(a):
    if a["start"] and a["finish"]:
        return f"{day(a['start'])} to {day(a['finish'])}"
    if a["finish"]:
        return f"by {day(a['finish'])}"
    if a["start"]:
        return f"from {day(a['start'])}"
    return "no dates"


def kind_of(a):
    return a["task_type"] if a["kind"] == "task" and a["task_type"] not in (None, "work") else a["kind"]


def named(a):
    return f"{a['index']} {a['title']}" if a["index"] else f"(no index) {a['title']}"


def badges(a):
    out = []
    if a["overdue_seconds"] > 0:
        out.append(f"Overdue {round(a['overdue_seconds'] / 3600)} h")
    if a["due_to_start"]:
        out.append("Due to start")
    if a["blockers"]:
        out.append(f"Blocked {len(a['blockers'])}")
    if not a["completion_requirements"].strip() and not a["deliverables_wanted"] and a["state"] in ("in_progress", "paused"):
        out.append("No deliverables")
    if a["deliverables_wanted"]:
        out.append(f"Deliverables {a['deliverables_done']} of {a['deliverables_wanted']} done")
    out.extend(f"After {d['title']}" for d in a["dependencies"] if d["waiting"])
    return out


def quoted(text, indent):
    """Text as the page shows it, its line breaks kept."""
    return [f"{indent}> {line}" if line.strip() else f"{indent}>" for line in text.strip().splitlines()]


def findings_lines(findings):
    if not findings:
        return ["## Findings", "", "Findings: none"]
    return ["## Findings", "", f"Findings: {len(findings)}", ""] + [f"- {f}" for f in findings]


def write(page_path, lines):
    outline, _ = companions(page_path)
    with open(outline, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines) + "\n")


def owned(a, indent=""):
    """An activity's owner, and who a task is assigned to, a line each; none when OKB names no one."""
    return ([f"{indent}Owner: {a['owner']}"] if a.get("owner") else []) + \
        ([f"{indent}Assigned to: {a['assignee']}"] if a["kind"] != "plan" and a.get("assignee") else [])


def opening_row(data):
    """The record id of the part the board opens on: the first part in progress, then the first one not
    completed or cancelled, then the first one. None for a plan with nothing under it."""
    by_id = {a["id"]: a for a in data["activities"]}
    heads = [row["activity"] for row in data["rows"]]
    for wanted in (lambda a: a["state"] == "in_progress", lambda a: a["state"] not in ("completed", "cancelled"), lambda a: True):
        for head in heads:
            if wanted(by_id[head]):
                return head
    return None


def parts(data):
    """The outline's line naming the parts in the board's menu and the one it opens on; none for a plan with fewer than two parts."""
    if len(data["rows"]) < 2:
        return []
    by_id = {a["id"]: a for a in data["activities"]}
    names = [named(by_id[row["activity"]]) for row in data["rows"]]
    return [f"Parts: {', '.join(names)}, All. Opens on {named(by_id[data['open_row']])}."]


def check_board(page_path, data):
    """The board's outline and picture. Returns a line for the tool's output."""
    by_id = {a["id"]: a for a in data["activities"]}
    plan = data["plan"]
    lines = [f"# Board: {named(plan)}", "",
             f"Read from OKB at {read_at(data['observed_at'])}, save number {data['cutoff']}.",
             f"Purpose: {data.get('purpose', '')}", *owned(plan), *parts(data), "",
             "Each row in order, then its cards in order. A card line is index and title, then its type, "
             "state, dates and badges. Under it are who it is assigned to, its deliverables and its blockers.", ""]
    for row in data["rows"]:
        head = by_id[row["activity"]]
        lines.append(f"## Row: {named(head)}")
        lines.append(f"{kind_of(head)} · {STATE_NAMES.get(head['state'], head['state'])} · {span(head)}"
                     + "".join(f" · {b}" for b in badges(head)))
        lines.extend(owned(head))
        lines.append("")
        for card in row["cards"]:
            a = by_id[card]
            lines.append(f"- {named(a)} · {kind_of(a)} · {STATE_NAMES.get(a['state'], a['state'])} · {span(a)}"
                         + "".join(f" · {b}" for b in badges(a)))
            lines.extend(owned(a, "  "))
            if a["completion_requirements"].strip():
                lines.append("  Deliverables:")
                lines.extend(quoted(a["completion_requirements"], "  "))
            for b in a["blockers"]:
                lines.append(f"  Blocker: {b['name'] or b['description']}")
        lines.append("")
    lines.extend(findings_lines(data["findings"]))
    write(page_path, lines)
    return f"outline written; {len(data['findings'])} findings; {picture(page_path, 1600)}"


BESIDE = "Beside the chart"


def check_model_board(page_path, data):
    """A model board's outline and picture: one line per row, then one line per card with its label,
    role and row. Returns a line for the tool's output."""
    cards = data["cards"]
    how = f"grouped by {data['by']}" if data["layout"] == "group" else f"by level of {data['by']}"
    lines = [f"# Board: {data['title']} (version {data['version_number']})", "",
             f"Drawn from OKB, save number {data['change_no']}, {how}.", ""]
    if data["description"]:
        lines.extend(quoted(data["description"], "") + [""])
    lines.extend(["## Rows", ""])
    # By level, the top row's nodes outside the relation are drawn above the chart, under Beside the chart.
    beside = data["rows"][0]["cards"] if data["layout"] == "level" else []
    if beside:
        lines.append(f"- {BESIDE} · {len(beside)} card{'s' if len(beside) != 1 else ''}")
    for at, row in enumerate(data["rows"], 1):
        count = len(row["places"]) + len(row["cards"]) - (len(beside) if at == 1 else 0) + len({u["id"] for u in row["under"]})
        heads = f" · columns: {', '.join(cards[p]['label'] for p in row['places'])}" if row["places"] else ""
        lines.append(f"- Row {at}: {row['name']} · {count} card{'s' if count != 1 else ''}{heads}")
    lines.extend(["", "## Cards", "",
                  "Each card in the order drawn: label, role, row, then what it is under, and whether it is a place or a gap.", ""])
    for row in data["rows"]:
        ordered = [(c, []) for c in row["cards"]] + [(p, []) for p in row["places"]] + [(u["id"], u.get("linked", u["under"])) for u in row["under"]]
        listed = set()
        for card_id, under in ordered:
            # A card under places that are not neighbours is drawn once under each run of them, and listed once.
            if card_id in listed:
                continue
            listed.add(card_id)
            c = cards[card_id]
            marks = (" · place" if c["place"] else "") + (" · gap" if c["gap"] else "")
            beneath = f" · under {', '.join(cards[u]['label'] for u in under)}" if under else ""
            name = BESIDE if card_id in beside else row["name"]
            lines.append(f"- {c['label']} · {c['role'] or '(no role)'} · row {name}{beneath}{marks}")
    lines.append("")
    lines.extend(findings_lines(data["findings"]))
    write(page_path, lines)
    return f"outline written; {len(data['findings'])} findings; {picture(page_path, 1100)}"


def check_graph(page_path, title, graph, findings):
    """The graph's outline and picture. Returns a line for the tool's output."""
    by_id = {n["id"]: n for n in graph["nodes"]}
    lines = [f"# Graph: {title}", "",
             "Each group in order, with its heading as drawn, then its nodes in order as reference, name and type. "
             "The links follow.", ""]
    for group in graph["groups"]:
        heading = f"{group['reference']} {group['name']}" if group.get("reference") else group["name"]
        lines.append(f"## Group: {heading}")
        lines.append("")
        for node in graph["nodes"]:
            if node["groupKey"] == group["key"]:
                lines.append(f"- {node['reference'] or '(no reference)'} {node['name']} · {node['typeLabel']}")
                if node.get("description"):
                    lines.extend(quoted(node["description"], "  "))
        lines.append("")
    lines.append("## Links")
    lines.append("")
    for edge in graph["edges"]:
        source, target = by_id[edge["from"]], by_id[edge["to"]]
        lines.append(f"- {source['reference'] or source['name']} {edge['label']} {target['reference'] or target['name']}")
    lines.append("")
    lines.extend(findings_lines(findings))
    write(page_path, lines)
    return f"outline written; {len(findings)} findings; {picture(page_path, 1100)}"


def state_machine_findings(graph_data, sm_data):
    """What the page draws wrongly or leaves loose: a state no transition joins and no route names,
    a state in no routine, a routine with no states, a link or route naming a node the page does not
    draw, and two nodes sharing a reference."""
    nodes = graph_data["nodes"]
    by_id = {n["id"]: n for n in nodes}
    groups = {g["key"] for g in graph_data["groups"]}
    found = []
    for e in graph_data["edges"]:
        for end in (e["from"], e["to"]):
            if end not in by_id:
                found.append(f"A {e['kind']} link names {end}, which the page does not draw.")
    joined = {end for e in graph_data["edges"] if e["kind"] != "dependency" for end in (e["from"], e["to"])}
    for r in sm_data.get("routes", []):
        for state in r["states"]:
            if state not in by_id:
                found.append(f"The route {r['name']} names {state}, which the page does not draw.")
        joined.update(r["states"])
    states = [n for n in nodes if n["kind"] == "node" and n["role"] != "group"]
    for n in states:
        if n["id"] not in joined:
            found.append(f"{n['reference'] or '(no reference)'} {n['name']} has no transition and is in no route.")
        if groups and n["groupKey"] not in groups:
            found.append(f"{n['reference'] or '(no reference)'} {n['name']} is in no routine.")
    for g in graph_data["groups"]:
        if not any(n["groupKey"] == g["key"] for n in states):
            found.append(f"The routine {g['name']} has no states.")
    seen = {}
    for n in nodes:
        reference = n.get("reference")
        if not reference:
            continue
        if reference in seen:
            found.append(f"{seen[reference]} and {n['name']} share the reference {reference}.")
        else:
            seen[reference] = n["name"]
    return found


def check_state_machine(page_path, title, line, graph_data, sm_data):
    """The state machine page's outline and picture. Returns a line for the tool's output."""
    nodes = graph_data["nodes"]
    by_id = {n["id"]: n for n in nodes}
    detail = sm_data.get("byId", {})

    def name_of(node_id):
        n = by_id.get(node_id)
        if not n:
            return f"(not drawn) {node_id}"
        return f"{n['reference']} {n['name']}" if n.get("reference") else n["name"]

    def node_lines(n, indent):
        # A gap or dead end carries its type as a tag too; the line names it once.
        tags = "".join(f" · {t}" for t in n.get("tags", []) if t != n["typeLabel"].lower().replace(" ", "-"))
        out = [f"{indent}- {n['reference'] or '(no reference)'} {n['name']} · {n['typeLabel']}{tags}"]
        if n.get("description"):
            out.extend(quoted(n["description"], indent + "  "))
        for category, heading in (("actors", "Actors"), ("applications", "Applications"), ("data", "Data")):
            linked = detail.get(n["id"], {}).get("links", {}).get(category, [])
            if linked:
                out.append(f"{indent}  {heading}: {', '.join(link['name'] for link in linked)}")
        return out

    lines = [f"# State machine: {title}", "", line, "",
             "Each routine in order, with its states in order as reference, name, type and tags, then the "
             "drawn objects. The transitions, dependencies and routes follow.", ""]
    states = [n for n in nodes if n["kind"] == "node" and n["role"] != "group"]
    for g in graph_data["groups"]:
        heading = f"{g['reference']} {g['name']}" if g.get("reference") else g["name"]
        lines.append(f"## Routine: {heading}")
        lines.append("")
        for n in states:
            if n["groupKey"] == g["key"]:
                lines.extend(node_lines(n, ""))
        if not any(n["groupKey"] == g["key"] for n in states):
            lines.append("None")
        lines.append("")
    loose = [n for n in states if n["groupKey"] not in {g["key"] for g in graph_data["groups"]}]
    if loose:
        lines.extend(["## States in no routine", ""])
        for n in loose:
            lines.extend(node_lines(n, ""))
        lines.append("")
    lines.extend(["## Objects", ""])
    objects = [n for n in nodes if n["kind"] == "object"]
    for n in objects:
        lines.extend(node_lines(n, ""))
    lines.extend([] if objects else ["None"])
    lines.append("")
    for kind, heading in (("transition", "Transitions"), ("dependency", "Dependencies")):
        lines.extend([f"## {heading}", ""])
        drawn = [e for e in graph_data["edges"] if (e["kind"] == "dependency") == (kind == "dependency")]
        for e in drawn:
            label = f" ({e['label']})" if e.get("label") else ""
            lines.append(f"- {name_of(e['from'])} → {name_of(e['to'])}{label}")
        lines.extend([] if drawn else ["None"])
        lines.append("")
    lines.extend(["## Routes", ""])
    if not sm_data.get("routes"):
        lines.append("None")
    for r in sm_data.get("routes", []):
        lines.append(f"- {r['name']}: {', '.join(name_of(s) for s in r['states'])}")
        if r.get("outcome"):
            lines.append(f"  Outcome: {r['outcome']}")
    lines.append("")
    findings = state_machine_findings(graph_data, sm_data)
    lines.extend(findings_lines(findings))
    write(page_path, lines)
    return f"outline written; {len(findings)} findings; {picture(page_path, 1100)}"
def parse_iso(value):
    """An ISO time as Python 3.9's fromisoformat takes it: a Z as +00:00, and a fraction of seconds padded or cut to six
    digits, since the database writes as few as it needs and Python before 3.11 reads only three or six."""
    value = value.replace("Z", "+00:00")
    value = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], value, count=1)
    return datetime.fromisoformat(value)
