import type {
  AgentRun,
  ApprovalsView,
  AttemptView,
  BlockedReason,
  CaseDetail,
  CaseEvent,
  Escalation,
  PlanView,
  Snapshot,
} from '@/api/types';
import { TRIAL } from '@/env/mode';
import { displayZone, humanize } from '@/lib/format';
import { asArray, asObject } from '@/lib/json';
import { APPROVALS, caseState, gateOutcome, PROVENANCE, ranOnIris, type OutcomeCase } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { checksOf, failureKindInWords, orderOrResult, outageResend } from './derive';
import { planLeader } from './follows';
import { approvalsByPlan, WRITE_OUTCOMES, type SafetyReceipt } from './receipt';
import { NOT_CHECKED, notCheckedAtReceiver } from './receiver';
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
  /** Whether the agent runs have been read, or failed to be: until then the page cannot tell where the board goes. */
  runsSettled?: boolean;
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

/** The systems that sent an operation for the encounter at the same event time as another: S8's two movers. */
export function sameTimeSystems(snapshot: Snapshot | null | undefined): string[] {
  if (!snapshot) return [];
  const rows = encounterTimeline(snapshot.summary, displayZone()).filter((r) => r.sameTime);
  return [...new Set(rows.map((r) => r.system).filter(Boolean))];
}

/** S8's second source in words, where the page says who moved the patient. */
const glossSystem = (system: string) => (system === 'BEDMGR' ? 'the bed manager (BEDMGR)' : system);

