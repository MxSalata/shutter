import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock, SITE_ENTRIES_EXAMPLE } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { siteMatchOf, type SiteMatch } from '@/lib/siteEntry';
import { theme } from '@/theme';
import { SiteEntryNote } from './SiteEntryNote';

const BASE = '/api/shutter';

const summary = {
  catalogue: {
    decision: 'person',
    entry: 'L1',
    outcome: 'escalate',
    matches: [
      {
        id: 'L1',
        version: 1,
        title: 'A failed transfer into the isolation ward',
        origin: 'site',
        decides: 'person',
        preferred: {
          outcome: 'escalate',
          why: 'Infection control places every patient in this ward by hand.',
        },
        alternatives: [],
        instructions: "Ring the ward's nurse in charge before anything is entered. Do not resend.",
        team: '',
      },
    ],
    overridden: [{ id: 'E2', decides: 'policy', outcome: 'resend' }],
    site_also: [
      {
        id: 'L4',
        version: 2,
        title: 'Any failed transfer this week',
        instructions: 'Tell the bed manager first.',
        team: '',
      },
    ],
  },
};

function note(match: SiteMatch) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MantineProvider theme={theme}>
        <SiteEntryNote match={match} />
      </MantineProvider>
    </QueryClientProvider>,
  );
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('operator'));

describe("one of the site's own scenarios on a case's plan", () => {
  it('names the entry, its version and who approved it, with its instructions, the other entry that matched and what it displaced', async () => {
    server.use(http.get(`${BASE}/site-entries`, () => HttpResponse.json(SITE_ENTRIES_EXAMPLE)));
    note(siteMatchOf(summary)!);
    expect(screen.getByText('Our own scenario L1')).toBeInTheDocument();
    expect(screen.getByText('A failed transfer into the isolation ward')).toBeInTheDocument();
    expect(screen.getByTestId('site-entry-instructions')).toHaveTextContent(
      "Ring the ward's nurse in charge before anything is entered. Do not resend.",
    );
    expect(screen.getByTestId('site-entry-also')).toHaveTextContent(
      'L4, Any failed transfer this week, matched too: Tell the bed manager first.',
    );
    expect(screen.getByTestId('site-entry-without')).toHaveTextContent(
      'Without it: E2, a resend by site policy.',
    );
    expect(await screen.findByText(/approved by approver/)).toBeInTheDocument();
    expect(screen.getByTestId('site-entry-note')).toHaveTextContent('version 1');
    expect(screen.getByTestId('site-entry-note')).toHaveTextContent(
      'Shutter sends nothing and closes nothing by itself',
    );
  });

  it('still says everything the evidence holds when the entries cannot be read or the entry has moved on', async () => {
    server.use(
      http.get(`${BASE}/site-entries`, () => HttpResponse.json({ error: 'forbidden' }, { status: 403 })),
    );
    const match = siteMatchOf({ catalogue: { ...summary.catalogue, overridden: [], site_also: [] } })!;
    note(match);
    expect(screen.getByTestId('site-entry-instructions')).toBeInTheDocument();
    expect(screen.queryByTestId('site-entry-also')).not.toBeInTheDocument();
    expect(screen.getByTestId('site-entry-without')).toHaveTextContent(
      'no shipped entry matches, so this would be a new pattern',
    );
    expect(screen.queryByText(/approved by/)).not.toBeInTheDocument();
  });

  it('gives no approver to a match whose version the evidence does not say', async () => {
    server.use(http.get(`${BASE}/site-entries`, () => HttpResponse.json(SITE_ENTRIES_EXAMPLE)));
    const match = siteMatchOf(summary)!;
    note({ ...match, version: undefined });
    expect(await screen.findByTestId('site-entry-instructions')).toBeInTheDocument();
    // The entries are read, and still no approver is lent from the version in force now.
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(screen.queryByText(/approved by/)).not.toBeInTheDocument();
  });
});
