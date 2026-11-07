#!/usr/bin/env python3
"""An incident's chains when something changes under them: three outages played as HL7 files into the production.

    python3 tests/e2e/incident_chain_check.py [--url http://localhost:52773] [--container shutter] [--only moved,reset,bed]

moved: a chain of two items under the incident's approval. The answer to item 1's write is lost, and another system updates
    the encounter after the write lands and before Shutter's verification reads it. The next item goes at the version in the
    previous item's receipt, so the sequence rule stops it, and nothing else is written.
reset: the receiver is reset while the chain waits for its approval, and the patient entered again, so the numbers match.
    The approval was given on a plan from before the reset: nothing goes.
bed: an incident whose first chain moves a patient into a bed, and whose last chain moves the bed's occupant out. The first
    chain stops rather than waiting for ever, the occupant leaves, and the patient then gets the bed on fresh evidence.

Its patients are its own and it adds no scenario, so it drops its files into the production's inbound folder through
`docker exec` (the container from --container or CTR). Signs in as the demo users operator and approver (password from
SHUTTER_PASSWORD, default "shutter"); the receiver is read and faulted through its API (_SYSTEM / SYS). It resets the
downstream system, so don't run it on an instance someone else is using. Exit status 1 when a check fails. Standard library
only; no model is called.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from scenario_check import Session, downstream_encounter, wait

FAILURES = []
SOURCE = "INC"
CLOSED_CASE = {"resolved", "blocked", "escalated", "failed"}
# A run's own number, so that a second run on one instance opens new cases
RUN = int(time.time()) % 89 + 10


def check(what, ok, detail=""):
    print(f"{'ok' if ok else 'NOT OK'}  {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILURES.append(what)


def nhs_number(mrn):
    """A synthetic NHS number in the range set aside for test data, as fixtures/generate.py makes one."""
    for pair in range(100):
        base = f"999{mrn[-4:]}{pair:02d}"
        digit = (11 - sum(int(d) * (10 - i) for i, d in enumerate(base)) % 11) % 11
        if digit != 10:
            return base + str(digit)
    raise ValueError(mrn)


class Patient:
    """One synthetic patient of a part, its n deciding where its encounter sorts among the part's."""

    def __init__(self, part, n):
        self.mrn = f"MRN{part}{RUN}{n}"
        self.encounter = f"ENC-{part}{RUN}{n}"
        self.part, self.n, self.seq = part, n, 0

    def message(self, trigger, hhmm, location=None, prior=None):
        """An HL7 ADT message at a local time on the fixtures' day, and its operation key's UTC time."""
        self.seq += 1
        stamp = f"20261015{hhmm}00"
        control = f"INC{self.part}{RUN}{self.n}{self.seq}"
        place = location or ""
        fields = ["1", "I", place, "", "", prior or ""] + [""] * 12 + [self.encounter] + [""] * 24 + ["20261015090000"]
        if trigger == "A03":
            fields.append(stamp)
        return "\r".join([
            f"MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|{stamp}||ADT^{trigger}^ADT_{trigger}|{control}|P|2.5.1",
            f"EVN|{trigger}|{stamp}||||{stamp}",
            f"PID|1||{self.mrn}^^^HOSP^MR~{nhs_number(self.mrn)}^^^NHS^NH||SYNTH^INC{self.n}||19800101|F",
            "PV1|" + "|".join(fields)]) + "\r"

    def key(self, event, hhmm):
        """The operation key of a message of the fixtures' day; 0920 in British Summer Time is 08:20Z."""
        return f"PAS^HOSP^{self.mrn}^{self.encounter}^{event}^2026-10-15T{int(hhmm[:2]) - 1:02d}:{hhmm[2:]}:00Z"


