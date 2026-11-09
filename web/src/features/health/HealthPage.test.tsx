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
import fixtures from '@/mocks/fixtures.json';
import { HealthGroup } from './HealthGroup';
import HealthPage from './HealthPage';
import { groupReport } from './report';
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

  it('is not ready when a stored credential no longer signs in, with the checks in their own open group', async () => {
    renderHealth({
      ...REPORT,
      interoperability: true,
      credentials_ok: false,
      credentials_state: 'stale',
      credentials_checked_at: '2026-11-03T10:00:00Z',
      credentials: [
        {
          namespace: 'SHUTTER',
          name: 'DownstreamAPI',
          user: 'downstream-api',
          status: 'refused',
          detail: 'downstream-api does not sign in with the stored password',
          ok: false,
        },
        {
          namespace: 'HOSPITAL',
          name: 'ShutterIntake',
          user: 'forwarder',
          status: 'ok',
          detail: 'forwarder signs in with the stored password',
          ok: true,
        },
      ],
    });
    const hero = await screen.findByRole('region', { name: 'Not ready' });
    expect(within(hero).getByRole('heading', { level: 2 })).toHaveTextContent(
      'Not ready: 1 core check fails.',
    );
    const checks = within(hero).getByRole('list', { name: 'Core checks' });
    expect(checks).toHaveTextContent('Stored credentials sign in: fails');
    expect(checks).toHaveTextContent('GET /health?refresh=1');
    const group = screen.getByRole('region', { name: 'Stored credentials' });
    expect(group).toHaveTextContent('0 of 1 pass');
    expect(
      within(group).getByRole('rowheader', { name: 'Stored credentials sign in' }).closest('tr'),
    ).toHaveTextContent('No');
    const refused = within(group).getByText('SHUTTER DownstreamAPI: refused');
    expect(refused.closest('[data-tech-detail="closed"]')).toBeNull();
    expect(refused.closest('tr')).toHaveAttribute('data-tone', 'blocking');
    expect(group).toHaveTextContent('HOSPITAL ShutterIntake: ok');
    expect(group).toHaveTextContent('downstream-api does not sign in with the stored password');
    expect(group).toHaveTextContent('stale');
    // The checks are no longer among the fields no group names
    expect(screen.queryByRole('region', { name: 'Other' })).toBeNull();
  });

  it('lists the checks first and the facts apart under Details, so a fact is never read as a failed check', async () => {
    renderHealth({
      ...REPORT,
      interoperability: true,
      production_state: 'running',
      shutter_production: 'Shutter.Production',
      adt_in: '/usr/irissys/mgr/shutter/in/',
      edition: 'aihub',
      missing_items: [],
      disabled_items: [],
    });
    const production = await screen.findByRole('region', { name: 'Production' });
    const tables = within(production).getAllByRole('table');
    expect(tables).toHaveLength(2);
    const [checks, details] = tables;
    expect(
      within(checks)
        .getAllByRole('rowheader')
        .map((h) => h.textContent),
    ).toEqual(['Interoperability enabled in the namespace', 'Production class compiled', 'Production state']);
    expect(within(production).getByRole('heading', { level: 3, name: 'Details' })).toBeInTheDocument();
    expect(details).toHaveAccessibleName('Details');
    expect(
      within(details)
        .getAllByRole('rowheader')
        .map((h) => h.textContent),
    ).toEqual(["Shutter's production", 'ADT inbound folder', 'Edition', 'Missing items', 'Disabled items']);
    // The checks come first; a detail is its label and value, with no mark and no tone
    expect(checks.compareDocumentPosition(details) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    for (const tr of within(details).getAllByRole('row')) {
      expect(tr).toHaveAttribute('data-kind', 'detail');
      expect(tr).not.toHaveAttribute('data-tone');
      expect(tr.querySelector('th svg')).toBeNull();
    }
    for (const tr of within(checks).getAllByRole('row')) {
      expect(tr).toHaveAttribute('data-kind', 'check');
      expect(tr.querySelector('th svg')).not.toBeNull();
    }
    expect(within(details).getByRole('rowheader', { name: 'Missing items' }).closest('tr')).toHaveTextContent(
      'None',
    );
    // The count and the group link count the checks only
    expect(production).toHaveTextContent('3 of 3 pass');
    expect(
      within(screen.getByRole('navigation', { name: 'Groups' })).getByRole('button', {
        name: 'Production 3 of 3 pass',
      }),
    ).toBeInTheDocument();
  });

  it('shows an install item missing from the production in the Production group, not behind Other', async () => {
    renderHealth({ ...REPORT, interoperability: true, missing_items: ['Scenario Player'], edition: 'core' });
    await screen.findByRole('region', { name: 'Ready' });
    const production = screen.getByRole('region', { name: 'Production' });
    expect(production).toHaveTextContent('2 of 2 pass, 1 to fix');
    const missing = within(production).getByRole('rowheader', { name: 'Missing items' }).closest('tr')!;
    expect(missing).toHaveAttribute('data-tone', 'blocking');
    expect(missing).toHaveTextContent('Scenario Player');
    expect(missing).toHaveTextContent('Run the install again: these items are missing from the production.');
    expect(within(production).getByRole('rowheader', { name: 'Edition' }).closest('tr')).toHaveTextContent(
      'core',
    );
    expect(screen.queryByRole('region', { name: 'Other' })).toBeNull();
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

  it('tells the truth about a dead receiver in the hero, within the budget, with the recorded report behind it', async () => {
    const dead = {
      ...fixtures.health,
      receivers: [
        {
          name: 'Downstream Out',
          has_api: true,
          state: 'no_answer',
          at: '2026-11-06T14:02:09Z',
          http_status: 0,
          from: 'connector',
          last_answer_at: '2026-11-06T13:10:00Z',
          incident: 'I-000002',
        },
      ],
      receivers_ok: false,
      watched_ok: false,
      watched_namespaces: [
        {
          namespace: 'PAS',
          ok: false,
          problems: ['The alert intake Ens.Alert is disabled in PAS.Production: its failures open no case'],
        },
      ],
    };
    const plain = renderHealth(dead, 'plain');
    const hero = await screen.findByRole('region', { name: 'Needs a look' });
    expect(hero).toHaveTextContent(
      'Running, but a receiver is not answering and a watched namespace has a problem.',
    );
    expect(hero).toHaveTextContent('Downstream Out: no answer at 6 Nov 2026, 14:02 UTC.');
    expect(hero).toHaveTextContent('PAS: The alert intake Ens.Alert is disabled');
    expect(screen.queryByRole('region', { name: 'Ready' })).not.toBeInTheDocument();
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(plain.container).length).toBeLessThanOrEqual(PLAIN_BUDGET);
    plain.unmount();
    const technical = renderHealth(dead, 'technical');
    await screen.findByRole('region', { name: 'Needs a look' });
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(technical.container).length).toBeLessThanOrEqual(TECHNICAL_BUDGET);
  });

  it('holds the budget on the night a whole site is down, naming two and counting the rest', async () => {
    const down = {
      ...fixtures.health,
      receivers: ['Downstream', 'Records', 'Pharmacy', 'Radiology', 'Billing'].map((name, i) => ({
        name: `${name} Out`,
        has_api: true,
        state: 'no_answer',
        at: `2026-11-06T14:0${i}:09Z`,
        http_status: 0,
        from: 'connector',
        last_answer_at: '2026-11-06T13:10:00Z',
        incident: `I-00000${i + 1}`,
      })),
      receivers_ok: false,
      watched_ok: false,
      watched_namespaces: ['PAS', 'LAB', 'ORDERS'].map((namespace) => ({
        namespace,
        ok: false,
        problems: [
          `The alert intake Ens.Alert is disabled in ${namespace}.Production: its failures open no case`,
        ],
      })),
    };
    const plain = renderHealth(down, 'plain');
    const hero = await screen.findByRole('region', { name: 'Needs a look' });
    expect(hero).toHaveTextContent(
      'Running, but 5 receivers are not answering and 3 watched namespaces have a problem.',
    );
    const lines = within(hero).getByRole('list', { name: 'What needs a look' });
    expect(within(lines).getAllByRole('listitem')).toHaveLength(2);
    expect(hero).toHaveTextContent('and 6 more, in the Other group.');
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(plain.container).length).toBeLessThanOrEqual(PLAIN_BUDGET);
    plain.unmount();
    const technical = renderHealth(down, 'technical');
    await screen.findByRole('region', { name: 'Needs a look' });
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(technical.container).length).toBeLessThanOrEqual(TECHNICAL_BUDGET);
  });

  it('holds the budget with the longest problems a watched namespace can report', async () => {
    const long =
      '40 forwards refused in the last 72 hours, the last at 2026-11-06T14:02:09Z: those failures have no case. Search the event log for: Shutter did not take';
    const down = {
      ...fixtures.health,
      watched_ok: false,
      watched_namespaces: ['PAS', 'LAB', 'ORDERS'].map((namespace) => ({
        namespace,
        ok: false,
        problems: [long, 'Another'],
      })),
    };
    const plain = renderHealth(down, 'plain');
    await screen.findByRole('region', { name: 'Needs a look' });
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(plain.container).length).toBeLessThanOrEqual(PLAIN_BUDGET);
  });

  it('adds no first-layer words when the receivers answer', async () => {
    const well = { ...fixtures.health, receivers: [], receivers_ok: true, watched_ok: true };
    const before = renderHealth(fixtures.health as Record<string, unknown>, 'plain');
    await screen.findByText('3 specialist agents and the coordinator agent');
    const without = layer1Words(before.container).length;
    before.unmount();
    const after = renderHealth(well, 'plain');
    await screen.findByText('3 specialist agents and the coordinator agent');
    expect(layer1Words(after.container).length).toBe(without);
  });
});

