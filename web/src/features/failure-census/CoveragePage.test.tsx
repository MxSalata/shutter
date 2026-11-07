import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import CoveragePage from './CoveragePage';
import type { CensusOverview, CensusReport } from './coverage';

const BASE = '/api/shutter';
const STATEMENT = 'This compares engine-visible delivery failures with Shutter cases.';

const overview = (over: Partial<CensusOverview> = {}): CensusOverview => ({
  enabled: true,
  statement: STATEMENT,
  maxWindowHours: 24,
  maxHeaders: 10000,
  scopes: [{ receiver: 'Lab Out', namespace: 'LAB', item: 'Lab Out' }],
  items: [],
  ...over,
});

const report = (over: Partial<CensusReport> = {}): CensusReport => ({
  runId: 'FC-000001',
  receiver: 'Lab Out',
  namespace: 'LAB',
  window: { from: '2026-11-06T01:00:00Z', to: '2026-11-06T02:00:00Z' },
  cutoff: '2026-11-06T02:00:01Z',
  sourceRead: 'ok',
  sourceError: '',
  completeness: 'complete',
  reasons: [],
  scanned: 10,
  startedAt: '2026-11-06T02:00:00Z',
  requestedBy: 'oper',
  statement: STATEMENT,
  totals: {
    deliveries: 10,
    completed: 6,
    notFinished: 0,
    failures: 4,
    eligible: 4,
    exact: 2,
    none: 1,
    ambiguous: 1,
    excluded: 0,
    unassessable: 0,
    missingIds: 0,
    evidenceGaps: 0,
    distinctCases: 3,
  },
  items: [
    {
      deliveryHeaderId: '11',
      target: 'Lab Out',
      sessionId: '5',
      originHeaderId: '',
      timeCreated: '2026-11-06T01:00:00Z',
      sourceStatus: 'error',
      family: 'ORU',
      resendOf: '',
      caseIds: 'C-000007',
      linkQuality: 'exact',
      eligibility: 'in_scope',
      explanation: 'only_delivery_in_session',
    },
  ],
  ...over,
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  cleanup();
});
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/coverage', element: <CoveragePage /> }], {
    initialEntries: ['/coverage'],
  });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

function answers(over: CensusOverview, run?: CensusReport) {
  const posted: unknown[] = [];
  server.use(
    http.get(`${BASE}/failure-census`, () => HttpResponse.json(over)),
    http.post(`${BASE}/failure-census`, async ({ request }) => {
      posted.push(await request.json());
      return HttpResponse.json(run, { status: 201 });
    }),
    http.get(`${BASE}/failure-census/:id`, () => HttpResponse.json(run)),
  );
  return posted;
}

describe('Source failure coverage', () => {
  it('says it is off, and offers no run, until the profile turns it on', async () => {
    answers(overview({ enabled: false }));
    renderPage();
    expect(await screen.findByText('The census is off')).toBeInTheDocument();
    expect(screen.getByText(STATEMENT)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Run the census' })).not.toBeInTheDocument();
  });

  it('runs on a registered receiver and shows the counts, the row and the CSV', async () => {
    const posted = answers(overview(), report());
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Run the census' }));
    expect(await screen.findByText('Census complete: every delivery in the period was read.')).toBeInTheDocument();
    expect(screen.getByText('No linked case').previousSibling).toHaveTextContent('1');
    expect(screen.getByText('Exactly linked').previousSibling).toHaveTextContent('2');
    expect(screen.getByRole('link', { name: 'C-000007' })).toHaveAttribute('href', '/cases/C-000007');
    expect(screen.getByRole('link', { name: 'Download CSV' })).toHaveAttribute(
      'href',
      `${BASE}/failure-census/FC-000001.csv`,
    );
    expect(posted[0]).toMatchObject({ receiver: 'Lab Out' });
    expect(Object.keys(posted[0] as object).sort()).toEqual(['from', 'receiver', 'to']);
  });

  it('shows an unreadable source as unknown, never as zero', async () => {
    const nulls = Object.fromEntries(Object.keys(report().totals).map((k) => [k, null]));
    answers(
      overview(),
      report({
        completeness: 'unknown',
        sourceRead: 'unavailable',
        sourceError: '<DIRECTORY>',
        reasons: ['source_unreadable'],
        scanned: null,
        totals: nulls as unknown as CensusReport['totals'],
        items: [],
      }),
    );
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Run the census' }));
    expect(await screen.findByText('Source reads unavailable: this is not zero failures')).toBeInTheDocument();
    expect(screen.getByText('Eligible source failures').previousSibling).toHaveTextContent('unknown');
    expect(screen.getByText('No linked case').previousSibling).toHaveTextContent('unknown');
    expect(screen.queryByText('0')).not.toBeInTheDocument();
  });

  it('shows a cap hit as incomplete, with why', async () => {
    answers(overview(), report({ completeness: 'incomplete', reasons: ['header_cap_hit'] }));
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Run the census' }));
    expect(await screen.findByText('Census incomplete')).toBeInTheDocument();
    expect(screen.getByText(/stopped at the most headers allowed/)).toBeInTheDocument();
    expect(screen.queryByText(/Census complete/)).not.toBeInTheDocument();
  });
});
