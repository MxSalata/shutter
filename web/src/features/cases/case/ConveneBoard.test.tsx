import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import CasePage from '../CasePage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderCase(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}`],
  });
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** GET /settings with the day's model budget, as a server of v1.34 sends it. */
function withBudget(budget: Record<string, unknown>) {
  server.use(http.get('/api/shutter/settings', () => HttpResponse.json({ ...fixtures.settings, budget })));
}

// C-000008 is S8's escalated board case; C-000001 is S1's, resolved
describe('Convene the board', () => {
  beforeEach(() => resetMock('approver'));

  it('is offered on a stopped case to those who may spend the model budget, with the budget beside it', async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false });
    let posted = '';
    server.use(
      http.post('/api/shutter/cases/:id/board', ({ params, request }) => {
        posted = `${String(params.id)} ${request.headers.get('X-Requested-With') ?? ''}`;
        return HttpResponse.json(
          { caseId: params.id, state: 'evidence', requestedBy: 'approver' },
          { status: 202 },
        );
      }),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog', { name: 'Convene the board on C-000008' });
    expect(within(dialog).getByText(/decides it live, whatever the site's policy says/)).toBeInTheDocument();
    expect(within(dialog).getByText("$4.20 of today's $15.00 spent on live runs")).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Convene' }));
    expect(await screen.findByText('The board is convening')).toBeInTheDocument();
    expect(posted).toBe('C-000008 Shutter');
  });

  it("says why it was refused, and can't be pressed once the caller's share is spent", async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 9, exhausted: false, perUserUsd: 3, spentByMeUsd: 1 });
    server.use(
      http.post('/api/shutter/cases/:id/board', () =>
        HttpResponse.json(
          { error: 'budget_exhausted', detail: "Your share of today's model budget is spent" },
          { status: 409 },
        ),
      ),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Your share: $1.00 of $3.00')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Convene' }));
    expect(
      await within(dialog).findByText(/Your share of today's model budget is spent/),
    ).toBeInTheDocument();
  });

  it('disables Convene when the share is already used up', async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 9, exhausted: false, perUserUsd: 3, spentByMeUsd: 3 });
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    expect(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Convene' })).toBeDisabled();
  });

  it("is not offered to the public demo's own user", async () => {
    resetMock('demo');
    renderCase('C-000008');
    expect(await screen.findByRole('heading', { name: 'Case C-000008' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Convene the board' })).not.toBeInTheDocument();
  });

  it('is not offered on a resolved case', async () => {
    renderCase('C-000001');
    expect(await screen.findByRole('heading', { name: 'Case C-000001' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Convene the board' })).not.toBeInTheDocument();
  });

  it('is offered to a judge', async () => {
    resetMock('judge');
    renderCase('C-000008');
    expect(await screen.findByRole('button', { name: 'Convene the board' })).toBeInTheDocument();
  });
});
