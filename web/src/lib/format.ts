/**
 * Times are ISO 8601 UTC from the server. They are shown in the feed's time zone, the site profile's feed.time_zone
 * (Europe/London unless a site says otherwise), so a transfer the PAS sent "at 09:20" reads 09:20 BST on screen, as
 * the hospital's staff know it; UTC and the browser's own time are in the tooltips. UK English.
 */
const parts = {
  day: 'numeric',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
} as const;

const accepts = (name: string) => {
  try {
    new Intl.DateTimeFormat('en-GB', { timeZone: name });
    return true;
  } catch {
    return false;
  }
};

/**
 * The Intl zone for a profile's answer: an IANA zone, or a fixed offset such as +01:00 or -03:30, which current engines
 * take as it is. An engine that doesn't gets the Etc/GMT name for a whole hour (whose sign is the other way round, and
 * which stops at GMT+12 on the west side); anything else reads as UTC.
 */
function intlZone(zone: string): string {
  if (accepts(zone)) return zone;
  const fixed = /^([+-])(\d{2}):00$/.exec(zone);
  if (fixed) {
    const hours = Number(fixed[2]);
    const name = hours === 0 ? 'UTC' : `Etc/GMT${fixed[1] === '+' ? '-' : '+'}${hours}`;
    if (accepts(name)) return name;
  }
  return 'UTC';
}

let zone = 'Europe/London';
let shown = 'Europe/London';
let dateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZone: zone });
let timeOnly = new Intl.DateTimeFormat('en-GB', {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  timeZone: zone,
});
let zoneName = new Intl.DateTimeFormat('en-GB', { timeZone: zone, timeZoneName: 'short' });
const utcDateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZone: 'UTC' });
const localDateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZoneName: 'short' });

/** The zone the app shows times in: the feed's, from the site profile. */
export function setDisplayZone(z: string | undefined) {
  const next = intlZone(z || 'Europe/London');
  shown = next === 'UTC' ? 'UTC' : z || 'Europe/London';
  if (next === zone) return;
  zone = next;
  dateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZone: zone });
  timeOnly = new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZone: zone,
  });
  zoneName = new Intl.DateTimeFormat('en-GB', { timeZone: zone, timeZoneName: 'short' });
}

/** The zone as the site profile names it (Europe/London, UTC, +01:00). */
export const displayZone = () => shown;

export function parseTime(iso: string | undefined | null): Date | undefined {
  if (!iso) return undefined;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? undefined : d;
}

export function formatDateTime(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? dateTime.format(d) : '';
}

/** The zone's short name at that moment: GMT or BST for Europe/London, UTC, or the offset. */
export function zoneLabel(iso: string | undefined | null): string {
  const d = parseTime(iso);
  if (!d) return '';
  return zoneName.formatToParts(d).find((p) => p.type === 'timeZoneName')?.value ?? zone;
}

/** "15 Oct, 09:20:00 BST": a time in the feed's zone, named; "15 Oct, 09:20:00" with `named` false. */
export function formatZoned(iso: string | undefined | null, named = true): string {
  const d = parseTime(iso);
  if (!d) return '';
  return named ? `${dateTime.format(d)} ${zoneLabel(iso)}` : dateTime.format(d);
}

/** "09:20:00 BST": the time alone in the feed's zone, named (or not, with `named` false), for a moment of today. */
export function formatZonedTime(iso: string | undefined | null, named = true): string {
  const d = parseTime(iso);
  if (!d) return '';
  return named ? `${timeOnly.format(d)} ${zoneLabel(iso)}` : timeOnly.format(d);
}

/** "2 Nov": the day of a moment in the feed's zone, with its year when that is not this year ("2 Nov 2025"). */
export function formatDay(iso: string | undefined | null, now: number = Date.now()): string {
  const d = parseTime(iso);
  if (!d) return '';
  const year = (t: Date) => new Intl.DateTimeFormat('en-GB', { timeZone: zone, year: 'numeric' }).format(t);
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    day: 'numeric',
    month: 'short',
    ...(year(d) === year(new Date(now)) ? {} : { year: 'numeric' }),
  }).format(d);
}

/** "08:20:00Z": the same moment's UTC time, short, to sit beside the local one in Technical. */
export function formatUtcTime(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? `${d.toISOString().slice(11, 19)}Z` : '';
}

