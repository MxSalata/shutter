#!/usr/bin/env python3
"""Checks every case's lineage in the message warehouse: nothing is written before the gate and the rehearsal.

    python3 tests/e2e/lineage_check.py [--url http://localhost:52773] [--ns SHUTTER] [--cases C-000001,...]

For each case, from Ens.MessageHeader in its workflow session (the order of the message ids is the order of events):
the board's first agent request, the gate's first request, the first rehearsal, the approval task's response, the first
recovery write and their count, the verification, and for a FHIR receiver the FHIR gate's first request, the first FHIR
write and their count. Holds, for every case:
  1. a write comes after the gate and after a rehearsal (gate < rehearsal < write);
  2. an approval, when there is one, comes before the write (judged where the session holds one case only: an
     incident's chains share a session, and one chain may be released by policy while another waits for a person);
  3. on the board, the agents decide before the gate judges (board < gate);
  4. a case resolved by a resend wrote at least once and was verified after it; the write may be a FHIR write;
  5. a FHIR write comes after the FHIR gate and after an approval (FHIR gate < approval < FHIR write), and there is
     exactly one: no policy releases it, and one approval allows one update.
Several cases can share one session (one message at two receivers, S22 and S23b); the checks hold per session then.
A blocked case may have written: the receiver refused the write (S23c's occupied bed). Exit status 1 when any fails.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iris_query import query  # noqa: E402

LINEAGE = """SELECT
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Bridge.Msg.AgentRequest') AS Board,
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.GateRequest') AS Gate,
 (SELECT MIN(h.ID) FROM Ens.MessageHeader h JOIN Shutter_Msg.WardOperation w ON w.ID = h.MessageBodyId
   AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation'
   WHERE h.SessionId = ? AND w.Purpose = 'rehearsal') AS Rehearsal,
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'EnsLib.Workflow.TaskResponse') AS Approval,
 (SELECT MIN(h.ID) FROM Ens.MessageHeader h JOIN Shutter_Msg.WardOperation w ON w.ID = h.MessageBodyId
   AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation'
   WHERE h.SessionId = ? AND w.Purpose = 'recovery') AS FirstWrite,
 (SELECT COUNT(*) FROM Ens.MessageHeader h JOIN Shutter_Msg.WardOperation w ON w.ID = h.MessageBodyId
   AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation'
   WHERE h.SessionId = ? AND w.Purpose = 'recovery') AS WriteCount,
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.VerifyRequest') AS Verify,
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.FHIRGateRequest') AS FhirGate,
 (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.FHIRWrite') AS FhirWrite,
 (SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.FHIRWrite') AS FhirWriteCount"""


def problems(case, ln, shared):
    """The rules a case's lineage breaks, as sentences. `shared`: other cases share the session (an incident's
    chains, or one message at two receivers), where approvals and writes of different chains interleave."""
    g = {k: int(v or 0) for k, v in ln.items()}
    out = []
    if g["WriteCount"]:
        if not g["Gate"] or not g["Rehearsal"] or not (g["Gate"] < g["Rehearsal"] < g["FirstWrite"]):
            out.append(f"a write ({g['FirstWrite']}) without the gate ({g['Gate']}) and a rehearsal ({g['Rehearsal']}) before it")
        if not shared and g["Approval"] and not g["Approval"] < g["FirstWrite"]:
            out.append(f"the approval ({g['Approval']}) comes after the write ({g['FirstWrite']})")
    if g["FhirWriteCount"]:
        if not g["FhirGate"] or not g["Approval"] or not (g["FhirGate"] < g["Approval"] < g["FhirWrite"]):
            out.append(f"a FHIR write ({g['FhirWrite']}) without the FHIR gate ({g['FhirGate']}) and an approval ({g['Approval']}) before it")
        if g["FhirWriteCount"] != 1:
            out.append(f"{g['FhirWriteCount']} FHIR writes in a session where one approval allows one")
    if case["Mode"] == "board" and g["Board"] and g["Gate"] and not g["Board"] < g["Gate"]:
        out.append(f"the gate ({g['Gate']}) judged before the board's first run ({g['Board']})")
    if case["State"] == "resolved" and case["Disposition"] == "resend":
        if g["WriteCount"]:
            if not g["Verify"] or not g["Verify"] > g["FirstWrite"]:
                out.append(f"resolved by a resend with no verification after the write ({g['FirstWrite']}, verify {g['Verify']})")
        elif g["FhirWriteCount"]:
            if not g["Verify"] or not g["Verify"] > g["FhirWrite"]:
                out.append(f"resolved by a FHIR write with no verification after it ({g['FhirWrite']}, verify {g['Verify']})")
        else:
            out.append("resolved by a resend with no write")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default="SHUTTER")
    ap.add_argument("--cases", default="", help="comma-separated case ids (default: every case)")
    args = ap.parse_args()
    cases = query(args.url, args.ns, 'SELECT CaseId, %EXACT(Mode) AS Mode, %EXACT(State) AS State, '
                  '%EXACT(Disposition) AS Disposition, WorkflowSessionId FROM Shutter_Store."Case" ORDER BY ID')
    wanted = {c.strip() for c in args.cases.split(",") if c.strip()}
    if wanted:
        cases = [c for c in cases if c["CaseId"] in wanted]
    per_session = {}
    for c in cases:
        if c.get("WorkflowSessionId"):
            per_session[c["WorkflowSessionId"]] = per_session.get(c["WorkflowSessionId"], 0) + 1
    failed = checked = 0
    for c in cases:
        s = c.get("WorkflowSessionId")
        if not s:
            continue
        checked += 1
        found = problems(c, query(args.url, args.ns, LINEAGE, [s] * LINEAGE.count("?"))[0], per_session.get(s, 0) > 1)
        if found:
            failed += 1
            print(f"FAIL {c['CaseId']} ({c['Mode']}, {c['State']}, {c['Disposition']}): " + "; ".join(found))
    print(f"{checked} cases checked, {failed} with a lineage problem" if failed else
          f"{checked} cases checked: every write came after the gate and a rehearsal, or for a FHIR case after its gate and "
          "its own approval, and every resolved resend was verified")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
