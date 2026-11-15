#!/usr/bin/env python3
"""Checks a site's own catalogue entry end to end over HTTP against docs/CONTRACTS.md, section 6.8: the brake.

    python3 tests/e2e/site_entry_check.py [--url http://localhost:52773] [--timeout 240]

On a demo instance, with nobody else using it. It plays S2 (a failed transfer, still current: a resend by site policy)
and S1 (the same transfer overtaken: closed with nothing sent) to have two stored, closed cases, then:

1. An entry made from S2's case by one person (the instance's administrator, who holds every right): refused without a
   proof (409 no_proof); proved on S2's case, which it must match, and S1's, which it must leave alone; proposed; its
   author's own approval refused (409 same_person); another digest refused (409 digest_mismatch); approved by a second
   person (the demo's approver). The catalogue's version then carries the generation and the entry.
2. The mode matrix. S2 in Site policy, Board and Single investigator mode: escalated naming the entry, made by the
   catalogue with no board, the shipped entry it displaced shown beside it, and no write in the receiver's history
   (the patient is still in Ward A). S2 in Rules only: the recorded baseline, as documented: the plain resend goes.
3. A board convened by hand on the escalated case: its recorded plan is the resend, which the unchanged gate blocks;
   the case is not resolved and nothing is written.
4. A second, broader entry with a lower priority number: it leads, and the first is shown beside it with its
   instructions.
5. Suspension by one approver (the case is the shipped catalogue's again, the Doctor warns), resumption by two.
6. Retirement by two people: S2 resends again, and the version keeps a higher generation with no entry.

What this does not reach, and where it is checked instead (tests/unit/Shutter/Test): a real case in Rules only, which
the gate blocks with ENTRY_NOT_NAMED_WRITE (Shutter.Test.Gate's rows, Shutter.Test.SiteSafety); a convened board whose
plan is to close, which goes to a person (Shutter.Test.SiteEntryRace: no recording holds such a plan for S2); an entry
that overlaps the entry for a death on the message, which leads (Shutter.Test.SiteSafety: no scenario records a death).

Every site entry this leaves is retired, so the scenarios after it run on the shipped catalogue. Exit status 1 when a
check fails. Standard library only.
"""
import argparse
import os
import re
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scenario_check import CLOSED, Session, downstream_encounter, wait, wait_until_idle  # noqa: E402

ENCOUNTER = "ENC-1002"


