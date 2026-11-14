import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { PathologyPath, ScenarioRun } from '@/api/types';
import { server } from '@/mocks/node';
import { LOOK_ONLY_DEMO, mockPathology, resetMock } from '@/mocks/handlers';
import { ORDERS_RESULTS_BRIEF } from '@/lib/categories';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
import { PathologyRunBanner } from './PathologyPaths';
import { PATHOLOGY_WORDS } from './pathologyText';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';
import { SCENARIOS_DEFINED } from './scenarioText';
import paths from '../../../../fixtures/pathology.json';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock());
afterEach(() => {
  cleanup();
  resetMock();
});

/** The two paths as GET /scenarios lists them on a live demo, with what each last opened. */
function listed(p2Outage: PathologyPath['latestOutage'] = null): PathologyPath[] {
  return paths.map((p) => ({
    ...(p as unknown as PathologyPath),
    kind: 'pathology' as const,
    latestCase:
      p.id === 'P1'
        ? { caseId: 'C-000901', state: 'escalated', disposition: 'escalate', headline: 'A person decides' }
        : null,
    latestOutage: p.id === 'P2' ? p2Outage : null,
  }));
}

function renderPage(detail: DetailLevel = 'plain', route = <ScenariosPage />) {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>{route}</MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('The pathology paths on the demo (1.4.6)', () => {
  it('lists the two paths apart from the scenarios, saying no agent runs, with their latest results', async () => {
    mockPathology(listed({ id: 7, state: 'offered', openedAt: '2026-11-14T02:32:04Z' }));
    renderPage();
    const group = await screen.findByRole('region', { name: PATHOLOGY_WORDS.title });
    expect(within(group).getByText(PATHOLOGY_WORDS.lead)).toBeInTheDocument();
    expect(PATHOLOGY_WORDS.lead).toContain(`apart from the ${SCENARIOS_DEFINED} scenarios`);
    expect(PATHOLOGY_WORDS.lead).toContain('No agent runs and no model is called.');
    expect(PATHOLOGY_WORDS.lead).toContain(ORDERS_RESULTS_BRIEF);
    const p1 = within(group).getByRole('article', { name: paths[0].title });
    expect(within(p1).getByRole('link', { name: 'C-000901' })).toHaveAttribute('href', '/cases/C-000901');
    expect(within(p1).getByRole('button', { name: 'Run P1' })).toBeEnabled();
    const p2 = within(group).getByRole('article', { name: paths[1].title });
    expect(within(p2).getByRole('link', { name: 'Outage 7 on Incidents' })).toHaveAttribute(
      'href',
      '/incidents#outage-7',
    );
    // The server refuses P2 while its last outage is open: the page says so on the button, before anyone presses it
    expect(within(p2).getByRole('button', { name: 'Run P2' })).toBeDisabled();
    expect(within(p2).getByText(PATHOLOGY_WORDS.outageOpen)).toBeInTheDocument();
    // The optional link after the main route's three
    expect(screen.getByRole('link', { name: PATHOLOGY_WORDS.link })).toHaveAttribute('href', '#pathology');
  });

  it('offers P2 again once its outage is closed', async () => {
    mockPathology(listed({ id: 7, state: 'closed', openedAt: '2026-11-14T02:32:04Z' }));
    renderPage();
    const group = await screen.findByRole('region', { name: PATHOLOGY_WORDS.title });
    const p2 = within(group).getByRole('article', { name: paths[1].title });
    expect(within(p2).getByRole('button', { name: 'Run P2' })).toBeEnabled();
    expect(within(p2).queryByText(PATHOLOGY_WORDS.outageOpen)).not.toBeInTheDocument();
  });

  it('shows nothing where the server lists no paths: the trial, a site, a demo without the results route', async () => {
    renderPage();
    await screen.findByRole('button', { name: 'Run S2' });
    expect(screen.queryByRole('region', { name: PATHOLOGY_WORDS.title })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: PATHOLOGY_WORDS.link })).not.toBeInTheDocument();
  });

  it("a sign-in that may not run scenarios sees the paths and can't run them", async () => {
    resetMock('demo');
    server.use(http.get('/api/shutter/me', () => HttpResponse.json(LOOK_ONLY_DEMO)));
    mockPathology(listed());
    renderPage();
    const group = await screen.findByRole('region', { name: PATHOLOGY_WORDS.title });
    for (const id of ['P1', 'P2'])
      expect(within(group).getByRole('button', { name: `Run ${id}` })).toBeDisabled();
  });

  it("a run's banner says what it does, that no agent runs, and where its outage is", () => {
    const run: ScenarioRun = {
      scenario: 'P2',
      mode: 'board',
      startedAt: '2026-11-14T02:31:58Z',
      state: 'running',
      files: ['result-1.hl7'],
      timeouts: [],
      step: 'taking the demo results system down',
    };
    const path = listed({ id: 7, state: 'offered', openedAt: '2026-11-14T02:32:04Z' })[1];
    renderPage('plain', <PathologyRunBanner run={run} path={path} />);
    expect(screen.getByText('Playing P2')).toBeInTheDocument();
    expect(screen.getByText(/^Now taking the demo results system down\./)).toBeInTheDocument();
    expect(screen.getByText(PATHOLOGY_WORDS.noAgent)).toBeInTheDocument();
    cleanup();
    renderPage(
      'plain',
      <PathologyRunBanner run={{ ...run, state: 'done', finishedAt: run.startedAt }} path={path} />,
    );
    expect(screen.getByRole('link', { name: 'Open its outage on Incidents' })).toHaveAttribute(
      'href',
      '/incidents#outage-7',
    );
    cleanup();
    renderPage(
      'plain',
      <PathologyRunBanner
        run={{ ...run, state: 'failed', error: "The last run's outage is still open" }}
        path={path}
      />,
    );
    expect(screen.getByText('P2 failed')).toBeInTheDocument();
  });

  it('keeps the page within its word budget with the group, in Plain and in Technical', async () => {
    mockPathology(listed({ id: 7, state: 'offered', openedAt: '2026-11-14T02:32:04Z' }));
    renderPage();
    await screen.findByRole('region', { name: PATHOLOGY_WORDS.title });
    await screen.findByRole('button', { name: 'Run S2' });
    const plain = layer1WordCount(document.body);
    expect(plain).toBeLessThanOrEqual(PLAIN_BUDGET);
    cleanup();
    resetMock();
    mockPathology(listed({ id: 7, state: 'offered', openedAt: '2026-11-14T02:32:04Z' }));
    renderPage('technical');
    await screen.findByRole('region', { name: PATHOLOGY_WORDS.title });
    await screen.findByRole('button', { name: 'Run S2' });
    expect(layer1WordCount(document.body)).toBeLessThanOrEqual(TECHNICAL_BUDGET);
  });
});
