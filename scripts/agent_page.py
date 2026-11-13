#!/usr/bin/env python3
"""Writes docs/readme/s8-what-the-agents-saw.md from S8's public recordings, with no model call: what one board member was
sent and did, in full, and how the others answered. scripts/evaluate.py writes and checks it with the evaluation.

    python3 scripts/agent_page.py [--check]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORDS = os.path.join(ROOT, "fixtures", "records")
OUT = os.path.join(ROOT, "docs", "readme", "s8-what-the-agents-saw.md")
BLOB = "https://github.com/MxSalata/shutter/blob/main/fixtures/records/"
STEM = "scenario-S8-ENC-1008-transfer-{}-1.json"
NAMES = {"conformance": "Conformance", "encounter": "Encounter Integrity", "impact": "Impact", "coordinator": "Coordinator"}
# Why "every check passed" is true of that resend, as src/Shutter/Operation/Gate.cls has it: Rules only in a scenario the
# runner plays is the baseline, kept to show what a plain resend does, so the gate leaves out ENTRY_NOT_NAMED_WRITE there.
EXEMPTION = (
    "That resend passes every check only because the check that would stop it is left out on purpose. Rules only in a "
    "scenario the runner plays is the baseline, kept to show what a plain resend does, so the gate does not apply "
    "`ENTRY_NOT_NAMED_WRITE` there. Any other write, a real case or a live story in that mode included, must name the "
    "catalogue entry it follows, and the entry S8's evidence matches calls for no resend: on a real case the gate holds it."
)


def load(member):
    with open(os.path.join(RECORDS, STEM.format(member)), encoding="utf-8") as f:
        record = json.load(f)
    transcript = record["transcript"]
    record["transcript"] = json.loads(transcript) if isinstance(transcript, str) else transcript
    return record


def pretty(text):
    """A tool's arguments or result as indented JSON, or as it came when it isn't JSON."""
    try:
        return json.dumps(json.loads(text), indent=2, ensure_ascii=False)
    except (TypeError, ValueError):
        return str(text)


def fenced(text, kind="json"):
    return f"```{kind}\n{text}\n```"


def folded(summary, text, kind="json"):
    return f"<details>\n<summary>{summary}</summary>\n\n{fenced(text, kind)}\n\n</details>"


def evidence_of(request):
    """The evidence block of a request: the text before it, its parsed JSON, and the text after it."""
    found = re.search(r"<evidence-[^>]*>\s*(.*?)\s*</evidence-[^>]*>", request, re.S)
    if not found:
        raise SystemExit("no evidence block in the request")
    return request[: found.start()].strip(), json.loads(found.group(1))


def page():
    records = {member: load(member) for member in NAMES}
    record = records["encounter"]
    response = record["response"]
    transcript = record["transcript"]
    messages = transcript["messages"]
    question, evidence = evidence_of(messages[0]["content"])
    matches = evidence["evidence"]["catalogue"]["matches"]
    entry = next(m for m in matches if m.get("preferred", {}).get("outcome") == "escalate")
    case = evidence["case_id"]
    plan = records["coordinator"]["response"]["result"]

    w = []
    w.append("# What an S8 agent was sent and did")
    w.append("")
    w.append(
        f"One board member's whole run on S8, the case in the README where a plain resend would write over the bed "
        f"manager's ward with every check passed: **{NAMES['encounter']}**, recorded live on {record['recordedAt'][:10]} as case {case} with "
        f"`{record['model']}`. It took {response['duration_ms'] / 1000:.1f} seconds, {response['prompt_tokens']:,} tokens in "
        f"and {response['completion_tokens']:,} out, and {response['tool_calls']} tool calls."
    )
    w.append("")
    w.append(EXEMPTION)
    w.append("")
    w.append(
        f"`scripts/agent_page.py` writes this page from the public file [{STEM.format('encounter')}]({BLOB}{STEM.format('encounter')}). "
        "No model was called to make it, and `scripts/evaluate.py --check` fails if the two differ. The patients are made up, "
        "and the encounter and patient appear as tokens (`ENC-T1`, `MRN-T1`), as the model received them."
    )
    w.append("")
    w.append("**Two things to read it with:**")
    w.append("")
    w.append(
        f"- **The agent is given the catalogue's advice.** Its evidence includes the matching entry, {entry['id']}, and that "
        "entry's preferred outcome, escalate. This run applies written policy to the evidence; it doesn't reach the answer "
        "unaided. Another member, Conformance, read the same evidence and proposed a resend, and its dissent was kept."
    )
    w.append(
        "- **This is what it read and called, not its reasoning.** The agents wrote almost nothing between tool calls, and the "
        "token counts are for the whole run, not for each call."
    )
    w.append("")
    w.append("## Its instructions")
    w.append("")
    w.append(folded("The rules every board member is given", transcript["base_system_prompt"], "text"))
    w.append("")
    w.append("## Its request")
    w.append("")
    w.append(question)
    w.append("")
    w.append("The catalogue's entry, as it appears in the evidence:")
    w.append("")
    w.append(fenced(json.dumps(entry, indent=2, ensure_ascii=False)))
    w.append("")
    w.append(folded("The whole evidence block", json.dumps(evidence, indent=2, ensure_ascii=False)))
    w.append("")
    w.append("## What it did")
    w.append("")
    results = [m for m in messages if m.get("role") == "tool"]
    calls = [c for m in messages if m.get("role") == "assistant" for c in (m.get("tool_calls") or [])]
    for index, call in enumerate(calls):
        name = call["name"]
        if name == "SubmitFindings":
            continue
        result = results[index]["content"] if index < len(results) else ""
        w.append(f"**{index + 1}. `{name}`**")
        w.append("")
        w.append(fenced(pretty(call["arguments"])))
        w.append("")
        if name == "GetWardState":
            w.append("What the receiver holds now: the bed manager's WARD-C at version 2, with the same event time as the failed message.")
            w.append("")
            w.append(fenced(pretty(result)))
        else:
            w.append(folded("The result", pretty(result)))
        w.append("")
    w.append("## What it submitted")
    w.append("")
    w.append(fenced(json.dumps(response["result"], indent=2, ensure_ascii=False)))
    w.append("")
    w.append("And its last message:")
    w.append("")
    w.append(f"> {messages[-1]['content']}")
    w.append("")
    w.append("## The whole board on this case")
    w.append("")
    w.append("| Member | Answer | Confidence | Started | Seconds | Recording |")
    w.append("| --- | --- | --- | --- | --- | --- |")
    for member, name in NAMES.items():
        r = records[member]["response"]
        confidence = r["result"].get("confidence", "")
        file = STEM.format(member)
        w.append(
            f"| {name} | {r['result']['disposition']} | {confidence} | {r['started_at'][11:19]} | "
            f"{r['duration_ms'] / 1000:.1f} | [file]({BLOB}{file}) |"
        )
    w.append("")
    w.append(
        f"The coordinator's plan: **{plan['disposition']}**, citing catalogue entry {plan.get('catalogue_entry', entry['id'])}, "
        "and nothing was written. A person decides."
    )
    w.append("")
    return "\n".join(w)


def write_or_check(check):
    """Writes the page, or with check says whether the file on disk is current. Returns True when it is."""
    text = page()
    if check:
        try:
            with open(OUT, encoding="utf-8") as f:
                return f.read() == text
        except OSError:
            return False
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="say whether the page is current; write nothing")
    args = parser.parse_args()
    ok = write_or_check(args.check)
    print(f"{os.path.relpath(OUT, ROOT)} {'is current' if ok else 'is out of date'}" if args.check else f"wrote {os.path.relpath(OUT, ROOT)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
