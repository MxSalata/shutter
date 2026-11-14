#!/usr/bin/env python3
"""The FHIR R4 receiver profile, end to end, on a running demo instance.

A stock EnsLib.HL7.Operation.TCPOperation in the hospital's production fails to deliver a ward transfer. The site profile
describes the system behind it as a FHIR R4 server (here the test FHIR server a demo install serves at /fhir-facade/r4),
so Shutter reads the Encounter over FHIR and, after this case's own approval by a person, sends at most one update with
If-Match on the version it read, then looks for the version carrying its marker in the history the server returns.

Each variant seeds its own Patient and Encounter and drops its own A02:
  0   no proof imported yet: blocked with FHIR_VERSIONING_UNPROVEN, no approval task, nothing sent;
  A   the move: waits for a person although the receiver's tier is released by policy, one update, verified;
  B   rules only, the answer to the update lost: an uncertain attempt, verified from the history;
  C   another writer between the read and the write: a version conflict, the approval revoked, nothing written;
  D   recovery switched off in the entry: blocked, no approval task, nothing sent;
and with --extended:
  C2  another writer and a server that ignores If-Match: the verification fails, the case is never resolved;
  D2  Shutter recovery stopped while the case waits: the approval is refused, nothing sent.

It changes the instance: two items in Hospital.Production, the four FHIR items in Shutter's production, a receiver in
the site profile, the proof row of that receiver. At its end it restores the site profile, removes the watched mode it
set and clears a stop it latched. Run it on a throwaway instance, after tests/conformance/fhir_conformance.py wrote
the proof file:

  python3 tests/e2e/fhir_receiver_check.py --ctr CONTAINER --url http://127.0.0.1:PORT --proof FILE [--ns SHUTTER] [--extended]

The approver's password is SHUTTER_PASSWORD (default "shutter"); the test FHIR server's controls and reads go as
_SYSTEM with FHIR_PASSWORD (default "SYS").
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plain_receiver_check import Api, check, docker, drop, result, session, setting  # noqa: E402

RECEIVER = 'FHIR Ward Out'
FEED = 'FHIR Ward In'
FOLDER = '/tmp/fhirward'
PORT = 6662
FHIR_BASE = '/fhir-facade/r4'
POLICY = 'fhir-2026-11-14.1'
MARKER = 'urn:shutter:recovery'
VISIT_SYSTEM = 'urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49'
MRN_SYSTEM = 'urn:shutter:demo:mrn'
WARD_SYSTEM = 'urn:shutter:ward'
TERMINAL = ('blocked', 'escalated', 'failed', 'resolved', 'closed')
CLINICIAN = 'Zo\u00eb'
# How long a terminal session waits for a connection: the web application's session timeout and a margin.
LICENSE_WAIT = 1020


def entry(enabled):
    """The receiver as a site describes it (DESIGN 2.1), on a tier the demo's policy releases without a person."""
    return {'name': RECEIVER, 'system': 'the ward system (FHIR R4)', 'category': 'current_state', 'tier': 1,
            'applies': 'arrival_order', 'resend_timestamp': 'original', 'cancels': False, 'merges': False,
            'fhir': {'base': FHIR_BASE, 'recovery_enabled': enabled,
                     'encounter_identifier': {'system': VISIT_SYSTEM},
                     'patient_identifier': {'system': MRN_SYSTEM, 'hl7_authority': 'HOSP'},
                     'marker': {'system': MARKER},
                     'location_map': [
                         {'ward': 'WARD-A', 'location': 'Location/ward-a', 'identifier': {'system': WARD_SYSTEM, 'value': 'WARD-A'}},
                         {'ward': 'WARD-B', 'location': 'Location/ward-b', 'identifier': {'system': WARD_SYSTEM, 'value': 'WARD-B'}}]}}


