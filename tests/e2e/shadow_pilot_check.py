#!/usr/bin/env python3
"""Shadow mode and the recovery stop on a running demo instance, counted on the wire (CONTRACTS 18).

A small counting proxy in the container stands between the connector "Downstream Out" and the demo receiver, and logs each
POST with its kind: normal (the feed), rehearsal or recovery. It fails a feed message on request, and holds a recovery write
unanswered on request. The check plays S2's messages under fresh identifiers and reads the counts:

  - enabled: one rehearsal and one write, so the counter counts;
  - stopped, across a production restart and a whole instance restart: the feed goes on and no recovery call is sent;
  - a stop takes a reason, records the signed-in user whatever the body says, and an operator can stop but neither clear nor
    enable;
  - a clear enables nothing and releases no earlier plan: its approval is refused until it is rejected and reinvestigated;
  - a write nobody answered reads as uncertain, and one a restart cut off stops recovery, with no retry on the wire;
  - shadow: nothing but the feed on the wire, a preview refused, and a report that says candidate for rehearsal.

It changes the instance, restarts it and needs the docker CLI: a throwaway one only.

  python3 tests/e2e/shadow_pilot_check.py --ctr CONTAINER --url http://127.0.0.1:PORT [--ns USER]

Signs in as the demo users operator and approver (SHUTTER_PASSWORD, default "shutter"). Standard library only.
"""
import argparse
import csv
import hashlib
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROXY_PORT = 6699
DIR = '/tmp/shadow'
HOME = '/home/irisowner'

PROXY = r'''
import http.server, json, os, socketserver, time, urllib.request, urllib.error
DIR = "%s"
def kind_of(body):
    try:
        b = json.loads(body)
    except Exception:
        return "unknown"
    if b.get("dry_run"):
        return "rehearsal"
    return "recovery" if b.get("expected_version") is not None else "normal"
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def forward(self, body):
        req = urllib.request.Request("http://127.0.0.1:52773" + self.path, data=body, method=self.command)
        for k in ("Authorization", "Content-Type"):
            if self.headers.get(k):
                req.add_header(k, self.headers[k])
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()
    def answer(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        self.answer(*self.forward(None))
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        kind = kind_of(body)
        with open(DIR + "/wire.log", "a") as log:
            log.write(kind + "\n")
        if kind == "normal" and os.path.exists(DIR + "/fail_normal"):
            return self.answer(503, b"{}")
        if kind == "recovery" and os.path.exists(DIR + "/hold_recovery"):
            time.sleep(120)
            return
        self.answer(*self.forward(body))
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
S(("127.0.0.1", %d), H).serve_forever()
''' % (DIR, PROXY_PORT)

FAILURES = []


def check(ok, text, detail=''):
    print(('ok   ' if ok else 'FAIL ') + text + (f' ({detail})' if detail != '' and not ok else ''), flush=True)
    if not ok:
        FAILURES.append(text)
    return ok


class Ctr:
    def __init__(self, name, ns):
        self.name, self.ns = name, ns

    def run(self, *args, stdin=None):
        return subprocess.run(['docker', 'exec', '-i', self.name, *args], input=stdin, capture_output=True, text=True, timeout=240)

    def session(self, lines, ns=None):
        return self.run('iris', 'session', 'IRIS', '-U', ns or self.ns, stdin='\n'.join(lines) + '\nHalt\n').stdout

    def value(self, expression):
        out = self.session([f'Write !,"RESULT: ",{expression},!'])
        for line in out.splitlines():
            if line.startswith('RESULT: '):
                return line[len('RESULT: '):]
        return out[-400:]

    def start_proxy(self):
        self.run('mkdir', '-p', DIR)
        self.run('sh', '-c', f'cat > {DIR}/proxy.py', stdin=PROXY)
        subprocess.run(['docker', 'exec', '-d', self.name, '/usr/irissys/bin/irispython', f'{DIR}/proxy.py'], check=True)
        time.sleep(2)

    def flag(self, name, on):
        self.run('sh', '-c', f'touch {DIR}/{name}' if on else f'rm -f {DIR}/{name}')

    def wire(self):
        text = self.run('sh', '-c', f'cat {DIR}/wire.log 2>/dev/null').stdout
        lines = text.split()
        return {k: lines.count(k) for k in ('normal', 'rehearsal', 'recovery', 'unknown')}

    def drop(self, folder, name, text):
        self.run('sh', '-c', f'cat > {folder}/{name}.tmp && mv {folder}/{name}.tmp {folder}/{name}.hl7', stdin=text)


