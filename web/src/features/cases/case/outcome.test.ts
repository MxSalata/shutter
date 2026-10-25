import { describe, expect, it } from 'vitest';
import type {
  AgentRun,
  ApprovalsView,
  AttemptView,
  BlockedReason,
  CaseDetail,
  Closure,
  Escalation,
  PlanView,
  Snapshot,
} from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  decisionSummary,
  evidenceSummary,
  failedSummary,
  nextAction,
  outcomeHeadline,
  outcomeReason,
  proposedSummary,
  provenanceOf,
  releaseStatus,
  verifiedSummary,
  writtenSummary,
  type CaseFacts,
} from './outcome';
import { safetyReceipt } from './receipt';

type Id = keyof typeof fixtures.cases;

/** A recorded case's facts as the page reads them; the blocked reason in the flat shape the hook returns. */
function factsOf(id: Id, change: Partial<CaseFacts> = {}): CaseFacts {
  const x = fixtures.cases[id];
  const c = x.detail as unknown as CaseDetail;
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
    ...change,
  };
  return {
    ...base,
    receipt: safetyReceipt({
      c: base.c,
      plan: base.plan,
      approvals: base.approvals,
      attempts: base.attempts,
      closure: x.closure as unknown as Closure,
      snapshot: base.snapshot,
    }),
  };
}

