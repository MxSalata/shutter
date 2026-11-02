import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import HealthPage from './HealthPage';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';

// The page reads TRIAL when it renders, so each test can say whether it is the trial
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

/** A report with a Yes, a No the trial explains, a core No it does not, and a value the report left out. */
const REPORT = {
  production_class: true,
  ai_hub_present: false,
  interoperability: false,
  adt_in: null,
};

/** The report the trial serves: the recorded instance's, with the text that says where it came from. */
const RECORDED = { recorded: fixtures.source, ...fixtures.health };

function renderHealth(report: Record<string, unknown> = REPORT, detail: 'plain' | 'technical' = 'plain') {
  server.use(http.get('/api/shutter/health', () => HttpResponse.json(report)));
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

describe('HealthPage', () => {
  beforeEach(() => resetMock('approver'));

  it('writes Yes, No or Not reported in every row, and says nothing of the trial outside it', async () => {
    demo.on = false;
    renderHealth();
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
    demo.on = false;
    renderHealth();
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

  it('says in the trial that a piece the recorded instance did not have is No, with a chip, and only for those pieces', async () => {
    demo.on = true;
    renderHealth();
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(within(hub).getByText('Not on the recorded instance')).toBeInTheDocument();
    const interop = await row('Interoperability enabled in the namespace');
    expect(interop).not.toHaveTextContent('Not on the recorded instance');
    expect(
      screen.getByText(
        'This is the report of the instance the trial was recorded on. Parts it did not have say so.',
      ),
    ).toBeInTheDocument();
    // The full note is in the group's detail, for touch, and in the chip's tooltip, which the browser test opens (a
    // Mantine tooltip takes over a minute to open in jsdom)
    const agents = screen.getByRole('region', { name: 'Agents and AI Hub' });
    expect(within(agents).getByRole('button', { name: 'Why they are missing' })).toBeInTheDocument();
    expect(agents).toHaveTextContent(
      'AI Hub installed. This report is from the instance that served the cases',
    );
    const chip = within(hub).getByText('Not on the recorded instance');
    expect(chip.closest('[tabindex]')).toHaveAttribute('tabindex', '0');
  });

  describe('on the report the trial serves', () => {
    beforeEach(() => {
      demo.on = true;
    });

    it('opens as a recording: the verdict in the past tense, what it was read from and when', async () => {
      renderHealth(RECORDED);
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
    });

    it('is one line of links to the groups, each with its count, that move focus to the heading', async () => {
      renderHealth(RECORDED);
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
      renderHealth(RECORDED);
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
      renderHealth(RECORDED);
      const install = await screen.findByRole('region', { name: 'Installation and licence' });
      expect(within(install).getByRole('rowheader', { name: 'Licence' }).closest('tr')).toHaveTextContent(
        'Concurrent User licence: 1 unit consumed, 7 available, up to 25 connections',
      );
      expect(within(install).getByRole('button', { name: 'Licence fields' })).toBeInTheDocument();
      expect(install).toHaveTextContent('units_consumed');
    });

    it('keeps the provenance and the API response behind disclosures named for what they hold', async () => {
      renderHealth(RECORDED);
      const provenance = await screen.findByRole('button', { name: 'Where this report comes from' });
      expect(provenance).toHaveAttribute('aria-expanded', 'false');
      const list = document.getElementById(provenance.getAttribute('aria-controls')!)!;
      expect(list.querySelectorAll('li').length).toBeGreaterThanOrEqual(5);
      expect(list).toHaveTextContent("Recorded from Shutter's REST API at 20 Oct 2026, 17:55 UTC");
      const api = screen.getByRole('button', { name: 'The report as the API sends it' });
      expect(api).toHaveAttribute('aria-expanded', 'false');
      // The provenance is never a row
      expect(document.querySelector('.health-rows')?.textContent).not.toContain('REST API at');
      for (const table of document.querySelectorAll('.health-rows'))
        expect(table.textContent).not.toContain("Recorded from Shutter's REST API");
    });

    it('says nothing is "live" in the first layer', async () => {
      renderHealth(RECORDED);
      await screen.findByRole('region', { name: 'Ready' });
      expect(layer1Words(document.body).join(' ')).not.toMatch(/\blive\b/i);
    });
  });

  describe('its word budget', () => {
    /** The first layer without the endpoint's own JSON, which "The report as the API sends it" opens in Technical. */
    function words(container: HTMLElement) {
      const copy = container.cloneNode(true) as HTMLElement;
      copy.querySelectorAll('.json-block').forEach((el) => el.remove());
      return layer1Words(copy);
    }

    it('stays within the budget on the trial report in Plain, and Technical within one and a half times', async () => {
      demo.on = true;
      const plain = renderHealth(RECORDED, 'plain');
      await screen.findByRole('region', { name: 'Ready' });
      await screen.findByText('3 specialist agents and the coordinator agent');
      const inPlain = words(plain.container).length;
      plain.unmount();
      const technical = renderHealth(RECORDED, 'technical');
      await screen.findByRole('region', { name: 'Ready' });
      await screen.findByText('3 specialist agents and the coordinator agent');
      const inTechnical = words(technical.container).length;
      console.info(`Health words: ${inPlain} in Plain, ${inTechnical} in Technical`);
      expect(inPlain).toBeLessThanOrEqual(PLAIN_BUDGET);
      expect(inTechnical).toBeLessThanOrEqual(TECHNICAL_BUDGET);
      expect(inTechnical).toBeGreaterThanOrEqual(inPlain);
    });
  });
});