function sameTimeFact(snapshot: Snapshot | null | undefined): string {
  const systems = sameTimeSystems(snapshot);
  if (systems.length < 2) return '';
  return `${systems.map(glossSystem).join(' and ')} moved the encounter at the same event time, so the times can't say which movement is current`;
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

/**
 * What came of the case, as the case list and the outcome band colour it (lib/status.ts caseOutcome): its state and
 * disposition, and what it wrote and what the verifier found once the attempts are read. Only a verifier's own outcome
 * counts as a verification, as the case list's summary counts it; until the attempts are read both stay unknown, so the
 * outcome reads "Resolved" rather than guessing.
 */
export function outcomeCaseOf(f: CaseFacts): OutcomeCase {
  const { c, receipt } = f;
  const base: OutcomeCase = {
    state: c.state,
    disposition: c.disposition,
    receiver: c.receiver,
    mode: c.mode,
  };
  if (f.attempts === undefined) return base;
  return {
    ...base,
    writes: receipt.writes,
    verification: VERIFIER_OUTCOMES.includes(receipt.verificationState) ? receipt.verificationState : '',
  };
}

/** The verifier's own outcomes; the receipt's other verification states say why there was none. */
const VERIFIER_OUTCOMES = ['verified', 'unresolved', 'not_committed', 'failed'];

/** Whether the receiver's dry run of the plan's exact write passed. */
const rehearsed = (f: CaseFacts) => f.plan?.rehearsal?.wouldApply === true;

/** "once", "twice", "3 times". */
const times = (n: number) => (n === 1 ? 'once' : n === 2 ? 'twice' : `${n} times`);

/**
 * The writes of a case that stopped after sending one. A write whose answer was lost may have landed, and may still land,
 * and one the receiver acknowledged was sent whatever the verifier then found, so neither reads as nothing sent.
 */
function stoppedWrites(f: CaseFacts, event: string): string {
  const sent = f.receipt.writes;
  const last = [...(f.attempts ?? [])]
    .reverse()
    .find((x) => WRITE_OUTCOMES.includes(str(x.attempt?.outcome)));
  const answer =
    str(last?.attempt?.outcome) === 'uncertain'
      ? sent === 1
        ? 'and the answer was lost'
        : 'and the last answer was lost'
      : sent === 1
        ? 'and the receiver acknowledged it'
        : 'and the receiver acknowledged the last';
  return `Sent the ${event} again, ${times(sent)}, ${answer}`;
}

/**
 * What Shutter did, leading with the action, since the outcome band above it says what came of it: "Sent the transfer
 * again, once, after a test run", "Asked a person to decide; sent nothing", "Sent nothing: a later event already moved
 * the patient on", "Sent the transfer again, once, and the answer was lost; a person decides". Built from the
 * disposition, the writes and whether the rehearsal passed; a write count not read yet is never guessed.
 */
export function actionHeadline(f: CaseFacts): string {
  const { c, receipt } = f;
  const event = humanize(c.event).toLowerCase() || 'message';
  const disposition = f.plan?.plan?.disposition || c.disposition;
  const unknown = f.attempts === undefined;
  const sent = receipt.writes;
  const sentAgain = `Sent the ${event} again, ${times(sent)}${rehearsed(f) ? ', after a test run' : ''}`;
  if (c.disposition === 'handled_by_hand') return 'Handed it to the team, who corrected it by hand';
  if (c.disposition === 'abandoned') return 'Gave the case up when its workflow stopped moving';
  if (c.disposition === 'already_delivered')
    return 'Already delivered: resent with the outage, and the receiver reported it already holds it';
  // Resent through the engine with its receiver's outage, under an approver's approval on the outage card
  const resent = outageResend(c);
  if (resent?.closure === 'sent')
    return `Resent it through the engine with the outage, under approval ${resent.runId}`;
  switch (c.state) {
    case 'resolved':
      if (unknown) return 'Closed the case; what it sent is not read yet';
      if (sent > 0) return sentAgain;
      if (disposition === 'superseded') return 'Sent nothing: a later event already moved the patient on';
      if (disposition === 'reconcile') return 'Sent nothing: the receiver already has it';
      return 'Closed the case; sent nothing';
    case 'escalated':
      if (unknown) return 'Asked a person to decide; what it sent is not read yet';
      return sent > 0
        ? `${stoppedWrites(f, event)}; a person decides`
        : 'Asked a person to decide; sent nothing';
    case 'blocked': {
      const rejected = (f.approvals?.approvals ?? []).some((a) => a.decision === 'rejected' && !a.revoked);
      const why = rejected
        ? 'a person rejected the plan'
        : gateStopped(f)
          ? 'the gate stopped the plan'
          : 'the case was stopped';
      if (unknown) return `Stopped: ${why}; what it sent is not read yet`;
      return sent > 0 ? `${stoppedWrites(f, event)}; then ${why}` : `Sent nothing: ${why}`;
    }
    case 'failed':
      if (unknown) return 'Stopped when the workflow failed; what it sent is not read yet';
      return sent === 0
        ? 'Stopped when the workflow failed; sent nothing'
        : `${sentAgain}; then the workflow failed`;
    case 'awaiting_approval':
      return rehearsed(f)
        ? 'Tested the fix at the receiver; sent nothing yet'
        : 'Prepared the fix; sent nothing yet';
    default:
      return `Working on it: ${caseState(c.state).label.toLowerCase()}`;
  }
}

/**
 * When the recorded case was approved: the time its events record the move out of awaiting approval, "20 Oct, 17:24
 * UTC", for the note the trial shows once it has replayed what the case did after a reader's approval. Empty when the
 * events record no approval.
 */
export function recordedApprovalTime(events: CaseEvent[] | null | undefined): string {
  const e = (events ?? []).find(
    (x) => x.kind === 'state' && x.fromState === 'awaiting_approval' && x.toState === 'approved',
  );
  const d = e?.at ? new Date(e.at) : null;
  if (!d || Number.isNaN(d.getTime())) return '';
  const day = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(d);
  return `${day}, ${d.toISOString().slice(11, 16)} UTC`;
}

/** The short reason under What Shutter did. */
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
      notCheckedAtReceiver(c, f.snapshot, f.attempts)
        ? lowerFirst(NOT_CHECKED)
        : 'Shutter did not verify the correction',
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
        'the plan passed the gate and waits for a person with the approver role to approve or reject it',
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
  const sent = list.filter((e) => ['sent', 'saved', 'queued'].includes(e.state)).at(-1);
  // Shown beside the label Escalation, so the text does not repeat the word
  if (sent) {
    const team = sent.teamName || sent.to || "the downstream system's team";
    // Saved as an .eml file with no mail server: nobody was emailed, and the line says so
    if (sent.state === 'saved') return `Saved as an email file for ${team}, not delivered`;
    return `${sent.state === 'sent' ? 'Sent' : 'Queued'} to ${team}`;
  }
  if (list.some((e) => e.state === 'draft' || e.state === 'failed')) return 'Drafted, not sent';
  return 'Not sent';
}

