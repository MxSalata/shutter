import { describe, expect, it } from 'vitest';
import type { CaseEvent, SnapshotItem } from '@/api/types';
import {
  checksOf,
  describeEntry,
  describeItem,
  forwardedFrom,
  orderOrResult,
  outageResend,
  phaseStatuses,
  rounds,
  shownFailureText,
} from './derive';

const transition = (seq: number, fromState: string, toState: string): CaseEvent => ({
  seq,
  at: '2026-10-15T09:00:00Z',
  kind: 'state',
  fromState,
  toState,
  text: '',
  actor: 'system',
  ref: '',
});

const path = (states: string[]) => states.slice(1).map((s, i) => transition(i + 1, states[i], s));

describe('phaseStatuses', () => {
  it('marks every phase done for a resolved write', () => {
    const states = [
      'detected',
      'collecting',
      'investigating',
      'proposed',
      'gated',
      'rehearsing',
      'awaiting_approval',
      'approved',
      'executing',
      'verifying',
      'resolved',
    ];
    expect(phaseStatuses('resolved', path(states))).toEqual([
      'done',
      'done',
      'done',
      'done',
      'done',
      'done',
      'done',
    ]);
  });

  it('skips rehearsal, approval and dispatch for a plan that writes nothing', () => {
    const states = ['detected', 'collecting', 'investigating', 'proposed', 'gated', 'verifying', 'resolved'];
    expect(phaseStatuses('resolved', path(states))).toEqual([
      'done',
      'done',
      'done',
      'skipped',
      'skipped',
      'skipped',
      'done',
    ]);
  });

  it('stops at dispatch when the dispatch gate blocks after the approval', () => {
    const states = [
      'detected',
      'collecting',
      'investigating',
      'proposed',
      'gated',
      'rehearsing',
      'awaiting_approval',
      'approved',
      'blocked',
    ];
    expect(phaseStatuses('blocked', path(states))).toEqual([
      'done',
      'done',
      'done',
      'done',
      'done',
      'stopped',
      'pending',
    ]);
  });

  it('stops at the gate when the gate blocks the proposal', () => {
    const states = ['detected', 'collecting', 'investigating', 'proposed', 'gated', 'blocked'];
    expect(phaseStatuses('blocked', path(states))[2]).toBe('stopped');
  });

  it('reads only the latest round after a re-plan: the first approval is not a dispatch', () => {
    const first = [
      'detected',
      'collecting',
      'investigating',
      'proposed',
      'gated',
      'rehearsing',
      'awaiting_approval',
      'approved',
    ];
    const second = ['approved', 'collecting', 'investigating', 'proposed', 'gated', 'verifying', 'resolved'];
    const events = [...path(first), ...path(second).map((e) => ({ ...e, seq: e.seq + 100 }))];
    expect(rounds(events)).toBe(2);
    expect(phaseStatuses('resolved', events)).toEqual([
      'done',
      'done',
      'done',
      'skipped',
      'skipped',
      'skipped',
      'done',
    ]);
  });

  it('shows the phase an open case is in as current', () => {
    const states = [
      'detected',
      'collecting',
      'investigating',
      'proposed',
      'gated',
      'rehearsing',
      'awaiting_approval',
    ];
    expect(phaseStatuses('awaiting_approval', path(states))).toEqual([
      'done',
      'done',
      'done',
      'done',
      'current',
      'pending',
      'pending',
    ]);
  });
});

const item = (kind: string, data: unknown): SnapshotItem => ({
  seq: 1,
  kind,
  source: 'ward_api',
  observed_at: '',
  digest: '',
  data,
});

