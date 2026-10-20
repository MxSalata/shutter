#!/usr/bin/env python3
"""Checks the roles of Shutter's REST API over HTTP against docs/CONTRACTS.md, section 5.

    python3 tests/e2e/roles_check.py [--url http://localhost:52773] [--timeout 60]

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter") and checks
that GET /me names each one's roles; that changing the agent library (PATCH /library/{code}) is refused to the
operator (403) and allowed to the approver (200), and the item is then put back as it was; that the operator drafts
and sends an escalation, and the case's timeline names who sent it and the digest of the text sent; that closing a
case by hand (POST /cases/{id}/close) is the operator's by default, with who, when and the reason on the case's record;
and that with the site profile's approvers.close_needs_approver on, the operator is refused (403) and the approver
closes the case. The profile is put back with the answers it had, saved from the API: from then on a change of the
seed file no longer replaces it, as for any profile a person saved.

It closes two cases that are escalated, blocked or failed, the newest first, so run it after the scenarios (CI runs it
after them), and not on an instance someone else is using. Exit status 1 when a check fails. Standard library only.
"""
import argparse
import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid


class Session:
    """One signed-in user of the REST API: a cookie jar and JSON in and out."""

    def __init__(self, url):
        self.base = url.rstrip("/") + "/api/shutter"
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, idempotent=False):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Shutter")
        if idempotent:
            request.add_header("Idempotency-Key", str(uuid.uuid4()))
        try:
            with self.opener.open(request, timeout=60) as response:
                text = response.read().decode()
                return response.status, (json.loads(text) if text else None)
        except urllib.error.HTTPError as error:
            text = error.read().decode()
            try:
                return error.code, json.loads(text) if text else None
            except json.JSONDecodeError:
                return error.code, {"unparsed": text[:200]}

    def sign_in(self, user, password):
        status, body = self.call("POST", "/session", {"username": user, "password": password})
        if status != 200:
            raise SystemExit(f"sign-in as {user} failed: HTTP {status} {body}")
        return self


