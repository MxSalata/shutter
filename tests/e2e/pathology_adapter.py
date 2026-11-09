"""The one file of the Pathology oracle that may change once the design names its fields.

THE RULE. pathology_check.py holds every assertion and is locked by assertions.sha256. This file only translates: it tells the
check how to read a thing or how to press a button in the product as designed. It decides nothing, so it may not filter, retry,
soften or wait for a result in a way that changes what the check sees, and it may not change an assertion. Whoever fills it in
must not be the one who built the feature. If a function here can't be written honestly because the product doesn't do the
thing, leave it raising NotWired: the check then reports NOT WIRED, which is never a pass.

WHAT IT MAY USE. Only the rig object it is given: rig.get(path) to read the REST API as the approver,
rig.control_of_case(namespace, case_id) for the control id behind a case, and rig.person_decides(method, path, body) for one
decision a person takes on the page. rig.site_setting(method, path, body) is for declare_receiver alone. The check refuses to run an adapter that imports anything but json, re and urllib.parse, or that names exec, eval, open,
globals, setattr, getattr, __import__ or the check itself (pathology_check.py, adapter_guard).

WHAT IS FILLED IN TODAY. An incident is a receiver outage on /outages, as docs/CONTRACTS.md section 17 sets out. A build with no
such route reads NOT WIRED, not "nothing open". The functions at the end read the fields docs/design-1.4.0.md names: an outage's
resends, a Row's acts, and the act handled_by_hand.
"""
import re


class NotWired(Exception):
    """The product as designed has not been connected here yet."""


# ---- Outages ----

CLOSED = "closed"
NO_SET_GATE = "no set gate in this build"


def _outages(rig):
    """Every outage row, read from the list route, which changes nothing. state=all because state=open could mean the state
    named open alone, and an outage draining or offered is still open to a person."""
    code, r = rig.get("/outages?state=all")
    if code == 404:
        raise NotWired("outages: this build has no /outages route")
    items = r.get("items") if isinstance(r, dict) else None
    if not isinstance(items, list):
        raise RuntimeError(f"GET /outages gave no list of items: {str(r)[:300]}")
    return items


def open_incidents(rig, namespace, receiver):
    """The ids of the incidents open for this receiver. One outage should give a list of one."""
    return [str(o.get("id")) for o in _outages(rig) if o.get("receiver") == receiver and o.get("state") != CLOSED]


def incident_is_closed(rig, namespace, receiver, incident):
    """True when this incident, one open_incidents gave, reads as closed. From the list route, because GET /outages/:id asks the
    reader to look again, and this must see what the product did by itself."""
    return any(str(o.get("id")) == str(incident) and o.get("state") == CLOSED for o in _outages(rig))


def _outage(rig, incident):
    """One outage in full. This is the read the design has compute the set."""
    code, r = rig.get("/outages/" + str(incident))
    if code == 404:
        raise NotWired("outage: GET /outages/:id answers 404")
    return r


def _strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from _strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from _strings(v)


def _finding_strings(x):
    """The strings held under a key naming a finding, wherever it sits. The snapshot also holds the message's own fields, so
    reading all of it would find a patient's character or a test code that no finding named."""
    if isinstance(x, dict):
        for k, v in x.items():
            if "finding" in str(k).lower():
                yield from _strings(v)
            else:
                yield from _finding_strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from _finding_strings(v)


# ---- Cases ----

CASE_DONE = ("escalated", "blocked", "resolved", "closed", "failed")


def _cases(rig, namespace, receiver):
    _, r = rig.get("/cases?limit=500")
    items = r.get("items", []) if isinstance(r, dict) else []
    return [c for c in items if c.get("sourceNamespace") == namespace and c.get("receiver") == receiver]


def _case_ids_of(rig, namespace, receiver, control):
    return [c.get("caseId") for c in _cases(rig, namespace, receiver) if control == rig.control_of_case(namespace, c.get("caseId"))]


