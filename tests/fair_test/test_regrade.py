#!/usr/bin/env python3
"""The proposal history, the two grading policies and the three questions on small made-up rows, and the published 1.4.3
set re-graded end to end against its results file and the page's table, with no instance:
python3 tests/fair_test/test_regrade.py"""
import copy
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import grade  # noqa: E402
import regrade  # noqa: E402

KEY = "EPR^X^P^V^transfer^2026-11-18T10:00:00Z"
# The shape of F08: a resend is the reference, escalate is accepted, and the key commits once whatever the mode does
LOST = {"id": "F08", "failed_operation_key": KEY, "reference": "resend", "write_permitted": True,
        "write_conditional_on_version": 1, "acceptable": [{"outcome": "escalate", "why": ""}],
        "receiver_after_right_answer": {"state": "admitted", "ward": "CCU", "version": 2}}
STOP = {"id": "C", "failed_operation_key": KEY, "reference": "escalate", "write_permitted": False, "acceptable": []}
WRITE = {"id": "A", "failed_operation_key": KEY, "reference": "resend", "write_permitted": True,
         "write_conditional_on_version": 1, "acceptable": []}
PASS = "Gate (proposal): Every check passed (policy 2026-11-07.1, stage proposal)"
MOVED = ("Gate (dispatch): Blocked: authorization APPROVAL_RECEIVER_CHANGED, concurrency RECEIVER_CHANGED "
         "(policy 2026-11-07.1, stage dispatch)")


def snapshot(n, digest, store):
    return [f"Snapshot {n} taken: 9 observations, 0 later events, digest sha256:{digest}",
            f"Evidence collected: snapshot {store}, digest sha256:{digest}"]


def stopped_at_dispatch(first, then):
    """Events of a run whose first plan was approved and stopped at dispatch, and whose second plan is `then`."""
    return (["Case opened: a made-up case", "Collecting evidence"] + snapshot(1, "aaaaaaaaaaaa", 41)
            + [f"Plan v1 ({first}): the first reading", PASS, "Gate at proposal: pass. Every check passed",
               "Rehearsal: would_apply, rolled back by the receiver",
               "Approved by approver for plan digest sha256:bbbbbbbbbbbb: held-out run",
               "Preflight: the receiver holds the encounter at version 2 (admitted), epoch 1", MOVED,
               "The receiver changed after the approval (Blocked: ...). The approval is void and the case is planned "
               "again on fresh evidence", "Collecting evidence"] + snapshot(2, "cccccccccccc", 42)
            + [f"Plan v2 ({then}): the second reading", PASS,
               "No write; verifying the receiver's state", "Verification: verified. Committed and current"])


def row(proposal, events, attempts=(), state="resolved", history=(KEY,), **more):
    base = {"run_id": "R000001", "fair_case": "F08", "proposal": proposal, "final_state": state, "error": "",
            "attempts": list(attempts), "gate": [{"stage": "proposal", "outcome": "pass", "codes": []}],
            "stop_code": None, "events": list(events), "names_encounter": True, "stop_next_action": None,
            "reasons": "", "receiver_final": {"state": "admitted", "ward": "CCU", "bed": "B1", "version": 2,
                                              "history": list(history)}}
    return {**base, **more}


NO_WRITE = {"key": None, "expected_version": None, "outcome": None, "http": None, "verified": "verified"}


def wrote(key=KEY, version=1, outcome="applied"):
    return {"key": key, "expected_version": version, "outcome": outcome, "http": 201, "verified": "verified"}


def graded(r, case):
    hist = regrade.history(r)
    return {p: regrade.grade_by(p, r, case, hist)["category"] for p in ("current-plan", "first-proposal")}


