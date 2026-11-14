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
import { asObject } from '@/lib/json';
import { fhirSummary, receiverKind } from './derive';

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
  /** Who let the current plan's write through: the approver, the site's policy, or why nobody needed to. */
  decidedBy: string;
  /** An earlier plan's approval, as history; empty when there is none. */
  earlierApproval: string;
  decidedAt: string;
  /** Writes that reached the receiver and may have landed: applied, already committed or uncertain. */
  writes: number;
  /** Writes the receiver acknowledged (applied or already committed). */
  acknowledged: number;
  /** Attempts that wrote nothing: refused by the receiver, a version conflict, or an error before sending. */
  notWritten: number;
  verification: string;
  /**
   * The verification as a state of lib/status's VERIFICATIONS: the verifier's outcome, pending after a write, by_hand
   * for a hand correction, not_applicable when there is no write of Shutter's; empty when none of these is known yet.
   */
  verificationState: string;
  /** One line that says where the case stands. */
  status: string;
  /** Set only on a FHIR case ("fhir_r4"): expectedVersion then holds the Encounter's ETag as read, verbatim. */
  receiverKind?: 'fhir_r4';
}

/** What a FHIR case's plan does, in place of a resend: the HL7 message is not sent again. */
export const FHIR_PROPOSAL =
  "Update the Encounter's location once, by another route than the original HL7 delivery";

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** Attempt outcomes where the write reached the receiver and may have landed (CONTRACTS, the attempt). */
export const WRITE_OUTCOMES = ['applied', 'already_committed', 'uncertain'];

/** Case states that stop a case: with no write sent by then, there is no write of Shutter's to verify. */
export const STOPPED_STATES = ['blocked', 'failed', 'escalated'];

/**
 * A case's approvals split by plan: those of the current plan, which can be its release, and those of earlier plans,
 * which are history (a re-plan revokes the earlier plan's approval). With no plan read, every approval counts as the
 * current plan's.
 */
export function approvalsByPlan(
  view: ApprovalsView | null | undefined,
  plan: PlanView | null | undefined,
): { current: Approval[]; earlier: Approval[] } {
  const all = view?.approvals ?? [];
  const digest = plan?.plan?.digest;
  if (!digest) return { current: all, earlier: [] };
  return {
    current: all.filter((a) => !a.planDigest || a.planDigest === digest),
    earlier: all.filter((a) => a.planDigest && a.planDigest !== digest),
  };
}

/**
 * The approval the receipt names, from the current plan's: the latest one in force, else the latest revoked one (the
 * server revokes an approval once its write is spent or not committed, and on a reopen, so a written case's approval
 * is often revoked).
 */
function approvalOf(current: Approval[]): Approval | undefined {
  const latest = [...current].sort((a, b) => str(b.decidedAt).localeCompare(str(a.decidedAt)));
  return latest.find((a) => !a.revoked) ?? latest[0];
}

/** An earlier plan's approval as history: "Earlier approval of plan v1 revoked by system: the receiver changed". */
export function earlierApprovalText(earlier: Approval[], plan: PlanView | null | undefined): string {
  const a = [...earlier].sort((x, y) => str(y.decidedAt).localeCompare(str(x.decidedAt)))[0];
  if (!a) return '';
  // Only a second plan has a single earlier one whose version is known
  const which = Number(plan?.plan?.version) === 2 ? 'plan v1' : 'an earlier plan';
  const verb = a.decision === 'rejected' ? 'Earlier rejection' : 'Earlier approval';
  return a.revoked
    ? `${verb} of ${which} revoked${a.revokedBy ? ` by ${a.revokedBy}` : ''}`
    : `${verb} of ${which}, not of the current plan`;
}

