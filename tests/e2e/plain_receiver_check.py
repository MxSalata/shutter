#!/usr/bin/env python3
"""A plain MLLP receiver: a stock EnsLib.HL7.Operation.TCPOperation with no API, on a running demo instance.

INSTALL.md 3.4 and CONTRACTS 6.4 say what a site gets for such a receiver: a case through the alert intake, the evidence and
the reason nothing was sent, and never a resend, because an ACK says a message arrived and not what the receiver now holds.
This plays that, twice, with the receiver down and with it answering a real AE, and checks nothing was sent and nothing else
was read in its place.

It changes the instance: it adds two items to Hospital.Production and a receiver to the site profile, so run it on a throwaway
one (stock-install-check.sh does, at its end).

  python3 tests/e2e/plain_receiver_check.py --ctr CONTAINER --url http://127.0.0.1:PORT [--ns USER]
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

RECEIVER = 'Plain Ward Out'
PORT = 6661
TERMINAL = ('blocked', 'escalated', 'failed', 'resolved', 'closed')

LISTENER = r'''
import socket, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", %d))
s.listen(5)
s.settimeout(1)
log = open("/tmp/plain/listener.log", "a", buffering=1)
end = time.time() + 150
conns = []
while time.time() < end:
    try:
        c, _ = s.accept()
        c.settimeout(0.2)
        conns.append([c, b""])
    except socket.timeout:
        pass
    for pair in list(conns):
        try:
            d = pair[0].recv(65536)
        except socket.timeout:
            continue
        except OSError:
            conns.remove(pair)
            continue
        if not d:
            conns.remove(pair)
            continue
        pair[1] += d
        while b"\x1c\r" in pair[1]:
            frame, pair[1] = pair[1].split(b"\x1c\r", 1)
            msh = frame.lstrip(b"\x0b").split(b"\r")[0].decode("latin-1")
            control = msh.split("|")[9]
            log.write(control + "\n")
            ack = "MSH|^~\\&|WARD|HOSP|PAS|HOSP|20260101000000||ACK|A" + control + "|P|2.5.1\rMSA|AE|" + control + "|Refused by the ward system\r"
            pair[0].sendall(b"\x0b" + ack.encode("latin-1") + b"\x1c\r")
''' % PORT


def docker(ctr, *args, stdin=None):
    return subprocess.run(['docker', 'exec', '-i', ctr, *args], input=stdin, capture_output=True, text=True, timeout=180)


def session(ctr, ns, lines):
    r = docker(ctr, 'iris', 'session', 'IRIS', '-U', ns, stdin='\n'.join(lines) + '\nHalt\n')
    return r.stdout


def result(out, what):
    """The value after RESULT: in a session's output, or stop with the output."""
    for line in out.splitlines():
        if line.startswith('RESULT: '):
            return line[len('RESULT: '):]
    sys.exit(f'{what}: no result\n{out[-1500:]}')


def setting(var, name, target, value):
    return (f'Set s = ##class(Ens.Config.Setting).%New() Set s.Name = "{name}", s.Target = "{target}", s.Value = "{value}" '
            f'Do {var}.Settings.Insert(s)')


def add_items(ctr):
    """A file service feeding the stock operation, which reports to the alert intake the production already has."""
    docker(ctr, 'mkdir', '-p', '/tmp/plain/in')
    lines = [
        'Set p = ##class(Ens.Config.Production).%OpenId("Hospital.Production")',
        'Set i = ##class(Ens.Config.Item).%New() Set i.Name = "Plain In", i.ClassName = "EnsLib.HL7.Service.FileService", i.PoolSize = 1, i.Enabled = 1, i.Production = p',
        'Do i.UpdateFromDefinition("")',
        setting('i', 'FilePath', 'Adapter', '/tmp/plain/in/'),
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
    ]
    got = result(session(ctr, 'HOSPITAL', lines), 'adding the items')
    if got != 'ok':
        sys.exit(f'adding the items: {got}')


