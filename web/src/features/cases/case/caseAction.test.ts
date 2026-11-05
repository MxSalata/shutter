import { describe, expect, it } from 'vitest';
import type {
  AgentRun,
  ApprovalsView,
  AttemptView,
  BlockedReason,
  CaseDetail,
  Closure,
  Escalation,
  Me,
  PlanView,
  Snapshot,
} from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { caseActionOf } from './caseAction';
import type { CaseFacts } from './outcome';
import { safetyReceipt } from './receipt';

type Id = keyof typeof fixtures.cases;

/** A recorded case's facts as the page reads them, its blocked reason flat as the hook returns it. */
function factsOf(id: Id, change: Partial<CaseFacts> & { state?: CaseDetail['state'] } = {}): CaseFacts {
  const x = fixtures.cases[id];
  const { state, ...rest } = change;
  const c = { ...(x.detail as unknown as CaseDetail), ...(state ? { state } : {}) };
  const raw = x.blockedReason as { code: string; catalogue: Record<string, string> } | null;
  const blocked: BlockedReason | null = raw
    ? {
        code: raw.code,
        title: raw.catalogue.title,
        prerequisite: raw.catalogue.prerequisite,
        nextAction: raw.catalogue.nextAction,
        owner: raw.catalogue.owner,
        reevaluateWhen: raw.catalogue.reevaluateWhen,
        text: raw.catalogue.text,
        checks: [],
      }
    : null;
  const base = {
    c,
    plan: x.plan as unknown as PlanView,
    approvals: x.approvals as unknown as ApprovalsView,
    attempts: x.attempts as unknown as AttemptView[],
    blocked,
    snapshot: x.snapshot as unknown as Snapshot,
    escalations: [] as Escalation[],
    runs: x.runs as unknown as AgentRun[],
    ...rest,
  };
  return {
    ...base,
    receipt: safetyReceipt({ ...base, closure: x.closure as unknown as Closure }),
  };
}

const ME: Record<string, Me> = {
  operator: { username: 'operator', operator: true, approver: false, can: { operate: true, approve: false } },
  approver: { username: 'approver', operator: true, approver: true, can: { operate: true, approve: true } },
  demo: {
    username: 'demo',
    operator: true,
    approver: true,
    can: { operate: true, approve: true, configure: false },
  },
  reader: { username: 'reader', operator: false, approver: false },
};

const sent = { seq: 1, state: 'sent' } as Escalation;

