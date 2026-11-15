import { CLOSED_STATES, type CaseDetail, type CaseEvent } from '@/api/types';
import { formatZoned, humanize } from '@/lib/format';

/**
 * The production's start, as the case records it (CONTRACTS 12, the start sweep): at every start of Shutter's
 * production each case not in a closed state gets one `error`-kind event by `system`, ref `start:<time>`, saying the
 * production started while the case was in its state, and the minutes after which an approver may abandon it if it
 * does not move on. It closes nothing: a clean stop and start resumes the work in flight.
 */
export function isStartNote(e: Pick<CaseEvent, 'kind' | 'actor' | 'ref'>): boolean {
  return e.kind === 'error' && e.actor === 'system' && (e.ref ?? '').startsWith('start:');
}

/**
 * States that wait for a person rather than for work in flight: the open approval task is a deferred message, which
 * the server counts as in flight whatever its age (409 busy), so abandoning is never offered there.
 */
export const WAITING_FOR_A_PERSON = ['awaiting_approval', 'grouped'];

/** A restart the case has not moved on from. */
export interface Restart {
  /** When the production started: the note's time. */
  at: string;
  /** The case's state then, and still now: nothing has moved since. */
  state: string;
  /** Whether the case waits for a person (an approval, its incident's decision) rather than for work in flight. */
  waiting: boolean;
  /** The quiet minutes after which an approver may abandon a working case: the note's, never fewer than the page's. */
  minutes: number;
  /** When those minutes run out, as ISO UTC. */
  abandonFrom: string;
}

/**
 * The newest restart a case has not moved on from: the case is open and its newest event is the production's start
 * note (a second restart with nothing in between is the newer note). Null once anything else is recorded after it, a
 * state change, a note or a decision, and for a closed case, which the start sweep never notes. The minutes are the
 * note's ("within N minutes", the server's `abandonAfterMinutes`), and never fewer than `pageMinutes`, the quiet the
 * Still working panel waits for: a time the page says is a time the page keeps.
 */
export function restartOf(
  c: Pick<CaseDetail, 'state'>,
  events: CaseEvent[] | null | undefined,
  pageMinutes: number,
): Restart | null {
  if (CLOSED_STATES.includes(c.state)) return null;
  const newest = (events ?? []).reduce<CaseEvent | undefined>(
    (a, e) => (!a || e.seq > a.seq ? e : a),
    undefined,
  );
  if (!newest || !isStartNote(newest)) return null;
  const at = newest.at;
  const started = Date.parse(at);
  if (Number.isNaN(started)) return null;
  const said = Number(/within (\d+) minutes/.exec(newest.text ?? '')?.[1] ?? 0);
  const minutes = Math.max(said, pageMinutes);
  return {
    at,
    state: c.state,
    waiting: WAITING_FOR_A_PERSON.includes(c.state),
    minutes,
    abandonFrom: new Date(started + minutes * 60_000).toISOString(),
  };
}

/**
 * What a restart means for the person reading the case, in two parts: what happened, and what to do now. A case
 * waiting for a person is decided as before, since a clean stop keeps its approval task. A working case is waited
 * for until the quiet minutes run out; after that an approver can abandon it (the Still working panel on the Summary
 * tab, shown to approvers only), and anyone else is told an approver can.
 */
export function restartWords(r: Restart, now: number, canAbandon: boolean): { title: string; body: string } {
  const was =
    r.state === 'awaiting_approval'
      ? 'waiting for approval'
      : r.state === 'grouped'
        ? 'grouped under an incident'
        : humanize(r.state).toLowerCase();
  const happened = `Shutter's production started at ${formatZoned(r.at)} while this case was ${was}, and nothing has moved since.`;
  const title = 'The production restarted during this case';
  if (r.waiting)
    return {
      title,
      body: `${happened} ${
        r.state === 'grouped'
          ? "A clean stop keeps the incident's approval task: its decision moves this case, as before."
          : 'A clean stop keeps the approval task: decide on the plan as before.'
      }`,
    };
  if (now < Date.parse(r.abandonFrom))
    return {
      title,
      body: `${happened} Work in flight resumes after a clean stop, so wait: if nothing moves by ${formatZoned(r.abandonFrom)}, an approver can abandon the case.`,
    };
  return {
    title,
    body: `${happened} Work in flight resumes after a clean stop, but nothing has moved for ${r.minutes} minutes. ${
      canAbandon
        ? "If the case's workflow has stopped for good, abandon it under Still working on the Summary tab: nothing more is sent, and it can be reinvestigated."
        : "If the case's workflow has stopped for good, an approver can abandon it: nothing more is sent, and it can be reinvestigated."
    }`,
  };
}
