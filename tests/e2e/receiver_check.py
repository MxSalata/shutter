#!/usr/bin/env python3
"""What to check at the receiver (GET /cases/{id}/receiver-check), on a running demo instance.

Plays a failed MDM^T02 and a failed ORU^R01, each with a synthetic Base64 payload in OBX and canary strings in NTE and PID-5,
and a failed transfer, through a stock TCP operation with no API and nothing listening. Reads the card of each, and of every
stopped case the scenarios left. Checks the card's fields, that no payload or canary comes through, roles, the site's runbook
line, and that reading the card makes no production message, no agent run and no change at any receiver.

It changes the instance as plain_receiver_check does (items in Hospital.Production, a receiver in the site profile, a user
with no roles), so run it on a throwaway one, after the scenarios.

  python3 tests/e2e/receiver_check.py --ctr CONTAINER --url http://127.0.0.1:PORT [--ns USER]
"""
import argparse
import base64
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plain_receiver_check import RECEIVER, Api, add_items, add_receiver, check, drop, result, session, send, stamp, wait_for_case  # noqa: E402

CANARY = 'CANARYRC7731'
PAYLOAD = base64.b64encode((CANARY + 'PAYLOAD ').encode() * 6000).decode()
MISSING = 'Not available from this message'
FORBIDDEN_KEYS = ('verified', 'safe_to_resend', 'action', 'confidence', 'expected')


def pid(n):
    return f'PID|1||MRN{n}^^^HOSP^MR||{CANARY}^SYNTH||19860412|M'


def t02(n, number):
    t = stamp()
    control = f'DOC{n}{t}'
    txa = f'TXA|1|CN|TX|{t}||||||||{number}|||||LA'
    return control, (f'MSH|^~\\&|DOCS|DOC|DMS|DOC|{t}||MDM^T02^MDM_T02|{control}|P|2.5.1\rEVN|T02|{t}\r{pid(n)}\r'
                     f'PV1|1|O|CLINIC1||||||||||||||||ENC-{n}\r{txa}\rOBX|1|ED|DOC^Letter||^application^pdf^Base64^{PAYLOAD}||||||F\r'
                     f'NTE|1||{CANARY}NOTE\r')


def oru(n):
    t = stamp()
    control = f'ORU{n}{t}'
    return control, (f'MSH|^~\\&|LIMS|PATH|OCS|PATH|{t}||ORU^R01^ORU_R01|{control}|P|2.5.1\r{pid(n)}\r'
                     f'PV1|1|O|CLINIC1||||||||||||||||ENC-{n}\rORC|RE|PL{n}|FILL{n}\rOBR|1|PL{n}|FILL{n}|FBC^Full blood count|||{t}||||||||||||||||||F\r'
                     f'OBX|1|ED|PDF^Report||^application^pdf^Base64^{PAYLOAD}||||||F\rNTE|1||{CANARY}NOTE\r')


def fields(card):
    return {f['label']: f for f in card['messageRequest']['fields']}


def clean(failures, label, card):
    text = json.dumps(card)
    check(failures, CANARY not in text, f'{label}: no canary on the card')
    check(failures, PAYLOAD[:40] not in text, f'{label}: no Base64 payload on the card')
    keys = set(re.findall(r'"(\w+)":', text))
    check(failures, not keys.intersection(FORBIDDEN_KEYS), f'{label}: no verified, safe_to_resend, action or expected field')
    low = text.lower()
    check(failures, 'safe to resend' not in low and 'expected result' not in low, f'{label}: the words never say safe to resend')


