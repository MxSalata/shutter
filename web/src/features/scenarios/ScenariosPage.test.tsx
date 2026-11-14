import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter, useLocation } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import type { CaseSummary, Scenario } from '@/api/types';
import { server } from '@/mocks/node';
import { recordedSiteProfile } from '@/mocks/profile';
import { LOOK_ONLY_DEMO, resetMock, writesOf } from '@/mocks/handlers';
import type { CaseFixture } from '@/mocks/hold';
import { caseOutcome } from '@/lib/status';
import { PROOF } from '@/lib/proof';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
import { ROUTE } from './execution';
import { SCENARIOS_LEAD } from './scenarioText';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';
import definitions from '../../../../fixtures/scenarios.json';
import recording from '@/mocks/fixtures.json';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderScenarios(detail: DetailLevel = 'plain') {
  useAppearance.setState({ detail });
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

/** The address's query as the router has it, for a test of what a page leaves in it. */
function Address() {
  return (
    <span data-testid="address" hidden>
      {useLocation().search}
    </span>
  );
}
const address = () => screen.getByTestId('address').textContent;

/** The page at an address, with the address in reach of the test. */
function renderAt(entry: string) {
  useAppearance.setState({ detail: 'plain' });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={[entry]}>
          <Address />
          <ScenariosPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** A scenario's row in the list, found by its Run button. */
async function card(id: string) {
  const run = await screen.findByRole('button', { name: `Run ${id}` });
  return run.closest<HTMLElement>('tr')!;
}

const scenarioDefs = definitions as unknown as Scenario[];
/** The scenarios the mock lists: the recording's, with their definitions. */
const listed = scenarioDefs.filter((d) => recording.scenarios.some((s) => s.id === d.id));
/** A recorded case's summary, as the list sends it: with the writes and the verification the mock counts. */
function summaryOf(id: string): CaseSummary {
  const c = (recording.cases as unknown as Record<string, CaseFixture>)[id];
  return { ...(c.summary as unknown as CaseSummary), ...writesOf(c) };
}
/** A scenario's newest recorded case, as the instance's list named it when the trial was recorded. */
function recordedLatest(id: string) {
  const newest = Object.values(recording.cases as unknown as Record<string, CaseFixture>)
    .map((c) => c.summary as unknown as CaseSummary)
    .filter((c) => c.scenario === id)
    .sort((a, b) => b.openedAt.localeCompare(a.openedAt) || b.caseId.localeCompare(a.caseId))[0];
  return newest
    ? {
        caseId: newest.caseId,
        state: newest.state,
        disposition: newest.disposition,
        headline: newest.headline,
      }
    : null;
}
/** The recorded scenario list with one scenario's latest case replaced. */
function withLatest(id: string, caseId: string) {
  const c = summaryOf(caseId);
  return http.get('/api/shutter/scenarios', () =>
    HttpResponse.json({
      scenarios: listed.map((d) => ({
        ...d,
        latestCase:
          d.id === id
            ? { caseId, state: c.state, disposition: c.disposition, headline: c.headline }
            : recordedLatest(d.id),
      })),
      run: null,
    }),
  );
}

describe('ScenariosPage', () => {
  beforeEach(() => resetMock('approver'));

  it('offers every mode outside the demo', async () => {
    renderScenarios();
    expect(await screen.findByRole('radio', { name: 'Single investigator' })).toBeEnabled();
  });

  it('lists every scenario under a heading of its own, each row headed by its scenario', async () => {
    renderScenarios();
    const run = await screen.findByRole('button', { name: 'Run S2' });
    const list = screen.getByRole('region', { name: 'Every scenario' });
    expect(list).toContainElement(run);
    const row = run.closest('tr')!;
    expect(within(row).getByRole('rowheader')).toHaveTextContent(/^S2Never-accepted transfer/);
    expect(within(list).getAllByRole('button', { name: /^Run S\d+[a-z]?$/ })).toHaveLength(listed.length);
    expect(within(list).getByText(`${listed.length} in all.`, { exact: false })).toBeInTheDocument();
  });

  it('keeps the one sentence and the six steps every case goes through behind What a scenario does', async () => {
    renderScenarios();
    await userEvent.click(await screen.findByRole('button', { name: 'What a scenario does' }));
    expect(
      await screen.findByRole('heading', {
        name: 'Shutter resends a failed HL7 delivery only when its checks pass. Otherwise it stops and names the patient.',
      }),
    ).toBeInTheDocument();
    const steps = screen.getByRole('list', { name: 'What happens to every case' });
    expect(
      within(steps)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['1Open case', '2Evidence', '3Board plan', '4Gate checks', '5Release', '6Verify']);
  });

  it('offers the short route first, S2, S3 and S8 in Board, in that order, with what you will see and its latest case', async () => {
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    for (const id of ['S2', 'S3', 'S8'])
      expect(await within(first).findByRole('button', { name: `Run ${id} in Board mode` })).toBeEnabled();
    expect(within(first).getAllByText('You will see')).toHaveLength(3);
    // The three are the route, in order, each card saying its place; S20 is not one of them
    const cards = [...first.querySelectorAll<HTMLElement>('.first-card')];
    expect(cards.map((c) => c.dataset.first)).toEqual([...ROUTE]);
    expect(ROUTE).toEqual(['S2', 'S3', 'S8']);
    expect(cards[0]).toHaveTextContent(/^1 of 3 · S2 ·Board/);
    expect(cards[2]).toHaveTextContent(/^3 of 3 · S8 ·Board/);
    expect(within(first).getByText('A short route, in this order.')).toBeInTheDocument();
    // S20 stays, as the optional approval-boundary card under the three, with its own Run in its own mode
    const optional = first.querySelector<HTMLElement>('.first-optional[data-first="S20"]')!;
    expect(optional).toHaveTextContent(/^Optional · S20 ·Rules only/);
    expect(
      within(optional).getByRole('heading', { name: 'The approval boundary: the gate stops a write' }),
    ).toBeInTheDocument();
    expect(within(optional).getByRole('button', { name: 'Run S20 in Rules only mode' })).toBeEnabled();
    const s3 = await within(first).findByRole('link', { name: /the latest S3 case in Board mode$/ });
    expect(s3).toHaveAttribute('href', '/cases/C-000003');
    // The latest case in the scenario's own mode, found among the cases, never written in
    const s20 = await within(first).findByRole('link', {
      name: /^Open C-\d+, the latest S20 case in Rules only mode$/,
    });
    expect(s20).toHaveAttribute('href', '/cases/C-000053');
    const s8 = await within(first).findByRole('link', { name: /the latest S8 case in Board mode$/ });
    expect(s8).toHaveAttribute('href', '/cases/C-000008');
  });

  it("says what you will see only as the scenarios' definitions and the recorded case have it", async () => {
    const def = (id: string) =>
      scenarioDefs.find((d) => d.id === id)!.expected as Scenario['expected'] & {
        final_reason?: string;
      };
    // S2: one conditional resend, a write
    expect(def('S2')).toMatchObject({ disposition: 'resend', write: true });
    // S3: reconciled from the receiver's receipt, nothing written
    expect(def('S3')).toMatchObject({ disposition: 'reconcile', write: false });
    expect(scenarioDefs.find((d) => d.id === 'S3')!.summary).toMatch(/its acknowledgement is lost/);
    // S8: escalated to a person, nothing written
    expect(def('S8')).toMatchObject({ disposition: 'escalate', write: false });
    // S20, played in rules mode: the approval bound to the receiver's version stops holding, the later move
    // supersedes the resend, nothing is written
    expect(def('S20')).toMatchObject({
      write: false,
      blocked_by: 'APPROVAL_RECEIVER_CHANGED',
      final_reason: 'SUPERSEDED_BY_LATER_EVENT',
      modes: ['rules'],
    });
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    // The catalogue entry S8 cites comes from its latest board case's plan, not from the page
    const cases = recording.cases as unknown as Record<
      string,
      { plan: { plan: { catalogueEntry?: string } } }
    >;
    const entry = cases['C-000008'].plan.plan.catalogueEntry!;
    expect(entry).toBe('E7');
    expect(
      await within(first).findByText(`citing catalogue entry ${entry},`, { exact: false }),
    ).toBeInTheDocument();
    expect(
      within(first).getByText(
        "Only the acknowledgement was lost: the receiver's receipt shows the transfer applied. The case is reconciled, and nothing is written.",
      ),
    ).toBeInTheDocument();
    // Why it matters, on the card: the evidence cannot order the two movements, so the board withholds the write
    expect(
      within(first).getByText(
        /^Two movements have the same recorded time, so the board withholds the resend\./,
      ),
    ).toBeInTheDocument();
  });

  it("keeps the guide's first target while the scenarios load, and when they cannot be read", async () => {
    server.use(http.get('*/scenarios', () => HttpResponse.json({ error: 'down' }, { status: 503 })));
    renderScenarios();
    const first = screen.getByRole('region', { name: 'Try these three first' });
    expect(first).toHaveAttribute('data-tour', 'scenarios');
    expect(within(first).getByText('Loading the scenarios…')).toBeInTheDocument();
    expect(
      await within(first).findByText(
        'The scenarios could not be read, so these three cannot be offered yet.',
      ),
    ).toBeInTheDocument();
  });

  it("shows every mode's own description in its card, in view without choosing the mode", async () => {
    renderScenarios();
    const modes = await screen.findByRole('radiogroup', { name: 'Run mode' });
    await screen.findByRole('button', { name: 'Run S2' });
    // The approved words, each inside its own card: none waits for its mode to be chosen, and none is hover-only
    const words: Record<string, string> = {
      Board:
        "Four AI Hub agents. Three specialists read the sealed evidence at once, each from one angle: the message, the encounter's history, the impact on the receiver. A coordinator weighs their findings and proposes one plan, with reasons.",
      'Site policy':
        "How a hospital would run it. Failures the catalogue recognises are settled by the site's written policy, with no model; anything it doesn't recognise goes to the board.",
      'Single investigator':
        'One AI Hub agent with the same evidence and tools proposes the plan alone, to compare with the board. Live only, so not in the trial.',
      'Rules only':
        'No agents: the baseline. Shutter resends the message unchanged unless the gate objects, as a plain Resend would. In S8 one gate check is lifted on purpose, to show what that writes.',
    };
    for (const [name, text] of Object.entries(words)) {
      const radio = within(modes).getByRole('radio', { name });
      const said = within(radio).getByText(text);
      expect(said).toBeVisible();
      expect(said.closest('.mantine-VisuallyHidden-root, [aria-hidden="true"], [hidden]')).toBeNull();
    }
    expect(
      screen.getByText(
        "Every Run button below uses it. The mode decides who proposes the plan. In every mode the same gate checks the plan, and a person or the site's policy releases any write.",
      ),
    ).toBeInTheDocument();
    // No line under the cards speaks for the chosen mode alone any more
    expect(document.querySelector('[data-mode-hint]')).toBeNull();
    await userEvent.click(within(modes).getByRole('radio', { name: 'Rules only' }));
    for (const text of Object.values(words)) expect(within(modes).getByText(text)).toBeVisible();
  });

  it('says how a run executes apart from who proposes, and promises no live run before its case says what ran', async () => {
    renderScenarios();
    await screen.findByRole('button', { name: 'Run S2' });
    const how = screen.getByRole('region', { name: 'How a run executes here' });
    expect(how).toHaveTextContent(
      'The mode says who proposes the plan, not how a run executes. From this sign-in the agents run as this install is set. Each case then says what ran: Live model only when a model was called, Recorded replay when its agents answered from their recordings.',
    );
    // Nothing here calls the page or the sign-in live, or a recording
    expect(within(how).queryByText('Browser recording')).not.toBeInTheDocument();
    expect(within(how).queryByText('Recorded replay')).not.toBeInTheDocument();
    expect(within(how).queryByText('Live model')).not.toBeInTheDocument();
  });

  it('counts the scenarios each mode plays, and the list by outcome, from the list itself', async () => {
    renderScenarios();
    const rules = await screen.findByRole('radio', { name: 'Rules only' });
    await screen.findByRole('button', { name: 'Run S2' });
    const inRules = listed.filter((d) => !d.expected?.modes || d.expected.modes.includes('rules')).length;
    expect(rules).toHaveAccessibleDescription(
      new RegExp(`Plays ${inRules} of the ${listed.length} scenarios$`),
    );
    const list = screen.getByRole('region', { name: 'Every scenario' });
    await within(list).findByRole('button', { name: 'Run S2' });
    const resends = listed.filter((d) => !d.expected?.incident && d.expected?.disposition === 'resend');
    const chip = within(list).getByRole('radio', { name: `Resend ${resends.length}` });
    await userEvent.click(chip);
    const runs = within(list).getAllByRole('button', { name: /^Run S\d+[a-z]?$/ });
    expect(runs.map((b) => b.getAttribute('aria-label'))).toEqual(resends.map((d) => `Run ${d.id}`));
    const incidents = listed.filter((d) => d.expected?.incident).length;
    expect(within(list).getByRole('radio', { name: `Incident chains ${incidents}` })).toBeInTheDocument();
    expect(within(list).queryByText(/illustrative/i)).not.toBeInTheDocument();
  });

  it('shows no guided path outside the demo: an instance has its own cases', async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Then follow this path' })).not.toBeInTheDocument();
  });

  it('leads with the induction prompt on an instance running the shipped profile', async () => {
    const view = recordedSiteProfile()!;
    server.use(
      http.get('/api/shutter/site-profile', () =>
        HttpResponse.json({ ...view, source: view.source.replace(' (demo)', '') }),
      ),
    );
    renderScenarios();
    const prompt = await screen.findByText('Shutter is running on the shipped site profile');
    const heading = screen.getByRole('heading', { name: 'Scenarios' });
    expect(prompt.compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("calls the demo's answers the demo's, as the site profile does, not the shipped profile", async () => {
    renderScenarios();
    expect(await screen.findByText("Shutter is running on the demo's answers")).toBeInTheDocument();
    expect(screen.queryByText('Shutter is running on the shipped site profile')).not.toBeInTheDocument();
  });

  it("marks a scenario a mode doesn't play, at full contrast, and says which modes it is", async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S7' })).toBeEnabled();
    await userEvent.click(screen.getByRole('radio', { name: 'Site policy' }));
    const s7 = await card('S7');
    expect(within(s7).getByRole('button', { name: 'Run S7' })).toBeDisabled();
    expect(within(s7).getByText('Not in Site policy mode')).toBeInTheDocument();
    expect(within(s7).getByText('Its modes: Board, Single investigator, Rules only.')).toBeInTheDocument();
    // The row itself is not dimmed: it reads as a scenario this mode leaves out, not as a broken one
    expect(s7.style.background).toBe('');
    expect(within(await card('S2')).getByRole('button', { name: 'Run S2' })).toBeEnabled();
    expect(within(await card('S2')).queryByText(/^Not in /)).not.toBeInTheDocument();
  });

  it("shows a mode's own expected outcome: S21's resend that the gate blocks, in Rules only mode only", async () => {
    const s21 = scenarioDefs.find((d) => d.id === 'S21')!;
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
    // The code the gate stops on is a code beside its words, not a red badge
    const code = within(s).getByText('EVENT_TIME_IMPLAUSIBLE');
    expect(code.tagName).toBe('CODE');
    expect(code.closest('.mantine-Badge-root')).toBeNull();
    expect(within(s).getByText('Stops on')).toBeInTheDocument();
    expect(within(s).getByText('Nothing written')).toBeInTheDocument();
  });

  it("keeps Run off while the last run's case is still working, and on once it waits on a person", async () => {
    const s2 = scenarioDefs.find((d) => d.id === 'S2')!;
    const run = { scenario: 'S2', mode: 'rules', startedAt: '', state: 'done', files: [], timeouts: [] };
    const latest = { caseId: 'C-000055', disposition: '', headline: '' };
    let state = 'investigating';
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({ scenarios: [{ ...s2, latestCase: { ...latest, state } }], run }),
      ),
    );
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeEnabled();
    state = 'awaiting_approval';
    await waitFor(() => expect(screen.getByRole('button', { name: 'Run S2' })).toBeEnabled(), {
      timeout: 5_000,
    });
  });

  it("links each receiver's case of a scenario that opens one per receiver, beside its latest", async () => {
    const s22 = scenarioDefs.find((d) => d.id === 'S22')!;
    const s2 = scenarioDefs.find((d) => d.id === 'S2')!;
    const latest = { caseId: 'C-000055', state: 'escalated', disposition: 'escalate', headline: '' };
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({
          scenarios: [
            { ...s22, latestCase: latest },
            { ...s2, latestCase: { ...latest, caseId: 'C-000002' } },
          ],
          run: null,
        }),
      ),
    );
    renderScenarios();
    await userEvent.click(await screen.findByRole('radio', { name: 'Site policy' }));
    const row = await card('S22');
    expect(within(row).getByRole('link', { name: 'C-000055' })).toBeInTheDocument();
    expect(within(row).getByRole('link', { name: "Each receiver's case for S22" })).toHaveAttribute(
      'href',
      '/cases?scenario=S22',
    );
    expect(within(await card('S2')).queryByRole('link', { name: /Each receiver/ })).not.toBeInTheDocument();
  });

  it('says how many encounters an incident scenario opens and the writes their chains make in all', async () => {
    renderScenarios();
    for (const id of ['S11', 'S12']) {
      const def = scenarioDefs.find((d) => d.id === id)!;
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
    const runs = screen.getAllByRole('button', { name: /^Run S\d+[a-z]?$/ });
    expect(runs.length).toBeGreaterThan(1);
    for (const run of runs) expect(run).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeDisabled();
    expect(screen.queryByRole('radio', { name: 'Board' })).not.toBeInTheDocument();
    // No row is marked for a mode when there is no mode to play in
    expect(screen.queryByText(/^Not in .+ mode$/)).not.toBeInTheDocument();
    // Nothing to try and nothing to play into: the list stands as reference, under the notice
    expect(screen.queryByRole('region', { name: 'Try these three first' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Three to look at first' })).not.toBeInTheDocument();
    expect(screen.queryByText('You will see')).not.toBeInTheDocument();
    expect(screen.getByText(SCENARIOS_LEAD.lookOnly)).toBeInTheDocument();
    expect(screen.queryByText(SCENARIOS_LEAD.live)).not.toBeInTheDocument();
  });

  it('says nothing of a demo hospital to a site user who operates but may not run scenarios', async () => {
    server.use(
      http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: false })),
      http.get('/api/shutter/me', () =>
        HttpResponse.json({
          username: 'x',
          operator: true,
          approver: false,
          can: { operate: true, approve: false, configure: false, scenarios: false },
        }),
      ),
    );
    renderScenarios();
    expect(await screen.findByText('The Scenario Player is switched off')).toBeInTheDocument();
    await screen.findByRole('button', { name: 'Run S2' });
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
    expect(screen.queryByText(/the hospital plays one every few minutes/)).not.toBeInTheDocument();
  });
});

