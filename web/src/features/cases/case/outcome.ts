import type {
  AgentRun,
  ApprovalsView,
  AttemptView,
  BlockedReason,
  CaseDetail,
  Escalation,
  PlanView,
  Snapshot,
} from '@/api/types';
import { displayZone, humanize } from '@/lib/format';
import { asArray, asObject } from '@/lib/json';
import { APPROVALS, caseState, gateOutcome, PROVENANCE, verification } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { checksOf } from './derive';
import { approvalsByPlan, type SafetyReceipt } from './receipt';
import { encounterTimeline } from './timeline';

/**
 * The case page's sentences: the outcome at the top, the next action and the one line each story step shows before
 * it is opened. Every one is put together from the case's structured facts (its state, plan, gate decisions,
 * approvals, attempts, blocked reason and evidence), never written by a model, and a fact that was not read says
 * Unknown rather than being guessed: a missing attempt list is not 0 writes.
 */
export interface CaseFacts {
  c: CaseDetail;
  receipt: SafetyReceipt;
  plan: PlanView | null | undefined;
  /** The plan's read error, when it failed: the plan's panels show it instead of loading. */
  planError?: unknown;
  retryPlan?: () => void;
  approvals: ApprovalsView | null | undefined;
  /** Undefined while the attempts are not read: the writes are then unknown. */
  attempts: AttemptView[] | null | undefined;
  blocked: BlockedReason | null | undefined;
  snapshot: Snapshot | null | undefined;
  /** Undefined while not read: whether a hand-off went out is then unknown. */
  escalations?: Escalation[] | null;
  runs?: AgentRun[] | null;
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));
const CLOSED = ['resolved', 'blocked', 'escalated', 'failed'];

/** A list of facts as one sentence: the first letter raised, a full stop at the end. */
function sentence(parts: string[]): string {
  const text = parts.filter(Boolean).join('; ');
  if (!text) return 'Unknown.';
  const raised = text.charAt(0).toUpperCase() + text.slice(1);
  return /[.?!…]$/.test(raised) ? raised : `${raised}.`;
}

const plural = (n: number, one: string) => `${n} ${one}${n === 1 ? '' : 's'}`;

/** The writes Shutter made, or Unknown while the attempts are not read. */
export function writesText(f: CaseFacts): string {
  if (f.attempts === undefined) return 'Writes unknown';
  const shutter = f.c.disposition === 'handled_by_hand' ? 'Shutter write' : 'write';
  return plural(f.receipt.writes, shutter);
}

/** The systems that sent an operation for the encounter at the same event time as another: S8's two movers. */
export function sameTimeSystems(snapshot: Snapshot | null | undefined): string[] {
  if (!snapshot) return [];
  const rows = encounterTimeline(snapshot.summary, displayZone()).filter((r) => r.sameTime);
  return [...new Set(rows.map((r) => r.system).filter(Boolean))];
}

function sameTimeFact(snapshot: Snapshot | null | undefined): string {
  const systems = sameTimeSystems(snapshot);
  if (systems.length < 2) return '';
  return `${systems.join(' and ')} moved the encounter at the same event time, so which movement is current can't be told from the times`;
}

/** The latest gate decision, or undefined before the gate has checked a plan. */
const lastGate = (plan: PlanView | null | undefined) => plan?.gateDecisions?.at(-1);

/**
 * Whether the gate stopped the case: the blocked reason lists the checks that failed, or the latest gate decision did
 * not pass. A plan a person rejected is blocked too, but not by the gate.
 */
function gateStopped(f: CaseFacts): boolean {
  if (f.blocked?.checks?.length) return true;
  const d = lastGate(f.plan);
  return !!d && d.outcome !== 'pass';
}

const lowerFirst = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);