describe("the case's action for its reader", () => {
  it('asks an approver, and the public demo, to decide on a resend waiting for approval; an operator waits', () => {
    const f = factsOf('C-000002', { state: 'awaiting_approval' });
    for (const who of ['approver', 'demo'])
      expect(caseActionOf(f, { me: ME[who] })).toEqual({
        needsYou: true,
        label: 'Decide on the resend',
        short: 'Needs you',
        name: 'Needs you: decide on the resend',
        goes: 'approval',
      });
    expect(caseActionOf(f, { me: ME.operator })).toEqual({
      needsYou: false,
      label: 'Waiting for an approver',
      short: 'No action',
      name: 'No action for you: waiting for an approver',
    });
  });

  it('waits for an approver while the user is not read yet, never claiming the action', () => {
    expect(
      caseActionOf(factsOf('C-000002', { state: 'awaiting_approval' }), { me: undefined }).needsYou,
    ).toBe(false);
  });

  it('asks an operator to escalate an escalated case, then to mark it handled once the email went out', () => {
    const f = factsOf('C-000008');
    expect(caseActionOf(f, { me: ME.operator })).toMatchObject({
      needsYou: true,
      label: 'Escalate to a team',
      goes: 'escalations',
    });
    const after = factsOf('C-000008', { escalations: [sent] });
    expect(caseActionOf(after, { me: ME.approver })).toMatchObject({
      needsYou: true,
      label: 'Mark as handled',
      name: 'Needs you: mark as handled',
      goes: 'escalations',
    });
    // With the two-person rule an operator waits for an approver to close it; without it, the operator closes it
    expect(caseActionOf(after, { me: ME.operator, closeNeedsApprover: true })).toEqual({
      needsYou: false,
      label: 'Waiting for an approver',
      short: 'No action',
      name: 'No action for you: waiting for an approver to mark it handled',
    });
    expect(caseActionOf(after, { me: ME.operator, closeNeedsApprover: false }).label).toBe('Mark as handled');
  });

  it('asks to mark a withheld case handled at once, and a case with a later draft after the sent email', () => {
    // C-000012 is S15's withheld merge: the team closes it, with no email first (the Escalations panel's rule)
    expect(caseActionOf(factsOf('C-000012'), { me: ME.approver })).toMatchObject({
      needsYou: true,
      label: 'Mark as handled',
    });
    expect(caseActionOf(factsOf('C-000012'), { me: ME.operator, closeNeedsApprover: false }).label).toBe(
      'Mark as handled',
    );
    const draftAfter = factsOf('C-000008', {
      escalations: [sent, { seq: 2, state: 'draft' } as Escalation],
    });
    expect(caseActionOf(draftAfter, { me: ME.approver }).label).toBe('Mark as handled');
  });

  it("escalates S25's blocked message, whose next action says to escalate otherwise", () => {
    expect(caseActionOf(factsOf('C-000064'), { me: ME.approver })).toMatchObject({
      needsYou: true,
      label: 'Escalate to a team',
    });
  });

  it("asks for the next step on a block whose action is not an escalation (S20's superseded plan)", () => {
    expect(caseActionOf(factsOf('C-000053'), { me: ME.operator })).toMatchObject({
      needsYou: true,
      label: 'Decide the next step',
    });
  });

  it('leaves a stopped case to an operator when the user cannot operate', () => {
    expect(caseActionOf(factsOf('C-000008'), { me: ME.reader })).toEqual({
      needsYou: false,
      label: 'Waiting for an operator',
      short: 'No action',
      name: 'No action for you: waiting for an operator',
    });
  });

  it('asks for a reinvestigation of a failed case, except in the trial, which has no real model', () => {
    const f = factsOf('C-000008', { state: 'failed' });
    expect(caseActionOf(f, { me: ME.operator })).toMatchObject({ needsYou: true, label: 'Reinvestigate' });
    expect(caseActionOf(f, { me: ME.operator, trial: true })).toEqual({
      needsYou: false,
      label: 'Reinvestigate',
      short: 'No action',
      name: 'No action for you: reinvestigate needs a real model, not in the trial',
    });
  });

  it('needs nothing of anyone on a closed case, a running one, an abandoned one or one handled by hand', () => {
    expect(caseActionOf(factsOf('C-000058'), { me: ME.approver })).toEqual({
      needsYou: false,
      label: 'No action needed',
      short: 'No action',
      name: 'No action needed on this case',
    });
    expect(caseActionOf(factsOf('C-000002', { state: 'rehearsing' }), { me: ME.approver }).name).toBe(
      'No action needed on this case: Shutter is rehearsing',
    );
    for (const disposition of ['abandoned', 'handled_by_hand']) {
      const f = factsOf('C-000008');
      expect(caseActionOf({ ...f, c: { ...f.c, disposition } }, { me: ME.approver }).label).toBe(
        'No action needed',
      );
    }
  });

  it("offers S8's two runs, never all clear, on a closed case its scenario doesn't expect", () => {
    expect(caseActionOf(factsOf('C-000021'), { me: ME.approver, notAsExpected: true })).toEqual({
      needsYou: false,
      label: 'Compare the two runs',
      short: 'Compare',
      name: 'Not the expected outcome: compare the two runs',
      goes: 'compare',
      differs: true,
    });
    // Another scenario has no second run to compare with
    const f = factsOf('C-000021');
    const other = caseActionOf(
      { ...f, c: { ...f.c, scenario: 'S3' } },
      { me: ME.approver, notAsExpected: true },
    );
    expect(other).toMatchObject({ label: 'See what differs', differs: true });
    expect(other.goes).toBeUndefined();
    // Without the scenario's word the same case keeps the plain answer
    expect(caseActionOf(factsOf('C-000021'), { me: ME.approver }).label).toBe('No action needed');
  });
});