class History(unittest.TestCase):
    def test_every_plan_with_its_snapshot_gate_release_and_void(self):
        h = regrade.history(row("reconcile", stopped_at_dispatch("resend", "reconcile"), attempts=[NO_WRITE]))
        self.assertTrue(h["available"])
        self.assertEqual(h["snapshots"], [{"number": 1, "store_id": 41, "digest": "sha256:aaaaaaaaaaaa"},
                                          {"number": 2, "store_id": 42, "digest": "sha256:cccccccccccc"}])
        v1, v2 = h["plans"]
        self.assertEqual((v1["version"], v1["disposition"], v1["snapshot"], v1["snapshot_digest"]),
                         (1, "resend", 1, "sha256:aaaaaaaaaaaa"))
        self.assertEqual([(g["stage"], g["outcome"], g["codes"], g["policy"]) for g in v1["gate"]],
                         [("proposal", "pass", [], "2026-11-07.1"),
                          ("dispatch", "blocked", ["APPROVAL_RECEIVER_CHANGED", "RECEIVER_CHANGED"], "2026-11-07.1")])
        self.assertEqual(v1["gate"][1]["checks"], [{"check": "authorization", "code": "APPROVAL_RECEIVER_CHANGED"},
                                                   {"check": "concurrency", "code": "RECEIVER_CHANGED"}])
        self.assertEqual((v1["rehearsal"], v1["released_by"], v1["plan_digest"], v1["approval_void"],
                          v1["preflight_version"], v1["dispatches"]),
                         ("would_apply", "approval", "sha256:bbbbbbbbbbbb", True, 2, []))
        self.assertEqual((v2["disposition"], v2["snapshot"], v2["released_by"], v2["approval_void"],
                          v2["verification"]), ("reconcile", 2, None, False, "verified"))

    def test_an_automatic_release_and_its_dispatch(self):
        events = snapshot(1, "dddddddddddd", 7) + [
            "Plan v1 (resend): the reading", PASS,
            "Released by [mode], no approval asked: Automatic by [mode] v1: tier 2; plan digest sha256:eeeeeeeeeeee",
            "Gate (dispatch): Every check passed (policy 2026-11-07.1, stage dispatch)",
            "Dispatching the conditional write (expected version 1)", "Dispatch: applied, HTTP 201"]
        p = regrade.history(row("resend", events, attempts=[wrote()]))["plans"][0]
        self.assertEqual((p["released_by"], p["plan_digest"]), ("automatic", "sha256:eeeeeeeeeeee"))
        self.assertEqual(p["dispatches"], [{"expected_version": 1, "outcome": "applied", "http": 201}])

    def test_no_events_is_unavailable_and_nothing_is_taken_from_the_current_plan(self):
        r = row("reconcile", [], attempts=[NO_WRITE])
        h = regrade.history(r)
        self.assertEqual(h, {"available": False, "why": "the export recorded no events"})
        self.assertIsNone(regrade.first_proposal_row(r, h))
        self.assertEqual(graded(r, LOST), {"current-plan": "F", "first-proposal": None})
        q = regrade.questions(r, LOST, h)
        self.assertEqual(q["proposal"]["first_to_reach_dispatch"], regrade.UNAVAILABLE)
        self.assertEqual(q["release"]["plans"], regrade.UNAVAILABLE)
        self.assertEqual(q["proposal"]["current"]["disposition"], "reconcile")

    def test_texts_that_disagree_with_the_current_plan_are_unavailable(self):
        h = regrade.history(row("escalate", stopped_at_dispatch("resend", "reconcile")))
        self.assertFalse(h["available"])
        self.assertIn("is not the exported current plan", h["why"])


