import { describe, expect, it } from 'vitest';
import type { Plan, Snapshot } from '@/api/types';
import { approvalChange, type ReviewedPlan } from './approvalChange';
import type { ActionCase } from './planAction';

const KEY = (event: string) => `PAS^HOSP^MRN1002^ENC-1002^${event}^2026-10-15T08:20:00Z`;

/** A case whose own operation is the plan's, as the gate's intent check requires of a resend. */
const caseOf = (event: string, place: { ward?: string; bed?: string | null } = {}): ActionCase => ({
  operationKey: KEY(event),
  event,
  ward: place.ward ?? '',
  bed: place.bed ?? null,
  sourceSystem: 'PAS',
  receiver: 'Downstream Out',
});

/** A plan for the case's operation: a resend conditional on a receiver version, or a plan that writes nothing. */
const planOf = (event: string, over: Partial<Plan> = {}): Plan =>
  ({
    id: '901',
    version: 1,
    digest: 'sha256:plan',
    disposition: 'resend',
    actionType: 'resend',
    operationKey: KEY(event),
    expectedVersion: 1,
    ...over,
  }) as Plan;

/** The receiver's dry run of plan 901 at version 1, leaving the encounter as given. */
const rehearsal = (after: Record<string, unknown>, over: Record<string, unknown> = {}) =>
  ({
    planId: '901',
    at: '2026-11-02T14:16:40Z',
    httpStatus: 200,
    wouldApply: true,
    reason: '',
    receiverVersion: 1,
    response: { would_apply: true, encounter_after: after },
    ...over,
  }) as unknown as ReviewedPlan['rehearsal'];

const snapshot = (summary: Record<string, unknown>) =>
  ({ takenAt: '2026-11-02T14:16:40Z', summary, items: [] }) as unknown as Snapshot;

const WARD_A = { state: 'admitted', ward: 'WARD-A', bed: 'BAY1-01', version: 1 };