describe('describeItem', () => {
  it("says what the downstream system holds, or that it can't be read", () => {
    expect(
      describeItem(
        item('ward_state', {
          http_status: 200,
          body: { state: 'admitted', ward: 'WARD-A', version: 1, epoch: 2, history: [{}] },
        }),
      ),
    ).toBe('Admitted in WARD-A, version 1, epoch 2; 1 operations in its history');
    expect(describeItem(item('ward_state', { http_status: 503, body: {} }))).toMatch(/unknown/);
  });

  it('never reads an unanswered receipt lookup as "not committed"', () => {
    expect(describeItem(item('receipt', { http_status: 404, body: { error: 'no_receipt' } }))).toMatch(
      /did not commit/,
    );
    expect(describeItem(item('receipt', { http_status: 503, body: { error: 'ward_unavailable' } }))).toMatch(
      /unknown/,
    );
  });

  it('says a merge with no encounter has no downstream state or receipt to read', () => {
    expect(describeItem(item('ward_state', { not_applicable: true, http_status: '' }))).toBe(
      'Not applicable: the message names no encounter',
    );
    expect(describeItem(item('receipt', { not_applicable: true }))).toBe(
      'Not applicable: the message names no encounter',
    );
  });

  it('notes the HL7 version the message says and the category it was parsed with', () => {
    expect(
      describeItem(
        item('validation', {
          parsed: true,
          doc_type: '2.5.1:ADT_A02',
          message_version: '2.4',
          route_category: '2.5.1',
          version_agrees: false,
          version_note: 'The message says HL7 2.4; the route parses it as 2.5.1',
        }),
      ),
    ).toBe(
      'Parses as 2.5.1:ADT_A02; HL7 2.4 parsed as 2.5.1: The message says HL7 2.4; the route parses it as 2.5.1',
    );
    expect(
      describeItem(
        item('validation', {
          parsed: true,
          doc_type: '2.5.1:ADT_A02',
          message_version: '2.5.1',
          route_category: '2.5.1',
          version_agrees: true,
        }),
      ),
    ).toBe('Parses as 2.5.1:ADT_A02; HL7 2.5.1 parsed as 2.5.1');
  });

  it('counts the free-text notes in a message', () => {
    expect(
      describeItem(
        item('message', {
          message_type: 'ADT^A02',
          message_control_id: 'M1',
          sending_application: 'PAS',
          assigned_location: 'WARD-B^BAY2',
          notes: ['resend now'],
        }),
      ),
    ).toMatch(/1 free-text note$/);
  });

  it('reads JSON text as well as JSON', () => {
    expect(
      describeItem(item('validation', JSON.stringify({ parsed: true, doc_type: '2.5.1:ADT_A02' }))),
    ).toBe('Parses as 2.5.1:ADT_A02');
  });

  it('says which production forwarded the message, and its header there', () => {
    expect(
      describeItem(
        item('source', {
          namespace: 'HOSPITAL',
          production: 'Hospital.Production',
          route: 'PAS In',
          header_id: '4243',
        }),
      ),
    ).toBe('Forwarded from HOSPITAL / Hospital.Production, route PAS In, message header 4243');
  });
});

describe('forwardedFrom', () => {
  it('leaves out the parts the source does not name', () => {
    expect(forwardedFrom({ namespace: 'HOSPITAL', production: 'Hospital.Production' })).toBe(
      'HOSPITAL / Hospital.Production',
    );
    expect(forwardedFrom({ namespace: 'HOSPITAL', route: 'PAS In' })).toBe('HOSPITAL, route PAS In');
  });

  it("is empty for a case the feed in Shutter's own production opened", () => {
    expect(forwardedFrom({})).toBe('');
    expect(forwardedFrom({ namespace: '', production: 'Shutter.Production', headerId: '11961' })).toBe('');
  });
});

describe('checksOf', () => {
  it('reads the checks whether the API sends them as JSON or as text', () => {
    const checks = [{ check: 'identity', result: 'pass', reason_code: 'IDENTITY_MATCHES', detail: '' }];
    const d = { stage: 'proposal', outcome: 'pass', policyVersion: '1', summary: '', at: '' } as const;
    expect(checksOf({ ...d, checks: checks as never })).toHaveLength(1);
    expect(checksOf({ ...d, checks: JSON.stringify(checks) })).toHaveLength(1);
  });
});

describe('describeEntry', () => {
  it('reads a kept disagreement and a cited event as sentences', () => {
    expect(
      describeEntry({ member: 'conformance', said: 'resend', why_kept: 'it judged the message alone' }),
    ).toBe('Conformance said resend: it judged the message alone');
    expect(
      describeEntry({
        event: 'transfer',
        ward: 'WARD-C',
        event_time: '2026-10-15T08:45:00Z',
        source: 'downstream history',
      }),
    ).toBe('Transfer to WARD-C at 09:45:00, from the downstream history');
  });
});

