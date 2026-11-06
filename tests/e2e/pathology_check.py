#!/usr/bin/env python3
"""What a laboratory receiver's outage and failures must do, played on a real instance on stock classes, read at the fake receiver.

    python3 tests/e2e/pathology_check.py [--reuse] [--keep] [--port 52796] [--ctr path-check] [--image IMAGE] [--module core]
                                         [--only O1,O4,...] [--smoke] [--expect-v100] [--unlocked]
                                         [--o12-baseline FILE] [--o12-save-baseline FILE] [--o12-scenario-url URL]
    python3 tests/e2e/pathology_check.py --list
    python3 tests/e2e/pathology_check.py --selftest

Written before the feature's design, from what the site wants and what stock IRIS was measured to do. So an assertion here reads
only what no design can move: the bytes at a fake receiver, how many frames it heard and in what order, a queue's depth, a
message header's status, how many headers a message has, and whether something loops. Where a row needs the product's own words
or a button, it goes through pathology_adapter.py, the only file that may be filled in later, and which can't change an assertion
here: this file and the rig are hashed in assertions.sha256 and a run refuses to start if they differ (--unlocked runs anyway and
can then never exit 0).

--smoke sets the instance up, passes one message through to a fake receiver and stops: it plays no row, and says whether the rig
stands. --only takes rows, or an assertion such as O5.d, which plays that assertion's whole row; a name it doesn't know is refused.

Every assertion has one result: ok, FAIL, NOT WIRED (the adapter has no answer yet) or NOT REACHED (the row stopped before it).
Only ok passes, so a row that never got there is no pass.

Exit status: 0 every assertion selected is ok; 1 at least one FAIL; 2 no FAIL but some NOT WIRED or NOT REACHED; 3 the rig itself
failed, in setting up or in any row, or the files were edited. A row whose rig breaks reads NOT REACHED, and the next row still runs. --expect-v100 compares each result with the table for the release before the feature, and exits
0 only on a full match. Needs Docker and no API key: no model is called. Run from the repository's root. Standard library only.
"""
import argparse
import ast
import contextlib
import hashlib
import http.cookiejar
import json
import os
import re
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "pathology_site")
CORPUS = os.path.join(SITE, "corpus")
LOCK = os.path.join(HERE, "assertions.sha256")
PW = "Onboard-2026x"
HOME = "/home/irisowner"
WORK = "/tmp/path_site"
LAB, ADT = "LABSITE", "ADTSITE"
WATCH = 30  # seconds to keep watching that nothing further happens
# How long the rig gives a design for what a design may choose. Generous, so that a debounce or a "stable for 5 minutes" passes.
INCIDENT_WITHIN = 360  # seconds from the first failure to the incident being open
CLOSE_WITHIN = 360  # seconds from the drain to the incident being closed
OFFER_WITHIN = 360  # seconds a design has to show what may go again, or to wrongly offer what may not: its poll may be slow
FINDING_WITHIN = 120  # seconds a design has to write up a finding or close an item once a message has settled
LICENCE_WAIT, LICENCE_POLL = 300, 15  # a Community instance can refuse a terminal session for minutes after a busy spell

sys.path.insert(0, HERE)
import pathology_adapter as adapter  # noqa: E402

E_LATIN1 = b"\xe8"
E_UTF8 = b"\xc3\xa8"
# Not a bare "E8": catalogue entries have names like that.
CHAR_NAMED = r"\u00e8|U\+00E8|\bC3 ?A8\b|0x ?E8\b|\bbyte E8\b|\u00c3\u00a8|\be[- ]grave\b|\be with (?:a |an )?grave\b|\bgrave accent\b"

# A field's name as a page may write it: PID-5, PID.5, OBX[2]-5, "OBX 2 field 5", "the PID segment, field 5".
def field_named(segment, number):
    return segment + r"(?:\W+\w+){0,2}\W+" + str(number) + r"\b"


# The fake receivers, by what each does. Each value is the mode fake_receiver.py reads, and all of them are made up.
RECEIVERS = {
    "down": None,  # nothing listening: the rig just doesn't start one, and a closed port refuses the connection
    "refuses_at_once": {"reset_on_connect": True},  # something listens, and resets each connection before reading a byte
    "never_answers": {"default": "SILENT"},  # takes the frame and never answers
    "takes_it_and_dies": {"default": "SILENT", "die_after": 1},  # takes the frame and dies before answering
    "ae_above_7f": {"ae_nonascii": {"words": "Invalid character in message"}},  # AE on any byte above 0x7F
    "ae_unknown_code": {"ae_unknown_code": {"known": ["HB", "WBC", "PLT", "MCV", "HCT"] + [f"TST0{i}" for i in range(1, 9)], "words": "Test code not recognised: "}},  # AE naming the code
    "refuses_duplicate": {"held": {"controls": [], "words": "ALREADY HELD, entered by hand"}},  # AE in its own words; a row names what it holds
    "refuses_repeat": {"refuses_repeat": {"words": "Message id already received"}},  # AE to a second copy of a control id, in its own words
    "files_duplicate_twice": {},  # AA for every copy: the log's "copy" says which it was
    "ca_then_silence": {"default": "CA"},  # commit accept, and nothing further ever comes
}

# ---- The assertions: id -> (kind, on the release before the feature, what that rests on, what it says) ----
# kind: "independent" reads only the rig; "adapter" goes through pathology_adapter.py.
# before: "hold" should be ok today; "fail" should FAIL today; "not_wired" reads NOT WIRED until the adapter is filled in.
# rests on: "measured" was seen on stock on one build; "read" is from reading the code, not run.
ASSERTIONS = {
    "O1.a": ("independent", "hold", "measured", "A retry-forever outage with 6 orders: the queue holds 5, one header reads Delivered and 5 Queued"),
    "O1.b": ("independent", "hold", "measured", "Over a further 60 s, and again once the wait for the incident ends, every order keeps exactly one header to the operation: nothing sent it again"),
    "O1.c": ("independent", "hold", "read", "No case for that receiver records a write attempt"),
    "O1.d": ("adapter", "fail", "measured", "Exactly one incident is open for the receiver, within 6 minutes of the first failure"),
    "O1.e": ("adapter", "not_wired", "read", "The incident's words say who to call, as the site wrote it"),
    "O2.a": ("independent", "hold", "measured", "The listener returns, slowly: every order reaches it exactly once, in the order sent"),
    "O2.b": ("independent", "hold", "measured", "The queue reads 0, every header Completed, and each order still has one header"),
    "O2.c": ("adapter", "fail", "measured", "The incident closes by itself within 6 minutes of the drain, with no person's action"),
    "O2.d": ("adapter", "fail", "read", "At no reading during the drain did the incident read closed while the queue held anything"),
    "O3.a": ("independent", "hold", "read", "It takes 2 of 6, then goes down again: those 2 arrived in order, the queue holds the rest, none of those Completed"),
    "O3.b": ("adapter", "fail", "read", "Over the next 60 s the same one incident stays open: no false close and no second incident"),
    "O3.c": ("independent", "hold", "read", "It returns: the rest arrive exactly once, in order, queue 0, all headers Completed"),
    "O3.d": ("adapter", "fail", "read", "Only now does the incident close, within 6 minutes of the drain"),
    "O4.a": ("independent", "hold", "measured", "No retry, nothing listening, orders and results of several sizes: all headers Error, the log says the connect failed for each, and no frame arrived"),
    "O4.b": ("independent", "hold", "measured", "The receiver returns and nobody approves: for 30 s no frame arrives and the headers stay Error"),
    "O4.c": ("adapter", "not_wired", "read", "What is offered to go again is exactly those messages, in the order sent"),
    "O4.d": ("adapter", "not_wired", "read", "After one approval each arrives exactly once, in that order"),
    "O5.a": ("independent", "hold", "measured", "The kinds exist: never opened (Error, no frame), read timeout (Error, one frame), AE (Suspended, one frame), CA then silence (Completed, one frame)"),
    "O5.b": ("adapter", "not_wired", "read", "What is offered is exactly the never-opened messages, in order, and at no reading anything else"),
    "O5.c": ("adapter", "not_wired", "read", "After one approval only those arrive, once each, and the read-timeout, AE and CA messages hear nothing further for 30 s"),
    "O5.d": ("adapter", "not_wired", "measured", "With a FailureTimeout above 0, a message the receiver took on its first attempt, whose last attempt says never opened, is not offered, and the never-opened messages beside it are"),
    "O5.e": ("adapter", "not_wired", "measured", "A message whose connection was lost on the read, after the receiver took it, is not offered, and the never-opened messages beside it are"),
    "O6.a": ("independent", "hold", "measured", "5 messages read Error with no frame, in two batches"),
    "O6.b": ("adapter", "not_wired", "read", "One decision, and the receiver answers AE to the third: it hears the first three in order and nothing more for 40 s"),
    "O6.c": ("adapter", "not_wired", "read", "One decision, and the receiver dies after the second: it hears two, the third's failed try is the last one made, it returns, and nothing further arrives for 30 s without a new decision"),
    "O6.d": ("adapter", "not_wired", "measured", "A resend that fails, of a message with an earlier case, is shown as failed with no new case or alert to prompt it, and nothing further goes"),
    "O7.a": ("independent", "hold", "measured", "Stock pass-through: orders and results in Latin-1 and UTF-8, with and without MSH-18, each arrive byte for byte as they came in (not the one with a wrong MSH-18, which stock reads by what MSH-18 says)"),
    "O7.b": ("adapter", "not_wired", "read", "On a resend each frame equals, byte for byte, the bytes that first came in, and the one with a wrong MSH-18 equals what stock sends of it with no resend"),
    "O7.c": ("adapter", "not_wired", "read", "Every stored copy of each message reads the same after the resend as before it"),
    "O8.a": ("independent", "hold", "measured", "A refusing receiver and an unknown one that would file a duplicate twice: all 10 messages read Error, and nothing arrives by itself once each returns"),
    "O8.b": ("adapter", "not_wired", "read", "Refusing receiver, holding the message already: one approval sends it exactly once"),
    "O8.c": ("adapter", "not_wired", "read", "Its refusal closes the item as already delivered, not as a failure"),
    "O8.d": ("adapter", "not_wired", "read", "Unknown receiver: the page offers already handled by hand, and nothing has been sent"),
    "O8.e": ("adapter", "not_wired", "read", "Choosing that sends nothing for 30 s and closes the item as handled by hand"),
    "O9.a": ("independent", "hold", "measured", "A receiver refusing such bytes: each of 7 messages with the character reads Suspended, the plain ones Completed, each with one frame"),
    "O9.b": ("independent", "hold", "measured", "For 30 s nothing repeats, and each frame holds the bytes that came in"),
    "O9.c": ("adapter", "fail", "measured", "Each message's words name every field holding the character (PID-5, ORC-12, OBX-5, NTE-3, as that message has them) and the character"),
    "O9.d": ("adapter", "not_wired", "read", "The page counts the 7 recent failures to that receiver sharing the character"),
    "O9.e": ("adapter", "not_wired", "read", "None of the 7 is offered to go again, at any reading while a design has time to offer it"),
    "O10.a": ("independent", "hold", "measured", "Seven panels refused for an unknown code in one OBX: Suspended, one frame each, no repeat for 30 s; a panel of known codes reads Completed"),
    "O10.b": ("adapter", "hold", "measured", "The words carry the receiver's code for each"),
    "O10.c": ("adapter", "not_wired", "read", "The finding names the right OBX in each panel: set ids 4, 2, 2, 5, 1, 4 and 3, of 3 to 8 OBX, not the first"),
    "O11.a": ("independent", "hold", "read", "Patient not found, demographics mismatch, duplicate order and result, an exact repeat, result before order, no order, older after newer, preliminary after final, cancel after result: Suspended, one frame each, no repeat for 30 s, no write attempt; the accepted ones read Completed"),
    "O11.b": ("adapter", "hold", "read", "Each settles or escalates, with no person needed to get there"),
    "O11.c": ("adapter", "hold", "measured", "Each one's words carry what the receiver said"),
    "O12.a": ("independent", "hold", "read", "scripts/evaluate.py --check is unmoved"),
    "O12.b": ("independent", "hold", "read", "tests/e2e/onboard_check.py passes, with no check of the baseline's missing"),
    "O12.c": ("independent", "hold", "read", "Every scenario as expected on a demo instance (given by --o12-scenario-url; NOT REACHED without it)"),
    "O13.a": ("independent", "hold", "read", "The control: a real ADT failure with a session still opens a case, so the intake is alive"),
    "O13.b": ("independent", "hold", "measured", "A start-up connect alert on an unprofiled ADT host reaches the consumer and opens nothing new"),
    "O13.c": ("independent", "hold", "read", "A session-less alert from an unprofiled host reaches the consumer and opens nothing new"),
    "O13.d": ("independent", "hold", "measured", "QueueCountAlert fires on an ADT operation, reaches the consumer and opens nothing new"),
    "O13.e": ("independent", "hold", "read", "The same start-up and session-less alerts on an unprofiled ADT host in the namespace beside profiled laboratory receivers open nothing new"),
    "O13.f": ("independent", "hold", "read", "The site's consumer fails with its own AlertOnError on: under 50 calls in 30 s, headers not running away, and it settles once it recovers"),
    "O13.g": ("adapter", "hold", "measured", "No incident is open for any of those hosts"),
    "O13.h": ("adapter", "not_wired", "measured", "A QueueWaitAlert on a message still being tried opens nothing new, or says plainly that the engine still holds it; it isn't offered to go again, and it arrives exactly once"),
}
ROWS = {
    "O1": ["O1.a", "O1.b", "O1.c", "O1.d", "O1.e"],
    "O2": ["O2.a", "O2.b", "O2.c", "O2.d"],
    "O3": ["O3.a", "O3.b", "O3.c", "O3.d"],
    "O4": ["O4.a", "O4.b", "O4.c", "O4.d"],
    "O5": ["O5.a", "O5.b", "O5.c", "O5.d", "O5.e"],
    "O6": ["O6.a", "O6.b", "O6.c", "O6.d"],
    "O7": ["O7.a", "O7.b", "O7.c"],
    "O8": ["O8.a", "O8.b", "O8.c", "O8.d", "O8.e"],
    "O9": ["O9.a", "O9.b", "O9.c", "O9.d", "O9.e"],
    "O10": ["O10.a", "O10.b", "O10.c"],
    "O11": ["O11.a", "O11.b", "O11.c"],
    "O12": ["O12.a", "O12.b", "O12.c"],
    "O13": ["O13.a", "O13.b", "O13.c", "O13.d", "O13.e", "O13.f", "O13.g", "O13.h"],
}
OK, FAIL, NOT_WIRED, NOT_REACHED = "ok", "FAIL", "NOT WIRED", "NOT REACHED"
BEFORE = {"hold": OK, "fail": FAIL, "not_wired": NOT_WIRED}
results = {}
rig_faults = []