describe('what an approval changes at the receiver', () => {
  it('reads a transfer from the dry run of the plan: where the receiver held the patient, and where it would', () => {
    const view = {
      plan: planOf('transfer'),
      rehearsal: rehearsal({ state: 'admitted', ward: 'WARD-B', bed: 'BAY2-04', version: 2 }),
    };
    expect(
      approvalChange(
        view,
        caseOf('transfer', { ward: 'WARD-B', bed: 'BAY2-04' }),
        snapshot({ ward_state: WARD_A }),
      ),
    ).toEqual({
      held: 'WARD-A, bed BAY1-01 at version 1',
      readAt: '2026-11-02T14:16:40Z',
      expected: 'WARD-B, bed BAY2-04 at version 2',
      basis: "the receiver's dry run of this plan",
      notes: [],
    });
  });

  it('shows a change of bed within one ward as that, from the same two readings', () => {
    const view = {
      plan: planOf('transfer'),
      rehearsal: rehearsal({ state: 'admitted', ward: 'WARD-A', bed: 'BAY1-09', version: 2 }),
    };
    const r = approvalChange(
      view,
      caseOf('transfer', { ward: 'WARD-A', bed: 'BAY1-09' }),
      snapshot({ ward_state: WARD_A }),
    );
    expect(r.held).toBe('WARD-A, bed BAY1-01 at version 1');
    expect(r.expected).toBe('WARD-A, bed BAY1-09 at version 2');
  });

  it("falls back to the plan's own operation when there is no dry run, and claims no version", () => {
    const r = approvalChange(
      { plan: planOf('transfer'), rehearsal: null },
      caseOf('transfer', { ward: 'WARD-B', bed: 'BAY2-04' }),
      snapshot({ ward_state: WARD_A }),
    );
    expect(r.expected).toBe('WARD-B, bed BAY2-04');
    expect(r.basis).toBe("the plan's operation");
  });

  it("reads the ward from the evidence's mapped operation of the plan's key before the case's own", () => {
    const r = approvalChange(
      { plan: planOf('transfer'), rehearsal: null },
      caseOf('transfer', { ward: 'WARD-B' }),
      snapshot({
        ward_state: WARD_A,
        operation: { operation_key: KEY('transfer'), event: 'transfer', ward: 'WARD-C', bed: 'BAY3-01' },
      }),
    );
    expect(r.expected).toBe('WARD-C, bed BAY3-01');
  });

  it('ignores a dry run of another plan, of another version, or one that would not apply', () => {
    const c = caseOf('transfer', { ward: 'WARD-B' });
    const s = snapshot({ ward_state: WARD_A });
    const after = { state: 'admitted', ward: 'WARD-Z', version: 9 };
    for (const stale of [
      rehearsal(after, { planId: '900' }),
      rehearsal(after, { receiverVersion: 2 }),
      rehearsal(after, { wouldApply: false }),
    ]) {
      const r = approvalChange({ plan: planOf('transfer'), rehearsal: stale }, c, s);
      expect(r.expected).toBe('WARD-B');
      expect(r.basis).toBe("the plan's operation");
    }
  });

  it('never shows an update as a move: the A08 case', () => {
    // An A08's mapped operation carries no ward (the case's ward is empty), and its dry run leaves the place alone
    const view = { plan: planOf('update'), rehearsal: rehearsal({ ...WARD_A, version: 2 }) };
    const r = approvalChange(view, caseOf('update'), snapshot({ ward_state: WARD_A }));
    expect(r.expected).toBe('WARD-A, bed BAY1-01 at version 2');
    expect(r.notes).toEqual([
      'An update carries no location: the ward and bed stay as the receiver holds them.',
    ]);
    // With no dry run, the words say the same and name no place
    const bare = approvalChange(
      { plan: planOf('update'), rehearsal: null },
      caseOf('update'),
      snapshot({ ward_state: WARD_A }),
    );
    expect(bare.expected).toBe('The update is applied; the ward and bed are not changed');
    expect(bare.basis).toBe('');
  });

  it('says what an A08 naming another place does not send, when the site shows it instead of stopping', () => {
    // further_messages.a08_location: show lets this A08 reach approval; its PV1-3 is in the evidence's message
    const r = approvalChange(
      { plan: planOf('update'), rehearsal: rehearsal({ ...WARD_A, version: 2 }) },
      caseOf('update'),
      snapshot({ ward_state: WARD_A, message: { a08_ward: 'WARD-B', a08_bed: 'BAY2-09' } }),
    );
    expect(r.expected).toBe('WARD-A, bed BAY1-01 at version 2');
    expect(r.notes).toEqual([
      'An update carries no location: the ward and bed stay as the receiver holds them.',
      'The message names WARD-B, bed BAY2-09; the resend does not carry it, so the patient is not moved there.',
    ]);
    // An A08 that repeats where the receiver has the patient needs no second line
    const same = approvalChange(
      { plan: planOf('update'), rehearsal: null },
      caseOf('update'),
      snapshot({ ward_state: WARD_A, message: { a08_ward: 'WARD-A', a08_bed: 'BAY1-01' } }),
    );
    expect(same.notes).toHaveLength(1);
  });

  it("gives a discharge the receiver's own state after it only where the dry run defines it", () => {
    const held = { state: 'admitted', ward: 'WARD-B', bed: 'BAY2-02', version: 2 };
    const plan = planOf('discharge', { expectedVersion: 2 });
    const dry = approvalChange(
      {
        plan,
        rehearsal: rehearsal(
          { state: 'discharged', ward: null, bed: null, version: 3 },
          { receiverVersion: 2 },
        ),
      },
      caseOf('discharge'),
      snapshot({ ward_state: held }),
    );
    expect(dry.held).toBe('WARD-B, bed BAY2-02 at version 2');
    expect(dry.expected).toBe('Discharged at version 3');
    const bare = approvalChange(
      { plan, rehearsal: null },
      caseOf('discharge'),
      snapshot({ ward_state: held }),
    );
    expect(bare.expected).toBe(
      'The discharge is applied; what the receiver then shows is not known until it is verified',
    );
  });

  it('says a reconciliation writes nothing, and what the evidence holds of the committed operation', () => {
    const plan = planOf('transfer', {
      disposition: 'reconcile',
      actionType: 'reconcile',
      expectedVersion: '',
    });
    const committed = approvalChange(
      { plan, rehearsal: null },
      caseOf('transfer', { ward: 'WARD-B' }),
      snapshot({
        ward_state: { state: 'admitted', ward: 'WARD-B', bed: 'BAY2-04', version: 2 },
        receipt: { status: 'committed', version_before: 1, version_after: 2 },
      }),
    );
    expect(committed.expected).toBe('No new write: the operation is recorded as already delivered');
    expect(committed.notes).toEqual([
      "The receiver's receipt in the evidence shows it committed, version 1 to 2.",
    ]);
    const unknown = approvalChange(
      { plan, rehearsal: null },
      caseOf('transfer', { ward: 'WARD-B' }),
      snapshot({ ward_state: WARD_A }),
    );
    expect(unknown.notes).toEqual([
      'The evidence holds no committed receipt for this operation: whether it was applied is unknown.',
    ]);
  });

  it('says a plan that only hands the case on changes nothing at the receiver', () => {
    const r = approvalChange(
      { plan: planOf('transfer', { disposition: 'escalate', operationKey: '' }), rehearsal: null },
      caseOf('transfer', { ward: 'WARD-B' }),
      snapshot({ ward_state: WARD_A }),
    );
    expect(r.expected).toBe('No write: nothing changes at the receiver');
    expect(r.notes).toEqual([]);
  });

  it('keeps what it does not have as unknown, rather than leave it out or guess', () => {
    const view = { plan: planOf('transfer'), rehearsal: null };
    const c = caseOf('transfer', { ward: 'WARD-B' });
    expect(approvalChange(view, c, undefined).held).toBe('Not read yet');
    expect(approvalChange(view, c, null).held).toBe('Not in the evidence');
    const empty = approvalChange(view, c, snapshot({ ward_state: {} }));
    expect(empty.held).toBe('Not in the evidence');
    expect(empty.readAt).toBe('');
    // A plan whose key is not the case's own, with no mapped operation of that key in the evidence: no ward is named
    const other = approvalChange(
      {
        plan: planOf('transfer', { operationKey: 'PAS^HOSP^MRN9^ENC-9^transfer^2026-10-15T09:00:00Z' }),
        rehearsal: null,
      },
      c,
      snapshot({ ward_state: WARD_A }),
    );
    expect(other.expected).toBe("Unknown: the plan's operation is not in the evidence");
    expect(other.basis).toBe('');
    // A resend with no operation key at all names nothing
    expect(
      approvalChange({ plan: planOf('transfer', { operationKey: '' }), rehearsal: null }, c, null).expected,
    ).toBe('Unknown: the plan names no operation');
  });

  it('names the state where the receiver holds no ward', () => {
    const r = approvalChange(
      { plan: planOf('discharge', { expectedVersion: 3 }), rehearsal: null },
      caseOf('discharge'),
      snapshot({ ward_state: { state: 'admitted', version: 3 } }),
    );
    expect(r.held).toBe('Admitted at version 3');
  });
});
