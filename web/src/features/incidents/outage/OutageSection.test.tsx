import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { OFFERED_LABEL, OutageSection } from './OutageSection';
import type { Outage, OutageList } from './types';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

const NOW = new Date().toISOString();

/** An outage in the routes' shape (CONTRACTS 17), every field present, with the given changes. */
function outage(changes: Partial<Outage> = {}): Outage {
  return {
    id: '7',
    receiver: 'Results Out',
    namespace: 'LABSITE',
    item: 'Results Out',
    state: 'open',
    kind: 'down',
    openedAt: NOW,
    closedAt: null,
    pausedUntil: null,
    readings: null,
    alerts: [],
    lists: { queued: [], offered: [], reached: [], refused: [] },
    openCases: [],
    version: 3,
    set: {
      status: 'not_computed',
      reason: 'the queue holds 2 messages: nothing is listed while anything is being tried',
    },
    approvable: false,
    acts: ['pause', 'read_again', 'close'],
    outcome: null,
    words: {
      first: 'The listener has been unreachable since 03:12.',
      do: 'Do: start the listener.',
      call: 'Call: the lab on 01632 960998.',
      critical: null,
    },
    ...changes,
  };
}

function row(id: string, control: string, reason: string) {
  return {
    headerId: id,
    controlId: control,
    timeCreated: '2026-11-09 03:12:00',
    status: 'Error',
    attempts: 'never_opened',
    reason,
    patient: { id: '9990000301', authority: 'NHS' },
    sibling: null,
  };
}

function serve(list: OutageList | null, status = 200) {
  server.use(
    http.get('/api/shutter/outages', () =>
      list
        ? HttpResponse.json(list, { status })
        : HttpResponse.json({ error: 'not_in_trial', detail: 'x' }, { status: 501 }),
    ),
  );
}

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <OutageSection />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('OutageSection', () => {
  it('shows nothing when the server has no outage routes, as the trial answers', async () => {
    serve(null);
    const { container } = renderSection();
    await new Promise((r) => setTimeout(r, 50));
    expect(container.querySelector('[data-testid="outages"]')).toBeNull();
  });

  it("says why there is no list, in the set's own words, and lists only the row's acts", async () => {
    serve({ items: [outage()], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).getByText('The listener has been unreachable since 03:12.')).toBeInTheDocument();
    expect(within(card).getByText('Call: the lab on 01632 960998.')).toBeInTheDocument();
    expect(within(card).getByTestId('outage-no-lists')).toHaveTextContent(
      'No list of messages: the queue holds 2 messages: nothing is listed while anything is being tried.',
    );
    const acts = await within(card).findByTestId('outage-acts');
    expect(within(acts).getByRole('button', { name: 'Read again' })).toBeInTheDocument();
    expect(within(acts).getByRole('button', { name: 'Pause' })).toBeDisabled();
    expect(within(acts).getByRole('button', { name: 'Close' })).toBeDisabled();
  });

  it('shows no Read again when the row does not list it', async () => {
    serve({ items: [outage({ acts: ['pause', 'close'] })], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).queryByRole('button', { name: 'Read again' })).toBeNull();
  });

  it('lists an offered set under its label, with each reason, and never an approval control while approvable is false', async () => {
    serve({
      items: [
        outage({
          state: 'offered',
          set: { status: 'computed', reason: null, digest: 'abc' },
          lists: {
            offered: [
              row('41', 'CA', ''),
              row('44', 'CF', 'Shutter tried at 03:20; the connection never opened'),
            ],
            queued: [],
            reached: [row('42', 'CB', 'the receiver took it on an attempt')],
            refused: [row('43', 'CC', 'Suspended: set aside, not a delivery that failed')],
          },
        }),
      ],
      receivers: [],
    });
    renderSection();
    const lists = await screen.findByTestId('outage-lists');
    expect(lists).toHaveTextContent(`${OFFERED_LABEL} (2)`);
    expect(lists).toHaveTextContent(
      'Control id CF (header 44, Error): Shutter tried at 03:20; the connection never opened',
    );
    expect(lists).toHaveTextContent('Reached the receiver: check its screen (1)');
    expect(lists).toHaveTextContent('Not listed, with the reason (1)');
    expect(screen.queryByRole('button', { name: /approve/i })).toBeNull();
  });

  it('keeps a closed row with open cases, never green, listing them with their owners', async () => {
    serve({
      items: [
        outage({
          state: 'closed',
          acts: [],
          outcome: 'Transport outage closed. 1 delivery exception still needs review.',
          openCases: [{ caseId: 'C-000012', reason: 'Suspended AE', owner: 'the lab' }],
        }),
        outage({ id: '8', state: 'closed', acts: [], outcome: 'Delivery backlog drained.' }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).getByTestId('outage-open-cases')).toHaveTextContent(
      'C-000012: Suspended AE (owner: the lab)',
    );
    expect(within(card).getByText('closed')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Outage 8, Results Out' })).toBeNull();
    expect(within(card).queryByTestId('outage-acts')).toBeNull();
  });

  it("says a watcher's reading is stale when it has not answered for a minute", async () => {
    const old = new Date(Date.now() - 5 * 60_000).toISOString();
    serve({
      items: [],
      receivers: [
        {
          receiver: 'Results Out',
          namespace: 'LABSITE',
          item: 'Results Out',
          reading: 'healthy',
          checkedAt: NOW,
        },
        { receiver: 'LIMS Out', namespace: 'LABSITE', item: 'LIMS Out', reading: 'healthy', checkedAt: old },
      ],
    });
    renderSection();
    const readings = await screen.findByTestId('readings');
    const lines = readings.querySelectorAll('[data-stale]');
    expect(lines[0]?.getAttribute('data-stale')).toBe('false');
    expect(lines[1]?.getAttribute('data-stale')).toBe('true');
    expect(lines[1]).toHaveTextContent('what is shown may be out of date');
  });

  it('shows an operator no acts', async () => {
    resetMock('operator');
    serve({ items: [outage()], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).queryByTestId('outage-acts')).toBeNull();
  });
});