describe('ScenariosPage, as each role has it', () => {
  const asServer = (me: object) =>
    server.use(http.get('/api/shutter/me', () => HttpResponse.json({ username: 'x', ...me })));

  it("greys out Run and Reset for the public demo's role on a server before 1.4.4, and says once why", async () => {
    resetMock('demo');
    asServer(LOOK_ONLY_DEMO);
    renderScenarios();
    const list = await screen.findByRole('region', { name: 'Every scenario' });
    const why = await screen.findByText(
      'This hospital plays its stories by itself, and this sign-in reads and approves: it does not run or reset a scenario. The trial and your own instance run them.',
    );
    // Its hospital's stories are the written policy's: the opening names no board there
    expect(
      screen.getByText(/Here the site's written policy proposes the fix, with no agent/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/a board of IRIS AI Hub agents/)).not.toBeInTheDocument();
    const runs = await within(list).findAllByRole('button', { name: /^Run S\d+[a-z]?$/ });
    expect(runs).toHaveLength(listed.length);
    for (const run of runs) {
      expect(run).toBeDisabled();
      expect(run).toHaveAttribute('aria-describedby', why.id);
    }
    expect(screen.getByRole('button', { name: 'Reset' })).toBeDisabled();
    expect(screen.getByRole('columnheader', { name: 'Play' })).toBeInTheDocument();
    // The reason is said once, not under 29 buttons
    expect(screen.queryByText(/Running a scenario needs/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Resetting the shared demo needs/)).not.toBeInTheDocument();
    // The user menu shows this sign-in the operator and approver badges, so no reason asks it for those roles, the
    // tooltips included: they say what the sign-in lacks
    expect(screen.queryByText(/needs the operator or approver role/)).not.toBeInTheDocument();
    await userEvent.hover(screen.getByRole('button', { name: 'Reset' }).parentElement!);
    expect(
      await screen.findByText('This sign-in reads and approves, and does not reset the shared demo'),
    ).toBeInTheDocument();
    await userEvent.unhover(screen.getByRole('button', { name: 'Reset' }).parentElement!);
    await userEvent.hover(runs[0].parentElement!);
    expect(
      await screen.findByText('This sign-in reads and approves, and does not run scenarios'),
    ).toBeInTheDocument();
    await userEvent.unhover(runs[0].parentElement!);
    expect(screen.queryByText(/needs the operator or approver role/)).not.toBeInTheDocument();
    // The modes read the list, starting where the hospital plays, and the cards still open their cases
    expect(screen.getByRole('radiogroup', { name: 'Investigation modes' })).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /Site policy/ })).toBeChecked();
    expect(within(list).getByText(/Filter by what should happen in Site policy mode/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('radio', { name: /^Board/ }));
    expect(within(list).getByText(/Filter by what should happen in Board mode/)).toBeInTheDocument();
    for (const run of within(list).getAllByRole('button', { name: /^Run S\d+[a-z]?$/ }))
      expect(run).toBeDisabled();
    await userEvent.click(screen.getByRole('radio', { name: /Site policy/ }));
    // The way to the board's recording is a link, not a pointer to one that may not be there
    // (It sits behind "What a scenario does", so it is out of the accessibility tree until that opens.)
    expect(screen.getByRole('link', { name: "S8's recording in the trial", hidden: true })).toHaveAttribute(
      'href',
      expect.stringMatching(/\?trial#\/cases\/C-000008$/),
    );
    const first = screen.getByRole('region', { name: 'Three to look at first' });
    expect(await within(first).findByRole('link', { name: /the latest S2 case/ })).toBeInTheDocument();
    for (const name of ['Run S2 in Site policy mode', 'Run S23a in Site policy mode'])
      expect(within(first).getByRole('button', { name })).toBeDisabled();
    expect(within(first).getAllByRole('button', { name: /^Run / })).toHaveLength(3);
    for (const run of within(first).getAllByRole('button', { name: /^Run / })) expect(run).toBeDisabled();
    // Nothing tells this role to try or play anything
    expect(screen.queryByText(SCENARIOS_LEAD.live)).not.toBeInTheDocument();
    expect(screen.getByText(SCENARIOS_LEAD.lookOnly)).toBeInTheDocument();
    const words = document.body.textContent ?? '';
    expect(words).not.toMatch(/\bTry\b/);
    expect(words).not.toMatch(/You will see/);
    // Nobody is asked to answer the induction questions in a read-only demo
    expect(screen.queryByText('Shutter is running on the shipped site profile')).not.toBeInTheDocument();
    expect(screen.queryByText("Shutter is running on the demo's answers")).not.toBeInTheDocument();
  });

  it('gives the public demo its own three, in the mode its hospital plays them, each with the case it has', async () => {
    resetMock('demo');
    asServer(LOOK_ONLY_DEMO);
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    // S2 and S23a have a Site policy case in the recording; S15 has none, so its card shows its latest case under
    // that case's own mode, never a mode it was not played in
    const s2 = await within(first).findByRole('link', {
      name: 'Open C-000028, the latest S2 case in Site policy mode',
    });
    expect(within(first).getByText('The hospital plays these in Site policy mode.')).toBeInTheDocument();
    expect(s2).toHaveAttribute('href', '/cases/C-000028');
    const s23a = within(first).getByRole('link', {
      name: 'Open C-000058, the latest S23a case in Site policy mode',
    });
    expect(s23a).toHaveAttribute('href', '/cases/C-000058');
    const s15 = within(first).getByRole('link', { name: 'Open C-000012, the latest S15 case in Board mode' });
    expect(s15).toHaveAttribute('href', '/cases/C-000012');
    expect(within(first).getAllByText('What it shows')).toHaveLength(3);
    expect(within(s15.closest('[data-first]')!).getByText('Board')).toBeInTheDocument();
    expect(within(first).queryByText(/Not played since the last reset/)).not.toBeInTheDocument();
    expect(within(first).queryByText(/none in .* mode among the newest cases/)).not.toBeInTheDocument();
    expect(within(first).queryByText(/S8|S20/)).not.toBeInTheDocument();
    // The catalogue entry S2's plan cites comes from the case, not from the page
    const cases = recording.cases as unknown as Record<
      string,
      { plan: { plan: { catalogueEntry?: string } } }
    >;
    const entry = cases['C-000028'].plan.plan.catalogueEntry!;
    expect(entry).toBe('E2');
    expect(
      await within(first).findByText(`(catalogue entry ${entry})`, { exact: false }),
    ).toBeInTheDocument();
  });

  it('keeps a card whose scenario has no case yet, saying so where the link would be', async () => {
    resetMock('demo');
    asServer(LOOK_ONLY_DEMO);
    server.use(
      http.get('/api/shutter/cases', () =>
        HttpResponse.json({ items: [summaryOf('C-000028'), summaryOf('C-000025')], total: 2 }),
      ),
    );
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    expect(
      await within(first).findByRole('link', {
        name: 'Open C-000028, the latest S2 case in Site policy mode',
      }),
    ).toBeInTheDocument();
    expect(
      within(first).getByRole('link', { name: 'Open C-000025, the latest S15 case in Rules only mode' }),
    ).toBeInTheDocument();
    expect(within(first).getAllByRole('link', { name: /^Open C-/ })).toHaveLength(2);
    const s23a = first.querySelector<HTMLElement>('[data-first="S23a"]')!;
    expect(within(s23a).getByText('One case frees a bed for another')).toBeInTheDocument();
    expect(within(s23a).getByText('Site policy')).toBeInTheDocument();
    expect(
      within(s23a).getByText('No case yet: the hospital plays one every few minutes.'),
    ).toBeInTheDocument();
    expect(within(first).queryByText(/Not played since the last reset/)).not.toBeInTheDocument();
    expect(within(first).queryByText(/none in .* mode/)).not.toBeInTheDocument();
  });

  it('shows the three cards on a fresh demo, before its hospital has played any of them', async () => {
    resetMock('demo');
    asServer(LOOK_ONLY_DEMO);
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    expect(
      await within(first).findAllByText('No case yet: the hospital plays one every few minutes.'),
    ).toHaveLength(3);
    for (const id of ['S2', 'S23a', 'S15'])
      expect(first.querySelector(`[data-first="${id}"] h3`)).not.toBeNull();
    expect(within(first).getAllByText('What it shows')).toHaveLength(3);
    expect(within(first).queryByRole('link', { name: /^Open C-/ })).not.toBeInTheDocument();
    expect(within(first).queryByText(/Not played since the last reset/)).not.toBeInTheDocument();
  });

  it("says what the demo's three will show only as the scenarios' definitions have it", async () => {
    const def = (id: string) =>
      scenarioDefs.find((d) => d.id === id)!.expected as Scenario['expected'] & { blocked_by?: string };
    // S2 in Site policy mode: one conditional resend, a write, which the live hospital's policy holds for approval
    expect(def('S2')).toMatchObject({ disposition: 'resend', write: true });
    // S23a: the second patient's transfer is resent into the freed bed, in Site policy mode among others
    expect(def('S23a')).toMatchObject({ disposition: 'resend', write: true, modes: ['board', 'policy'] });
    // S15: the merge is withheld by the gate and escalated, nothing written
    expect(def('S15')).toMatchObject({ disposition: 'escalate', write: false, blocked_by: 'MERGE_WITHHELD' });
    resetMock('demo');
    asServer(LOOK_ONLY_DEMO);
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    expect(
      await within(first).findByText(/holds the one conditional resend for a person/),
    ).toBeInTheDocument();
    expect(within(first).getByText(/this one is resent into the bed/)).toBeInTheDocument();
    expect(
      within(first).getByText(/the gate prevents a patient merge from being sent in any mode/),
    ).toBeInTheDocument();
  });

  it('keeps Run and Reset for an approver, and says nothing about a demo that plays itself', async () => {
    resetMock('approver');
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeEnabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeEnabled();
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Play' })).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'Board' })).toBeInTheDocument();
  });

  it('keeps Run and Reset when the server sends `can.scenarios`', async () => {
    asServer({
      operator: true,
      approver: false,
      can: { operate: true, approve: false, configure: false, scenarios: true },
    });
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeEnabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeEnabled();
  });

  it("gives the judges' account Run, and Reset greyed out with its reason, never asking for a role it shows", async () => {
    resetMock('judge');
    renderScenarios();
    const list = await screen.findByRole('region', { name: 'Every scenario' });
    const runs = await within(list).findAllByRole('button', { name: /^Run S\d+[a-z]?$/ });
    expect(runs).toHaveLength(listed.length);
    expect(within(list).getByRole('button', { name: 'Run S2' })).toBeEnabled();
    const reset = screen.getByRole('button', { name: 'Reset' });
    expect(reset).toBeDisabled();
    const why =
      'This sign-in runs scenarios but does not reset the shared demo, which would clear it for everyone signed in';
    // Written under the button, where a keyboard and a screen reader reach it
    expect(screen.getByText(why)).toBeInTheDocument();
    // Not the public demo's look-only page: no single reason above the list, the board's modes open
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /^Board/ })).toBeChecked();
    expect(screen.getByRole('region', { name: 'Try these three first' })).toBeInTheDocument();
    expect(screen.queryByText(/needs the operator or approver role/)).not.toBeInTheDocument();
    // The run goes to the server, which plays it: the page then says it is playing
    await userEvent.click(within(list).getByRole('button', { name: 'Run S2' }));
    expect((await screen.findAllByText(/Playing S2/)).length).toBeGreaterThan(0);
    resetMock('approver');
  });

  it("gives the public demo's account Run, saying its runs replay the recorded agents, and keeps Reset greyed out", async () => {
    resetMock('demo');
    renderScenarios();
    const list = await screen.findByRole('region', { name: 'Every scenario' });
    const run = await within(list).findByRole('button', { name: 'Run S2' });
    expect(run).toBeEnabled();
    // Said once under the modes, of scenario runs only: no new inference, nothing spent, and the case says it was replayed
    const how = screen.getByRole('region', { name: 'How a run executes here' });
    expect(how).toHaveTextContent(
      'The mode says who proposes the plan, not how a run executes. Scenario runs from this sign-in replay the recorded agents on this IRIS instance: no new inference, nothing is spent, and the case says it was replayed.',
    );
    expect(within(how).getByText('Recorded replay')).toBeInTheDocument();
    // The way to live agents, with the install steps a link away
    expect(how).toHaveTextContent(
      "Live agents run from a sign-in that has them (on the online demo, the judges' account) and on your own install with a model key.",
    );
    expect(within(how).getByRole('link', { name: /^how to install/ })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter#try-it',
    );
    // Nothing says the sign-in makes no model call anywhere else: the sentence is about scenario runs
    expect(how).not.toHaveTextContent(/no model is called/);
    await userEvent.hover(run.parentElement!);
    expect(await screen.findByText('Play S2 in Board mode from its recordings')).toBeInTheDocument();
    await userEvent.unhover(run.parentElement!);
    // Reset stays with the hospital's own team, its reason under it, never asking for a role the menu shows
    expect(screen.getByRole('button', { name: 'Reset' })).toBeDisabled();
    expect(
      screen.getByText(
        'This sign-in runs scenarios but does not reset the shared demo, which would clear it for everyone signed in',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/needs the operator or approver role/)).not.toBeInTheDocument();
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
    // The single investigator was never recorded: it is described, can't be chosen, and says why and the way to it
    const single = screen.getByRole('radio', { name: /Single investigator/ });
    expect(single).toBeDisabled();
    expect(screen.getByText('No recording to replay')).toBeInTheDocument();
    expect(single).toHaveAccessibleDescription(
      /No recording to replay To run it: a sign-in with the live agents \(the judges' account\), or your own install with a model key\.$/,
    );
    expect(
      within(single).getByText(
        "To run it: a sign-in with the live agents (the judges' account), or your own install with a model key.",
      ),
    ).toBeVisible();
    expect(screen.getByRole('radio', { name: /^Board/ })).toBeChecked();
    // The run plays, and the banner says how it executes, from the run's own mark: recorded agents, no new inference
    await userEvent.click(run);
    const banner = (await screen.findByText(/^Playing S2 \(Board\)$/)).closest<HTMLElement>(
      '[role="alert"]',
    )!;
    expect(within(banner).getByTestId('run-execution')).toHaveTextContent(
      'Recorded replayIts agents answer from their recordings on this IRIS instance: no new inference.',
    );
    resetMock('approver');
  });

  it("keeps the judge's runs off the replay words, and calls none live before its case says what ran", async () => {
    resetMock('judge');
    renderScenarios();
    const list = await screen.findByRole('region', { name: 'Every scenario' });
    const run = await within(list).findByRole('button', { name: 'Run S2' });
    expect(run).toBeEnabled();
    expect(screen.queryByText(/replay the recorded agents/)).not.toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /Single investigator/ })).toBeEnabled();
    expect(screen.queryByText('No recording to replay')).not.toBeInTheDocument();
    // A run the server did not mark as a replay claims nothing while it plays: only its case's agent runs can say
    await userEvent.click(run);
    const banner = (await screen.findByText(/^Playing S2 \(Board\)$/)).closest<HTMLElement>(
      '[role="alert"]',
    )!;
    expect(within(banner).getByTestId('run-execution')).toHaveTextContent(
      /^Its case says what ran: live only when a model was called\.$/,
    );
    expect(within(banner).queryByText('Live model')).not.toBeInTheDocument();
    resetMock('approver');
  });

  it('derives the powers from the flags of a server that sends no `can`, as before', async () => {
    asServer({ operator: true, approver: true });
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeEnabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeEnabled();
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
  });

  it('keeps the disabled controls and their reason for someone who cannot operate at all', async () => {
    asServer({ operator: false, approver: false });
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S2' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Reset' })).toBeDisabled();
    expect(screen.queryByText(/plays its stories by itself/)).not.toBeInTheDocument();
    // The reason is written under the buttons, not only in a tooltip a disabled button cannot open
    expect(
      screen.getAllByText('Running a scenario needs the operator or approver role').length,
    ).toBeGreaterThan(0);
    expect(
      screen.getByText('Resetting the shared demo needs the operator or approver role'),
    ).toBeInTheDocument();
    const first = screen.getByRole('region', { name: 'Try these three first' });
    expect(
      within(first).getAllByText('Running a scenario needs the operator or approver role').length,
    ).toBeGreaterThan(0);
  });

  it('says why Run is disabled while another scenario plays, under the button', async () => {
    resetMock('approver');
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({
          scenarios: listed.map((d) => ({ ...d, latestCase: recordedLatest(d.id) })),
          run: {
            scenario: 'S2',
            mode: 'board',
            startedAt: new Date().toISOString(),
            state: 'running',
            files: [],
            timeouts: [],
            step: 'delivering S2-01-A01.hl7',
          },
        }),
      ),
    );
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S5' })).toBeDisabled();
    expect(screen.getAllByText('A run of S2 is still playing').length).toBeGreaterThan(0);
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Now delivering S2-01-A01.hl7. Files delivered so far: none.',
    );
  });
});

