"""The one model of an OKB plan that both its board and its graph are drawn from.

The model is built from the progress files `okb_get_progress` wrote: the plan, and every activity
under it in index order. An activity's index, such as `2.2` or `2.2a`, is its own field, kept apart
from its title. Indexes are compared in runs: digits as numbers, anything else without case, and a
shorter index first where one runs out. An activity with no index comes after every indexed one
beside it, by start date then title, and is a finding.

Each activity carries its parent, its dependencies, its blockers and its evidence. A blocker listed
on a task is joined to the blocker record whose record id is its blocker id. The findings are what
the person would want put right before the page is given to them.
"""
import json
import re
from datetime import datetime

import page_check

ACTIVITY_LIMIT = 500
STATES = ("pending", "in_progress", "paused", "completed", "cancelled")
# The states each state may move to, as OKB's work records data model sets them.
NEXT_STATES = {
    "pending": ["in_progress", "cancelled"],
    "in_progress": ["paused", "completed", "cancelled"],
    "paused": ["in_progress", "cancelled"],
    "completed": ["in_progress"],
    "cancelled": [],
}
# Versions saved before the upgrade 0009 of the schema OKB was forked from carry the old names of three states.
OLD_STATES = {"planned": "pending", "active": "in_progress", "on_hold": "paused"}
TASK_TYPES = ("work", "deliverable", "blocker")
RUN = re.compile(r"\d+|\D+")


def activity_state(state):
    """A state by its current name."""
    return OLD_STATES.get(state, state)


def item_state(item):
    """An item's state: OKB's own reading of it where the answer gives one, else its payload's."""
    return activity_state(item.get("state") or item["payload"].get("state"))


def when(value):
    return parse_iso(value) if value else None

def parse_iso(value):
    """An ISO time as Python 3.9's fromisoformat takes it: a Z as +00:00, and a fraction of seconds padded or cut to six
    digits, since the database writes as few as it needs and Python before 3.11 reads only three or six."""
    value = value.replace("Z", "+00:00")
    value = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], value, count=1)
    return datetime.fromisoformat(value)



def index_of(item):
    return " ".join(str(item["payload"].get("index") or "").split())


def index_key(index):
    """`2.10` after `2.9`, and `2.2` before `2.2a`."""
    return tuple((0, int(run), "") if run.isdigit() else (1, 0, run.casefold()) for run in RUN.findall(index))


def effective(payload, end):
    """The forecast date, or the baseline date where the forecast is null."""
    return payload.get(f"forecast_{end}_at") or payload.get(f"baseline_{end}_at")


def order_key(item):
    index = index_of(item)
    if index:
        return (0, index_key(index), "", item["title"].casefold())
    return (1, (), effective(item["payload"], "start") or "9999", item["title"].casefold())


def read_pages(paths):
    """Every page's items, joined, with the save number and observation time they share."""
    cutoff = observed_at = None
    items = {}
    for path in paths:
        page = json.load(open(path, encoding="utf-8"))
        if not isinstance(page, dict) or not isinstance(page.get("items"), list) or "cutoff" not in page:
            raise SystemExit(f"{path} does not hold a progress answer; no page was drawn")
        if cutoff is None:
            cutoff, observed_at = page["cutoff"], page.get("observed_at")
        elif (page["cutoff"], page.get("observed_at")) != (cutoff, observed_at):
            raise SystemExit("the progress files come from different reads: each page must carry the first page's "
                             "save number and observation time; no page was drawn")
        for item in page["items"]:
            if "parent" not in item:
                raise SystemExit("the progress answer gives no parent for its activities; the database needs the upgrade "
                                 "0005-progress-parent; no page was drawn")
            items[item["record_id"]] = item
    return cutoff, observed_at, items


def choose_plan(items, plan_id):
    if plan_id:
        item = items.get(plan_id)
        if item is None or item["payload"].get("activity_kind") != "plan":
            raise SystemExit(f"{plan_id} is not a plan in the progress files; no page was drawn")
        return item
    tops = [i for i in items.values() if i["payload"].get("activity_kind") == "plan" and not i["parent"]]
    if len(tops) == 1:
        return tops[0]
    if not tops:
        raise SystemExit("the progress files hold no plan without a parent; no page was drawn")
    listed = "; ".join(f"{i['title']} ({i['record_id']})" for i in sorted(tops, key=lambda i: i["title"].casefold()))
    raise SystemExit(f"the progress files hold {len(tops)} plans without a parent; name one with plan_id: {listed}; "
                     "no page was drawn")


def named(item):
    """An activity as a person finds it: its index, then its title."""
    index = index_of(item)
    return f"{index} {item['title']}" if index else item["title"]