def person_text(rig, namespace, receiver, control=None):
    """All the words a person can read on the page about this message, or with control None about this receiver's incident.
    Only what the page shows: a value kept in a store and not shown doesn't belong here."""
    parts = []
    for incident in open_incidents(rig, namespace, receiver) if control is None else []:
        o = _outage(rig, incident)
        # The card's own words, its lists and alerts, and why no list is shown: not the row's raw runbook and call fields.
        parts.extend(_strings([o.get("words"), o.get("lists"), o.get("alerts"), o.get("openCases"), (o.get("set") or {}).get("reason")]))
    if control is not None:
        for cid in _case_ids_of(rig, namespace, receiver, control):
            parts.extend(_strings(rig.get("/cases/" + cid)[1]))
            parts.extend(_strings(rig.get("/cases/" + cid + "/plan")[1]))
            code, snapshot = rig.get("/cases/" + cid + "/snapshot")
            if code == 200:
                parts.extend(_finding_strings(snapshot))
            code, drafts = rig.get("/cases/" + cid + "/escalations")
            if code == 200:
                parts.extend(_strings(drafts))
    return "\n".join(parts)


def settled(rig, namespace, receiver, control):
    """True once this message's case has stopped at a state that settles or escalates it, with nobody needing to do more to get
    an answer from Shutter. False while it is moving, or when it has no case."""
    for c in _cases(rig, namespace, receiver):
        if control == rig.control_of_case(namespace, c.get("caseId")):
            return rig.get("/cases/" + c.get("caseId"))[1].get("state") in CASE_DONE
    return False


# ---- The site's declaration ----

def declare_receiver(rig, namespace, receiver, facts):
    """Tell the site profile, in the design's own form, what a site would write for this receiver. facts holds: product,
    category ("orders_results"), who_to_call, what_to_do, duplicates ("refuses", "files_twice" or "unknown"), duplicate_words.
    Use rig.site_setting. Called once per receiver, before any message.
    A profile the product refuses is raised, not read as undeclared: the two have stopped agreeing, and that must be seen."""
    _outages(rig)
    _, current = rig.get("/site-profile")
    profile = current["profile"]
    duplicates = {"behaviour": facts["duplicates"]}
    if facts.get("duplicate_words"):
        duplicates["phrase"] = facts["duplicate_words"]
    entry = {
        "name": receiver,
        "system": facts["product"],
        "category": facts["category"],
        "tier": 3,  # The validator requires a tier; nothing reads it for this category.
        "watch": {"namespace": namespace, "item": receiver},
        "runbook": facts["what_to_do"],
        "call": facts["who_to_call"],
        "duplicates": duplicates,
    }
    if facts["category"] == "orders_results":
        # What lets a build with the send offer one here. The set still decides what goes, and a build without it reads this nowhere.
        entry["engine_resend"] = True
        # And what a site that has Shutter resend here writes beside it: the send holds to shadow mode, as every recovery call
        # does (CONTRACTS 18, v1.54), and the rig installs as a site does, which starts in shadow mode.
        profile["recovery"] = {"mode": "enabled"}
    profile["receivers"] = [r for r in profile.get("receivers", []) if r.get("name") != receiver] + [entry]
    profile["expectedVersion"] = str(current["version"])
    code, answer = rig.site_setting("PUT", "/site-profile", profile)
    if not 200 <= code < 300:
        raise RuntimeError(f"the site profile refused {receiver}: {code} {str(answer)[:400]}")


# ---- What is offered ----

def resend_set(rig, namespace, receiver):
    """The control ids, in the order they would go, of what the product offers to send again for this receiver right now."""
    out = []
    for incident in open_incidents(rig, namespace, receiver):
        o = _outage(rig, incident)
        given = o.get("set") or {}
        if given.get("status") == "not_computed" and given.get("reason") == NO_SET_GATE:
            raise NotWired("resend_set: " + NO_SET_GATE)
        lists = o.get("lists")
        if not isinstance(lists, dict) or not isinstance(lists.get("offered"), list):
            raise RuntimeError(f"outage {incident} gave no lists.offered: {str(o)[:300]}")
        out.extend(row.get("controlId") for row in lists["offered"])
    return out


def approve_resend(rig, namespace, receiver):
    """A person's one approval of what resend_set shows. One call of rig.person_decides, however many messages go.
    The rig can't send an Idempotency-Key header; on the existing mechanism it is optional."""
    incidents = open_incidents(rig, namespace, receiver)
    if not incidents:
        raise NotWired("approve_resend: no outage is open to approve on")
    o = _outage(rig, incidents[0])
    if o.get("approvable") is not True:
        raise NotWired("approve_resend: the outage reads approvable false")
    body = {"digest": (o.get("set") or {}).get("digest"), "version": o.get("version"), "note": "checked with the duty desk"}
    code, _ = rig.person_decides("POST", "/outages/" + incidents[0] + "/approvals", body)
    if code == 404:
        raise NotWired("approve_resend: POST /outages/:id/approvals answers 404")


