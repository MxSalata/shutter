import type { PlanView, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import { asObject } from '@/lib/json';
import { quotedVersion, receiverKind } from './derive';
import { evidenceOf } from './message';
import { planOperation, type ActionCase } from './planAction';

/** The evidence behind a case, while it is being read (`undefined`) or when there is none (`null`). */
export type ApprovalEvidence = Snapshot | null | undefined;

/** The plan under review: its own fields, and the receiver's dry run of it when there is one. */
export type ReviewedPlan = Pick<PlanView, 'plan'> & { rehearsal?: PlanView['rehearsal'] };

export interface ApprovalChange {
  /** What the evidence read at the receiver: "WARD-A, bed BAY1-01 at version 1", or that it has no reading. */
  held: string;
  /** When that was read; empty with no reading. */
  readAt: string;
  /** What the receiver is expected to hold if this plan is released, or why that is not known. */
  expected: string;
  /** Where the expectation comes from, to follow it in brackets; empty when it needs no source. */
  basis: string;
  /** What else the reader should know of the effect: what the operation leaves alone, what it does not carry. */
  notes: string[];
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** An encounter as the receiver gives it, in words: "WARD-B, bed BAY2-04", "Discharged"; a state other than admitted is said. */
function placeWords(e: Record<string, unknown>): string {
  const where = [str(e.ward), e.bed ? `bed ${str(e.bed)}` : ''].filter(Boolean).join(', ');
  const state = str(e.state);
  if (!where) return state ? humanize(state) : '';
  return state && state !== 'admitted' ? `${humanize(state)}, ${where}` : where;
}

/**
 * The encounter the receiver's dry run of this plan would leave, or undefined: only a dry run of this very plan that
 * said it would apply, checked against the version the plan's write is conditional on. A dry run at another version
 * says nothing about this write (CONTRACTS 1.1).
 */
function rehearsedAfter(view: ReviewedPlan): Record<string, unknown> | undefined {
  const r = view.rehearsal;
  if (!r || r.wouldApply !== true) return undefined;
  const of = str((r as { planId?: unknown }).planId);
  if (of && str(view.plan.id) && of !== str(view.plan.id)) return undefined;
  if (str(r.receiverVersion) !== str(view.plan.expectedVersion)) return undefined;
  return asObject(asObject(r.response)?.encounter_after);
}

/**
 * What an approval changes at the receiver, for the Approval section and the review dialog alike: what the evidence
 * read there and when, and what releasing this plan is expected to leave. The reading is as old as the evidence and
 * the receiver may have moved since, which the dispatch gate finds, so it is never worded as what the receiver holds
 * now. The expectation is read from the plan's own operation: the receiver's dry run of this plan when there is one,
 * else what the mapped operation of the plan's key carries. An update carries no ward or bed (CONTRACTS 1.1), so it
 * is never shown as a move, whatever location its message names. Anything missing is said, not guessed.
 */
export function approvalChange(
  view: ReviewedPlan,
  c: ActionCase,
  snapshot: ApprovalEvidence,
): ApprovalChange {
  const read = asObject(asObject(snapshot?.summary)?.ward_state);
  const where = read ? placeWords(read) : '';
  const known = where && read?.version !== undefined && read.version !== null;
  const reading = {
    held: known
      ? `${where} at version ${receiverKind(snapshot) === 'fhir_r4' ? quotedVersion(read.version) : str(read.version)}`
      : snapshot === undefined
        ? 'Not read yet'
        : 'Not in the evidence',
    readAt: known ? (snapshot?.takenAt ?? '') : '',
  };
  const { plan } = view;
  const op = planOperation(plan, c, snapshot);
  if (plan.disposition !== 'resend') {
    const receipt = evidenceOf(snapshot, 'receipt');
    const committed = asObject(receipt?.body) ?? receipt;
    const versions =
      committed && committed.version_after !== undefined && committed.version_after !== null
        ? `, version ${str(committed.version_before) || 'none'} to ${str(committed.version_after)}`
        : '';
    return {
      ...reading,
      expected:
        plan.disposition === 'reconcile'
          ? 'No new write: the operation is recorded as already delivered'
          : 'No write: nothing changes at the receiver',
      basis: '',
      notes:
        plan.disposition !== 'reconcile'
          ? []
          : versions
            ? [`The receiver's receipt in the evidence shows it committed${versions}.`]
            : [
                'The evidence holds no committed receipt for this operation: whether it was applied is unknown.',
              ],
    };
  }
  const notes: string[] = [];
  if (op?.event === 'update') {
    notes.push('An update carries no location: the ward and bed stay as the receiver holds them.');
    // The A08's own PV1-3, which only an A08's evidence carries: shown as what the resend does not send
    const message = evidenceOf(snapshot, 'message');
    const named = [str(message?.a08_ward), message?.a08_bed ? `bed ${str(message.a08_bed)}` : '']
      .filter(Boolean)
      .join(', ');
    const heldPlace = read
      ? [str(read.ward), read.bed ? `bed ${str(read.bed)}` : ''].filter(Boolean).join(', ')
      : '';
    if (named && named !== heldPlace)
      notes.push(
        `The message names ${named}; the resend does not carry it, so the patient is not moved there.`,
      );
  }
  const after = rehearsedAfter(view);
  if (after) {
    const place = placeWords(after);
    const version = str(after.version);
    if (place)
      return {
        ...reading,
        expected: `${place}${version ? ` at version ${version}` : ''}`,
        basis: "the receiver's dry run of this plan",
        notes,
      };
  }
  // No dry run to read: what the plan's own operation carries, and no more
  const expected = !op
    ? 'Unknown: the plan names no operation'
    : op.event === 'update'
      ? 'The update is applied; the ward and bed are not changed'
      : op.event === 'discharge'
        ? 'The discharge is applied; what the receiver then shows is not known until it is verified'
        : op.event === 'admit' || op.event === 'transfer'
          ? op.ward
            ? [op.ward, op.bed ? `bed ${op.bed}` : ''].filter(Boolean).join(', ')
            : op.mapped
              ? 'Unknown: the operation names no ward'
              : "Unknown: the plan's operation is not in the evidence"
          : `${humanize(op.event) || 'The operation'} applied; what the receiver then shows is not known until it is verified`;
  return {
    ...reading,
    expected,
    basis: op && (op.event === 'admit' || op.event === 'transfer') && op.ward ? "the plan's operation" : '',
    notes,
  };
}