describe('an order or a result, and its evidence', () => {
  it('knows an order or a result by its event code or the structure its failure names', () => {
    expect(orderOrResult({ event: 'r01' })).toBe('result');
    expect(orderOrResult({ event: 'O21' })).toBe('order');
    expect(orderOrResult({ event: 'transfer', failureText: 'This message is ORU, not ADT: x' })).toBe(
      'result',
    );
    expect(orderOrResult({ event: 'x', failureText: 'This message is OML, not ADT: x' })).toBe('order');
    expect(orderOrResult({ event: 'x', failureText: 'This message is MDM, not ADT: x' })).toBeNull();
    expect(orderOrResult({ event: 'transfer' })).toBeNull();
  });

  const item = (kind: string, data: Record<string, unknown>, source = 'message_store') =>
    ({ kind, source, data }) as unknown as SnapshotItem;

  it('never shows a raw source name, and says what was not read for a receiver with no API', () => {
    expect(describeItem(item('pending_messages', { items: [], count: 0 }))).toBe(
      'None: no later message of the encounter is waiting to be delivered',
    );
    expect(describeItem(item('pending_messages', { items: [{}, {}], count: 2 }))).toMatch(
      /^2 later messages/,
    );
    expect(
      describeItem(item('further_messages', { identifier: 'read', stops: [], shows: [], unread: '' })),
    ).toBe('None found for the patient after this message');
    expect(describeItem(item('further_messages', { identifier: 'read', stops: [{}], shows: [{}, {}] }))).toBe(
      '1 that stops a write; 2 shown on the plan',
    );
    expect(describeItem(item('something_new', {}))).toBe('Recorded from the message store');
    expect(
      describeItem(
        item('ward_state', {
          http_status: 0,
          body: { error: "no state endpoint in the receiver's description" },
        }),
        'Quillon O9 Out',
      ),
    ).toBe('Not read: Quillon O9 Out has no record Shutter reads (no state endpoint in its description)');
    expect(describeItem(item('receipt', { http_status: -1, body: {} }), 'Quillon O9 Out')).toBe(
      'Not read: Quillon O9 Out keeps no receipts Shutter reads',
    );
    expect(describeItem(item('receipt', { http_status: 0, body: {} }), 'X')).toMatch(/\(HTTP none\)/);
  });

  it("finds the outage resend that settled a case's message, never a hand closure", () => {
    const r = (runId: string, closure: string | null) => ({ runId, position: 1, state: 's', closure });
    expect(outageResend({ resends: [r('R8-2', 'failed'), r('R8-3', 'sent')] })?.runId).toBe('R8-3');
    expect(outageResend({ resends: [r('H8', 'handled_by_hand')] })).toBeUndefined();
    expect(outageResend({ resends: [r('R8-3', 'already_delivered')] })?.closure).toBe('already_delivered');
    expect(outageResend({})).toBeUndefined();
  });
});

describe('the words of a message Shutter does not model', () => {
  const now =
    'Shutter does not resend it from its case, so a person decides; where its receiver is set up for the outage resend, an approver can have the engine send it again from the Incidents page';
  it('reads the words stored before 1.4.1 as they are true now, keeping what the source reported', () => {
    expect(
      shownFailureText(
        'This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides. The source reported: Alert from Quillon O9 Out',
      ),
    ).toBe(`This message is ORU, not ADT: ${now}. The source reported: Alert from Quillon O9 Out`);
    expect(shownFailureText('This message is MDM, not ADT: Shutter resends only ADT')).toBe(
      `This message is MDM, not ADT: ${now}`,
    );
    expect(
      shownFailureText(
        'There is no operation to resend. This message is ORM, not ADT: Shutter resends only ADT, so nothing is planned',
      ),
    ).toBe(`There is no operation to resend. This message is ORM, not ADT: ${now}`);
  });
  it('leaves every other text as it is', () => {
    expect(shownFailureText('The connection was refused')).toBe('The connection was refused');
    expect(shownFailureText(undefined)).toBe('');
    expect(shownFailureText(`This message is ORU, not ADT: ${now}`)).toBe(
      `This message is ORU, not ADT: ${now}`,
    );
  });
  it('says the error item in the evidence in the words of now', () => {
    const item = {
      kind: 'error',
      source: 'production',
      observed_at: '2026-11-10T01:21:43Z',
      digest: '',
      data: {
        kind: 'unmappable',
        text: 'This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides',
      },
    } as unknown as SnapshotItem;
    expect(describeItem(item)).toBe(`Unmappable: This message is ORU, not ADT: ${now}`);
  });
});
