import { describe, expect, it } from 'vitest';
import type { ApprovalsView, AttemptView, CaseDetail, Closure, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { safetyReceipt } from './receipt';

type Recorded = (typeof fixtures.cases)[keyof typeof fixtures.cases];

function receiptOf(id: keyof typeof fixtures.cases) {
  const x = fixtures.cases[id] as Recorded;
  return safetyReceipt({
    c: x.detail as unknown as CaseDetail,
    plan: x.plan as unknown as PlanView,
    approvals: x.approvals as unknown as ApprovalsView,
    attempts: x.attempts as unknown as AttemptView[],
    closure: x.closure as unknown as Closure,
    snapshot: x.snapshot as unknown as Snapshot,
  });
}

describe('safetyReceipt', () => {
  it("records the rules case's approved write and its verification", () => {
    const r = receiptOf('C-000021');
    expect(r.action).toMatch(/^Resend PAS transfer to WARD-B unchanged, on condition .* version 2$/);
    expect(r.planDigest).toBe(fixtures.cases['C-000021'].plan.plan.digest);
    expect(r.snapshotDigest).toBe(fixtures.cases['C-000021'].snapshot.digest);
    expect(r.expectedVersion).toBe('2');
    expect(r.receiverEpoch).toBe('227');
    expect(r.gate).toMatchObject({ outcome: 'pass', policyVersion: '2026-10-20.1' });
    expect(r.decidedBy).toBe('Approved by approver');
    expect(r.writes).toBe(1);
    expect(r.acknowledged).toBe(1);
    expect(r.verification).toMatch(/^Verified: Committed and current/);
    expect(r.status).toBe('1 write; verified at the receiver');
  });

  it('says an escalated case wrote nothing and waits for a person', () => {
    const r = receiptOf('C-000008');
    expect(r.action).toBe('Escalate: no write to the receiver');
    expect(r.catalogueEntry).toBe('E7');
    expect(r.decidedBy).toBe('No approval needed: the plan writes nothing');
    expect(r.writes).toBe(0);
    expect(r.expectedVersion).toBe('');
    expect(r.status).toBe('0 writes; waiting for a person');
    expect(r.verification).toBe('Not applicable: no Shutter write');
  });

  it('names the site policy when it released the write', () => {
    const r = receiptOf('C-000002');
    const base = fixtures.cases['C-000002'];
    const approvals = {
      ...base.approvals,
      approvals: base.approvals.approvals.map((a) => ({
        ...a,
        approver: 'policy',
        comment: 'Automatic by site policy v9',
      })),
    };
    const p = safetyReceipt({
      c: base.detail as unknown as CaseDetail,
      plan: base.plan as unknown as PlanView,
      approvals: approvals as unknown as ApprovalsView,
      attempts: base.attempts as unknown as AttemptView[],
      closure: base.closure as unknown as Closure,
      snapshot: base.snapshot as unknown as Snapshot,
    });
    expect(r.decidedBy).toMatch(/^Approved by /);
    expect(p.decidedBy).toBe("Released by the site's written policy (Automatic by site policy v9)");
  });

  it('reads a policy plan with no approval row from who made the plan, and counts an open case so far', () => {
    const c = {
      ...fixtures.cases['C-000021'].detail,
      state: 'executing',
      planCreatedBy: 'policy:E2',
    } as unknown as CaseDetail;
    const r = safetyReceipt({ c, plan: null, approvals: null, attempts: [], closure: null, snapshot: null });
    expect(r.action).toBe('No plan yet');
    expect(r.decidedBy).toBe("The site's written policy, entry E2");
    expect(r.status).toBe('0 writes so far; executing');
  });
  it('names a revoked approval, and counts only attempts that reached the receiver as writes', () => {
    const base = fixtures.cases['C-000021'];
    const c = { ...base.detail, state: 'escalated' } as unknown as CaseDetail;
    const approvals = {
      ...base.approvals,
      approvals: base.approvals.approvals.map((a) => ({ ...a, revoked: true, revokedBy: 'system' })),
    } as unknown as ApprovalsView;
    const attempt = (outcome: string) =>
      ({ attempt: { ...base.attempts[0].attempt, outcome }, verification: null }) as unknown as AttemptView;
    const r = safetyReceipt({
      c,
      plan: base.plan as unknown as PlanView,
      approvals,
      attempts: [attempt('error'), attempt('version_conflict'), attempt('uncertain')],
      closure: null,
      snapshot: base.snapshot as unknown as Snapshot,
    });
    expect(r.decidedBy).toBe('Approved by approver (since revoked by system)');
    expect(r.planDigest).toBe(base.approvals.approvals[0].planDigest);
    expect(r.writes).toBe(1);
    expect(r.acknowledged).toBe(0);
    expect(r.notWritten).toBe(2);
    expect(r.status).toBe('1 write; waiting for a person');
  });

  it('says nobody let a blocked write plan through', () => {
    const base = fixtures.cases['C-000021'];
    const c = { ...base.detail, state: 'blocked', planCreatedBy: '' } as unknown as CaseDetail;
    const attempt = { attempt: { ...base.attempts[0].attempt, outcome: 'error' }, verification: null };
    const r = safetyReceipt({
      c,
      plan: base.plan as unknown as PlanView,
      approvals: { approvals: [], tasks: [] },
      attempts: [attempt as unknown as AttemptView],
      closure: null,
      snapshot: null,
    });
    expect(r.decidedBy).toBe('Nobody: the gate blocked it');
    expect(r.writes).toBe(0);
    expect(r.status).toBe('0 writes; blocked, waiting for a person');
  });
});