class Api:
    def __init__(self, url, user, password):
        self.base = url.rstrip('/') + '/api/shutter'
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor())
        self.user, self.password = user, password
        self.sign_in()

    def sign_in(self):
        status, body = self.call('POST', '/session', {'username': self.user, 'password': self.password})
        if status != 200:
            sys.exit(f'sign-in as {self.user}: {status} {body}')

    def call(self, method, path, body=None, raw=False):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header('X-Requested-With', 'Shutter')
        if data is not None:
            req.add_header('Content-Type', 'application/json')
        try:
            with self.opener.open(req, timeout=60) as r:
                text = r.read().decode()
                return r.status, (text if raw else (json.loads(text) if text else None))
        except urllib.error.HTTPError as e:
            text = e.read().decode()
            try:
                return e.code, json.loads(text)
            except ValueError:
                return e.code, {'unparsed': text[:200]}


def wait(what, get, timeout=150, every=2):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = get()
        except OSError:
            value = None
        if value:
            return value
        time.sleep(every)
    check(False, f'timed out waiting for {what}')
    return None


SETTLED = ('escalated', 'blocked', 'failed', 'resolved', 'awaiting_approval')


class Play:
    """S2's messages under fresh identifiers: the admission delivered, the transfer failed by the proxy."""

    def __init__(self, ctr, operator, approver, folder):
        self.ctr, self.operator, self.approver, self.folder = ctr, operator, approver, folder
        self.seq = 0

    def run(self):
        self.seq += 1
        tag = f'{int(time.time()) % 100000:05d}{self.seq}'
        fix = {'MRN1002': f'MRN{tag}', 'ENC-1002': f'ENC-{tag}'}
        def text(name):
            with open(os.path.join('fixtures', 'S2', name), newline='') as f:
                t = f.read()
            for k, v in fix.items():
                t = t.replace(k, v)
            # A bed of its own, or the last play's patient occupies it and the gate rightly waits.
            return t.replace('MSG', f'M{tag}').replace('BAY2^04', f'BAY2^{tag}').replace('BAY1^01', f'BAY1^{tag}')
        before = self.ctr.wire()
        self.ctr.session(['Set ^Shutter.Config("mode") = "rules"'])
        self.ctr.drop(self.folder, f'a{tag}', text('S2-01-A01.hl7'))
        wait('the admission on the wire', lambda: self.ctr.wire()['normal'] > before['normal'])
        time.sleep(3)
        self.ctr.flag('fail_normal', True)
        at = self.ctr.wire()['normal']
        self.ctr.drop(self.folder, f'b{tag}', text('S2-02-A02.hl7'))
        wait('the transfer on the wire', lambda: self.ctr.wire()['normal'] > at)
        time.sleep(2)
        self.ctr.flag('fail_normal', False)
        return self.case(fix['ENC-1002']), before

    def case(self, encounter):
        def find():
            _, cases = self.operator.call('GET', '/cases?limit=50')
            items = cases.get('cases') or cases.get('items') or [] if isinstance(cases, dict) else cases
            for c in items:
                if c.get('encounterId') == encounter and c.get('receiver') == 'Downstream Out':
                    return c['caseId']
            return None
        return wait(f'a case for {encounter}', find)

    def settled(self, case_id, states=SETTLED, timeout=150):
        def get():
            _, c = self.operator.call('GET', f'/cases/{case_id}')
            return c if c and c.get('state') in states else None
        got = wait(f'{case_id} to settle in {states}', get, timeout=timeout)
        if not got:
            _, c = self.operator.call('GET', f'/cases/{case_id}')
            print('     the case is', (c or {}).get('state'), (c or {}).get('headline'), flush=True)
        return got or {}

    def approve(self, case_id, decision='approve'):
        _, c = self.operator.call('GET', f'/cases/{case_id}')
        _, view = self.operator.call('GET', f'/cases/{case_id}/plan')
        plan = view.get('plan', view) if isinstance(view, dict) else {}
        return self.approver.call('POST', f'/cases/{case_id}/approvals', {
            'decision': decision, 'planDigest': plan.get('digest'), 'expectedVersion': c.get('version'), 'comment': 'a check'})


