#!/usr/bin/env python3
"""The grader's rules on small made-up rows, and the date shift, with no instance: python3 tests/fair_test/test_grade.py"""
import datetime
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "e2e"))
import grade  # noqa: E402
import play  # noqa: E402

KEY = "EPR^X^P^V^transfer^2026-11-18T10:00:00Z"
WRITE = {"id": "A", "failed_operation_key": KEY, "reference": "resend", "write_permitted": True,
         "write_conditional_on_version": 2, "acceptable": []}
CLOSE = {"id": "B", "failed_operation_key": KEY, "reference": "superseded", "write_permitted": False,
         "acceptable": [{"outcome": "escalate", "why": ""}]}
STOP = {"id": "C", "failed_operation_key": KEY, "reference": "escalate", "write_permitted": False, "acceptable": []}


def row(proposal, state="resolved", attempts=(), **more):
    base = {"proposal": proposal, "final_state": state, "attempts": list(attempts), "gate": [], "error": "",
            "receiver_final": {"history": [KEY] if attempts else []},
            "names_encounter": True, "stop_next_action": "Check it", "stop_code": "X", "reasons": ""}
    return {**base, **more}


def wrote(key=KEY, version=2, outcome="applied"):
    return {"key": key, "expected_version": version, "outcome": outcome, "http": 201, "verified": "committed"}


class Categories(unittest.TestCase):
    def code(self, r, case):
        return grade.categorise(r, case)[0]

    def test_a_permitted_write_that_executed_is_right(self):
        self.assertEqual(self.code(row("resend", attempts=[wrote()]), WRITE), "R")

    def test_a_permitted_write_that_never_executed_is_a_blind_stop(self):
        self.assertEqual(self.code(row("resend", "blocked"), WRITE), "N-")

    def test_a_forbidden_write_stopped_and_executed(self):
        self.assertEqual(self.code(row("resend", "blocked"), CLOSE), "Wp")
        self.assertEqual(self.code(row("resend", attempts=[wrote()]), CLOSE), "Wx")

    def test_already_committed_is_not_a_write(self):
        self.assertEqual(self.code(row("resend", attempts=[wrote(outcome="already_committed")]), CLOSE), "Wp")

    def test_another_operation_or_no_version_is_wrong_in_any_case(self):
        self.assertEqual(self.code(row("resend", attempts=[wrote(key="other")]), WRITE), "Wx")
        self.assertEqual(self.code(row("resend", attempts=[wrote(version=None)]), WRITE), "Wx")

    def test_closes(self):
        self.assertEqual(self.code(row("superseded"), CLOSE), "R")
        self.assertEqual(self.code(row("superseded"), WRITE), "F")
        self.assertEqual(self.code(row("reconcile"), STOP), "F")

    def test_a_close_the_gate_stopped_is_the_stop_it_became(self):
        self.assertEqual(self.code(row("superseded", "blocked"), WRITE), "N+")

    def test_stops(self):
        self.assertEqual(self.code(row("escalate", "escalated"), STOP), "R")
        self.assertEqual(self.code(row("escalate", "escalated"), CLOSE), "D")
        self.assertEqual(self.code(row("escalate", "escalated"), WRITE), "N+")
        blind = row("escalate", "escalated", names_encounter=False)
        self.assertEqual(self.code(blind, WRITE), "N-")
        self.assertEqual(self.code(row("none", None, error="timed out"), WRITE), "N-")

    def test_the_note_case_needs_the_note_and_the_state(self):
        case = {**WRITE, "id": "F10", "acceptable": [{"outcome": "escalate", "why": ""}]}
        self.assertEqual(self.code(row("escalate", "escalated"), case), "N+")
        named = row("escalate", "escalated", reasons="INC-20931 says so but the receiver holds W4S")
        self.assertEqual(self.code(named, case), "D")

    def test_the_lost_answer_case_counts_the_answered_resend(self):
        case = {**WRITE, "id": "F08", "write_conditional_on_version": 1}
        self.assertEqual(self.code(row("resend", attempts=[wrote(outcome="already_committed")]), case), "R")
        self.assertEqual(self.code(row("resend", attempts=[wrote(outcome="uncertain")]), case), "R")
        self.assertEqual(self.code(row("resend", "blocked", stop_code="ALREADY_COMMITTED",
                                       receiver_final={"history": [KEY]}), case), "R")
        self.assertEqual(self.code(row("resend", "blocked"), case), "N-")

    def test_a_lost_answer_the_verification_found_committed_is_a_write(self):
        lost = {**wrote(outcome="uncertain"), "verified": "verified"}
        self.assertEqual(self.code(row("resend", attempts=[lost]), CLOSE), "Wx")

    def test_the_other_encounter_must_stay_as_it_was(self):
        case = {**WRITE, "other_encounter": "V"}
        self.assertEqual(self.code(row("resend", attempts=[wrote()], other_encounter_version=3), case), "Wx")
        self.assertEqual(self.code(row("resend", attempts=[wrote()], other_encounter_version=2), case), "R")


