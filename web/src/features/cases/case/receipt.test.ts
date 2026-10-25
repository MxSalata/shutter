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
    expect(p.decidedBy).toBe('Approved by site policy (Automatic by site policy v9)');
  });

  it('reads a policy plan with no approval row from who made the plan, and counts an open case so far', () => {
    const c = {
      ...fixtures.cases['C-000021'].detail,
      state: 'executing',
      planCreatedBy: 'policy:E2',
    } as unknown as CaseDetail;
    const r = safetyReceipt({ c, plan: null, approvals: null, attempts: [], closure: null, snapshot: null });
    expect(r.action).toBe('No plan yet');
    expect(r.decidedBy).toBe('Site policy, entry E2');
    expect(r.status).toBe('0 writes so far; executing');
  });
});
