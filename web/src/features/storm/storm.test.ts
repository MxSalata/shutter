import { describe, expect, it } from 'vitest';
import { livePollInterval } from '@/api/hooks';
import type { LiveStorm, Settings } from '@/api/types';
import { ApiError } from '@/lib/errors';
import { formatTime, zoneLabel } from '@/lib/format';
import { isStormPlaying, isStormShown, LIVE_POLL_MS, STORM_POLL_MS } from '@/lib/storm';
import {
  cooldownTime,
  patientWards,
  refusalWords,
  stormPatients,
  stormRefusal,
  stormView,
  wardLabel,
} from './view';

const NOW = Date.parse('2026-11-02T10:00:00Z');
const at = (seconds: number) => new Date(NOW + seconds * 1000).toISOString();

const storm = (s: Partial<LiveStorm>): LiveStorm => ({
  stormId: 'ST-000003',
  state: 'sending',
  startedAt: at(-60),
  endsAt: at(540),
  movements: 8,
  sent: 0,
  ...s,
});

const refused = (status: number, body: unknown) =>
  new ApiError({ status, method: 'POST', path: '/live/storm', body });

describe('whether a storm plays and shows', () => {
  it('plays from the press until it is done or failed', () => {
    for (const state of ['requested', 'sending', 'waiting_receiver', 'releasing'])
      expect(isStormPlaying(storm({ state }), NOW)).toBe(true);
    for (const state of ['done', 'failed']) expect(isStormPlaying(storm({ state }), NOW)).toBe(false);
    expect(isStormPlaying(null, NOW)).toBe(false);
  });

  it('does not count a storm the player left playing a minute past its span', () => {
    expect(isStormPlaying(storm({ endsAt: at(-30) }), NOW)).toBe(true);
    expect(isStormPlaying(storm({ endsAt: at(-90) }), NOW)).toBe(false);
    expect(isStormShown(storm({ endsAt: at(-90) }), NOW)).toBe(false);
  });

  it('shows a storm that ended for ten minutes after its end, a failed one from its start', () => {
    expect(isStormShown(storm({ state: 'done', endedAt: at(-9 * 60) }), NOW)).toBe(true);
    expect(isStormShown(storm({ state: 'done', endedAt: at(-11 * 60) }), NOW)).toBe(false);
    expect(isStormShown(storm({ state: 'failed', startedAt: at(-5 * 60) }), NOW)).toBe(true);
    expect(isStormShown(storm({ state: 'failed', startedAt: at(-15 * 60) }), NOW)).toBe(false);
  });
});

describe('how often the banner reads the settings', () => {
  const settings = (live: Settings['live']) => ({ live }) as Settings;

  it('every 3 s while a storm plays, every 30 s otherwise, and never without a live hospital', () => {
    expect(STORM_POLL_MS).toBe(3_000);
    expect(LIVE_POLL_MS).toBe(30_000);
    expect(livePollInterval(undefined, NOW)).toBe(false);
    expect(livePollInterval(settings({ enabled: false }), NOW)).toBe(false);
    expect(livePollInterval(settings({ enabled: true }), NOW)).toBe(30_000);
    expect(livePollInterval(settings({ enabled: true, storm: storm({ state: 'sending' }) }), NOW)).toBe(
      3_000,
    );
    expect(livePollInterval(settings({ enabled: true, storm: storm({ state: 'releasing' }) }), NOW)).toBe(
      3_000,
    );
    expect(livePollInterval(settings({ enabled: true, storm: storm({ state: 'done' }) }), NOW)).toBe(30_000);
    expect(livePollInterval(settings({ enabled: true, storm: storm({ state: 'failed' }) }), NOW)).toBe(
      30_000,
    );
    // A storm left playing by a player that stopped: no reason to read every 3 s
    expect(livePollInterval(settings({ enabled: true, storm: storm({ endsAt: at(-120) }) }), NOW)).toBe(
      30_000,
    );
  });
});

