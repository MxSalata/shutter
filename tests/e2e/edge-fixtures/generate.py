#!/usr/bin/env python3
"""Writes the HL7 and scenarios.json for tests/e2e/edge_rows_check.py: scenarios that prove rows of docs/edge-cases.md.

    python3 tests/e2e/edge-fixtures/generate.py

They sit apart from fixtures/, so the demo's own list of scenarios and its recordings stay as they are. Each is a variant of
a listed scenario, built with fixtures/generate.py's own message, and played in rules or site policy, with no agents.
"""
import importlib.util
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fixture_generator", os.path.join(HERE, "..", "..", "..", "fixtures", "generate.py"))
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)

# scenario: (the listed scenario it varies, the patient)
VARIANTS = {
    "S6b": ("S6", ("MRN1061", "ENC-1061", "SYNTH^PIA", "19700102", "F")),
    "S22b": ("S22", ("MRN1221", "ENC-1221", "SYNTH^QUIN", "19710203", "M")),
    "S22c": ("S22", ("MRN1222", "ENC-1222", "SYNTH^ROSA", "19720304", "F")),
    "S3b": ("S3", ("MRN1031", "ENC-1031", "SYNTH^SAM", "19730405", "M")),
    "S1b": ("S1", ("MRN1011", "ENC-1011", "SYNTH^TESS", "19740506", "F")),
    "S2b": ("S2", ("MRN1021", "ENC-1021", "SYNTH^UMA", "19750607", "F")),
    "S25b": ("S25", ("MRN1251", "ENC-1251", "SYNTH^VIC", "19760708", "M")),
    "S25c": ("S25", ("MRN1252", "ENC-1252", "SYNTH^WREN", "19770809", "F")),
}
BOTH = ["Downstream Out", "Records Out"]


def m(sid, seq, trigger, time, recorded=None, no_event_time=False, raw=None, **kw):
    """One message of a variant. recorded is EVN-2 and MSH-7 when they differ from the event time; no_event_time leaves
    EVN-6 empty; raw changes the finished text, for a message no sender should send."""
    G.PATIENTS[sid] = VARIANTS[sid][1]
    _, text, meta = G.message(VARIANTS[sid][0], seq + 50, trigger, time, patient=sid, **kw)
    if recorded:
        stamp = f"{G.DAY}{recorded}00"
        text = re.sub(r"^(MSH(?:\|[^|\r]*){5}\|)\d+", lambda x: x.group(1) + stamp, text)
        text = re.sub(r"\rEVN\|([^|]*)\|\d+", lambda x: f"\rEVN|{x.group(1)}|{stamp}", text)
    if no_event_time:
        text = re.sub(r"(\rEVN\|[^\r]*\|\|\|\|)\d+", r"\1", text)
    if raw:
        text = raw(text)
    return f"{sid}-{seq:02d}-{trigger}.hl7", text, meta


def scenario(sid, title, summary, steps, expected, messages):
    return {"id": sid, "title": title, "summary": summary, "steps": steps, "expected": expected}, messages


def by_downstream(**want):
    return {"Downstream Out": want}