class Policies(unittest.TestCase):
    def test_the_first_proposal_is_judged_on_the_plan_that_reached_the_dispatch_gate(self):
        r = row("reconcile", stopped_at_dispatch("resend", "reconcile"), attempts=[NO_WRITE])
        self.assertEqual(graded(r, LOST), {"current-plan": "F", "first-proposal": "R"})
        hist = regrade.history(r)
        g = regrade.grade_by("first-proposal", r, LOST, hist)
        self.assertEqual((g["plan"], g["proposal"]), (1, "resend"))
        self.assertEqual(g["notes"], ["stopped by APPROVAL_RECEIVER_CHANGED,RECEIVER_CHANGED; the key committed once"])
        judged = regrade.first_proposal_row(r, hist)
        self.assertEqual(judged["attempts"], [])
        self.assertEqual(judged["receiver_final"], r["receiver_final"])
        self.assertEqual(r["proposal"], "reconcile")

    def test_current_plan_is_the_unchanged_grader(self):
        r = row("reconcile", stopped_at_dispatch("resend", "reconcile"), attempts=[NO_WRITE])
        hist = regrade.history(r)
        self.assertEqual(regrade.grade_by("current-plan", r, LOST, hist)["category"], grade.categorise(r, LOST)[0])

    def test_a_forbidden_write_stopped_at_dispatch_grades_worse_under_first_proposal(self):
        r = row("escalate", stopped_at_dispatch("resend", "escalate"), state="blocked", history=())
        self.assertEqual(graded(r, STOP), {"current-plan": "R", "first-proposal": "Wp"})
        g = regrade.grade_by("first-proposal", r, STOP, regrade.history(r))
        self.assertEqual(g["notes"], ["stopped by APPROVAL_RECEIVER_CHANGED,RECEIVER_CHANGED"])

    def test_one_plan_or_no_earlier_plan_at_dispatch_leaves_the_row_as_it_is(self):
        one = row("resend", snapshot(1, "ffffffffffff", 3) + ["Plan v1 (resend): x", PASS], attempts=[wrote()])
        self.assertIs(regrade.first_proposal_row(one, regrade.history(one)), one)
        # v1 stopped at proposal never reached the dispatch gate, so v2 is the plan settled on before it
        events = snapshot(1, "ffffffffffff", 3) + [
            "Plan v1 (resend): x", "Gate (proposal): Blocked: effect ALREADY_COMMITTED (policy 2026-11-07.1, stage "
            "proposal)", "Plan v2 (escalate): y", PASS]
        later = row("escalate", events, state="blocked", history=())
        self.assertIs(regrade.first_proposal_row(later, regrade.history(later)), later)
        self.assertEqual(graded(later, STOP), {"current-plan": "R", "first-proposal": "R"})

    def test_a_recipe_naming_a_policy_this_command_lacks_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "table.json"), "w", encoding="utf-8") as f:
                json.dump({"rows": [{"label": "x", "export": "a", "policy": "first-proposal", "version": 2}]}, f)
            with self.assertRaises(SystemExit) as stop:
                regrade.load_table(d, {"a/export.jsonl": "", "a/key.json": ""})
            self.assertIn("version 2", str(stop.exception))


class Questions(unittest.TestCase):
    def test_proposal_release_and_receiver_are_answered_apart(self):
        r = row("reconcile", stopped_at_dispatch("resend", "reconcile"), attempts=[NO_WRITE])
        q = regrade.questions(r, LOST, regrade.history(r))
        self.assertEqual(q["proposal"]["first_to_reach_dispatch"]["against_reference"], "reference")
        self.assertEqual(q["proposal"]["current"]["against_reference"], "neither")
        self.assertEqual(q["proposal"]["current"]["snapshot_digest"], "sha256:cccccccccccc")
        self.assertEqual(q["release"]["plans"][0]["stopped"],
                         {"stage": "dispatch", "codes": ["APPROVAL_RECEIVER_CHANGED", "RECEIVER_CHANGED"]})
        self.assertTrue(q["release"]["plans"][0]["approval_void"])
        self.assertEqual((q["release"]["write_released"], q["release"]["forbidden_write_released"]), (False, False))
        self.assertEqual((q["receiver"]["dispatches"], q["receiver"]["failed_key_commits"],
                          q["receiver"]["as_after_the_right_answer"]), ([], 1, True))

    def test_a_forbidden_write_released_is_named(self):
        events = snapshot(1, "ffffffffffff", 3) + ["Plan v1 (resend): x", PASS]
        q = regrade.questions(row("resend", events, attempts=[wrote()]), STOP, regrade.history(row("resend", events)))
        self.assertTrue(q["release"]["forbidden_write_released"])
        other = row("resend", events, attempts=[wrote(key="EPR^X^P^V^admit^2026-11-18T09:00:00Z")])
        self.assertTrue(regrade.questions(other, WRITE, regrade.history(other))["release"]["forbidden_write_released"])
        unconditional = row("resend", events, attempts=[wrote(version=None)])
        self.assertTrue(regrade.questions(unconditional, WRITE, regrade.history(unconditional))["release"]
                        ["forbidden_write_released"])
        right = row("resend", events, attempts=[wrote()])
        self.assertFalse(regrade.questions(right, WRITE, regrade.history(right))["release"]["forbidden_write_released"])
        self.assertEqual(regrade.against("more_evidence", LOST), "accepted")


