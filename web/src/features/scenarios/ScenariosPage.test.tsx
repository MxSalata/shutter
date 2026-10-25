import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import type { Scenario } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
import definitions from '../../../../fixtures/scenarios.json';

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

  it("puts the scenario cards' headings under a heading of their own", async () => {
    renderScenarios();
    const run = await screen.findByRole('button', { name: 'Run S2' });
    const heading = screen.getByRole('heading', { name: 'Every scenario', level: 2 });
    const card = within(run.closest<HTMLElement>('.mantine-Card-root')!).getByRole('heading', { level: 3 });
    expect(heading.compareDocumentPosition(card) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('shows no guided path outside the demo: an instance has its own cases', async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Start here' })).not.toBeInTheDocument();
  });

  it('leads with the induction prompt on an instance running the shipped profile', async () => {
    renderScenarios();
    const prompt = await screen.findByText('Shutter is running on the shipped site profile');
    const heading = screen.getByRole('heading', { name: 'Scenarios' });
    expect(prompt.compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
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

  it("shows a mode's own expected outcome: S21's resend that the gate blocks, in Rules only mode only", async () => {
    const s21 = (definitions as unknown as Scenario[]).find((d) => d.id === 'S21')!;
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({ scenarios: [{ ...s21, latestCase: null }], run: null }),
      ),
    );
    renderScenarios();
    await userEvent.click(await screen.findByRole('radio', { name: 'Site policy' }));
    let s = await card('S21');
    expect(within(s).getByText('or More evidence')).toBeInTheDocument();
    expect(within(s).queryByText('or Resend')).not.toBeInTheDocument();
    expect(within(s).queryByText('EVENT_TIME_IMPLAUSIBLE')).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('radio', { name: 'Rules only' }));
    s = await card('S21');
    expect(within(s).getByText('or Resend')).toBeInTheDocument();
    expect(within(s).queryByText('or More evidence')).not.toBeInTheDocument();
    expect(within(s).getByText('EVENT_TIME_IMPLAUSIBLE')).toBeInTheDocument();
    expect(within(s).getByText('Nothing written')).toBeInTheDocument();
  });

  it('says how many encounters an incident scenario opens and the writes their chains make in all', async () => {
    renderScenarios();
    for (const id of ['S11', 'S12']) {
      const def = (definitions as unknown as Scenario[]).find((d) => d.id === id)!;
      const encounters = def.expected!.encounters!;
      const writes = encounters.reduce((n, e) => n + (e.writes || 0), 0);
      const c = await card(id);
      expect(
        within(c).getByText(
          `Opens one incident of ${encounters.length} encounters, each released as its own chain.`,
        ),
      ).toBeInTheDocument();
      expect(within(c).getByText(`${writes} conditional writes in all`)).toBeInTheDocument();
    }
    // The catalogue's two incidents, as it defines them today
    expect(within(await card('S11')).getByText(/of 6 encounters/)).toBeInTheDocument();
    expect(within(await card('S12')).getByText(/of 4 encounters/)).toBeInTheDocument();
    // A scenario of one case ends in a state, with no incident line
    const s2 = await card('S2');
    expect(within(s2).queryByText(/Opens one incident/)).not.toBeInTheDocument();
    expect(within(s2).getByText(/^Ends /)).toBeInTheDocument();
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
