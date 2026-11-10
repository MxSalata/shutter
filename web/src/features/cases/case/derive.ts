import type { CaseEvent, CaseResend, GateCheck, GateDecision, SnapshotItem } from '@/api/types';
import { asArray, asObject } from '@/lib/json';
import { formatTime, humanize } from '@/lib/format';

/** Pure helpers behind the case page's panels: what they derive from the API's data, kept apart to be tested. */

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/**
 * What a receiver did with a message Shutter does not model, an order, a result or a document (CONTRACTS v1.45). Its kind
 * says unmappable because there is no operation to resend, and the message itself may be sound, so the words come from
 * the receiver's outcome. Null for every other case.
 */
export function notModelled(c: {
  failureText?: unknown;
  failureOutcome?: unknown;
}): 'not_delivered' | 'unknown' | 'refused' | null {
  if (!/^This message is [^ ,]+, not ADT:/.test(str(c.failureText))) return null;
  const outcome = str(c.failureOutcome);
  if (outcome === 'uncertain') return 'unknown';
  return outcome === 'rejected' ? 'refused' : 'not_delivered';
}

/** What Shutter does with a message it does not model, as Shutter.Store.Case.NOTMODELLEDWHAT says it (1.4.1). */
export const NOT_MODELLED_WHAT =
  'Shutter does not resend it from its case, so a person decides; where its receiver is set up for the outage resend, an approver can have the engine send it again from the Incidents page';

/**
 * A failure text as it reads now (Shutter.Store.Case.ShownFailureText): the words stored before 1.4.1, "Shutter resends
 * only ADT, so it sends nothing and a person decides" or a shorter form, are no longer true and read as NOT_MODELLED_WHAT,
 * with what the source reported after them kept. Any other text is returned as it is.
 */
export function shownFailureText(text: unknown): string {
  const t = str(text);
  const at = t.indexOf('Shutter resends only ADT');
  if (at < 0) return t;
  const source = t.indexOf('. The source reported: ', at);
  return `${t.slice(0, at)}${NOT_MODELLED_WHAT}${source >= 0 ? t.slice(source) : ''}`;
}

/**
 * Whether a case is an order or a result, and which: "result" (an ORU, event R01, R30 and the like) or "order" (ORM,
 * OML and the like, event O01, O21 ...), by the event code or the structure a message Shutter does not model names in its
 * failure text; null for anything else. An order or a result goes to no ward and asks for no bed, so its sentence names
 * neither.
 */
export function orderOrResult(c: { event?: unknown; failureText?: unknown }): 'order' | 'result' | null {
  const event = str(c.event);
  if (/^r\d\d$/i.test(event)) return 'result';
  if (/^o\d\d$/i.test(event)) return 'order';
  const structure = /^This message is ([^ ,]+), not ADT:/.exec(str(c.failureText))?.[1] ?? '';
  if (/^(ORU|OUL)/i.test(structure)) return 'result';
  if (/^O/i.test(structure)) return 'order';
  return null;
}

/** The kind whose words fit the case: for a message Shutter does not model, the one that says what the receiver did. */
export function failureKindInWords(c: {
  failureKind?: string;
  failureText?: unknown;
  failureOutcome?: unknown;
}): string {
  const what = notModelled(c);
  if (what === 'unknown') return 'uncertain_outcome';
  if (what === 'refused') return 'rejected';
  if (what === 'not_delivered') return 'delivery_failed';
  return c.failureKind ?? '';
}

/**
 * Where a forwarded case's message came from, as the case and its `source` evidence name it: "HOSPITAL /
 * Hospital.Production, route PAS In, message header 4243". Empty for a case the feed in Shutter's own production opened.
 */
export function forwardedFrom(source: {
  namespace?: unknown;
  production?: unknown;
  route?: unknown;
  headerId?: unknown;
}): string {
  if (!str(source.namespace)) return '';
  return `${str(source.namespace)}${source.production ? ` / ${str(source.production)}` : ''}${source.route ? `, route ${str(source.route)}` : ''}${source.headerId ? `, message header ${str(source.headerId)}` : ''}`;
}

/** What each kind of observation is, as the evidence lists name them. */
const KIND_LABELS: Record<string, string> = {
  findings: 'What Shutter found in the order or result',
  operation: 'The failed operation',
  error: 'What the connector reported',
  message: 'The HL7 message',
  validation: 'Schema validation',
  ward_state: "The downstream system's encounter",
  receipt: "The downstream system's receipt for this operation",
  later_event: 'A later event for the encounter',
  route: 'The route and what the connector guarantees',
  source: 'Where the original message lives',
  note: 'Note',
};

/**
 * The label of an observation's kind; the receiver's own observations name the case's receiver (its production item)
 * when the case names one.
 */
export function kindLabel(kind: string, receiver?: string): string | undefined {
  if (receiver && kind === 'ward_state') return `${receiver}'s encounter`;
  if (receiver && kind === 'receipt') return `${receiver}'s receipt for this operation`;
  return KIND_LABELS[kind];
}

