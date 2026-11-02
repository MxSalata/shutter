import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { CaseDetail, CaseEvent } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from '../CasePage';

/** Whether the page is the trial: set per test. */
const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return env.trial;
    },
  };
});

const ID = 'C-000008';
const recorded = (fixtures.cases as unknown as Record<string, { detail: CaseDetail; events: CaseEvent[] }>)[
  ID
];

let bodies: Record<string, unknown>[] = [];
let state: { detail: CaseDetail; events: CaseEvent[] };

/** The recorded case as one its workflow left collecting evidence, with the given events. */
function leftCollecting(events: CaseEvent[]) {
  state = { detail: { ...recorded.detail, state: 'collecting', disposition: '', closedAt: '' }, events };
  server.use(
    http.get(`/api/shutter/cases/${ID}`, () => HttpResponse.json(state.detail)),
    http.get(`/api/shutter/cases/${ID}/events`, () => HttpResponse.json(state.events)),
  );
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  env.trial = false;
  notifications.clean();
  bodies = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.url.endsWith('/abandon'))
      bodies.push((await request.clone().json()) as Record<string, unknown>);
  });
});

function renderCase() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${ID}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Waits for the case's events, which the panel reads, by their showing in the audit trail. */
async function eventsRead() {
  await userEvent.click(await screen.findByRole('tab', { name: 'Audit trail' }));
  const timeline = await screen.findByRole('region', { name: 'Timeline' });
  await waitFor(() => expect(within(timeline).queryByText('No events yet.')).toBeNull());
}

describe('AbandonPanel', () => {
  it('lets an approver abandon a case whose workflow stopped moving, with a reason and the case version', async () => {
    leftCollecting(recorded.events);
    server.use(
      http.post(`/api/shutter/cases/${ID}/abandon`, async ({ request }) => {
        const { reason } = (await request.json()) as { reason: string };
        state = {
          detail: {
            ...state.detail,
            state: 'failed',
            disposition: 'abandoned',
            version: state.detail.version + 1,
          },
          events: state.events,
        };
        return HttpResponse.json(
          { caseId: ID, state: 'abandoning', requestedBy: 'approver', reason },
          { status: 202 },
        );
      }),
    );
    renderCase();
    const panel = await screen.findByRole('region', { name: 'Still working' });
    expect(within(panel).getByText(/Nothing has moved for \d+ (minutes|hours|days)/)).toBeInTheDocument();
    await userEvent.click(within(panel).getByRole('button', { name: 'Abandon the case…' }));
    const dialog = await screen.findByRole('dialog', { name: `Abandon ${ID}` });
    const submit = within(dialog).getByRole('button', { name: 'Abandon the case' });
    expect(submit).toBeDisabled();
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /Why give it up/ }),
      'The production restarted mid-run',
    );
    await userEvent.click(submit);
    expect(await screen.findByText('Abandoning the case…')).toBeInTheDocument();
    expect(bodies).toEqual([
      { reason: 'The production restarted mid-run', expectedVersion: expect.any(Number) },
    ]);
    const top = await screen.findByRole('region', { name: 'Outcome' });
    await waitFor(() => expect(within(top).getByTestId('outcome-line')).toHaveTextContent('Abandoned'));
    expect(within(top).getByText('Gave the case up when its workflow stopped moving')).toBeInTheDocument();
    // The header says it once: the outcome, then the state it left the case in
    const status = screen.getByRole('heading', { name: `Case ${ID}` }).parentElement!;
    expect(within(status).getAllByText('Abandoned')).toHaveLength(1);
    expect(within(status).getByText('Failed')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
  });

  /** The server's busy refusal, its newest message in flight at the given time. */
  function refusedBusy(newestAt: string) {
    server.use(
      http.post(`/api/shutter/cases/${ID}/abandon`, () =>
        HttpResponse.json(
          {
            error: 'busy',
            detail: `The case's workflow has 1 message in flight (newest ${newestAt})`,
            state: 'collecting',
            inFlight: 1,
            newestAt,
            deferred: false,
          },
          { status: 409 },
        ),
      ),
    );
  }

  it('keeps the dialog open with the reason a busy case is refused, and when to try again', async () => {
    leftCollecting(recorded.events);
    refusedBusy(new Date(Date.now() - 5 * 60_000).toISOString());
    renderCase();
    const panel = await screen.findByRole('region', { name: 'Still working' });
    await userEvent.click(within(panel).getByRole('button', { name: 'Abandon the case…' }));
    const dialog = await screen.findByRole('dialog', { name: `Abandon ${ID}` });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Why give it up/ }), 'Stuck');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Abandon the case' }));
    const alert = await within(dialog).findByRole('alert');
    expect(alert).toHaveTextContent("The case's workflow has 1 message in flight");
    expect(alert).toHaveTextContent(/Try again after/);
    expect(screen.getByRole('dialog', { name: `Abandon ${ID}` })).toBeInTheDocument();
  });

  it('is not offered while the case still moves, nor to an operator', async () => {
    const fresh = recorded.events.map((e) => ({ ...e, at: new Date().toISOString() }));
    leftCollecting(fresh);
    const { unmount } = renderCase();
    expect(await screen.findByRole('heading', { name: `Case ${ID}` })).toBeInTheDocument();
    await eventsRead();
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
    unmount();

    resetMock('operator');
    leftCollecting(recorded.events);
    renderCase();
    await eventsRead();
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
  });
  it('names no retry time that has already passed', async () => {
    leftCollecting(recorded.events);
    refusedBusy('2026-10-25T09:00:00Z');
    renderCase();
    const panel = await screen.findByRole('region', { name: 'Still working' });
    await userEvent.click(within(panel).getByRole('button', { name: 'Abandon the case…' }));
    const dialog = await screen.findByRole('dialog', { name: `Abandon ${ID}` });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Why give it up/ }), 'Stuck');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Abandon the case' }));
    const alert = await within(dialog).findByRole('alert');
    expect(alert).toHaveTextContent("The case's workflow has 1 message in flight");
    expect(alert).not.toHaveTextContent(/Try again after/);
  });

  it('is not offered on a case that waits for an approval, however long', async () => {
    leftCollecting(recorded.events);
    state.detail = { ...state.detail, state: 'awaiting_approval' };
    renderCase();
    await eventsRead();
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
  });

  it('shows in the trial disabled, with its reason, and opens no dialog', async () => {
    env.trial = true;
    leftCollecting(recorded.events);
    renderCase();
    const panel = await screen.findByRole('region', { name: 'Still working' });
    const button = within(panel).getByRole('button', { name: 'Abandon the case…' });
    expect(button).toBeDisabled();
    expect(button).toHaveAccessibleDescription("Not in the trial's recording");
    await userEvent.click(button).catch(() => undefined);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(bodies).toEqual([]);
  });

  it('carries the live chip beside its confirm on a live system', async () => {
    leftCollecting(recorded.events);
    renderCase();
    const panel = await screen.findByRole('region', { name: 'Still working' });
    await userEvent.click(within(panel).getByRole('button', { name: 'Abandon the case…' }));
    const dialog = await screen.findByRole('dialog', { name: `Abandon ${ID}` });
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
  });
});
