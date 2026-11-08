#!/usr/bin/env python3
"""The proof's own verdicts with no instance and no Docker: which reading carried the head, readings by minute, the card's word,
the AlertProcess line a trace came from, and which of two messages a receiver heard first. Run anywhere:
python3 tests/e2e/v11_proof/a/test_proof_a.py. Exit status 1 when one fails."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import proof_a as p  # noqa: E402

failed = []


def check(name, ok, detail=""):
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {detail}"), flush=True)
    if not ok:
        failed.append(name)


HEADS = [
    # stuck, status, oldest Delivered, ActiveMessage, expected
    ("41", "Retry", "41", "41", ["oldest Delivered header", "ActiveMessage", "Status (Retry)"]),
    ("41", "Retry", "41", "", ["oldest Delivered header", "Status (Retry)"]),
    ("41", "Error", "", "41", ["ActiveMessage"]),
    ("41", "Retry", "39", "", []),
    ("41", "Retry", "", "", []),
    ("", "Retry", "", "", []),
    ("41", "OK", "41", "", ["oldest Delivered header"]),
]
for stuck, status, oldest, active, want in HEADS:
    got = p.head_carriers(stuck, status, oldest, active)
    check(f"head_carriers({stuck!r}, {status!r}, {oldest!r}, {active!r})", got == want, got)

check("per_minute groups by minute", p.per_minute([(0, "a"), (59, "b"), (60, "a"), (119.9, "a")]) == {0: ["a", "b"], 1: ["a"]}, p.per_minute([(0, "a"), (59, "b"), (60, "a"), (119.9, "a")]))
check("per_minute of nothing", p.per_minute([]) == {})
check("card_word is the last reading", p.card_word(["down", "cant_tell"]) == "cant_tell")
check("card_word with no reading says so", p.card_word([]) == "no reading")

SOURCE = '''Method X()
{
    If session = "" {
        $$$TRACE("Alert from " _ source _ " carries no session: nothing to hand to Shutter")
        Quit $$$OK
    }
    If ..Seen(session, source) {
        $$$TRACE("Alert from " _ source _ " for session " _ session _ ": this failure was handed to Shutter already")
    }
    $$$TRACE("Not an alert (" _ $SELECT($ISOBJECT(request): $CLASSNAME(request), 1: "nothing") _ "): ignored")
}'''
check("a session-less trace finds its line", p.trace_line(SOURCE, "Alert from NoRetry Out carries no session: nothing to hand to Shutter") == 4)
check("a seen trace finds its line", p.trace_line(SOURCE, "Alert from Retry Out for session 812: this failure was handed to Shutter already") == 8)
check("a trace of other words finds none", p.trace_line(SOURCE, "Shutter opened or found case C-000001") == 0)
check("a quoted quote is matched as one", p.trace_line('    $$$TRACE("say ""no"" here")', 'say "no" here') == 1)

check("first_order: a first", p.first_order(["x", "a", "b"], "a", "b") == "a")
check("first_order: b first", p.first_order(["b", "a"], "a", "b") == "b")
check("first_order: only b heard", p.first_order(["b"], "a", "b") == "b")
check("first_order: only a heard", p.first_order(["a"], "a", "b") == "a")
check("first_order: neither", p.first_order(["c"], "a", "b") == "")

print(f"\n{'all ok' if not failed else str(len(failed)) + ' failed'}", flush=True)
sys.exit(1 if failed else 0)