describe("ScenariosPage, a finished run's own case and Home's way in", () => {
  beforeEach(() => resetMock('judge'));
  afterEach(() => resetMock('approver'));

  const started = '2026-11-13T10:00:00Z';
  /** A run of S2 in Board that has finished, as the server reports it: not marked as a replay. */
  const finished = (extra: Record<string, unknown> = {}) => ({
    scenario: 'S2',
    mode: 'board',
    startedAt: started,
    finishedAt: '2026-11-13T10:00:20Z',
    state: 'done',
    files: ['S2-01-A01.hl7', 'S2-02-A02.hl7'],
    timeouts: [],
    ...extra,
  });
  /** The recorded S2 board case, opened before the run: the previous run's, which the scenario still names as its latest. */
  const earlier = () => summaryOf('C-000002');
  /** The case the run opened, a few seconds after it started. */
  const own = () => ({
    ...earlier(),
    caseId: 'C-000070',
    openedAt: '2026-11-13T10:00:05Z',
    state: 'awaiting_approval' as const,
  });

  /** S2's latest case as the scenario names it: the earlier board case, the previous run's. */
  const latestOf = (id: string) => {
    if (id !== 'S2') return recordedLatest(id);
    const { caseId, state, disposition, headline } = earlier();
    return { caseId, state, disposition, headline };
  };

  function serve(run: Record<string, unknown>, cases: () => CaseSummary[], runs?: unknown[]) {
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({
          scenarios: listed.map((d) => ({ ...d, latestCase: latestOf(d.id) })),
          run,
        }),
      ),
      http.get('/api/shutter/cases', () => HttpResponse.json({ items: cases(), total: cases().length })),
      http.get('/api/shutter/cases/C-000070/runs', () =>
        runs ? HttpResponse.json(runs) : HttpResponse.json({ error: 'not_found' }, { status: 404 }),
      ),
    );
  }

  const banner = async () =>
    (await screen.findByText(/^S2 played \(Board\), /)).closest<HTMLElement>('[role="alert"]')!;

  it("offers no case until the run's own has opened: never the previous run's, never the Cases list", async () => {
    let cases = [earlier()];
    serve(finished(), () => cases);
    const client = renderScenarios();
    const alert = await banner();
    await within(await card('S2')).findByRole('link', { name: 'C-000002' });
    // The scenario's latest case is the run before this one: the banner does not call it this run's
    expect(within(alert).queryByRole('link')).not.toBeInTheDocument();
    expect(alert).toHaveTextContent(
      'The production does the rest: its case opens in a few seconds, and its link appears here.',
    );
    expect(alert).not.toHaveTextContent('follow it in Cases');
    // Nothing is claimed about a model while no case of the run says what ran
    expect(within(alert).getByTestId('run-execution')).toHaveTextContent(
      /^Its case says what ran: live only when a model was called\.$/,
    );
    // The run's case opens: the next action is that case, by its id from the list
    cases = [own(), earlier()];
    await client.invalidateQueries({ queryKey: ['cases'] });
    expect(await within(alert).findByRole('link', { name: 'Open its case, C-000070' })).toHaveAttribute(
      'href',
      '/cases/C-000070',
    );
    expect(alert).toHaveTextContent('Next on the short route: S3, in its card below.');
    expect(alert).toHaveTextContent(
      "In IRIS: Message trace on the case opens its own session in IRIS's Visual Trace.",
    );
    // After a reset the case is gone from the list, and so is the link
    cases = [];
    await client.invalidateQueries({ queryKey: ['cases'] });
    await waitFor(() => expect(within(alert).queryByRole('link')).not.toBeInTheDocument());
  });

  it("labels the finished run from its own case's agent runs: live only when a model was called", async () => {
    serve(finished(), () => [own(), earlier()], [
      { id: 1, role: 'coordinator', mode: 'live', model: 'claude-opus-5-5', status: 'ok' },
    ]);
    renderScenarios();
    const alert = await banner();
    await waitFor(() =>
      expect(within(alert).getByTestId('run-execution')).toHaveTextContent(
        /^Live modelA model was called for this run\.$/,
      ),
    );
  });

  it('never labels a run live whose agents answered from their recordings, whatever the sign-in', async () => {
    // The install replays, or the run fell back: the server did not mark the run, and its case's runs are replays
    serve(finished(), () => [own(), earlier()], [
      { id: 1, role: 'coordinator', mode: 'replay', model: 'claude-opus-5-5', status: 'ok' },
    ]);
    renderScenarios();
    const alert = await banner();
    await waitFor(() =>
      expect(within(alert).getByTestId('run-execution')).toHaveTextContent(
        /^Recorded replayReplayed from a recorded live run: no model was called now\.$/,
      ),
    );
    expect(within(alert).queryByText('Live model')).not.toBeInTheDocument();
  });

  it("says a run the server marked as a replay made no new inference, without reading its case's runs", async () => {
    resetMock('demo');
    serve(finished({ replay: true }), () => [own(), earlier()], [
      { id: 1, role: 'coordinator', mode: 'live', model: 'claude-opus-5-5', status: 'ok' },
    ]);
    renderScenarios();
    const alert = await banner();
    expect(within(alert).getByTestId('run-execution')).toHaveTextContent(
      /^Recorded replayIts agents answered from their recordings on this IRIS instance: no new inference, nothing spent\.$/,
    );
    expect(await within(alert).findByRole('link', { name: 'Open its case, C-000070' })).toBeInTheDocument();
    expect(within(alert).queryByText('Live model')).not.toBeInTheDocument();
  });

  it("shows a Run just pressed as starting: the last run's banner and its case link give way before the server answers", async () => {
    // The last run, S2, has finished and its own case is open: its banner links that case
    let run: Record<string, unknown> = finished();
    let answer: () => void = () => undefined;
    const held = new Promise<void>((resolve) => (answer = resolve));
    serve(finished(), () => [own(), earlier()]);
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({ scenarios: listed.map((d) => ({ ...d, latestCase: latestOf(d.id) })), run }),
      ),
      // The server takes its time over the new run, as the online demo does: the answer waits until the test lets it go
      http.post('/api/shutter/scenarios/S3/run', async () => {
        await held;
        run = {
          scenario: 'S3',
          mode: 'board',
          startedAt: '',
          queuedAt: '2026-11-13T10:05:00Z',
          state: 'queued',
          files: [],
          timeouts: [],
        };
        return HttpResponse.json({ scenario: 'S3', mode: 'board', startedAt: '', files: [] });
      }),
    );
    renderScenarios();
    const last = await banner();
    expect(await within(last).findByRole('link', { name: 'Open its case, C-000070' })).toBeInTheDocument();
    await userEvent.click(await screen.findByRole('button', { name: 'Run S3 in Board mode' }));
    // From the press: the new run as starting, and nothing of the last run, its case link least of all
    const starting = await screen.findByTestId('run-starting');
    expect(starting).toHaveTextContent('Starting S3 (Board)');
    expect(starting).toHaveTextContent(
      'Asking the scenario player to start it. Its case link appears here once the run has played and its case has opened.',
    );
    expect(within(starting).queryByRole('link')).not.toBeInTheDocument();
    expect(screen.queryByText(/^S2 played \(Board\), /)).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /^Open its case/ })).not.toBeInTheDocument();
    expect(screen.queryByTestId('run-next')).not.toBeInTheDocument();
    // The server answers: the banner is the new run's, queued, still with no case link
    answer();
    expect(await screen.findByText('S3 is queued (Board)')).toBeInTheDocument();
    expect(screen.queryByTestId('run-starting')).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /^Open its case/ })).not.toBeInTheDocument();
  });

  it("keeps the last run's banner when the new run is refused: no run started, so nothing is shown as starting", async () => {
    serve(finished(), () => [own(), earlier()]);
    let asked = 0;
    server.use(
      http.post('/api/shutter/scenarios/S3/run', () => {
        asked += 1;
        return HttpResponse.json({ error: 'wrong_state', message: 'a run of S2 is queued' }, { status: 409 });
      }),
    );
    renderScenarios();
    await banner();
    await userEvent.click(await screen.findByRole('button', { name: 'Run S3 in Board mode' }));
    await waitFor(() => expect(asked).toBe(1));
    await waitFor(() => expect(screen.queryByTestId('run-starting')).not.toBeInTheDocument());
    // The banner is the last run's again, by its own name and time, with its own case
    const last = await banner();
    expect(last).toHaveTextContent(/^S2 played \(Board\), /);
    expect(await within(last).findByRole('link', { name: 'Open its case, C-000070' })).toBeInTheDocument();
  });

  it("lands on S2's card from Home's start with its Run focused, starts nothing, and drops the start from the address", async () => {
    const scrollTo = window.scrollTo;
    window.scrollTo = (() => undefined) as typeof window.scrollTo;
    const sent: string[] = [];
    const note = ({ request }: { request: Request }) => {
      if (request.method !== 'GET') sent.push(`${request.method} ${new URL(request.url).pathname}`);
    };
    server.events.on('request:start', note);
    try {
      resetMock('approver');
      renderAt('/?mode=board&start=S2');
      const first = await screen.findByRole('region', { name: 'Try these three first' });
      const run = await within(first).findByRole('button', { name: 'Run S2 in Board mode' });
      await waitFor(() => expect(run).toHaveFocus());
      // Arriving is navigation alone: no run, no approval, no write of any kind
      expect(sent).toEqual([]);
      expect(screen.queryByText(/^(Playing S2|S2 played|S2 is queued)/)).not.toBeInTheDocument();
      expect(screen.getByRole('radio', { name: 'Board' })).toBeChecked();
      // Back from the run's case, or a reload, finds the page as it was left, not the card again
      await waitFor(() => expect(address()).toBe('?mode=board'));
      // The second choice is Run itself
      await userEvent.click(run);
      await waitFor(() => expect(sent).toEqual(['POST /api/shutter/scenarios/S2/run']));
    } finally {
      server.events.removeListener('request:start', note);
      window.scrollTo = scrollTo;
    }
  });

  it('ignores a start the address names that is no card, and still drops it', async () => {
    const scrollTo = window.scrollTo;
    window.scrollTo = (() => undefined) as typeof window.scrollTo;
    try {
      resetMock('approver');
      renderAt('/?start=%22%5D%2C%5Bdata-x');
      await screen.findByRole('button', { name: 'Run S2' });
      await waitFor(() => expect(address()).toBe(''));
      expect(document.activeElement).toBe(document.body);
    } finally {
      window.scrollTo = scrollTo;
    }
  });
});