/** Whether a moment falls on today's date in the feed's zone. */
export function isToday(iso: string | undefined | null, now: number = Date.now()): boolean {
  const d = parseTime(iso);
  if (!d) return false;
  const day = new Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return day.format(d) === day.format(new Date(now));
}

/** The same moment in UTC, as the API carries it. */
export function formatUtc(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? `${utcDateTime.format(d)} UTC` : '';
}

/** The same moment in the browser's own time zone, with the zone named. */
export function formatLocal(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? localDateTime.format(d) : '';
}

export function formatTime(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? timeOnly.format(d) : '';
}

/** "12 s ago", "3 min ago", "2 h ago", "4 days ago". */
export function formatAge(iso: string | undefined | null, now: number = Date.now()): string {
  const d = parseTime(iso);
  if (!d) return '';
  const s = Math.max(0, Math.round((now - d.getTime()) / 1000));
  if (s < 60) return `${s} s ago`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 48) return `${h} h ago`;
  return `${Math.round(h / 24)} days ago`;
}

export function formatDuration(ms: number | undefined | null): string {
  if (ms === undefined || ms === null || Number.isNaN(Number(ms))) return '';
  const n = Number(ms);
  if (n < 1000) return `${n} ms`;
  if (n < 60_000) return `${(n / 1000).toFixed(1)} s`;
  return `${Math.floor(n / 60_000)} min ${Math.round((n % 60_000) / 1000)} s`;
}

const integer = new Intl.NumberFormat('en-GB');
export function formatInt(n: number | string | undefined | null): string {
  if (n === undefined || n === null || n === '') return '';
  return integer.format(Number(n));
}

/**
 * "1 chain", "6 chains", "1,896,147 tokens": a count with its noun in the right number, never "chain(s)". `many` is
 * the plural when adding an s is wrong ("1 pass", "3 passes"; "1 entry", "2 entries").
 */
export function plural(n: number, word: string, many?: string): string {
  return `${integer.format(n)} ${n === 1 ? word : (many ?? (/(s|x|ch|sh)$/.test(word) ? `${word}es` : `${word}s`))}`;
}

/** US dollars, as the providers price tokens: four decimals below a cent, two above. */
export function formatUsd(n: number | string | undefined | null): string {
  if (n === undefined || n === null || n === '') return '';
  const v = Number(n);
  if (Number.isNaN(v)) return '';
  return v > 0 && v < 0.01 ? `$${v.toFixed(4)}` : `$${v.toFixed(2)}`;
}

/**
 * "sha256:9f86d081884c…" for a digest: enough to compare by eye; the full value goes in a tooltip or copy. Anything
 * else (an operation key, whose times hold colons too) is cut at `length` characters.
 */
export function shortDigest(digest: string | undefined | null, length = 12): string {
  if (!digest) return '';
  const m = /^([a-z0-9-]+):([0-9a-f]+)$/i.exec(digest);
  if (m) return `${m[1]}:${m[2].length > length ? `${m[2].slice(0, length)}…` : m[2]}`;
  return digest.length > length ? `${digest.slice(0, length)}…` : digest;
}

/** Codes whose words alone would read differently from the status badges. */
const CODE_WORDS: Record<string, string> = {
  awaiting_approval: 'Waiting for approval',
};

/** "release_failed" → "Release failed"; "awaiting_approval" reads "Waiting for approval", as the badges say. */
export function humanize(code: string | undefined | null): string {
  if (!code) return '';
  if (CODE_WORDS[code]) return CODE_WORDS[code];
  const text = code.replace(/_/g, ' ').toLowerCase();
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * Identifiers the server keeps from before the downstream system had its name (snapshot item kinds, evidence
 * sources, readiness keys), and readiness keys whose words alone would say too little, as the screens name them.
 */
const KEY_LABELS: Record<string, string> = {
  ward_state: 'Downstream state',
  ward_state_http_status: 'Downstream state HTTP status',
  ward_api: 'Downstream API',
  ward_classes: 'Downstream classes',
  wards_webapp: 'Downstream webapp',
  purge_task: 'Message purge task',
  message_days: 'Messages kept (days)',
  escalation_days: 'Escalation texts kept (days)',
  shutter_production: "Shutter's production",
  board_members: 'Enabled agents',
  mode: 'Investigation mode for new cases',
};

/** An identifier in words: its label when it has one, otherwise humanized. */
export function keyLabel(code: string | undefined | null): string {
  return (code && KEY_LABELS[code]) || humanize(code);
}
