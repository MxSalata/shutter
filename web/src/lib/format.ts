/**
 * Times are ISO 8601 UTC from the server and are shown in UTC, as the HL7 messages and the scenarios carry them (a
 * transfer "at 09:20" reads 09:20 on screen too); the browser's own time is in the tooltips. UK English.
 */
const parts = {
  day: 'numeric',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
} as const;
const dateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZone: 'UTC' });
const timeOnly = new Intl.DateTimeFormat('en-GB', {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  timeZone: 'UTC',
});
const localDateTime = new Intl.DateTimeFormat('en-GB', { ...parts, timeZoneName: 'short' });

export function parseTime(iso: string | undefined | null): Date | undefined {
  if (!iso) return undefined;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? undefined : d;
}

export function formatDateTime(iso: string | undefined | null): string {
  const d = parseTime(iso);
  return d ? dateTime.format(d) : '';
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

/** "awaiting_approval" → "Awaiting approval". */
export function humanize(code: string | undefined | null): string {
  if (!code) return '';
  const text = code.replace(/_/g, ' ').toLowerCase();
  return text.charAt(0).toUpperCase() + text.slice(1);
}