def generation_of(version):
    """The generation a catalogue version carries (";g<n>:"), or -1 when it carries none."""
    found = re.search(r";g(\d+):", version or "")
    return int(found.group(1)) if found else -1


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each case")
    p.add_argument("--admin-user", default="_SYSTEM", help="the entries' author: an account holding Shutter_Configure")
    p.add_argument("--admin-password", default="SYS")
    args = p.parse_args()

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    author = Session(args.url).sign_in(args.admin_user, args.admin_password)
    failures = []

    def check(name, condition, detail=""):
        print(("ok   " if condition else "FAIL ") + name + ("" if condition else f"  ({detail})"), flush=True)
        if not condition:
            failures.append(name)
        return condition

    def error_of(body):
        return (body or {}).get("error")

    def play(scenario, mode, approve=False):
        """Plays a scenario in a mode and returns its case once closed, or (None, why) when the run is refused."""
        wait_until_idle(operator, args.timeout)
        before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        status, started = operator.call("POST", f"/scenarios/{scenario}/run", {"mode": mode}, idempotent=True)
        if status not in (200, 202):
            return None, f"HTTP {status} {error_of(started)}"
        started_at = max(started.get("startedAt") or "", started.get("queuedAt") or "", before)

        def run_state():
            _, body = operator.call("GET", "/scenarios")
            run = (body or {}).get("run") or {}
            return run.get("state") if run.get("scenario") == scenario else None

        def newest():
            _, body = operator.call("GET", f"/cases?scenario={scenario}&limit=5")
            items = [c for c in (body or {}).get("items", []) if c.get("openedAt", "") >= started_at]
            return items[0] if items else None

        case = wait(f"{scenario} {mode}: a case", newest, args.timeout)
        approved = [False]

        def settled():
            _, c = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}")
            if c["state"] in CLOSED and run_state() != "running":
                return c
            if c["state"] == "awaiting_approval" and approve and not approved[0] and run_state() != "running":
                _, view = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}/plan")
                decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"], "comment": "site entry check"}
                status, body = approver.call("POST", f"/cases/{urllib.parse.quote(case['caseId'])}/approvals", decision, idempotent=True)
                if status != 202:
                    raise RuntimeError(f"the approval was refused: HTTP {status} {body}")
                approved[0] = True
            return None

        final = wait(f"{scenario} {mode} {case['caseId']}: the outcome", settled, args.timeout)
        return listed(final), ""

    def listed(case):
        """The case with what only the cases list carries: its writes."""
        _, body = operator.call("GET", f"/cases?scenario={urllib.parse.quote(case.get('scenario') or '')}&limit=20")
        for item in (body or {}).get("items", []):
            if item.get("caseId") == case["caseId"]:
                return dict(case, writes=item.get("writes"))
        return case

    def catalogue_of(case_id):
        _, snap = operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/snapshot")
        summary = (snap or {}).get("summary") or {}
        return summary.get("catalogue") or {}

    def ward():
        held = downstream_encounter(args.url, "_SYSTEM", "SYS", ENCOUNTER)
        return held.get("ward"), [h.get("event") for h in held.get("history") or []]

    def site_entry(entry_id):
        _, body = operator.call("GET", f"/site-entries/{entry_id}")
        return body or {}

    def decide(session, entry_id, action, decision="approve", digest=None, reason="site entry check"):
        proposal = site_entry(entry_id).get("proposal") or {}
        body = {"action": action, "version": proposal.get("version"), "digest": digest or proposal.get("digest"), "decision": decision, "reason": reason}
        return session.call("POST", f"/site-entries/{entry_id}/approvals", body)

    def two_people(entry_id, action):
        """An action proved and proposed by the author, approved by the approver. Returns the approval's answer."""
        status, proof = author.call("POST", f"/site-entries/{entry_id}/proof", {"action": action})
        if status != 200 or not (proof or {}).get("passed"):
            return status, proof
        status, body = author.call("POST", f"/site-entries/{entry_id}/propose", {"action": action})
        if status != 200:
            return status, body
        return decide(approver, entry_id, action)

    made = []
    try:
        # ---- two stored, closed cases ----
        _, before = operator.call("GET", "/catalogue")
        shipped = (before or {}).get("shippedVersion", "")
        version_before = (before or {}).get("version", "")
        check("GET /catalogue lists the shipped entries with the catalogue's version", len((before or {}).get("shipped") or []) > 0 and shipped != "", str(before)[:200])
        check("the vocabulary is served with it", "event" in (((before or {}).get("vocabulary") or {}).get("conditions") or {}))
        baseline, why = play("S2", "policy", approve=True)
        check("with no site entry, S2 in Site policy mode resends and resolves", baseline and baseline["state"] == "resolved" and baseline.get("writes") == 1, f"{why} {baseline and baseline['state']}")
        check("and the receiver holds the patient in Ward B", ward()[0] == "WARD-B", str(ward()))
        near, why = play("S1", "policy", approve=True)
        check("S1 in Site policy mode closes with nothing sent", near and near["state"] == "resolved" and near.get("writes") == 0, f"{why} {near and near['state']}")
        if not baseline or not near:
            raise SystemExit("the two cases the entry is proved on could not be made")
        match_id, near_id = baseline["caseId"], near["caseId"]
        check("S2's case matched E2 alone", catalogue_of(match_id).get("entry") == "E2", str(catalogue_of(match_id).get("entry")))

        # ---- 1. the entry: a draft, a proof, a proposal, a second person ----
        body = {"fromCase": match_id, "title": "A failed transfer into Ward B", "priority": 10,
                "why": "The ward places its patients by hand this month, so a resend cannot know the bed is right.",
                "instructions": "Ring the ward's nurse in charge before anything is entered. Do not resend.",
                "fixtures": [{"case": match_id, "expect": "match"}, {"case": near_id, "expect": "no_match"}]}
        status, valid = operator.call("POST", "/site-entries/validate", dict({k: v for k, v in body.items() if k != "fromCase"}, pattern={"event": "transfer", "delivery": ["failed", "uncertain"]}))
        check("POST /site-entries/validate answers the sentence and what the pattern can displace", status == 200 and valid.get("valid") and "a person decides" in valid.get("sentence", "") and any(o.get("id") == "E2" for o in valid.get("overlap", [])), f"{status} {str(valid)[:300]}")
        status, refused = operator.call("POST", "/site-entries/validate", dict({k: v for k, v in body.items() if k != "fromCase"}, pattern={"event": "transfer"}, decides="policy"))
        check("and refuses a body that says who decides", status == 200 and not refused.get("valid") and any(pr.get("field") == "decides" for pr in refused.get("problems", [])), f"{status} {str(refused)[:300]}")
        _, listed = operator.call("GET", "/site-entries")
        status, preview = operator.call("POST", "/site-entries/preview", body)
        rows = ((preview or {}).get("proof") or {}).get("fixtures") or []
        check("POST /site-entries/preview from S2's case: the proof passes, the entry leads there and leaves S1's alone", status == 200 and ((preview or {}).get("proof") or {}).get("passed") and len(rows) == 2 and rows[0].get("lead") == preview.get("id") and rows[1].get("holds") is False, f"{status} {str(preview)[:400]}")
        check("its content is the case's conditions and facts, as a draft's would be", ((preview or {}).get("content") or {}).get("pattern", {}).get("event") == ["transfer"] and ((preview or {}).get("content") or {}).get("scope", {}).get("ward") == ["WARD-B"], str((preview or {}).get("content"))[:300])
        check("its impact counts S2's case", match_id in str((((preview or {}).get("proof") or {}).get("impact") or {}).get("cases")), str(((preview or {}).get("proof") or {}).get("impact"))[:300])
        _, after_preview = operator.call("GET", "/site-entries")
        check("and the preview stored nothing", len((after_preview or {}).get("items") or []) == len((listed or {}).get("items") or []) and "proofId" not in ((preview or {}).get("proof") or {}), f"{len((after_preview or {}).get('items') or [])} {len((listed or {}).get('items') or [])}")
        check("GET /site-entries says how many open plans an approval would stop", isinstance((after_preview or {}).get("waitingPlans"), int), str((after_preview or {}).get("waitingPlans")))
        status, entry = author.call("POST", "/site-entries", body)
        check("POST /site-entries makes a draft from S2's case", status == 201 and str((entry or {}).get("id", "")).startswith("L") and entry.get("state") == "draft", f"{status} {str(entry)[:300]}")
        if status != 201:
            raise SystemExit("no draft was made")
        first = entry["id"]
        made.append(first)
        content = entry.get("content") or {}
        check("its pattern is the conditions the case showed, without the reserved one", content.get("pattern", {}).get("event") == ["transfer"] and "death_recorded" not in content.get("pattern", {}), str(content.get("pattern"))[:300])
        check("its scope is the case's facts", content.get("scope", {}).get("ward") == ["WARD-B"] and content.get("scope", {}).get("receiver") == [baseline.get("receiver")], str(content.get("scope")))
        check("and it has no field for who decides or the outcome", not any(k in content for k in ("decides", "preferred", "alternatives", "outcome")))
        status, refused = author.call("POST", f"/site-entries/{first}/propose", {"action": "activate"})
        check("a proposal with no proof is 409 no_proof", status == 409 and error_of(refused) == "no_proof", f"{status} {refused}")
        status, proof = author.call("POST", f"/site-entries/{first}/proof", {})
        rows = (proof or {}).get("fixtures") or []
        check("the proof passes: the entry leads on S2's case and leaves S1's alone", status == 200 and proof.get("passed") and len(rows) == 2 and rows[0].get("lead") == first and rows[1].get("holds") is False, f"{status} {str(proof)[:400]}")
        check("its impact counts S2's case among the last stored cases", match_id in str(((proof or {}).get("impact") or {}).get("cases")) and near_id not in str(((proof or {}).get("impact") or {}).get("cases")), str((proof or {}).get("impact"))[:300])
        status, proposed = author.call("POST", f"/site-entries/{first}/propose", {"action": "activate"})
        check("proposed: the entry waits for approval", status == 200 and proposed.get("state") == "proposed" and (proposed.get("proposal") or {}).get("action") == "activate", f"{status} {str(proposed)[:300]}")
        _, unchanged = operator.call("GET", "/catalogue")
        check("a proposal changes nothing: the catalogue's version is what it was", unchanged.get("version") == version_before, unchanged.get("version"))
        status, refused = author.call("PUT", f"/site-entries/{first}", dict(body, expectedVersion=proposed.get("revision")))
        check("a proposed version is frozen (409 wrong_state)", status == 409 and error_of(refused) == "wrong_state", f"{status} {refused}")
        status, refused = decide(author, first, "activate")
        check("the author's own approval is 409 same_person", status == 409 and error_of(refused) == "same_person", f"{status} {refused}")
        status, refused = decide(approver, first, "activate", digest="sha256:another")
        check("another digest is 409 digest_mismatch", status == 409 and error_of(refused) == "digest_mismatch", f"{status} {refused}")
        status, refused = operator.call("POST", f"/site-entries/{first}/approvals", {"action": "activate"})
        check("an operator's approval is 403", status == 403, f"{status} {refused}")
        status, active = decide(approver, first, "activate", reason="Agreed with the ward's manager")
        check("a second person approves: active", status == 200 and active.get("state") == "active" and active.get("approvedBy") == "approver", f"{status} {str(active)[:300]}")
        version = (active or {}).get("catalogueVersion", "")
        check("the catalogue's version carries the generation and the entry", version.startswith(shipped + ";g") and version.endswith(f":{first}@1"), version[-40:])
        activated_at = generation_of(version)
        check("the answer says how many waiting plans were made under the old version", isinstance((active or {}).get("waitingPlans"), int), str((active or {}).get("waitingPlans")))
        _, listing = operator.call("GET", "/catalogue")
        site = (listing or {}).get("site") or []
        check("GET /catalogue lists the entry as the matcher reads it: a person, escalate, no alternatives", len(site) == 1 and site[0].get("id") == first and site[0].get("decides") == "person" and site[0].get("preferred", {}).get("outcome") == "escalate" and site[0].get("alternatives") == [], str(site)[:300])

        # ---- 2. the mode matrix ----
        escalated = None
        for mode, name in (("policy", "Site policy"), ("board", "Board"), ("single", "Single investigator")):
            case, why = play("S2", mode)
            if case is None and "not_recorded" in why:
                print(f"skip S2 in {name} mode: the run is refused here ({why}); the mode is checked in process (Shutter.Test.SiteEntryRace)")
                continue
            if not check(f"S2 in {name} mode: escalated", case and case["state"] == "escalated", f"{why} {case and case['state']}"):
                continue
            escalated = escalated or case
            check(f"S2 in {name} mode: naming the entry, by the catalogue and no board", case.get("catalogueEntry") == first and case.get("planCreatedBy") == f"policy:{first}", f"{case.get('catalogueEntry')} {case.get('planCreatedBy')}")
            cat = catalogue_of(case["caseId"])
            match = (cat.get("matches") or [{}])[0]
            check(f"S2 in {name} mode: the match is the entry alone, a person, escalate", len(cat.get("matches") or []) == 1 and match.get("origin") == "site" and match.get("decides") == "person" and cat.get("outcome") == "escalate", str(cat)[:300])
            check(f"S2 in {name} mode: E2 is shown as displaced, with the entry's instructions", [o.get("id") for o in cat.get("overridden") or []] == ["E2"] and "Ring the ward" in match.get("instructions", ""), str(cat.get("overridden")))
            held, events = ward()
            check(f"S2 in {name} mode: no write in the receiver's history", case.get("writes") == 0 and held == "WARD-A" and "transfer" not in events, f"writes {case.get('writes')}, ward {held}, history {events}")
        case, why = play("S2", "rules", approve=True)
        check("S2 in Rules only: the recorded baseline resends, as documented", case and case["state"] == "resolved" and case.get("writes") == 1, f"{why} {case and case['state']} writes {case and case.get('writes')}")
        check("the entry counts the cases it sent to a person", site_entry(first).get("casesSent", 0) >= 1, str(site_entry(first).get("casesSent")))

        # ---- 3. a board convened by hand on the escalated case ----
        if escalated:
            # The newest S2 run left the receiver after the baseline's resend: play it once more so the patient is in Ward A.
            escalated, why = play("S2", "policy")
            status, convened = approver.call("POST", f"/cases/{urllib.parse.quote(escalated['caseId'])}/board", {"reason": "site entry check"}, idempotent=True)
            if status in (200, 202):
                def closed_again():
                    _, c = operator.call("GET", f"/cases/{urllib.parse.quote(escalated['caseId'])}")
                    return c if c["state"] in CLOSED and c.get("version") != escalated.get("version") else None

                final = listed(wait("the convened board's case to close again", closed_again, args.timeout))
                check("a board convened on the escalated case does not resolve it", final["state"] in ("blocked", "escalated"), final["state"])
                held, events = ward()
                check("and nothing is written", final.get("writes") == 0 and held == "WARD-A" and "transfer" not in events, f"writes {final.get('writes')}, ward {held}")
            elif status == 409 and error_of(convened) == "live_unavailable":
                # No model can run on this instance: the one refusal that is not a fault.
                print(f"skip the convened board: POST /cases/{{id}}/board answered HTTP {status} {error_of(convened)}")
            else:
                check("a board can be convened on the escalated case", False, f"HTTP {status} {convened}")

        # ---- 4. two site entries: the priority leads, and both instructions show ----
        broad = {"title": "Any failed transfer nothing has overtaken", "priority": 5, "pattern": {"event": "transfer", "later_applied": "none"},
                 "why": "The trust is moving wards this week.", "instructions": "Tell the bed manager first.",
                 "fixtures": [{"case": match_id, "expect": "match"}, {"case": near_id, "expect": "no_match"}]}
        status, entry = author.call("POST", "/site-entries", broad)
        check("a second, broader entry is drafted", status == 201, f"{status} {str(entry)[:300]}")
        if status == 201:
            second = entry["id"]
            made.append(second)
            status, body2 = two_people(second, "activate")
            check("and activated by two people", status == 200 and (body2 or {}).get("state") == "active", f"{status} {str(body2)[:300]}")
            case, why = play("S2", "policy")
            cat = catalogue_of(case["caseId"]) if case else {}
            check("S2 with two site entries: the lower priority number leads", case and case["state"] == "escalated" and case.get("catalogueEntry") == second, f"{why} {case and case.get('catalogueEntry')}")
            also = cat.get("site_also") or []
            check("and the other is shown beside it with its instructions", [a.get("id") for a in also] == [first] and "Ring the ward" in (also[0].get("instructions") if also else ""), str(also)[:300])
            check("the leading entry's own instructions show too", "bed manager" in ((cat.get("matches") or [{}])[0].get("instructions") or ""))
            status, body2 = two_people(second, "retire")
            check("the second entry is retired by two people", status == 200 and (body2 or {}).get("state") == "retired", f"{status} {str(body2)[:300]}")

        # ---- 5. suspension by one approver, resumption by two ----
        status, refused = operator.call("POST", f"/site-entries/{first}/suspend", {"reason": "it floods the on-call"})
        check("an operator cannot suspend (403)", status == 403, f"{status}")
        status, refused = approver.call("POST", f"/site-entries/{first}/suspend", {})
        check("a suspension needs a reason (400)", status == 400, f"{status} {refused}")
        status, suspended = approver.call("POST", f"/site-entries/{first}/suspend", {"reason": "It floods the on-call with escalations"})
        check("one approver suspends the entry at once", status == 200 and suspended.get("state") == "suspended" and (suspended.get("suspended") or {}).get("by") == "approver", f"{status} {str(suspended)[:300]}")
        _, listing = operator.call("GET", "/site-entries")
        warnings = ((listing or {}).get("status") or {}).get("warnings") or []
        check("GET /site-entries warns for as long as it lasts", any("suspended" in w and first in w for w in warnings), str(warnings))
        _, health = operator.call("GET", "/health")
        check("and so does the Doctor's report", first in str((health or {}).get("site_entries", {}).get("warnings")), str((health or {}).get("site_entries"))[:300])
        case, why = play("S2", "policy", approve=True)
        check("while it is suspended, S2 resends again", case and case["state"] == "resolved" and case.get("writes") == 1 and case.get("catalogueEntry") == "E2", f"{why} {case and case['state']} {case and case.get('catalogueEntry')}")
        status, resumed = two_people(first, "resume")
        check("resuming takes a proof, a proposal and a second person", status == 200 and (resumed or {}).get("state") == "active", f"{status} {str(resumed)[:300]}")
        case, why = play("S2", "policy")
        check("resumed, the entry stops S2 again", case and case["state"] == "escalated" and case.get("catalogueEntry") == first, f"{why} {case and case['state']}")

        # ---- 6. retirement ----
        status, refused = author.call("POST", f"/site-entries/{first}/propose", {"action": "retire"})
        check("a retirement needs its own proof (409 no_proof)", status == 409 and error_of(refused) == "no_proof", f"{status} {refused}")
        status, retired = two_people(first, "retire")
        check("the entry is retired by two people", status == 200 and (retired or {}).get("state") == "retired", f"{status} {str(retired)[:300]}")
        version = (retired or {}).get("catalogueVersion", "")
        check("the version keeps its suffix, at a higher generation, with no entry", version.startswith(shipped + ";g") and version.endswith(":") and generation_of(version) > activated_at >= 1, f"{version[-30:]} (activated at generation {activated_at})")
        case, why = play("S2", "policy", approve=True)
        check("after the retirement S2 resends again", case and case["state"] == "resolved" and case.get("writes") == 1 and case.get("catalogueEntry") == "E2", f"{why} {case and case['state']}")
        detail = site_entry(first)
        kinds = [e.get("kind") for e in reversed(detail.get("events") or [])]
        check("the entry's events say what was done, in order", [k for k in kinds if k in ("created", "proposed", "approved", "activated", "suspended", "resumed", "retired")][:4] == ["created", "proposed", "approved", "activated"] and kinds[-1] == "retired" and "suspended" in kinds and "resumed" in kinds, str(kinds))
        status, refused = author.call("PUT", f"/site-entries/{first}", dict(body))
        check("a retired entry is not changed again (409 wrong_state)", status == 409 and error_of(refused) == "wrong_state", f"{status} {refused}")
    finally:
        # Whatever happened above, no site entry is left applying to the scenarios that run after this.
        for entry_id in made:
            state = site_entry(entry_id).get("state")
            if state == "active":
                status, _ = approver.call("POST", f"/site-entries/{entry_id}/suspend", {"reason": "site entry check: left active by a failed run"})
                print(f"note: {entry_id} was left active and is suspended now (HTTP {status})")

    print(f"{len(failures)} failed" if failures else "every check passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