# ---- Findings: the words the design gives them, on the case ----

def shared_character_count(rig, namespace, receiver, control):
    """The number the page gives of recent failures to this receiver that share this message's special character: k in the
    finding's "k of the last n failures". None when the page gives no such number."""
    m = re.search(r"(\d+) of the last \d+ failures", person_text(rig, namespace, receiver, control))
    return int(m.group(1)) if m else None


def says_engine_holds(rig, namespace, receiver, control):
    """True when what the page shows for this message's case says plainly that the engine is still trying it, and true when
    this message has no case, since nothing new was opened for it."""
    if not _case_ids_of(rig, namespace, receiver, control):
        return True
    return bool(re.search(r"the engine holds it|the engine is still trying|it is still trying", person_text(rig, namespace, receiver, control), re.I))


def named_obx(rig, namespace, receiver, control):
    """The OBX set ids (integers) the finding names as the fault, as a list: s in its "set id OBX-1 = s". The same finding on
    two parts of the page is one naming."""
    out = []
    for s in re.findall(r"set id OBX-1 = (\d+)", person_text(rig, namespace, receiver, control)):
        if int(s) not in out:
            out.append(int(s))
    return out


# ---- Shutter's resends and hand closures (docs/design-1.4.0.md, parts 2 to 4; CONTRACTS 17.3 and 17.8) ----

def _resends(rig, receiver, control):
    """The ledger rows the outage list gives for this control id at this receiver, every outage's, in the route's order."""
    out = []
    for o in _outages(rig):
        if o.get("receiver") != receiver:
            continue
        resends = o.get("resends")
        if not isinstance(resends, list):
            raise NotWired("resends: GET /outages gives no resends on an outage")
        out.extend(r for r in resends if isinstance(r, dict) and r.get("controlId") == control)
    return out


def _offered_row(rig, namespace, receiver, control):
    """The open outage's lists.offered row for this control id, with the outage, or (None, None)."""
    for incident in open_incidents(rig, namespace, receiver):
        o = _outage(rig, incident)
        for row in ((o.get("lists") or {}).get("offered") or []):
            if row.get("controlId") == control:
                return o, row
    return None, None


def offers_handled_by_hand(rig, namespace, receiver, control):
    """True when the page offers a person the choice "already handled by hand" for this message: the open outage's
    lists.offered row for the control id lists handled_by_hand in its acts."""
    _, row = _offered_row(rig, namespace, receiver, control)
    return row is not None and "handled_by_hand" in (row.get("acts") or [])


def choose_handled_by_hand(rig, namespace, receiver, control):
    """A person takes that choice. One call of rig.person_decides: the act with that row's headerId, the outage's version
    and a note."""
    o, row = _offered_row(rig, namespace, receiver, control)
    if row is None:
        raise NotWired("choose_handled_by_hand: no open outage offers this message")
    body = {"act": "handled_by_hand", "headerId": row.get("headerId"), "note": "entered at the receiver by hand, checked with the duty desk", "version": o.get("version")}
    rig.person_decides("POST", "/outages/" + str(o.get("id")) + "/acts", body)


def closure(rig, namespace, receiver, control):
    """How this message's case or item stands: None while open, or one of "already_delivered", "handled_by_hand", "other".
    From the outage's resends: the closure as written for already_delivered and handled_by_hand, sent, failed or unknown as
    "other"; no row for the control id, or a null closure, None."""
    rows = _resends(rig, receiver, control)
    if not rows:
        return None
    got = rows[-1].get("closure")
    if got is None:
        return None
    return got if got in ("already_delivered", "handled_by_hand") else "other"


def resend_failed(rig, namespace, receiver, control):
    """True when the page shows that this message's resend did not succeed, for a message that already had a case: a
    resends row for the control id reads state failed."""
    return any(r.get("state") == "failed" for r in _resends(rig, receiver, control))
