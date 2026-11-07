import { describe, expect, it } from 'vitest';
import { recordedSiteProfile } from '@/mocks/profile';
import { describePath, diffProfiles, fieldId, validateProfile } from './profile';
import { reminderPreview } from './reminderPreview';

const recorded = recordedSiteProfile()!.profile;
const withReminders = (reminders: unknown) =>
  ({
    ...structuredClone(recorded),
    mail: { allowed_domains: ['example.nhs.uk'] },
    reminders,
  }) as typeof recorded;

/** The rows of tests/unit/Shutter/Test/CaseReminder.cls's ProfileRows: the same words here as at the server. */
const RULES: [string, unknown, string][] = [
  ['nothing set is off and passes', {}, ''],
  [
    'the whole setting',
    {
      enabled: true,
      team_hours: 4,
      officer_hours: 8,
      officer_name: 'Test Officer',
      officer_address: 'officer@example.nhs.uk',
      window_start: '08:00',
      window_end: '18:00',
      days: ['mon', 'tue', 'wed', 'thu', 'fri'],
      patient_detail: 'identifiers',
      sign_in_url: 'https://shutter.example.nhs.uk/shutter/',
    },
    '',
  ],
  ['not an object', [], 'reminders: must be an object'],
  ['an unknown setting', { enable: true }, 'reminders.enable: unknown setting'],
  ['enabled as a word', { enabled: 'yes' }, 'reminders.enabled: must be true or false'],
  ['hours of zero', { team_hours: 0 }, 'reminders.team_hours: must be a whole number of hours from 1 to 720'],
  [
    'hours in part',
    { team_hours: 1.5 },
    'reminders.team_hours: must be a whole number of hours from 1 to 720',
  ],
  [
    'hours as text',
    { officer_hours: '8' },
    'reminders.officer_hours: must be a whole number of hours from 1 to 720',
  ],
  [
    'the officer no later than the team',
    { team_hours: 8, officer_hours: 8 },
    'reminders.officer_hours: must be later than team_hours',
  ],
  [
    'the officer before the default team hours',
    { officer_hours: 2 },
    'reminders.officer_hours: must be later than team_hours',
  ],
  [
    'a window start with no minutes',
    { window_start: '8' },
    'reminders.window_start: must be a time such as 08:00',
  ],
  ['an hour past the day', { window_end: '24:00' }, 'reminders.window_end: must be a time such as 08:00'],
  [
    'a window that ends before it starts',
    { window_start: '18:00', window_end: '08:00' },
    'reminders.window_end: must be later than window_start',
  ],
  [
    'a day that is none',
    { days: ['mon', 'funday'] },
    'reminders.days[1]: must be mon, tue, wed, thu, fri, sat or sun',
  ],
  ['no days', { days: [] }, 'reminders.days: must name at least one day'],
  ['days as text', { days: 'mon' }, 'reminders.days: must name at least one day'],
  [
    'a patient detail that is none',
    { patient_detail: 'full_name' },
    'reminders.patient_detail: must be none, identifiers or identifiers_initial',
  ],
  [
    'an officer outside the domains',
    { officer_address: 'a@evil.com' },
    'reminders.officer_address: not in the allowed domains',
  ],
  [
    "a header injected in the officer's address",
    { officer_address: 'a@example.nhs.uk\r\nBcc: e@evil.com' },
    'reminders.officer_address: must not contain line breaks or control characters',
  ],
  [
    "a display name in the officer's address",
    { officer_address: 'Officer <a@example.nhs.uk>' },
    'reminders.officer_address: must be a bare address, local@domain, with no display name, brackets or spaces',
  ],
  [
    "a line break in the officer's name",
    { officer_name: 'A\r\nB' },
    'reminders.officer_name: must not contain line breaks or control characters',
  ],
  [
    'a sign-in address that is not one',
    { sign_in_url: 'javascript:alert(1)' },
    'reminders.sign_in_url: must be an address starting http:// or https://, with no spaces',
  ],
  [
    'a sign-in address with a space',
    { sign_in_url: 'https://a b/' },
    'reminders.sign_in_url: must be an address starting http:// or https://, with no spaces',
  ],
];

describe('the reminder in the site profile', () => {
  it.each(RULES)('validates as the server does: %s', (_name, value, expected) => {
    expect(validateProfile(withReminders(value))).toBe(expected);
  });

  it('is absent from the shipped profile, so it is off', () => {
    expect(recorded.reminders).toBeUndefined();
  });

  it('lands a server error on its field and names it', () => {
    expect(fieldId('reminders.officer_address')).toBe('site-reminders-officer_address');
    expect(fieldId('reminders.days[1]')).toBe('site-reminders-days');
    expect(describePath('reminders.officer_address')).toBe('Reminders, officer address');
  });

  it('shows the change in the review, and says plainly when a mail starts going out unreviewed', () => {
    const on = diffProfiles(
      recorded,
      withReminders({ enabled: true, patient_detail: 'identifiers_initial' }),
    );
    const text = on.filter((c) => c.path.startsWith('reminders')).map((c) => c.text);
    expect(text.join(' ')).toMatch(/Reminders for cases left open: on, sent with nobody reviewing them/);
    expect(text.join(' ')).toMatch(/Identifiers and the first letter of the first name/);
    expect(
      diffProfiles(recorded, structuredClone(recorded)).some((c) => c.path.startsWith('reminders')),
    ).toBe(false);
  });
});

describe('the preview, with made-up patients', () => {
  it('follows the setting for patient detail', () => {
    expect(reminderPreview({ patient_detail: 'none' }).body).toMatch(/^C-000101, open 11 hours$/m);
    expect(reminderPreview({ patient_detail: 'none' }).body).not.toMatch(/hospital number/);
    expect(reminderPreview(undefined).body).toMatch(
      /^C-000101, hospital number TEST-0001 \(DEMO\), visit V-1001, open 11 hours$/m,
    );
    expect(reminderPreview({ patient_detail: 'identifiers_initial' }).body).toMatch(
      /visit V-1001, first name A, open 11 hours$/m,
    );
  });

  it('follows the hours and the sign-in address', () => {
    const p = reminderPreview({
      team_hours: 2,
      officer_hours: 6,
      sign_in_url: 'https://shutter.example.nhs.uk/',
    });
    expect(p.body).toMatch(/First reminder, open 2 hours or more: 2/);
    expect(p.body).toMatch(/Later reminder, open 6 hours or more: 1/);
    expect(p.body).toMatch(/Sign in to see them: https:\/\/shutter\.example\.nhs\.uk\//);
    expect(reminderPreview(undefined).body).toMatch(/Sign in to Shutter to see them\./);
  });

  it('says each case\'s age and that the mail waited for the window', () => {
    const p = reminderPreview({ window_start: '07:30', window_end: '19:00', days: ['mon', 'sat'] });
    expect(p.body).toMatch(/^C-000102, hospital number TEST-0002 \(DEMO\), visit V-1002, open 5 hours$/m);
    expect(p.body).toMatch(/Reminders go only from 07:30 to 19:00 on Mon, Sat\. 1 of these cases passed its/);
  });

  it('keeps identifiers out of the subject, and says nobody reviewed it', () => {
    for (const patient_detail of ['none', 'identifiers', 'identifiers_initial']) {
      const p = reminderPreview({ patient_detail });
      expect(p.subject).toBe('Shutter: 3 cases need a person, the oldest open 11 hours, waited for the window');
      expect(p.body).toMatch(/nobody reviewed it/);
    }
  });
});