class Rig(Api):
    """The approver's calls to Shutter, and the system account's to the test FHIR server."""

    def __init__(self, url, password, fhir_password):
        super().__init__(url, password)
        self.fhir_auth = 'Basic ' + base64.b64encode(f'_SYSTEM:{fhir_password}'.encode()).decode()

    def fhir(self, path, method='GET', body=None):
        """One request to the test FHIR server: the status, and the body as JSON when it is JSON."""
        request = urllib.request.Request(self.url + FHIR_BASE + path, method=method,
                                         data=None if body is None else json.dumps(body).encode('utf-8'))
        request.add_header('Authorization', self.fhir_auth)
        request.add_header('Accept', 'application/fhir+json')
        if body is not None:
            request.add_header('Content-Type', 'application/json; charset=utf-8')
        try:
            with urllib.request.urlopen(request, timeout=30) as r:
                status, raw = r.status, r.read()
        except urllib.error.HTTPError as e:
            status, raw = e.code, e.read()
        text = raw.decode('utf-8', 'replace')
        try:
            return status, json.loads(text)
        except ValueError:
            return status, text

    def stats(self):
        status, body = self.fhir('/admin/stats')
        if status != 200 or not isinstance(body, dict):
            sys.exit(f'GET {FHIR_BASE}/admin/stats: HTTP {status}: {body}')
        return body

    def case(self, cid):
        return self.get(f'/cases/{urllib.parse.quote(cid)}')


def terminal(ctr, ns, lines):
    """A terminal session's output. The Community license allows 8 connections in all, a terminal session is one, and
    the web sessions of users an earlier check signed in each hold one until 15 minutes after their last request. A
    session refused for that reason ran nothing, so it is asked for again until a connection is free."""
    deadline = time.time() + LICENSE_WAIT
    told = False
    while True:
        out = session(ctr, ns, lines)
        if '<LICENSE LIMIT EXCEEDED>' not in out or time.time() > deadline:
            return out
        if not told:
            print(f'  no connection is free for a terminal session (the license allows 8, and signed-in web sessions hold '
                  f'them until 15 minutes after their last request); asking again for up to {LICENSE_WAIT // 60} minutes', flush=True)
            told = True
        time.sleep(15)


def ask(ctr, ns, lines, what):
    """A terminal session whose last line writes RESULT: ok, or the reason; stops on anything else."""
    got = result(terminal(ctr, ns, lines), what)
    if got != 'ok':
        sys.exit(f'{what}: {got}')