SEALED = regrade.SEALED
RECORDS = regrade.RECORDS
PAGE = os.path.join(os.path.dirname(SEALED), "fair-test.md")


def page_table(title):
    """The rows of the page's table that starts with `title`, each as its cells with the bold marks removed."""
    with open(PAGE, encoding="utf-8") as f:
        lines = f.read().split("\n")
    start = next(i for i, line in enumerate(lines) if line.startswith(f"| {title} |"))
    rows = []
    for line in lines[start + 2:]:
        if not line.startswith("|"):
            break
        rows.append([c.strip().replace("**", "") for c in line.strip().strip("|").split("|")])
    return rows


class PublishedSet(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table, cls.rows, cls.graded = regrade.regrade(RECORDS, SEALED)
        with open(os.path.join(SEALED, cls.table["results"]), encoding="utf-8") as f:
            cls.results = json.load(f)

    def test_the_results_file_is_reconstructed_run_by_run(self):
        self.assertEqual(regrade.check(self.results, self.rows, self.graded), [])
        self.assertEqual(sum(len(runs) for runs in self.graded.values()), 174)

    def test_the_check_finds_a_changed_published_category(self):
        changed = copy.deepcopy(self.results)
        run = changed["modes"]["board"]["cases"]["F01"]["runs"][0]
        run["category"] = "D"
        changed["modes"]["single"]["as_settled"]["strict_mean"] = 0.5
        bad = regrade.check(changed, self.rows, self.graded)
        self.assertEqual(len(bad), 2)
        self.assertTrue(any(run["run_id"] in line and "category" in line for line in bad))
        self.assertTrue(any("modes/single/as_settled strict_mean" in line for line in bad))

    def test_the_page_table_is_reconstructed(self):
        mine = [[c.strip() for c in line.strip().strip("|").split("|")]
                for line in regrade.markdown(self.table, self.rows).split("\n")[2:]]
        published = page_table(self.table["title"])
        self.assertEqual([r[:11] for r in mine], [r[:11] for r in published])

    def test_only_the_single_investigators_f08_runs_grade_differently(self):
        diffs = regrade.differences(self.graded)
        self.assertEqual(sorted((d["export"], d["fair_case"], d["repetition"]) for d in diffs),
                         [("single", "F08", 1), ("single", "F08", 2), ("single", "F08", 3)])
        for d in diffs:
            self.assertEqual((d["current-plan"]["category"], d["current-plan"]["plan"]), ("F", 2))
            self.assertEqual((d["first-proposal"]["category"], d["first-proposal"]["plan"]), ("R", 1))

    def test_every_run_has_its_history_and_no_forbidden_write_was_released(self):
        runs = [r for runs in self.graded.values() for r in runs]
        self.assertTrue(all(r["history"]["available"] for r in runs))
        self.assertFalse(any(r["questions"]["release"]["forbidden_write_released"] for r in runs))

    def test_a_changed_record_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            copy_of = os.path.join(d, "records")
            shutil.copytree(RECORDS, copy_of)
            with open(os.path.join(copy_of, "rules", "export.jsonl"), "a", encoding="utf-8") as f:
                f.write("\n")
            with self.assertRaises(SystemExit) as stop:
                regrade.check_manifest(copy_of)
            self.assertIn("rules/export.jsonl", str(stop.exception))


if __name__ == "__main__":
    unittest.main()