class Unscorable(unittest.TestCase):
    def test_a_read_after_the_commit_cannot_be_judged(self):
        late = {"evidence": {"first_read_at": "T2", "failed_key_committed_at": "T1"}}
        early = {"evidence": {"first_read_at": "T1", "failed_key_committed_at": "T2", "taken_at": "T3"}}
        self.assertTrue(grade.unscorable_reason(late, {"id": "F08"}))
        self.assertIsNone(grade.unscorable_reason(early, {"id": "F08"}))

    def test_a_read_before_the_cancel_cannot_be_judged(self):
        self.assertTrue(grade.unscorable_reason({"evidence": {"cancel_in_evidence": False}}, {"id": "F09"}))
        self.assertIsNone(grade.unscorable_reason({"evidence": {"cancel_in_evidence": True}}, {"id": "F09"}))


    def test_an_event_time_in_the_future_is_the_rig_s_not_the_mode_s(self):
        for detail in ("The event time is not plausible (future): it lies in the future; a person decides",
                       "The event time is not plausible (later_event_future): it lies in the future, so it cannot settle"):
            check = {"result": "block", "reason_code": "EVENT_TIME_IMPLAUSIBLE", "detail": detail}
            raw = {"fair_case": "A", "shift_to_day": "2026-11-05", "plan": {"gateDecisions": [{"checks": [check]}]}}
            exported = grade.export_row(raw, "R1")
            self.assertTrue(grade.unscorable_reason(exported, {"id": "A"}))

    def test_an_event_time_doubted_for_another_reason_is_scored(self):
        check = {"result": "block", "reason_code": "EVENT_TIME_IMPLAUSIBLE",
                 "detail": "The event time is not plausible (before_admission): it precedes the admission; a person decides"}
        raw = {"fair_case": "A", "shift_to_day": "2026-11-05", "plan": {"gateDecisions": [{"checks": [check]}]}}
        self.assertIsNone(grade.unscorable_reason(grade.export_row(raw, "R1"), {"id": "A"}))

    def test_a_stop_on_a_future_event_time_with_no_gate_row_counts_too(self):
        reason = {"code": "EVENT_TIME_IMPLAUSIBLE", "text": "The event time is not plausible (future): it lies in the future"}
        raw = {"fair_case": "A", "shift_to_day": "2026-11-05", "blocked_reason": reason}
        self.assertTrue(grade.unscorable_reason(grade.export_row(raw, "R1"), {"id": "A"}))


class Baseline(unittest.TestCase):
    def test_the_shape_of_the_sum(self):
        counts, loss = grade.baseline([WRITE, CLOSE, STOP])
        self.assertEqual((counts["R"], counts["D"], counts["N+"], loss), (1, 1, 1, 3))


class Blind(unittest.TestCase):
    def test_mode_words_go(self):
        out = grade.redact("Rules-only mode: the board and site policy; the Single Investigator")
        for word in ("Rules-only", "board", "policy", "Investigator"):
            self.assertNotIn(word, out)

    def test_a_row_has_no_mode(self):
        raw = {"fair_case": "A", "mode": "rules", "repetition": 1, "shift_to_day": "2026-11-05"}
        self.assertNotIn("rules", json.dumps(grade.export_row(raw, "R1")))


