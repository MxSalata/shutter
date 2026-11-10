#!/usr/bin/env python3
"""The live hospital as the sign-in page reads it: the anonymous health route's live, with the public demo's hardening.

    python3 tests/e2e/live_public_check.py --url http://127.0.0.1:PORT --ctr NAME [--save health.json]

Runs against a CI-style install with the demo hospital (Shutter in SHUTTER, the hospital in HOSPITAL). It switches the
live hospital on (Hospital.Setup.SetLive), waits for the player's first round, and reads GET /health with no session: live
must be {enabled: true, every_minutes} and nothing else of the player. Then it leaves UnknownUser with no roles, as the
public demo's hardening does (the stock image already gives it none), and checks the same answer comes from the public
copy in Shutter's namespace (^Shutter.Live("public")): with the player off and the copy stale the answer has no live key,
which shows the hospital can't be read by that caller; the switch off reads as off at once; on again, the player's rounds
keep the copy current; signed in as demo (made for the check with the role Shutter_Demo when the install has no such
login) the answer is the same. UnknownUser's roles, the demo login and the live switch are put back as they were. --save
writes the last anonymous answer, for the web's sign-in line. It needs Docker and no API key. Exit status 1 when a check
fails.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--url", required=True)
ap.add_argument("--ctr", required=True)
ap.add_argument("--shutter-ns", default="SHUTTER")
ap.add_argument("--hospital-ns", default="HOSPITAL")
ap.add_argument("--save", default="")
args = ap.parse_args()
API = args.url.rstrip("/") + "/api/shutter"
SNS, HNS = args.shutter_ns, args.hospital_ns
failed = []
passed = 0


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def session(ns, code, timeout=300):
    r = subprocess.run(["docker", "exec", "-i", args.ctr, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
    return r.stdout


def value(ns, expr):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def health(user=None, password="shutter"):
    req = urllib.request.Request(API + "/health", headers={"Accept": "application/json"})
    if user:
        req.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def copy():
    text = value(SNS, '$GET(^Shutter.Live("public"))')
    return json.loads(text) if text else None


def wait_for(test, seconds=90, every=3):
    end = time.time() + seconds
    last = None
    while time.time() < end:
        last = test()
        if last:
            return last
        time.sleep(every)
    return last


def roles(user):
    return value("%SYS", f'$SELECT(##class(Security.Users).Get("{user}",.p):$GET(p("Roles")),1:"<none>")')


def set_roles(user, list_):
    code = f'Kill p Set p("Roles")="{list_}" Set sc=##class(Security.Users).Modify("{user}",.p) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!'
    return session("%SYS", code)


def ensure_demo():
    """The public demo's login demo (role Shutter_Demo), made for the check when the install has none (a CI install makes
    it only when SHUTTER_PUBLIC_DEMO_PASSWORD is set); returns whether it was made, so that it is removed afterwards."""
    if value("%SYS", '##class(Security.Users).Exists("demo")') == "1":
        return False
    out = session("%SYS", f'Set sc=##class(Security.Users).Create("demo","Shutter_Demo","shutter","Shutter public demo (live_public_check)","{SNS}","","",0,1) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
    check("the demo login made for the check (role Shutter_Demo)", "<<<ok>>>" in out, out[-400:])
    return True


def live_of(h):
    return h.get("live") if isinstance(h, dict) else None


def two(h):
    """The live hospital's switch and cadence from an answer: the anonymous one carries only these, a signed-in caller
    who holds Shutter_Operate (the demo login does) gets the full report with the player's whole status."""
    live = live_of(h)
    return {k: live[k] for k in ("enabled", "every_minutes") if k in live} if isinstance(live, dict) else None