class Rig:
    def __init__(self, args):
        self.args = args
        password = os.environ.get("SHUTTER_PASSWORD", "shutter")
        self.operator = Session(args.url).sign_in("operator", password)
        self.approver = Session(args.url).sign_in("approver", password)
        self.inbound = ""
        self.dropped = 0

    def session(self, code):
        """One terminal command in the namespace; a licence refusal (exit 133) waits and tries again."""
        for _ in range(30):
            done = subprocess.run(["docker", "exec", "-i", self.args.container, "iris", "session", "IRIS", "-U", "SHUTTER"],
                                  input=code + "\nHalt\n", capture_output=True, text=True, check=False)
            if done.returncode != 133:
                return done.stdout
            time.sleep(20)
        raise SystemExit("no terminal session: the licence refused every try")

    def begin(self):
        """The downstream system reset and the mode set, as a scenario's run starts; the inbound folder is read back."""
        out = self.session('Set t = ##class(Shutter.Scenarios.Runner).Begin("INCIDENT-CHECK", "policy", .e) '
                           'Write !,"BEGIN|",e,"|",^Shutter.Config("adtIn"),"|",!')
        line = next((x for x in out.splitlines() if x.startswith("BEGIN|")), "")
        parts = line.split("|")
        if len(parts) < 3 or parts[1]:
            raise SystemExit(f"the reset was refused: {out[-300:]}")
        self.inbound = parts[2].rstrip("/") + "/"
        self.fault({"mode": "off"})

    def drop(self, text):
        """One file into the inbound folder, as the scenario runner drops one: two seconds apart keeps them in order."""
        self.dropped += 1
        name = f"INC{RUN}-{self.dropped:03d}"
        target = self.inbound + name
        subprocess.run(["docker", "exec", "-i", self.args.container, "sh", "-c", f"cat > '{target}.part' && mv '{target}.part' '{target}.hl7'"],
                       input=text.encode(), check=True)
        time.sleep(2)

    def receiver(self, method, path, body=None):
        request = urllib.request.Request(self.args.url.rstrip("/") + "/downstream/api" + path, method=method,
                                         data=None if body is None else json.dumps(body).encode())
        request.add_header("Authorization", "Basic " + base64.b64encode(b"_SYSTEM:SYS").decode())
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status
        except urllib.error.HTTPError as error:
            return error.code

    def fault(self, body):
        status = self.receiver("POST", "/faults", body)
        if status != 200:
            raise SystemExit(f"the receiver refused the fault {body}: HTTP {status}")

    def enter(self, patient, event, ward, when, source="WARD", key=None):
        """A write entered in the receiver's own screens, not through the feed."""
        return self.receiver("POST", "/operations", {
            "operation_key": key or f"{source}^HOSP^{patient.mrn}^{patient.encounter}^{event}^{when}",
            "encounter_id": patient.encounter, "patient_id": patient.mrn, "patient_id_authority": "HOSP", "event": event,
            "event_time": when, "source_system": source, **({"ward": ward} if ward else {})})

    def held(self, patient):
        return downstream_encounter(self.args.url, "_SYSTEM", "SYS", patient.encounter)

    def incident_of(self, patient):
        """The incident holding the patient's chain, once it has one."""
        def found():
            _, listing = self.operator.call("GET", "/incidents?limit=10")
            for row in (listing or {}).get("items", []) if isinstance(listing, dict) else (listing or []):
                _, inc = self.operator.call("GET", "/incidents/" + urllib.parse.quote(row["incidentId"]))
                if any(c.get("encounterId") == patient.encounter for c in (inc or {}).get("chains") or []):
                    return inc
            return None
        return wait(f"a chain for {patient.encounter}", found, self.args.timeout)

    def reread(self, incident):
        return self.operator.call("GET", "/incidents/" + urllib.parse.quote(incident["incidentId"]))[1]

    def chain(self, incident, patient):
        return next(c for c in self.reread(incident).get("chains") or [] if c.get("encounterId") == patient.encounter)

    def approve(self, incident):
        body = {"planDigest": (incident.get("plan") or {}).get("digest"), "decision": "approve", "comment": "chain check"}
        status, out = self.approver.call("POST", f"/incidents/{urllib.parse.quote(incident['incidentId'])}/approvals",
                                         body, idempotent=True)
        if status != 202:
            raise SystemExit(f"the approval was refused: HTTP {status} {out}")

    def closes(self, incident, timeout=None):
        def closed():
            inc = self.reread(incident)
            return inc if inc.get("state") == "closed" else None
        try:
            return wait(f"{incident['incidentId']} to close", closed, timeout or self.args.timeout)
        except TimeoutError as error:
            check(str(error), False)
            return self.reread(incident)

    def case(self, case_id):
        return self.operator.call("GET", "/cases/" + urllib.parse.quote(case_id))[1] or {}

    def writes(self, case_id):
        _, attempts = self.operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/attempts")
        return [(a.get("attempt") or {}).get("outcome") for a in attempts or []]

    def events(self, case_id):
        _, events = self.operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/events?limit=200")
        rows = events if isinstance(events, list) else (events or {}).get("items", [])
        return " ".join(str(e.get("text") or "") for e in rows)


