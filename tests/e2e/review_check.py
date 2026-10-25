#!/usr/bin/env python3
"""Checks the production review over HTTP against docs/CONTRACTS.md, section 13.

    python3 tests/e2e/review_check.py [--url http://localhost:52773] [--timeout 120]

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter"). As the
operator it lists the review targets (Shutter's own production and the demo hospital's), and reviews each twice with
agent false: each review ends done with the demo's configuration findings by code (NO_ALERT_CONSUMER, ALERTING_OFF,
QUEUE_ALERTS_OFF and FEED_SILENCE_UNWATCHED in both, PURGE_MISSING in the hospital's), in baseline order, and with the
same fingerprint both times: 64 hex characters over the configuration findings alone, which the script computes again.
When a review's own summary or case aggregates count errors in its window, they show as MESSAGE_ERRORS and
ERRORS_GROUPED on an item, which are counts with their latest message and do not enter the fingerprint. A second start
while a review of the production runs is 409 wrong_state naming it; when the first had already finished it is 202
instead, and that extra review must give the same fingerprint. The newest review the script started is the first in the
production's listing. The approver marks one configuration finding intended (201; the operator's annotation is 403), a fresh
review of the production shows it intended, and after the approver's DELETE (204; the operator's is 403) it reads new
again. A review with agent true ends with agent.state no_record (a replay instance with no recording for the
configuration's record key) or ok (every finding ranked within its severity tier; the ones the recording matched by code, item and setting
explained and first in their tier).

A review only reads the production, and the script deletes the annotation it made, so it may run on an instance in
use; on an instance with a provider key and the Agent Board item in live mode, the agent run spends model credit.
Exit status 1 when a check fails. Standard library only.
"""
import argparse
import hashlib
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

# The demo's configuration findings by production (the design's section 7); the hospital's has no purge task.
EXPECTED = {
    ("SHUTTER", "Shutter.Production"): {"NO_ALERT_CONSUMER", "ALERTING_OFF", "QUEUE_ALERTS_OFF", "FEED_SILENCE_UNWATCHED"},
    ("HOSPITAL", "Hospital.Production"): {"NO_ALERT_CONSUMER", "ALERTING_OFF", "QUEUE_ALERTS_OFF", "FEED_SILENCE_UNWATCHED",
                                          "PURGE_MISSING"},
}
# Counts and observations, which never move the fingerprint (Shutter.Review.Sweep.Fingerprint)
VOLATILE = {"ERRORS_GROUPED", "RULE_ERRORS", "MESSAGE_ERRORS", "SUSPENDED_MESSAGES", "QUEUE_BACKLOG", "NAMESPACE_UNREADABLE"}
TIERS = ["high", "medium", "low", "info"]
FINISHED = {"done", "failed"}


class Session:
    """One signed-in user of the REST API: a cookie jar and JSON in and out."""

    def __init__(self, url):
        self.base = url.rstrip("/") + "/api/shutter"
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, key=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Shutter")
        if key:
            request.add_header("Idempotency-Key", key)
        try:
            with self.opener.open(request, timeout=120) as response:
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