class RigBroken(Exception):
    """The rig could not set up what a row needs: this says nothing about the product."""


def record(aid, status, detail=""):
    results.setdefault(aid, (status, str(detail)[:1500]))
    # The first result of an assertion stands: nothing later may turn a FAIL into a pass.
    if status == FAIL and results[aid][0] == OK:
        results[aid] = (FAIL, str(detail)[:1500])
    print(f"  {status:<11} {aid}  {ASSERTIONS[aid][3]}" + ("" if status == OK or not detail else f"\n        {str(detail)[:1500]}"), flush=True)


def check(aid, ok, detail=""):
    record(aid, OK if ok else FAIL, "" if ok else detail)


@contextlib.contextmanager
def wired(*aids):
    """Runs a stretch that needs the adapter. If the adapter has no answer, every assertion named reads NOT WIRED, not passed."""
    try:
        yield
    except adapter.NotWired as e:
        for a in aids:
            if a not in results:
                record(a, NOT_WIRED, f"pathology_adapter.{e}")


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


# ---- The pure rules: no instance needed, so --selftest can test them ----

def exactly_once_in_order(heard, sent):
    """(ok, why): the receiver heard each of sent once, in that order, and nothing else."""
    if heard == sent:
        return True, ""
    return False, f"heard {heard}, wanted {sent}"


def verdict(selected):
    """The exit status from the results of the assertions selected."""
    states = [results.get(a, (NOT_REACHED,))[0] for r in selected for a in ROWS[r]]
    if FAIL in states:
        return 1
    if any(s != OK for s in states):
        return 2
    return 0


def against_before(selected):
    """The assertions whose result differs from the table for the release before the feature."""
    out = []
    for r in selected:
        for a in ROWS[r]:
            got = results.get(a, (NOT_REACHED,))[0]
            want = BEFORE[ASSERTIONS[a][1]]
            if got != want:
                out.append((a, want, got))
    return out


FORBIDDEN_NAMES = {"exec", "eval", "compile", "open", "globals", "locals", "vars", "setattr", "getattr", "delattr", "__import__", "pathology_check", "subprocess", "socket", "os", "sys", "builtins", "importlib"}
ALLOWED_IMPORTS = {"json", "re", "urllib.parse"}


def adapter_guard(source):
    """What in the adapter's source breaks its rule: it may translate, not reach round the check."""
    bad = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            bad += [f"import {n.name}" for n in node.names if n.name not in ALLOWED_IMPORTS]
        elif isinstance(node, ast.ImportFrom):
            if node.module not in ALLOWED_IMPORTS:
                bad.append(f"from {node.module} import")
        elif isinstance(node, ast.Name) and node.id in FORBIDDEN_NAMES:
            bad.append(f"name {node.id}")
        elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
            bad.append(f"attribute {node.attr}")
    return bad


def parse_only(text):
    """The rows --only names, in order. O5.d means its row, O5. A name that is neither is an error: selecting nothing would pass."""
    wanted = set()
    for word in text.split(","):
        word = word.strip()
        if not word:
            continue
        name = word[0].upper() + word[1:].lower()
        if name in ROWS:
            wanted.add(name)
        elif name in ASSERTIONS:
            wanted.add(name.split(".")[0])
        else:
            raise ValueError(f"--only names {word}, which is no row or assertion here")
    return [r for r in ROWS if r in wanted]


def locked_files():
    """(path, expected digest) from the lock file."""
    with open(LOCK) as f:
        return [(os.path.join(HERE, line.split(None, 1)[1].strip()), line.split()[0]) for line in f if line.strip()]


def lock_problems():
    if not os.path.exists(LOCK):
        return ["assertions.sha256 is missing"]
    out = []
    for path, want in locked_files():
        try:
            with open(path, "rb") as f:
                if hashlib.sha256(f.read()).hexdigest() != want:
                    out.append(f"{os.path.basename(path)} differs from assertions.sha256")
        except OSError:
            out.append(f"{os.path.basename(path)} is missing")
    return out


def hl7_msg(segs):
    return "\r".join(segs).encode("ascii") + b"\r"


def stamp():
    return time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 120))


def order(control, placer=None):
    now = stamp()
    placer = placer or control
    return hl7_msg([
        f"MSH|^~\\&|LARKSPUR|HOSP|QUILLON|HOSP|{now}||ORM^O01^ORM_O01|{control}|P|2.5.1",
        f"PID|1||MRN{control}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F",
        f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}|||||||||||||||||||||||||{now}",
        f"ORC|NW|{placer}||||||||{now}",
        f"OBR|1|{placer}||FBC^Full blood count^L|||{now}",
    ])


PANEL = [("HB", "Haemoglobin", "132", "g/L"), ("WBC", "White cells", "7.1", "10*9/L"), ("PLT", "Platelets", "250", "10*9/L"), ("MCV", "Mean cell volume", "90", "fL"), ("HCT", "Haematocrit", "0.41", "L/L")]


def result(control, codes=None, status="F", order_code="FBC^Full blood count^L", placer=None, pid5=b"SYNTH^RIG", note=None, msh18=b""):
    """A result as bytes: an ORU with one OBX per panel row, whose codes may be replaced by {position: code}."""
    now = stamp()
    placer = placer or control
    obx = []
    for i, (code, name, val, unit) in enumerate(PANEL, 1):
        code = (codes or {}).get(i, code)
        obx.append(f"OBX|{i}|NM|{code}^{name}^L||{val}|{unit}|||||{status}")
    msh = f"MSH|^~\\&|QUILLON|HOSP|LARKSPUR|HOSP|{now}||ORU^R01^ORU_R01|{control}|P|2.5.1".encode("ascii")
    if msh18:
        msh += b"||||||" + msh18
    head = [f"PID|1||MRN{control}^^^HOSP^MR~9997001001^^^NHS^NH||".encode("ascii") + pid5 + b"||19751120|F"]
    rest = [f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}", f"ORC|RE|{placer}", f"OBR|1|{placer}||{order_code}|||{now}"] + obx
    out = [msh] + head + [r.encode("ascii") for r in rest]
    if note:
        out.append(b"NTE|1||" + note)
    return b"\r".join(out) + b"\r"


def corpus(name, control):
    """A corpus message's bytes with only its control id replaced, so that each row's messages are told apart at the receiver."""
    with open(os.path.join(CORPUS, name + ".hl7"), "rb") as f:
        head, sep, rest = f.read().partition(b"\r")
    fields = head.split(b"|")
    fields[9] = control.encode("ascii")
    return b"|".join(fields) + sep + rest


def adt_a01(control):
    now = stamp()
    return hl7_msg([
        f"MSH|^~\\&|PAS|HOSP|BEDS|HOSP|{now}||ADT^A01^ADT_A01|{control}|P|2.5.1",
        f"EVN|A01|{now}||||{now}",
        f"PID|1||MRN{control}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F",
        f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}",
    ])


# ---- The rig, modelled on onboard_check.py ----

CTR = "path-check"
URL = ""
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
tag = time.strftime("%H%M%S")


def session(ns, code, timeout=400):
    """Runs ObjectScript. A licence refusal exits 133 at once with no output, which no caller could tell from an empty answer, so it waits, then says so."""
    end = time.time() + LICENCE_WAIT
    while True:
        r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
        if r.returncode != 133 and "<LICENSE LIMIT EXCEEDED>" not in (r.stdout or ""):
            return r.stdout
        if time.time() >= end:
            raise RigBroken(f"iris session in {ns} was still refused after {LICENCE_WAIT} s: exit {r.returncode}, {(r.stdout or '')[-300:]} {(r.stderr or '')[-300:]}")
        time.sleep(LICENCE_POLL)


def value(ns, expr, timeout=300):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RigBroken(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr, timeout=300):
    return json.loads(value(ns, expr, timeout))


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method, headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    try:
        with opener.open(req, timeout=60) as r:
            text, code = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        text, code = e.read().decode(), e.code
    try:
        return code, json.loads(text)
    except ValueError:
        return code, text


def sign_in():
    code, _ = api("POST", "/session", {"username": "appr1", "password": PW})
    if code not in (200, 201):
        raise RigBroken(f"the approver could not sign in: {code}")


def read_api(path, allow_404=False):
    """A read the rig relies on. An error must never read as an empty list: 'nothing there' on a dead API would pass a row."""
    code, r = api("GET", path)
    if code == 401:
        sign_in()
        code, r = api("GET", path)
    if allow_404 and code == 404:
        return code, r
    if not 200 <= code < 300:
        raise RigBroken(f"GET {path} answered {code}: {str(r)[:300]}")
    return code, r


def listing(path):
    """The items of a list route. Anything that isn't a list of items is a broken read, not an empty one."""
    _, r = read_api(path)
    items = r if isinstance(r, list) else r.get("items") if isinstance(r, dict) else None
    if not isinstance(items, list):
        raise RigBroken(f"GET {path} gave no list: {str(r)[:300]}")
    return items