export function nextAction(f: CaseFacts): NextAction {
  const { c } = f;
  const none = { blocking: '', lookAgain: '', handoff: '', escalate: false };
  if (c.state === 'resolved') return { kind: 'none', action: 'No pending action', role: '', ...none };
  // An abandoned case was given up on purpose: nothing is pending, and the card keeps Reinvestigate for when the cause
  // is fixed, in the neutral tone, as the action button at the top says no action is needed
  if (c.state === 'failed' && c.disposition === 'abandoned')
    return { kind: 'none', action: 'No pending action: the case was abandoned', role: '', ...none };
  if (c.state === 'failed')
    return {
      kind: 'person',
      action: 'Reinvestigate once the cause is fixed, or leave the case closed',
      role: 'Operator',
      blocking: 'The workflow failed',
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
  unreadable: 'was held: its HL7 schema is not loaded here',
  withheld: 'was withheld, never sent',
};

/** How a delivery failed in a few words; a message Shutter does not model by what the receiver did with it. */
function failedHow(c: CaseDetail): string {
  return FAILURES[failureKindInWords(c)] ?? (humanize(c.failureKind).toLowerCase() || 'failed');
}

/**
 * What was sent, in a few words: "PAS transfer to WARD-B", or for an order or a result "QUILLON result": it goes to no
 * ward, so the location its PV1 carries is not named as a destination.
 */
export function whatWasSent(c: CaseDetail): string {
  const system = c.sourceSystem ? `${c.sourceSystem} ` : '';
  const kind = orderOrResult(c);
  if (kind) return `${system}${kind}`;
  return `${system}${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''}`;
}

/** "PAS transfer to WARD-B was not delivered: HTTP 503, ward_unavailable." */
export function failedSummary(c: CaseDetail, what = whatWasSent(c)): string {
  const how = failedHow(c);
  // A withheld message was never sent, so its reason code ("merge") is no error, and a code that only repeats the event
  // reads as a slip: the words already say what happened
  const reason =
    failureKindInWords(c) === 'withheld' || str(c.failureReasonCode) === str(c.event)
      ? ''
      : str(c.failureReasonCode);
  const detail = [c.failureHttpStatus ? `HTTP ${str(c.failureHttpStatus)}` : '', reason]
    .filter(Boolean)
    .join(', ');
  return sentence([`${what} ${how}${detail ? `: ${detail}` : ''}`]);
}

/** What failed in a few words, the event and how it failed: "Transfer was not delivered". */
export function failedTitle(c: CaseDetail): string {
  const how = failedHow(c);
  const kind = orderOrResult(c);
  return `${kind ? `${kind.charAt(0).toUpperCase()}${kind.slice(1)}` : humanize(c.event) || 'The operation'} ${how}`;
}

/** The sending systems in words, for the failure map's list and a screen reader's sentence. */
export const SYSTEMS: Record<string, string> = {
  PAS: 'patient administration system',
  BEDMGR: 'bed manager',
};

/**
 * The header's one sentence: what failed, put together from the case's facts and never cut. What Shutter did about it
 * is the Outcome card's. The sending system is named by its short name ("The PAS transfer..."): the header defines it
 * in a `Term`, a click away, rather than spelling it out in the sentence.
 */
export function headerSentence(c: CaseDetail): string {
  const system = c.sourceSystem ? `${c.sourceSystem} ` : '';
  const summary = failedSummary(c, whatWasSent(c));
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
        ? `when Shutter looked, the receiver held the encounter ${humanize(str(b.state)).toLowerCase()}${b.ward ? ` in ${str(b.ward)}` : ''} at version ${str(b.version)}`
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

/**
 * The evidence step's line: what was observed and from where, since the outcome's first card already says what the
 * evidence found. "7 observations: the message, the connector, Downstream Out and the encounter's timeline."
 */
export function observationsSummary(snapshot: Snapshot | null | undefined, receiver?: string): string {
  if (!snapshot) return 'No evidence yet.';
  const kinds = new Set(snapshot.items.map((x) => x.kind));
  const from = [
    kinds.has('message') ? 'the message' : '',
    kinds.has('error') || kinds.has('route') ? 'the connector' : '',
    kinds.has('ward_state') || kinds.has('receipt') ? receiver || 'the receiver' : '',
    "the encounter's timeline",
  ].filter(Boolean);
  const list = from.length > 1 ? `${from.slice(0, -1).join(', ')} and ${from.at(-1)}` : from[0];
  return `${plural(snapshot.items.length, 'observation')}: ${list}.`;
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
    : planLeader(by)
      ? `the board of case ${planLeader(by)}`
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
  // A resend through the engine with the outage writes no conditional write of the case's own: the ledger's words say it
  const resent = outageResend(f.c);
  if (resent?.words)
    return sentence([resent.words.replace(/\.$/, ''), 'the engine sent the stored message unchanged']);
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
  const notChecked = notCheckedAtReceiver(f.c, f.snapshot, f.attempts);
  if (notChecked) return sentence([NOT_CHECKED, notChecked.accepted]);
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
  // Released on the outage card: an approver approved the outage's list, this message among them
  const resent = outageResend(f.c);
  if (resent) return { ...APPROVALS.approved, label: `Approved on the outage (${resent.runId})` };
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

/**
 * Where an agent's answer came from on this case: how it executed, which the mode (who proposed the plan) does not say.
 * On IRIS it is what the case's own runs record. In the trial the page shows a recording in the browser and runs
 * nothing, so it says that first, and what IRIS ran when the case was recorded second: a recorded board case is never
 * read as inference made now.
 */
export function provenanceOf(mode: string, runs: AgentRun[] | null | undefined, trial = TRIAL): Status {
  const recorded = ranOnIris(mode, runs);
  // While the runs are still being read, a case with agents says Unknown, as on IRIS
  if (!trial || (mode !== 'rules' && runs === undefined)) return recorded;
  return {
    ...PROVENANCE.recording,
    label: `${PROVENANCE.recording.label}: no new inference`,
    hint: `${PROVENANCE.recording.hint}. When it was recorded on IRIS: ${recorded.label}.`,
  };
}

const wordCount = (t: string) => t.trim().split(/\s+/).filter(Boolean).length;

/**
 * A next action short enough to head its card, and the rest of it for the card's details: an action of up to 16 words
 * stays whole; a longer one is cut after its first sentence, and a first sentence still longer than that at its first
 * colon or semicolon. Never mid-phrase, and no word is dropped: the head and the rest together say all of it.
 */
export function actionHead(text: string, most = 16): { head: string; rest: string } {
  const all = text.trim();
  if (wordCount(all) <= most) return { head: all, rest: '' };
  const sentence = /^(.+?[.!?])\s+(\S.*)$/s.exec(all);
  let head = sentence ? sentence[1] : all;
  let rest = sentence ? sentence[2] : '';
  if (wordCount(head) > most) {
    const clause = /^(.+?)[;:]\s+(\S.*)$/s.exec(head);
    if (clause && wordCount(clause[1]) >= 3) {
      const after = clause[2].charAt(0).toUpperCase() + clause[2].slice(1);
      head = clause[1];
      rest = [after, rest].filter(Boolean).join(' ');
    }
  }
  return { head, rest };
}
