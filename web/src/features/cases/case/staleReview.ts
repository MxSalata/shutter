import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import { approvalChange } from './approvalChange';
import { fhirSummary, receiverKind } from './derive';
import { planWords } from './planAction';

/** A review's case, plan and evidence as they were read: what a stopped review read, or what the case reads now. */
export interface ReviewedState {
  c: CaseDetail;
  view: PlanView;
  snapshot: Snapshot | null | undefined;
}

/** One line of what changed between a stopped review and the case now: what it was, what it is, and whether it moved. */
export interface ChangeRow {
  label: string;
  /** What it was; empty when it was read again and says the same, so there is nothing older to show. */
  was: string;
  now: string;
  changed: boolean;
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** The receiver version a plan's write is conditional on: a FHIR Encounter's ETag as read, else the plan's own version. */
function receiverVersion(s: ReviewedState): string {
  if (s.view.plan.disposition !== 'resend') return 'No write';
  if (receiverKind(s.snapshot) === 'fhir_r4')
    return str(fhirSummary(s.snapshot)?.encounter?.etag) || 'Not read';
  return str(s.view.plan.expectedVersion) || 'None';
}

/** What the evidence read at the receiver, as the review shows it; empty when the page has no evidence to compare. */
function evidenceRead(s: ReviewedState): string {
  if (!s.snapshot) return '';
  return approvalChange(s.view, s.c, s.snapshot).held;
}

/**
 * Whether the case as read now is older than a review opened on it: a page whose reads have not caught up with a
 * review opened on a fresh read. Versions only go up, so an older read is never a change.
 */
export function readBehind(
  opened: Pick<ReviewedState, 'c' | 'view'>,
  c: CaseDetail,
  view: PlanView | null | undefined,
): boolean {
  return c.version < opened.c.version || (!!view?.plan && view.plan.version < opened.view.plan.version);
}

/**
 * Whether the evidence was read again: by the digest of what matters to the decision where both reads have one, else
 * by the whole snapshot's digest. A material digest is never compared with a plain one.
 */
function evidenceMoved(before: Snapshot | null | undefined, now: Snapshot | null | undefined): boolean {
  if (before?.materialDigest && now?.materialDigest) return before.materialDigest !== now.materialDigest;
  return str(before?.digest) !== str(now?.digest);
}

/**
 * What changed between a review that was stopped and the case as read now: the case's state when it is no longer the
 * one the review opened in, then in the order a reader checks a decision's binding: the plan, the action it takes, the
 * receiver version its write is conditional on, what the evidence read at the receiver, and the case version. The
 * evidence is compared only where both reads have it; read again with the same words, it says so rather than repeat
 * them. With no plan now, the plan reads "None" and nothing else of it is compared.
 */
export function whatChanged(
  before: ReviewedState,
  now: { c: CaseDetail; view: PlanView | null | undefined; snapshot: Snapshot | null | undefined },
): ChangeRow[] {
  const row = (label: string, was: string, is: string, changed = was !== is): ChangeRow => ({
    label,
    was,
    now: is,
    changed,
  });
  const plan = now.view?.plan;
  const rows: ChangeRow[] = [];
  if (now.c.state !== before.c.state)
    rows.push(row('State', humanize(before.c.state), humanize(now.c.state)));
  const samePlan = !!plan && plan.digest === before.view.plan.digest;
  rows.push(
    row(
      'Plan',
      `v${before.view.plan.version}`,
      plan
        ? `v${plan.version}${!samePlan && plan.version === before.view.plan.version ? ', another digest' : ''}`
        : 'None',
      !samePlan,
    ),
  );
  if (plan && now.view) {
    const after: ReviewedState = { c: now.c, view: now.view, snapshot: now.snapshot };
    rows.push(
      row(
        'Action',
        planWords(before.view.plan, before.c, before.snapshot).action,
        planWords(plan, now.c, now.snapshot).action,
      ),
    );
    rows.push(row('Receiver version', receiverVersion(before), receiverVersion(after)));
    const was = evidenceRead(before);
    const is = evidenceRead(after);
    if (was && is)
      rows.push(
        was === is && evidenceMoved(before.snapshot, now.snapshot)
          ? row('Evidence', '', `Read again: ${is}`, true)
          : row('Evidence', was, is),
      );
  }
  rows.push(row('Case version', String(before.c.version), String(now.c.version)));
  return rows;
}

/**
 * Why a decision on the review that was stopped was not recorded, in one sentence for the review that replaces it:
 * the plan moved, else the case did, else nothing the page reads changed and the server's refusal is all there is.
 */
export function replacedWords(before: ReviewedState, now: ReviewedState): string {
  const was = `plan v${before.view.plan.version}`;
  if (now.view.plan.digest !== before.view.plan.digest)
    return `Your decision on ${was} was not recorded: the plan changed, and this is plan v${now.view.plan.version}.`;
  if (now.c.version !== before.c.version)
    return `Your decision on ${was} was not recorded: the case changed under it, though the plan is the same.`;
  return `Your decision on ${was} was not recorded: it was refused as stale, though nothing this page reads has changed.`;
}
