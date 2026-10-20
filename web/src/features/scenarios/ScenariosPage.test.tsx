import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderScenarios() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <ScenariosPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
  return client;
}

/** A scenario's card, found by its Run button. */
async function card(id: string) {
  const run = await screen.findByRole('button', { name: `Run ${id}` });
  return run.closest<HTMLElement>('.mantine-Card-root')!;
}

describe('ScenariosPage', () => {
  beforeEach(() => resetMock('approver'));

  it('offers every mode outside the demo', async () => {
    renderScenarios();
    expect(await screen.findByRole('radio', { name: 'Single investigator' })).toBeInTheDocument();
  });

  it('shows no guided path outside the demo: an instance has its own cases', async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Start here' })).not.toBeInTheDocument();
  });

  it("greys out a scenario in a mode it isn't defined for, and says which modes it is", async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S7' })).toBeEnabled();
    await userEvent.click(screen.getByRole('radio', { name: 'Site policy' }));
    const s7 = await card('S7');
    expect(within(s7).getByRole('button', { name: 'Run S7' })).toBeDisabled();
    expect(
      within(s7).getByText(
        'Not defined for Site policy mode. Its modes: Board, Single investigator, Rules only.',
      ),
    ).toBeInTheDocument();
    expect(within(await card('S2')).getByRole('button', { name: 'Run S2' })).toBeEnabled();
  });

  it('offers runs on a demo instance', async () => {
    const client = renderScenarios();
    await waitFor(() => expect(client.getQueryState(keys.health)?.status).toBe('success'));
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeEnabled();
    expect(screen.queryByText('The Scenario Player is switched off')).not.toBeInTheDocument();
  });

  it('says the Scenario Player is switched off on a site install, and offers no runs', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: false })));
    renderScenarios();
    expect(await screen.findByText('The Scenario Player is switched off')).toBeInTheDocument();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeDisabled();
    const runs = screen.getAllByRole('button', { name: /^Run S\d+$/ });
    expect(runs.length).toBeGreaterThan(1);
    for (const run of runs) expect(run).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeDisabled();
    expect(screen.queryByRole('radio', { name: 'Board' })).not.toBeInTheDocument();
    // No card is greyed out for a mode when there is no mode to play in
    expect(screen.queryByText(/^Not defined for/)).not.toBeInTheDocument();
  });
});
