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

WHAT IS FILLED IN TODAY. The functions under "Reads on the API as it stands" work on the current product, so the assertions
that use them really fail, or hold, on it. They may be replaced when the design moves those fields. The rest raise NotWired.
"""


class NotWired(Exception):
    """The product as designed has not been connected here yet."""


# ---- Reads on the API as it stands; may be replaced once the design names its fields ----

OPEN_STATES_END = ("closed",)
CASE_DONE = ("escalated", "blocked", "resolved", "closed", "failed")


def open_incidents(rig, namespace, receiver):
    """The ids of the incidents open for this receiver. One outage should give a list of one."""
    code, r = rig.get("/incidents?limit=500")
    if code == 404:
        raise NotWired("open_incidents")
    items = r.get("items", []) if isinstance(r, dict) else []
    return [str(i.get("incidentId") or i.get("id")) for i in items if i.get("receiver") == receiver and i.get("state") not in OPEN_STATES_END]


def incident_is_closed(rig, namespace, receiver, incident):
    """True when this incident, one open_incidents gave, reads as closed."""
    _, r = rig.get("/incidents/" + str(incident))
    return isinstance(r, dict) and r.get("state") in OPEN_STATES_END


def _strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from _strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from _strings(v)


def _cases(rig, namespace, receiver):
    _, r = rig.get("/cases?limit=500")
    items = r.get("items", []) if isinstance(r, dict) else []
    return [c for c in items if c.get("sourceNamespace") == namespace and c.get("receiver") == receiver]


def person_text(rig, namespace, receiver, control=None):
    """All the words a person can read on the page about this message, or with control None about this receiver's incident.
    Only what the page shows: a value kept in a store and not shown doesn't belong here."""
    parts = []
    for incident in open_incidents(rig, namespace, receiver) if control is None else []:
        parts.extend(_strings(rig.get("/incidents/" + incident)[1]))
    if control is not None:
        for c in _cases(rig, namespace, receiver):
            cid = c.get("caseId")
            if control != rig.control_of_case(namespace, cid):
                continue
            parts.extend(_strings(rig.get("/cases/" + cid)[1]))
            parts.extend(_strings(rig.get("/cases/" + cid + "/plan")[1]))
    return "\n".join(parts)


def settled(rig, namespace, receiver, control):
    """True once this message's case has stopped at a state that settles or escalates it, with nobody needing to do more to get
    an answer from Shutter. False while it is moving, or when it has no case."""
    for c in _cases(rig, namespace, receiver):
        if control == rig.control_of_case(namespace, c.get("caseId")):
            return rig.get("/cases/" + c.get("caseId"))[1].get("state") in CASE_DONE
    return False


# ---- To fill in once the design names them ----

def declare_receiver(rig, namespace, receiver, facts):
    """Tell the site profile, in the design's own form, what a site would write for this receiver. facts holds: product,
    category ("orders_results"), who_to_call, what_to_do, duplicates ("refuses", "files_twice" or "unknown"), duplicate_words.
    Use rig.site_setting. Called once per receiver, before any message."""
    raise NotWired("declare_receiver")


def resend_set(rig, namespace, receiver):
    """The control ids, in the order they would go, of what the product offers to send again for this receiver right now."""
    raise NotWired("resend_set")


def approve_resend(rig, namespace, receiver):
    """A person's one approval of what resend_set shows. One call of rig.person_decides, however many messages go."""
    raise NotWired("approve_resend")


def offers_handled_by_hand(rig, namespace, receiver, control):
    """True when the page offers a person the choice "already handled by hand" for this message."""
    raise NotWired("offers_handled_by_hand")


def choose_handled_by_hand(rig, namespace, receiver, control):
    """A person takes that choice. One call of rig.person_decides."""
    raise NotWired("choose_handled_by_hand")


def closure(rig, namespace, receiver, control):
    """How this message's case or item stands: None while open, or one of "already_delivered", "handled_by_hand", "other"."""
    raise NotWired("closure")


def shared_character_count(rig, namespace, receiver, control):
    """The number the page gives of recent failures to this receiver that share this message's special character."""
    raise NotWired("shared_character_count")


def resend_failed(rig, namespace, receiver, control):
    """True when the page shows that this message's resend did not succeed, for a message that already had a case."""
    raise NotWired("resend_failed")


def says_engine_holds(rig, namespace, receiver, control):
    """True when what the page shows for this message's case says plainly that the engine is still trying it, and true when
    this message has no case, since nothing new was opened for it."""
    raise NotWired("says_engine_holds")


def named_obx(rig, namespace, receiver, control):
    """The OBX set ids (integers) the finding names as the fault, as a list."""
    raise NotWired("named_obx")