/** The write the receiver acknowledged, as "version 1 to 2", from the attempt's receipt. */
function appliedVersions(attempts: AttemptView[] | null | undefined): string {
  for (const x of [...(attempts ?? [])].reverse()) {
    const r = asObject(x.attempt?.receipt);
    if (r && r.version_after !== undefined)
      return `version ${str(r.version_before) || 'none'} to ${str(r.version_after)}`;
  }
  return '';
}

/** The headline: the state, the writes and, where there is a write or a hand correction, the verification. */
export function outcomeHeadline(f: CaseFacts): string {
  const { c, receipt } = f;
  const byHand = c.disposition === 'handled_by_hand';
  const parts = [
    byHand ? 'Closed' : c.disposition === 'abandoned' ? 'Abandoned' : caseState(c.state).label,
    byHand ? 'Handled by hand' : '',
    writesText(f),
  ];
  if (receipt.verificationState && (receipt.writes > 0 || byHand))
    parts.push(verification(receipt.verificationState).label);
  return parts.filter(Boolean).join(' · ');
}

/** The short reason under the headline. */
export function outcomeReason(f: CaseFacts): string {
  const { c } = f;
  const target = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
  const sameTime = sameTimeFact(f.snapshot);
  const approvals = f.approvals?.approvals ?? [];
  if (c.disposition === 'handled_by_hand') {
    const gate = lastGate(f.plan);
    return sentence([
      'the team corrected the systems by hand and a person closed the case',
      approvals.some((a) => a.revoked)
        ? `an earlier approval was revoked${approvals.find((a) => a.revoked)?.revokedBy ? ` by ${approvals.find((a) => a.revoked)?.revokedBy}` : ''}`
        : '',
      gate?.outcome === 'block'
        ? `the latest plan was blocked by the gate at ${gate.stage}`
        : gate && gate.outcome !== 'pass'
          ? `the gate's result on the latest plan at ${gate.stage} was ${gateOutcome(gate.outcome, checksOf(gate)).label.toLowerCase()}`
          : '',
      'Shutter did not verify the correction',
    ]);
  }
  switch (c.state) {
    case 'resolved': {
      if (f.receipt.writes > 0) {
        const versions = appliedVersions(f.attempts);
        return sentence([
          `${target} applied at the receiver${versions ? `, ${versions}` : ''}`,
          f.receipt.verificationState === 'verified' ? 'the verifier found the effect there' : '',
        ]);
      }
      return sentence([c.outcome || 'Unknown']);
    }
    case 'blocked':
    case 'escalated': {
      // The reason in words; its code stays with the next action's details and the gate's checks
      const reason =
        f.blocked === undefined
          ? 'reason not read yet'
          : f.blocked?.title || f.blocked?.code || 'reason unknown';
      return sentence([
        c.state === 'blocked' && f.blocked && gateStopped(f)
          ? `blocked by the gate: ${lowerFirst(reason)}`
          : reason,
        sameTime,
      ]);
    }
    case 'failed':
      return sentence([
        c.disposition === 'abandoned'
          ? 'an approver gave the case up after its workflow stopped moving'
          : 'the workflow failed',
        c.outcome,
      ]);
    case 'awaiting_approval':
      return sentence([
        'the plan passed the gate and waits for a person with the approver role to release or reject it',
        sameTime,
      ]);
    default:
      return sentence([caseState(c.state).hint ?? `the case is ${humanize(c.state).toLowerCase()}`]);
  }
}

/** What has to happen next, who does it, and what blocks the case until then. */
export interface NextAction {
  /** none: nothing is waiting; shutter: Shutter is working; person: a person must act. */
  kind: 'none' | 'shutter' | 'person';
  action: string;
  role: string;
  blocking: string;
  lookAgain: string;
  /** For a stopped case: whether the hand-off to the team went out. */
  handoff: string;
  /** Whether escalating to the team is the next step itself, not only a way out of it. */
  escalate: boolean;
}

