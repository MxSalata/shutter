import {
  IconBroadcast,
  IconCircleCheck,
  IconCircleX,
  IconClock,
  IconCode,
  IconFileDescription,
  IconHandStop,
  IconListDetails,
  IconLockCancel,
  IconMinus,
  IconPlayerPlay,
  IconProgress,
  IconQuestionMark,
  IconSend,
  IconShieldCheck,
  IconShieldQuestion,
  IconShieldX,
  IconUserCheck,
  IconUserQuestion,
  IconAlertCircle,
  IconAlertTriangle,
  IconInfoCircle,
} from '@tabler/icons-react';
import { humanize } from './format';
import type { Status, Tone } from './tone';

/**
 * Every status the app shows, by role, in the five tones of tone.ts. Each role is a field of its own (the case's
 * state, its disposition, the gate, the approval, the writes, the verification, where an agent's answer came from),
 * never one status read off another: a resolved case is not by itself a verified write, and an escalation is a
 * person's turn, not a failure.
 */

const s = (tone: Tone, label: string, hint?: string, icon?: Status['icon']): Status => ({
  tone,
  label,
  hint,
  icon,
});

const RUNNING = IconProgress;

/** The case workflow's states: information while it runs, attention when a person is needed, blocking when stopped. */
export const CASE_STATES: Record<string, Status> = {
  detected: s('info', 'Detected', 'The failure was seen; the case is open', RUNNING),
  collecting: s(
    'info',
    'Collecting',
    'Reading the message, the downstream system and the message store',
    RUNNING,
  ),
  investigating: s('info', 'Investigating', 'The board is reviewing the evidence', RUNNING),
  grouped: s(
    'info',
    'Grouped',
    'Held by an incident: released in order with the other failures to the same receiver',
    IconListDetails,
  ),
  proposed: s('info', 'Proposed', 'A plan was proposed', RUNNING),
  gated: s('info', 'Gated', 'The gate checked the plan', RUNNING),
  rehearsing: s('info', 'Rehearsing', "The downstream system's dry run of the exact action", RUNNING),
  awaiting_approval: s(
    'attention',
    'Awaiting approval',
    'A person with the approver role must release or reject the plan',
    IconUserQuestion,
  ),
  approved: s(
    'info',
    'Released',
    "Released by a person or the site's written policy; the receiver is read once more and the gate checks again before dispatch",
    RUNNING,
  ),
  executing: s('info', 'Executing', 'The conditional write is being sent', RUNNING),
  verifying: s('info', 'Verifying', "Reading the receiver's committed history and receipts", RUNNING),
  resolved: s(
    'neutral',
    'Resolved',
    'Closed with an outcome; the receipt says what was written and what the verifier found',
    IconCircleCheck,
  ),
  blocked: s(
    'blocking',
    'Blocked',
    'Stopped: a check or a person said no; nothing more is sent',
    IconHandStop,
  ),
  escalated: s('attention', 'Escalated', 'Handed to a person to decide', IconUserQuestion),
  failed: s('blocking', 'Failed', 'The workflow itself failed', IconAlertCircle),
};

export const caseState = (state: string): Status =>
  CASE_STATES[state] ?? s('neutral', humanize(state), undefined, IconMinus);

/** How a case was handled. A disposition is a decision, not a result: neutral, except where a person is needed. */
export const DISPOSITIONS: Record<string, Status> = {
  resend: s(
    'neutral',
    'Resend',
    'Send the same operation again, conditional on the receiver version, after rehearsal and the gate',
    IconListDetails,
  ),
  reconcile: s('neutral', 'Reconcile', 'It was applied already: record that, send nothing', IconListDetails),
  superseded: s(
    'neutral',
    'Superseded',
    'A later event moved the encounter on: sending it now would undo that',
    IconListDetails,
  ),
  more_evidence: s('attention', 'More evidence', 'The evidence does not decide it yet', IconQuestionMark),
  escalate: s('attention', 'Escalate', 'A person must decide', IconUserQuestion),
  handled_by_hand: s(
    'neutral',
    'Handled by hand',
    'The team corrected the systems by hand, and a person closed the case; Shutter did not verify the correction',
    IconListDetails,
  ),
  abandoned: s(
    'neutral',
    'Abandoned',
    'An approver gave the case up after its workflow stopped moving; nothing more is sent, and it can be reinvestigated',
    IconListDetails,
  ),
};