def activity(item, items, observed):
    p = item["payload"]
    start, finish = effective(p, "start"), effective(p, "finish")
    state = item_state(item)
    due_to_start = state == "pending" and start is not None and observed is not None and when(start) < observed
    waiting = state in ("in_progress", "paused") or due_to_start
    parent = items.get((item["parent"] or {}).get("record_id"))
    kind = p.get("activity_kind")
    task_type = p.get("task_type") if p.get("task_type") in TASK_TYPES else ("work" if kind == "task" else None)

    def blocker(entry):
        found = items.get(entry.get("blocker_id"))
        return {"description": entry.get("description") or "A blocker",
                "record_id": found["record_id"] if found else None,
                "name": named(found) if found else None,
                "state": item_state(found) if found else None}

    def dependency(d):
        found = items.get(d["record_id"])
        return {"record_id": d["record_id"], "title": named(found) if found else "An activity outside this board",
                "state": activity_state(d.get("state")), "unfinished": bool(d.get("unfinished")),
                "waiting": bool(d.get("unfinished")) and waiting}

    def type_of(record_id):
        found = items.get(record_id)
        return found["payload"].get("task_type") if found else None

    # Each activity it waits on is shown once: a blocker under its blockers, a deliverable under its
    # deliverables, and any other activity under what it depends on.
    waits = item.get("dependencies") or []
    listed = {b.get("blocker_id") for b in p.get("blockers") or []}
    deliverables = [dependency(d) for d in waits if type_of(d["record_id"]) == "deliverable"]
    # The deliverables still wanted, which the board counts: those in any state but cancelled.
    wanted = [d for d in deliverables if d["state"] != "cancelled"]

    # Each activity's owner is the person accountable for it. From the upgrade 0040 of the schema OKB was forked from,
    # whose progress names a plan's creator in creator_actor_id, OKB writes the owner's name into
    # owner_label, and an activity with no owner_actor_id has no owner until one is set. Before it, a
    # plan's owner is the person who created it and a task's is its assignee, from upgrade
    # 0016-task-assignee, and before that the owner text saved.
    if "creator_actor_id" in item:
        owner = p.get("owner_label") if p.get("owner_actor_id") else None
    elif "assignee_name" in item:
        owner = ((item.get("creator_name") or item.get("owner_name")) if kind == "plan" else item.get("assignee_name")) or p.get("owner_label")
    else:
        owner = p.get("owner_label")

    return {
        "id": item["record_id"], "index": index_of(item), "title": item["title"], "kind": kind, "task_type": task_type,
        "state": state, "description": p.get("description") or "", "owner": owner, "assignee": item.get("assignee_name"),
        "baseline_start_at": p.get("baseline_start_at"), "baseline_finish_at": p.get("baseline_finish_at"),
        "forecast_start_at": p.get("forecast_start_at"), "forecast_finish_at": p.get("forecast_finish_at"),
        "start": start, "finish": finish,
        "started_at": item.get("started_at"), "actual_finish": item.get("actual_finish"),
        "overdue_seconds": item.get("overdue_seconds") or 0,
        "due_to_start": due_to_start,
        "blockers": [blocker(b) for b in p.get("blockers") or []],
        "completion_requirements": p.get("completion_requirements") or "", "completion_note": p.get("completion_note") or "",
        "external_references": [{"label": r.get("label") or "", "reference": r.get("reference") or ""}
                                for r in p.get("external_references") or []],
        "baseline_finish_variance_seconds": item.get("baseline_finish_variance_seconds"),
        "forecast_finish_variance_seconds": item.get("forecast_finish_variance_seconds"),
        "prior_state": activity_state(item.get("prior_state")),
        # Null when the database lacks the upgrade 0007 of the schema OKB was forked from, whose answer gives no evidence.
        "evidence": [{"title": e.get("title") or "", "standing": e.get("standing"), "deleted": bool(e.get("deleted"))}
                     for e in item["evidence"]] if isinstance(item.get("evidence"), list) else None,
        "dependencies": [dependency(d) for d in waits
                         if type_of(d["record_id"]) not in ("deliverable", "blocker") and d["record_id"] not in listed],
        "deliverables": deliverables,
        "deliverables_wanted": len(wanted),
        "deliverables_done": sum(1 for d in wanted if d["state"] == "completed"),
        "waits_on": [d["record_id"] for d in waits],
        "parent_id": parent["record_id"] if parent else None,
        "parent_title": named(parent) if parent else None,
        "latest": {"version_number": item.get("version_number"), "change_no": item.get("change_no"),
                   "recorded_at": item.get("recorded_at"), "reason": item.get("change_reason") or ""},
        "next_states": NEXT_STATES.get(state, []),
    }