function handoff(f: CaseFacts): string {
  if (f.escalations === undefined) return 'Unknown';
  const list = f.escalations ?? [];
  const sent = list.filter((e) => e.state === 'sent' || e.state === 'queued').at(-1);
  // Shown beside the label Escalation, so the text does not repeat the word
  if (sent)
    return `${sent.state === 'sent' ? 'Sent' : 'Queued'} to ${sent.teamName || sent.to || "the downstream system's team"}`;
  if (list.some((e) => e.state === 'draft' || e.state === 'failed')) return 'Drafted, not sent';
  return 'Not sent';
}

export function nextAction(f: CaseFacts): NextAction {
  const { c } = f;
  const none = { blocking: '', lookAgain: '', handoff: '', escalate: false };
  if (c.state === 'resolved') return { kind: 'none', action: 'No pending action', role: '', ...none };
  if (c.state === 'failed')
    return {
      kind: 'person',
      action: 'Reinvestigate once the cause is fixed, or leave the case closed',
      role: 'Operator',
      blocking: c.disposition === 'abandoned' ? 'The case was abandoned' : 'The workflow failed',
      lookAgain: '',
      handoff: '',
      escalate: false,
    };
  if (c.state === 'blocked' || c.state === 'escalated') {
    const b = f.blocked;
    const unknown = b === undefined ? 'Not read yet' : 'Unknown';
    return {
      kind: 'person',
      action: b?.nextAction || unknown,
      role: b?.owner || unknown,
      blocking: b?.prerequisite || b?.text || unknown,
      lookAgain: b?.reevaluateWhen ?? '',
      handoff: handoff(f),
      // An escalated case goes to the team; a blocked one only when its reason says to escalate
      escalate: c.state === 'escalated' || /escalat/i.test(b?.nextAction ?? ''),
    };
  }
  if (c.state === 'awaiting_approval')
    return {
      kind: 'person',
      action: `Approve or reject plan v${str(f.plan?.plan?.version) || '?'}`,
      role: 'Approver',
      blocking: 'The write waits for a person to release it; the gate checks it again at dispatch',
      lookAgain: '',
      handoff: '',
      escalate: false,
    };
  return {
    kind: 'shutter',
    action: `No action needed now: Shutter is ${caseState(c.state).label.toLowerCase()}`,
    role: '',
    ...none,
  };
}

// ---- the story steps' one-line summaries ----

const FAILURES: Record<string, string> = {
  delivery_failed: 'was not delivered',
  uncertain_outcome: 'has an unknown outcome',
  rejected: 'was refused',
  unmappable: 'could not be mapped',
  withheld: 'was withheld, never sent',
};

/** "PAS transfer to WARD-B was not delivered: HTTP 503, ward_unavailable." */
export function failedSummary(
  c: CaseDetail,
  what = `${c.sourceSystem ? `${c.sourceSystem} ` : ''}${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''}`,
): string {
  const how = FAILURES[c.failureKind] ?? (humanize(c.failureKind).toLowerCase() || 'failed');
  const detail = [c.failureHttpStatus ? `HTTP ${str(c.failureHttpStatus)}` : '', str(c.failureReasonCode)]
    .filter(Boolean)
    .join(', ');
  return sentence([`${what} ${how}${detail ? `: ${detail}` : ''}`]);
}

/** What failed in a few words, the event and how it failed: "Transfer was not delivered". */
export function failedTitle(c: CaseDetail): string {
  const how = FAILURES[c.failureKind] ?? (humanize(c.failureKind).toLowerCase() || 'failed');
  return `${humanize(c.event) || 'The operation'} ${how}`;
}

/** The sending systems a header names, glossed at first use. */
const SYSTEMS: Record<string, string> = {
  PAS: 'patient administration system',
  BEDMGR: 'bed manager',
};

/**
 * The header's one sentence: what failed, put together from the case's facts and never cut. What Shutter did about it
 * is the Outcome card's.
 */