export const disposition = (d: string): Status =>
  DISPOSITIONS[d] ?? s('neutral', humanize(d), undefined, IconListDetails);

/** One gate check, in four states: a check a plan that writes nothing does not need is not counted as passed. */
export type CheckState = 'passed' | 'blocked' | 'unknown' | 'not_applicable';

export const CHECK_STATES: Record<CheckState, Status> = {
  passed: s('positive', 'Passed', 'The check passed', IconShieldCheck),
  blocked: s('blocking', 'Blocked', 'The check failed: no write', IconShieldX),
  unknown: s(
    'blocking',
    'Unknown: blocks a write',
    'The check could not be decided; an unknown blocks a write as surely as a failure',
    IconShieldQuestion,
  ),
  not_applicable: s(
    'neutral',
    'Not applicable',
    'Not checked here: the plan writes nothing, the check belongs to a later stage, or there is nothing to check against',
    IconMinus,
  ),
};

/**
 * The reason codes the gate (Gate.cls) gives a check it passes without checking anything: no write proposed, a check
 * of a later stage, no catalogue installed, a message that names no encounter to compare.
 */
export const NOT_APPLICABLE_CODES = ['NOT_APPLICABLE', 'NOT_YET_REQUIRED', 'NOT_CONFIGURED', 'NO_ENCOUNTER'];

export function checkState(c: { result: string; reason_code?: string }): CheckState {
  if (c.result === 'block') return 'blocked';
  if (c.result === 'pass')
    return NOT_APPLICABLE_CODES.includes(c.reason_code ?? '') ? 'not_applicable' : 'passed';
  return 'unknown';
}

/** "6 passed, 3 not applicable": the checks of a decision by state, the empty states left out. */
export function checkCounts(checks: { result: string; reason_code?: string }[]): string {
  const order: CheckState[] = ['passed', 'blocked', 'unknown', 'not_applicable'];
  const states = checks.map(checkState);
  return order
    .map((k) => [k, states.filter((x) => x === k).length] as const)
    .filter(([, n]) => n > 0)
    .map(([k, n]) => `${n} ${k === 'unknown' ? 'unknown' : CHECK_STATES[k].label.toLowerCase()}`)
    .join(', ');
}

/** A gate decision's outcome, counting only the applicable checks as passed. */
export function gateOutcome(outcome: string, checks: { result: string; reason_code?: string }[]): Status {
  const states = checks.map(checkState);
  const n = (k: CheckState) => states.filter((x) => x === k).length;
  const applicable = states.length - n('not_applicable');
  const na = n('not_applicable') ? `; ${n('not_applicable')} not applicable` : '';
  if (outcome === 'pass')
    return s(
      'positive',
      applicable
        ? `Passed ${n('passed')} of ${applicable} applicable check${applicable === 1 ? '' : 's'}`
        : 'Passed',
      `Every check that applies to this plan passed${na}`,
      IconShieldCheck,
    );
  if (outcome === 'block')
    return s(
      'blocking',
      'Blocked',
      `${n('blocked')} check${n('blocked') === 1 ? '' : 's'} blocked the write${n('unknown') ? `, ${n('unknown')} unknown` : ''}`,
      IconShieldX,
    );
  return s(
    'blocking',
    'Unknown: write blocked',
    'A check could not be decided, and an unknown blocks a write',
    IconShieldQuestion,
  );
}