describe('ScenariosPage, its rows and its proof', () => {
  beforeEach(() => resetMock('approver'));

  it('reads the live lead outside the trial', async () => {
    renderScenarios();
    expect(await screen.findByText(SCENARIOS_LEAD.live)).toBeInTheDocument();
    expect(screen.queryByText(SCENARIOS_LEAD.trial)).not.toBeInTheDocument();
  });

  it("colours a row by its latest case's outcome when the case is among the newest cases", async () => {
    renderScenarios();
    // S5's latest case: a resolved resend, written and verified at the receiver
    const s5 = await card('S5');
    const link = await within(s5).findByRole('link', { name: /^C-\d+$/ });
    const found = summaryOf(link.textContent!);
    expect(found).toMatchObject({ state: 'resolved', disposition: 'resend', verification: 'verified' });
    expect(found.writes).toBeGreaterThan(0);
    // The badge reads the short form; its tooltip is the long one
    const badge = await within(s5).findByText('Delivered, verified');
    expect(
      caseOutcome(
        found,
        listed.find((d) => d.id === 'S5'),
      ).label,
    ).toBe('Delivered: verified at the receiver');
    expect(badge.closest('[data-tone]')).toHaveAttribute('data-tone', 'positive');
    expect(s5).toHaveAttribute('data-tone', 'positive');
    expect(within(s5).getByText('As expected')).toBeInTheDocument();
    // No badge in the list is a tab stop: the row's stops are its link, its More and its Run
    expect(s5.querySelectorAll('[tabindex="0"]')).toHaveLength(0);
    expect(s5.querySelectorAll('a, button, [tabindex="0"]').length).toBeLessThanOrEqual(3);
    expect(screen.getByRole('button', { name: 'How to read this list' })).toBeInTheDocument();
  });

  it('keeps the state badge for a latest case older than the newest cases', async () => {
    const s5 = listed.find((d) => d.id === 'S5')!;
    server.use(
      http.get('/api/shutter/scenarios', () =>
        HttpResponse.json({
          scenarios: [
            {
              ...s5,
              latestCase: { caseId: 'C-009999', state: 'resolved', disposition: 'resend', headline: '' },
            },
          ],
          run: null,
        }),
      ),
    );
    const client = renderScenarios();
    const row = await card('S5');
    await waitFor(() => expect(client.getQueryState(keys.cases({ limit: 100 }))?.status).toBe('success'));
    expect(within(row).getByRole('link', { name: 'C-009999' })).toBeInTheDocument();
    expect(within(row).getByText('Resolved')).toBeInTheDocument();
    expect(within(row).queryByText('Delivered, verified')).not.toBeInTheDocument();
    expect(within(row).queryByText('As expected')).not.toBeInTheDocument();
    expect(row).toHaveAttribute('data-tone', 'neutral');
  });

  it("marks S8's Rules only write not as expected, once, and S20's blocked case as expected", async () => {
    server.use(withLatest('S8', 'C-000021'));
    renderScenarios();
    const s8 = await card('S8');
    expect(within(s8).getByRole('link', { name: 'C-000021' })).toBeInTheDocument();
    expect(await within(s8).findAllByText('Not as expected')).toHaveLength(1);
    expect(within(s8).queryByText('Delivered, verified')).not.toBeInTheDocument();
    expect(s8).toHaveAttribute('data-tone', 'blocking');
    // S20's latest case is blocked, which is what S20 expects
    await userEvent.click(screen.getByRole('radio', { name: 'Rules only' }));
    const s20 = await card('S20');
    expect(await within(s20).findByText('Blocked')).toBeInTheDocument();
    expect(within(s20).getByText('As expected')).toBeInTheDocument();
  });

  it('says what the comparison recorded under what should happen, by its split', async () => {
    renderScenarios();
    for (const id of PROOF.rulesMisses!.stopped)
      expect(
        within(await card(id)).getByText('Recorded: board as expected; Rules only stopped by the gate'),
      ).toBeInTheDocument();
    expect(PROOF.rulesMisses!.wrote).toEqual(['S8']);
    expect(
      within(await card('S8')).getByText('Recorded: board as expected; Rules only wrote, not as expected'),
    ).toBeInTheDocument();
    expect(
      within(await card('S2')).getByText('Recorded: board as expected; Rules only as expected'),
    ).toBeInTheDocument();
    // A scenario the comparison did not play says nothing of it
    expect(within(await card('S15')).queryByText(/^Recorded:/)).not.toBeInTheDocument();
  });

  it("shows each row's first sentence in full and the rest behind a button named for its scenario", async () => {
    renderScenarios();
    const s1 = await card('S1');
    const def = listed.find((d) => d.id === 'S1')!;
    const [first] = def.summary.split('. ');
    expect(within(s1).getByText(`${first}.`)).toBeInTheDocument();
    const more = within(s1).getByRole('button', { name: 'More about S1' });
    expect(more).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(more);
    expect(more).toHaveAttribute('aria-expanded', 'true');
    expect(
      within(s1)
        .getByText(def.summary.slice(first.length + 2))
        .closest('[data-tech-detail]'),
    ).toHaveAttribute('data-tech-detail', 'open');
  });

  it('draws a diagram in each row and on each card, in the mode the row is showing, with the same in words', async () => {
    renderScenarios();
    const s20 = within(await card('S20')).getByRole('img', { name: /^S20, .* mode, in a diagram/ });
    expect(s20).toHaveAccessibleName(
      expect.stringContaining('a person changes the record at the receiver by hand'),
    );
    expect(s20).toHaveAccessibleName(expect.stringContaining('Expected: nothing written, superseded'));
    const list = screen.getByRole('region', { name: 'Every scenario' });
    expect(within(list).getAllByRole('img', { name: /in a diagram/ })).toHaveLength(listed.length);
    const first = screen.getByRole('region', { name: 'Try these three first' });
    expect(within(first).getAllByRole('img', { name: /in a diagram/ })).toHaveLength(3);
    // S21 is stopped by the gate in Rules only, so its picture changes with the choice of mode
    const s21 = () => within(screen.getByRole('button', { name: 'Run S21' }).closest('tr')!);
    expect(s21().getByRole('img', { name: /in a diagram/ })).not.toHaveAccessibleName(
      expect.stringContaining('EVENT_TIME_IMPLAUSIBLE'),
    );
    await userEvent.click(screen.getByRole('radio', { name: 'Rules only' }));
    expect(s21().getByRole('img', { name: /in a diagram/ })).toHaveAccessibleName(
      expect.stringContaining('EVENT_TIME_IMPLAUSIBLE'),
    );
  });

  it("shows the scenario's HL7 events as a code in Technical only", async () => {
    renderScenarios('technical');
    expect(within(await card('S2')).getByText('A01, A02 fails')).toBeInTheDocument();
    expect(within(await card('S15')).getByText('A01, A02, A40 withheld')).toBeInTheDocument();
  });

  it('keeps the HL7 events out of Plain', async () => {
    renderScenarios();
    expect(within(await card('S2')).queryByText('A01, A02 fails')).not.toBeInTheDocument();
  });

  it("states the proof from the board's evaluation, each comparison on its own base", async () => {
    renderScenarios();
    const board = PROOF.board!;
    const played = PROOF.played!;
    expect(board).toMatchObject({ matched: 24, scored: 24 });
    expect(played).toMatchObject({ of: 11, board: 11, rules: 4 });
    const line = (await screen.findByText(/^Tested on/)).closest<HTMLElement>('[data-proof-line]')!;
    // The words a reader sees (the definitions the terms carry for screen readers aside), led by the cohort and the
    // release both figures belong to
    expect(visibleText(line)).toContain(
      `Catalogue demonstration, recorded before release 1.0.0. Tested on ${board.scored} cases from ${board.scenarios} scenarios (an incident gives several), the board chose the expected action every time. Played end to end on ${played.of} one-failure scenarios: the board ${played.board}, Rules only ${played.rules}.`,
    );
    expect(within(line).getByRole('link', { name: 'See the evaluation' })).toHaveAttribute(
      'href',
      '/evaluation',
    );
    expect(line).not.toHaveTextContent('scored passes');
  });

  it('names the bases of the proof in Technical', async () => {
    renderScenarios('technical');
    const line = (await screen.findByText(/^Tested on/)).closest<HTMLElement>('[data-proof-line]')!;
    expect(visibleText(line)).toContain(
      `(${PROOF.board!.scored} scored passes, proposed action; ${PROOF.played!.of} scenarios, played end to end)`,
    );
  });

  it('names the agents in the Board mode, and says how many scenarios each mode plays as a badge', async () => {
    renderScenarios();
    const board = await screen.findByRole('radio', { name: 'Board' });
    await screen.findByRole('button', { name: 'Run S2' });
    expect(board).toHaveAccessibleDescription(
      /^Four AI Hub agents\. Three specialists read the sealed evidence at once, each from one angle: the message, the encounter's history, the impact on the receiver\. A coordinator weighs their findings and proposes one plan, with reasons\. Plays \d+ of the \d+ scenarios$/,
    );
    await screen.findByRole('button', { name: 'Run S2' });
    const count = document.getElementById('mode-board-count')!;
    expect(count).toHaveClass('mantine-Badge-root');
  });

  it("wraps the headline's HL7 and the proof's Rules only in their definitions", async () => {
    renderScenarios();
    await userEvent.click(await screen.findByRole('button', { name: 'What a scenario does' }));
    const heading = await screen.findByRole('heading', { name: /^Shutter resends a failed HL7 delivery/ });
    expect(within(heading).getByText('HL7')).toHaveAccessibleDescription(
      'The standard format hospital systems use to send each other messages, such as a patient transfer.',
    );
    const line = (await screen.findByText(/^Tested on/)).closest<HTMLElement>('[data-proof-line]')!;
    expect(within(line).getByText('Rules only')).toHaveAttribute('aria-describedby');
  });

  /** Waits for every part of the page that loads: the rows, their latest cases' outcomes, S8's cited entry. */
  async function loaded() {
    await screen.findByRole('button', { name: 'Run S2' });
    await within(await card('S5')).findByText('Delivered, verified');
    await screen.findByText('citing catalogue entry E7,', { exact: false });
  }

  it('keeps the first layer within its word budget, in Plain and in Technical', async () => {
    renderScenarios();
    await loaded();
    const plain = layer1WordCount(document.body);
    expect(plain).toBeLessThanOrEqual(PLAIN_BUDGET);
    cleanupAndReset();
    renderScenarios('technical');
    await loaded();
    const technical = layer1WordCount(document.body);
    expect(technical).toBeLessThanOrEqual(TECHNICAL_BUDGET);
    expect(technical).toBeLessThanOrEqual(plain * 1.5);
  });
});

/** An element's text as a reader sees it: without hidden parts (a term's definition) and visually hidden ones. */
function visibleText(el: HTMLElement): string {
  const copy = el.cloneNode(true) as HTMLElement;
  for (const h of copy.querySelectorAll('[hidden], [aria-hidden="true"], .mantine-VisuallyHidden-root'))
    h.remove();
  return (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
}

/** Unmounts the page and clears the mock between two renders in one test. */
function cleanupAndReset() {
  cleanup();
  resetMock('approver');
}
