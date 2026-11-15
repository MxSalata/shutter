import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { SiteEntriesView } from '@/api/types';
import { resetMock, SITE_ENTRIES_EXAMPLE } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { OwnScenarios } from './OwnScenarios';

const BASE = '/api/shutter';

function page() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MantineProvider theme={theme}>
        <OwnScenarios />
      </MantineProvider>
    </QueryClientProvider>,
  );
}

const answering = (body: SiteEntriesView) =>
  server.use(http.get(`${BASE}/site-entries`, () => HttpResponse.json(body)));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('operator');
  useAppearance.setState({ detail: 'plain' });
});

describe("the site's own scenarios on the Site profile page", () => {
  it('says there is none on a site that has none, and how one is made', async () => {
    page();
    expect(await screen.findByText(/None yet: the shipped catalogue alone decides/)).toBeInTheDocument();
    expect(screen.getByText(/can never allow a resend/)).toBeInTheDocument();
    expect(screen.queryByTestId('own-scenarios-list')).not.toBeInTheDocument();
  });

  it('lists an active entry with its sentence, who approved it and what it has stopped', async () => {
    answering(SITE_ENTRIES_EXAMPLE);
    page();
    const row = await screen.findByTestId('own-scenario-L1');
    expect(within(row).getByText('L1: A failed transfer into the isolation ward')).toBeInTheDocument();
    expect(within(row).getByText('Active')).toBeInTheDocument();
    expect(
      within(row).getByText(/When a transfer to Downstream Out from PAS fails.*a person decides\./),
    ).toBeInTheDocument();
    expect(within(row).getByText(/Version 1 approved by approver/)).toBeInTheDocument();
    expect(within(row).getByText(/0 cases sent to a person in the last 30 days/)).toBeInTheDocument();
    // Plain shows no condition names; nothing on the page changes an entry.
    expect(screen.queryByTestId('own-scenario-L1-pattern')).not.toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.queryByTestId('own-scenarios-warnings')).not.toBeInTheDocument();
  });

  it('shows the exact pattern, scope and digest in Technical', async () => {
    useAppearance.setState({ detail: 'technical' });
    answering(SITE_ENTRIES_EXAMPLE);
    page();
    const exact = await screen.findByTestId('own-scenario-L1-pattern');
    expect(exact).toHaveTextContent('"event":["transfer"]');
    expect(exact).toHaveTextContent('"ward":["WARD-ISO"]');
    expect(exact).toHaveTextContent('sha256:');
  });

  it('warns for a suspended entry and one that needs review, and says what waits for a second person', async () => {
    const example = SITE_ENTRIES_EXAMPLE.items[0];
    answering({
      ...SITE_ENTRIES_EXAMPLE,
      items: [
        {
          ...example,
          state: 'suspended',
          suspended: {
            by: 'approver',
            at: '2026-11-15T11:00:00Z',
            reason: 'It floods the on-call with escalations',
          },
          proposal: {
            action: 'resume',
            version: 1,
            digest: example.digest ?? '',
            by: 'approver',
            at: '2026-11-15T12:00:00Z',
          },
        },
        {
          ...example,
          id: 'L2',
          title: 'Any failed transfer this week',
          needsReview: true,
          review: {
            dropped: [{ condition: 'later_applied', why: "this release's vocabulary has no such condition" }],
            notes: [],
          },
          casesSent30: 1,
        },
        {
          ...example,
          id: 'L3',
          title: 'A draft',
          state: 'draft',
          activeVersion: 0,
          draftVersion: 1,
          approvedBy: undefined,
        },
        {
          ...example,
          id: 'L4',
          title: 'Waiting',
          state: 'proposed',
          activeVersion: 0,
          draftVersion: 1,
          approvedBy: undefined,
        },
      ],
      status: {
        ...SITE_ENTRIES_EXAMPLE.status,
        suspended: ['L1'],
        needsReview: ['L2'],
        onePerson: { by: 'admin', at: '2026-11-15T09:00:00Z', reason: 'One approver this month' },
        warnings: [
          'Site entry L1 is suspended (by approver, 2026-11-15T11:00:00Z): its protection is off until a second person approves resuming it',
          'Site entry L2 needs review: an upgrade or a change of the site profile touched it. It still applies',
          'The two-person rule for site entries is lifted (by admin, 2026-11-15T09:00:00Z): one person may propose and approve their own entry',
        ],
      },
    });
    page();
    const warnings = await screen.findByTestId('own-scenarios-warnings');
    expect(within(warnings).getByText(/L1 is suspended/)).toBeInTheDocument();
    expect(within(warnings).getByText(/L2 needs review/)).toBeInTheDocument();
    expect(within(warnings).getByText(/two-person rule for site entries is lifted/)).toBeInTheDocument();
    const suspended = screen.getByTestId('own-scenario-L1');
    expect(within(suspended).getByText('Suspended')).toBeInTheDocument();
    expect(within(suspended).getByText(/Suspended by approver.*It floods the on-call/)).toBeInTheDocument();
    expect(
      within(suspended).getByText(
        /Resuming it waits for a second person's approval \(proposed by approver\)/,
      ),
    ).toBeInTheDocument();
    const flagged = screen.getByTestId('own-scenario-L2');
    expect(within(flagged).getByText('Needs review')).toBeInTheDocument();
    expect(within(flagged).getByText(/No longer checked: later applied/)).toBeInTheDocument();
    expect(within(flagged).getByText(/1 case sent to a person in the last 30 days/)).toBeInTheDocument();
    expect(within(screen.getByTestId('own-scenario-L3')).getByText('Draft')).toBeInTheDocument();
    expect(within(screen.getByTestId('own-scenario-L3')).getByText(/Not approved yet/)).toBeInTheDocument();
    expect(
      within(screen.getByTestId('own-scenario-L4')).getByText('Waiting for approval'),
    ).toBeInTheDocument();
  });

  it('says so when the list cannot be read', async () => {
    server.use(
      http.get(`${BASE}/site-entries`, () => HttpResponse.json({ error: 'forbidden' }, { status: 403 })),
    );
    page();
    expect(await screen.findByText('Our own scenarios could not be read')).toBeInTheDocument();
  });
});