/** What the downstream system answered a write. An acknowledgement is never called verified. */
export const ATTEMPTS: Record<string, Status> = {
  applied: s(
    'info',
    'Acknowledged',
    'The downstream system answered 201; verification reads what it committed',
    IconSend,
  ),
  already_committed: s(
    'info',
    'Already committed',
    'The downstream system had committed this operation before',
    IconSend,
  ),
  uncertain: s(
    'attention',
    'No answer: outcome unknown',
    'The write may or may not have been committed; reconciled by its key',
    IconQuestionMark,
  ),
  version_conflict: s(
    'blocking',
    'Refused: the receiver changed',
    'The expected version no longer matched; nothing was written',
    IconCircleX,
  ),
  refused: s('blocking', 'Refused', 'The downstream system refused the write', IconCircleX),
  error: s('blocking', 'Error', 'The write could not be sent', IconAlertCircle),
};

export const attempt = (outcome: string): Status => ATTEMPTS[outcome] ?? s('neutral', humanize(outcome));

/** What the verifier found at the receiver; the two last are what a case without a verification says. */
export const VERIFICATIONS: Record<string, Status> = {
  verified: s('positive', 'Effect verified at the receiver', undefined, IconCircleCheck),
  unresolved: s('attention', 'Not established', undefined, IconQuestionMark),
  not_committed: s('blocking', 'Not committed at the receiver', undefined, IconCircleX),
  failed: s('blocking', 'Contradiction: a person must check', undefined, IconCircleX),
  pending: s('info', 'Verification pending', undefined, IconClock),
  not_applicable: s('neutral', 'Not applicable: no Shutter write', undefined, IconMinus),
  by_hand: s('neutral', 'Not verified by Shutter', 'The team corrected the systems by hand', IconMinus),
};

export const verification = (outcome: string): Status =>
  VERIFICATIONS[outcome] ?? s('neutral', humanize(outcome));

/** The writes a run made: information when there were some, neutral when none. Proposed and made are kept apart. */
export function writes(n: number): Status {
  return n
    ? s('info', `${n} write${n === 1 ? '' : 's'}`, 'Writes that reached the receiver', IconSend)
    : s('neutral', '0 writes', 'Nothing was written to the receiver', IconMinus);
}

export function proposedWrites(n: number): Status {
  return s(
    'info',
    `Proposed: ${n} write${n === 1 ? '' : 's'}`,
    'What the plan would write; nothing is sent before the gate and the release',
    IconFileDescription,
  );
}

/** Where an answer came from: a live model call, a recorded run replayed, or the rules with no model at all. */
export const PROVENANCE: Record<'live' | 'replay' | 'rules', Status> = {
  live: s('info', 'Live model', 'A model was called for this run', IconBroadcast),
  replay: s(
    'neutral',
    'Recorded replay',
    'Replayed from a recorded live run: no model was called now',
    IconPlayerPlay,
  ),
  rules: s('neutral', 'Rules only', 'No model: the deterministic rules decided', IconCode),
};

/** The release of a write: a person or the site's written policy releases it, after the gate. */
export const APPROVALS: Record<string, Status> = {
  awaiting: s(
    'attention',
    'Awaiting approval',
    'A person with the approver role must release or reject the plan',
    IconUserQuestion,
  ),
  approved: s('info', 'Approved', 'Released by a person; the gate checks again at dispatch', IconUserCheck),
  policy: s(
    'info',
    "Released by the site's written policy",
    'The site profile releases this kind of write without a person; the gate still checks it',
    IconFileDescription,
  ),
  rejected: s('blocking', 'Rejected', 'A person rejected the plan: nothing is sent', IconCircleX),
  revoked: s(
    'blocking',
    'Approval revoked',
    'An earlier approval no longer authorises a write: its plan, evidence or receiver changed, or its write was spent',
    IconLockCancel,
  ),
  not_required: s(
    'neutral',
    'Not required',
    'The plan writes nothing, so nothing needs releasing',
    IconMinus,
  ),
};

/** A production review's finding severities: blocking, attention, information and neutral, highest first. */
export const SEVERITY_STATUS: Record<string, Status> = {
  high: s('blocking', 'High', undefined, IconAlertCircle),
  medium: s('attention', 'Medium', undefined, IconAlertTriangle),
  low: s('info', 'Low', undefined, IconInfoCircle),
  info: s('neutral', 'Info', undefined, IconInfoCircle),
};