class AdapterRig:
    """All the adapter may touch. It counts a person's decisions, so a row can see that one approval really was one."""

    def __init__(self):
        self.decisions = 0
        self.declaring = False

    def get(self, path):
        """(status, body). 404 comes back for the adapter to read; any other error is a broken rig, never an empty answer."""
        return read_api(path, allow_404=True)

    def person_decides(self, method, path, body=None):
        self.decisions += 1
        return api(method, path, body)

    def site_setting(self, method, path, body=None):
        if not self.declaring:
            raise RigBroken("site_setting is for declare_receiver alone")
        return api(method, path, body)

    def control_of_case(self, ns, case_id):
        """The control id of the message behind a case, by the header the case names; empty when it names none."""
        _, c = self.get("/cases/" + str(case_id))
        header = c.get("originHeaderId") if isinstance(c, dict) else None
        if not header:
            return ""
        return value(ns, f'##class(EnsLib.HL7.Message).%OpenId(##class(Ens.MessageHeader).%OpenId("{header}").MessageBodyId).GetValueAt("1:10")')


rig = AdapterRig()


def send(port, data, name):
    """Sends these bytes, unchanged, into a service port; returns the MSA line."""
    path = f"{WORK}/{name}.hl7"
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > {path}"], input=data, check=True)
    r = subprocess.run(["docker", "exec", CTR, "python3", f"{WORK}/mllp_send.py", str(port), path, "20"], capture_output=True, text=True, timeout=60)
    if "MSA|" not in r.stdout:
        raise RigBroken(f"the service on {port} did not take {name}: {r.stdout} {r.stderr}")
    return r.stdout.strip()


def rx_spec(port, spec):
    data = json.dumps(spec).encode()
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > {WORK}/mode-{port}.tmp && mv {WORK}/mode-{port}.tmp {WORK}/mode-{port}"], input=data, check=True)


def rx_up(port, spec=None):
    """Starts a fake receiver on this port, with this behaviour. What it hears is kept across restarts."""
    rx_spec(port, spec or {})
    subprocess.run(["docker", "exec", "-d", CTR, "python3", f"{WORK}/fake_receiver.py", str(port), WORK, "7200"], check=True)
    for _ in range(30):
        if rx_listening(port):
            return
        time.sleep(0.5)
    raise RigBroken(f"the fake receiver on {port} did not start")


def rx_listening(port):
    code = f"import socket;s=socket.socket();s.settimeout(1);print(s.connect_ex(('127.0.0.1',{port})))"
    r = subprocess.run(["docker", "exec", CTR, "python3", "-c", code], capture_output=True, text=True)
    return r.stdout.strip() == "0"


def rx_down(port):
    subprocess.run(["docker", "exec", CTR, "touch", f"{WORK}/stop-{port}"], check=True)
    for _ in range(30):
        if not rx_listening(port):
            return
        time.sleep(0.5)
    raise RigBroken(f"the fake receiver on {port} did not stop")


def frames(port):
    """Everything the receiver on this port has heard, in order."""
    r = subprocess.run(["docker", "exec", CTR, "sh", "-c", f"cat {WORK}/rx-{port}.jsonl 2>/dev/null"], capture_output=True, text=True)
    return [json.loads(line) for line in r.stdout.splitlines() if line.strip()]


def heard(port, controls=None):
    return [f["ctl"] for f in frames(port) if controls is None or f["ctl"] in controls]


def bytes_heard(port, control):
    return [bytes.fromhex(f["hex"]) for f in frames(port) if f["ctl"] == control]


def headers(ns, target):
    """Every header of an HL7 message to this item, oldest first: [(status, control id)]."""
    code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM Ens.MessageHeader WHERE TargetConfigName='{target}' AND MessageBodyClassName='EnsLib.HL7.Message' ORDER BY ID") While rs.%Next() {{ Set h=##class(Ens.MessageHeader).%OpenId(rs.%Get("ID")),m=##class(EnsLib.HL7.Message).%OpenId(h.MessageBodyId) If $ISOBJECT(m) {{ Write !,"<<<",##class(Ens.DataType.MessageStatus).LogicalToDisplay(h.Status),"|",m.GetValueAt("1:10"),">>>",! }} }}"""
    return [tuple(x.split("|", 1)) for x in re.findall(r"<<<(.*?)>>>", session(ns, code))]


def status_of(ns, target, controls):
    """{control: [its headers' statuses]}."""
    out = {c: [] for c in controls}
    for st, c in headers(ns, target):
        if c in out:
            out[c].append(st)
    return out


def queue(ns, item):
    return int(value(ns, f'##class(Ens.Queue).GetCount("{item}")'))


def log_count(ns, item, words):
    code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS N FROM Ens_Util.Log WHERE ConfigName='{item}' AND Text LIKE '%{words}%'") Do rs.%Next() Write !,"<<<",rs.%Get("N"),">>>",!"""
    return last_number(ns, code)


def last_number(ns, code):
    out = session(ns, code)
    found = re.findall(r"<<<(\d+)>>>", out)
    if not found:
        raise RigBroken(f"no number from {ns}: {out[-500:]}")
    return int(found[-1])


def header_total(ns):
    code = """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS N FROM Ens.MessageHeader") Do rs.%Next() Write !,"<<<",rs.%Get("N"),">>>",!"""
    return last_number(ns, code)


def wait_until(pred, seconds=120, every=3):
    end = time.time() + seconds
    while time.time() < end:
        if pred():
            return True
        time.sleep(every)
    return bool(pred())


def wait_status(ns, target, want, seconds=180):
    """Waits until every control's only header reads as wanted, {control: status}; returns what they read."""
    def done():
        now = status_of(ns, target, list(want))
        return all(now[c] == [want[c]] for c in want)
    wait_until(done, seconds)
    return status_of(ns, target, list(want))


def cases_for(ns, receiver):
    return [c for c in listing("/cases?limit=500") if c.get("sourceNamespace") == ns and c.get("receiver") == receiver]


def case_ids(ns):
    return {c.get("caseId") for c in listing("/cases?limit=500") if c.get("sourceNamespace") == ns}


def attempts_for(ns, receiver):
    """The write attempts on every case for this receiver."""
    out = []
    for c in cases_for(ns, receiver):
        out += listing(f"/cases/{c['caseId']}/attempts")
    return out


def alert_log(ns, after=0):
    out = session(ns, f'Set k={after} For {{ Set k=$ORDER(^OraSite.Alerts(k),1,v) Quit:k=""  Write !,"<<<",k,"|",v,">>>",! }}')
    return {int(a.split("|", 1)[0]): a.split("|", 1)[1] for a in re.findall(r"<<<(.*?)>>>", out)}


def alert_count(ns):
    return int(value(ns, "$GET(^OraSite.Alerts)+0"))


def stored_copies(ns, control):
    """A fingerprint of each stored HL7 message with this control id."""
    code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 2000 ID FROM EnsLib_HL7.Message ORDER BY ID DESC") While rs.%Next() {{ Set m=##class(EnsLib.HL7.Message).%OpenId(rs.%Get("ID")) If $ISOBJECT(m),m.GetValueAt("1:10")="{control}" {{ Write !,"<<<",$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHA1Hash(m.OutputToString())),">>>",! }} }}"""
    return re.findall(r"<<<(.*?)>>>", session(ns, code))


def offered_settles(target, want=None, forbidden=(), seconds=OFFER_WITHIN):
    """Reads what the product offers, for up to seconds: a design's poll may be slow, and an offer read too early would pass a
    row by being empty. Stops once it reads as wanted; with want None it watches the whole time. (last reading, every forbidden
    message any reading held). An unwired adapter raises at the first read, so this costs nothing until it is filled in."""
    bad, end = set(), time.time() + seconds
    while True:
        last = adapter.resend_set(rig, LAB, target)
        bad |= set(last) & set(forbidden)
        if (want is not None and last == want) or time.time() >= end:
            return last, sorted(bad)
        time.sleep(5)


def declare(receiver, **facts):
    """Says what a site would write for this receiver. An adapter with no answer leaves it undeclared, and rows say so."""
    if receiver in declared:
        return
    rig.declaring = True
    try:
        adapter.declare_receiver(rig, LAB, receiver, facts)
        declared.add(receiver)
    except adapter.NotWired:
        pass
    finally:
        rig.declaring = False


declared = set()


# ---- The rows ----

ORDERS_IN, ORDERS_OUT, ORDERS_RX = 7501, "Larkspur Out", 7401
WHO = "Larkspur duty desk, 01632 960123"
TODO = "Restart the Larkspur listener from the service console"