def burst(rig, part):
    """An outage with one ordered chain under the incident's approval, whose encounter sorts after three single chains."""
    singles = [Patient(part, n) for n in (1, 2, 3)]
    ordered = Patient(part, 9)
    for i, p in enumerate(singles + [ordered]):
        rig.drop(p.message("A01", "0900", f"WARD-A^BAY1^{i + 10:02d}^HOSP"))
    rig.fault({"mode": "fail_before_accept"})
    for i, p in enumerate(singles):
        rig.drop(p.message("A02", "0920", f"WARD-B^BAY2^{i + 10:02d}^HOSP", f"WARD-A^BAY1^{i + 10:02d}^HOSP"))
    rig.drop(ordered.message("A02", "0920", "WARD-B^BAY2^20^HOSP", "WARD-A^BAY1^13^HOSP"))
    rig.drop(ordered.message("A03", "0950", "WARD-B^BAY2^20^HOSP"))
    rig.fault({"mode": "off"})
    return ordered


def waiting_for_approval(rig, ordered):
    """The incident once it is waiting for the approval and its automatic chains are done."""
    incident = rig.incident_of(ordered)

    def settled():
        inc = rig.reread(incident)
        chains = inc.get("chains") or []
        return inc if inc.get("state") == "awaiting_approval" and all(
            c.get("state") in ("awaiting_approval", "resolved") for c in chains) else None

    return wait("the incident to wait for its approval", settled, rig.args.timeout)


def moved(rig):
    print("-- moved: another system writes between item 1's commit and its verification", flush=True)
    rig.begin()
    ordered = burst(rig, 1)
    incident = waiting_for_approval(rig, ordered)
    chain = rig.chain(incident, ordered)
    check("the chain is ordered, under the incident's approval", chain.get("kind") == "ordered" and chain.get("policy") == "approval",
          f"{chain.get('kind')} {chain.get('policy')}")
    version = rig.held(ordered).get("version")
    # The connector gives up at 15 s, with the receiver still holding the write: the answer is lost.
    rig.fault({"mode": "delay_response", "seconds": 20, "operation_key": ordered.key("transfer", "0920")})
    rig.approve(incident)

    def committed():
        return (rig.held(ordered).get("version") or 0) > version

    wait("item 1 to land at the receiver", committed, rig.args.timeout, every=0.5)
    status = rig.enter(ordered, "update", None, "2026-10-15T08:40:00Z")
    check("another system updates the encounter before the verification reads it", status == 201, f"HTTP {status}")
    rig.fault({"mode": "off"})
    final = rig.closes(incident)
    chain = next(c for c in final.get("chains") or [] if c.get("encounterId") == ordered.encounter)
    first, second = chain["items"][0], chain["items"][1]
    check("item 1 is verified, its answer having been lost", first.get("state") == "resolved"
          and rig.writes(first["caseId"]) == ["uncertain"], f"{first.get('state')} {rig.writes(first['caseId'])}")
    check("item 1's version is its receipt's, not the encounter's", first.get("verifiedVersion") == version + 1,
          f"{first.get('verifiedVersion')}, the receiver went from {version}")
    case2 = rig.case(second["caseId"])
    check("item 2 is stopped by the sequence rule", case2.get("state") == "blocked" and "sequence rule" in (case2.get("headline") or ""),
          f"{case2.get('state')}: {case2.get('headline')}")
    check("item 2 wrote nothing", not rig.writes(second["caseId"]), str(rig.writes(second["caseId"])))
    check("the chain says it stopped", chain.get("state") == "stopped", str(chain.get("state")))
    held = rig.held(ordered)
    check("the receiver keeps the patient admitted, one write and the other system's further on",
          held.get("state") == "admitted" and held.get("version") == version + 2, f"{held.get('state')} v{held.get('version')}")


