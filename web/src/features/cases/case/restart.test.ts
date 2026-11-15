import { describe, expect, it } from 'vitest';
import type { CaseEvent } from '@/api/types';
import { formatZoned } from '@/lib/format';
import { isStartNote, restartOf, restartWords } from './restart';

const START = '2026-11-15T10:00:00Z';

/** The start sweep's note, as Shutter.Store.Case.MarkOpenAtStart writes it. */
function startNote(seq: number, at = START, state = 'investigating', minutes = 15): CaseEvent {
  return {
    seq,
    at,
    kind: 'error',
    fromState: '',
    toState: '',
    text: `The production started at ${at} while this case was ${state}. Work in flight resumes when the production was stopped cleanly; if the case does not move on within ${minutes} minutes, an approver can abandon it (POST /cases/C-000002/abandon, or "Abandon the case" on the case page)`,
    actor: 'system',
    ref: `start:${at}`,
  };
}

const event = (
  seq: number,
  kind: CaseEvent['kind'],
  at: string,
  extra: Partial<CaseEvent> = {},
): CaseEvent => ({
  seq,
  at,
  kind,
  fromState: '',
  toState: '',
  text: '',
  actor: 'system',
  ref: '',
  ...extra,
});

const before = [
  event(1, 'state', '2026-11-15T09:50:00Z', { toState: 'collecting' }),
  event(2, 'state', '2026-11-15T09:51:00Z', { fromState: 'collecting', toState: 'investigating' }),
];

describe('isStartNote', () => {
  it("is the start sweep's note and nothing else of the error kind", () => {
    expect(isStartNote(startNote(3))).toBe(true);
    expect(
      isStartNote(event(3, 'error', START, { ref: 'gate', text: 'The gate could not read the receiver' })),
    ).toBe(false);
    // A person's words are never the sweep's, whatever they say
    expect(isStartNote({ ...startNote(3), actor: 'approver' })).toBe(false);
    expect(isStartNote({ ...startNote(3), kind: 'note' })).toBe(false);
  });
});

describe('restartOf', () => {
  it('reads a restart the case has not moved on from, with its abandon time', () => {
    const r = restartOf({ state: 'investigating' }, [...before, startNote(3)], 15);
    expect(r).toEqual({
      at: START,
      state: 'investigating',
      waiting: false,
      minutes: 15,
      abandonFrom: '2026-11-15T10:15:00.000Z',
    });
  });

  it('is gone once anything else is recorded after the note', () => {
    const moved = event(4, 'state', '2026-11-15T10:01:00Z', {
      fromState: 'investigating',
      toState: 'proposed',
    });
    expect(restartOf({ state: 'proposed' }, [...before, startNote(3), moved], 15)).toBeNull();
    const noted = event(4, 'note', '2026-11-15T10:02:00Z', { actor: 'operator', text: 'Looking into it' });
    expect(restartOf({ state: 'investigating' }, [...before, startNote(3), noted], 15)).toBeNull();
  });

  it('takes the newest of two restarts with nothing in between, whatever order the events come in', () => {
    const later = startNote(4, '2026-11-15T11:00:00Z');
    expect(restartOf({ state: 'investigating' }, [later, startNote(3), ...before], 15)?.at).toBe(
      '2026-11-15T11:00:00Z',
    );
  });

  it('says nothing for a closed case, a case never restarted, or no events yet', () => {
    expect(restartOf({ state: 'failed' }, [...before, startNote(3)], 15)).toBeNull();
    expect(restartOf({ state: 'investigating' }, before, 15)).toBeNull();
    expect(restartOf({ state: 'investigating' }, [], 15)).toBeNull();
    expect(restartOf({ state: 'investigating' }, undefined, 15)).toBeNull();
  });

  it("keeps the server's minutes, but never fewer than the page waits before offering to abandon", () => {
    expect(
      restartOf({ state: 'investigating' }, [startNote(3, START, 'investigating', 30)], 15),
    ).toMatchObject({
      minutes: 30,
      abandonFrom: '2026-11-15T10:30:00.000Z',
    });
    expect(
      restartOf({ state: 'investigating' }, [startNote(3, START, 'investigating', 11)], 15)?.minutes,
    ).toBe(15);
    // A note whose words carry no minutes falls back to the page's
    const plain = { ...startNote(3), text: 'The production started' };
    expect(restartOf({ state: 'investigating' }, [plain], 15)?.minutes).toBe(15);
  });

  it('tells a case waiting for a person from one waiting for work in flight', () => {
    expect(restartOf({ state: 'awaiting_approval' }, [startNote(3)], 15)?.waiting).toBe(true);
    expect(restartOf({ state: 'grouped' }, [startNote(3)], 15)?.waiting).toBe(true);
    expect(restartOf({ state: 'executing' }, [startNote(3)], 15)?.waiting).toBe(false);
  });
});

describe('restartWords', () => {
  const at = Date.parse(START);
  const working = restartOf({ state: 'investigating' }, [startNote(3)], 15)!;

  it('says when it started and asks a working case to be waited for, until the time it can be abandoned', () => {
    const { title, body } = restartWords(working, at + 5 * 60_000, true);
    expect(title).toBe('The production restarted during this case');
    expect(body).toBe(
      `Shutter's production started at ${formatZoned(START)} while this case was investigating, and nothing has moved since. Work in flight resumes after a clean stop, so wait: if nothing moves by ${formatZoned('2026-11-15T10:15:00.000Z')}, an approver can abandon the case.`,
    );
  });

  it('points an approver to Still working once the quiet minutes are over, and tells anyone else an approver can', () => {
    const late = at + 20 * 60_000;
    expect(restartWords(working, late, true).body).toMatch(
      /nothing has moved for 15 minutes\. If the case's workflow has stopped for good, abandon it under Still working on the Summary tab: nothing more is sent, and it can be reinvestigated\.$/,
    );
    expect(restartWords(working, late, false).body).toMatch(
      /nothing has moved for 15 minutes\. If the case's workflow has stopped for good, an approver can abandon it: nothing more is sent, and it can be reinvestigated\.$/,
    );
  });

  it('asks for the decision as before on a case waiting for one, at any time', () => {
    const waiting = restartOf({ state: 'awaiting_approval' }, [startNote(3)], 15)!;
    for (const now of [at, at + 60 * 60_000]) {
      const { body } = restartWords(waiting, now, true);
      expect(body).toMatch(/while this case was waiting for approval, and nothing has moved since\./);
      expect(body).toMatch(/A clean stop keeps the approval task: decide on the plan as before\.$/);
      expect(body).not.toMatch(/abandon/);
    }
    const grouped = restartOf({ state: 'grouped' }, [startNote(3)], 15)!;
    expect(restartWords(grouped, at, true).body).toMatch(
      /while this case was grouped under an incident, .* its decision moves this case, as before\.$/,
    );
  });
});
