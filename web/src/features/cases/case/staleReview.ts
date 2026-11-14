import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
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
 * What changed between a review that was stopped and the case as read now, in the order a reader checks a decision's
 * binding: the plan, the action it takes, the receiver version its write is conditional on, what the evidence read at
 * the receiver, and the case version. The evidence is compared only where both reads have it. With no plan now, the
 * plan reads "None" and nothing else of it is compared.
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
    if (was && is) {
      const moved =
        str(before.snapshot?.materialDigest || before.snapshot?.digest) !==
        str(now.snapshot?.materialDigest || now.snapshot?.digest);
      rows.push(row('Evidence', was, is, moved || was !== is));
    }
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
