import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import SettingsPage from './SettingsPage';

/** The page as the trial shows it: the recorded instance, answered in the browser. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

function renderTrial() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/settings', element: <SettingsPage /> }], {
    initialEntries: ['/settings'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('SettingsPage in the trial', () => {
  it('says what was spent here and that every answer is a replay, with no "live"', async () => {
    renderTrial();
    const band = await screen.findByRole('region', { name: 'Summary' });
    expect(within(band).getByText('Spent here')).toBeInTheDocument();
    expect(within(band).getByText('every answer here is a replay')).toBeInTheDocument();
    const line = await screen.findByText(/64 replayed runs cost nothing\./);
    expect(line).toHaveTextContent(
      "$0.00 spent here: every answer is a replay. 64 replayed runs cost nothing. The production reviews' agent answered 2 times, listed apart below.",
    );
  });

  it('keeps the word "live" out of the first layer: the tiles, the Agents intro, the costs and the prices', async () => {
    renderTrial();
    await screen.findByRole('button', { name: /^Every case/ });
    expect(layer1Words(document.body).join(' ')).not.toMatch(/\blive\b/i);
  });

  it('keeps "live" for the second layer, where the expert expects it', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderTrial();
    const detail = await screen.findByRole('button', { name: 'Classes, modes, models and budgets' });
    expect(detail).toHaveAttribute('aria-expanded', 'true');
    // The recorded instance had AI Hub, its runner and a provider, so nothing is listed as missing
    expect(screen.queryByText(/^Not on this instance:/)).not.toBeInTheDocument();
    expect(screen.getByRole('table', { name: 'Settings of the agent items' })).toBeVisible();
    expect(document.body.textContent).toMatch(/\blive\b/i);
  });

  it('names a run by how it was made: replayed, and a real one as "real", never "live"', async () => {
    server.use(
      http.get('/api/shutter/costs', () =>
        HttpResponse.json({
          totals: { spentUsd: 0.5, liveRuns: 1, replayedRuns: 1 },
          byModel: [
            {
              model: 'claude-opus-5-5',
              mode: 'replay',
              runs: 1,
              promptTokens: 1,
              completionTokens: 1,
              cacheReadTokens: 0,
              costUsd: 0,
            },
            {
              model: 'claude-opus-5-5',
              mode: 'live',
              runs: 1,
              promptTokens: 1,
              completionTokens: 1,
              cacheReadTokens: 0,
              costUsd: 0.5,
            },
          ],
          byDay: [],
          byCase: [],
        }),
      ),
    );
    renderTrial();
    const table = await screen.findByRole('table', { name: 'Costs by model' });
    expect(within(table).getByText(/replayed/)).toBeInTheDocument();
    expect(within(table).getByText(/real/)).toBeInTheDocument();
    expect(within(table).queryByText(/live/)).not.toBeInTheDocument();
  });

  it('names a replayed review run by the model its recording was made with, and as replayed', async () => {
    renderTrial();
    const table = await screen.findByRole('table', { name: 'Costs by production review' });
    const row = within(table).getAllByRole('row')[1];
    expect(within(row).getByText('claude-opus-5-5')).toBeInTheDocument();
    expect(within(row).getByText(/replayed/)).toBeInTheDocument();
    expect(within(row).queryByText(/none/)).not.toBeInTheDocument();
  });
});