describe('the outcome sentence', () => {
  it('reads S2 as resolved with one write verified at the receiver', () => {
    const f = factsOf('C-000002');
    expect(outcomeHeadline(f)).toBe('Resolved · 1 write · Effect verified at the receiver');
    expect(outcomeReason(f)).toBe(
      'Transfer to WARD-B applied at the receiver, version 1 to 2; the verifier found the effect there.',
    );
    expect(nextAction(f)).toMatchObject({ kind: 'none', action: 'No pending action' });
  });

  it('reads S8 on the board as escalated with no write, and names the two systems at the same time', () => {
    const f = factsOf('C-000008');
    expect(outcomeHeadline(f)).toBe('Escalated · 0 writes');
    expect(outcomeReason(f)).toBe(
      "Handed to a person; PAS and BEDMGR moved the encounter at the same event time, so which movement is current can't be told from the times.",
    );
    const next = nextAction(f);
    expect(next).toMatchObject({ kind: 'person', role: 'Operator' });
    expect(next.handoff).toBe('Escalation: not sent');
    expect(next.escalate).toBe(true);
    // S20's next step is to close the case as superseded, not to escalate it
    expect(nextAction(factsOf('C-000053')).escalate).toBe(false);
  });

  it('says whether the hand-off went out', () => {
    const sent = { seq: 1, state: 'sent', teamName: 'Integration team' } as Escalation;
    expect(nextAction(factsOf('C-000008', { escalations: [sent] })).handoff).toBe(
      'Escalation 1 sent to Integration team',
    );
    expect(nextAction(factsOf('C-000008', { escalations: undefined })).handoff).toBe('Unknown');
  });

  it('says in words that the gate blocked a rules case, leaving its reason code to the details', () => {
    const f = factsOf('C-000053');
    expect(outcomeHeadline(f)).toBe('Blocked · 0 writes');
    expect(outcomeReason(f)).toBe('Blocked by the gate: a later event made this movement obsolete.');
  });

  it('says writes are unknown, never 0, while the attempts are not read', () => {
    const f = factsOf('C-000002', { attempts: undefined });
    expect(outcomeHeadline(f)).toMatch(/^Resolved · Writes unknown/);
    expect(writtenSummary(f)).toBe('Unknown: the attempts are not read yet.');
  });

  it('says the reason is not read yet rather than inventing one', () => {
    const f = factsOf('C-000008', { blocked: undefined });
    expect(outcomeReason(f)).toMatch(/^Reason not read yet/);
    expect(nextAction(f)).toMatchObject({ action: 'Not read yet', role: 'Not read yet' });
  });

  it('reads a hand closure as closed with no Shutter write and the correction not verified by Shutter', () => {
    const recorded = factsOf('C-000053');
    const f = factsOf('C-000053', {
      c: { ...recorded.c, state: 'resolved', disposition: 'handled_by_hand' },
      approvals: {
        approvals: [{ ...recorded.approvals!.approvals[0], revoked: true, revokedBy: 'system' }],
        tasks: [],
      },
    });
    expect(outcomeHeadline(f)).toBe('Closed · Handled by hand · 0 Shutter writes · Not verified by Shutter');
    expect(outcomeReason(f)).toBe(
      'The team corrected the systems by hand and a person closed the case; an earlier approval was revoked by system; the latest plan was blocked by the gate at proposal; Shutter did not verify the correction.',
    );
    expect(nextAction(f).action).toBe('No pending action');
    // The revoked approval is plan v1's, not the latest plan's: it is history, not the release
    expect(releaseStatus(f)).toBeUndefined();
    expect(f.receipt.decidedBy).toBe('The team, by hand');
  });

  it("does not read a gate's unknown result on a hand closure as blocked", () => {
    const recorded = factsOf('C-000053');
    const plan = recorded.plan!;
    const f = factsOf('C-000053', {
      c: { ...recorded.c, state: 'resolved', disposition: 'handled_by_hand' },
      plan: { ...plan, gateDecisions: plan.gateDecisions.map((d) => ({ ...d, outcome: 'unknown' })) },
    });
    expect(outcomeReason(f)).not.toMatch(/blocked by the gate/);
    expect(outcomeReason(f)).toMatch(/the gate's result on the latest plan at proposal was unknown/);
  });

  it("names only the current plan's approval as the release, and an earlier plan's as history", () => {
    // S7: plan v1 approved, the approval revoked when the receiver changed, plan v2 supersedes and writes nothing
    const s7 = factsOf('C-000007');
    expect(releaseStatus(s7)?.label).toBe('Not required');
    expect(s7.receipt.decidedBy).toBe('No approval needed: the plan writes nothing');
    expect(s7.receipt.planDigest).toBe(s7.plan!.plan.digest);
    expect(decisionSummary(s7)).toMatch(
      /; earlier approval of plan v1 revoked by system: the receiver changed before dispatch\.$/,
    );
    // S20 and S7 on rules: the gate blocked plan v2, which nobody released
    for (const id of ['C-000053', 'C-000020'] as const) {
      const f = factsOf(id);
      expect(releaseStatus(f)).toBeUndefined();
      expect(f.receipt.decidedBy).toBe('Nobody: the gate blocked it');
      expect(decisionSummary(f)).not.toMatch(/approved by/);
      expect(decisionSummary(f)).toMatch(/nobody: the gate blocked it; earlier approval of plan v1 revoked/);
    }
  });

  it('says who released a write is unknown while the approvals are not read', () => {
    const f = factsOf('C-000021', { approvals: undefined });
    expect(f.receipt.decidedBy).toBe('Unknown');
    expect(releaseStatus(f)).toBeUndefined();
    expect(decisionSummary(f)).toMatch(/; who released it is unknown\.$/);
  });

  it('names the approver role while a write waits for release', () => {
    const recorded = factsOf('C-000002');
    const f = factsOf('C-000002', {
      c: { ...recorded.c, state: 'awaiting_approval' },
      approvals: { approvals: [], tasks: [] },
      attempts: [],
    });
    expect(outcomeHeadline(f)).toBe('Waiting for approval · 0 writes');
    expect(nextAction(f)).toMatchObject({
      kind: 'person',
      role: 'Approver',
      action: 'Approve or reject plan v1',
    });
    expect(releaseStatus(f)?.label).toBe('Waiting for approval');
  });
});

describe("the story steps' summaries", () => {
  it('says what failed', () => {
    expect(failedSummary(factsOf('C-000008').c)).toBe(
      'PAS transfer to WARD-B was not delivered: HTTP 503, ward_unavailable.',
    );
  });

  it('says what the receiver holds and that it has no receipt', () => {
    expect(evidenceSummary(factsOf('C-000008').snapshot)).toBe(
      'The receiver holds the encounter admitted in WARD-C at version 2; no receipt for this operation; PAS and BEDMGR have the same event time.',
    );
    expect(evidenceSummary(null)).toBe('No evidence yet.');
  });

  it('says who proposed what, with the dissent kept', () => {
    expect(proposedSummary(factsOf('C-000008'))).toBe(
      'The coordinator: escalate without writing; 1 specialist dissent kept.',
    );
    expect(proposedSummary(factsOf('C-000021'))).toBe(
      'The rules: resend the operation unchanged, on condition the receiver is at version 2.',
    );
  });

  it('says nobody proposed a write on a withheld case, and unknown for a run not read', () => {
    const plan = factsOf('C-000008').plan!;
    const withheld = factsOf('C-000008', {
      plan: { ...plan, plan: { ...plan.plan, createdBy: 'withheld' } },
      runs: [],
    });
    expect(proposedSummary(withheld)).toBe(
      'Nobody proposed a write: Shutter withholds merges and cancels; a person decides.',
    );
    const unread = factsOf('C-000008', {
      plan: { ...plan, plan: { ...plan.plan, createdBy: 'run:12' } },
      runs: undefined,
    });
    expect(proposedSummary(unread)).toMatch(/^Unknown: /);
  });

  it('says the gate and the release apart', () => {
    expect(decisionSummary(factsOf('C-000008'))).toMatch(
      /^Gate passed \d+ of \d+ applicable checks at proposal; no approval needed: the plan writes nothing\.$/,
    );
    expect(decisionSummary(factsOf('C-000021'))).toMatch(/; approved by approver\.$/);
  });

  it('says what was written and verified', () => {
    expect(writtenSummary(factsOf('C-000008'))).toBe('0 writes by Shutter.');
    expect(writtenSummary(factsOf('C-000021'))).toBe(
      '1 conditional write, 1 acknowledged, receiver version 2 to 3.',
    );
    expect(verifiedSummary(factsOf('C-000008'))).toBe('Not applicable: no Shutter write.');
  });
});

describe('provenance', () => {
  it('tells rules, replays and live runs apart', () => {
    expect(provenanceOf('rules', []).label).toBe('Rules only');
    expect(provenanceOf('board', factsOf('C-000008').runs).label).toBe('Recorded replay');
    expect(provenanceOf('board', [{ mode: 'live' } as AgentRun]).label).toBe('Live model');
    expect(provenanceOf('board', undefined).label).toBe('Unknown');
    expect(provenanceOf('policy', []).label).toBe("No model: the site's policy");
  });
});
