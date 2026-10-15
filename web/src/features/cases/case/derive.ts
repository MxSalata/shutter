import type { CaseEvent, GateCheck, GateDecision, SnapshotItem } from '@/api/types';
import { asArray, asObject } from '@/lib/json';
import { formatTime, humanize } from '@/lib/format';

/** Pure helpers behind the case page's panels: what they derive from the API's data, kept apart to be tested. */

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** One line that says what an observation found, so the list reads without opening each item. */
export function describeItem(item: SnapshotItem): string {
  const d = asObject(item.data) ?? {};
  switch (item.kind) {
    case 'operation':
      return `${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''} at ${formatTime(str(d.event_time))} for ${str(d.encounter_id)}`;
    case 'error':
      return `${humanize(str(d.kind))}: ${str(d.text)}`;
    case 'message': {
      const notes = asArray(d.notes);
      return `${str(d.message_type)} ${str(d.message_control_id)} from ${str(d.sending_application)}, location ${str(d.assigned_location).split('^')[0]}${notes.length ? `, ${notes.length} free-text note${notes.length > 1 ? 's' : ''}` : ''}`;
    }
    case 'validation':
      return d.parsed
        ? `Parses as ${str(d.doc_type)}`
        : `Does not parse${d.error ? `: ${str(d.error)}` : ''}`;
    case 'ward_state': {
      const status = Number(d.http_status);
      const b = asObject(d.body) ?? {};
      if (status === 200)
        return `${humanize(str(b.state))}${b.ward ? ` in ${str(b.ward)}` : ''}, version ${str(b.version)}${b.epoch !== undefined ? `, epoch ${str(b.epoch)}` : ''}; ${asArray(b.history).length} operations in its history`;
      if (status === 404) return 'The ward has no such encounter';
      return `Could not be read (HTTP ${status || 'none'}): unknown`;
    }
    case 'receipt': {
      const status = Number(d.http_status);
      const b = asObject(d.body) ?? {};
      if (status === 200)
        return `Committed: version ${str(b.version_before)} to ${str(b.version_after)}, at ${formatTime(str(b.applied_at))}`;
      if (status === 404) return 'No receipt: the ward did not commit this operation';
      return `The lookup did not answer (HTTP ${status || 'none'}): committed or not is unknown`;
    }
    case 'later_event':
      return `${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''} at ${formatTime(str(d.event_time))} (${humanize(str(d.outcome))})`;
    case 'route':
      return `${str(d.feed)}`;
    default:
      return str(d.text) || item.source;
  }
}

/** The workflow's phases and the case states that belong to each (Interlock.Process.CaseWorkflow). */
export const PHASES = [
  { key: 'evidence', label: 'Evidence', states: ['detected', 'collecting'] },
  { key: 'investigation', label: 'Investigation', states: ['investigating'] },
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
