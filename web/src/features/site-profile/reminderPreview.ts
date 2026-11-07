import type { SiteProfile } from '@/api/types';

/**
 * The reminder for cases left open, in the page: what each setting reads when not stored, and a preview of the digest
 * with made-up patients, in the words of Shutter.Util.CaseReminder.Compose. Nothing here sends anything.
 */
export type Reminders = NonNullable<SiteProfile['reminders']>;

export const REMINDER_DEFAULTS = {
  team_hours: 4,
  officer_hours: 8,
  window_start: '08:00',
  window_end: '18:00',
  days: ['mon', 'tue', 'wed', 'thu', 'fri'],
  patient_detail: 'identifiers',
} as const;

export const DAY_LABELS: Record<string, string> = {
  mon: 'Mon',
  tue: 'Tue',
  wed: 'Wed',
  thu: 'Thu',
  fri: 'Fri',
  sat: 'Sat',
  sun: 'Sun',
};

export const DETAIL_LABELS: Record<string, string> = {
  none: 'No patient detail: case numbers only',
  identifiers: 'Identifiers: hospital number and visit number',
  identifiers_initial: 'Identifiers and the first letter of the first name',
};

/** Made-up patients, with a threshold and an age each. */
const SAMPLE = [
  {
    caseId: 'C-000101',
    id: 'TEST-0001',
    visit: 'V-1001',
    initial: 'A',
    receiver: 'Bed board',
    kind: 'delivery failed',
    later: true,
    hours: 11,
  },
  {
    caseId: 'C-000102',
    id: 'TEST-0002',
    visit: 'V-1002',
    initial: 'B',
    receiver: 'Bed board',
    kind: 'delivery failed',
    later: false,
    hours: 5,
  },
  {
    caseId: 'C-000103',
    id: 'TEST-0003',
    visit: 'V-1003',
    initial: 'C',
    receiver: 'Patient records',
    kind: 'rejected',
    later: false,
    hours: 4,
  },
];

const hours = (n: number) => `${n} ${n === 1 ? 'hour' : 'hours'}`;

/** The digest for the settings as they stand, at each level of patient detail, in the server's words. */
export function reminderPreview(r: Reminders | undefined): { subject: string; body: string } {
  const detail = r?.patient_detail ?? REMINDER_DEFAULTS.patient_detail;
  const teamHours = r?.team_hours ?? REMINDER_DEFAULTS.team_hours;
  const officerHours = r?.officer_hours ?? REMINDER_DEFAULTS.officer_hours;
  const url = r?.sign_in_url ?? '';
  const oldest = Math.max(...SAMPLE.map((c) => c.hours));
  const start = r?.window_start ?? REMINDER_DEFAULTS.window_start;
  const end = r?.window_end ?? REMINDER_DEFAULTS.window_end;
  const days = (r?.days ?? REMINDER_DEFAULTS.days).map((d) => DAY_LABELS[d] ?? d).join(', ');
  const line = (c: (typeof SAMPLE)[number]) => {
    const age = `open ${hours(c.hours)}`;
    if (detail === 'none') return `${c.caseId}, ${age}`;
    const ids = `${c.caseId}, hospital number ${c.id} (DEMO), visit ${c.visit}`;
    return detail === 'identifiers_initial'
      ? `${ids}, first name ${c.initial}, ${age}`
      : `${ids}, ${age}`;
  };
  const groups = new Map<string, number>();
  for (const c of SAMPLE) {
    const g = `${c.receiver}, ${c.kind}`;
    groups.set(g, (groups.get(g) ?? 0) + 1);
  }
  const later = SAMPLE.filter((c) => c.later).length;
  return {
    subject: `Shutter: ${SAMPLE.length} cases need a person, the oldest open ${hours(oldest)}, waited for the window`,
    body: [
      'Hello,',
      '',
      `${SAMPLE.length} cases in Shutter need a person. This reminder went out by itself and nobody reviewed it. Sending it changed no case's state.`,
      '',
      `First reminder, open ${teamHours} hours or more: ${SAMPLE.length - later}`,
      `Later reminder, open ${officerHours} hours or more: ${later}`,
      `The oldest has been open ${hours(oldest)}.`,
      `Reminders go only from ${start} to ${end} on ${days}. 1 of these cases passed its reminder time before today's window opened, so this mail waited for it.`,
      '',
      ...[...groups].map(([g, n]) => `${g}: ${n}`),
      '',
      ...SAMPLE.map(line),
      '',
      url ? `Sign in to see them: ${url}` : 'Sign in to Shutter to see them.',
    ].join('\n'),
  };
}