function decider(
  c: CaseDetail,
  plan: PlanView | null | undefined,
  approvals: ApprovalsView | null | undefined,
  approval: Approval | undefined,
  writes: boolean,
): string {
  if (approval) {
    const who =
      approval.approver === 'policy'
        ? `the site's written policy${approval.comment ? ` (${approval.comment})` : ''}`
        : approval.approver;
    const revoked = approval.revoked
      ? ` (since revoked${approval.revokedBy ? ` by ${approval.revokedBy}` : ''})`
      : '';
    const verb =
      approval.decision === 'rejected'
        ? 'Rejected'
        : approval.approver === 'policy'
          ? 'Released'
          : 'Approved';
    return `${verb} by ${who}${revoked}`;
  }
  const by = c.planCreatedBy ?? plan?.plan?.createdBy ?? '';
  // A plan the policy wrote that writes nothing is settled by that; one that writes still waits for its release
  if (by.startsWith('policy:') && !writes)
    return `The site's written policy, entry ${by.slice('policy:'.length)}`;
  if (!writes) return 'No approval needed: the plan writes nothing';
  // Approvals not read (still loading, or the read failed): who released the write is not known
  if (approvals === undefined) return 'Unknown';
  if (c.disposition === 'handled_by_hand') return 'The team, by hand';
  switch (c.state) {
    case 'blocked':
      return 'Nobody: the gate blocked it';
    case 'escalated':
      return 'Nobody yet: a person decides';
    case 'failed':
      return 'Nobody: the workflow failed';
    default:
      return 'Nobody yet';
  }
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
  const byPlan = approvalsByPlan(approvals, plan);
  const approval = approvalOf(byPlan.current);
  // A FHIR update that Shutter's own last check stopped before the socket is not an attempt the receiver did not take
  const tried = (attempts ?? []).filter(
    (x) => x.attempt && (asObject(x.attempt.response) ?? {}).sent !== false,
  );
  const sent = tried.filter((x) => WRITE_OUTCOMES.includes(str(x.attempt?.outcome)));
  const acknowledged = sent.filter((x) => ['applied', 'already_committed'].includes(str(x.attempt?.outcome)));
  const last =
    [...(attempts ?? [])].reverse().find((x) => x.verification)?.verification ?? closure?.verification;
  const decisions = plan?.gateDecisions ?? [];
  const gate = decisions.length ? decisions[decisions.length - 1] : undefined;
  const disposition = p?.disposition || c.disposition || '';
  const writes = disposition === 'resend';
  // With no verification yet: one still to come after a write, or none to make (no Shutter write, a hand
  // correction, a case that stopped before its write went out)
  // A case stopped with a write and no verification, as a write call that errored: nothing is coming to verify it
  const unverifiedWrite = sent.length > 0 && STOPPED_STATES.includes(c.state);
  const verification = last
    ? `${humanize(last.outcome)}${last.summary ? `: ${last.summary}` : ''}`
    : unverifiedWrite
      ? 'Not established: whether the write landed is for a person to check'
      : sent.length
        ? 'Verification pending'
        : c.disposition === 'handled_by_hand'
          ? 'Not verified by Shutter: the team corrected it by hand'
          : p && !writes
            ? 'Not applicable: no Shutter write'
            : STOPPED_STATES.includes(c.state)
              ? `Not applicable: ${humanize(c.state).toLowerCase()} with nothing written`
              : '';
  const verificationState = last
    ? last.outcome
    : unverifiedWrite
      ? 'unresolved'
      : sent.length
        ? 'pending'
        : c.disposition === 'handled_by_hand'
          ? 'by_hand'
          : (p && !writes) || STOPPED_STATES.includes(c.state)
            ? 'not_applicable'
            : '';
  const target = `${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''}`;
  const fhir = receiverKind(snapshot) === 'fhir_r4';
  const etag = fhirSummary(snapshot)?.encounter?.etag ?? '';
  const action = !p
    ? 'No plan yet'
    : writes && fhir
      ? `${FHIR_PROPOSAL}, with If-Match on the version read${etag ? ` (ETag ${etag})` : ''}`
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
    planDigest: str(p?.digest || approval?.planDigest),
    snapshotDigest: str(approval?.snapshotDigest || snapshot?.digest),
    expectedVersion: writes ? (fhir ? etag : str(approval?.expectedVersion ?? p?.expectedVersion)) : '',
    receiverEpoch: str(approval?.receiverEpoch),
    gate: gate ? { stage: gate.stage, outcome: gate.outcome, policyVersion: gate.policyVersion } : null,
    decidedBy: decider(c, plan, approvals, approval, writes),
    earlierApproval: earlierApprovalText(byPlan.earlier, plan),
    decidedAt: str(approval?.decidedAt),
    writes: sent.length,
    acknowledged: acknowledged.length,
    notWritten: tried.length - sent.length,
    verification,
    verificationState,
    status: statusOf(c, sent.length, closure, last?.outcome === 'verified' ? 'verified at the receiver' : ''),
    ...(fhir ? { receiverKind: 'fhir_r4' as const } : {}),
  };
}

/**
 * The receipt's facts in plain words, one caption each (the newcomer's layer): what was proposed, what was written
 * and whether the receiver took it. The versions, epochs, policy ids and times stay in the copied receipt and in the
 * receipt's "Versions, keys and times".
 */
export function proposalCaption(r: SafetyReceipt): string {
  if (r.disposition === 'resend' && r.planVersion !== null && r.receiverKind === 'fhir_r4')
    return FHIR_PROPOSAL;
  return r.disposition === 'resend' && r.planVersion !== null ? 'Send it again, unchanged' : r.action;
}

/** "1 update, accepted"; "1 update, not confirmed"; nothing for no write, which the badge says. */
export function writesCaption(r: SafetyReceipt): string {
  const updates = r.writes ? `${r.writes} update${r.writes === 1 ? '' : 's'}` : '';
  const how = !r.writes
    ? ''
    : r.acknowledged === r.writes
      ? 'accepted'
      : r.acknowledged
        ? `${r.acknowledged} accepted`
        : 'not confirmed';
  const refused = r.notWritten
    ? `${r.notWritten} attempt${r.notWritten === 1 ? '' : 's'} the receiver did not take`
    : '';
  return [updates ? `${updates}, ${how}` : '', refused].filter(Boolean).join('; ');
}

/** The writes' versions and epoch, as the copied receipt names them: "1 acknowledged; conditional on version 2, epoch 227". */
export function writesDetail(r: SafetyReceipt): string {
  return [
    r.writes ? `${r.acknowledged} acknowledged` : '',
    r.notWritten ? `${r.notWritten} attempt${r.notWritten === 1 ? '' : 's'} the receiver did not take` : '',
    r.writes && r.expectedVersion && r.receiverKind === 'fhir_r4'
      ? `sent with If-Match ${r.expectedVersion}`
      : r.writes && r.expectedVersion
        ? `conditional on version ${r.expectedVersion}${r.receiverEpoch ? `, epoch ${r.receiverEpoch}` : ''}`
        : '',
  ]
    .filter(Boolean)
    .join('; ');
}
