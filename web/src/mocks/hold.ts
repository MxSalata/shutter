import fixtures from './fixtures.json';
import blockReasons from '../../../knowledge/block-reasons.json';

/**
 * The demo's case held at its approval. The recordings hold no case waiting for a person, since the scenario check
 * approves each plan as it plays, so the mock holds one recorded case where it waited: its events up to the request
 * for approval, its evidence, findings, plan and rehearsal (without the gate's check at dispatch, which came after the
 * approval), and an open approval task, with no decision, dispatch or closure yet. Approving it replays what the
 * recorded case did next (the case as it resolved, with a note on its timeline saying so); rejecting it closes it as
 * blocked, with the blocked reason and closure the server gives. Everything here is derived from the recorded case:
 * the fixtures themselves are not changed.
 */
export type CaseFixture = (typeof fixtures.cases)[keyof typeof fixtures.cases];

/** S2 on the board: a resend after rehearsal, which the README walks through. */
export const HELD_CASES = ['C-000002'];

export type Hold =
  | { state: 'awaiting' }
  | { state: 'approved'; by: string; at: string; comment: string }
  | { state: 'rejected'; by: string; at: string; comment: string };

interface Event {
  seq: number;
  at: string;
  kind: string;
  fromState?: string;
  toState?: string;
  text: string;
  actor?: string;
  ref?: string;
}

/** The recorded events up to the request for approval: the first state change out of awaiting_approval is cut. */
function eventsBeforeDecision(c: CaseFixture): Event[] {
  const events = c.events as Event[];
  const decided = events.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
  return decided < 0 ? events : events.slice(0, decided);
}

/** The case's version at that point: one per state change, as the store counts them. */
const versionOf = (events: Event[]) => events.filter((e) => e.kind === 'state').length;

/** Whether the recorded case can be held: it passed through awaiting_approval and was approved. */
export function canHold(c: CaseFixture | undefined): c is CaseFixture {
  if (!c) return false;
  const events = c.events as Event[];
  return (
    events.some((e) => e.kind === 'state' && e.toState === 'awaiting_approval') &&
    events.some((e) => e.kind === 'state' && e.fromState === 'awaiting_approval' && e.toState === 'approved')
  );
}

interface GateDecision {
  stage: string;
  policyVersion?: string;
}

/** The case as it waited for an approver. */
export function awaiting(c: CaseFixture): CaseFixture {
  const kept = eventsBeforeDecision(c);
  const last = kept.at(-1);
  const at = last?.at.replace(/\.\d+Z$/, 'Z') ?? c.summary.openedAt;
  const version = versionOf(kept);
  const note: Event = {
    seq: (last?.seq ?? 0) + 1,
    at: last?.at ?? at,
    kind: 'note',
    text: 'Demo replay: this recorded case is held here, before its approval, so that it can be approved in the browser. Approving it replays what the recorded case did next; rejecting it closes it as blocked.',
    actor: 'system',
  };
  const open = {
    state: 'awaiting_approval',
    version,
    outcome: '',
    closedAt: '',
    updatedAt: at,
    currentApprovalId: '',
  };
  const approvals = c.approvals as { approvals: unknown[]; tasks: Record<string, unknown>[] };
  const plan = c.plan as { gateDecisions?: GateDecision[] } | null;
  return {
    ...c,
    // The gate checks the plan again at dispatch, after the approval: that decision is not made yet
    plan: plan && {
      ...plan,
      gateDecisions: (plan.gateDecisions ?? []).filter((g) => g.stage !== 'dispatch'),
    },
    summary: { ...c.summary, ...open },
    detail: {
      ...c.detail,
      ...open,
      counts: { ...c.detail.counts, events: kept.length + 1, approvals: 0, attempts: 0 },
    },
    events: [...kept, note],
    approvals: {
      approvals: [],
      tasks: approvals.tasks.map((t) => ({
        ...t,
        action: '',
        userName: '',
        assignedTo: '',
        complete: false,
        timeCompleted: '',
      })),
    },
    attempts: [],
    closure: null,
  } as unknown as CaseFixture;
}