/** One line that says what an observation found, so the list reads without opening each item. */
export function describeItem(item: SnapshotItem, receiver?: string): string {
  const noun = receiver || 'the downstream system';
  const d = asObject(item.data) ?? {};
  switch (item.kind) {
    case 'operation':
      return `${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''} at ${formatTime(str(d.event_time))} for ${str(d.encounter_id)}`;
    case 'error':
      return `${humanize(str(d.kind))}: ${shownFailureText(d.text)}`;
    case 'message': {
      const notes = asArray(d.notes);
      return `${str(d.message_type)} ${str(d.message_control_id)} from ${str(d.sending_application)}, location ${str(d.assigned_location).split('^')[0]}${notes.length ? `, ${notes.length} free-text note${notes.length > 1 ? 's' : ''}` : ''}`;
    }
    case 'validation': {
      // The version the message says and the category its route parses it with, when they differ (a note, never a failure)
      const version = d.message_version
        ? `; HL7 ${str(d.message_version)} parsed as ${str(d.route_category)}${d.version_agrees === false && d.version_note ? `: ${str(d.version_note)}` : ''}`
        : '';
      return d.parsed
        ? `Parses as ${str(d.doc_type)}${version}`
        : `Does not parse${d.error ? `: ${str(d.error)}` : ''}${version}`;
    }
    case 'ward_state': {
      if (d.not_applicable) return 'Not applicable: the message names no encounter';
      const status = Number(d.http_status);
      const b = asObject(d.body) ?? {};
      if (status === 200)
        return `${humanize(str(b.state))}${b.ward ? ` in ${str(b.ward)}` : ''}, version ${str(b.version)}${b.epoch !== undefined ? `, epoch ${str(b.epoch)}` : ''}; ${asArray(b.history).length} operations in its history`;
      if (status === 404) return `${noun.charAt(0).toUpperCase()}${noun.slice(1)} has no such encounter`;
      // A receiver whose description names no state endpoint (an orders and results receiver with no API) was not asked
      if (!status && /no state endpoint/.test(str(b.error)))
        return `Not read: ${noun} has no record Shutter reads (no state endpoint in its description)`;
      return `Could not be read (HTTP ${status || 'none'}): unknown`;
    }
    case 'receipt': {
      if (d.not_applicable) return 'Not applicable: the message names no encounter';
      const status = Number(d.http_status);
      const b = asObject(d.body) ?? {};
      if (status === 200)
        return `Committed: version ${str(b.version_before)} to ${str(b.version_after)}, at ${formatTime(str(b.applied_at))}`;
      if (status === 404) return `No receipt: ${noun} did not commit this operation`;
      // -1: the receiver keeps no receipts (no receipt path in its description), as against 0 for no answer
      if (status === -1) return `Not read: ${noun} keeps no receipts Shutter reads`;
      return `The lookup did not answer (HTTP ${status || 'none'}): committed or not is unknown`;
    }
    case 'pending_messages': {
      const n = Number(d.count ?? asArray(d.items).length) || 0;
      return n
        ? `${n} later message${n === 1 ? '' : 's'} of the encounter not yet delivered: a resend waits for ${n === 1 ? 'it' : 'them'}`
        : 'None: no later message of the encounter is waiting to be delivered';
    }
    case 'further_messages': {
      if (d.identifier === 'unreadable') return 'Not read: the message names no patient Shutter can look up';
      const stops = asArray(d.stops).length;
      const shows = asArray(d.shows).length;
      const unread = str(d.unread);
      if (!stops && !shows)
        return `None found for the patient after this message${unread ? `; not read in full: ${unread}` : ''}`;
      return [
        stops ? `${stops} that stop${stops === 1 ? 's' : ''} a write` : '',
        shows ? `${shows} shown on the plan` : '',
        unread ? `not read in full: ${unread}` : '',
      ]
        .filter(Boolean)
        .join('; ');
    }
    case 'later_event':
      return `${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''} at ${formatTime(str(d.event_time))} (${humanize(str(d.outcome))})`;
    case 'route':
      return `${str(d.feed)}`;
    case 'source': {
      const from = forwardedFrom({
        namespace: d.namespace,
        production: d.production,
        route: d.route,
        headerId: d.header_id,
      });
      return `Forwarded from ${from || 'another production'}`;
    }
    default:
      return str(d.text) || `Recorded from ${SOURCE_WORDS[item.source] ?? 'the production'}`;
  }
}

/** Where an evidence item was read, in words: the snapshot's source names are identifiers, not for a reader. */
const SOURCE_WORDS: Record<string, string> = {
  message_store: 'the message store',
  production: 'the production',
  validator: "the message's schema",
  ward_api: "the receiver's API",
};

/** The workflow's phases and the case states that belong to each (Shutter.Process.CaseWorkflow). */
export const PHASES = [
  { key: 'evidence', label: 'Evidence', states: ['detected', 'collecting'] },
  // A case an incident holds waits in grouped until the incident releases it into its dispatch
  { key: 'investigation', label: 'Investigation', states: ['investigating', 'grouped'] },
  { key: 'gate', label: 'Plan and gate', states: ['proposed', 'gated'] },
  { key: 'rehearsal', label: 'Rehearsal', states: ['rehearsing'] },
  { key: 'approval', label: 'Approval', states: ['awaiting_approval'] },
  // After the approval: the preflight read of the receiver and the dispatch gate, then the write
  { key: 'dispatch', label: 'Dispatch', states: ['approved', 'executing'] },
  { key: 'verification', label: 'Verification', states: ['verifying'] },
] as const;

