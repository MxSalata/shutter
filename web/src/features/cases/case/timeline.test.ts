import { describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { encounterTimeline, nearClockChange } from './timeline';

const s8 = fixtures.cases['C-000008'].snapshot.summary;

describe('encounterTimeline', () => {
  it("puts S8's two transfers at the same time side by side, with the version the bed manager's left", () => {
    const rows = encounterTimeline(s8, 'Europe/London');
    expect(rows.map((r) => [r.system, r.event, r.ward, r.received, r.versionAfter])).toEqual([
      ['PAS', 'admit', 'WARD-A', 1, '1'],
      ['PAS', 'transfer', 'WARD-B', 2, ''],
      ['BEDMGR', 'transfer', 'WARD-C', 3, '2'],
    ]);
    expect(rows.map((r) => r.sameTime)).toEqual([false, true, true]);
    expect(rows.find((r) => r.thisCase)?.outcome).toBe('unavailable');
    expect(rows.some((r) => r.clockChange)).toBe(false);
  });

  it('reads a summary sent as JSON text, and adds what only the receiver holds', () => {
    const summary = {
      timeline: [
        {
          event: 'transfer',
          ward: 'WARD-B',
          event_time: '2026-10-15T08:20:00Z',
          operation_key: 'PAS^HOSP^M^E^transfer^2026-10-15T08:20:00Z',
          sent_at: '2026-10-20 17:26:48.399',
          this_case: true,
          outcome: 'unavailable',
          http_status: 503,
        },
      ],
      ward_state: {
        history: [
          {
            version_after: 1,
            event: 'admit',
            ward: 'WARD-A',
            event_time: '2026-10-15T08:00:00Z',
            applied_at: '2026-10-20T17:26:46Z',
            operation_key: 'ADMIN^HOSP^M^E^admit^2026-10-15T08:00:00Z',
          },
        ],
      },
    };
    const rows = encounterTimeline(JSON.stringify(summary), 'Europe/London');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ system: 'ADMIN', source: 'receiver', received: null, versionAfter: '1' });
    expect(rows[1]).toMatchObject({ system: 'PAS', source: 'feed', received: 1, httpStatus: 503 });
  });

  it("flags S21's transfer at 01:30 on the night the clocks go back, in the feed's zone", () => {
    const summary = {
      message: { feed_time_zone: 'Europe/London' },
      timeline: [
        {
          event: 'admit',
          ward: 'WARD-A',
          event_time: '2026-10-24T23:20:00Z',
          sent_at: '1',
          outcome: 'applied',
        },
        {
          event: 'transfer',
          ward: 'WARD-B',
          event_time: '2026-10-25T00:30:00Z',
          sent_at: '2',
          this_case: true,
        },
      ],
    };
    const rows = encounterTimeline(summary, 'UTC');
    expect(rows.map((r) => r.clockChange)).toEqual([false, true]);
    expect(rows.some((r) => r.sameTime)).toBe(false);
  });

  it('is empty when the summary has no timeline', () => {
    expect(encounterTimeline(undefined, 'Europe/London')).toEqual([]);
  });
});

describe('nearClockChange', () => {
  it('is true only in the hour around a change, and never for a zone without one', () => {
    // Europe/London goes back at 01:00 UTC on 25 October 2026 and forward at 01:00 UTC on 29 March 2026
    expect(nearClockChange('2026-10-25T00:30:00Z', 'Europe/London')).toBe(true);
    expect(nearClockChange('2026-10-25T01:30:00Z', 'Europe/London')).toBe(true);
    expect(nearClockChange('2026-10-25T02:30:00Z', 'Europe/London')).toBe(false);
    expect(nearClockChange('2026-03-29T00:30:00Z', 'Europe/London')).toBe(true);
    expect(nearClockChange('2026-10-15T08:20:00Z', 'Europe/London')).toBe(false);
    expect(nearClockChange('2026-10-25T00:30:00Z', 'UTC')).toBe(false);
    expect(nearClockChange('2026-10-25T00:30:00Z', 'Not/AZone')).toBe(false);
  });
});