def wait(check, timeout, every=1):
    """Calls check() until it returns something truthy, or returns None after timeout seconds."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(every)
    return None


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--timeout", type=int, default=60, help="seconds to wait for a case to close or an email to go")
    args = p.parse_args()

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    failures = []
    checks = [0]

    def check(name, condition, detail=""):
        checks[0] += 1
        print(("ok   " if condition else "FAIL ") + name + ("" if condition else f"  ({detail})"), flush=True)
        if not condition:
            failures.append(name)
        return condition

    def error_of(body):
        return (body or {}).get("error")

    # ---- who is who ----
    status, body = Session(args.url).call("GET", "/me")
    check("GET /me signed out: 401", status == 401, status)
    status, body = operator.call("GET", "/me")
    check("operator: GET /me says operator, not approver",
          status == 200 and body.get("operator") is True and body.get("approver") is False, f"{status} {body}")
    status, body = approver.call("GET", "/me")
    check("approver: GET /me says operator and approver",
          status == 200 and body.get("operator") is True and body.get("approver") is True, f"{status} {body}")

    # ---- the agent library: an approver's change ----
    status, library = approver.call("GET", "/library")
    if not check("GET /library: 200 with members", status == 200 and isinstance(library, list) and library, f"{status} {library}"):
        library = []
    if library:
        member = library[0]
        code, sort = member["code"], member.get("sort", 0)
        kept = {k: member.get(k) for k in ("enabled", "inDefaultBoard", "sort")}

        def current():
            _, items = approver.call("GET", "/library")
            return next((m for m in items or [] if m.get("code") == code), {})

        status, body = operator.call("PATCH", f"/library/{code}", {"sort": sort + 1})
        check(f"operator: PATCH /library/{code} is 403 forbidden", status == 403 and error_of(body) == "forbidden", f"{status} {body}")
        check("and the library is unchanged", {k: current().get(k) for k in kept} == kept, current())
        status, body = approver.call("PATCH", f"/library/{code}", {"sort": sort + 1})
        check(f"approver: PATCH /library/{code}: 200 with the change", status == 200 and (body or {}).get("sort") == sort + 1, f"{status} {body}")
        status, body = approver.call("PATCH", f"/library/{code}", {"sort": sort})
        check("approver: the item put back: 200", status == 200 and (body or {}).get("sort") == sort, f"{status} {body}")
        check("and the library is as it was", {k: current().get(k) for k in kept} == kept, current())

    status, view = approver.call("GET", "/site-profile")
    if not check("GET /site-profile: 200", status == 200 and isinstance((view or {}).get("profile"), dict), f"{status} {view}"):
        print(f"{len(failures)} of {checks[0]} failed")
        return 1
    saved = {k: v for k, v in view["profile"].items() if k != "version"}
    status, body = operator.call("PUT", "/site-profile", {**saved, "expectedVersion": view["version"]})
    check("operator: PUT /site-profile is 403 forbidden", status == 403 and error_of(body) == "forbidden", f"{status} {body}")

    def put_profile(profile):
        _, now = approver.call("GET", "/site-profile")
        return approver.call("PUT", "/site-profile", {**profile, "expectedVersion": (now or {}).get("version")})

    # ---- closing by hand: two closable cases ----
    closable = []
    for state in ("escalated", "blocked", "failed"):
        _, listing = operator.call("GET", f"/cases?state={state}&limit=50")
        closable += [(c["caseId"], c) for c in (listing or {}).get("items", [])]
    closable.sort(key=lambda x: x[0], reverse=True)
    if not check("two cases that are escalated, blocked or failed (run the scenarios first)", len(closable) >= 2, f"{len(closable)} found"):
        print(f"{len(failures)} of {checks[0]} failed")
        return 1
    (first, _), (second, _) = closable[0], closable[1]
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    def case(caseid):
        return operator.call("GET", f"/cases/{caseid}")[1] or {}

    def last_state_event(caseid):
        _, events = operator.call("GET", f"/cases/{caseid}/events")
        states = [e for e in events or [] if e.get("kind") == "state"]
        return states[-1] if states else {}

    def close(session, caseid, reason):
        return session.call("POST", f"/cases/{caseid}/close", {"reason": reason, "expectedVersion": case(caseid).get("version")}, idempotent=True)

    def closed_by_hand(caseid):
        c = case(caseid)
        return c if c.get("state") == "resolved" and c.get("disposition") == "handled_by_hand" else None

    profile_changed = False
    try:
        # The rule must be off for the default: a site that keeps it on is switched off for the check and put back after
        if (saved.get("approvers") or {}).get("close_needs_approver") is True:
            status, body = put_profile({**saved, "approvers": {**saved["approvers"], "close_needs_approver": False}})
            profile_changed = True
            check("the two-person rule switched off for the default", status == 200, f"{status} {body}")

        reason = f"Corrected by hand at the receiver (roles check {stamp})"
        status, body = close(operator, first, reason)
        check(f"operator: POST /cases/{first}/close by default: 202 closing",
              status == 202 and (body or {}).get("state") == "closing" and (body or {}).get("requestedBy") == "operator", f"{status} {body}")
        c = wait(lambda: closed_by_hand(first), args.timeout)
        check(f"{first} resolves as handled_by_hand", bool(c), case(first).get("state"))
        event = last_state_event(first)
        check("its state event names the operator, the time and the reason",
              event.get("toState") == "resolved" and event.get("actor") == "operator" and bool(event.get("at"))
              and event.get("text", "").startswith(f"Handled by hand: {reason}"), event)
        _, closure = operator.call("GET", f"/cases/{first}/closure")
        closure = closure or {}
        check("its closure says who recorded it and why, and when it closed",
              closure.get("disposition") == "handled_by_hand" and closure.get("outcome") == f"Handled by hand, recorded by operator: {reason}"
              and bool(closure.get("closedAt")) and "operator" in (closure.get("actors") or []), closure)

        # ---- an escalation: the operator's, with who sent it and the digest of the text sent ----
        status, draft = operator.call("POST", f"/cases/{second}/escalations", {}, idempotent=True)
        draft = draft or {}
        check(f"operator: POST /cases/{second}/escalations: 201 draft with a recipient",
              status == 201 and draft.get("state") == "draft" and bool(draft.get("to")), f"{status} {draft}")
        seq, digest = draft.get("seq"), draft.get("bodyDigest")
        status, body = operator.call("POST", f"/cases/{second}/escalations/{seq}/send", {"bodyDigest": digest}, idempotent=True)
        check("operator: the send bound to the digest: 202 queued", status == 202 and (body or {}).get("sentBy") == "operator", f"{status} {body}")

        def sent():
            _, items = operator.call("GET", f"/cases/{second}/escalations")
            e = next((x for x in items or [] if x.get("seq") == seq), {})
            return e if e.get("state") == "sent" else None

        e = wait(sent, args.timeout) or {}
        check("the escalation is sent, by the operator, with the digest of the text read",
              e.get("sentBy") == "operator" and bool(e.get("sentAt")) and e.get("bodyDigest") == digest, e)
        _, events = operator.call("GET", f"/cases/{second}/events")
        line = next((x for x in events or [] if x.get("ref") == f"escalation:{seq}" and " sent by " in x.get("text", "")), {})
        check("the timeline names who sent it, when, and the digest of the text sent",
              line.get("actor") == "operator" and bool(line.get("at")) and line.get("text", "").endswith(f"digest of the text sent {digest}"), line)

        # ---- the two-person rule ----
        status, body = put_profile({**saved, "approvers": {**(saved.get("approvers") or {}), "close_needs_approver": True}})
        profile_changed = True
        check("approver: PUT /site-profile with approvers.close_needs_approver: 200",
              status == 200 and ((body or {}).get("profile", {}).get("approvers") or {}).get("close_needs_approver") is True, f"{status} {body}")
        before = case(second)
        reason = f"Corrected by the team after escalation {seq} (roles check {stamp})"
        status, body = close(operator, second, reason)
        check(f"operator under the rule: POST /cases/{second}/close is 403 forbidden, saying an approver is needed",
              status == 403 and error_of(body) == "forbidden" and "approver" in (body or {}).get("detail", ""), f"{status} {body}")
        after = case(second)
        check("and the case is unchanged", (after.get("state"), after.get("version")) == (before.get("state"), before.get("version")), after.get("state"))
        status, body = close(approver, second, reason)
        check(f"approver under the rule: POST /cases/{second}/close: 202 closing",
              status == 202 and (body or {}).get("requestedBy") == "approver", f"{status} {body}")
        c = wait(lambda: closed_by_hand(second), args.timeout)
        check(f"{second} resolves as handled_by_hand", bool(c), case(second).get("state"))
        event = last_state_event(second)
        check("its state event names the approver, the reason and the escalation it followed",
              event.get("actor") == "approver" and event.get("text", "").startswith(f"Handled by hand: {reason}; after escalation {seq}")
              and "(sent)" in event.get("text", "") and event.get("ref") == f"escalation:{seq}", event)
    finally:
        if profile_changed:
            status, body = put_profile(saved)
            restored = {k: v for k, v in ((body or {}).get("profile") or {}).items() if k != "version"}
            check("the site profile is put back with its answers", status == 200 and restored == saved, f"{status} {body}")

    print(f"{len(failures)} of {checks[0]} failed" if failures else f"all {checks[0]} checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