def row_outage(selected):
    """O1, O2 and O3 are one story on one operation."""
    step("O1: a retry-forever outage, 6 orders, nothing listening")
    declare(ORDERS_OUT, product="Larkspur Orders", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    rx_down_if_up(ORDERS_RX)
    no_adapter = []

    def incidents_now():
        if no_adapter:
            return []
        try:
            return adapter.open_incidents(rig, LAB, ORDERS_OUT)
        except adapter.NotWired as e:
            no_adapter.append(str(e))
            return []

    def adapter_check(aid, ok, detail=""):
        if no_adapter:
            record(aid, NOT_WIRED, f"pathology_adapter.{no_adapter[0]}")
        else:
            check(aid, ok, detail)

    sent = [f"OUT{tag}{i}" for i in range(1, 7)]
    for c in sent:
        send(ORDERS_IN, order(c), c)
    got = wait_until(lambda: queue(LAB, ORDERS_OUT) == 5, 60)
    st = status_of(LAB, ORDERS_OUT, sent)
    flat = sorted(s for v in st.values() for s in v)
    check("O1.a", got and flat == ["Delivered"] + ["Queued"] * 5, (queue(LAB, ORDERS_OUT), st))
    time.sleep(60)
    st = status_of(LAB, ORDERS_OUT, sent)
    check("O1.b", all(len(v) == 1 for v in st.values()), st)
    check("O1.c", attempts_for(LAB, ORDERS_OUT) == [], attempts_for(LAB, ORDERS_OUT))
    wait_until(lambda: len(incidents_now()) == 1 or no_adapter, INCIDENT_WITHIN - 60)
    st = status_of(LAB, ORDERS_OUT, sent)
    check("O1.b", all(len(v) == 1 for v in st.values()), st)
    incidents = incidents_now()
    adapter_check("O1.d", len(incidents) == 1, incidents)
    if ORDERS_OUT in declared and not no_adapter:
        words = adapter.person_text(rig, LAB, ORDERS_OUT)
        check("O1.e", "01632 960123" in words, words[:600])
    else:
        record("O1.e", NOT_WIRED, "pathology_adapter.declare_receiver")

    step("O2: the listener returns, slowly; all drain by themselves")
    rx_up(ORDERS_RX, {"delay": 2})
    early_close = []
    first = incidents[0] if incidents else None

    def drained():
        n = queue(LAB, ORDERS_OUT)
        if first and n > 0 and adapter.incident_is_closed(rig, LAB, ORDERS_OUT, first):
            early_close.append(n)
        return n == 0 and len(heard(ORDERS_RX, sent)) >= len(sent)

    wait_until(drained, 240, 1)
    time.sleep(5)
    ok, why = exactly_once_in_order(heard(ORDERS_RX, sent), sent)
    check("O2.a", ok, why)
    st = wait_status(LAB, ORDERS_OUT, {c: "Completed" for c in sent}, 60)
    check("O2.b", queue(LAB, ORDERS_OUT) == 0 and all(v == ["Completed"] for v in st.values()), st)
    closed = bool(first) and wait_until(lambda: adapter.incident_is_closed(rig, LAB, ORDERS_OUT, first), CLOSE_WITHIN)
    adapter_check("O2.c", closed and rig.decisions == 0, (first, closed, rig.decisions))
    adapter_check("O2.d", bool(first) and not early_close, ("no incident was ever open" if not first else early_close))

    step("O3: it goes down again during the drain")
    rx_down_if_up(ORDERS_RX)
    again = [f"AGN{tag}{i}" for i in range(1, 7)]
    for c in again:
        send(ORDERS_IN, order(c), c)
    time.sleep(30)
    wait_until(lambda: len(incidents_now()) == 1 or no_adapter, INCIDENT_WITHIN - 30)
    second = incidents_now()
    rx_up(ORDERS_RX, {"die_after": 2})
    wait_until(lambda: not rx_listening(ORDERS_RX), 120, 1)
    time.sleep(10)
    st = status_of(LAB, ORDERS_OUT, again)
    check("O3.a", heard(ORDERS_RX, again) == again[:2] and queue(LAB, ORDERS_OUT) >= 1 and all(st[c] != ["Completed"] for c in again[2:]), (heard(ORDERS_RX, again), queue(LAB, ORDERS_OUT), st))
    held = True
    for _ in range(6):
        time.sleep(10)
        now = incidents_now()
        held = held and len(second) == 1 and now == second
    adapter_check("O3.b", held, (second, incidents_now()))
    rx_up(ORDERS_RX, {})
    wait_until(lambda: queue(LAB, ORDERS_OUT) == 0 and len(heard(ORDERS_RX, again)) >= len(again), 240, 2)
    time.sleep(5)
    ok, why = exactly_once_in_order(heard(ORDERS_RX, again), again)
    st = wait_status(LAB, ORDERS_OUT, {c: "Completed" for c in again}, 60)
    check("O3.c", ok and queue(LAB, ORDERS_OUT) == 0 and all(v == ["Completed"] for v in st.values()), (why, st))
    closed = bool(second) and wait_until(lambda: adapter.incident_is_closed(rig, LAB, ORDERS_OUT, second[0]), CLOSE_WITHIN)
    adapter_check("O3.d", closed, (second, closed))
    rx_down_if_up(ORDERS_RX)


def rx_down_if_up(port):
    if rx_listening(port):
        rx_down(port)


def fail_set(svc, target, messages, seconds=180):
    """Sends these with nothing listening and waits for each to read Error. {control: bytes}."""
    for c, data in messages.items():
        send(svc, data, c)
    return wait_status(LAB, target, {c: "Error" for c in messages}, seconds)


def row_o4(selected):
    step("O4: no retry, nothing listening")
    svc, target, rx = 7504, "Quillon O4 Out", 7404
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    kinds = ["01_orm_plain", "02_oru_3obx_plain", "02_oru_5obx_plain", "02_oru_8obx_plain", "01_orm_plain"]
    sent = [f"N4{tag}{i}" for i in range(1, 6)]
    before = log_count(LAB, target, "ErrOutConnectExpired")
    st = fail_set(svc, target, {c: corpus(k, c) for c, k in zip(sent, kinds)})
    check("O4.a", all(v == ["Error"] for v in st.values()) and log_count(LAB, target, "ErrOutConnectExpired") >= before + len(sent) and heard(rx, sent) == [], st)
    rx_up(rx, {})
    time.sleep(WATCH)
    st = status_of(LAB, target, sent)
    check("O4.b", heard(rx, sent) == [] and all(v == ["Error"] for v in st.values()), (heard(rx, sent), st))
    with wired("O4.c", "O4.d"):
        offered, _ = offered_settles(target, sent)
        check("O4.c", offered == sent, offered)
        n = rig.decisions
        adapter.approve_resend(rig, LAB, target)
        wait_until(lambda: len(heard(rx, sent)) >= len(sent), 120, 2)
        time.sleep(10)
        ok, why = exactly_once_in_order(heard(rx, sent), sent)
        check("O4.d", ok and rig.decisions == n + 1, (why, rig.decisions - n))
    rx_down_if_up(rx)


def row_o5(selected):
    step("O5: a mixed set: never opened, read timeout, AE")
    svc, target, rx = 7505, "Quillon O5 Out", 7405
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    never, timed, refused, confirmed = [f"N5{tag}{i}" for i in range(1, 6)], f"T5{tag}", f"R5{tag}", f"C5{tag}"
    st1 = fail_set(svc, target, {c: result(c) for c in never})
    rx_up(rx, {"by_control": {timed: {"code": "SILENT"}, refused: {"code": "AE", "words": "Refused by the application"}, confirmed: {"code": "CA"}}})
    time.sleep(10)  # The operation connects within about 6 s: the three below are about what the receiver does, not about a connect.
    send(svc, result(timed), timed)
    send(svc, result(refused), refused)
    send(svc, result(confirmed), confirmed)
    st2 = wait_status(LAB, target, {timed: "Error", refused: "Suspended", confirmed: "Completed"}, 180)
    h = heard(rx, never + [timed, refused, confirmed])
    check("O5.a", all(v == ["Error"] for v in st1.values()) and st2[timed] == ["Error"] and st2[refused] == ["Suspended"] and st2[confirmed] == ["Completed"] and h == [timed, refused, confirmed], (st1, st2, h))
    rx_spec(rx, {})
    with wired("O5.b", "O5.c"):
        offered, wrong = offered_settles(target, never, [timed, refused, confirmed])
        check("O5.b", offered == never and not wrong, (offered, wrong))
        n = rig.decisions
        adapter.approve_resend(rig, LAB, target)
        wait_until(lambda: len(heard(rx, never)) >= len(never), 120, 2)
        time.sleep(WATCH)
        ok, why = exactly_once_in_order(heard(rx, never), never)
        others = heard(rx, [timed, refused, confirmed])
        check("O5.c", ok and others == [timed, refused, confirmed] and rig.decisions == n + 1, (why, others, rig.decisions - n))
    rx_down_if_up(rx)
    taken_then_dead("O5.d", 7525, "Quillon O5d Out", 7425, "ErrFailureTimeout%ErrOutConnectExpired")
    taken_then_dead("O5.e", 7535, "Quillon O5e Out", 7435, "ErrOutConnectionLost")


def taken_then_dead(aid, svc, target, rx, words):
    """Four messages that never opened a connection, then one the receiver takes before dying with no answer. Only the four may go.
    The four keep the row honest: offering nothing at all would otherwise pass."""
    step(f"{aid}: the receiver took it and died before answering")
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    mark = aid.replace(".", "").upper()
    never, taken = [f"N{mark}{tag}{i}" for i in range(1, 5)], f"T{mark}{tag}"
    st1 = fail_set(svc, target, {c: result(c) for c in never}, 300)
    before = log_count(LAB, target, words)
    rx_up(rx, RECEIVERS["takes_it_and_dies"])
    time.sleep(10)  # The operation connects within about 6 s, so the message goes on a connection that opens.
    send(svc, result(taken), taken)
    st2 = wait_status(LAB, target, {taken: "Error"}, 120)
    after = log_count(LAB, target, words)
    if not (all(v == ["Error"] for v in st1.values()) and st2[taken] == ["Error"] and heard(rx, [taken]) == [taken] and after > before):
        record(aid, NOT_REACHED, ("the stimulus did not happen", st1, st2, heard(rx, [taken]), before, after))
        rx_down_if_up(rx)
        return
    with wired(aid):
        offered, wrong = offered_settles(target, never, [taken])
        check(aid, offered == never and not wrong, (offered, wrong))
    rx_down_if_up(rx)


def row_o6(selected):
    step("O6: one approval, in order, and it stops at the first failure")
    svc, target, rx = 7506, "Quillon O6 Out", 7406
    svc_b, target_b, rx_b = 7516, "Quillon O6b Out", 7416
    for t in (target, target_b):
        declare(t, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    a = [f"A6{tag}{i}" for i in range(1, 6)]
    b = [f"B6{tag}{i}" for i in range(1, 6)]
    st_a = fail_set(svc, target, {c: result(c) for c in a})
    st_b = fail_set(svc_b, target_b, {c: result(c) for c in b})
    check("O6.a", all(v == ["Error"] for v in list(st_a.values()) + list(st_b.values())) and heard(rx, a) == [] and heard(rx_b, b) == [], (st_a, st_b))
    rx_up(rx, {"by_control": {a[2]: {"code": "AE", "words": "Refused by the application"}}})
    with wired("O6.b"):
        offered_settles(target, a)
        n = rig.decisions
        adapter.approve_resend(rig, LAB, target)
        wait_until(lambda: len(heard(rx, a)) >= 3, 120, 2)
        time.sleep(40)
        check("O6.b", heard(rx, a) == a[:3] and rig.decisions == n + 1, (heard(rx, a), rig.decisions - n))
    rx_up(rx_b, {"die_after": 2})
    with wired("O6.c"):
        offered_settles(target_b, b)
        n = rig.decisions
        adapter.approve_resend(rig, LAB, target_b)
        wait_until(lambda: not rx_listening(rx_b), 120, 2)
        time.sleep(15)
        at_failure = heard(rx_b, b)
        rx_up(rx_b, {})
        time.sleep(WATCH)
        # Dialling on after the third failed reaches nobody, so only the headers can show it. A route with no header can't be caught here; the frames still are.
        st = status_of(LAB, target_b, b[3:])
        check("O6.c", at_failure == b[:2] and heard(rx_b, b) == b[:2] and all(len(v) == 1 for v in st.values()) and rig.decisions == n + 1, (at_failure, heard(rx_b, b), st, rig.decisions - n))
    rx_down_if_up(rx)
    rx_down_if_up(rx_b)

    step("O6.d: a resend fails, on a message that already has a case")
    svc_d, target_d, rx_d = 7526, "Quillon O6d Out", 7426
    declare(target_d, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    d = [f"D6{tag}{i}" for i in range(1, 6)]
    fail_set(svc_d, target_d, {c: result(c) for c in d})
    # The message that will fail its resend must itself hold the earlier case: any other message's case wouldn't make the stimulus.
    if not wait_until(lambda: any(rig.control_of_case(LAB, c["caseId"]) == d[0] for c in cases_for(LAB, target_d)), 90):
        record("O6.d", NOT_REACHED, "no earlier case opened on the first message, so the row's stimulus did not happen")
        return
    rx_up(rx_d, {"by_control": {d[0]: {"code": "AE", "words": "Refused by the application"}}})
    with wired("O6.d"):
        offered_settles(target_d, d)
        adapter.approve_resend(rig, LAB, target_d)
        wait_until(lambda: len(heard(rx_d, d)) >= 1, 120, 2)
        noticed = wait_until(lambda: adapter.resend_failed(rig, LAB, target_d, d[0]), 120)
        time.sleep(WATCH)
        check("O6.d", noticed and heard(rx_d, d) == d[:1], (noticed, heard(rx_d, d)))
    rx_down_if_up(rx_d)


def encodings(control):
    """The same result three ways: the bytes that come in are what must go out."""
    return {
        control + "L": result(control + "L", pid5=b"MOLI" + E_LATIN1 + b"RE^RIG"),
        control + "U": result(control + "U", pid5=b"MOLI" + E_UTF8 + b"RE^RIG"),
        control + "M": result(control + "M", pid5=b"MOLI" + E_UTF8 + b"RE^RIG", msh18=b"UNICODE UTF-8"),
    }


def corpus_encodings(mark):
    """The corpus's orders and results with the character, each encoding it has, and the one whose MSH-18 says the wrong thing."""
    names = ["04_oru_e_grave_utf8_no18", "04_oru_e_grave_latin1_no18", "04_oru_e_grave_utf8_with18", "04_oru_e_grave_latin1_with18", "04_orm_e_grave_utf8_no18",
             "04_orm_e_grave_latin1_no18", "04_orm_e_grave_utf8_with18"]
    out = {f"{mark}K{i}": corpus(n, f"{mark}K{i}") for i, n in enumerate(names, 1)}
    out[mark + "W"] = corpus("04_oru_e_grave_latin1_declares_utf8", mark + "W")
    return out


def row_o7(selected):
    step("O7: the bytes sent equal the bytes that came in")
    rx_c = 7407
    ctl = encodings(f"C7{tag}")
    ctl.update(corpus_encodings(f"C7{tag}"))
    rx_up(rx_c, {})
    for c, data in ctl.items():
        send(7507, data, c)
    wait_until(lambda: len(heard(rx_c, list(ctl))) >= len(ctl), 60, 2)
    # Latin-1 bytes under an MSH-18 saying UTF-8: stock reads them as UTF-8, so what it stores and sends isn't what came in, and that isn't Shutter's to change.
    wrong = f"C7{tag}W"
    same = {c: bytes_heard(rx_c, c) == [data] for c, data in ctl.items() if c != wrong}
    check("O7.a", all(same.values()), same)
    stock_sent = bytes_heard(rx_c, wrong)
    print(f"        a wrong MSH-18: stock sent {len(stock_sent)} frame, {'as it came in' if stock_sent == [ctl[wrong]] else 'changed: ' + repr(stock_sent)[:300]}", flush=True)
    rx_down_if_up(rx_c)
    svc, target, rx = 7517, "Quillon O7 Out", 7417
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    msgs = encodings(f"R7{tag}")
    msgs.update(corpus_encodings(f"R7{tag}"))
    msgs.update({f"R7{tag}P{i}": result(f"R7{tag}P{i}") for i in (1, 2)})
    fail_set(svc, target, msgs, 300)
    if len(stock_sent) != 1:
        raise RigBroken(f"the control heard {len(stock_sent)} frames of the wrong MSH-18 message, so there is nothing to hold its resend to")
    expected = dict(msgs)
    expected[f"R7{tag}W"] = stock_sent[0].replace(wrong.encode("ascii"), f"R7{tag}W".encode("ascii"))
    copies = {c: stored_copies(LAB, c) for c in msgs}
    rx_up(rx, {})
    with wired("O7.b", "O7.c"):
        offered_settles(target, list(msgs))
        adapter.approve_resend(rig, LAB, target)
        wait_until(lambda: len(heard(rx, list(msgs))) >= len(msgs), 120, 2)
        time.sleep(10)
        same = {c: bytes_heard(rx, c) == [expected[c]] for c in msgs}
        check("O7.b", all(same.values()), same)
        after = {c: stored_copies(LAB, c) for c in msgs}
        check("O7.c", all(copies[c] and set(after[c]) == set(copies[c]) for c in msgs), (copies, after))
    rx_down_if_up(rx)


def row_o8(selected):
    step("O8: duplicates, at a receiver that refuses them and at one nobody knows about")
    svc_r, ref, rx_r = 7508, "Larkspur O8 Refuses Out", 7408
    svc_u, unk, rx_u = 7518, "Merrow O8 Unknown Out", 7418
    declare(ref, product="Larkspur Orders", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    declare(unk, product="Merrow Results", category="orders_results", who_to_call="Merrow support desk, 01632 960124", what_to_do="Check Merrow's record first", duplicates="unknown", duplicate_words="")
    c_r, c_u = f"D8R{tag}", f"D8U{tag}"
    # 5 at each, as a design may open an incident only at 5 failures. The one under test goes last, so that the others go ahead of its refusal.
    set_r = [f"E8R{tag}{i}" for i in range(1, 5)] + [c_r]
    set_u = [f"E8U{tag}{i}" for i in range(1, 5)] + [c_u]
    st_r = fail_set(svc_r, ref, {c: result(c) for c in set_r})
    st_u = fail_set(svc_u, unk, {c: result(c) for c in set_u})
    rx_up(rx_r, {"held": {"controls": [c_r], "words": "ALREADY HELD, entered by hand"}})
    rx_up(rx_u, RECEIVERS["files_duplicate_twice"])
    time.sleep(WATCH)
    check("O8.a", all(v == ["Error"] for v in list(st_r.values()) + list(st_u.values())) and heard(rx_r, set_r) == [] and heard(rx_u, set_u) == [], (st_r, st_u, heard(rx_r), heard(rx_u)))
    with wired("O8.b", "O8.c"):
        offered_settles(ref, set_r)
        adapter.approve_resend(rig, LAB, ref)
        wait_until(lambda: len(heard(rx_r, [c_r])) >= 1, 120, 2)
        time.sleep(WATCH)
        check("O8.b", heard(rx_r, [c_r]) == [c_r], heard(rx_r, [c_r]))
        wait_until(lambda: adapter.closure(rig, LAB, ref, c_r) is not None, FINDING_WITHIN)
        got = adapter.closure(rig, LAB, ref, c_r)
        check("O8.c", got == "already_delivered", got)
    with wired("O8.d", "O8.e"):
        wait_until(lambda: adapter.offers_handled_by_hand(rig, LAB, unk, c_u) is True, OFFER_WITHIN, 5)
        check("O8.d", adapter.offers_handled_by_hand(rig, LAB, unk, c_u) is True and heard(rx_u, [c_u]) == [], heard(rx_u, [c_u]))
        adapter.choose_handled_by_hand(rig, LAB, unk, c_u)
        time.sleep(WATCH)
        wait_until(lambda: adapter.closure(rig, LAB, unk, c_u) is not None, FINDING_WITHIN)
        got = adapter.closure(rig, LAB, unk, c_u)
        check("O8.e", heard(rx_u, [c_u]) == [] and got == "handled_by_hand", (heard(rx_u, [c_u]), got))
    rx_down_if_up(rx_r)
    rx_down_if_up(rx_u)


def row_o9(selected):
    step("O9: a special character, named with its field")
    svc, target, rx = 7509, "Quillon O9 Out", 7409
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    rx_up(rx, RECEIVERS["ae_above_7f"])
    pid5, orc12, obx5, nte3 = field_named("PID", 5), field_named("ORC", 12), field_named("OBX", 5), field_named("NTE", 3)
    everywhere = [pid5, orc12, obx5, nte3]
    marked = {
        f"E9{tag}1": (corpus("04_oru_e_grave_latin1_no18", f"E9{tag}1"), everywhere),
        f"E9{tag}2": (corpus("04_oru_e_grave_utf8_with18", f"E9{tag}2"), everywhere),
        f"E9{tag}3": (corpus("04_oru_e_grave_utf8_no18", f"E9{tag}3"), everywhere),
        f"E9{tag}4": (corpus("04_oru_e_grave_latin1_with18", f"E9{tag}4"), everywhere),
        f"E9{tag}5": (corpus("04_orm_e_grave_latin1_no18", f"E9{tag}5"), [pid5, nte3]),
        f"E9{tag}6": (result(f"E9{tag}6", pid5=b"MOLI" + E_UTF8 + b"RE^RIG"), [pid5]),
        f"E9{tag}7": (result(f"E9{tag}7", note=b"Seen by Dr Moli" + E_LATIN1 + b"re"), [nte3]),
    }
    plain, plain2 = f"P9{tag}", f"Q9{tag}"
    for c, (data, _) in marked.items():
        send(svc, data, c)
    send(svc, result(plain), plain)
    send(svc, corpus("04_oru_plain_control", plain2), plain2)
    all_ids = list(marked) + [plain, plain2]
    want = {c: "Suspended" for c in marked}
    want[plain] = want[plain2] = "Completed"
    st = wait_status(LAB, target, want)
    check("O9.a", all(st[c] == [want[c]] for c in want) and sorted(heard(rx, all_ids)) == sorted(all_ids), (st, heard(rx, all_ids)))
    time.sleep(WATCH)
    same = {c: bytes_heard(rx, c) == [d] for c, (d, _) in marked.items()}
    check("O9.b", sorted(heard(rx, all_ids)) == sorted(all_ids) and all(same.values()), (heard(rx, all_ids), same))
    wait_until(lambda: len(cases_for(LAB, target)) >= len(marked), 60)

    def naming():
        texts = {c: adapter.person_text(rig, LAB, target, c) for c in marked}
        return {c: all(re.search(f, texts[c], re.I) for f in marked[c][1]) and bool(re.search(CHAR_NAMED, texts[c], re.I)) for c in marked}

    wait_until(lambda: all(naming().values()), FINDING_WITHIN, 20)
    named = naming()
    check("O9.c", all(named.values()), named)
    with wired("O9.d"):
        counts = {}

        def counted():
            counts.update({c: adapter.shared_character_count(rig, LAB, target, c) for c in marked})
            return all(v == len(marked) for v in counts.values())

        check("O9.d", wait_until(counted, FINDING_WITHIN, 10), counts)
    with wired("O9.e"):
        offered, wrong = offered_settles(target, forbidden=list(marked))
        check("O9.e", not wrong, (offered, wrong))
    rx_down_if_up(rx)


def row_o10(selected):
    step("O10: an unknown test code in a panel names the right OBX")
    svc, target, rx = 7510, "Quillon O10 Out", 7410
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    p4, p2 = f"U10{tag}A", f"U10{tag}B"
    known = f"U10{tag}K"
    # control: (bytes, the code the receiver will name, the OBX set id holding it). The two made-up codes differ, so one case's words can't serve for the other's.
    panels = {
        p4: (result(p4, codes={4: "XQZ9"}), "XQZ9", 4),
        p2: (result(p2, codes={2: "VRT7"}), "VRT7", 2),
        f"U10{tag}C": (corpus("03_oru_3obx_unknown_at_2", f"U10{tag}C"), "ZZUNK", 2),
        f"U10{tag}D": (corpus("03_oru_5obx_unknown_at_5", f"U10{tag}D"), "ZZUNK", 5),
        f"U10{tag}E": (corpus("03_oru_8obx_unknown_at_1", f"U10{tag}E"), "ZZUNK", 1),
        f"U10{tag}F": (corpus("03_oru_6obx_unknown_at_4", f"U10{tag}F"), "ZZUNK", 4),
        f"U10{tag}G": (corpus("06_oru_6obx_unknown_at_3_e_grave_utf8_no18", f"U10{tag}G"), "ZZUNK", 3),
    }
    rx_up(rx, RECEIVERS["ae_unknown_code"])
    for c, (data, _, _) in panels.items():
        send(svc, data, c)
    send(svc, corpus("03_oru_all_known_4obx", known), known)
    want = {c: "Suspended" for c in panels}
    want[known] = "Completed"
    st = wait_status(LAB, target, want)
    time.sleep(WATCH)
    order_sent = list(panels) + [known]
    check("O10.a", all(st[c] == [want[c]] for c in want) and heard(rx, order_sent) == order_sent, (st, heard(rx, order_sent)))
    wait_until(lambda: len(cases_for(LAB, target)) >= len(panels), 60)
    words = {c: panels[c][1] in adapter.person_text(rig, LAB, target, c) for c in panels}
    check("O10.b", all(words.values()), words)
    with wired("O10.c"):
        got = {}

        def named_right():
            got.update({c: adapter.named_obx(rig, LAB, target, c) for c in panels})
            return all(got[c] == [panels[c][2]] for c in panels)

        check("O10.c", wait_until(named_right, FINDING_WITHIN, 10), got)
    rx_down_if_up(rx)


def row_o11(selected):
    step("O11: the other predictable refusals: each settles or escalates, with no write")
    svc, target, rx = 7511, "Quillon O11 Out", 7411
    declare(target, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="unknown", duplicate_words="")
    t = tag
    first_order = f"F11{t}"
    cases = {
        f"NF11{t}": (result(f"NF11{t}"), "Patient not found"),
        f"DM11{t}": (result(f"DM11{t}"), "Demographics mismatch on date of birth"),
        f"DU11{t}": (order(f"DU11{t}", placer=first_order), "Duplicate order number"),
        f"PR11{t}": (result(f"PR11{t}", status="P"), "Preliminary result after a final result"),
        f"CA11{t}": (order(f"CA11{t}", placer=first_order).replace(b"ORC|NW|", b"ORC|CA|"), "Cancel received after the result"),
    }
    # The corpus's sequences, in the order a feed would send them: the receiver takes the first of each and refuses the rest.
    accepted = {f"SA1{t}": corpus("05_seq_a1_order", f"SA1{t}"), f"SB2{t}": corpus("05_seq_b2_order_after", f"SB2{t}"), f"SD1{t}": corpus("05_seq_d1_result_final", f"SD1{t}")}
    refused_seq = {
        f"SA2{t}": (corpus("05_seq_a2_order_duplicate", f"SA2{t}"), "Duplicate order number"),
        f"SA4{t}": (corpus("05_seq_a4_result_duplicate", f"SA4{t}"), "Duplicate result for this order"),
        f"SB1{t}": (corpus("05_seq_b1_result_first", f"SB1{t}"), "Result received before its order"),
        f"SC1{t}": (corpus("05_seq_c1_result_no_order", f"SC1{t}"), "No order held for this result"),
        f"SD2{t}": (corpus("05_seq_d2_result_older_timestamp", f"SD2{t}"), "Older than the result already held"),
    }
    cases.update(refused_seq)
    # The exact repeat has the same control id as what it repeats, so the receiver tells them apart by having heard it.
    repeat = f"SA3{t}"
    repeat_words = RECEIVERS["refuses_repeat"]["refuses_repeat"]["words"]
    rx_up(rx, dict(RECEIVERS["refuses_repeat"], by_control={c: {"code": "AE", "words": w} for c, (_, w) in cases.items()}))
    send(svc, order(first_order), first_order)
    for c, (data, _) in cases.items():
        if c not in refused_seq:
            send(svc, data, c)
    send(svc, accepted[f"SA1{t}"], f"SA1{t}")
    send(svc, refused_seq[f"SA2{t}"][0], f"SA2{t}")
    send(svc, corpus("05_seq_a3_result", repeat), repeat)
    send(svc, refused_seq[f"SA4{t}"][0], f"SA4{t}")
    send(svc, corpus("05_seq_a5_result_identical_ctl", repeat), repeat + "-again")
    send(svc, refused_seq[f"SB1{t}"][0], f"SB1{t}")
    send(svc, accepted[f"SB2{t}"], f"SB2{t}")
    send(svc, refused_seq[f"SC1{t}"][0], f"SC1{t}")
    send(svc, accepted[f"SD1{t}"], f"SD1{t}")
    send(svc, refused_seq[f"SD2{t}"][0], f"SD2{t}")
    want = {c: "Suspended" for c in cases}
    want.update({c: "Completed" for c in accepted})
    st = wait_status(LAB, target, want)
    wait_until(lambda: sorted(status_of(LAB, target, [repeat])[repeat]) == ["Completed", "Suspended"], 60)
    time.sleep(WATCH)
    twice = sorted(status_of(LAB, target, [repeat])[repeat])
    once = list(cases) + list(accepted)
    got = heard(rx, once)
    ok = all(st[c] == [want[c]] for c in want) and twice == ["Completed", "Suspended"] and sorted(got) == sorted(once) and heard(rx, [repeat]) == [repeat, repeat] and attempts_for(LAB, target) == []
    check("O11.a", ok, (st, twice, got, heard(rx, [repeat]), attempts_for(LAB, target)))
    cases[repeat] = (b"", repeat_words)
    wait_until(lambda: len(cases_for(LAB, target)) >= len(cases), 60)
    done = {}
    for c in cases:
        done[c] = wait_until(lambda: adapter.settled(rig, LAB, target, c), 60)
    check("O11.b", all(done.values()), done)
    words = {c: cases[c][1] in adapter.person_text(rig, LAB, target, c) for c in cases}
    check("O11.c", all(words.values()), words)
    rx_down_if_up(rx)


def nothing_new(ns, before, seconds=30):
    """Waits, then the cases that appeared in this namespace since."""
    time.sleep(seconds)
    return case_ids(ns) - before


def fired(ns, after, source, words=""):
    """True when the consumer has been given an alert from this host since entry number after: proof the stimulus happened."""
    return any(a.startswith(source + " |") and words in a for a in alert_log(ns, after).values())


def row_o13(selected):
    step("O13: on ADT hosts with no pathology profile, alerts with no message open nothing, and a failing consumer doesn't loop")
    # The laboratory receivers are declared first where the adapter can do it: the risk is a profile somewhere changing what the intake takes everywhere.
    declare(ORDERS_OUT, product="Larkspur Orders", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    beds, beds_rx = "Beds Out", 7431
    rx_down_if_up(beds_rx)
    control = f"ADT13{tag}"
    before = case_ids(ADT)
    send(7531, adt_a01(control), control)
    opened = wait_until(lambda: any(c.get("receiver") == beds for c in cases_for(ADT, beds)) and bool(case_ids(ADT) - before), 90)
    check("O13.a", opened, case_ids(ADT) - before)
    if not opened:
        return  # With the intake dead, "opens nothing" would mean nothing: the rest read NOT REACHED.
    time.sleep(10)

    n = alert_count(ADT)
    before = case_ids(ADT)
    session(ADT, f'Set sc=##class(Ens.Director).EnableConfigItem("{beds}",0,1)\nSet sc=##class(Ens.Director).EnableConfigItem("{beds}",1,1)')
    happened = wait_until(lambda: fired(ADT, n, beds, "ErrOutConnectExpired"), 60)
    new = nothing_new(ADT, before)
    check("O13.b", happened and not new, ("the start-up alert never fired" if not happened else new))

    n = alert_count(ADT)
    before = case_ids(ADT)
    session(ADT, "Set ^OraSite.Say=1")
    happened = wait_until(lambda: fired(ADT, n, "Ora Say"), 30)
    new = nothing_new(ADT, before)
    check("O13.c", happened and not new, ("the session-less alert never fired" if not happened else new))

    queue_item, queue_rx = "Beds Queue Out", 7432
    rx_down_if_up(queue_rx)
    n = alert_count(ADT)
    before = case_ids(ADT)
    for i in range(1, 5):
        send(7532, adt_a01(f"Q13{tag}{i}"), f"Q13{tag}{i}")
    happened = wait_until(lambda: fired(ADT, n, queue_item, "QueueCountAlert"), 200, 5)
    new = nothing_new(ADT, before)
    check("O13.d", happened and not new, ("QueueCountAlert never fired" if not happened else new))
    rx_up(queue_rx, {})
    wait_until(lambda: queue(ADT, queue_item) == 0, 90)
    rx_down_if_up(queue_rx)

    mixed, mixed_rx = "Beds Mixed Out", 7433
    rx_down_if_up(mixed_rx)
    n = alert_count(LAB)
    before = case_ids(LAB)
    session(LAB, f'Set sc=##class(Ens.Director).EnableConfigItem("{mixed}",0,1)\nSet sc=##class(Ens.Director).EnableConfigItem("{mixed}",1,1)')
    a = wait_until(lambda: fired(LAB, n, mixed, "ErrOutConnectExpired"), 60)
    session(LAB, "Set ^OraSite.Say=1")
    b = wait_until(lambda: fired(LAB, n, "Ora Say"), 30)
    new = nothing_new(LAB, before)
    check("O13.e", a and b and not new, ("start-up fired" if a else "start-up did not fire", "session-less fired" if b else "session-less did not fire", new))

    # The consumer fails. Provoked by a failure and a session-less alert, both of which reach it.
    before_h = header_total(ADT)
    session(ADT, "Set ^OraSite.AlertFail=1")
    n = alert_count(ADT)
    send(7531, adt_a01(f"LOOP13{tag}"), f"LOOP13{tag}")
    session(ADT, "Set ^OraSite.Say=2")
    time.sleep(WATCH)
    calls = alert_count(ADT) - n
    after_h = header_total(ADT)
    session(ADT, "Kill ^OraSite.AlertFail")
    time.sleep(10)
    settled_at = alert_count(ADT)
    time.sleep(10)
    still = alert_count(ADT) - settled_at
    print(f"        the consumer was called {calls} times in {WATCH} s; {after_h - before_h} new headers; {still} calls in the last 10 s")
    check("O13.f", 0 < calls < 50 and after_h - before_h < 300 and still == 0, (calls, after_h - before_h, still))

    with wired("O13.g"):
        open_now = {h: adapter.open_incidents(rig, ns, h) for ns, h in ((ADT, beds), (ADT, queue_item), (LAB, mixed), (ADT, "Ora Say"), (LAB, "Ora Say"))}
        check("O13.g", not any(open_now.values()), open_now)

    step("O13.h: a QueueWaitAlert, whose session is that of a message the engine is still trying")
    waiting, waiting_rx = "Quillon Wait Out", 7434
    declare(waiting, product="Quillon Lab", category="orders_results", who_to_call=WHO, what_to_do=TODO, duplicates="refuses", duplicate_words="ALREADY HELD")
    rx_down_if_up(waiting_rx)
    n = alert_count(LAB)
    held_back = [f"W13{tag}{i}" for i in (1, 2)]
    for c in held_back:
        send(7534, order(c), c)
    if not wait_until(lambda: fired(LAB, n, waiting, "QueueWaitAlert"), 240, 5):
        record("O13.h", NOT_REACHED, "the QueueWaitAlert never fired")
        return
    time.sleep(WATCH)
    print(f"        cases on that receiver while the engine holds both: {len(cases_for(LAB, waiting))}; queue {queue(LAB, waiting)}; headers {status_of(LAB, waiting, held_back)}", flush=True)
    with wired("O13.h"):
        offered, wrong = offered_settles(waiting, forbidden=held_back)
        opened = cases_for(LAB, waiting)
        plain = not opened or all(adapter.says_engine_holds(rig, LAB, waiting, c) for c in held_back)
        rx_up(waiting_rx, {})
        wait_until(lambda: queue(LAB, waiting) == 0 and len(heard(waiting_rx, held_back)) >= len(held_back), 120, 2)
        time.sleep(10)
        ok, why = exactly_once_in_order(heard(waiting_rx, held_back), held_back)
        check("O13.h", plain and not wrong and ok, (opened, offered, wrong, why))
    rx_down_if_up(waiting_rx)


def smoke():
    """The rig stands, or it doesn't: the productions run, the API reads, and one message goes through a fake receiver unchanged."""
    step("Smoke: no row is played")
    problems = []
    for ns, prod in ((LAB, "OraLab.Production"), (ADT, "OraAdt.Production")):
        state = value(ns, '##class(Ens.Director).GetProductionStatus(.n,.s)_n_"|"_s')
        if not state.endswith(f"{prod}|1"):
            problems.append(f"{ns} reads {state}")
    listing("/cases?limit=1")
    read_api("/incidents?limit=1")
    rx, control = 7407, f"SMOKE{tag}"
    data = result(control, pid5=b"MOLI" + E_LATIN1 + b"RE^RIG")
    rx_up(rx, {})
    send(7507, data, control)
    wait_until(lambda: heard(rx, [control]) == [control], 60, 2)
    if bytes_heard(rx, control) != [data]:
        problems.append(f"the receiver heard {bytes_heard(rx, control)}")
    st = wait_status(LAB, "Quillon O7 Control Out", {control: "Completed"}, 60)
    if st[control] != ["Completed"]:
        problems.append(f"its header reads {st}")
    rx_down(rx)
    print("  " + ("the rig stands" if not problems else f"THE RIG DOES NOT STAND: {problems}"), flush=True)
    return problems


def normal_names(text):
    """The names of a run's passing and failing checks, with its durations and times taken out."""
    names = re.findall(r"^\s+(?:ok|FAIL)\s+(.+)$", text, re.M)
    return sorted({re.sub(r"\d+", "N", n) for n in names})


def row_o12(selected, args, root):
    step("O12: with no pathology profile, every existing check is unchanged")
    r = subprocess.run([sys.executable, "scripts/evaluate.py", "--check"], cwd=root, capture_output=True, text=True, timeout=600)
    check("O12.a", r.returncode == 0, r.stdout[-600:] + r.stderr[-300:])
    cmd = [sys.executable, "tests/e2e/onboard_check.py", "--ctr", CTR + "-o12", "--port", str(args.port + 1), "--image", args.image]
    if args.module:
        cmd += ["--module", args.module]
    r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=3000, errors="replace")
    names = normal_names(r.stdout)
    if args.o12_save_baseline:
        with open(args.o12_save_baseline, "w") as f:
            f.write("\n".join(names) + "\n")
    missing = []
    if args.o12_baseline:
        with open(args.o12_baseline) as f:
            missing = sorted(set(f.read().split("\n")) - set(names) - {""})
    check("O12.b", r.returncode == 0 and bool(names) and not missing, (r.returncode, missing[:20], r.stdout[-400:]))
    if not args.o12_scenario_url:
        record("O12.c", NOT_REACHED, "no --o12-scenario-url was given")
        return
    # The way the repository's CI plays them: no model is called, the board's answers are the recorded ones.
    groups = [
        ([], "S1 S2 S3 S4 S5 S6 S7 S8 S9 S10 S13 S15 S16"),
        (["--modes", "board"], "S21 S22 S23a S23b S23c S24 S25"),
        (["--modes", "policy"], "S11 S12 S17 S18 S19 S22 S23a S23b S23c S24 S25"),
        (["--modes", "rules"], "S20"),
        (["--modes", "rules,policy"], "S21"),
    ]
    bad = []
    for extra, ids in groups:
        r = subprocess.run([sys.executable, "tests/e2e/scenario_check.py", "--url", args.o12_scenario_url, "--approve"] + extra + ids.split(), cwd=root, capture_output=True, text=True, timeout=3000)
        if r.returncode:
            bad.append((extra, ids, r.stdout[-500:]))
    check("O12.c", not bad, bad)


# ---- Setting up ----

def setup(args, root):
    global URL
    URL = f"http://127.0.0.1:{args.port}/api/shutter"
    target = f"{HOME}/pkg/{args.module}" if args.module else f"{HOME}/pkg"
    if not args.reuse:
        step("A stock instance, with Shutter installed without the demo, in its own namespace")
        subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
        subprocess.run(["docker", "run", "-d", "--name", CTR, "-p", f"127.0.0.1:{args.port}:52773", args.image, "--check-caps", "false", "--ISCAgent", "false"], check=True, capture_output=True)
        for _ in range(80):
            if b"^running" in subprocess.run(["docker", "exec", CTR, "iris", "qlist", "IRIS"], capture_output=True).stdout:
                break
            time.sleep(3)
        time.sleep(5)
        tar = subprocess.Popen(["tar", "-C", root, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "."], stdout=subprocess.PIPE)
        subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], stdin=tar.stdout, check=True)
        subprocess.run(["docker", "cp", os.path.join(root, "vendor/ipm/zpm-0.10.10.xml"), f"{CTR}:/tmp/zpm.xml"], check=True)
        out = session("USER", f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck") Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("SHUTTER"),"|",!')
        if "ok|" not in out:
            raise RigBroken("Setup.cls did not reach CreateNamespace: " + out[-500:])
        out = session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {target} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 500)
        if "RESULT: ok" not in out:
            raise RigBroken("the load failed: " + out[-800:])
        step("The hospital's namespaces, already running their own productions")
        subprocess.run(["docker", "cp", SITE + "/.", f"{CTR}:{WORK}"], check=True)
        subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", WORK], check=True)
        for ns, prod in ((LAB, "OraLab.Production"), (ADT, "OraAdt.Production")):
            session("SHUTTER", f'Write ##class(Shutter.Setup).CreateNamespace("{ns}")')
            lines = [f'Set sc=$SYSTEM.OBJ.Load("{WORK}/{f}.cls","ck-d") Write !,"[c] ",sc,!' for f in ("OraSite.AlertLog", "OraSite.Say", prod)]
            lines.append(f'Set sc=##class(Ens.Director).StartProduction("{prod}") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
            out = session(ns, "\n".join(lines))
            if "[start] ok" not in out:
                raise RigBroken(f"{ns} did not start {prod}: {out[-600:]}")
        session("SHUTTER", f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("appr1","Shutter_Approver","{PW}","An approver","SHUTTER","","",0,1)
Set $NAMESPACE="SHUTTER"
Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("appr1","An approver")
Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","appr1",1,"Approver")''')
        for ns in (LAB, ADT):
            a = obj("SHUTTER", f'##class(Shutter.Setup).OnboardApply("{ns}","{{}}")')
            if not a.get("ok"):
                raise RigBroken(f"the apply on {ns} failed: {a}")
            c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("{ns}","shutter-fwd","{PW}")')
            if '"ok":true' not in c:
                raise RigBroken(f"the credential on {ns} failed: {c[-300:]}")
    sign_in()


def run_row(name, fn, *extra):
    """Plays a row. Whatever breaks it, the assertions it didn't reach read NOT REACHED with the reason, and the next row runs."""
    why = ""
    try:
        fn(*extra)
    except adapter.NotWired as e:
        print(f"  a row hit an unwired adapter outside a wired stretch: {e}")
        why = f"unwired adapter: {e}"
    except RigBroken as e:
        print(f"  THE RIG FAILED in {name}, which says nothing about the product: {e}", flush=True)
        rig_faults.append((name, str(e)))
        why = f"the rig failed: {e}"
    except Exception:
        why = traceback.format_exc()[-1200:]
        print(f"  {name} stopped on an unexpected error:\n{why}", flush=True)
        rig_faults.append((name, why))
    for a in ROWS[name]:
        if a not in results:
            record(a, NOT_REACHED, why)
    return why


def show_list():
    print("| Assertion | Reads | On the release before the feature | Rests on | Says |\n| --- | --- | --- | --- | --- |")
    for a, (kind, before, basis, text) in ASSERTIONS.items():
        print(f"| {a} | {kind} | {BEFORE[before]} | {basis} | {text} |")


# ---- Tests of the oracle itself, with no instance ----

def raises_value(fn):
    try:
        fn()
    except ValueError:
        return True
    return False


def selftest():
    import tempfile
    import socket
    problems = []

    def expect(what, cond):
        print(("  ok    " if cond else "  FAIL  ") + what)
        if not cond:
            problems.append(what)

    expect("every assertion belongs to a row", sorted(a for r in ROWS.values() for a in r) == sorted(ASSERTIONS))
    expect("every row O1 to O13 is there", list(ROWS) == [f"O{i}" for i in range(1, 14)])
    expect("--only takes rows and an assertion's row, in order", parse_only("O5.d, o1,O5") == ["O1", "O5"] and parse_only("") == [])
    expect("--only refuses what it doesn't know", raises_value(lambda: parse_only("O99")) and raises_value(lambda: parse_only("O5.z")))
    source = open(os.path.abspath(__file__), encoding="utf-8").read()
    for aid in ASSERTIONS:
        used = re.search(r'(check|record|taken_then_dead)\("' + re.escape(aid) + '"', source) or re.search(r'wired\([^)]*"' + re.escape(aid) + '"', source)
        expect(f"{aid} is asserted somewhere", bool(used))
    expect("only ASCII in this file", source.isascii())
    expect("the adapter keeps its rule", adapter_guard(open(os.path.join(HERE, "pathology_adapter.py"), encoding="utf-8").read()) == [])
    expect("the guard catches an import", bool(adapter_guard("import os\n")))
    expect("the guard catches a reach into the check", bool(adapter_guard("import pathology_check\n")) and bool(adapter_guard("x = pathology_check\n")))
    expect("the guard catches eval and a dunder", bool(adapter_guard("eval('1')\n")) and bool(adapter_guard("x = y.__dict__\n")))
    expect("the lock matches", lock_problems() == [])

    expect("order and once: the same list passes", exactly_once_in_order(["a", "b"], ["a", "b"])[0])
    expect("order and once: a duplicate fails", not exactly_once_in_order(["a", "a", "b"], ["a", "b"])[0])
    expect("order and once: swapped fails", not exactly_once_in_order(["b", "a"], ["a", "b"])[0])
    expect("order and once: one missing fails", not exactly_once_in_order(["a"], ["a", "b"])[0])

    real_adapter_set = adapter.resend_set
    readings = [["a"], ["a", "x"], ["a", "b"]]
    adapter.resend_set = lambda r, n, t: readings.pop(0)
    expect("an offer is read until it's right, and a wrong reading on the way is kept", offered_settles("T", ["a", "b"], ["x"], 60) == (["a", "b"], ["x"]))
    adapter.resend_set = lambda r, n, t: []
    expect("with nothing wanted the offer is watched to the end, and empty is what it says", offered_settles("T", None, ["x"], 0) == ([], []))
    adapter.resend_set = real_adapter_set

    saved = dict(results)
    results.clear()
    for a in ROWS["O5"]:
        results[a] = (OK, "")
    expect("all ok exits 0", verdict(["O5"]) == 0)
    expect("a row that never ran is no pass", verdict(["O5", "O6"]) == 2)
    results["O5.b"] = (NOT_WIRED, "")
    expect("not wired is no pass", verdict(["O5"]) == 2)
    results["O5.c"] = (FAIL, "")
    expect("a FAIL exits 1", verdict(["O5"]) == 1)
    results.clear()
    for a in ROWS["O1"]:
        results[a] = (BEFORE[ASSERTIONS[a][1]], "")
    expect("the table matches itself", against_before(["O1"]) == [])
    results["O1.d"] = (OK, "")
    expect("a row passing that should fail is a mismatch", against_before(["O1"]) == [("O1.d", FAIL, OK)])
    results.clear()
    record("O5.a", OK)
    record("O5.a", FAIL, "later")
    expect("a later FAIL replaces an ok", results["O5.a"][0] == FAIL)
    record("O5.a", OK)
    expect("a later ok doesn't undo a FAIL", results["O5.a"][0] == FAIL)
    results.clear()
    results.update(saved)

    # What a dead API, a refused session or a broken row must read as.
    def raises(kind, fn):
        try:
            fn()
        except kind:
            return True
        except Exception:
            return False
        return False

    real_api, real_run, real_wait, real_poll = api, subprocess.run, LICENCE_WAIT, LICENCE_POLL
    g = globals()
    for code in (401, 403, 500):
        g["api"] = lambda method, path, body=None, c=code: (c, {"error": "refused"})
        expect(f"a {code} is a broken rig, not no cases", raises(RigBroken, lambda: cases_for("N", "R")) and raises(RigBroken, lambda: case_ids("N")))
        expect(f"a {code} is a broken rig for the adapter too", raises(RigBroken, lambda: rig.get("/incidents?limit=500")))
    g["api"] = lambda method, path, body=None: (200, "<LICENSE LIMIT EXCEEDED>")
    expect("a 200 with no list is a broken read", raises(RigBroken, lambda: case_ids("N")))
    g["api"] = lambda method, path, body=None: (404, {"error": "no route"})
    expect("a 404 reaches the adapter, to read as NotWired", rig.get("/incidents")[0] == 404)
    g["api"] = lambda method, path, body=None: (200, {"items": [{"caseId": "C1", "sourceNamespace": "N", "receiver": "R"}]})
    expect("a good list still reads", case_ids("N") == {"C1"} and [c["caseId"] for c in cases_for("N", "R")] == ["C1"])
    g["api"] = real_api

    class Done:
        def __init__(self, returncode, stdout):
            self.returncode, self.stdout, self.stderr = returncode, stdout, ""

    answers = [Done(133, ""), Done(0, "<LICENSE LIMIT EXCEEDED>"), Done(0, "<<<7>>>")]
    g["LICENCE_WAIT"], g["LICENCE_POLL"] = 5, 0.01
    subprocess.run = lambda *a, **k: answers.pop(0)
    expect("a licence refusal is retried until it answers", last_number("N", "x") == 7)
    subprocess.run = lambda *a, **k: Done(133, "")
    g["LICENCE_WAIT"] = 0
    expect("a licence refusal that lasts is a broken rig", raises(RigBroken, lambda: session("N", "x")))
    subprocess.run = lambda *a, **k: Done(0, "no number here")
    expect("no number is a broken rig, not an IndexError", raises(RigBroken, lambda: header_total("N")))
    subprocess.run, g["LICENCE_WAIT"], g["LICENCE_POLL"] = real_run, real_wait, real_poll

    saved_rows, saved_faults = dict(results), list(rig_faults)
    results.clear()
    rig_faults.clear()

    def half_row():
        record("O5.a", OK)
        [][1]

    def rig_row():
        raise RigBroken("no instance")

    run_row("O5", half_row)
    expect("a crash in a row keeps what it got, and the rest read NOT REACHED", results["O5.a"][0] == OK and results["O5.b"][0] == NOT_REACHED and "IndexError" in results["O5.b"][1])
    run_row("O6", rig_row)
    expect("a broken rig in a row reads NOT REACHED, and is recorded for exit 3", results["O6.a"][0] == NOT_REACHED and len(rig_faults) == 2)
    results.clear()
    results.update(saved_rows)
    rig_faults[:] = saved_faults

    expect("O7's three encodings hold the bytes", b"\xe8" in encodings("X")["XL"] and b"\xc3\xa8" in encodings("X")["XU"] and b"|P|2.5.1||||||UNICODE UTF-8\r" in encodings("X")["XM"])
    panel = result("Z1", codes={4: "XQZ9"}).split(b"\r")
    expect("a panel has its unknown code at OBX 4", [s for s in panel if s.startswith(b"OBX|4|")][0].startswith(b"OBX|4|NM|XQZ9^"))
    expect("a panel has 5 OBX", len([s for s in panel if s.startswith(b"OBX|")]) == 5)
    expect("control id is MSH-10", panel[0].split(b"|")[9] == b"Z1")
    expect("order's control and placer", order("Z2", placer="P9").split(b"\r")[0].split(b"|")[9] == b"Z2" and b"ORC|NW|P9|" in order("Z2", placer="P9"))
    expect("MSH-18 lands in field 18", result("Z3", msh18=b"UNICODE UTF-8").split(b"\r")[0].split(b"|")[17] == b"UNICODE UTF-8")
    expect("a corpus message changes only its control id", corpus("05_seq_a3_result", "C0503") == open(os.path.join(CORPUS, "05_seq_a3_result.hl7"), "rb").read() and corpus("04_oru_e_grave_latin1_no18", "ZZ1").split(b"\r")[0].split(b"|")[9] == b"ZZ1" and b"\xe8" in corpus("04_oru_e_grave_latin1_no18", "ZZ1"))
    expect("the corpus's exact repeat is one message", corpus("05_seq_a3_result", "Z") == corpus("05_seq_a5_result_identical_ctl", "Z"))
    expect("the corpus has its unknown code where its name says", [s for s in corpus("03_oru_5obx_unknown_at_5", "Z").split(b"\r") if b"ZZUNK" in s][0].startswith(b"OBX|5|") and [s for s in corpus("06_oru_6obx_unknown_at_3_e_grave_utf8_no18", "Z").split(b"\r") if b"ZZUNK" in s][0].startswith(b"OBX|3|"))
    for way in ("PID-5", "PID.5", "PID 5", "PID segment, field 5", "the PID-5 field"):
        expect(f"a field's name reads {way}", bool(re.search(field_named("PID", 5), way)))
    expect("a field's name reads a repeating segment", bool(re.search(field_named("OBX", 5), "in OBX[2]-5")) and bool(re.search(field_named("OBX", 5), "OBX 2 field 5")))
    expect("a field's name doesn't read another field", not re.search(field_named("PID", 5), "PID-3 and PID-55"))
    expect("names read from a run, digits taken out", normal_names("  ok    the load finishes in 12 s\n  FAIL  x\n        detail\n") == ["the load finishes in N s", "x"])
    expect("a field regex reads PID-5", bool(re.search(r"PID\W{0,3}5\b", "the character is in PID-5")))
    expect("the character regex reads the char itself, its bytes and its name", all(re.search(CHAR_NAMED, t, re.I) for t in ("\u00e8", "U+00E8", "bytes C3 A8", "byte E8", "e with a grave accent", "an e-grave")))
    expect("the character regex doesn't read 'grave' as a plain word", not re.search(CHAR_NAMED, "a grave error in the message", re.I))
    expect("the character regex doesn't read plain words or a catalogue entry", not re.search(CHAR_NAMED, "the message was refused, Catalogue E8", re.I))

    with tempfile.TemporaryDirectory() as work:
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        sock.close()
        mode = os.path.join(work, f"mode-{port}")

        def set_mode(m):
            with open(mode, "w") as f:
                json.dump(m, f)

        def start():
            p = subprocess.Popen([sys.executable, os.path.join(SITE, "fake_receiver.py"), str(port), work, "30"])
            for _ in range(50):
                with socket.socket() as t:
                    if t.connect_ex(("127.0.0.1", port)) == 0:
                        return p
                time.sleep(0.1)
            return p

        def talk(data, wait=0.6):
            with socket.create_connection(("127.0.0.1", port), timeout=3) as s:
                s.sendall(b"\x0b" + data + b"\x1c\r")
                s.settimeout(wait)
                try:
                    reply = s.recv(4096)
                except OSError:
                    return ""
            seg = [x for x in reply.strip(b"\x0b\x1c\r").split(b"\r") if x.startswith(b"MSA")]
            return seg[0].decode("latin-1") if seg else ""

        def log():
            with open(os.path.join(work, f"rx-{port}.jsonl")) as f:
                return [json.loads(x) for x in f]

        set_mode({})
        p = start()
        plain = result("R1")
        expect("receiver: plain answers AA", talk(plain).startswith("MSA|AA|R1"))
        expect("receiver: logs the exact bytes", bytes.fromhex(log()[-1]["hex"]) == plain)
        set_mode({"ae_nonascii": {"words": "Bad"}})
        latin = result("R2", pid5=b"MOLI\xe8RE^X")
        expect("receiver: a high byte gets AE with words", talk(latin) == "MSA|AE|R2|Bad")
        expect("receiver: high bytes kept in the log", bytes.fromhex(log()[-1]["hex"]) == latin)
        expect("receiver: plain still AA in that mode", talk(result("R3")).startswith("MSA|AA|R3"))
        set_mode({"by_control": {"R4": {"code": "SILENT"}, "R5": {"code": "AE", "words": "No"}}})
        expect("receiver: SILENT gives nothing", talk(result("R4")) == "")
        expect("receiver: by_control answers", talk(result("R5")) == "MSA|AE|R5|No")
        expect("receiver: logged silent frame", any(x["ctl"] == "R4" and x["answer"] == "SILENT" for x in log()))
        set_mode({"held": {"controls": ["R6"], "words": "ALREADY HELD"}})
        expect("receiver: held refuses", talk(result("R6")) == "MSA|AE|R6|ALREADY HELD")
        expect("receiver: others pass", talk(result("R7")).startswith("MSA|AA|R7"))
        set_mode(RECEIVERS["ca_then_silence"])
        with socket.create_connection(("127.0.0.1", port), timeout=3) as s:
            s.sendall(b"\x0b" + result("R20") + b"\x1c\r")
            s.settimeout(1.0)
            first = s.recv(4096)
            try:
                further = s.recv(4096)
            except OSError:
                further = b""
        expect("receiver: CA, then nothing further", b"MSA|CA|R20" in first and further == b"")
        set_mode(RECEIVERS["ae_unknown_code"])
        expect("receiver: AE names the unknown code, not the first OBX", talk(result("R21", codes={4: "XQZ9"})) == "MSA|AE|R21|Test code not recognised: XQZ9")
        expect("receiver: a known panel passes that mode", talk(result("R22")).startswith("MSA|AA|R22"))
        set_mode(RECEIVERS["files_duplicate_twice"])
        twice = result("R23")
        expect("receiver: AA for the first copy and the second", talk(twice).startswith("MSA|AA|R23") and talk(twice).startswith("MSA|AA|R23"))
        expect("receiver: the log says which copy each was", [x["copy"] for x in log() if x["ctl"] == "R23"] == [1, 2])
        set_mode(RECEIVERS["refuses_repeat"])
        expect("receiver: a first copy is taken, a repeat refused in its words", talk(result("R25")).startswith("MSA|AA|R25") and talk(result("R25")) == "MSA|AE|R25|Message id already received")
        set_mode(RECEIVERS["refuses_at_once"])
        count = len(log())
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=3) as s:
                s.settimeout(1.0)
                time.sleep(0.3)
                s.sendall(b"\x0b" + result("R24") + b"\x1c\r")
                refused_by = s.recv(4096)
        except OSError:
            refused_by = b""
        time.sleep(0.3)
        expect("receiver: resets the connection, hearing no frame and answering nothing", refused_by == b"" and len(log()) == count)
        set_mode({})
        count = len(log())
        with socket.create_connection(("127.0.0.1", port), timeout=3):
            pass
        time.sleep(0.3)
        expect("receiver: a bare probe is no frame", len(log()) == count)
        open(os.path.join(work, f"stop-{port}"), "w").close()
        p.wait(timeout=5)
        set_mode({"die_after": 2})
        p = start()
        talk(result("R8"))
        talk(result("R9"))
        time.sleep(0.5)
        expect("receiver: dies after two", p.poll() is not None)
        with socket.socket() as t:
            expect("receiver: the port is closed after dying", t.connect_ex(("127.0.0.1", port)) != 0)
        set_mode({"default": "SILENT", "die_after": 1})
        p = start()
        expect("receiver: takes the frame and dies with no answer", talk(result("R10"), 1.0) == "" and log()[-1]["ctl"] == "R10" and log()[-1]["answer"] == "SILENT")
        time.sleep(0.5)
        expect("receiver: gone after that", p.poll() is not None)
        expect("receiver: keeps its log across restarts", [x["ctl"] for x in log()][-3:] == ["R8", "R9", "R10"] and log()[0]["ctl"] == "R1")
    print(f"\n{'selftest failed: ' + str(len(problems)) if problems else 'selftest passed'}")
    return 1 if problems else 0


def main():
    global CTR
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--port", type=int, default=52796)
    ap.add_argument("--ctr", default="path-check")
    ap.add_argument("--image", default="irishealth-community:2027.1.0AI.109.0")
    ap.add_argument("--module", default="")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(HERE)), help="the repository's root, when this file isn't in it")
    ap.add_argument("--only", default="", help="rows, comma-separated, or an assertion, which plays its row; O1, O2 and O3 always run together")
    ap.add_argument("--smoke", action="store_true", help="set the instance up, pass one message through, and stop")
    ap.add_argument("--expect-v100", action="store_true")
    ap.add_argument("--unlocked", action="store_true")
    ap.add_argument("--o12-baseline", default="")
    ap.add_argument("--o12-save-baseline", default="")
    ap.add_argument("--o12-scenario-url", default="")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.list:
        show_list()
        return 0
    if args.selftest:
        return selftest()
    CTR = args.ctr
    edited = lock_problems()
    for line in edited:
        print("EDITED:", line, flush=True)
    if edited and not args.unlocked:
        print("The assertions may not change. Refusing to run; --unlocked runs anyway and can never exit 0.")
        return 3
    bad = adapter_guard(open(os.path.join(HERE, "pathology_adapter.py"), encoding="utf-8").read())
    if bad:
        print("The adapter breaks its rule:", bad)
        return 3
    try:
        wanted = parse_only(args.only)
    except ValueError as e:
        print(e)
        return 3
    selected = [r for r in ROWS if not wanted or r in wanted]
    if set(selected) & {"O1", "O2", "O3"}:
        selected = sorted(set(selected) | {"O1", "O2", "O3"}, key=list(ROWS).index)
    plays = [("O1", row_outage), ("O4", row_o4), ("O5", row_o5), ("O6", row_o6), ("O7", row_o7), ("O8", row_o8), ("O9", row_o9), ("O10", row_o10), ("O11", row_o11), ("O13", row_o13)]
    try:
        if args.smoke:
            setup(args, args.repo)
            return 3 if smoke() else 0
        if any(name in selected for name, _ in plays):
            setup(args, args.repo)
        for name, fn in plays:
            if name in selected:
                why = run_row(name, fn, selected)
                if name == "O1":
                    for later in ("O2", "O3"):
                        for a in ROWS[later]:
                            if a not in results:
                                record(a, NOT_REACHED, why)
    except RigBroken as e:
        print(f"\nTHE RIG FAILED in setting up, which says nothing about the product: {e}")
        return 3
    finally:
        if not args.keep and not args.reuse:
            subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
    if "O12" in selected:
        run_row("O12", row_o12, selected, args, args.repo)
    step("Results")
    counts = {}
    for r in selected:
        for a in ROWS[r]:
            st = results.get(a, (NOT_REACHED,))[0]
            counts[st] = counts.get(st, 0) + 1
            if st != OK:
                print(f"  {st:<11} {a}  {ASSERTIONS[a][3]}")
    print(counts)
    for name, why in rig_faults:
        print(f"  RIG FAULT in {name}, which says nothing about the product: {why}")
    if args.expect_v100:
        diff = against_before(selected)
        for a, want, got in diff:
            print(f"  UNEXPECTED {a}: wanted {want} on the release before the feature, got {got}")
        print("matches the table" if not diff else f"{len(diff)} differ from the table")
        return 3 if edited or rig_faults else (1 if diff else 0)
    code = verdict(selected)
    return 3 if edited or rig_faults else code


if __name__ == "__main__":
    sys.exit(main())
