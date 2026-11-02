import {
  IconBroadcast,
  IconChecks,
  IconCircleCheck,
  IconCircleMinus,
  IconCircleOff,
  IconCircleX,
  IconClock,
  IconCode,
  IconFileDescription,
  IconHandStop,
  IconListDetails,
  IconLockCancel,
  IconMinus,
  IconPlayerPlay,
  IconPlayerSkipForward,
  IconProgress,
  IconQuestionMark,
  IconRepeat,
  IconSend,
  IconShieldCheck,
  IconShieldQuestion,
  IconShieldX,
  IconTargetOff,
  IconTool,
  IconUserCheck,
  IconUserQuestion,
  IconUsers,
  IconAlertCircle,
  IconAlertTriangle,
  IconInfoCircle,
} from '@tabler/icons-react';
import type { CaseState, CaseSummary, IncidentSummary, Mode, Scenario } from '@/api/types';
import { humanize, plural } from './format';
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
    'Waiting for approval',
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
    IconRepeat,
  ),
  reconcile: s('neutral', 'Reconcile', 'It was applied already: record that, send nothing', IconChecks),
  superseded: s(
    'neutral',
    'Superseded',
    'A later event moved the encounter on: sending it now would undo that',
    IconPlayerSkipForward,
  ),
  more_evidence: s('attention', 'More evidence', 'The evidence does not decide it yet', IconQuestionMark),
  escalate: s('attention', 'Escalate', 'A person must decide', IconUserQuestion),
  handled_by_hand: s(
    'neutral',
    'Handled by hand',
    'The team corrected the systems by hand, and a person closed the case; Shutter did not verify the correction',
    IconTool,
  ),
  abandoned: s(
    'neutral',
    'Abandoned',
    'An approver gave the case up after its workflow stopped moving; nothing more is sent, and it can be reinvestigated',
    IconCircleOff,
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
    'Waiting for approval',
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

/**
 * A precedent's decision (CONTRACTS 6.4): approved means a person approved and the write was verified at the receiver,
 * so it is positive, as a verified effect is; rejected is blocking, as a rejection is. A retired one counts for nothing
 * and is neutral. These say what happened before, never what to do now.
 */
export const PRECEDENT_DECISIONS: Record<string, Status> = {
  approved: s(
    'positive',
    'Approved, verified',
    'A person approved the plan and the write was verified at the receiver',
    IconUserCheck,
  ),
  rejected: s('blocking', 'Rejected', 'A person rejected the plan: nothing was sent', IconCircleX),
  retired: s(
    'neutral',
    'Retired',
    'Retired by an approver: it stays on record and counts for nothing',
    IconCircleOff,
  ),
};

/** A production review's finding severities: blocking, attention, information and neutral, highest first. */
export const SEVERITY_STATUS: Record<string, Status> = {
  high: s('blocking', 'High', undefined, IconAlertCircle),
  medium: s('attention', 'Medium', undefined, IconAlertTriangle),
  low: s('info', 'Low', undefined, IconInfoCircle),
  info: s('neutral', 'Info', undefined, IconInfoCircle),
};

/**
 * Who releases a write of a kind at a tier, as the site profile answers it: the site's written policy (information, so
 * it stands out), a person (attention: a person is needed), a person for each chain, or the board (neutral). One map
 * for the site profile's matrix, its receiver cards and a case's receiver line.
 */
export const RELEASES: Record<string, Status> = {
  automatic: s(
    'info',
    "The site's written policy",
    'Released by the site profile without a person, after the gate',
    IconFileDescription,
  ),
  approval: s('attention', 'A person', 'One approval by a person with the approver role', IconUserCheck),
  per_chain: s(
    'attention',
    'A person, per chain',
    "A person approves each chain's release on its own",
    IconUserCheck,
  ),
  board: s(
    'neutral',
    'The board decides',
    'The board of agents decides; a person releases its plan',
    IconUsers,
  ),
};

export const release = (value: string): Status => RELEASES[value] ?? s('neutral', humanize(value));

/** The states a case passes through while its workflow runs, before it ends or waits for a person. */
const RUNNING_STATES: readonly CaseState[] = [
  'detected',
  'collecting',
  'investigating',
  'grouped',
  'proposed',
  'gated',
  'rehearsing',
  'approved',
  'executing',
  'verifying',
];

/** What a case needs for its outcome: the summary's state and disposition, and what it wrote and verified when sent. */
export type OutcomeCase = Pick<CaseSummary, 'state' | 'disposition'> &
  Partial<Pick<CaseSummary, 'writes' | 'verification' | 'receiver'>> & { mode?: Mode | string };

/** The part of a scenario its cases are compared with. */
export type ExpectedScenario = Pick<Scenario, 'id' | 'expected'>;

export interface Expectation {
  /** as-expected: matches; stopped: blocked by the gate where the scenario expects no block; differs: not expected. */
  kind: 'as-expected' | 'stopped' | 'differs' | 'unknown';
  label: string;
  /** The disposition the scenario expects of this case, when one applies. */
  expects?: string;
}

/**
 * How a case compares with its scenario's expectation, where one applies: the receiver's own expectation when the
 * scenario names one (S22), the mode's own additions when it has them (S21 in Rules only mode), and none for an incident
 * scenario (S11, S12: their expectation is per encounter) or a scenario with no expected disposition. Unknown, too,
 * while the case has not ended or waits for a person's approval.
 */
export function expectationOf(c: OutcomeCase, scenario?: ExpectedScenario | null): Expectation {
  const unknown: Expectation = { kind: 'unknown', label: '' };
  const base = scenario?.expected;
  if (!scenario || !base || base.incident) return unknown;
  const byMode = c.mode ? base.by_mode?.[c.mode as Mode] : undefined;
  const e = byMode ? { ...base, ...byMode } : base;
  const receiver = c.receiver ? e.by_receiver?.[c.receiver] : undefined;
  const expects = receiver ? receiver.disposition : e.disposition;
  const write = receiver ? receiver.write : e.write;
  if (!expects) return unknown;
  const matches = c.disposition === expects || (e.acceptable ?? []).includes(c.disposition);
  if (c.state === 'blocked')
    return e.blocked_by
      ? { kind: 'as-expected', label: 'As expected', expects }
      : { kind: 'stopped', label: `Stopped by the gate; ${scenario.id} expects ${expects}`, expects };
  if (c.state === 'resolved') {
    const wroteWrongly = (c.writes ?? 0) > 0 && write === false;
    return !matches || wroteWrongly
      ? { kind: 'differs', label: `Not the expected outcome: ${scenario.id} expects ${expects}`, expects }
      : { kind: 'as-expected', label: 'As expected', expects };
  }
  if (c.state === 'escalated' && matches) return { kind: 'as-expected', label: 'As expected', expects };
  return unknown;
}

/** The case outcome's kinds, one per row of the rule below, for counting and filtering. */
export type CaseOutcomeKey =
  | 'handled-by-hand'
  | 'abandoned'
  | 'awaiting-approval'
  | 'escalated'
  | 'blocked'
  | 'failed'
  | 'running'
  | 'not-as-expected'
  | 'not-committed'
  | 'contradiction'
  | 'unverified'
  | 'delivered'
  | 'nothing-to-send-verified'
  | 'nothing-to-send'
  | 'resolved';

export type CaseOutcome = Status & { short: string; key: CaseOutcomeKey };

const o = (
  key: CaseOutcomeKey,
  tone: Tone,
  label: string,
  short: string,
  icon: Status['icon'],
  hint?: string,
): CaseOutcome => ({ key, tone, label, short, icon, hint });

/**
 * What came of a case, coloured by its outcome rather than its workflow state: the first rule that matches wins. A
 * verification knows a write landed, not that it was right, so a delivery reads "Delivered: verified at the receiver",
 * never "recovered"; and a resolved case its scenario did not expect (rules alone's S8 resend, C-000021) is blocking,
 * however verified. The writes and the verification count only when the summary sends them; without them a resolved
 * case is "Resolved", as before. `label` is the long form (the case page, a list badge's tooltip), `short` the list's.
 */
export function caseOutcome(c: OutcomeCase, scenario?: ExpectedScenario | null): CaseOutcome {
  if (c.disposition === 'handled_by_hand')
    return o('handled-by-hand', 'neutral', 'Handled by hand', 'Handled by hand', IconTool);
  if (c.disposition === 'abandoned')
    return o('abandoned', 'neutral', 'Abandoned', 'Abandoned', IconCircleOff);
  if (c.state === 'awaiting_approval')
    return o(
      'awaiting-approval',
      'attention',
      'Waiting for approval',
      'Waiting for approval',
      IconUserQuestion,
    );
  if (c.state === 'escalated')
    return o('escalated', 'attention', 'Escalated: a person decides', 'Escalated', IconUserQuestion);
  if (c.state === 'blocked')
    return o('blocked', 'blocking', 'Blocked: nothing sent', 'Blocked', IconHandStop);
  if (c.state === 'failed') return o('failed', 'blocking', 'Failed', 'Failed', IconAlertCircle);
  if (RUNNING_STATES.includes(c.state)) {
    const label = caseState(c.state).label;
    return o('running', 'info', label, label, IconProgress);
  }
  if (c.state === 'resolved') {
    const expectation = expectationOf(c, scenario);
    if (expectation.kind === 'differs')
      return o('not-as-expected', 'blocking', expectation.label, 'Not as expected', IconTargetOff);
    const known = c.writes !== undefined && c.verification !== undefined;
    if (known && c.verification === 'not_committed')
      return o(
        'not-committed',
        'blocking',
        "Didn't take effect at the receiver",
        "Didn't take effect",
        IconCircleX,
      );
    if (known && c.verification === 'failed')
      return o(
        'contradiction',
        'blocking',
        'Contradiction at the receiver: a person must check',
        'Contradiction',
        IconCircleX,
      );
    if (known && c.verification === 'unresolved')
      return o(
        'unverified',
        'attention',
        "Couldn't verify at the receiver",
        "Couldn't verify",
        IconQuestionMark,
      );
    if (known && c.verification === 'verified')
      return (c.writes ?? 0) > 0
        ? o(
            'delivered',
            'positive',
            'Delivered: verified at the receiver',
            'Delivered, verified',
            IconCircleCheck,
          )
        : o(
            'nothing-to-send-verified',
            'positive',
            'Nothing to send: verified at the receiver',
            'Nothing to send, verified',
            IconCircleCheck,
          );
    // A superseded or reconciled case sends nothing by its nature, so its writes need not be sent to say so
    if ((c.writes === undefined || c.writes === 0) && ['superseded', 'reconcile'].includes(c.disposition))
      return o('nothing-to-send', 'neutral', 'Nothing to send', 'Nothing to send', IconCircleMinus);
  }
  return o(
    'resolved',
    'neutral',
    c.state === 'resolved' ? 'Resolved' : humanize(c.state),
    c.state === 'resolved' ? 'Resolved' : humanize(c.state),
    IconCircleCheck,
    'Closed. The record does not say what was written or verified.',
  );
}

/** The incident outcome's kinds, for counting and filtering. */
export type IncidentOutcomeKey =
  'verified' | 'stopped' | 'rejected' | 'person' | 'taking' | 'running' | 'closed';

/**
 * What came of an incident, from its state and its chains' states (`progress.byState`): every chain verified is
 * positive; a chain stopped or rejected is blocking; a chain escalated or waiting for a person is attention; while
 * open, it is taking cases (information).
 */
export function incidentOutcome(
  i: Pick<IncidentSummary, 'state' | 'progress'>,
): Status & { key: IncidentOutcomeKey } {
  const by = i.progress?.byState ?? {};
  const chains = i.progress?.chains ?? Object.values(by).reduce((a, b) => a + b, 0);
  const n = (k: string) => by[k] ?? 0;
  if (n('stopped'))
    return {
      key: 'stopped',
      tone: 'blocking',
      label: `${n('stopped')} stopped`,
      hint: `${plural(n('stopped'), 'chain')} stopped at the first surprise: the rest went to a person`,
      icon: IconHandStop,
    };
  if (n('rejected'))
    return {
      key: 'rejected',
      tone: 'blocking',
      label: `${n('rejected')} rejected`,
      hint: `A person rejected ${plural(n('rejected'), 'chain')}: nothing of ${n('rejected') === 1 ? 'it' : 'them'} was sent`,
      icon: IconCircleX,
    };
  if (n('escalated') || n('awaiting_approval') || i.state === 'awaiting_approval')
    return {
      key: 'person',
      tone: 'attention',
      label: n('escalated') ? `${n('escalated')} escalated` : 'Waiting for approval',
      hint: n('escalated')
        ? `${plural(n('escalated'), 'chain')} handed to a person`
        : 'A person must approve its release',
      icon: IconUserQuestion,
    };
  if (i.state === 'open')
    return {
      key: 'taking',
      tone: 'info',
      label: 'Taking cases',
      hint: 'Failures to the receiver join it',
      icon: IconProgress,
    };
  if (i.state !== 'closed')
    return { key: 'running', tone: 'info', label: humanize(i.state), icon: IconProgress };
  if (chains > 0 && n('resolved') === chains)
    return {
      key: 'verified',
      tone: 'positive',
      label: chains === 1 ? 'Its chain verified' : `All ${chains} chains verified`,
      hint: 'Every operation verified at the receiver',
      icon: IconCircleCheck,
    };
  return { key: 'closed', tone: 'neutral', label: 'Closed', icon: IconCircleCheck };
}