/** The case after a decision in the demo: approved, the recorded outcome; rejected, blocked. */
export function decided(c: CaseFixture, hold: Exclude<Hold, { state: 'awaiting' }>): CaseFixture {
  if (hold.state === 'approved') {
    const events = c.events as Event[];
    const note: Event = {
      seq: (events.at(-1)?.seq ?? 0) + 1,
      at: hold.at,
      kind: 'note',
      text: `Demo replay: approved in the browser by ${hold.by}. The approval, dispatch and verification shown are the recorded case's, including its approver and comment.`,
      actor: 'system',
    };
    return {
      ...c,
      detail: { ...c.detail, counts: { ...c.detail.counts, events: events.length + 1 } },
      events: [...events, note],
    } as unknown as CaseFixture;
  }
  const held = awaiting(c);
  const events = held.events as Event[];
  const headline = `Rejected by ${hold.by}: ${c.summary.headline}`;
  const closed = {
    state: 'blocked',
    version: versionOf(events) + 1,
    headline,
    closedAt: hold.at,
    updatedAt: hold.at,
  };
  const recorded = (c.approvals as { approvals: Record<string, unknown>[] }).approvals[0] ?? {};
  const tasks = (held.approvals as { tasks: Record<string, unknown>[] }).tasks;
  const all: Event[] = [
    ...events,
    {
      seq: (events.at(-1)?.seq ?? 0) + 1,
      at: hold.at,
      kind: 'state',
      fromState: 'awaiting_approval',
      toState: 'blocked',
      text: `Rejected by ${hold.by}${hold.comment ? `: ${hold.comment}` : ''}`,
      actor: hold.by,
    },
  ];
  const gates = (held.plan as { gateDecisions?: GateDecision[] } | null)?.gateDecisions ?? [];
  return {
    ...held,
    summary: { ...held.summary, ...closed },
    detail: { ...held.detail, ...closed },
    events: all,
    // As the server answers when no gate check failed and the rejection is the case's last state change
    blockedReason: {
      code: REJECTED,
      catalogue: catalogueEntry(REJECTED),
      failingChecks: [],
      state: 'blocked',
      headline,
    },
    closure: {
      caseId: c.summary.caseId,
      state: 'blocked',
      disposition: c.summary.disposition,
      outcome: '',
      closedAt: hold.at,
      verification: null,
      verifiedEffects: [],
      unverified: [
        "Consumers beyond the downstream system are outside the production's view and are not verified",
      ],
      actors: [...new Set(all.map((e) => e.actor).filter((a): a is string => !!a))].sort(),
      policyVersion: gates.at(-1)?.policyVersion ?? '',
    },
    approvals: {
      approvals: [
        {
          ...recorded,
          approver: hold.by,
          decision: 'rejected',
          decidedAt: hold.at,
          expiresAt: '',
          comment: hold.comment,
        },
      ],
      tasks: tasks.map((t) => ({
        ...t,
        action: 'Reject',
        userName: hold.by,
        assignedTo: hold.by,
        complete: true,
        timeCompleted: hold.at,
      })),
    },
  } as unknown as CaseFixture;
}

const REJECTED = 'REJECTED_BY_APPROVER';

/** A block reason's catalogue entry (knowledge/block-reasons.json), in the API's names. */
function catalogueEntry(code: string) {
  const r = blockReasons.reasons.find((x) => x.code === code);
  return r
    ? {
        code: r.code,
        title: r.title,
        prerequisite: r.prerequisite,
        nextAction: r.next_action,
        owner: r.owner,
        reevaluateWhen: r.reevaluate_when,
        text: r.text,
      }
    : null;
}

/** The case as the demo shows it now. */
export function heldView(c: CaseFixture, hold: Hold | undefined): CaseFixture {
  if (!hold) return c;
  return hold.state === 'awaiting' ? awaiting(c) : decided(c, hold);
}

/** A fresh hold on every held case the recording can hold. */
export function freshHolds(cases: Record<string, CaseFixture>): Record<string, Hold> {
  return Object.fromEntries(
    HELD_CASES.filter((id) => canHold(cases[id])).map((id) => [id, { state: 'awaiting' } as Hold]),
  );
}
