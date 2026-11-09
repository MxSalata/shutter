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
import { caseOutcome } from '@/lib/status';
import {
  actionHead,
  actionHeadline,
  decisionSummary,
  evidenceSummary,
  failedSummary,
  failedTitle,
  headerSentence,
  nextAction,
  outcomeCaseOf,
  outcomeReason,
  proposedSummary,
  provenanceOf,
  recordedApprovalTime,
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

const outcomeOf = (f: CaseFacts) => caseOutcome(outcomeCaseOf(f));

describe('the outcome sentence', () => {
  it('reads S2 as delivered and verified, and says what Shutter did, leading with the action', () => {
    const f = factsOf('C-000002');
    expect(outcomeOf(f)).toMatchObject({ key: 'delivered', label: 'Delivered: verified at the receiver' });
    expect(actionHeadline(f)).toBe('Sent the transfer again, once, after a test run');
    expect(outcomeReason(f)).toBe(
      'Transfer to WARD-B applied at the receiver, version 1 to 2; the verifier found the effect there.',
    );
    expect(nextAction(f)).toMatchObject({ kind: 'none', action: 'No pending action' });
  });

  it('reads S8 on the board as escalated with no write, and names the two systems at the same time', () => {
    const f = factsOf('C-000008');
    expect(outcomeOf(f).label).toBe('Escalated: a person decides');
    expect(actionHeadline(f)).toBe('Asked a person to decide; sent nothing');
    expect(outcomeReason(f)).toBe(
      "Handed to a person; PAS and the bed manager (BEDMGR) moved the encounter at the same event time, so the times can't say which movement is current.",
    );
    const next = nextAction(f);
    expect(next).toMatchObject({ kind: 'person', role: 'Operator' });
    expect(next.handoff).toBe('Not sent');
    expect(next.escalate).toBe(true);
    // S20's next step is to close the case as superseded, not to escalate it
    expect(nextAction(factsOf('C-000053')).escalate).toBe(false);
  });

  it('never guesses that nothing was sent while the attempts are not read', () => {
    for (const state of ['escalated', 'blocked', 'failed'] as const) {
      const f = factsOf('C-000008', { attempts: undefined });
      const sentence = actionHeadline({ ...f, c: { ...f.c, state } });
      expect(sentence).toContain('what it sent is not read yet');
      expect(sentence).not.toMatch(/sent nothing/i);
    }
  });

  it('asks for a reinvestigation of a failed case, and nothing of an abandoned one, which was given up on purpose', () => {
    const f = factsOf('C-000008');
    const failed = { ...f, c: { ...f.c, state: 'failed' as const } };
    expect(nextAction(failed)).toMatchObject({
      kind: 'person',
      action: 'Reinvestigate once the cause is fixed, or leave the case closed',
      role: 'Operator',
      blocking: 'The workflow failed',
    });
    const abandoned = { ...failed, c: { ...failed.c, disposition: 'abandoned' as const } };
    expect(nextAction(abandoned)).toMatchObject({
      kind: 'none',
      action: 'No pending action: the case was abandoned',
      role: '',
      escalate: false,
    });
  });

  it('says whether the hand-off went out', () => {
    const sent = { seq: 1, state: 'sent', teamName: 'Integration team' } as Escalation;
    expect(nextAction(factsOf('C-000008', { escalations: [sent] })).handoff).toBe('Sent to Integration team');
    expect(nextAction(factsOf('C-000008', { escalations: undefined })).handoff).toBe('Unknown');
    // Saved as an email file with no mail server: nobody was emailed, and the line never reads Sent
    const saved = { seq: 1, state: 'saved', teamName: 'Integration team' } as Escalation;
    expect(nextAction(factsOf('C-000008', { escalations: [saved] })).handoff).toBe(
      'Saved as an email file for Integration team, not delivered',
    );
    const queued = { ...saved, state: 'queued' } as Escalation;
    expect(nextAction(factsOf('C-000008', { escalations: [queued] })).handoff).toBe(
      'Queued to Integration team',
    );
  });

  it('says in words that the gate blocked a rules case, leaving its reason code to the details', () => {
    const f = factsOf('C-000053');
    expect(outcomeOf(f).label).toBe('Blocked: nothing sent');
    expect(actionHeadline(f)).toBe('Sent nothing: the gate stopped the plan');
    expect(outcomeReason(f)).toBe('Blocked by the gate: a later event made this movement obsolete.');
  });

  it('says writes are unknown, never 0, while the attempts are not read', () => {
    const f = factsOf('C-000002', { attempts: undefined });
    // Nothing guessed: the outcome stays "Resolved" and the action says the writes are not read
    expect(outcomeCaseOf(f).writes).toBeUndefined();
    expect(outcomeOf(f).key).toBe('resolved');
    expect(actionHeadline(f)).toBe('Closed the case; what it sent is not read yet');
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
    expect(outcomeOf(f).label).toBe('Handled by hand');
    expect(actionHeadline(f)).toBe('Handed it to the team, who corrected it by hand');
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
    expect(outcomeOf(f).label).toBe('Waiting for approval');
    expect(actionHeadline(f)).toBe('Tested the fix at the receiver; sent nothing yet');
    expect(nextAction(f)).toMatchObject({
      kind: 'person',
      role: 'Approver',
      action: 'Approve or reject plan v1',
    });
    expect(releaseStatus(f)?.label).toBe('Waiting for approval');
  });
});

describe('what Shutter did, by outcome', () => {
  it('says a superseded case sent nothing because a later event moved the patient on', () => {
    const f = factsOf('C-000007');
    expect(actionHeadline(f)).toBe('Sent nothing: a later event already moved the patient on');
    expect(outcomeOf(f).label).toBe('Nothing to send: verified at the receiver');
  });

  it("reads rules alone's S8 write as not as expected with S8's expectation, and delivered without it", () => {
    const f = factsOf('C-000021');
    const s8 = fixtures.scenarios.find((s) => s.id === 'S8') as unknown as Parameters<typeof caseOutcome>[1];
    expect(caseOutcome(outcomeCaseOf(f), s8)).toMatchObject({
      key: 'not-as-expected',
      tone: 'blocking',
      label: 'Not the expected outcome: S8 expects escalate',
    });
    expect(outcomeOf(f).key).toBe('delivered');
  });

  it('counts only a verifier outcome as a verification', () => {
    expect(outcomeCaseOf(factsOf('C-000008'))).toMatchObject({ writes: 0, verification: '' });
    expect(outcomeCaseOf(factsOf('C-000002'))).toMatchObject({ writes: 1, verification: 'verified' });
  });

  it('names when the recorded case was approved, for the note after a replay in the trial', () => {
    expect(recordedApprovalTime(fixtures.cases['C-000002'].events as never)).toBe('2 Nov, 14:16 UTC');
    expect(recordedApprovalTime(fixtures.cases['C-000008'].events as never)).toBe('');
    expect(recordedApprovalTime(undefined)).toBe('');
  });
});

describe("the story steps' summaries", () => {
  it('says what failed', () => {
    expect(failedSummary(factsOf('C-000008').c)).toBe(
      'PAS transfer to WARD-B was not delivered: HTTP 503, ward_unavailable.',
    );
  });

  it('gives no reason code for a withheld message, which was never sent', () => {
    expect(failedSummary(factsOf('C-000012').c)).toBe('PAS merge was withheld, never sent.');
  });

  it('says what the receiver holds and that it has no receipt', () => {
    expect(evidenceSummary(factsOf('C-000008').snapshot)).toBe(
      'When Shutter looked, the receiver held the encounter admitted in WARD-C at version 2; no receipt for this operation; PAS and BEDMGR have the same event time.',
    );
    expect(evidenceSummary(null)).toBe('No evidence yet.');
  });

  it('says who proposed what, with the dissent kept', () => {
    expect(proposedSummary(factsOf('C-000008'))).toBe(
      'The coordinator: escalate without writing; Conformance dissented, proposing resend (kept in the plan).',
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

  it("names the leader's board on a plan a follower took from it, not the plan's raw author", () => {
    const plan = factsOf('C-000008').plan!;
    const followed = factsOf('C-000008', {
      plan: { ...plan, plan: { ...plan.plan, createdBy: 'lead:C-000007' } },
      runs: [],
    });
    expect(proposedSummary(followed)).toMatch(/^The board of case C-000007: /);
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

describe("the next action's head and rest", () => {
  it('keeps an action of up to 16 words whole', () => {
    const text = "Read the findings and the gate's notes, then decide how to recover the message by hand.";
    expect(actionHead(text)).toEqual({ head: text, rest: '' });
  });

  it("cuts a longer one after its first sentence, as S25's parse failure", () => {
    const text = fixtures.cases['C-000064'].blockedReason!.catalogue.nextAction;
    const { head, rest } = actionHead(text);
    expect(head).toBe("Read the gate's words.");
    expect(`${head} ${rest}`).toBe(text);
  });

  it('cuts a long first sentence at its first semicolon or colon, dropping no word', () => {
    const text =
      'Hand the merge to the PAS team named for the sending application; mark the case handled when it confirms what it did.';
    expect(actionHead(text)).toEqual({
      head: 'Hand the merge to the PAS team named for the sending application',
      rest: 'Mark the case handled when it confirms what it did.',
    });
  });
});

describe('an order or a result, and a message resent with its outage', () => {
  const result = (more: Partial<CaseDetail> = {}): CaseFacts => {
    const f = factsOf('C-000002');
    return {
      ...f,
      c: {
        ...f.c,
        event: 'r01',
        ward: 'WARD-A',
        bed: 'BAY1-01',
        sourceSystem: 'QUILLON',
        failureKind: 'unmappable',
        failureOutcome: 'error',
        failureHttpStatus: undefined,
        failureReasonCode: 'alert',
        failureText: 'This message is ORU, not ADT: a person decides',
        ...more,
      } as CaseDetail,
    };
  };

  it('names a result as a result, going to no ward', () => {
    const { c } = result();
    expect(headerSentence(c)).toBe('The QUILLON result was not delivered: alert.');
    expect(failedSummary(c)).toBe('QUILLON result was not delivered: alert.');
    expect(failedTitle(c)).toBe('Result was not delivered');
  });

  it('says what the outage resend did: who approved it, what the engine sent, and how it ended', () => {
    const words = 'Resent by Shutter at 19:18 under approval R8-3 by appr1; new header 481 Completed.';
    const f = result({
      state: 'resolved',
      disposition: 'escalate',
      resends: [{ runId: 'R8-3', position: 3, state: 'completed', closure: 'sent', words, headerId: '444' }],
    });
    expect(actionHeadline(f)).toBe('Resent it through the engine with the outage, under approval R8-3');
    expect(writtenSummary(f)).toBe(
      'Resent by Shutter at 19:18 under approval R8-3 by appr1; new header 481 Completed; the engine sent the stored message unchanged.',
    );
    expect(releaseStatus(f)?.label).toBe('Approved on the outage (R8-3)');
    // A hand closure is no resend
    const byHand = result({
      state: 'resolved',
      resends: [{ runId: 'H8', position: 0, state: 'handled_by_hand', closure: 'handled_by_hand' }],
    });
    expect(writtenSummary(byHand)).not.toMatch(/Resent/);
  });
});
