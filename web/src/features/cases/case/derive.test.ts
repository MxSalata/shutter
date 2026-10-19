import { describe, expect, it } from 'vitest';
import type { CaseEvent, SnapshotItem } from '@/api/types';
import { checksOf, describeEntry, describeItem, phaseStatuses, rounds } from './derive';

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
  it("says what the ward holds, or that it can't be read", () => {
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
        source: 'ward history',
      }),
    ).toBe('Transfer to WARD-C at 09:45:00, from the ward history');
  });
});
