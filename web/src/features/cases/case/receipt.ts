import type {
  Approval,
  ApprovalsView,
  AttemptView,
  CaseDetail,
  Closure,
  PlanView,
  Snapshot,
} from '@/api/types';
import { humanize } from '@/lib/format';

/**
 * A case's safety receipt: what was proposed, what it was bound to, who or what let it through, how many writes the
 * receiver got and what the verifier found, in one record. Composed from what the case page already reads (the case,
 * its plan, approvals, attempts, closure and snapshot); kept apart from the card to be tested.
 */
export interface SafetyReceipt {
  caseId: string;
  state: string;
  mode: string;
  action: string;
  disposition: string;
  catalogueEntry: string;
  planVersion: number | null;
  planDigest: string;
  snapshotDigest: string;
  expectedVersion: string;
  receiverEpoch: string;
  gate: { stage: string; outcome: string; policyVersion: string } | null;
  /** Who let the write through: the approver, the site's policy, or why nobody needed to. */
  decidedBy: string;
  decidedAt: string;
  writes: number;
  /** Writes the receiver acknowledged (applied or already committed). */
  acknowledged: number;
  verification: string;
  /** One line that says where the case stands. */
  status: string;
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** The approval in force: the latest one that was not revoked. */
function approvalOf(view: ApprovalsView | null | undefined): Approval | undefined {
  return [...(view?.approvals ?? [])]
    .filter((a) => !a.revoked)
    .sort((a, b) => str(b.decidedAt).localeCompare(str(a.decidedAt)))[0];
}

function decider(
  c: CaseDetail,
  plan: PlanView | null | undefined,
  approval: Approval | undefined,
  writes: boolean,
): string {
  if (approval) {
    const who =
      approval.approver === 'policy'
        ? `site policy${approval.comment ? ` (${approval.comment})` : ''}`
        : approval.approver;
    return `${approval.decision === 'rejected' ? 'Rejected' : 'Approved'} by ${who}`;
  }
  const by = c.planCreatedBy ?? plan?.plan?.createdBy ?? '';
  if (by.startsWith('policy:')) return `Site policy, entry ${by.slice('policy:'.length)}`;
  if (!writes) return 'No approval needed: the plan writes nothing';
  return 'Not approved yet';
}

function statusOf(
  c: CaseDetail,
  writes: number,
  closure: Closure | null | undefined,
  verified: string,
): string {
  const prefix = `${writes} write${writes === 1 ? '' : 's'}`;
  if (c.disposition === 'handled_by_hand')
    return `${prefix}; handled by the team${closure?.outcome ? `: ${closure.outcome}` : ''}`;
  switch (c.state) {
    case 'escalated':
      return `${prefix}; waiting for a person`;
    case 'blocked':
      return `${prefix}; blocked, waiting for a person`;
    case 'failed':
      return `${prefix}; the workflow failed${closure?.outcome ? `: ${closure.outcome}` : ''}`;
    case 'resolved':
      return `${prefix}; ${verified || closure?.outcome || 'resolved'}`;
    default:
      return `${prefix} so far; ${humanize(c.state).toLowerCase()}`;
  }
}

export function safetyReceipt({
  c,
  plan,
  approvals,
  attempts,
  closure,
  snapshot,
}: {
  c: CaseDetail;
  plan: PlanView | null | undefined;
  approvals: ApprovalsView | null | undefined;
  attempts: AttemptView[] | null | undefined;
  closure: Closure | null | undefined;
  snapshot: Snapshot | null | undefined;
}): SafetyReceipt {
  const p = plan?.plan;
  const approval = approvalOf(approvals);
  const sent = (attempts ?? []).filter((x) => x.attempt);
  const acknowledged = sent.filter((x) => ['applied', 'already_committed'].includes(str(x.attempt?.outcome)));
  const last =
    [...(attempts ?? [])].reverse().find((x) => x.verification)?.verification ?? closure?.verification;
  const verification = last ? `${humanize(last.outcome)}${last.summary ? `: ${last.summary}` : ''}` : '';
  const decisions = plan?.gateDecisions ?? [];
  const gate = decisions.length ? decisions[decisions.length - 1] : undefined;
  const disposition = p?.disposition || c.disposition || '';
  const writes = disposition === 'resend';
  const target = `${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''}`;
  const action = !p
    ? 'No plan yet'
    : writes
      ? `Resend ${c.sourceSystem} ${target} unchanged, on condition the receiver is still at version ${str(p.expectedVersion)}`
      : `${humanize(disposition)}: no write to the receiver`;
  return {
    caseId: c.caseId,
    state: c.state,
    mode: c.mode,
    action,
    disposition,
    catalogueEntry: str(p?.catalogueEntry),
    planVersion: p ? Number(p.version) : null,
    planDigest: str(approval?.planDigest || p?.digest),
    snapshotDigest: str(approval?.snapshotDigest || snapshot?.digest),
    expectedVersion: writes ? str(approval?.expectedVersion ?? p?.expectedVersion) : '',
    receiverEpoch: str(approval?.receiverEpoch),
    gate: gate ? { stage: gate.stage, outcome: gate.outcome, policyVersion: gate.policyVersion } : null,
    decidedBy: decider(c, plan, approval, writes),
    decidedAt: str(approval?.decidedAt),
    writes: sent.length,
    acknowledged: acknowledged.length,
    verification,
    status: statusOf(c, sent.length, closure, last?.outcome === 'verified' ? 'verified at the receiver' : ''),
  };
}