def point_connector(ctr):
    lines = [
        'Set p = ##class(Ens.Config.Production).%OpenId("Shutter.Production")',
        'Set i = p.FindItemByConfigName("Downstream Out")',
        'Set s = ##class(Ens.Config.Setting).%New() Set s.Name = "HTTPServer", s.Target = "Adapter", s.Value = "127.0.0.1" Do i.Settings.Insert(s)',
        f'Set s = ##class(Ens.Config.Setting).%New() Set s.Name = "HTTPPort", s.Target = "Adapter", s.Value = "{PROXY_PORT}" Do i.Settings.Insert(s)',
        'Set sc = p.%Save() Do:sc p.SaveToClass()',
        'Set:sc sc = ##class(Ens.Director).UpdateProduction(30, 1)',
        'Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ]
    out = ctr.session(lines)
    return 'RESULT: ok' in out, out[-400:]


def restart_instance(ctr, url):
    subprocess.run(['docker', 'restart', '-t', '5', ctr.name], check=True, capture_output=True)
    def up():
        try:
            with urllib.request.urlopen(url.rstrip('/') + '/api/shutter/health', timeout=10) as r:
                return r.status == 200
        except (OSError, urllib.error.HTTPError):
            return False
    wait('the instance after a restart', up, timeout=240, every=5)
    ctr.start_proxy()
    wait('the production after a restart', lambda: ctr.value('##class(Ens.Director).IsProductionRunning()') == '1', timeout=120, every=5)
    time.sleep(10)


def put_mode(api, mode):
    _, view = api.call('GET', '/site-profile')
    body = {k: v for k, v in view['profile'].items() if k != 'version'}
    body['recovery'] = {'mode': mode}
    body['expectedVersion'] = view['version']
    return api.call('PUT', '/site-profile', body)


def incident_approve(ctr, approver, digest='sha256:shadow-check'):
    """An approval of an incident waiting for it: a row of its own, gone afterwards, since no chain may run here."""
    ctr.session([
        'Set i = ##class(Shutter.Store.Incident).%New(), i.IncidentId = "I-SHADOW", i.State = "awaiting_approval", i.PlanDigest = "sha256:shadow-check"',
        'Do i.%Save()',
        'Set c = ##class(Shutter.Store.Chain).%New(), c.Incident = i, c.Seq = 1, c.State = "awaiting_approval", c.Policy = "approval"',
        'Do c.%Save()',
    ])
    out = approver.call('POST', '/incidents/I-SHADOW/approvals', {'decision': 'approve', 'planDigest': digest, 'comment': 'a check'})
    ctr.session([
        'Set i = ##class(Shutter.Store.Incident).ByIncidentId("I-SHADOW")',
        'If $ISOBJECT(i) { Set id = i.%Id() Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Chain WHERE Incident = ?", id) Do ##class(Shutter.Store.Incident).%DeleteId(id) }',
    ])
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ctr', required=True)
    parser.add_argument('--url', required=True)
    parser.add_argument('--ns', default='USER')
    args = parser.parse_args()
    password = os.environ.get('SHUTTER_PASSWORD', 'shutter')
    ctr = Ctr(args.ctr, args.ns)
    operator, approver = Api(args.url, 'operator', password), Api(args.url, 'approver', password)

    print('-- setup', flush=True)
    ctr.start_proxy()
    ok, detail = point_connector(ctr)
    check(ok, 'the connector goes through the counting proxy', detail)
    status, _ = operator.call('POST', '/scenarios/reset', {})
    check(status == 200, 'the demo is reset', status)
    folder = ctr.value('$GET(^Shutter.Config("adtIn"))')
    _, view = approver.call('GET', '/site-profile')
    check(view['profile'].get('recovery', {}).get('mode') == 'enabled', 'the demo seeds enabled, explicitly', view['profile'].get('recovery'))
    body = {k: v for k, v in view['profile'].items() if k != 'version'}
    body['policy']['2']['single'] = 'approval'
    body['expectedVersion'] = view['version']
    status, _ = approver.call('PUT', '/site-profile', body)
    check(status == 200, 'single cases wait for an approver here', status)
    play = Play(ctr, operator, approver, folder)

    print('-- enabled: the negative control', flush=True)
    case_id, before = play.run()
    c = play.settled(case_id, ('awaiting_approval',))
    check(c.get('state') == 'awaiting_approval', 'the case waits for an approver', c.get('state'))
    w = ctr.wire()
    check(w['rehearsal'] == before['rehearsal'] + 1, 'one rehearsal on the wire', w)
    status, out = play.approve(case_id)
    check(status in (200, 202), 'approved', f'{status} {out}')
    c = play.settled(case_id, ('resolved', 'blocked', 'escalated', 'failed'))
    w = ctr.wire()
    check(w['recovery'] == before['recovery'] + 1, 'exactly one authorised write on the wire', w)
    check(c.get('state') == 'resolved', 'and the case resolves', c.get('state'))

    print('-- the stop', flush=True)
    waiting, _ = play.run()
    play.settled(waiting, ('awaiting_approval',))
    status, _ = operator.call('POST', '/recovery-control/stop', {})
    check(status == 400, 'a stop needs a reason', status)
    status, view = operator.call('POST', '/recovery-control/stop', {'reason': 'a check', 'actor': 'somebody-else', 'stoppedBy': 'somebody-else', 'user': 'somebody-else'})
    check(status == 200 and view.get('stopped') is True, 'an operator can stop', f'{status} {view}')
    check(view.get('stoppedBy') == 'operator', 'and the record names the signed-in user, not the body', view.get('stoppedBy'))
    generation = view.get('generation')
    status, again = operator.call('POST', '/recovery-control/stop', {'reason': 'again'})
    check(status == 200 and again.get('generation') == generation, 'a second stop changes nothing', again)
    status, _ = operator.call('POST', '/recovery-control/clear', {'reason': 'x', 'expectedGeneration': generation})
    check(status == 403, 'an operator cannot clear', status)
    status, _ = put_mode(operator, 'shadow')
    check(status == 403, 'or change the mode', status)
    status, out = play.approve(waiting)
    check(status == 409 and out.get('error') == 'recovery_stopped' and 'stopped' in out.get('detail', '') and 'reject it and reinvestigate' in out.get('detail', ''), 'an approval is refused while stopped, in words that hold after a clear', f'{status} {out}')
    status, out = incident_approve(ctr, approver)
    check(status == 409 and out.get('error') == 'recovery_stopped' and 'fresh evidence' in out.get('detail', ''), 'and an incident approval, which waits', f'{status} {out}')
    case_id, before = play.run()
    w = ctr.wire()
    check(w['normal'] == before['normal'] + 2, 'the ordinary feed goes on while stopped', w)
    c = play.settled(case_id, ('escalated', 'blocked', 'failed'))
    w = ctr.wire()
    check(c.get('state') == 'escalated', 'the case goes to a person', c.get('state'))
    check(w['rehearsal'] == before['rehearsal'] and w['recovery'] == before['recovery'], 'no rehearsal and no write on the wire', w)
    status, out = operator.call('POST', f'/cases/{case_id}/preview-blind-resend', {})
    check(status == 409 and out.get('error') == 'recovery_stopped', 'a preview is refused', f'{status} {out}')

    print('-- restarts', flush=True)
    out = ctr.session(['Set sc = ##class(Ens.Director).StopProduction(30, 1) Write !,"STOP ",sc,!', 'Set sc = ##class(Ens.Director).StartProduction() Write !,"START ",sc,!'])
    check('STOP 1' in out and 'START 1' in out, 'the production stops and starts', out[-300:])
    _, view = operator.call('GET', '/recovery-control')
    check(view.get('stopped') is True and view.get('generation') == generation, 'the stop outlives a production restart', view)
    restart_instance(ctr, args.url)
    operator.sign_in()
    approver.sign_in()
    _, view = operator.call('GET', '/recovery-control')
    check(view.get('stopped') is True and view.get('generation') == generation, 'and an instance restart', view)
    case_id, before = play.run()
    c = play.settled(case_id, ('escalated', 'blocked', 'failed'))
    w = ctr.wire()
    check(w['rehearsal'] == before['rehearsal'] and w['recovery'] == before['recovery'], 'still nothing on the wire after it', w)

    print('-- the clear', flush=True)
    status, _ = approver.call('POST', '/recovery-control/clear', {'reason': 'x', 'expectedGeneration': generation - 1})
    check(status == 409, 'a stale generation is refused', status)
    status, _ = approver.call('POST', '/recovery-control/clear', {'expectedGeneration': generation})
    check(status == 400, 'a clear needs a reason', status)
    status, view = approver.call('POST', '/recovery-control/clear', {'reason': 'a check', 'expectedGeneration': generation})
    check(status == 200 and view.get('stopped') is False and view.get('generation') > generation, 'an approver clears', f'{status} {view}')
    before = ctr.wire()
    status, out = play.approve(waiting)
    check(status == 409 and out.get('error') == 'plan_predates_control' and 'reject it and reinvestigate' in out.get('detail', ''), 'a clear releases no earlier plan: the approval is refused', f'{status} {out}')
    _, c = operator.call('GET', f'/cases/{waiting}')
    check(c.get('state') == 'awaiting_approval', 'and leaves no approval on the record: the case still waits', c.get('state'))
    _, approvals = operator.call('GET', f'/cases/{waiting}/approvals')
    check(not any((a.get('decision') == 'approved') for a in (approvals if isinstance(approvals, list) else (approvals or {}).get('approvals') or [])), 'with no approved decision', approvals)
    check(ctr.wire()['recovery'] == before['recovery'], 'and nothing on the wire', ctr.wire())
    status, out = incident_approve(ctr, approver, 'nothing')
    check(status == 409 and out.get('error') == 'plan_changed', 'an incident is no longer held by the stop: its own checks answer', f'{status} {out}')
    status, out = play.approve(waiting, 'reject')
    check(status in (200, 202), 'the way on the words give: reject it', f'{status} {out}')
    c = play.settled(waiting, ('blocked',), timeout=60)
    status, out = operator.call('POST', f'/cases/{waiting}/reinvestigate', {'reason': 'a check'})
    check(status in (200, 202), 'and reinvestigate', f'{status} {out}')
    c = play.settled(waiting, ('awaiting_approval',))
    status, out = play.approve(waiting)
    check(status in (200, 202), 'its new plan can be approved', f'{status} {out}')
    wait('the new plan\'s write on the wire', lambda: ctr.wire()['recovery'] == before['recovery'] + 1, timeout=60)
    check(ctr.wire()['recovery'] == before['recovery'] + 1, 'and writes once', ctr.wire())
    play.settled(waiting, ('blocked', 'escalated', 'failed', 'resolved'))

    print('-- a write nobody answers', flush=True)
    case_id, before = play.run()
    play.settled(case_id, ('awaiting_approval',))
    ctr.flag('hold_recovery', True)
    status, out = play.approve(case_id)
    check(status in (200, 202), 'approved', f'{status} {out}')
    wait('the held write on the wire', lambda: ctr.wire()['recovery'] > before['recovery'], timeout=60, every=1)
    c = play.settled(case_id, ('verifying', 'blocked', 'escalated', 'failed', 'resolved'), timeout=60)
    _, attempts = operator.call('GET', f'/cases/{case_id}/attempts')
    listed = attempts if isinstance(attempts, list) else (attempts or {}).get('attempts') or (attempts or {}).get('items') or []
    check(any((a.get('attempt') or a).get('outcome') == 'uncertain' for a in listed), 'a write nobody answered reads as uncertain, not as not sent', attempts)
    _, view = operator.call('GET', '/recovery-control')
    check(view.get('stopped') is False, 'and the case reads it back, so recovery is not stopped', view)

    print('-- a write a restart cuts off', flush=True)
    time.sleep(5)
    case_id, before = play.run()
    play.settled(case_id, ('awaiting_approval',))
    status, out = play.approve(case_id)
    check(status in (200, 202), 'approved', f'{status} {out}')
    wait('the held write on the wire', lambda: ctr.wire()['recovery'] > before['recovery'], timeout=30, every=0.5)
    _, view = operator.call('GET', '/recovery-control')
    check(view.get('outstandingCount', 0) >= 1, 'the call is outstanding while it runs', view)
    sent = ctr.wire()['recovery']
    ctr.flag('hold_recovery', False)
    restart_instance(ctr, args.url)
    operator.sign_in()
    approver.sign_in()
    view = wait('the control to find the cut-off call', lambda: (lambda v: v if v.get('stopped') else None)(operator.call('GET', '/recovery-control')[1]), timeout=60)
    view = view or {}
    check(view.get('stoppedBy') == 'system', 'a call cut off by a restart stops recovery', view)
    check(any(p.get('state') == 'uncertain' for p in view.get('outstanding', [])), 'and is listed as uncertain', view)
    time.sleep(30)
    check(ctr.wire()['recovery'] == sent, 'with no retry on the wire', ctr.wire())
    status, cleared = approver.call('POST', '/recovery-control/clear', {'reason': 'seen', 'expectedGeneration': view.get('generation')})
    check(status == 200 and cleared.get('stopped') is False and cleared.get('outstandingCount') == 0, 'a person sees it and clears', f'{status} {cleared}')

    print('-- shadow', flush=True)
    status, out = put_mode(approver, 'shadow')
    check(status == 200, 'the approver sets shadow', f'{status} {out}')
    case_id, before = play.run()
    w = ctr.wire()
    check(w['normal'] == before['normal'] + 2, 'the ordinary feed goes on in shadow', w)
    c = play.settled(case_id, ('escalated', 'blocked', 'failed', 'resolved'))
    w = ctr.wire()
    check(c.get('state') == 'escalated', 'the case goes to a person', c.get('state'))
    check('Shadow observation: nothing sent' in (c.get('headline') or ''), 'and says what it is', c.get('headline'))
    check(w['rehearsal'] == before['rehearsal'] and w['recovery'] == before['recovery'], 'no rehearsal and no write on the wire', w)
    status, out = operator.call('POST', f'/cases/{case_id}/preview-blind-resend', {})
    check(status == 409 and out.get('error') == 'recovery_shadow', 'a preview is refused', f'{status} {out}')
    status, report = operator.call('GET', '/shadow-observations?receiver=' + urllib.parse.quote('Downstream Out'))
    summary = (report or {}).get('summary', {})
    check(status == 200 and summary.get('denominator') == 'cases reaching Shutter', 'the report counts cases reaching Shutter', report if status != 200 else summary)
    check(summary.get('candidatesForRehearsal', 0) >= 1, 'with a candidate for rehearsal', summary)
    status, text = operator.call('GET', '/shadow-observations.csv', raw=True)
    rows = list(csv.DictReader(io.StringIO(text))) if status == 200 else []
    mine = [r for r in rows if r.get('case_id') == case_id]
    check(len(mine) == 1 and mine[0]['candidate_for_rehearsal'] == 'true' and mine[0]['recovery_calls_sent'] == '0' and mine[0]['rehearsal_performed'] == 'false', 'the CSV has its row, with nothing sent', mine)
    check('would have recovered' not in text.lower() and 'MRN' not in text, 'and never says would have recovered, or names a patient')
    _, c = operator.call('GET', f'/cases/{case_id}')
    printed = 'P-' + hashlib.sha256(f"{mine[0]['deployment_id']}|{c.get('patientIdAuthority') or ''}|{c.get('patientId')}".encode()).hexdigest()[:16]
    check(mine[0]['patient_reference'].startswith('P-') and mine[0]['patient_reference'] != printed, 'and its patient reference cannot be worked out from what it prints', mine[0]['patient_reference'])
    _, view = operator.call('GET', '/recovery-control')
    check('reportKey' not in view and 'ReportKey' not in view, 'and the screen is not given the key', sorted(view))
    before = ctr.wire()
    status, out = put_mode(approver, 'enabled')
    check(status == 200, 'enabled again', f'{status} {out}')
    time.sleep(20)
    _, after = operator.call('GET', f'/cases/{case_id}')
    check(after.get('state') == 'escalated' and ctr.wire() == before, 'and neither the report nor enabling releases the case', (after.get('state'), ctr.wire()))

    if FAILURES:
        print(f'{len(FAILURES)} check(s) failed')
        return 1
    print('Shadow mode and the stop: as documented, counted on the wire.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