def scenarios():
    out = []

    # EC-053: a clerk's catch-up. The discharge applied, then the morning's move arrives, recorded hours after it happened.
    a = m("S6b", 1, "A01", "0900", ward="WARD-A")
    d = m("S6b", 2, "A03", "1400", ward="WARD-A")
    b = m("S6b", 3, "A02", "0930", recorded="1700", ward="WARD-B", prior="WARD-A")
    out.append(scenario(
        "S6b", "A catch-up entry after the discharge",
        "The 14:00 discharge applied at both receivers; then the 09:30 transfer, recorded at 17:00, is refused by both as an "
        "invalid transition. The bed manager closes it with nothing sent; the records system escalates it with the correcting steps.",
        [{"file": a[0]}, {"file": d[0]}, {"file": b[0], "expect": "delivery_fails"}],
        {"modes": ["policy"], "write": False, "final_state": "discharged", "final_ward": None,
         "failed_operation_key": b[2]["operation_key"],
         "by_receiver": {
             "Downstream Out": {"disposition": "superseded", "outcome": "none", "write": False,
                                "final_state": "discharged", "final_ward": None},
             "Records Out": {"disposition": "escalate", "outcome": "correct_history", "write": False,
                             "final_state": "discharged", "final_ward": None}}},
        [a, d, b]))

    # EC-059: both failed and both plans wait; edge_rows_check.py approves one and reads the other.
    a = m("S22b", 1, "A01", "0900", ward="WARD-A")
    b = m("S22b", 2, "A02", "0920", ward="WARD-B", prior="WARD-A")
    out.append(scenario(
        "S22b", "A write to one of two receivers",
        "The 09:20 transfer fails at both receivers and each case's plan waits. Approving one writes to that receiver only.",
        [{"file": a[0]}, {"fault": "fail_before_accept", "receivers": BOTH}, {"file": b[0], "expect": "delivery_fails"},
         {"wait": 5}, {"fault": "off", "receivers": BOTH}],
        {"modes": ["rules"], "failed_operation_key": b[2]["operation_key"], "write": True, "final_state": "admitted",
         "final_ward": "WARD-B", "disposition": "resend"},
        [a, b]))

    # EC-054: the 14:00 move is keyed at 16:40, after the 15:00 move applied: oldest by event time, newest by arrival.
    a = m("S22c", 1, "A01", "0900", ward="WARD-A")
    c = m("S22c", 2, "A02", "1500", ward="WARD-C", prior="WARD-A")
    b = m("S22c", 3, "A02", "1400", recorded="1640", ward="WARD-B", prior="WARD-A")
    out.append(scenario(
        "S22c", "A backdated transfer",
        "The 15:00 transfer applied at both receivers; the 14:00 one, recorded at 16:40, then fails at both. By event time it "
        "is overtaken, though it arrived last: the bed manager closes it, the records system escalates with the correcting steps.",
        [{"file": a[0]}, {"file": c[0]}, {"fault": "fail_before_accept", "receivers": BOTH},
         {"file": b[0], "expect": "delivery_fails"}, {"wait": 5}, {"fault": "off", "receivers": BOTH}],
        {"modes": ["policy"], "write": False, "final_state": "admitted", "final_ward": "WARD-C",
         "failed_operation_key": b[2]["operation_key"],
         "by_receiver": {
             "Downstream Out": {"disposition": "superseded", "outcome": "none", "write": False,
                                "final_state": "admitted", "final_ward": "WARD-C"},
             "Records Out": {"disposition": "escalate", "outcome": "correct_history", "write": False,
                             "final_state": "admitted", "final_ward": "WARD-C"}}},
        [a, c, b]))

    # EC-082, the same key: the sender repeats the move under a new control id while the plan waits, and this one lands.
    a = m("S3b", 1, "A01", "0900", ward="WARD-A")
    b = m("S3b", 2, "A02", "0920", ward="WARD-B", prior="WARD-A")
    again = m("S3b", 3, "A02", "0920", ward="WARD-B", prior="WARD-A")
    out.append(scenario(
        "S3b", "The sender repeats the move: the same key",
        "The 09:20 transfer fails; while its resend waits for approval the sender repeats it under a new control id, and that "
        "lands. The approval is void and the case reads the receipt: nothing more is written.",
        [{"file": a[0]}, {"fault": "fail_before_accept"}, {"file": b[0], "expect": "delivery_fails"}, {"wait": 5},
         {"fault": "off"}, {"wait_for_state": "awaiting_approval", "timeout": 180}, {"file": again[0]}],
        {"modes": ["rules"], "write": False, "final_state": "admitted", "final_ward": "WARD-B",
         "failed_operation_key": b[2]["operation_key"],
         "history_once": b[2]["operation_key"],
         "by_receiver": by_downstream(disposition="reconcile", write=False, final_state="admitted", final_ward="WARD-B",
                                      blocked_by="APPROVAL_RECEIVER_CHANGED")},
        [a, b, again]))

    # EC-082, a new time: no EVN-6, so a new EVN-2 makes a new key, read as a later transfer to the same ward.
    a = m("S1b", 1, "A01", "0900", ward="WARD-A")
    b = m("S1b", 2, "A02", "0920", no_event_time=True, ward="WARD-B", prior="WARD-A")
    again = m("S1b", 3, "A02", "0940", no_event_time=True, ward="WARD-B", prior="WARD-A")
    out.append(scenario(
        "S1b", "The sender repeats the move: a new time",
        "A sender with no EVN-6 repeats the failed 09:20 transfer stamped 09:40, while the resend waits for approval, and that "
        "lands. It reads as a later transfer: the original is closed and not sent over it.",
        [{"file": a[0]}, {"fault": "fail_before_accept"}, {"file": b[0], "expect": "delivery_fails"}, {"wait": 5},
         {"fault": "off"}, {"wait_for_state": "awaiting_approval", "timeout": 180}, {"file": again[0]}],
        {"modes": ["rules"], "write": False, "final_state": "admitted", "final_ward": "WARD-B",
         "failed_operation_key": b[2]["operation_key"],
         "history_once": again[2]["operation_key"],
         "by_receiver": by_downstream(disposition="superseded", write=False, final_state="admitted", final_ward="WARD-B",
                                      blocked_by="APPROVAL_RECEIVER_CHANGED")},
        [a, b, again]))

    # EC-135 and EC-083: the same operation comes again mapped to another ward, while the plan waits.
    a = m("S2b", 1, "A01", "0900", ward="WARD-A")
    b = m("S2b", 2, "A02", "0920", ward="WARD-B", prior="WARD-A")
    again = m("S2b", 3, "A02", "0920", ward="WARD-C", prior="WARD-A")
    out.append(scenario(
        "S2b", "The same operation, mapped differently",
        "While the resend of the 09:20 transfer to Ward B waits for approval, the same transfer fails again under the same key "
        "carrying Ward C, as after a change of mapping. The case blocks, and nothing is written for either.",
        [{"file": a[0]}, {"fault": "fail_before_accept"}, {"file": b[0], "expect": "delivery_fails"}, {"wait": 5},
         {"fault": "off"}, {"wait_for_state": "awaiting_approval", "timeout": 180},
         {"fault": "fail_before_accept"}, {"file": again[0], "expect": "delivery_fails"}, {"wait": 5}, {"fault": "off"}],
        {"modes": ["rules"], "write": False, "final_state": "admitted", "final_ward": "WARD-A",
         "failed_operation_key": b[2]["operation_key"],
         "by_receiver": by_downstream(disposition="resend", write=False, final_state="admitted", final_ward="WARD-A",
                                      blocked_by="PAYLOAD_CHANGED", final_reason="PAYLOAD_CHANGED")},
        [a, b, again]))

    # EC-121: a raw CR inside a note, and a second PID. Each fails at the bed manager and comes to a case that can't validate it.
    def broken(sid, title, summary, raw):
        a = m(sid, 1, "A01", "0900", ward="WARD-A")
        b = m(sid, 2, "A02", "0920", raw=raw, ward="WARD-B", prior="WARD-A")
        key = b[2]["operation_key"]
        out.append(scenario(
            sid, title, summary,
            [{"file": a[0]}, {"fault": "fail_before_accept", "operation_key": key}, {"file": b[0], "expect": "delivery_fails"},
             {"wait": 5}, {"fault": "off"}],
            {"modes": ["policy"], "write": False, "final_state": "admitted", "final_ward": "WARD-A", "failed_operation_key": key,
             "by_receiver": by_downstream(disposition="escalate", acceptable=["more_evidence", "resend"], write=False,
                                          final_state="admitted", final_ward="WARD-A", final_reason="PARSE_FAILED")},
            [a, b]))

    broken("S25b", "A raw line break inside a note",
           "The transfer's note holds a bare CR, so the rest of its line reads as a segment. Validation refuses it and nothing is "
           "written; nothing rejoins the line.",
           lambda t: t + "OBX|1|TX|NOTE^Transfer note^L||Moved to bay 3\rafter review||||||F\r")
    broken("S25c", "A second PID",
           "The transfer carries a second PID. Validation refuses it and nothing is written.",
           lambda t: re.sub(r"(\rPID\|[^\r]*)", r"\1\rPID|1||MRN1999^^^HOSP^MR||SYNTH^OTHER||19810101|M", t, count=1))
    return out


def main():
    listing = []
    for entry, messages in scenarios():
        folder = os.path.join(HERE, entry["id"])
        os.makedirs(folder, exist_ok=True)
        for name, text, _ in messages:
            with open(os.path.join(folder, name), "w", encoding="utf-8", newline="") as f:
                f.write(text)
        listing.append(entry)
    with open(os.path.join(HERE, "scenarios.json"), "w", encoding="utf-8") as f:
        json.dump(listing, f, indent=2)
        f.write("\n")
    print(f"{len(listing)} scenarios written to {HERE}")


if __name__ == "__main__":
    main()