def spy(ctr, ns, api, encounters):
    """Everything a read of the card could touch: production messages by target, agent runs, each receiver's encounter."""
    out = session(ctr, ns, [
        'Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName T, COUNT(*) N FROM Ens.MessageHeader GROUP BY TargetConfigName")',
        'Set s = "" While rs.%Next() { Set s = s _ rs.%Get("T") _ "=" _ rs.%Get("N") _ ";" }',
        'Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) N FROM Shutter_Store.AgentRun") Do rs.%Next() Set s = s _ "runs=" _ rs.%Get("N")',
        'Write !,"RESULT: ",s,!',
    ])
    state = {}
    for pair in result(out, 'counting').split(';'):
        if '=' in pair:
            k, v = pair.rsplit('=', 1)
            state[k.strip()] = v
    for encounter in encounters:
        status, body = api.call(f'/downstream/api/encounters/{encounter}', auth=api.system)
        state[encounter] = f'{status} {body.get("version") if isinstance(body, dict) else ""}'
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ctr', required=True)
    parser.add_argument('--url', required=True)
    parser.add_argument('--ns', default='USER')
    args = parser.parse_args()
    api = Api(args.url, os.environ.get('SHUTTER_PASSWORD', 'shutter'))
    failures = []

    add_items(args.ctr)
    add_receiver(args.ctr, args.ns)
    feed = result(session(args.ctr, 'HOSPITAL', ['Write !,"RESULT: ",##class(%File).NormalizeDirectory("shutter/hospital/in", $SYSTEM.Util.ManagerDirectory()),!']), 'the feed')
    base = int(time.time()) % 8000 + 1000

    # ---- the two common failures, with nothing listening ----
    number = f'DOCNUM{base}'
    _, text = t02(base, number)
    drop(args.ctr, '/tmp/plain/in', f't{base}', text)
    print('A failed MDM^T02 at a receiver with no API:')
    case = wait_for_case(api, f'ENC-{base}')
    print(f'  {case["caseId"]}: {case["state"]}, event {case.get("event")}, kind {case.get("failureKind")}')
    card = api.get(f'/cases/{case["caseId"]}/receiver-check')
    check(failures, card['variant'] == 'document', f'the document card: {card["variant"]}')
    check(failures, card['receiverEvidence'] == 'unavailable', 'no receiver evidence')
    check(failures, fields(card).get('Document number', {}).get('value') == number, f'TXA-12 is read: {fields(card).get("Document number")}')
    check(failures, fields(card).get('Status', {}).get('value') == 'LA', f'TXA-17 is read: {fields(card).get("Status")}')
    check(failures, card['identity']['messageType'] == 'MDM^T02', f'the type: {card["identity"]["messageType"]}')
    check(failures, card['identity']['encounterId'] == f'ENC-{base}', 'the encounter')
    check(failures, 'may still arrive' in card['queueWarning'], 'the queue warning')
    clean(failures, 'T02', card)
    t02card = card

    _, text = oru(base + 1)
    drop(args.ctr, '/tmp/plain/in', f'o{base}', text)
    print('A failed ORU^R01 at a receiver with no API:')
    case = wait_for_case(api, f'ENC-{base + 1}')
    print(f'  {case["caseId"]}: {case["state"]}, event {case.get("event")}, kind {case.get("failureKind")}')
    card = api.get(f'/cases/{case["caseId"]}/receiver-check')
    check(failures, card['variant'] == 'result', f'the result card: {card["variant"]}')
    numbers = [f for f in card['messageRequest']['fields'] if f['label'].startswith('Order or report number')]
    check(failures, numbers and numbers[0]['value'] == f'FILL{base + 1}', f'OBR-3 is read: {numbers}')
    clean(failures, 'ORU', card)

    print('A failed transfer at a receiver with no API:')
    encounter, _ = send(args.ctr, feed, base + 2)
    case = wait_for_case(api, encounter)
    print(f'  {case["caseId"]}: {case["state"]}, kind {case.get("failureKind")}')
    plain = case['caseId']
    card = api.get(f'/cases/{plain}/receiver-check')
    check(failures, card['variant'] == 'manual_compare', f'the general card: {card["variant"]}')
    check(failures, card['evidenceNote'].startswith('Shutter cannot read this receiving system'), f'the banner: {card["evidenceNote"]}')
    check(failures, fields(card).get('Ward', {}).get('value') == 'WARD-B', 'what the message asked')
    clean(failures, 'plain transfer', card)

    # ---- every stopped case on the instance: the scenarios' cases included ----
    print('Every stopped case:')
    cases = api.get('/cases?limit=500').get('items', [])
    seen = {}
    for c in cases:
        if c['state'] not in ('blocked', 'escalated', 'failed'):
            continue
        got = api.get(f'/cases/{c["caseId"]}/receiver-check')
        seen.setdefault(c.get('scenario') or c.get('event'), set()).add(got['variant'])
        clean([], c['caseId'], got)
        keys = set(re.findall(r'"(\w+)":', json.dumps(got)))
        if keys.intersection(FORBIDDEN_KEYS) or CANARY in json.dumps(got):
            failures.append(f'{c["caseId"]} carries something it must not')
    print('  ' + ', '.join(f'{k}: {sorted(v)}' for k, v in sorted(seen.items(), key=lambda x: str(x[0]))))
    for scenario, variant in (('S13', 'identity_or_time'), ('S8', 'later_movement'), ('S15', 'withheld'), ('S10', 'manual_compare')):
        if scenario in seen:
            check(failures, variant in seen[scenario], f'{scenario} has the {variant} card: {sorted(seen[scenario])}')
        else:
            print(f'  NOT CHECKED: no stopped case of {scenario} on this instance')

    # ---- a spy: reading the card changes nothing and calls nothing ----
    print('Reading the card:')
    encounters = [c.get('encounterId') for c in cases if c.get('encounterId') and c.get('receiver') == 'Downstream Out'][:8]
    stopped = [c['caseId'] for c in cases if c['state'] in ('blocked', 'escalated', 'failed')][:12]
    time.sleep(5)
    before = spy(args.ctr, args.ns, api, encounters)
    for cid in stopped * 2:
        api.get(f'/cases/{cid}/receiver-check')
    after = spy(args.ctr, args.ns, api, encounters)
    moved = {k: (before.get(k), after.get(k)) for k in set(before) | set(after) if before.get(k) != after.get(k)}
    receivers = {k: v for k, v in moved.items() if k in ('Downstream Out', 'Records Out', RECEIVER, 'runs', 'Case Evidence', 'Evidence') or k in encounters}
    check(failures, not receivers, f'{len(stopped) * 2} reads: no message to a receiver, no agent run, no receiver change: {receivers or "none"}')
    print(f'  every other count: {moved or "none moved"}')

    # ---- roles ----
    print('Who may read it:')
    cid = stopped[0]
    status, _ = api.call(f'/api/shutter/cases/{cid}/receiver-check', auth='Basic ' + base64.b64encode(b'operator:' + os.environ.get('SHUTTER_PASSWORD', 'shutter').encode()).decode())
    check(failures, status == 200, f'an operator: {status}')
    session(args.ctr, '%SYS', ['Set sc = ##class(Security.Users).Create("rcnorole", "", "RcNoRole-1", "no roles") Write !,"RESULT: ",sc,!'])
    status, body = api.call(f'/api/shutter/cases/{cid}/receiver-check', auth='Basic ' + base64.b64encode(b'rcnorole:RcNoRole-1').decode())
    check(failures, status in (401, 403) and 'variant' not in json.dumps(body), f'a user without Shutter_Operate: {status}')
    status, body = api.call(f'/api/shutter/cases/{cid}/receiver-check', auth='Basic !')
    check(failures, status == 401 and 'variant' not in json.dumps(body), f'nobody signed in: {status}')
    done = next((c['caseId'] for c in cases if c['state'] == 'resolved'), None)
    if done:
        status, body = api.call(f'/api/shutter/cases/{done}/receiver-check')
        check(failures, status == 404 and body.get('error') == 'not_stopped', f'a resolved case: {status} {body}')
    status, body = api.call('/api/shutter/cases/C-999999/receiver-check')
    check(failures, status == 404, f'an unknown case: {status}')

    # ---- the site's runbook line ----
    print("The site's runbook line:")
    view = api.get('/site-profile')
    profile = view['profile']
    entry = next(r for r in profile['receivers'] if r['name'] == RECEIVER)
    for bad in ('<b>bold</b>', 'see https://pas.example/x', 'password: x', 'patient 1234567', 'x' * 301):
        entry['manual_check'] = {'runbook': bad}
        status, body = api.call('/api/shutter/site-profile', 'PUT', profile)
        check(failures, status == 400 and 'manual_check' in json.dumps(body), f'refused ({status}): {bad[:24]}')
    line = 'In Clinical Documents, search the patient and report reference; check Filed > Unfiled, then open the item.'
    entry['manual_check'] = {'runbook': line}
    status, body = api.call('/api/shutter/site-profile', 'PUT', profile)
    check(failures, status == 200, f'a plain line is saved: {status}')
    card = api.get(f'/cases/{t02card["caseId"]}/receiver-check')
    check(failures, card['siteRunbook'] == line, 'it shows on the receiver\'s stopped case')
    check(failures, card['variant'] == 'document' and card['receiverEvidence'] == 'unavailable', 'and changes nothing else about the card')

    if failures:
        print(f'{len(failures)} check(s) failed')
        for f in failures:
            print('  ' + f)
        return 1
    print('What to check at the receiver: as documented, nothing leaked, nothing called.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