export function headerSentence(c: CaseDetail): string {
  const system = c.sourceSystem
    ? `${c.sourceSystem}${SYSTEMS[c.sourceSystem] ? ` (${SYSTEMS[c.sourceSystem]})` : ''} `
    : '';
  const what = `${system}${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''}`;
  const summary = failedSummary(c, what);
  // A system's name keeps its capitals; an event's first letter is lowered after "The"
  return `The ${system ? summary : summary.charAt(0).toLowerCase() + summary.slice(1)}`;
}

/** What the receiver holds, whether it has a receipt for this operation, and the facts that complicate it. */
export function evidenceSummary(snapshot: Snapshot | null | undefined): string {
  if (!snapshot) return 'No evidence yet.';
  const item = (kind: string) => snapshot.items.find((x) => x.kind === kind);
  const parts: string[] = [];
  const ward = asObject(item('ward_state')?.data);
  if (ward && !ward.not_applicable) {
    const status = Number(ward.http_status);
    const b = asObject(ward.body) ?? {};
    parts.push(
      status === 200
        ? `the receiver holds the encounter ${humanize(str(b.state)).toLowerCase()}${b.ward ? ` in ${str(b.ward)}` : ''} at version ${str(b.version)}`
        : status === 404
          ? 'the receiver has no such encounter'
          : "the receiver's state is unknown",
    );
  }
  const receipt = asObject(item('receipt')?.data);
  if (receipt && !receipt.not_applicable) {
    const status = Number(receipt.http_status);
    const b = asObject(receipt.body) ?? {};
    parts.push(
      status === 200
        ? `it committed this operation, version ${str(b.version_before)} to ${str(b.version_after)}`
        : status === 404
          ? 'no receipt for this operation'
          : 'whether it committed this operation is unknown',
    );
  }
  const later = asObject(item('later_event')?.data);
  if (later)
    parts.push(
      `a later ${humanize(str(later.event)).toLowerCase()}${later.ward ? ` to ${str(later.ward)}` : ''}`,
    );
  const systems = sameTimeSystems(snapshot);
  if (systems.length > 1) parts.push(`${systems.join(' and ')} have the same event time`);
  return sentence(parts.length ? parts : [`${plural(snapshot.items.length, 'observation')} recorded`]);
}

/** Who proposed what: the coordinator, one agent, the rules or the site's policy, with any dissent kept. */
export function proposedSummary(f: CaseFacts): string {
  const p = f.plan?.plan;
  if (!p) return f.plan === undefined ? 'Not read yet.' : 'No plan yet.';
  const by = p.createdBy ?? '';
  const runs = f.runs ?? [];
  // A withheld merge or cancel has no agent run: nobody proposed a write, and a person decides
  if (by === 'withheld')
    return 'Nobody proposed a write: Shutter withholds merges and cancels; a person decides.';
  const who = by.startsWith('policy:')
    ? `the site's policy, entry ${by.slice('policy:'.length)}`
    : by === 'rules'
      ? 'the rules'
      : runs.some((r) => r.role === 'coordinator')
        ? 'the coordinator'
        : runs.some((r) => r.role === 'generalist')
          ? 'one agent'
          : by.startsWith('run:') || !by
            ? 'unknown'
            : by;
  const action =
    p.disposition === 'resend'
      ? `resend the operation unchanged, on condition the receiver is at version ${str(p.expectedVersion)}`
      : `${humanize(p.disposition).toLowerCase()} without writing`;
  // The specialists whose disagreement the coordinator kept, by name, with what each proposed instead
  const dissent = asArray(
    asObject(runs.filter((r) => r.role === 'coordinator').at(-1)?.result)?.disagreements,
  )
    .map((d) => asObject(d) ?? {})
    .map((d) => {
      const name = runs.find((r) => r.memberCode === str(d.member))?.member?.name ?? humanize(str(d.member));
      const said = /^[a-z_]+/.exec(str(d.said))?.[0];
      return `${name} dissented${said ? `, proposing ${humanize(said).toLowerCase()}` : ''}`;
    });
  return sentence([`${who}: ${action}`, ...dissent.map((d) => `${d} (kept in the plan)`)]);
}