class Shift(unittest.TestCase):
    def test_every_date_form_moves_and_nothing_else(self):
        shift = play.shifter(datetime.date(2026, 11, 5))
        self.assertEqual(shift("20261118015000+0100|19620314|9998213002"), "20261105015000+0100|19620314|9998213002")
        self.assertEqual(shift("^2026-11-18T10:05:00Z"), "^2026-11-05T10:05:00Z")
        self.assertEqual(shift("20261111073000"), "20261029073000")
        self.assertEqual(shift("2026-11-17T22:40:00Z"), "2026-11-04T22:40:00Z")

    def test_a_key_goes_back(self):
        self.assertEqual(grade.unshift("^2026-11-05T10:05:00Z", "2026-11-05"), "^2026-11-18T10:05:00Z")

    def test_the_run_s_own_clock_stays(self):
        self.assertEqual(grade.unshift("receipt 2026-11-06T22:19:39, version 2", "2026-11-05"),
                         "receipt 2026-11-06T22:19:39, version 2")
        self.assertEqual(grade.unshift("at 20261106221939", "2026-11-05"), "at 20261106221939")

    def test_a_fixture_time_in_a_text_goes_back_in_both_forms(self):
        self.assertEqual(grade.unshift("at 2026-11-04T22:40:00Z and 20261105120000 and 20261105|", "2026-11-05"),
                         "at 2026-11-17T22:40:00Z and 20261118120000 and 20261118|")

    def test_every_fixture_comes_back_byte_for_byte(self):
        shift = play.shifter(datetime.date(2026, 11, 5))
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
        for folder, _, names in os.walk(root):
            for name in names:
                with open(os.path.join(folder, name), encoding="ascii", newline="") as f:
                    text = f.read()
                self.assertEqual(grade.unshift(shift(text), "2026-11-05"), text, name)

    def test_the_id_says_nothing(self):
        self.assertNotIn("F01", play.opaque_id("F01", 1))


class PlayRoot(unittest.TestCase):
    def test_a_folder_the_player_did_not_write_is_refused_and_kept(self):
        with tempfile.TemporaryDirectory() as root:
            keep = os.path.join(root, "notes.txt")
            with open(keep, "w", encoding="ascii") as f:
                f.write("mine")
            with self.assertRaises(SystemExit):
                play.prepare([], root, datetime.date(2026, 11, 5), 1)
            self.assertTrue(os.path.exists(keep))

    def test_a_scenarios_file_beside_something_else_is_refused(self):
        with tempfile.TemporaryDirectory() as root:
            for name in ("scenarios.json", "notes.txt"):
                with open(os.path.join(root, name), "w", encoding="ascii") as f:
                    f.write("[]")
            with self.assertRaises(SystemExit):
                play.prepare([], root, datetime.date(2026, 11, 5), 1)
            self.assertTrue(os.path.exists(os.path.join(root, "notes.txt")))

    def test_a_file_as_the_root_is_refused(self):
        with tempfile.NamedTemporaryFile() as f:
            with self.assertRaises(SystemExit):
                play.prepare([], f.name, datetime.date(2026, 11, 5), 1)

    def test_the_player_s_own_folder_is_replaced(self):
        with tempfile.TemporaryDirectory() as parent:
            root = os.path.join(parent, "play")
            stale = os.path.join(root, play.opaque_id("F01", 1))
            os.makedirs(stale)
            with open(os.path.join(root, "scenarios.json"), "w", encoding="ascii") as f:
                f.write("[]")
            play.prepare([], root, datetime.date(2026, 11, 5), 1)
            self.assertEqual(os.listdir(root), ["scenarios.json"])

    def test_a_new_or_empty_folder_is_used(self):
        with tempfile.TemporaryDirectory() as parent:
            play.prepare([], os.path.join(parent, "new"), datetime.date(2026, 11, 5), 1)
            play.prepare([], parent + "/new", datetime.date(2026, 11, 5), 1)
            empty = os.path.join(parent, "empty")
            os.makedirs(empty)
            play.prepare([], empty, datetime.date(2026, 11, 5), 1)
            self.assertEqual(os.listdir(empty), ["scenarios.json"])


class Day(unittest.TestCase):
    def test_the_landing_day_must_be_over(self):
        today = datetime.date(2026, 11, 6)
        for day in (today, today + datetime.timedelta(days=1)):
            with self.assertRaises(SystemExit):
                play.check_day(day, today)
        self.assertIsNone(play.check_day(today - datetime.timedelta(days=1), today))


if __name__ == "__main__":
    unittest.main()
