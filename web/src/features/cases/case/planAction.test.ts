import { describe, expect, it } from 'vitest';
import type { CaseDetail, Plan, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { decisionLabels, planOperation, planWords, receiverPhrase, type ActionCase } from './planAction';

const KEY = (event: string) => `PAS^HOSP^MRN1002^ENC-1002^${event}^2026-10-15T08:20:00Z`;

const caseOf = (event: string, ward = ''): ActionCase => ({
  operationKey: KEY(event),
  event,
  ward,
  bed: null,
  sourceSystem: 'PAS',
  receiver: 'Downstream Out',
});

const planOf = (event: string, over: Partial<Plan> = {}) =>
  ({
    disposition: 'resend',
    operationKey: KEY(event),
    expectedVersion: 1,
    plan: {},
    ...over,
  }) as Plan;

/** The evidence's route as the recordings carry it: what the receiver is, with its API in brackets. */
const routed = { route: { receiver: 'the demo bed-management system (/downstream/api)' } };
const snapshot = (summary: Record<string, unknown> = routed) =>
  ({ takenAt: '2026-11-02T14:16:40Z', summary, items: [] }) as unknown as Snapshot;

describe("the plan's action in plain words", () => {
  it('says a resend as one sentence: what is sent, once, and the receiver version it is conditional on', () => {
    const w = planWords(planOf('transfer'), caseOf('transfer', 'WARD-B'), snapshot());
    expect(w.write).toBe(true);
    expect(w.action).toBe('Resend the PAS transfer to WARD-B, once');
    expect(w.headline).toBe(
      'Resend the PAS transfer to WARD-B, once, only if the bed-management system is still at version 1.',
    );
    expect(w.onlyIf).toEqual([
      'The bed-management system still holds the encounter at version 1',
      'No later event has moved the encounter on',
    ]);
    expect(w.noun).toBe('the resend');
  });

  it('says the same of the recorded S2 case the trial holds for approval', () => {
    const recorded = fixtures.cases['C-000002'];
    const w = planWords(
      (recorded.plan as unknown as PlanView).plan,
      recorded.detail as unknown as CaseDetail,
      recorded.snapshot as unknown as Snapshot,
    );
    expect(w.headline).toBe(
      'Resend the PAS transfer to WARD-B, once, only if the bed-management system is still at version 1.',
    );
  });

  it('names an admission as one, conditional on the receiver not having seen the encounter', () => {
    const w = planWords(planOf('admit', { expectedVersion: 0 }), caseOf('admit', 'WARD-A'), snapshot());
    expect(w.headline).toBe(
      'Resend the PAS admission to WARD-A, once, only if the bed-management system still has no record of the encounter (version 0).',
    );
    expect(w.onlyIf[0]).toBe('The bed-management system still has no record of the encounter (version 0)');
  });

  it('names no ward for a discharge or an update, which carry none', () => {
    expect(
      planWords(planOf('discharge', { expectedVersion: 2 }), caseOf('discharge'), snapshot()).headline,
    ).toBe('Resend the PAS discharge, once, only if the bed-management system is still at version 2.');
    expect(planWords(planOf('update'), caseOf('update'), snapshot()).action).toBe(
      'Resend the PAS update, once',
    );
  });

  it('says first that a plan which is no resend sends nothing', () => {
    const c = caseOf('transfer', 'WARD-B');
    const of = (disposition: string) =>
      planWords(planOf('transfer', { disposition, expectedVersion: '' }), c, snapshot());
    expect(of('reconcile').headline).toBe(
      'Send nothing: record the PAS transfer to WARD-B as already delivered.',
    );
    expect(of('superseded').headline).toBe(
      'Send nothing: a later event overtook the PAS transfer to WARD-B.',
    );
    expect(of('escalate').headline).toBe('Send nothing: hand the PAS transfer to WARD-B to a person.');
    expect(of('more_evidence').headline).toBe('Send nothing to the bed-management system: more evidence.');
    for (const d of ['reconcile', 'superseded', 'escalate', 'more_evidence']) {
      expect(of(d).write).toBe(false);
      expect(of(d).onlyIf).toEqual([]);
      expect(of(d).noun).toBe('the plan');
    }
  });

  it("speaks of the case's own operation where a plan that sends nothing carries no key", () => {
    const none = planOf('transfer', { disposition: 'escalate', operationKey: '', expectedVersion: '' });
    expect(planWords(none, caseOf('transfer', 'WARD-B'), snapshot()).headline).toBe(
      'Send nothing: hand the PAS transfer to WARD-B to a person.',
    );
    // An order or a result goes to no ward, whatever its PV1 carries
    const result = { ...caseOf('R01', 'WARD-B'), sourceSystem: 'QUILLON' };
    expect(planWords(none, result, snapshot()).headline).toBe(
      'Send nothing: hand the QUILLON result to a person.',
    );
  });

  it("says so when a resend names no operation, rather than borrow the case's", () => {
    const w = planWords(planOf('transfer', { operationKey: '' }), caseOf('transfer', 'WARD-B'), snapshot());
    expect(w.action).toBe('Resend an operation the plan does not name, once');
  });

  it('names the receiver by its production item, or as the receiver, when the evidence does not describe it', () => {
    expect(receiverPhrase({ receiver: 'Records Out' }, null)).toBe('Records Out');
    expect(receiverPhrase({ receiver: undefined }, undefined)).toBe('the receiver');
    expect(planWords(planOf('transfer'), caseOf('transfer', 'WARD-B'), null).headline).toBe(
      'Resend the PAS transfer to WARD-B, once, only if Downstream Out is still at version 1.',
    );
  });

  it('says a version the plan does not carry is not named, and never fills one in', () => {
    const w = planWords(
      planOf('transfer', { expectedVersion: '' }),
      caseOf('transfer', 'WARD-B'),
      snapshot(),
    );
    expect(w.headline).toBe(
      'Resend the PAS transfer to WARD-B, once, on a receiver version the plan does not name.',
    );
    expect(w.onlyIf[0]).toBe(
      'The receiver version the write is conditional on: unknown, the plan names none',
    );
    // The version the plan's own action carries counts as the plan's
    const inner = planOf('transfer', { expectedVersion: '', plan: { action: { expected_version: 3 } } });
    expect(planWords(inner, caseOf('transfer', 'WARD-B'), snapshot()).condition).toBe(
      'only if the bed-management system is still at version 3',
    );
  });
});

describe("the plan's own operation", () => {
  it("is the evidence's mapped operation of the plan's key, then the case's own", () => {
    const c = caseOf('transfer', 'WARD-B');
    const mapped = snapshot({
      operation: { operation_key: KEY('transfer'), event: 'transfer', ward: 'WARD-C', bed: 'BAY3-01' },
    });
    expect(planOperation(planOf('transfer'), c, mapped)).toMatchObject({
      event: 'transfer',
      ward: 'WARD-C',
      bed: 'BAY3-01',
      mapped: true,
    });
    expect(planOperation(planOf('transfer'), c, null)).toMatchObject({ ward: 'WARD-B', mapped: true });
  });

  it("names no destination for a plan whose key is neither the evidence's nor the case's", () => {
    const other = planOf('transfer', {
      operationKey: 'BEDMGR^HOSP^MRN9^ENC-9^transfer^2026-10-15T09:00:00Z',
    });
    const c = caseOf('transfer', 'WARD-B');
    expect(planOperation(other, c, null)).toEqual({
      key: 'BEDMGR^HOSP^MRN9^ENC-9^transfer^2026-10-15T09:00:00Z',
      sourceSystem: 'BEDMGR',
      encounterId: 'ENC-9',
      event: 'transfer',
      ward: '',
      bed: '',
      mapped: false,
    });
    // The case's ward is the case's operation's, not this plan's: the headline leaves it out
    expect(planWords(other, c, null).action).toBe('Resend the BEDMGR transfer, once');
  });

  it('is nothing for a plan with no key, or a key that is no operation key', () => {
    expect(planOperation(planOf('transfer', { operationKey: '' }), caseOf('transfer'), null)).toBeNull();
    expect(
      planOperation(planOf('transfer', { operationKey: 'UNMAPPED^7704' }), caseOf('transfer'), null),
    ).toBeNull();
  });
});

describe('the words on the buttons that decide', () => {
  it('names the resend, and the plan for one that writes nothing', () => {
    expect(decisionLabels({ disposition: 'resend' })).toEqual({
      noun: 'the resend',
      approve: 'Approve the resend',
      reject: 'Reject the resend',
      decide: 'Decide on the resend',
      nextAction: 'Approve or reject the resend',
    });
    expect(decisionLabels({ disposition: 'reconcile' }).approve).toBe('Approve the plan');
    // Only a write waits for an approval: a plan not read yet is named as the resend
    expect(decisionLabels(undefined).decide).toBe('Decide on the resend');
  });
});