def reset(rig):
    print("-- reset: the receiver is reset while the chain waits for its approval", flush=True)
    rig.begin()
    ordered = burst(rig, 2)
    incident = waiting_for_approval(rig, ordered)
    chain = rig.chain(incident, ordered)
    version = rig.held(ordered).get("version")
    status = rig.receiver("POST", "/reset")
    check("the receiver is reset", status == 200, f"HTTP {status}")
    status = rig.enter(ordered, "admit", "WARD-A", "2026-10-15T08:00:00Z", source="PAS", key=ordered.key("admit", "0900"))
    check("the patient is entered again, at the same version", status == 201 and rig.held(ordered).get("version") == version,
          f"HTTP {status}, v{rig.held(ordered).get('version')}, was v{version}")
    rig.approve(incident)
    final = rig.closes(incident)
    chain = next(c for c in final.get("chains") or [] if c.get("encounterId") == ordered.encounter)
    first = chain["items"][0]
    case1 = rig.case(first["caseId"])
    check("the item is blocked, not written", case1.get("state") == "blocked" and not rig.writes(first["caseId"]),
          f"{case1.get('state')} {rig.writes(first['caseId'])}")
    check("the reason is the reset", "RECEIVER_RESET" in rig.events(first["caseId"]), rig.events(first["caseId"])[-400:])
    check("the chain stops", chain.get("state") == "stopped", str(chain.get("state")))
    held = rig.held(ordered)
    check("the receiver holds the patient as entered", held.get("ward") == "WARD-A" and held.get("version") == version,
          f"{held.get('ward')} v{held.get('version')}")


def bed(rig):
    print("-- bed: a chain waits on a bed whose occupant's movement is held in a later chain", flush=True)
    rig.begin()
    arriving, occupant = Patient(3, 1), Patient(3, 9)
    others = [Patient(3, n) for n in (2, 3, 4)]
    bed_b = "WARD-B^BAY2^02^HOSP"
    rig.drop(arriving.message("A01", "0900", "WARD-A^BAY1^01^HOSP"))
    rig.drop(occupant.message("A01", "0905", bed_b))
    for i, p in enumerate(others):
        rig.drop(p.message("A01", "0900", f"WARD-A^BAY1^{i + 10:02d}^HOSP"))
    rig.fault({"mode": "fail_before_accept"})
    rig.drop(occupant.message("A02", "0920", "WARD-C^BAY1^07^HOSP", bed_b))
    for i, p in enumerate(others):
        rig.drop(p.message("A02", "0920", f"WARD-B^BAY2^{i + 10:02d}^HOSP", f"WARD-A^BAY1^{i + 10:02d}^HOSP"))
    rig.fault({"mode": "off"})
    rig.drop(arriving.message("A02", "0930", bed_b, "WARD-A^BAY1^01^HOSP"))
    incident = rig.incident_of(arriving)
    first = rig.chain(incident, arriving)
    last = rig.chain(incident, occupant)
    check("the arriving patient's chain goes before the occupant's", first.get("seq") < last.get("seq"), f"{first.get('seq')} {last.get('seq')}")
    # Well past what the other chains take: without the fix this is where the check ends.
    final = rig.closes(incident)
    check("the incident closes", final.get("state") == "closed", str(final.get("state")))
    by_encounter = {c.get("encounterId"): c for c in final.get("chains") or []}
    check("the arriving patient's chain stopped", by_encounter[arriving.encounter].get("state") == "stopped",
          str(by_encounter[arriving.encounter].get("state")))
    check("the occupant's chain resolved", by_encounter[occupant.encounter].get("state") == "resolved",
          str(by_encounter[occupant.encounter].get("state")))
    check("the occupant has left the bed", rig.held(occupant).get("ward") == "WARD-C", str(rig.held(occupant).get("ward")))
    case_id = by_encounter[arriving.encounter]["items"][0]["caseId"]

    def settled():
        case = rig.case(case_id)
        return case if case.get("state") in CLOSED_CASE and not case.get("waitsOn") else None

    case = wait("the arriving patient's case to settle on fresh evidence", settled, rig.args.timeout)
    check("the arriving patient's case resolved by itself", case.get("state") == "resolved", f"{case.get('state')}: {case.get('headline')}")
    held = rig.held(arriving)
    check("the arriving patient has the bed", held.get("ward") == "WARD-B" and held.get("bed") == "BAY2-02",
          f"{held.get('ward')} {held.get('bed')}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--container", default=os.environ.get("CTR", "shutter"))
    p.add_argument("--only", default="moved,reset,bed")
    p.add_argument("--timeout", type=int, default=300, help="seconds to wait for each step")
    args = p.parse_args()
    rig = Rig(args)
    parts = {"moved": moved, "reset": reset, "bed": bed}
    for name in args.only.split(","):
        parts[name](rig)
    print(f"{len(FAILURES)} failed" if FAILURES else "all as expected", flush=True)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