/** The gate's latest result and who or what released the write. */
export function decisionSummary(f: CaseFacts): string {
  const d = lastGate(f.plan);
  const gate = d ? `gate ${gateOutcome(d.outcome, checksOf(d)).label.toLowerCase()} at ${d.stage}` : '';
  if (!f.plan?.plan) return f.plan === undefined ? 'Not read yet.' : 'No plan for the gate yet.';
  const by = f.receipt.decidedBy;
  const earlier = f.receipt.earlierApproval;
  return sentence([
    gate || 'the gate has not checked the plan yet',
    f.c.state === 'awaiting_approval'
      ? 'waiting for approval'
      : by === 'Unknown'
        ? 'who released it is unknown'
        : by.charAt(0).toLowerCase() + by.slice(1),
    earlier ? earlier.charAt(0).toLowerCase() + earlier.slice(1) : '',
  ]);
}

/** The writes Shutter sent, with the receiver's versions when one landed. */
export function writtenSummary(f: CaseFacts): string {
  if (f.attempts === undefined) return 'Unknown: the attempts are not read yet.';
  const r = f.receipt;
  if (!r.writes) {
    const extra = r.notWritten ? `; ${plural(r.notWritten, 'attempt')} the receiver did not take` : '';
    return sentence([`0 writes by Shutter${extra}`]);
  }
  const versions = appliedVersions(f.attempts);
  return sentence([
    `${plural(r.writes, 'conditional write')}, ${r.acknowledged} acknowledged${versions ? `, receiver ${versions}` : ''}`,
  ]);
}

/** What the verifier found, or why there is nothing to verify. */
export function verifiedSummary(f: CaseFacts): string {
  const r = f.receipt;
  if (!r.verification) return CLOSED.includes(f.c.state) ? 'Unknown.' : 'Nothing to verify yet.';
  return sentence([r.verification]);
}

/**
 * The release as a status, its badge beside the receipt's words for who decided: a person's approval or rejection of
 * the current plan, the site's written policy, an approval waiting, the current plan's approval revoked, or none
 * needed for a plan that writes nothing. Only the current plan's approval can be its release: an earlier plan's is
 * history, named in the gate and decision step. Undefined when there is no status to show, or the approvals are not
 * read.
 */
export function releaseStatus(f: CaseFacts): Status | undefined {
  const write = f.plan?.plan?.disposition === 'resend';
  if (f.plan?.plan && !write) return APPROVALS.not_required;
  if (f.c.state === 'awaiting_approval') return APPROVALS.awaiting;
  if (f.approvals === undefined) return undefined;
  const { current } = approvalsByPlan(f.approvals, f.plan);
  const latest = current.filter((a) => !a.revoked).at(-1) ?? current.at(-1);
  if (!latest) return undefined;
  if (latest.decision !== 'approved') return APPROVALS.rejected;
  // Revoked once its write was sent, the approval still released that write; revoked before, it released nothing
  if (latest.revoked && !f.receipt.writes) return APPROVALS.revoked;
  return latest.approver === 'policy' ? { ...APPROVALS.policy, label: 'Site policy' } : APPROVALS.approved;
}

/** Where an agent's answer came from on this case: the rules, a live model, a recorded replay, or the site's policy. */
export function provenanceOf(mode: string, runs: AgentRun[] | null | undefined): Status {
  if (mode === 'rules') return PROVENANCE.rules;
  if (runs === undefined) return { tone: 'neutral', label: 'Unknown' };
  const list = runs ?? [];
  if (!list.length)
    return {
      ...PROVENANCE.rules,
      label: mode === 'policy' ? "No model: the site's policy" : 'No agent run yet',
      hint: undefined,
    };
  if (list.some((r) => r.mode !== 'replay')) return PROVENANCE.live;
  return PROVENANCE.replay;
}
