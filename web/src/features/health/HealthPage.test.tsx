import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { chooseTransport, resetTransportForTests } from '@/api/transport';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import { createTrialTransport } from '@/trial/transport';
import HealthPage from './HealthPage';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';

// The page reads TRIAL when it renders, so each block can say whether it is the trial. The live tests answer a report
// of their own through msw; the trial's tests run the trial's real path, its transport answering the recorded report.
const demo = vi.hoisted(() => ({ on: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return demo.on;
  },
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/** A live report with a Yes, a No, a core No that the trial would not explain, and a value the report left out. */
const REPORT = {
  production_class: true,
  ai_hub_present: false,
  interoperability: false,
  adt_in: null,
};

/**
 * Renders the page. A live test gives the report msw answers; the trial's tests give none, and the trial's transport
 * answers with the recorded report.
 */
function renderHealth(report?: Record<string, unknown>, detail: 'plain' | 'technical' = 'plain') {
  if (report) server.use(http.get('/api/shutter/health', () => HttpResponse.json(report)));
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <HealthPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The report's row for a check, by its name in words. */
async function row(name: string) {
  return (await screen.findByRole('rowheader', { name })).closest('tr')!;
}

describe('HealthPage on a live system', () => {
  beforeEach(() => {
    demo.on = false;
    resetMock('approver');
  });

  it('writes Yes, No or Not reported in every row, and says nothing of the trial', async () => {
    renderHealth(REPORT);
    expect(within(await row('Production class compiled')).getByText('Yes')).toBeInTheDocument();
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(hub).not.toHaveTextContent('Not on the recorded instance');
    const interop = await row('Interoperability enabled in the namespace');
    expect(within(interop).getByText('No')).toBeInTheDocument();
    expect(interop).toHaveTextContent('Enable Interoperability in the namespace, then reload.');
    expect(within(await row('ADT inbound folder')).getByText('Not reported')).toBeInTheDocument();
    expect(screen.queryByText(/This is the report of the instance the trial was recorded on/)).toBeNull();
  });

  it('opens on the verdict: not ready, naming the failing check and what to do', async () => {
    renderHealth(REPORT);
    const hero = await screen.findByRole('region', { name: 'Not ready' });
    expect(within(hero).getByRole('heading', { level: 2 })).toHaveTextContent(
      'Not ready: 1 core check fails.',
    );
    const checks = within(hero).getByRole('list', { name: 'Core checks' });
    expect(checks).toHaveTextContent('Interoperability on: fails');
    expect(checks).toHaveTextContent('Enable Interoperability in the namespace, then reload.');
    expect(checks).toHaveTextContent('Production compiled: passes');
    // The agents badge says where the agents run, apart from the verdict
    expect(
      within(hero).getByText('Agents replay recordings; running them needs IRIS AI Hub'),
    ).toBeInTheDocument();
  });

  it('words the model budget per reset on the public demo and by the day elsewhere, in the Other group', async () => {
    const budget = { dailyUsd: 5, spentTodayUsd: 1.5, exhausted: false };
    const view = renderHealth({ ...REPORT, budget });
    expect(await screen.findByRole('region', { name: 'Other' })).toHaveTextContent(
      "$1.50 of today's $5.00 spent on live runs",
    );
    view.unmount();
    renderHealth({ ...REPORT, budget, live: { enabled: true } });
    const other = await screen.findByRole('region', { name: 'Other' });
    expect(other).toHaveTextContent('$1.50 of the $5.00 per reset spent on live runs');
    expect(other).toHaveTextContent('since the demo last reset (every hour)');
    expect(other).not.toHaveTextContent(/today/i);
  });
});

describe('HealthPage in the trial', () => {
  /** The trial never sends a call: its transport answers from the recording in the browser. */
  const sent = vi.fn(() => Promise.reject(new Error('fetch was called from the trial')));

  beforeAll(() => {
    demo.on = true;
    vi.stubGlobal('fetch', sent);
    resetTransportForTests();
    chooseTransport(createTrialTransport('approver'));
  });
  afterEach(() => {
    expect(sent).not.toHaveBeenCalled();
  });
  afterAll(() => {
    vi.unstubAllGlobals();
    resetTransportForTests();
    demo.on = false;
  });

  it('opens as a recording: the verdict in the past tense, what it was read from and when', async () => {
    renderHealth();
    const hero = await screen.findByRole('region', { name: 'Ready' });
    expect(within(hero).getByRole('heading', { level: 2 })).toHaveTextContent(
      'The recorded instance was ready: its message engine was running and every core check passed (7 of 7).',
    );
    expect(within(hero).getByRole('list', { name: 'Core checks' }).children).toHaveLength(7);
    expect(hero).toHaveTextContent('Shutter.Production');
    expect(hero).toHaveTextContent('SHUTTER');
    expect(hero).toHaveTextContent('version 0.1.0');
    expect(hero).toHaveTextContent('read 20 Oct 2026, 17:55 UTC');
    // The agents badge names IRIS AI Hub and the build, never "not needed"
    expect(
      within(hero).getByText('Board runs recorded on IRIS AI Hub (build 154); replayed here'),
    ).toBeInTheDocument();
    expect(hero).not.toHaveTextContent(/not needed/i);
    expect(
      screen.getByText(
        'This is the report of the instance the trial was recorded on. Parts it did not have say so.',
      ),
    ).toBeInTheDocument();
  });

  it('says that a piece the recorded instance did not have is No, with a chip, and only for those pieces', async () => {
    renderHealth();
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(within(hub).getByText('Not on the recorded instance')).toBeInTheDocument();
    const interop = await row('Interoperability enabled in the namespace');
    expect(within(interop).getByText('Yes')).toBeInTheDocument();
    expect(interop).not.toHaveTextContent('Not on the recorded instance');
    // The full note is in the group's detail, for touch, and in the chip's tooltip, which the foundation's hint opens
    // on hover, focus and tap
    const agents = screen.getByRole('region', { name: 'Agents and AI Hub' });
    expect(within(agents).getByRole('button', { name: 'Why they are missing' })).toBeInTheDocument();
    expect(agents).toHaveTextContent(
      'AI Hub installed. This report is from the instance that served the cases',
    );
    const chip = within(hub).getByText('Not on the recorded instance');
    expect(chip.closest('[tabindex]')).toHaveAttribute('tabindex', '0');
  });

  it("shows the chip's note when the keyboard reaches it", async () => {
    renderHealth();
    const hub = await row('AI Hub installed');
    const chip = within(hub).getByText('Not on the recorded instance').closest<HTMLElement>('[tabindex]')!;
    act(() => chip.focus());
    expect(await screen.findByRole('tooltip')).toHaveTextContent(
      'This report is from the instance that served the cases',
    );
  });

  it('is one line of links to the groups, each with its count, that move focus to the heading', async () => {
    renderHealth();
    const nav = await screen.findByRole('navigation', { name: 'Groups' });
    const links = within(nav).getAllByRole('button');
    expect(links.map((l) => l.textContent?.replace(/\s+/g, ' '))).toEqual([
      'Production 4 of 4 pass',
      'Web applications 3 of 3 pass',
      'Agents and AI Hub',
      'Cases and housekeeping',
      'Installation and licence',
    ]);
    const user = userEvent.setup();
    await user.click(within(nav).getByRole('button', { name: 'Web applications 3 of 3 pass' }));
    expect(screen.getByRole('heading', { level: 2, name: 'Web applications' })).toHaveFocus();
  });

  it('groups the rows, with the Agents group saying where the runs were recorded', async () => {
    renderHealth();
    const agents = await screen.findByRole('region', { name: 'Agents and AI Hub' });
    expect(agents).toHaveTextContent(
      "The agents' runs were recorded on IRIS AI Hub; this report's instance replays them.",
    );
    expect(agents).toHaveTextContent('2 not on the recorded instance');
    expect(within(agents).getAllByText('Not on the recorded instance')).toHaveLength(2);
    expect(within(agents).getByRole('rowheader', { name: 'Enabled agents' })).toBeInTheDocument();
    const production = screen.getByRole('region', { name: 'Production' });
    expect(production).toHaveTextContent('4 of 4 pass');
    const rowOf = (name: string) => within(production).getByRole('rowheader', { name }).closest('tr')!;
    expect(rowOf('Production class compiled')).toHaveTextContent('Yes');
    expect(rowOf('Production state')).toHaveTextContent('running');
    expect(rowOf("Shutter's production")).toHaveTextContent('Shutter.Production');
    expect(rowOf('ADT inbound folder')).toHaveTextContent('/usr/irissys/mgr/shutter/in/');
    // The default board comes from the agent library
    await waitFor(() =>
      expect(
        within(agents).getByRole('rowheader', { name: 'Default board' }).closest('tr'),
      ).toHaveTextContent('3 specialist agents and the coordinator agent'),
    );
  });

  it('writes the licence as one sentence, with its raw fields in the group detail', async () => {
    renderHealth();
    const install = await screen.findByRole('region', { name: 'Installation and licence' });
    expect(within(install).getByRole('rowheader', { name: 'Licence' }).closest('tr')).toHaveTextContent(
      'Concurrent User licence: 1 unit consumed, 7 available, up to 25 connections',
    );
    expect(within(install).getByRole('button', { name: 'Licence fields' })).toBeInTheDocument();
    expect(install).toHaveTextContent('units_consumed');
  });

  it('keeps the provenance and the API response behind disclosures named for what they hold', async () => {
    renderHealth();
    const provenance = await screen.findByRole('button', { name: 'Where this report comes from' });
    expect(provenance).toHaveAttribute('aria-expanded', 'false');
    const list = document.getElementById(provenance.getAttribute('aria-controls')!)!;
    expect(list.querySelectorAll('li').length).toBeGreaterThanOrEqual(5);
    expect(list).toHaveTextContent("Recorded from Shutter's REST API at 20 Oct 2026, 17:55 UTC");
    const api = screen.getByRole('button', { name: 'The report as the API sends it' });
    expect(api).toHaveAttribute('aria-expanded', 'false');
    // The provenance is never a row
    for (const table of document.querySelectorAll('.health-rows'))
      expect(table.textContent).not.toContain("Recorded from Shutter's REST API");
  });

  it('says nothing is "live" in the first layer', async () => {
    renderHealth();
    await screen.findByRole('region', { name: 'Ready' });
    expect(layer1Words(document.body).join(' ')).not.toMatch(/\blive\b/i);
  });

  it('stays within the word budget in Plain, and Technical within one and a half times', async () => {
    const plain = renderHealth(undefined, 'plain');
    await screen.findByRole('region', { name: 'Ready' });
    await screen.findByText('3 specialist agents and the coordinator agent');
    const inPlain = layer1Words(plain.container).length;
    plain.unmount();
    const technical = renderHealth(undefined, 'technical');
    await screen.findByRole('region', { name: 'Ready' });
    await screen.findByText('3 specialist agents and the coordinator agent');
    const inTechnical = layer1Words(technical.container).length;
    console.info(`Health words: ${inPlain} in Plain, ${inTechnical} in Technical`);
    expect(inPlain).toBeLessThanOrEqual(PLAIN_BUDGET);
    expect(inTechnical).toBeLessThanOrEqual(TECHNICAL_BUDGET);
    expect(inTechnical).toBeGreaterThanOrEqual(inPlain);
  });
});