describe("the trial's chip for a piece the recorded instance did not have", () => {
  beforeEach(() => resetMock('approver'));

  it('marks the row No with the chip, keeps its note in the group detail, and shows it when the keyboard reaches it', async () => {
    // The recording has AI Hub: a recording from an instance without it
    const report = { ...fixtures.health, ai_hub_present: false };
    const agents = groupReport(report, true).groups.find((g) => g.def.id === 'agents')!;
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
          <MemoryRouter>
            <HealthGroup group={agents} report={report} />
          </MemoryRouter>
        </QueryClientProvider>
      </MantineProvider>,
    );
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(within(await row('AI Hub runner compiled')).getByText('Yes')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'What the dashes mean' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Agents and AI Hub' })).toHaveTextContent(
      'AI Hub installed. This report is from the instance that served the cases',
    );
    const chip = within(hub).getByText('Not on the recorded instance').closest<HTMLElement>('[tabindex]')!;
    expect(chip).toHaveAttribute('tabindex', '0');
    act(() => chip.focus());
    expect(await screen.findByRole('tooltip')).toHaveTextContent(
      'This report is from the instance that served the cases',
    );
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
    expect(hero).toHaveTextContent(`version ${fixtures.health.version}`);
    expect(hero).toHaveTextContent('read 2 Nov 2026, 14:56 UTC');
    // The recorded instance had AI Hub and its runner: the agents badge says so, never "not needed"
    expect(within(hero).getByText('Agents run on IRIS AI Hub')).toBeInTheDocument();
    expect(hero).not.toHaveTextContent(/not needed/i);
    expect(
      screen.getByText(
        "This is the report of the instance the trial was recorded on. Parts it did not have say so. Its counts are that instance's whole store, more than this trial's cases or Evaluation's runs.",
      ),
    ).toBeInTheDocument();
  });

  it('says Yes for AI Hub and its runner, which the recorded instance had, with no chip', async () => {
    renderHealth();
    for (const name of ['AI Hub installed', 'AI Hub runner compiled']) {
      const r = await row(name);
      expect(within(r).getByText('Yes')).toBeInTheDocument();
      expect(r).not.toHaveTextContent('Not on the recorded instance');
    }
    const agents = screen.getByRole('region', { name: 'Agents and AI Hub' });
    expect(within(agents).queryByRole('button', { name: 'What the dashes mean' })).not.toBeInTheDocument();
    expect(screen.queryByText('Not on the recorded instance')).not.toBeInTheDocument();
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
      'Other',
    ]);
    const user = userEvent.setup();
    await user.click(within(nav).getByRole('button', { name: 'Web applications 3 of 3 pass' }));
    expect(screen.getByRole('heading', { level: 2, name: 'Web applications' })).toHaveFocus();
  });

  it('groups the rows, the Agents group with nothing missing and every other field one click away', async () => {
    renderHealth();
    const agents = await screen.findByRole('region', { name: 'Agents and AI Hub' });
    expect(agents).not.toHaveTextContent('not on the recorded instance');
    expect(within(agents).getByRole('rowheader', { name: 'Enabled agents' })).toBeInTheDocument();
    expect(
      within(agents).getByRole('rowheader', { name: 'Recorded agent runs' }).closest('tr'),
    ).toHaveTextContent(String(fixtures.health.recordings));
    // The fields no group names, in a data disclosure, closed in both modes
    const other = screen.getByRole('region', { name: 'Other' });
    expect(within(other).getByRole('button', { name: /^The report's other \d+ fields$/ })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(other).toHaveTextContent(fixtures.health.gate_policy_version);
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

  it('shows a group of facts as Details alone, and keeps every count to the checks', async () => {
    renderHealth();
    const install = await screen.findByRole('region', { name: 'Installation and licence' });
    expect(within(install).getAllByRole('table')).toHaveLength(1);
    expect(within(install).getByRole('table')).toHaveAccessibleName('Details');
    expect(
      within(install).getByRole('rowheader', { name: 'Demo installation' }).closest('tr'),
    ).toHaveTextContent('Yes');
    expect(install).not.toHaveTextContent(/\bpass\b/);
    // Production: its four checks, each ticked, then six facts; "4 of 4" counts the checks only
    const production = screen.getByRole('region', { name: 'Production' });
    const [checks, details] = within(production).getAllByRole('table');
    expect(within(checks).getAllByRole('row')).toHaveLength(4);
    expect(checks.querySelectorAll('th svg')).toHaveLength(4);
    expect(within(details).getAllByRole('row')).toHaveLength(6);
    expect(details.querySelector('th svg')).toBeNull();
    expect(production).toHaveTextContent('4 of 4 pass');
    // The Agents group: two checks, then the counts and the board
    const agents = screen.getByRole('region', { name: 'Agents and AI Hub' });
    const [hub, counts] = within(agents).getAllByRole('table');
    expect(
      within(hub)
        .getAllByRole('rowheader')
        .map((h) => h.textContent),
    ).toEqual(['AI Hub installed', 'AI Hub runner compiled']);
    expect(
      within(counts)
        .getAllByRole('rowheader')
        .map((h) => h.textContent),
    ).toEqual(['Enabled agents', 'Default board', 'Recorded agent runs', 'API mimic setting']);
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
    expect(list).toHaveTextContent(
      "Recorded from Shutter's REST API on an instance with IRIS AI Hub at 2 Nov 2026, 14:56 UTC",
    );
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