const phaseOf = (state: string) => PHASES.findIndex((p) => (p.states as readonly string[]).includes(state));

/** Where the latest round began: the last move into collecting evidence (a re-plan starts one). */
function latestRoundStart(events: CaseEvent[]): number {
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].kind === 'state' && events[i].toState === 'collecting') return i;
  }
  return 0;
}

/** How many rounds of evidence and planning the case has had: more than one after a re-plan. */
export function rounds(events: CaseEvent[]): number {
  return Math.max(1, events.filter((e) => e.kind === 'state' && e.toState === 'collecting').length);
}

export type PhaseStatus = 'done' | 'current' | 'skipped' | 'stopped' | 'pending';

/**
 * Each phase's status, from the states the case has been through (its state events) and the state it is in. A
 * closed case that wasn't resolved stopped in the phase it was in when it closed; phases a plan doesn't need (no
 * write: no rehearsal, approval or dispatch) show as skipped.
 */
export function phaseStatuses(state: string, events: CaseEvent[]): PhaseStatus[] {
  const visited = new Set<number>();
  let stoppedAt = -1;
  // A re-plan starts a new round at the evidence: only the latest round's states count, and the move that starts
  // it counts only for where it goes (it leaves the earlier round's approval behind)
  const start = latestRoundStart(events);
  for (const [i, e] of events.slice(start).entries()) {
    if (e.kind !== 'state') continue;
    const from = start > 0 && i === 0 ? -1 : phaseOf(e.fromState);
    const to = phaseOf(e.toState);
    if (from >= 0) visited.add(from);
    if (to >= 0) visited.add(to);
    if (to < 0 && ['blocked', 'escalated', 'failed'].includes(e.toState)) stoppedAt = from;
  }
  const current = phaseOf(state);
  if (current >= 0) visited.add(current);
  const furthest = Math.max(-1, ...visited);
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(state);
  return PHASES.map((_, i) => {
    if (closed && state !== 'resolved' && i === stoppedAt) return 'stopped';
    if (!closed && i === current) return 'current';
    if (visited.has(i)) return 'done';
    if (i < furthest || (closed && state === 'resolved')) return 'skipped';
    return 'pending';
  });
}

export function checksOf(d: GateDecision): GateCheck[] {
  return asArray<GateCheck>(d.checks);
}

/**
 * One entry of a finding's list in words: a kept disagreement ("Conformance said resend: ...") or a cited event
 * ("transfer to WARD-C at 09:45:00, from the downstream history"); anything else as JSON.
 */
export function describeEntry(x: unknown): string {
  if (typeof x === 'string') return x;
  const o = asObject(x);
  if (!o) return JSON.stringify(x);
  const s = (k: string) => (o[k] === undefined || o[k] === null ? '' : String(o[k]));
  if (o.member !== undefined && o.said !== undefined)
    return `${humanize(s('member'))} said ${humanize(s('said')).toLowerCase()}${o.why_kept || o.why ? `: ${s('why_kept') || s('why')}` : ''}`;
  if (o.event !== undefined && (o.event_time !== undefined || o.ward !== undefined))
    return `${humanize(s('event'))}${o.ward ? ` to ${s('ward')}` : ''}${o.event_time ? ` at ${formatTime(s('event_time'))}` : ''}${o.source ? `, from the ${s('source')}` : ''}`;
  // An observation or a free-text note, as the evidence collector records them: { observation_id, text }
  if (typeof o.text === 'string') return o.text;
  return JSON.stringify(x);
}

/**
 * The case's events split into its rounds: a re-plan starts a new round with the move into collecting evidence, so
 * each round holds its own evidence, plan, gate checks, rehearsal, release, dispatch and verification. Oldest first.
 */
export function eventRounds(events: CaseEvent[]): CaseEvent[][] {
  const rounds: CaseEvent[][] = [];
  let seenCollecting = false;
  for (const e of events) {
    const starts = e.kind === 'state' && e.toState === 'collecting';
    if (starts && seenCollecting) rounds.push([]);
    if (starts) seenCollecting = true;
    if (!rounds.length) rounds.push([]);
    rounds[rounds.length - 1].push(e);
  }
  return rounds;
}

/**
 * The outage resend that settled the case's message, if one did: the latest row of an approved run (never a hand closure)
 * that the engine sent, closed as sent or as already held at the receiver. The case's own plan may have proposed no write;
 * this is what Shutter did afterwards, through the outage card.
 */
export function outageResend(c: { resends?: CaseResend[] | null }): CaseResend | undefined {
  return (c.resends ?? [])
    .filter((r) => !r.runId.startsWith('H') && (r.closure === 'sent' || r.closure === 'already_delivered'))
    .at(-1);
}

/** The run's approval id, as the ledger names the run ("R8-3"). */
export const resendApproval = (r: CaseResend) => r.runId;
