import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { formatTime, zoneLabel } from '@/lib/format';
import { INSTALL_URL } from '@/lib/liveAgents';
import { axeViolations } from '@/test/axe';
import { layer1Words } from '@/test/words';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
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
  beforeEach(() => {
    resetMock('approver');
    env.trial = false;
    notifications.clean();
  });

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
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
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
    // The refusal reads as the notice, the share apart from the cap, and Convene can't be pressed again
    expect(layer1Words(await within(dialog).findByRole('status')).join(' ')).toBe(
      'Your share of the live budget is used up until 00:00 UTC. Open cases, recorded runs and the trial still work. To run the live agents yourself, install Shutter with your own API key: how to install',
    );
    expect(within(dialog).queryByText(/budget_exhausted/)).not.toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Convene' })).toBeDisabled();
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

  // C-000014 is S1's blocked rules case, C-000061 S23c's blocked site policy case
  it('says why there is no board to convene on a rules case, in place of the button', async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false });
    renderCase('C-000014');
    expect(
      await screen.findByText(
        'No board to convene: a Rules only case is decided by its rules, with no agents.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Convene the board' })).not.toBeInTheDocument();
  });

  it('keeps the board on a site policy case, which the policy may leave to the board', async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false });
    renderCase('C-000061');
    expect(await screen.findByRole('button', { name: 'Convene the board' })).toBeInTheDocument();
  });

  it("says nothing of the board on a rules case to the public demo's own user, who is never offered it", async () => {
    resetMock('demo');
    renderCase('C-000014');
    expect(await screen.findByRole('heading', { name: 'Case C-000014' })).toBeInTheDocument();
    expect(screen.queryByTestId('convene-reason')).not.toBeInTheDocument();
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

  it('says the budget per reset on the public demo, which resets every hour', async () => {
    server.use(
      http.get('/api/shutter/settings', () =>
        HttpResponse.json({
          ...fixtures.settings,
          live: { enabled: true },
          budget: { dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false },
        }),
      ),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog', { name: 'Convene the board on C-000008' });
    expect(
      await within(dialog).findByText(
        '$4.20 of the $15.00 per reset spent on live runs since the demo last reset (every hour)',
      ),
    ).toBeInTheDocument();
    expect(within(dialog).queryByText(/today/)).not.toBeInTheDocument();
  });

  it('says the live agents cannot run, and until when, while live.agents says so, and cannot be pressed', async () => {
    const until = new Date(Date.now() + 200 * 60_000).toISOString();
    server.use(
      http.get('/api/shutter/settings', () =>
        HttpResponse.json({
          ...fixtures.settings,
          live: { enabled: false, agents: { available: false, reason: 'provider_auth', until } },
          budget: { dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false },
        }),
      ),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog', { name: 'Convene the board on C-000008' });
    const note = await within(dialog).findByRole('note');
    expect(note).toHaveTextContent(
      `The live AI service for this demo is unavailable until ${formatTime(until).slice(0, 5)} ${zoneLabel(until)}.`,
    );
    expect(within(note).getByRole('link', { name: 'how to install' })).toHaveAttribute('href', INSTALL_URL);
    // The notice stands in for the budget's line
    expect(within(dialog).queryByText(/spent on live runs/)).not.toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Convene' })).toBeDisabled();
    expect(await axeViolations(dialog)).toEqual([]);
  });

  it('reads a 409 live_unavailable with its live object as the notice, with the time it gives', async () => {
    withBudget({ dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false });
    const until = new Date(Date.now() + 200 * 60_000).toISOString();
    server.use(
      http.post('/api/shutter/cases/:id/board', () =>
        HttpResponse.json(
          {
            error: 'live_unavailable',
            detail: "The model provider refused Shutter's key (provider_auth)",
            live: { available: false, reason: 'provider_auth', until, detail: 'refused' },
          },
          { status: 409 },
        ),
      ),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Convene' }));
    expect(await within(dialog).findByRole('status')).toHaveTextContent(
      `The live AI service for this demo is unavailable until ${formatTime(until).slice(0, 5)} ${zoneLabel(until)}.`,
    );
    expect(within(dialog).queryByText(/live_unavailable|provider_auth/)).not.toBeInTheDocument();
  });

  it("says the public demo's budget is used up until its next reset, from the budget alone", async () => {
    const resets = new Date(Date.now() + 40 * 60_000).toISOString();
    server.use(
      http.get('/api/shutter/settings', () =>
        HttpResponse.json({
          ...fixtures.settings,
          live: { enabled: true },
          budget: { dailyUsd: 2, spentTodayUsd: 2.05, exhausted: true, resetsAt: resets },
        }),
      ),
    );
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Convene the board' }));
    const dialog = await screen.findByRole('dialog', { name: 'Convene the board on C-000008' });
    expect(await within(dialog).findByRole('note')).toHaveTextContent(
      `The live AI budget for this demo is used up until ${formatTime(resets).slice(0, 5)} ${zoneLabel(resets)}, when the demo resets.`,
    );
    expect(within(dialog).getByRole('button', { name: 'Convene' })).toBeDisabled();
  });

  it('shows in the trial disabled, with its reason, and never as if a run started', async () => {
    env.trial = true;
    let posted = 0;
    server.use(
      http.post('/api/shutter/cases/:id/board', () => {
        posted += 1;
        return HttpResponse.json({}, { status: 202 });
      }),
    );
    renderCase('C-000008');
    const button = await screen.findByRole('button', { name: 'Convene the board' });
    expect(button).toBeDisabled();
    expect(button).toHaveAccessibleDescription('Needs a real model: not in the trial');
    await userEvent.click(button).catch(() => undefined);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.queryByText('The board is convening')).not.toBeInTheDocument();
    expect(posted).toBe(0);
  });

  it('says in the trial too why a rules case has no board to convene, with no disabled button', async () => {
    env.trial = true;
    renderCase('C-000014');
    expect(
      await screen.findByText(
        'No board to convene: a Rules only case is decided by its rules, with no agents.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Convene the board' })).not.toBeInTheDocument();
  });

  it('is not shown in the trial on a resolved case either', async () => {
    env.trial = true;
    renderCase('C-000001');
    expect(await screen.findByRole('heading', { name: 'Case C-000001' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Convene the board' })).not.toBeInTheDocument();
  });
});