describe('the five steps', () => {
  const statuses = (s: LiveStorm) => stormView(s).steps.map((x) => x.status);
  const words = (s: LiveStorm) => stormView(s).steps.map((x) => x.words);

  it('starts at the bed manager going down, with the movements sent so far', () => {
    const v = stormView(storm({ state: 'requested', sent: 0, patients: 4 }));
    expect(v.current).toBe(0);
    expect(v.line).toBe('Step 1 of 5: The bed manager is down');
    expect(v.steps[0].detail).toBe('0 of 8 movements sent');
    expect(v.status).toEqual({ tone: 'info', label: 'Playing' });
    expect(stormView(storm({ sent: 3 })).steps[0].detail).toBe('3 of 8 movements sent');
    expect(statuses(storm({ sent: 3 }))).toEqual(['current', 'pending', 'pending', 'pending', 'pending']);
    // Steps not reached yet say what will happen, with no figure the record does not hold
    expect(words(storm({ sent: 3 })).slice(1)).toEqual([
      'Deliveries fail; Shutter opens a case for each',
      'Grouped into one incident',
      'The bed manager is back; releasing in order',
      'Done',
    ]);
  });

  it('counts the failed deliveries and the cases once every movement went out', () => {
    const v = stormView(storm({ state: 'waiting_receiver', sent: 8, cases: 8 }));
    expect(v.current).toBe(1);
    expect(v.line).toBe('Step 2 of 5: 8 deliveries failed; Shutter opened 8 cases');
    expect(v.steps[0]).toMatchObject({ status: 'done', detail: undefined });
    expect(stormView(storm({ state: 'waiting_receiver', sent: 1, cases: 1 })).steps[1].words).toBe(
      '1 delivery failed; Shutter opened 1 case',
    );
  });

  it('names the incident once the cases joined one', () => {
    const v = stormView(
      storm({ state: 'waiting_receiver', sent: 8, cases: 8, incidentId: 'I-000016', incidentState: 'open' }),
    );
    expect(v.current).toBe(2);
    expect(v.line).toBe('Step 3 of 5: Grouped into incident I-000016');
    expect(v.steps[2]).toMatchObject({ status: 'current', incidentId: 'I-000016' });
  });

  it('releases in order once the bed manager is back, with the cases resolved so far', () => {
    const v = stormView(
      storm({
        state: 'releasing',
        sent: 8,
        cases: 8,
        resolved: 5,
        incidentId: 'I-000016',
        receiverUpAt: at(-5),
      }),
    );
    expect(v.current).toBe(3);
    expect(v.line).toBe('Step 4 of 5: The bed manager is back; releasing in order');
    expect(v.steps[3].detail).toBe('5 of 8 resolved');
    expect(statuses(storm({ state: 'releasing', incidentId: 'I-000016' }))).toEqual([
      'done',
      'done',
      'done',
      'current',
      'pending',
    ]);
  });

  it('says when no incident was recorded for a storm that went past that step', () => {
    const v = stormView(storm({ state: 'releasing', sent: 8, cases: 8, incidentId: null }));
    expect(v.steps[2]).toMatchObject({ status: 'skipped', words: 'No incident recorded' });
  });

  it('ends done, with the counts', () => {
    const v = stormView(
      storm({ state: 'done', sent: 8, cases: 8, resolved: 8, incidentId: 'I-000016', endedAt: at(-10) }),
    );
    expect(v.current).toBe(4);
    expect(v.line).toBe('Step 5 of 5: Done: 8 cases, 8 resolved, nothing written twice');
    expect(v.status).toEqual({ tone: 'positive', label: 'Done' });
    expect(statuses(storm({ state: 'done', incidentId: 'I-000016' }))).toEqual([
      'done',
      'done',
      'done',
      'done',
      'finished',
    ]);
  });

  it('ends stopped with the error, and marks only the steps the record shows it reached', () => {
    const v = stormView(
      storm({ state: 'failed', sent: 3, cases: 2, error: 'The receiver could not be stopped' }),
    );
    expect(v.line).toBe('Step 5 of 5: Stopped: The receiver could not be stopped');
    expect(v.status).toEqual({ tone: 'blocking', label: 'Stopped' });
    expect(v.steps.map((s) => s.status)).toEqual(['done', 'done', 'skipped', 'skipped', 'stopped']);
    expect(stormView(storm({ state: 'failed' })).line).toBe('Step 5 of 5: Stopped: the storm did not finish');
  });
});

describe('the patients', () => {
  it('reads as wards, never names, and only once the player planned them', () => {
    expect(wardLabel('WARD-A')).toBe('Ward A');
    expect(wardLabel('ICU')).toBe('ICU');
    expect(
      patientWards({ mrn: 'MRN500101', encounterId: 'ENC-500101', ward: 'WARD-A', toWard: 'WARD-C' }),
    ).toBe('Ward A to Ward C');
    expect(patientWards({ mrn: 'MRN500101', encounterId: 'ENC-500101', ward: 'WARD-A', toWard: '' })).toBe(
      'Ward A',
    );
    expect(stormPatients(storm({ patients: 4 }))).toEqual([]);
  });
});

describe('the refusals', () => {
  it('reads each refusal from its status and code, and nothing else as one', () => {
    expect(stormRefusal(refused(409, { error: 'live_off', detail: 'off' }))).toEqual({ code: 'live_off' });
    expect(
      stormRefusal(refused(409, { error: 'storm_in_progress', stormId: 'ST-000002', state: 'sending' })),
    ).toEqual({ code: 'storm_in_progress', stormId: 'ST-000002', state: 'sending' });
    expect(stormRefusal(refused(409, { error: 'cooldown', until: at(300), retryAfterSeconds: 300 }))).toEqual(
      {
        code: 'cooldown',
        until: at(300),
        retryAfterSeconds: 300,
      },
    );
    expect(stormRefusal(refused(503, { error: 'no_service' }))).toEqual({ code: 'no_service' });
    expect(stormRefusal(refused(500, { error: 'internal' }))).toBeNull();
    expect(stormRefusal(refused(403, { error: 'forbidden' }))).toBeNull();
    expect(stormRefusal(new Error('network'))).toBeNull();
  });

  it('says each in one calm sentence, the cooldown with its time as the app shows times', () => {
    const until = at(252);
    const time = `${formatTime(until).slice(0, 5)} ${zoneLabel(until)}`;
    expect(cooldownTime(until)).toBe(time);
    expect(refusalWords({ code: 'cooldown', until })).toBe(`The next storm can start at ${time}.`);
    expect(refusalWords({ code: 'cooldown', retryAfterSeconds: 252 }, NOW)).toBe(
      `The next storm can start at ${time}.`,
    );
    expect(refusalWords({ code: 'cooldown' })).toBe('The next storm can start in a few minutes.');
    expect(refusalWords({ code: 'live_off' })).toBe('The live hospital is off.');
    expect(refusalWords({ code: 'storm_in_progress' })).toBe('A storm is already playing; watch it here.');
    expect(refusalWords({ code: 'no_service' })).toBe("The demo hospital isn't installed here.");
  });
});