def add_receiver(ctr, ns):
    """The site's description of it: declared features, all false, and no api."""
    entry = {'name': RECEIVER, 'system': 'a plain MLLP ward system', 'category': 'current_state', 'tier': 2,
             'applies': 'arrival_order', 'resend_timestamp': 'original', 'cancels': False, 'merges': False,
             'features': {'conditional_writes': False, 'receipts': False, 'history': False, 'dry_run': False}}
    literal = json.dumps(entry).replace('"', '""')
    lines = [
        'Set p = ##class(Shutter.Store.SiteProfile).Current()',
        f'Do p.%Get("receivers").%Push({{}}.%FromJSON("{literal}"))',
        'Set sc = ##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "plain_receiver_check", "plain_receiver_check")',
        'Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ]
    got = result(session(ctr, ns, lines), 'adding the receiver')
    if got != 'ok':
        sys.exit(f'adding the receiver: {got}')


def drop(ctr, folder, name, text):
    r = docker(ctr, 'sh', '-c', f'cat > {folder}/{name}.tmp && mv {folder}/{name}.tmp {folder}/{name}.hl7', stdin=text)
    if r.returncode:
        sys.exit(f'writing {folder}/{name}: {r.stderr}')


def stamp():
    return time.strftime('%Y%m%d%H%M%S', time.gmtime())


def send(ctr, feed, n):
    """Admits an encounter through the hospital's own feed, to the demo receiver, then sends its transfer to the plain one."""
    pid = f'PID|1||MRN{n}^^^HOSP^MR~99910{n}4^^^NHS^NH||SYNTH^BRAM||19860412|M'
    t1 = stamp()
    admit = (f'MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|{t1}||ADT^A01^ADT_A01|MSGA{n}{t1}|P|2.5.1\rEVN|A01|{t1}||||{t1}\r{pid}\r'
             f'PV1|1|I|WARD-A^BAY1^{n}^HOSP||||||||||||||||ENC-{n}|||||||||||||||||||||||||{t1}\r')
    drop(ctr, feed, f'a{n}', admit)
    time.sleep(6)
    t2 = stamp()
    control = f'MSGB{n}{t2}'
    transfer = (f'MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|{t2}||ADT^A02^ADT_A02|{control}|P|2.5.1\rEVN|A02|{t2}||||{t2}\r{pid}\r'
                f'PV1|1|I|WARD-B^BAY2^{n}^HOSP|||WARD-A^BAY1^{n}^HOSP|||||||||||||ENC-{n}|||||||||||||||||||||||||{t1}\r')
    drop(ctr, '/tmp/plain/in', f'b{n}', transfer)
    return f'ENC-{n}', control


class Api:
    def __init__(self, url, password):
        self.url = url
        self.auth = 'Basic ' + base64.b64encode(f'approver:{password}'.encode()).decode()
        # The demo receiver's own API is for the system account, as scenario_check reads it.
        self.system = 'Basic ' + base64.b64encode(b'_SYSTEM:SYS').decode()

    def call(self, path, method='GET', body=None, auth=None):
        request = urllib.request.Request(self.url + path, method=method, data=None if body is None else json.dumps(body).encode())
        request.add_header('Authorization', auth or self.auth)
        request.add_header('Content-Type', 'application/json')
        request.add_header('X-Requested-With', 'Shutter')
        try:
            with urllib.request.urlopen(request, timeout=30) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as e:
            raw = e.read().decode('utf-8', 'replace')
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, raw

    def get(self, path):
        status, body = self.call('/api/shutter' + path)
        if status != 200:
            sys.exit(f'GET {path}: HTTP {status}: {body}')
        return body


def wait_for_case(api, encounter):
    deadline = time.time() + 180
    last = None
    while time.time() < deadline:
        for case in api.get('/cases').get('items', []):
            if case.get('encounterId') == encounter and case.get('receiver') == RECEIVER:
                last = case
                if case.get('state') in TERMINAL:
                    return case
        time.sleep(3)
    sys.exit(f'no finished case for {encounter} on {RECEIVER} in 180 s; last seen: {last}')


def check(failures, ok, text):
    print(('  ok   ' if ok else '  FAIL ') + text)
    if not ok:
        failures.append(text)


def play(ctr, api, feed, n, label, kinds, sent_expected):
    print(label)
    encounter, control = send(ctr, feed, n)
    case = wait_for_case(api, encounter)
    cid = case['caseId']
    failures = []
    print(f'  {cid}: {case["state"]}, failure kind {case.get("failureKind")}')
    check(failures, case.get('failureKind') in kinds, f'the alert intake opened it as {sorted(kinds)}')
    check(failures, case['state'] == 'blocked', 'it ends blocked, with a person to decide')
    snapshot = api.get(f'/cases/{cid}/snapshot')
    summary = snapshot.get('summary', snapshot)
    route = summary.get('route') or {}
    check(failures, route.get('capabilities_source') == 'declared by the site profile', 'its capabilities are the declared ones')
    check(failures, route.get('conditional_writes') is False, 'with conditional writes false')
    check(failures, summary.get('ward_http_status') != 200, 'and nothing else was read in its place')
    reasons = json.dumps(api.get(f'/cases/{cid}/blocked-reason'))
    check(failures, 'CONNECTOR_INCAPABLE' in reasons, 'the reason says a resend cannot be made safe (CONNECTOR_INCAPABLE)')
    attempts = api.get(f'/cases/{cid}/attempts')
    items = attempts.get('items', attempts) if isinstance(attempts, dict) else attempts
    check(failures, not items, 'no write was attempted')
    status, answer = api.call(f'/api/shutter/cases/{cid}/approvals', 'POST', {'decision': 'approve', 'planDigest': 'sha256:plain-receiver-check', 'expectedVersion': case.get('version', 0)})
    check(failures, status == 409, f'an approval is refused (HTTP {status}): {answer.get("detail") if isinstance(answer, dict) else answer}')
    status, held = api.call(f'/downstream/api/encounters/{encounter}', auth=api.system)
    check(failures, status == 200 and held.get('ward') == 'WARD-A', f'the demo receiver still holds what the feed gave it: {held.get("ward") if status == 200 else status}')
    log = docker(ctr, 'sh', '-c', 'cat /tmp/plain/listener.log 2>/dev/null').stdout.split()
    check(failures, log.count(control) == sent_expected, f'the receiver saw the message {sent_expected} time(s), as the first send; it saw it {log.count(control)}')
    return failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ctr', required=True)
    parser.add_argument('--url', required=True)
    parser.add_argument('--ns', default='USER')
    args = parser.parse_args()
    api = Api(args.url, os.environ.get('SHUTTER_PASSWORD', 'shutter'))

    add_items(args.ctr)
    add_receiver(args.ctr, args.ns)
    feed = result(session(args.ctr, 'HOSPITAL', ['Write !,"RESULT: ",##class(%File).NormalizeDirectory("shutter/hospital/in", $SYSTEM.Util.ManagerDirectory()),!']), 'the feed folder').rstrip('/')
    print(f'added {RECEIVER}, a stock TCP operation on port {PORT} with no API, to Hospital.Production and the site profile')
    base = int(time.time()) % 8000 + 1000

    failures = play(args.ctr, api, feed, base, 'The receiver is down:', {'delivery_failed', 'uncertain_outcome'}, 0)

    docker(args.ctr, 'sh', '-c', 'cat > /tmp/plain/listener.py', stdin=LISTENER)
    subprocess.run(['docker', 'exec', '-d', args.ctr, '/usr/irissys/bin/irispython', '/tmp/plain/listener.py'], check=True)
    time.sleep(2)
    failures += play(args.ctr, api, feed, base + 1, 'The receiver answers AE:', {'rejected'}, 1)

    if failures:
        print(f'{len(failures)} check(s) failed')
        return 1
    print('A plain receiver: a case, its evidence and the reason, and nothing sent. As documented.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