def add_items(ctr):
    """A file service feeding the stock TCP operation, which reports to the alert intake the production already has."""
    have = result(terminal(ctr, 'HOSPITAL', [
        'Set p = ##class(Ens.Config.Production).%OpenId("Hospital.Production")',
        f'Write !,"RESULT: ",$SELECT($ISOBJECT(p.FindItemByConfigName("{RECEIVER}")): "there", 1: "missing"),!',
    ]), 'reading Hospital.Production')
    if have == 'there':
        return False
    ask(ctr, 'HOSPITAL', [
        'Set p = ##class(Ens.Config.Production).%OpenId("Hospital.Production")',
        f'Set i = ##class(Ens.Config.Item).%New() Set i.Name = "{FEED}", i.ClassName = "EnsLib.HL7.Service.FileService", i.PoolSize = 1, i.Enabled = 1, i.Production = p',
        'Do i.UpdateFromDefinition("")',
        setting('i', 'FilePath', 'Adapter', f'{FOLDER}/in/'),
        setting('i', 'FileSpec', 'Adapter', '*.hl7'),
        setting('i', 'CallInterval', 'Adapter', '1'),
        setting('i', 'DeleteFromServer', 'Adapter', '1'),
        setting('i', 'TargetConfigNames', 'Host', RECEIVER),
        setting('i', 'MessageSchemaCategory', 'Host', '2.5.1'),
        setting('i', 'AckMode', 'Host', 'Never'),
        'Do p.Items.Insert(i)',
        f'Set o = ##class(Ens.Config.Item).%New() Set o.Name = "{RECEIVER}", o.ClassName = "EnsLib.HL7.Operation.TCPOperation", o.PoolSize = 1, o.Enabled = 1, o.Production = p',
        'Do o.UpdateFromDefinition("")',
        setting('o', 'IPAddress', 'Adapter', '127.0.0.1'),
        setting('o', 'Port', 'Adapter', str(PORT)),
        setting('o', 'AlertOnError', 'Host', '1'),
        setting('o', 'FailureTimeout', 'Host', '0'),
        'Do p.Items.Insert(o)',
        'Set a = p.FindItemByConfigName("Ens.Alert")',
        f'Set k = "" For {{ Set st = a.Settings.GetNext(.k) Quit:k=""  If st.Name = "Receivers" Set st.Value = st.Value _ ",{RECEIVER}" }}',
        'Set sc = p.%Save() Do:sc p.SaveToClass()',
        'Set:sc sc = ##class(Ens.Director).UpdateProduction(30, 1)',
        'Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ], 'adding the items to Hospital.Production')
    return True


def place_items(ctr, ns):
    """The four FHIR items, as a site places them: on this instance's own web port, with the demo's credential."""
    out = result(terminal(ctr, ns, [
        'Set r = ##class(Shutter.FHIR.Install).PlaceItems("127.0.0.1", "", "FHIRFacade", "")',
        'Write !,"RESULT: ",r.%ToJSON(),!',
    ]), 'placing the FHIR items')
    try:
        placed = json.loads(out)
    except ValueError:
        sys.exit(f'placing the FHIR items: {out}')
    if not placed.get('ok'):
        sys.exit(f'placing the FHIR items: {out}')
    ask(ctr, ns, [
        'Set problem = ##class(Shutter.FHIR.Install).Problem()',
        'Write !,"RESULT: ",$SELECT(problem = "": "ok", 1: problem),!',
    ], 'the FHIR items after placing them')
    return placed


def store_entry(api, enabled):
    """The entry through the route a site uses, in place of an earlier one of the same name."""
    current = api.get('/site-profile')
    profile = current['profile']
    profile['receivers'] = [r for r in profile.get('receivers', []) if r.get('name') != RECEIVER] + [entry(enabled)]
    profile['expectedVersion'] = str(current['version'])
    status, answer = api.call('/api/shutter/site-profile', 'PUT', profile)
    if status != 200:
        sys.exit(f'PUT /site-profile with the FHIR receiver: HTTP {status}: {answer}')


def put_file(ctr, name, text):
    r = docker(ctr, 'sh', '-c', f'cat > {FOLDER}/{name}', stdin=text)
    if r.returncode:
        sys.exit(f'writing {FOLDER}/{name}: {r.stderr}')


def read_file_lines(name):
    return [
        f'Set f = ##class(%Stream.FileCharacter).%New() Set f.TranslateTable = "UTF8" Do f.LinkToFile("{FOLDER}/{name}")',
        'Set text = "" While \'f.AtEnd { Set text = text _ f.Read(32000) }',
    ]


def import_proof(ctr, ns, path):
    """The proof of the conformance run, imported for the receiver as a site imports its own."""
    with open(path, encoding='utf-8') as f:
        put_file(ctr, 'proof.json', f.read())
    ask(ctr, ns, read_file_lines('proof.json') + [
        f'Set sc = ##class(Shutter.Store.FHIRProof).Import("{RECEIVER}", text, .p)',
        'Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ], 'importing the proof')


def restore_profile(ctr, ns, before):
    """The profile as it was, under the source it had, so the page still says whose answers they are."""
    put_file(ctr, 'profile-before.json', json.dumps(before['profile']))
    source = str(before.get('source') or '').replace('"', '""')
    return result(terminal(ctr, ns, read_file_lines('profile-before.json') + [
        f'Set sc = ##class(Shutter.Store.SiteProfile).Store(text, "{source}", "fhir_receiver_check")',
        'Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ]), 'restoring the site profile')


def watched_mode(ctr, ns, mode):
    """No route sets the mode an alert case runs in, so a terminal session does; "" removes the setting."""
    line = f'Set ^Shutter.Config("watchedMode") = "{mode}"' if mode else 'Kill ^Shutter.Config("watchedMode")'
    ask(ctr, ns, [line, 'Write !,"RESULT: ok",!'], 'setting the watched mode')


def clear_stop(api, why):
    control = api.get('/recovery-control')
    if not control.get('stopped'):
        return True
    status, answer = api.call('/api/shutter/recovery-control/clear', 'POST',
                              {'reason': why, 'expectedGeneration': str(control.get('generation'))})
    return status == 200 and not answer.get('stopped')


def hl7_time(seconds):
    return time.strftime('%Y%m%d%H%M%S', time.gmtime(seconds)) + '+0000'


class Round:
    """One variant's own patient, visit and Encounter, and the test server's PUT count once they were seeded."""

    def __init__(self, n):
        self.n = n
        self.visit = f'FHV-{n}'
        self.mrn = f'MRN{n}'
        self.encounter = f'enc-{n}'
        self.patient = f'pat-{n}'
        self.puts = 0

    def sent(self, api):
        return api.stats().get('puts_received', 0) - self.puts


def begin(ctr, api, n, faults=()):
    """Seeds the test FHIR server, sets the fault, and drops the transfer the stock operation cannot deliver."""
    r = Round(n)
    now = time.time()
    since = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now - 7200))
    seed = [
        {'resourceType': 'Location', 'id': 'ward-a', 'status': 'active', 'name': 'Ward A',
         'identifier': [{'system': WARD_SYSTEM, 'value': 'WARD-A'}]},
        {'resourceType': 'Location', 'id': 'ward-b', 'status': 'active', 'name': 'Ward B',
         'identifier': [{'system': WARD_SYSTEM, 'value': 'WARD-B'}]},
        {'resourceType': 'Patient', 'id': r.patient, 'active': True, 'identifier': [{'system': MRN_SYSTEM, 'value': r.mrn}]},
        {'resourceType': 'Encounter', 'id': r.encounter, 'status': 'in-progress',
         'identifier': [{'system': VISIT_SYSTEM, 'value': r.visit}],
         'class': {'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode', 'code': 'IMP'},
         'subject': {'reference': f'Patient/{r.patient}'},
         'participant': [{'individual': {'display': CLINICIAN}}],
         'location': [{'location': {'reference': 'Location/ward-a'}, 'status': 'active', 'period': {'start': since}}]},
    ]
    status, answer = api.fhir('/admin/reset', 'POST', seed)
    seeded = answer.get('seeded', []) if isinstance(answer, dict) else []
    if status != 200 or len(seeded) != len(seed) or any(s.get('status') not in (200, 201) for s in seeded):
        sys.exit(f'POST {FHIR_BASE}/admin/reset with the seed: HTTP {status}: {answer}')
    if faults:
        status, answer = api.fhir('/admin/fault', 'POST', {'modes': list(faults), 'times': 1})
        if status != 200:
            sys.exit(f'POST {FHIR_BASE}/admin/fault {list(faults)}: HTTP {status}: {answer}')
    # The seed's own PUTs are counted by the server, so what Shutter sent is the count from here on.
    r.puts = api.stats().get('puts_received', 0)
    t, admitted = hl7_time(now), hl7_time(now - 7200)
    pv1 = [''] * 45
    pv1[0], pv1[1], pv1[2], pv1[3], pv1[6], pv1[19], pv1[44] = 'PV1', '1', 'I', 'WARD-B', 'WARD-A', r.visit, admitted
    message = (f'MSH|^~\\&|PAS|HOSP|WARD|HOSP|{t}||ADT^A02^ADT_A02|FHIR{n}|P|2.5.1\rEVN|A02|{t}||||{t}\r'
               f'PID|1||{r.mrn}^^^HOSP^MR||SYNTH^BRAM||19860412|M\r' + '|'.join(pv1) + '\r')
    drop(ctr, f'{FOLDER}/in', f'a02-{n}', message)
    return r


def wait_for(api, r, states, seconds=240):
    """The variant's case once it is in one of the states, or has ended; stops when it never gets there."""
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        for case in api.get('/cases?limit=200').get('items', []):
            if case.get('encounterId') == r.visit and case.get('receiver') == RECEIVER:
                last = case
                if case.get('state') in states or case.get('state') in TERMINAL:
                    return api.case(case['caseId'])
        time.sleep(2)
    sys.exit(f'no case for {r.visit} on {RECEIVER} reached {sorted(states)} in {seconds} s; last seen: '
             f'{None if last is None else (last.get("caseId"), last.get("state"), last.get("headline"))}')


def reason(api, cid):
    """The reason code of a stopped case, with the rows that failed, or the state it is in."""
    status, body = api.call(f'/api/shutter/cases/{urllib.parse.quote(cid)}/blocked-reason')
    if status != 200:
        return '', f'HTTP {status} {body.get("detail") if isinstance(body, dict) else body}'
    failing = ', '.join(f'{c.get("check")} {c.get("reason_code")}' for c in body.get('failingChecks') or [])
    return body.get('code'), failing


def approvals(api, cid):
    view = api.get(f'/cases/{urllib.parse.quote(cid)}/approvals')
    return view.get('approvals') or [], view.get('tasks') or []


def attempts(api, cid):
    """The case's write attempts, each with its verification."""
    return [pair for pair in api.get(f'/cases/{urllib.parse.quote(cid)}/attempts') or [] if pair.get('attempt')]


def approve(api, cid):
    """The approver's own approval of the plan as it stands; the status and the answer."""
    case = api.case(cid)
    plan = api.get(f'/cases/{urllib.parse.quote(cid)}/plan')
    return api.call(f'/api/shutter/cases/{urllib.parse.quote(cid)}/approvals', 'POST',
                    {'decision': 'approve', 'planDigest': plan['plan']['digest'], 'expectedVersion': case.get('version'),
                     'comment': 'fhir_receiver_check'})


def history(api, r):
    """The Encounter's versions as the server returns them: version id to resource."""
    status, bundle = api.fhir(f'/Encounter/{r.encounter}/_history')
    entries = bundle.get('entry', []) if status == 200 and isinstance(bundle, dict) else []
    return {str(((e.get('resource') or {}).get('meta') or {}).get('versionId')): e.get('resource') or {} for e in entries}


def marked(resource):
    return [t.get('code') for t in ((resource.get('meta') or {}).get('tag') or []) if t.get('system') == MARKER]


def stopped_without_asking(api, r, label, code, words):
    """Variants 0 and D: the case stops at the proposal gate with one reason, nobody is asked, nothing is sent."""
    print(label)
    failures = []
    case = wait_for(api, r, TERMINAL)
    cid = case['caseId']
    got, failing = reason(api, cid)
    print(f'  {cid}: {case["state"]}, {got} ({failing}); {case.get("headline")}')
    check(failures, case['state'] == 'blocked', 'the case is blocked')
    check(failures, got == code, f'its reason is {code}: {words}')
    stored, tasks = approvals(api, cid)
    check(failures, not tasks and not stored, f'no approval task was sent and nothing was approved ({len(tasks)} tasks, {len(stored)} approvals)')
    check(failures, not attempts(api, cid), 'no write was attempted')
    check(failures, r.sent(api) == 0, f'the server received no PUT ({r.sent(api)})')
    return failures


def to_approval(api, r, failures, expected_mode=''):
    """Waits for the approval task; returns the case, or None with the reason printed when it never asked."""
    case = wait_for(api, r, ('awaiting_approval',))
    cid = case['caseId']
    print(f'  {cid}: {case["state"]}, mode {case.get("mode")}; {case.get("headline")}')
    ok = case['state'] == 'awaiting_approval'
    check(failures, ok, 'the case waits for a person\'s approval' if ok else f'the case waits for a person\'s approval; it is {case["state"]}: {reason(api, cid)}')
    if expected_mode:
        check(failures, case.get('mode') == expected_mode, f'the case runs in mode {expected_mode} ({case.get("mode")})')
    return case if ok else None


def decided(api, r, failures, cid):
    """Approves as the approver and waits for the case's end."""
    status, answer = approve(api, cid)
    who = answer.get('approver') if isinstance(answer, dict) else None
    check(failures, status == 202 and who == 'approver', f'the approver\'s approval is accepted (HTTP {status}, approver {who})')
    if status != 202:
        print(f'  {answer}')
        return None
    case = wait_for(api, r, TERMINAL)
    print(f'  {cid}: {case["state"]}; {case.get("headline")}')
    return case


def variant_a(ctr, api, n):
    print('A, the move:')
    failures = []
    r = begin(ctr, api, n)
    case = to_approval(api, r, failures, 'policy')
    if case is None:
        return failures
    cid = case['caseId']
    stored, tasks = approvals(api, cid)
    check(failures, not stored and len(tasks) == 1, f'the tier\'s policy released nothing: one open task, no approval yet ({len(tasks)} tasks, {len(stored)} approvals)')
    view = api.get(f'/cases/{urllib.parse.quote(cid)}/plan')
    decisions = view.get('gateDecisions') or []
    check(failures, bool(decisions) and all(d.get('policyVersion') == POLICY for d in decisions),
          f'its gate decision carries the FHIR policy version {POLICY} ({[d.get("policyVersion") for d in decisions]})')
    rows = [(c.get('check'), c.get('reason_code')) for d in decisions for c in (d.get('checks') or [])]
    check(failures, ('rehearsal', 'FHIR_NO_DRY_RUN_SUBSTITUTED') in rows, 'the rehearsal row is FHIR_NO_DRY_RUN_SUBSTITUTED')
    check(failures, view.get('rehearsal') is None, 'there is no rehearsal')
    check(failures, 'rehears' not in (case.get('headline') or '').lower(), 'the headline promises no rehearsal')
    check(failures, r.sent(api) == 0, f'the server received no PUT before the approval ({r.sent(api)})')

    case = decided(api, r, failures, cid)
    if case is None:
        return failures
    check(failures, case['state'] == 'resolved', f'the case is resolved ({case["state"]}: {reason(api, cid) if case["state"] != "resolved" else ""})')
    stored, _ = approvals(api, cid)
    check(failures, len(stored) == 1 and stored[0].get('approver') == 'approver' and stored[0].get('approver') != 'policy',
          f'the one approval is the approver\'s own, never the policy\'s ({[a.get("approver") for a in stored]})')
    tried = attempts(api, cid)
    attempt = tried[0]['attempt'] if tried else {}
    verification = (tried[0].get('verification') or {}) if tried else {}
    receipt = attempt.get('receipt') if isinstance(attempt.get('receipt'), dict) else {}
    check(failures, len(tried) == 1 and attempt.get('outcome') == 'applied', f'one attempt, applied ({[t["attempt"].get("outcome") for t in tried]})')
    check(failures, receipt.get('kind') == 'fhir', f'its receipt is a FHIR one ({receipt.get("kind")})')
    check(failures, verification.get('outcome') == 'verified' and str(verification.get('summary') or '').startswith('Verified in Encounter version "2"'),
          f'the verification: {verification.get("outcome")}, {str(verification.get("summary") or "")[:60]}')
    status, current = api.fhir(f'/Encounter/{r.encounter}')
    locations = current.get('location', []) if status == 200 and isinstance(current, dict) else []
    is_open = [(e.get('location') or {}).get('reference') for e in locations if not (e.get('period') or {}).get('end')]
    check(failures, is_open == ['Location/ward-b'], f'over HTTP the Encounter\'s open location is Location/ward-b ({is_open})')
    versions = history(api, r)
    check(failures, sorted(versions) == ['1', '2'], f'its history has exactly two versions ({sorted(versions)})')
    second = versions.get('2') or {}
    check(failures, len(marked(second)) == 1 and marked(second) == [receipt.get('operation_id')] and not marked(versions.get('1') or {}),
          f'version 2 alone carries the marker, with the receipt\'s operation id ({marked(second)})')
    names = [(p.get('individual') or {}).get('display') for p in second.get('participant') or []]
    check(failures, names == [CLINICIAN], f'its participant still reads {CLINICIAN} ({names})')
    check(failures, r.sent(api) == 1, f'the server received one PUT ({r.sent(api)})')
    return failures


def variant_b(ctr, api, ns, n):
    print('B, a lost answer (rules only):')
    failures = []
    watched_mode(ctr, ns, 'rules')
    try:
        r = begin(ctr, api, n, ['commit_drop_response'])
        case = to_approval(api, r, failures, 'rules')
    finally:
        watched_mode(ctr, ns, '')
    if case is None:
        return failures
    cid = case['caseId']
    case = decided(api, r, failures, cid)
    if case is None:
        return failures
    tried = attempts(api, cid)
    attempt = tried[0]['attempt'] if tried else {}
    verification = (tried[0].get('verification') or {}) if tried else {}
    check(failures, len(tried) == 1 and attempt.get('outcome') == 'uncertain', f'one attempt, uncertain ({[t["attempt"].get("outcome") for t in tried]}, HTTP {attempt.get("httpStatus")})')
    check(failures, verification.get('outcome') == 'verified', f'the verification found it: {verification.get("outcome")}, {str(verification.get("summary") or "")[:60]}')
    check(failures, case['state'] == 'resolved', f'the case is resolved ({case["state"]}: {reason(api, cid) if case["state"] != "resolved" else ""})')
    check(failures, r.sent(api) == 1, f'the server received one PUT ({r.sent(api)})')
    return failures


def variant_c(ctr, api, n):
    print('C, another writer between the read and the write:')
    failures = []
    r = begin(ctr, api, n, ['second_writer_between_read_and_write'])
    case = to_approval(api, r, failures, 'policy')
    if case is None:
        return failures
    cid = case['caseId']
    case = decided(api, r, failures, cid)
    if case is None:
        return failures
    tried = attempts(api, cid)
    check(failures, len(tried) == 1 and tried[0]['attempt'].get('outcome') == 'version_conflict',
          f'one attempt, version_conflict ({[(t["attempt"].get("outcome"), t["attempt"].get("httpStatus")) for t in tried]})')
    got, failing = reason(api, cid)
    check(failures, case['state'] == 'blocked' and got == 'FHIR_WRITE_CONFLICT', f'the case is blocked with FHIR_WRITE_CONFLICT ({case["state"]}, {got} {failing})')
    stored, _ = approvals(api, cid)
    check(failures, len(stored) == 1 and stored[0].get('revoked') in (True, 1), f'the approval is revoked ({[(a.get("approver"), a.get("revoked")) for a in stored]})')
    versions = history(api, r)
    check(failures, bool(versions) and not any(marked(v) for v in versions.values()), f'no version carries the marker (versions {sorted(versions)})')
    return failures


def variant_c2(ctr, api, n):
    print('C2, another writer and a server that ignores If-Match:')
    failures = []
    r = begin(ctr, api, n, ['second_writer_between_read_and_write', 'ignore_if_match'])
    case = to_approval(api, r, failures)
    if case is None:
        return failures
    cid = case['caseId']
    case = decided(api, r, failures, cid)
    if case is None:
        return failures
    tried = attempts(api, cid)
    verification = (tried[0].get('verification') or {}) if tried else {}
    check(failures, verification.get('outcome') == 'failed', f'the verification failed: {verification.get("outcome")}, {str(verification.get("summary") or "")[:80]}')
    got, failing = reason(api, cid)
    check(failures, case['state'] == 'escalated' and got == 'FHIR_WRITE_CONTRADICTED', f'the case is escalated with FHIR_WRITE_CONTRADICTED ({case["state"]}, {got} {failing})')
    states = [e.get('toState') for e in api.get(f'/cases/{urllib.parse.quote(cid)}/events') or [] if isinstance(e, dict)]
    check(failures, 'escalated' in states and 'resolved' not in states, f'it was never resolved (its states: {[x for x in states if x]})')
    return failures


def variant_d2(ctr, api, n, latched):
    print('D2, Shutter recovery stopped while the case waits:')
    failures = []
    r = begin(ctr, api, n)
    case = to_approval(api, r, failures)
    if case is None:
        return failures
    cid = case['caseId']
    status, answer = api.call('/api/shutter/recovery-control/stop', 'POST', {'reason': 'fhir_receiver_check: variant D2'})
    latched.append(True)
    check(failures, status == 200 and isinstance(answer, dict) and answer.get('stopped') is True, f'the stop is latched (HTTP {status})')
    status, answer = approve(api, cid)
    code = answer.get('error') if isinstance(answer, dict) else answer
    check(failures, status == 409 and code == 'recovery_stopped', f'the approval answers 409 recovery_stopped (HTTP {status} {code})')
    time.sleep(5)
    check(failures, r.sent(api) == 0 and not attempts(api, cid), f'the server received no PUT ({r.sent(api)})')
    check(failures, clear_stop(api, 'fhir_receiver_check: variant D2 is over'), 'the stop is cleared again')
    # The plan predates the stop, so it can never be sent: the approver rejects it, which closes the task.
    case = api.case(cid)
    plan = api.get(f'/cases/{urllib.parse.quote(cid)}/plan')
    api.call(f'/api/shutter/cases/{urllib.parse.quote(cid)}/approvals', 'POST',
             {'decision': 'reject', 'planDigest': plan['plan']['digest'], 'expectedVersion': case.get('version'),
              'comment': 'fhir_receiver_check: the plan was made before the stop'})
    return failures


def leave(ctr, ns, api, before, latched):
    """The end, whatever happened: the site profile as it was, no watched mode, no stop of this run's. Each step is
    tried by itself and says how it went, so a stop on the way out never hides why the run stopped. Returns what
    could not be put back."""
    steps = [('the site profile restored', lambda: restore_profile(ctr, ns, before) == 'ok'),
             ('the watched mode removed', lambda: watched_mode(ctr, ns, '') is None)]
    if latched:
        steps.append(('the stop cleared', lambda: clear_stop(api, 'fhir_receiver_check: its end')))
    undone = []
    for what, step in steps:
        try:
            ok, why = step(), ''
        except (Exception, SystemExit) as e:
            ok, why = False, f': {e}'
        print(f'at the end: {what}' if ok else f'at the end: NOT DONE, {what}{why}')
        if not ok:
            undone.append(what)
    return undone


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--ctr', required=True)
    parser.add_argument('--url', required=True)
    parser.add_argument('--proof', required=True, help='the proof file tests/conformance/fhir_conformance.py --proof wrote')
    parser.add_argument('--ns', default='SHUTTER')
    parser.add_argument('--extended', action='store_true', help='also play variants C2 and D2')
    args = parser.parse_args()
    if not os.path.isfile(args.proof):
        sys.exit(f'no proof file at {args.proof}: run tests/conformance/fhir_conformance.py with --proof first')
    api = Rig(args.url.rstrip('/'), os.environ.get('SHUTTER_PASSWORD', 'shutter'), os.environ.get('FHIR_PASSWORD', 'SYS'))

    before = api.get('/site-profile')
    made = docker(args.ctr, 'mkdir', '-p', f'{FOLDER}/in')
    if made.returncode:
        sys.exit(f'making {FOLDER}/in in {args.ctr}: {made.stderr}')
    latched = []
    failures = []
    try:
        placed = place_items(args.ctr, args.ns)
        add_items(args.ctr)
        store_entry(api, True)
        print(f'placed the FHIR items ({placed.get("added")} added), added {RECEIVER}, a stock TCP operation on port {PORT} with nothing '
              f'listening, to Hospital.Production, and stored it in the site profile as a FHIR R4 receiver at {FHIR_BASE}')
        time.sleep(5)
        n = int(time.time()) % 800000 * 10 + 1000000

        r = begin(args.ctr, api, n)
        failures += stopped_without_asking(api, r, '0, no proof yet:', 'FHIR_VERSIONING_UNPROVEN', 'no conformance run is recorded for this server software')
        import_proof(args.ctr, args.ns, args.proof)
        print(f'imported the proof {args.proof} for {RECEIVER}')

        failures += variant_a(args.ctr, api, n + 1)
        failures += variant_b(args.ctr, api, args.ns, n + 2)
        failures += variant_c(args.ctr, api, n + 3)

        store_entry(api, False)
        r = begin(args.ctr, api, n + 4)
        failures += stopped_without_asking(api, r, 'D, recovery switched off in the entry:', 'FHIR_RECOVERY_DISABLED', 'fhir.recovery_enabled is false')

        if args.extended:
            store_entry(api, True)
            failures += variant_c2(args.ctr, api, n + 5)
            failures += variant_d2(args.ctr, api, n + 6, latched)
    finally:
        left = leave(args.ctr, args.ns, api, before, latched)
    if left:
        failures.append('the instance was not left as it was found')

    if failures:
        print(f'{len(failures)} check(s) failed')
        return 1
    print('The FHIR R4 receiver profile: one update after this case\'s own approval, verified from the history; stopped when '
          'unproven, switched off or overtaken. As designed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
