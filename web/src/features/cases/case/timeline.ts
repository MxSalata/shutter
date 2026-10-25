import { asArray, asObject } from '@/lib/json';

/**
 * The encounter's timeline as the evidence recorded it: every operation the feed sent for the encounter
 * (snapshot.summary.timeline) and the receiver's committed history (ward_state.history), one row per operation in
 * event order. Kept apart from the table to be tested.
 */
export interface TimelineRow {
  operationKey: string;
  event: string;
  ward: string;
  eventTime: string;
  /** The sending system, the operation key's first part (PAS, BEDMGR). */
  system: string;
  /** Where the row comes from: the feed's own record, or only the receiver's history. */
  source: 'feed' | 'receiver';
  /** The order the feed sent the operations in, 1 first; null for a row only the receiver's history holds. */
  received: number | null;
  sentAt: string;
  outcome: string;
  httpStatus: number | null;
  /** The receiver's version once the operation applied; empty when it did not. */
  versionAfter: string;
  thisCase: boolean;
  later: boolean;
  /** Another operation for the encounter has the same event time (S8): the order of the two can't be told. */
  sameTime: boolean;
  /** The event time falls in the hour around a clock change in the feed's zone (S21): its local time is doubtful. */
  clockChange: boolean;
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** The zone's offset from UTC at that moment, in minutes; undefined when the zone is not one Intl knows. */
export function zoneOffset(ms: number, zone: string): number | undefined {
  try {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    }).formatToParts(new Date(ms));
    const n = (type: string) => Number(parts.find((p) => p.type === type)?.value);
    const wall = Date.UTC(n('year'), n('month') - 1, n('day'), n('hour'), n('minute'), n('second'));
    return Math.round((wall - Math.floor(ms / 1000) * 1000) / 60_000);
  } catch {
    return undefined;
  }
}

/**
 * True when the zone's offset an hour before the moment differs from the one an hour after: the moment's local time
 * is within the hour that is repeated when the clocks go back, or next to the hour skipped when they go forward.
 */
export function nearClockChange(iso: string, zone: string): boolean {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return false;
  const before = zoneOffset(t - 3_600_000, zone);
  const after = zoneOffset(t + 3_600_000, zone);
  return before !== undefined && after !== undefined && before !== after;
}

export function encounterTimeline(summary: unknown, zone: string): TimelineRow[] {
  const s = asObject(summary) ?? {};
  const message = asObject(s.message) ?? {};
  const feedZone = str(message.feed_time_zone) || zone;
  const fed = asArray(s.timeline)
    .map((x) => asObject(x))
    .filter((x): x is Record<string, unknown> => !!x);
  // The order the feed sent them in: by the time each was sent, the timeline's own order breaking ties
  const order = fed
    .map((x, i) => ({ i, at: str(x.sent_at) }))
    .sort((a, b) => a.at.localeCompare(b.at) || a.i - b.i);
  const received = new Map(order.map((o, n) => [o.i, n + 1]));
  const rows: TimelineRow[] = fed.map((x, i) => ({
    operationKey: str(x.operation_key),
    event: str(x.event),
    ward: str(x.ward),
    eventTime: str(x.event_time),
    system: str(x.operation_key).split('^')[0] ?? '',
    source: 'feed',
    received: received.get(i) ?? null,
    sentAt: str(x.sent_at),
    outcome: str(x.outcome),
    httpStatus: x.http_status === undefined || x.http_status === '' ? null : Number(x.http_status),
    versionAfter: str(x.version_after),
    thisCase: x.this_case === true,
    later: x.later === true,
    sameTime: false,
    clockChange: false,
  }));
  // The receiver's history gives the version an operation left, and any operation the feed has no record of
  const ward = asObject(s.ward_state) ?? {};
  for (const h of asArray(ward.history)) {
    const e = asObject(h);
    if (!e) continue;
    const key = str(e.operation_key);
    const row = rows.find((r) => key && r.operationKey === key && !r.versionAfter);
    if (row) {
      row.versionAfter = str(e.version_after);
      continue;
    }
    if (key && rows.some((r) => r.operationKey === key)) continue;
    rows.push({
      operationKey: key,
      event: str(e.event),
      ward: str(e.ward),
      eventTime: str(e.event_time),
      system: key.split('^')[0] ?? '',
      source: 'receiver',
      received: null,
      sentAt: str(e.applied_at),
      outcome: 'applied',
      httpStatus: null,
      versionAfter: str(e.version_after),
      thisCase: false,
      later: false,
      sameTime: false,
      clockChange: false,
    });
  }
  const time = (r: TimelineRow) => Date.parse(r.eventTime);
  for (const r of rows) {
    r.sameTime = !!r.eventTime && rows.some((o) => o !== r && o.eventTime && time(o) === time(r));
    r.clockChange = !!r.eventTime && nearClockChange(r.eventTime, feedZone);
  }
  return rows.sort(
    (a, b) =>
      (time(a) || 0) - (time(b) || 0) ||
      (a.received ?? Number.MAX_SAFE_INTEGER) - (b.received ?? Number.MAX_SAFE_INTEGER),
  );
}