was_live = value(HNS, '+$GET(^Hospital.Config("live"))')
was_roles = roles("UnknownUser")
made_demo = ensure_demo()
print(f"live switch was {was_live}; UnknownUser's roles were '{was_roles}'")
last = None
try:
    step("1. The live hospital on, as the public demo runs it")
    out = value(HNS, "##class(Hospital.Setup).SetLive(1)")
    check("SetLive(1) in the hospital's namespace", out.startswith("ok"), out)
    st = wait_for(lambda: value(HNS, '$GET(^Hospital.Live("status"))'), 120)
    check("the player wrote its status", bool(st), st)
    c = copy()
    check("and the public copy in Shutter's namespace: enabled true, every_minutes, at", bool(c) and c.get("enabled") is True and isinstance(c.get("every_minutes"), int) and isinstance(c.get("at"), int) and set(c) == {"enabled", "every_minutes", "at"}, c)

    step(f"2. The anonymous answer on an install as CI makes it (UnknownUser's roles as the image has them: '{was_roles}')")
    h = health()
    last = h
    print("  anonymous health:", json.dumps(h))
    check("live is {enabled: true, every_minutes}", live_of(h) == {"enabled": True, "every_minutes": c.get("every_minutes") if c else 7}, h)

    step("3. UnknownUser with no roles, as the public demo hardens it")
    out = set_roles("UnknownUser", "")
    check("UnknownUser's roles taken away", "<<<ok>>>" in out, out[-600:])
    check("UnknownUser now holds no role", roles("UnknownUser") == "", roles("UnknownUser"))
    h = health()
    last = h
    print("  anonymous health:", json.dumps(h))
    check("the anonymous answer still says the live hospital is on, with its cadence", live_of(h) == {"enabled": True, "every_minutes": c.get("every_minutes") if c else 7}, h)
    check("and nothing else of the player", set((live_of(h) or {}).keys()) == {"enabled", "every_minutes"}, h)
    check("the rest of the anonymous answer as before (ok, demo)", h.get("ok") is True and h.get("demo") is True, h)

    step("4. Where it comes from: the player off and the copy stale")
    out = value(HNS, "##class(Hospital.Setup).SetLive(0)")
    check("SetLive(0)", out.startswith("ok"), out)
    c = copy()
    check("the switch off reaches the copy at once", bool(c) and c.get("enabled") is False, c)
    h = health()
    check("the anonymous answer reads off at once", live_of(h) == {"enabled": False, "every_minutes": c.get("every_minutes") if c else 7}, h)
    time.sleep(6)
    session(SNS, 'Set o={}.%FromJSON(^Shutter.Live("public")) Set o.at=o.at-(4*7*60) Set ^Shutter.Live("public")=o.%ToJSON()')
    stale_at = (copy() or {}).get("at")
    h = health()
    print("  anonymous health:", json.dumps(h))
    check("a stale copy and a hospital this caller can't read: no live key", "live" not in h, h)
    d = health("demo")
    check("signed in as demo, the hospital is read: live enabled false", two(d) == {"enabled": False, "every_minutes": c.get("every_minutes") if c else 7}, d)
    check("and the stale copy keeps its time (a reader never renews it)", (copy() or {}).get("at") == stale_at, copy())

    step("5. On again: the switch writes the copy, the player's rounds keep it current")
    out = value(HNS, "##class(Hospital.Setup).SetLive(1)")
    check("SetLive(1)", out.startswith("ok"), out)
    c1 = copy()
    check("the copy says on at once", bool(c1) and c1.get("enabled") is True, c1)
    time.sleep(12)
    c2 = copy()
    check("the player's rounds renew its time", bool(c2) and c2.get("at", 0) > c1.get("at", 0), [c1, c2])
    h = health()
    last = h
    print("  anonymous health:", json.dumps(h))
    check("anonymous: {enabled: true, every_minutes}", live_of(h) == {"enabled": True, "every_minutes": c2.get("every_minutes") if c2 else 7}, h)
    d = health("demo")
    print("  signed in as demo, live:", json.dumps(live_of(d)))
    check("signed in as demo: the same switch and cadence", two(d) == live_of(h), live_of(d))
finally:
    step("6. Put back as it was")
    out = set_roles("UnknownUser", was_roles)
    check(f"UnknownUser's roles back ('{was_roles}')", "<<<ok>>>" in out and roles("UnknownUser") == was_roles, out[-400:])
    out = value(HNS, f"##class(Hospital.Setup).SetLive({was_live})")
    check(f"the live switch back to {was_live}", out.startswith("ok"), out)
    if made_demo:
        out = session("%SYS", 'Set sc=##class(Security.Users).Delete("demo") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
        check("the demo login made for the check removed", "<<<ok>>>" in out, out[-400:])

if args.save and last is not None:
    with open(args.save, "w") as f:
        json.dump(last, f)
print(f"\n{passed} ok, {len(failed)} failed")
for name in failed:
    print("  FAILED:", name)
sys.exit(1 if failed else 0)
