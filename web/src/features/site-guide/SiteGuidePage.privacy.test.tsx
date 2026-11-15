import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import SiteGuidePage from './SiteGuidePage';

/**
 * This site's guide holds configuration and words only, in the rule of tests/privacy_check.py: rendered from the trial's
 * recorded data, in Plain and in Technical, no case, message or patient value of the recording appears in it, nor a
 * mail address or domain of the profile, nor an API path, nor anything shaped like an NHS number.
 */

vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return true;
  },
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => resetMock('demo'));

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/** Every string value under one of these keys, anywhere in the recording's cases. */
function valuesOf(o: Json, keys: string[], out = new Set<string>()): Set<string> {
  if (Array.isArray(o)) for (const v of o) valuesOf(v, keys, out);
  else if (o && typeof o === 'object')
    for (const [k, v] of Object.entries(o)) {
      if (keys.includes(k) && typeof v === 'string' && v) out.add(v);
      valuesOf(v, keys, out);
    }
  return out;
}

const CASE_KEYS = [
  'caseId',
  'case_id',
  'patientId',
  'patient_id',
  'encounterId',
  'encounter_id',
  'operationKey',
  'operation_key',
  'sourceMessageId',
  'patient_name',
  'bed',
];

/** The patient and case values of the recording, and what the profile's mail and API settings hold. */
function forbidden(): string[] {
  const values = valuesOf(fixtures.cases as unknown as Json, CASE_KEYS);
  const profile = fixtures.siteProfile.profile as unknown as {
    mail?: { allowed_domains?: string[]; from?: string };
    teams?: { mailbox?: string }[];
    receivers: { api?: Record<string, string> }[];
  };
  for (const d of profile.mail?.allowed_domains ?? []) values.add(d);
  if (profile.mail?.from) values.add(profile.mail.from);
  for (const t of profile.teams ?? []) if (t.mailbox) values.add(t.mailbox);
  for (const r of profile.receivers)
    for (const v of Object.values(r.api ?? {})) if (v.length > 1) values.add(v);
  // A name is checked by its parts too, as a summary would write it ("SYNTH, ADA" as "Ada Synth")
  for (const v of [...values]) if (/^[A-Z]+, [A-Z]+$/.test(v)) v.split(', ').forEach((p) => values.add(p));
  return [...values].filter((v) => v.length >= 4);
}

/** Ten digits, plain or spaced 3 3 4, whose modulus 11 check digit is valid: an NHS number's shape. */
function nhsShaped(text: string): string[] {
  return [...text.matchAll(/(?<![\w-])(\d{3})[ -]?(\d{3})[ -]?(\d{4})(?![\w-])/g)]
    .map((m) => m.slice(1).join(''))
    .filter((d) => {
      const sum = [...d.slice(0, 9)].reduce((a, c, i) => a + Number(c) * (10 - i), 0);
      const check = 11 - (sum % 11);
      return (check === 11 ? 0 : check) === Number(d[9]) && check !== 10;
    });
}

function renderGuide() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/site-guide', element: <SiteGuidePage /> }], {
    initialEntries: ['/site-guide'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe("This site's guide and the patient's data", () => {
  it('holds the recording’s many patient values to check against', () => {
    expect(forbidden().length).toBeGreaterThan(100);
    expect(forbidden()).toContain('example.nhs.uk');
  });

  for (const detail of ['plain', 'technical'] as const)
    it(`shows no case, message, patient, mail address, domain or API path, in ${detail}`, async () => {
      const { container } = renderGuide();
      await screen.findByRole('heading', { level: 1, name: "This site's guide" });
      if (detail === 'technical') await userEvent.click(screen.getByRole('radio', { name: 'Technical' }));
      const text = container.textContent ?? '';
      // The trial says its data is sample data, on the cover and in the stamp at the foot of every page
      expect(text).toContain('Trial (sample data)');
      // Whole words, in any case, as tests/privacy_check.py matches them: "SYNTH" is a name, "synthetic" is not
      const word = (v: string) =>
        new RegExp(`(?<![\\p{L}\\p{N}])${v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\p{L}\\p{N}])`, 'iu');
      expect(forbidden().filter((v) => word(v).test(text))).toEqual([]);
      expect(text.match(/[\w.+-]+@[\w-]+\.[\w.]+/g)).toBeNull();
      expect(text.match(/\bC-\d{6}\b/g)).toBeNull();
      expect(text.match(/\/api\/|\/downstream\//g)).toBeNull();
      expect(nhsShaped(text)).toEqual([]);
    });
});