def findings_of(plan, activities):
    """What the person would want put right, one line each, in the order the activities are drawn."""
    found = []
    everything = [plan] + activities
    by_id = {a["id"]: a for a in everything}
    seen = {}
    for a in everything:
        name = f"{a['index']} {a['title']}" if a["index"] else a["title"]
        if not a["index"]:
            found.append(f"{a['title']} has no index.")
        elif a["index"] in seen:
            found.append(f"{seen[a['index']]} and {a['title']} share the index {a['index']}.")
        else:
            seen[a["index"]] = a["title"]
        if not a["description"].strip():
            found.append(f"{name} has no description.")
        for b in a["blockers"]:
            if b["state"] in ("completed", "cancelled"):
                found.append(f"{name} still lists the blocker {b['name']}, which is {b['state']}.")
    listed = {b["record_id"] for a in everything for b in a["blockers"] if b["record_id"]}
    depended = {d for a in everything for d in a["waits_on"]}
    for a in activities:
        name = f"{a['index']} {a['title']}" if a["index"] else a["title"]
        if a["task_type"] == "blocker" and a["id"] not in listed and a["state"] not in ("completed", "cancelled"):
            found.append(f"The blocker {name} is not listed on any task's blockers.")
        if a["task_type"] in ("deliverable", "blocker") and a["id"] not in depended:
            found.append(f"No task waits on the {a['task_type']} {name}.")
    found += finish_order(everything)
    return found


def finish_order(activities):
    """Each activity that finishes before a child, or a deliverable it waits on, as OKB
    refuses, one line each. Each activity carries id, index, title, kind, task_type, state, finish,
    parent_id and waits_on. A cancelled activity, and one with no finish, is left out. The words and
    times are those of OKB's refusal."""
    found = []
    by_id = {a["id"]: a for a in activities}
    children = {}
    for c in activities:
        children.setdefault(c["parent_id"], []).append(c)
    for a in activities:
        if a["state"] == "cancelled" or not a["finish"]:
            continue
        later = {c["id"]: c for c in children.get(a["id"], [])}
        for d in a["waits_on"]:
            if d in by_id and by_id[d]["task_type"] == "deliverable":
                later.setdefault(d, by_id[d])
        for c in later.values():
            if c["state"] != "cancelled" and c["finish"] and when(c["finish"]) > when(a["finish"]):
                # A plan under a plan with no parent is a sprint; one deeper is a plan.
                word = (c["task_type"] if c["task_type"] in ("deliverable", "blocker") else
                        ("sprint" if not a["parent_id"] else "plan") if c["kind"] == "plan" else "task")
                name = f"{a['index']} {a['title']}" if a["index"] else a["title"]
                early, late = page_check.uk_time(a["finish"]), page_check.uk_time(c["finish"])
                found.append(f"{name} finishes {shown(early, late)}, before its {word} {c['index'] or c['title']}, "
                             f"which finishes {shown(late, early)}.")
    return found


def shown(t, other):
    """`19 Oct 17:00`, with the year when the other time falls in another year: `30 Dec 2026 17:00`."""
    return f"{t.day} {t:%b} {t.year} {t:%H:%M}" if t.year != other.year else f"{t.day} {t:%b %H:%M}"


def build(cutoff, observed_at, items, plan):
    """The plan model: the plan, every activity under it in drawn order, its parts and its findings."""
    observed = when(observed_at)
    children = {}
    for item in items.values():
        parent = (item["parent"] or {}).get("record_id")
        if parent:
            children.setdefault(parent, []).append(item)

    def order(group):
        return sorted(group, key=order_key)

    def under(record_id, seen):
        found = []
        for child in order(children.get(record_id, [])):
            if child["record_id"] in seen:
                continue
            seen.add(child["record_id"])
            found.append(child)
            found.extend(under(child["record_id"], seen))
        return found

    everything = under(plan["record_id"], {plan["record_id"]})
    if len(everything) > ACTIVITY_LIMIT:
        raise SystemExit(f"the plan has {len(everything)} activities under it, over the {ACTIVITY_LIMIT}-activity limit; "
                         "no page was drawn")
    parts = []
    for child in order(children.get(plan["record_id"], [])):
        if child["payload"].get("activity_kind") == "plan":
            members = [i["record_id"] for i in under(child["record_id"], {plan["record_id"], child["record_id"]})]
        else:
            members = [child["record_id"]]
        parts.append({"activity": child["record_id"], "cards": members})
    counts = {s: 0 for s in STATES}
    for item in everything:
        counts[item_state(item)] = counts.get(item_state(item), 0) + 1
    model_plan = activity(plan, items, observed)
    activities = [activity(i, items, observed) for i in everything]
    return {
        "cutoff": cutoff, "observed_at": observed_at, "counts": counts,
        "plan": model_plan, "activities": activities, "rows": parts,
        "findings": findings_of(model_plan, activities),
    }


def load(paths, plan_id):
    """The plan model from the progress files, for the plan named, or the only plan with no parent."""
    cutoff, observed_at, items = read_pages(paths)
    plan = choose_plan(items, (plan_id or "").strip())
    return build(cutoff, observed_at, items, plan)