def wait(check, timeout, every=2):
    """Calls check() until it returns something truthy, or returns None after timeout seconds."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(every)
    return None


def fingerprint(findings):
    """The configuration fingerprint as the contract defines it: SHA-256 over the sorted configuration lines."""
    lines = sorted(f"{f['code']}|{f['item']}|{f['setting']}|{f['found']}" for f in findings
                   if f.get("confidence") in ("confirmed", "consistent") and f.get("code") not in VOLATILE)
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest() if lines else ""


def configuration(findings):
    return sorted((f["code"], f["item"], f["setting"], f["found"]) for f in findings if f.get("code") not in VOLATILE)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--timeout", type=int, default=120, help="seconds to wait for each review")
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

    def done():
        print(f"{len(failures)} of {checks[0]} failed" if failures else f"all {checks[0]} checks passed")
        return 1 if failures else 0

    def get(path):
        return operator.call("GET", path)[1] or {}

    def finished(review_id):
        r = get(f"/production-reviews/{urllib.parse.quote(review_id)}")
        return r if r.get("state") in FINISHED else None

    def start(ns, prod, agent):
        """Starts a review and returns the 202's body; a review of the production already running is waited for."""
        body = {"namespace": ns, "production": prod, "agent": agent}
        for _ in range(2):
            status, started = operator.call("POST", "/production-reviews", body, key=str(uuid.uuid4()))
            if status == 409 and (started or {}).get("error") == "wrong_state" and (started or {}).get("reviewId"):
                wait(lambda: finished(started["reviewId"]), args.timeout)
                continue
            check(f"operator: POST /production-reviews for {prod} (agent {str(agent).lower()}): 202 sweeping",
                  status == 202 and (started or {}).get("state") == "sweeping"
                  and re.fullmatch(r"PR-\d{6}", (started or {}).get("reviewId") or "") is not None
                  and (started or {}).get("requestedBy") == "operator", f"{status} {started}")
            return started if status == 202 else None
        check(f"a review of {prod} can start", False, "another review kept running")
        return None

    def review(ns, prod, agent=False):
        """Starts a review, waits for it to finish and returns it, or None."""
        started = start(ns, prod, agent)
        if not started:
            return None
        r = wait(lambda: finished(started["reviewId"]), args.timeout)
        if not check(f"{started['reviewId']} of {prod} ends done", (r or {}).get("state") == "done",
                     (r or {}).get("state") or "still running"):
            return None
        return r

    # ---- the targets ----
    status, body = operator.call("GET", "/production-reviews/targets")
    targets = {(t.get("namespace"), t.get("production")): t for t in (body or {}).get("items") or []}
    check("operator: GET /production-reviews/targets lists Shutter's production (own) and the hospital's (watched)",
          status == 200 and set(EXPECTED) <= set(targets)
          and targets.get(("SHUTTER", "Shutter.Production"), {}).get("own") is True
          and targets.get(("HOSPITAL", "Hospital.Production"), {}).get("own") is False
          and targets.get(("HOSPITAL", "Hospital.Production"), {}).get("watched") is True, f"{status} {body}")
    status, body = operator.call("POST", "/production-reviews", {"namespace": "%SYS", "production": "Not.A.Production",
                                                                 "agent": False}, key=str(uuid.uuid4()))
    check("operator: a review of a production that is not a target is 400 bad_request",
          status == 400 and (body or {}).get("error") == "bad_request", f"{status} {body}")
    status, body = operator.call("GET", "/production-reviews/PR-999999")
    check("GET /production-reviews/PR-999999 is 404 not_found", status == 404 and (body or {}).get("error") == "not_found",
          f"{status} {body}")

    def latest(f):
        """A counted finding's latest message: the header id, or for an error group whose log rows name no message (the
        production's own start and stop errors), its latest event log row."""
        e = f.get("evidence") or {}
        return str(e.get("latestHeaderId") or "") != "" or (f.get("code") == "ERRORS_GROUPED"
                                                            and str(e.get("latestLogId") or "") != "")

    def errors_in_window(r):
        """Whether the review's own data counts errors in its window: message errors, or cases it opened."""
        total = ((r.get("caseAggregates") or {}).get("_total") or {}).get("count") or 0
        return ((r.get("summary") or {}).get("messageErrorsInWindow") or 0) > 0 or total > 0

    # ---- each production, reviewed twice with agent false ----
    reviews = {}
    newest = {}  # the newest reviewId the script started, by production
    for (ns, prod), codes in EXPECTED.items():
        first = review(ns, prod)
        if not first:
            continue
        findings = first.get("findings") or []
        found = {f.get("code") for f in findings}
        check(f"{prod}: the demo's findings {', '.join(sorted(codes))}", codes <= found, f"found {sorted(found)}")
        check(f"{prod}: the findings are F1 to F{len(findings)} in baseline order (severity tier first)",
              [f.get("id") for f in findings] == [f"F{n}" for n in range(1, len(findings) + 1)]
              and [TIERS.index(f.get("severity")) for f in findings]
              == sorted(TIERS.index(f.get("severity")) for f in findings), [(f.get("id"), f.get("severity")) for f in findings])
        check(f"{prod}: the summary counts the findings by severity",
              (first.get("summary") or {}).get("findings") == len(findings)
              and (first.get("summary") or {}).get("bySeverity") == {t: sum(1 for f in findings if f.get("severity") == t)
                                                                      for t in TIERS}, first.get("summary"))
        check(f"{prod}: with agent false the agent is skipped and nothing is ranked",
              (first.get("agent") or {}).get("state") == "skipped"
              and all(f.get("rank") is None and f.get("explanation") == "" for f in findings), first.get("agent"))
        fp = first.get("fingerprint") or ""
        check(f"{prod}: the fingerprint is 64 hex characters over the configuration findings alone",
              re.fullmatch(r"[0-9a-f]{64}", fp) is not None and fp == fingerprint(findings), f"{fp} / {fingerprint(findings)}")
        counted = [f for f in findings if f.get("code") in ("MESSAGE_ERRORS", "ERRORS_GROUPED")]
        check(f"{prod}: the window's errors are indicative counts with their latest message",
              all(f.get("confidence") == "indicative" and f.get("source") == "observed"
                  and (f.get("evidence") or {}).get("count", 0) > 0 and latest(f) for f in counted),
              [(f.get("id"), f.get("code"), f.get("confidence"), f.get("source"), (f.get("evidence") or {}).get("count"),
                (f.get("evidence") or {}).get("latestHeaderId"), (f.get("evidence") or {}).get("latestLogId"))
               for f in counted])
        if errors_in_window(first):
            check(f"{prod}: the window's errors (summary {(first.get('summary') or {}).get('messageErrorsInWindow')} "
                  f"message errors, cases) show as MESSAGE_ERRORS and ERRORS_GROUPED on an item",
                  any(f.get("code") == "MESSAGE_ERRORS" and f.get("item") for f in findings)
                  and any(f.get("code") == "ERRORS_GROUPED" and f.get("item") for f in findings), f"found {sorted(found)}")
        else:
            print(f"note {prod}: {first.get('reviewId')} counts no errors in its window, so no item-level error findings to see")

        # The second run, and a start while it is still sweeping
        started = start(ns, prod, False)
        if not started:
            continue
        newest[(ns, prod)] = started["reviewId"]
        status, body = operator.call("POST", "/production-reviews", {"namespace": ns, "production": prod, "agent": False},
                                     key=str(uuid.uuid4()))
        if status == 409:
            check(f"{prod}: a start while {started['reviewId']} runs is 409 wrong_state naming it",
                  (body or {}).get("error") == "wrong_state" and (body or {}).get("reviewId") == started["reviewId"],
                  f"{status} {body}")
        elif status == 202:
            extra_id = (body or {}).get("reviewId") or ""
            print(f"note {prod}: {started['reviewId']} had finished before the second start (202 {extra_id}), so no 409 to see")
            if check(f"{prod}: the extra start's 202 names a new review", re.fullmatch(r"PR-\d{6}", extra_id) is not None
                     and extra_id != started["reviewId"], f"{body}"):
                newest[(ns, prod)] = extra_id
                extra = wait(lambda: finished(extra_id), args.timeout) or {}
                check(f"{prod}: the extra review {extra_id} ends done with the same fingerprint",
                      extra.get("state") == "done" and extra.get("fingerprint") == fp,
                      f"{extra.get('state') or 'still running'} {extra.get('fingerprint')}")
        else:
            check(f"{prod}: a start while {started['reviewId']} runs is 409 wrong_state (or 202 once it has finished)",
                  False, f"{status} {body}")
        second = wait(lambda: finished(started["reviewId"]), args.timeout) or {}
        check(f"{prod}: a second review gives the same fingerprint and the same configuration findings",
              second.get("state") == "done" and second.get("fingerprint") == fp
              and configuration(second.get("findings") or []) == configuration(findings),
              f"{second.get('state')} {second.get('fingerprint')}")
        reviews[(ns, prod)] = second

    status, listing = operator.call("GET", "/production-reviews?production=Shutter.Production&limit=5")
    if status >= 500 or status == 429:
        # A busy instance can refuse a request (a licence unit, a restart): once more, then judge it
        time.sleep(3)
        status, listing = operator.call("GET", "/production-reviews?production=Shutter.Production&limit=5")
    items = (listing or {}).get("items") or []
    latest = newest.get(("SHUTTER", "Shutter.Production"))
    check(f"operator: GET /production-reviews?production= lists the newest review first ({latest})",
          bool(items) and items[0].get("reviewId") == latest and all(i.get("production") == "Shutter.Production" for i in items)
          and (listing or {}).get("total", 0) >= len(items),
          f"{status} {[i.get('reviewId') for i in items] if items else listing}")

    # ---- an annotation: the approver's, bound to the finding's value, seen by a fresh review, then revoked ----
    base = reviews.get(("SHUTTER", "Shutter.Production"))
    candidates = [f for f in (base or {}).get("findings") or [] if f.get("status") == "new" and f.get("code") not in VOLATILE]
    candidates.sort(key=lambda f: f.get("code") != "FEED_SILENCE_UNWATCHED")
    if not check("a configuration finding with status new to annotate", bool(candidates), "none"):
        return done()
    finding, rid = candidates[0], base["reviewId"]
    subject = (finding["code"], finding["item"], finding["setting"])
    path = f"/production-reviews/{urllib.parse.quote(rid)}/annotations"

    def matching(r):
        return next((f for f in (r or {}).get("findings") or [] if (f["code"], f["item"], f["setting"]) == subject), {})

    note = {"findingId": finding["id"], "status": "intended",
            "reason": f"Review check {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}: intended for the check, then deleted"}
    status, body = operator.call("POST", path, note, key=str(uuid.uuid4()))
    check("operator: POST /production-reviews/{id}/annotations is 403 forbidden, naming Shutter_Approve",
          status == 403 and (body or {}).get("error") == "forbidden" and "Shutter_Approve" in (body or {}).get("detail", ""),
          f"{status} {body}")
    status, body = approver.call("POST", path, {"findingId": "F999", "status": "intended", "reason": "x"},
                                 key=str(uuid.uuid4()))
    check("approver: an annotation of an unknown finding is 404 not_found",
          status == 404 and (body or {}).get("error") == "not_found", f"{status} {body}")
    check(f"and {finding['id']} ({finding['code']}) is still new", matching(get(f"/production-reviews/{rid}")).get("status") == "new",
          matching(get(f"/production-reviews/{rid}")).get("status"))
    annotation = None
    try:
        status, body = approver.call("POST", path, note, key=str(uuid.uuid4()))
        if status == 201:
            annotation = str((body or {}).get("annotationId") or "")
        check(f"approver: {finding['id']} ({finding['code']} on {finding['item'] or 'the production'}) marked intended: 201",
              status == 201 and bool(annotation) and ((body or {}).get("code"), (body or {}).get("item"),
                                                      (body or {}).get("setting")) == subject
              and (body or {}).get("status") == "intended" and (body or {}).get("reason") == note["reason"]
              and (body or {}).get("owner") == "approver" and bool((body or {}).get("createdAt")), f"{status} {body}")
        if not annotation:
            return done()
        intended_before = (base.get("summary") or {}).get("intended", 0)
        fresh = review("SHUTTER", "Shutter.Production") or {}
        seen = matching(fresh)
        check("a fresh review of the production shows the finding intended, with the annotation's id",
              seen.get("status") == "intended" and str(seen.get("annotationId")) == annotation, seen)
        check("and counts it in summary.intended, with the fingerprint unchanged",
              (fresh.get("summary") or {}).get("intended") == intended_before + 1
              and fresh.get("fingerprint") == base.get("fingerprint"), f"{fresh.get('summary')} {fresh.get('fingerprint')}")
        check("the review it was made on shows it intended too (status is read live)",
              matching(get(f"/production-reviews/{rid}")).get("status") == "intended",
              matching(get(f"/production-reviews/{rid}")))
        status, body = operator.call("DELETE", f"/production-reviews/annotations/{annotation}")
        check("operator: DELETE /production-reviews/annotations/{id} is 403 forbidden",
              status == 403 and (body or {}).get("error") == "forbidden", f"{status} {body}")
        status, body = approver.call("DELETE", f"/production-reviews/annotations/{annotation}")
        check("approver: DELETE /production-reviews/annotations/{id}: 204 with an empty body",
              status == 204 and body is None, f"{status} {body}")
        if status == 204:
            annotation = None
        after = get(f"/production-reviews/{fresh.get('reviewId')}")
        check("and the finding reads new again, with no annotation",
              matching(after).get("status") == "new" and matching(after).get("annotationId") == ""
              and (after.get("summary") or {}).get("intended") == intended_before, matching(after))
    finally:
        if annotation:
            status, _ = approver.call("DELETE", f"/production-reviews/annotations/{annotation}")
            check(f"the annotation {annotation} is deleted", status == 204, status)

    # ---- the agent: a recorded explanation, or none recorded for this configuration ----
    for ns, prod in EXPECTED:
        r = review(ns, prod, agent=True)
        if not r:
            continue
        agent, findings = r.get("agent") or {}, r.get("findings") or []
        key = f"review:{ns}:{prod}|review|1|{r.get('fingerprint')}"
        if agent.get("state") == "ok":
            ranked = sorted(findings, key=lambda f: f.get("rank") or 0)
            check(f"{prod}: agent ok: every finding ranked 1 to {len(findings)} within its severity tier",
                  sorted(f.get("rank") or 0 for f in findings) == list(range(1, len(findings) + 1))
                  and [TIERS.index(f["severity"]) for f in ranked] == sorted(TIERS.index(f["severity"]) for f in ranked)
                  and agent.get("recordKey") == key,
                  [(f.get("id"), f.get("rank"), f.get("severity")) for f in findings])
            # A recording is matched by code, item and setting: findings it has no entry for keep the baseline order
            # after the explained ones of their tier, with no explanation, and its entries with no finding drop.
            explained = [f for f in findings if f.get("explanation")]
            first_unexplained = {}
            for f in ranked:
                if not f.get("explanation"):
                    first_unexplained.setdefault(f["severity"], f["rank"])
            check(f"{prod}: the recording explains {agent.get('explained')} of the findings, the others follow them in their tier",
                  (agent.get("explained") or 0) >= 1 and agent.get("explained") == len(explained)
                  and (agent.get("explained") or 0) + (agent.get("unexplained") or 0) == len(findings)
                  and isinstance(agent.get("dropped"), int)
                  and all(f["rank"] < first_unexplained.get(f["severity"], len(findings) + 1) for f in explained),
                  {k: agent.get(k) for k in ("explained", "unexplained", "dropped", "recordedEntries")})
        else:
            check(f"{prod}: agent no_record: a replay with no recording for {key}",
                  agent.get("state") == "no_record" and agent.get("mode") == "replay" and agent.get("recordKey") == key
                  and all(f.get("rank") is None for f in findings), agent)

    return done()


if __name__ == "__main__":
    sys.exit(main())
