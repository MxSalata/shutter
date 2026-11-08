import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import type { CaseSummary, Scenario } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock, writesOf } from '@/mocks/handlers';
import type { CaseFixture } from '@/mocks/hold';
import { caseOutcome } from '@/lib/status';
import { PROOF } from '@/lib/proof';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
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
        name: 'Shutter fixes a failed HL7 transfer only when its checks pass. Otherwise it stops and names the patient.',
      }),
    ).toBeInTheDocument();
    const steps = screen.getByRole('list', { name: 'What happens to every case' });
    expect(
      within(steps)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['1Open case', '2Evidence', '3Board plan', '4Gate checks', '5Release', '6Verify']);
  });

  it('offers three scenarios to try first, each in its own mode, with what you will see and its latest case', async () => {
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    for (const [id, mode] of [
      ['S2', 'Board'],
      ['S8', 'Board'],
      ['S20', 'Rules only'],
    ])
      expect(await within(first).findByRole('button', { name: `Run ${id} in ${mode} mode` })).toBeEnabled();
    expect(within(first).getAllByText('You will see')).toHaveLength(3);
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
    // Why it matters, on the card: the wrong write would pass every check
    expect(
      within(first).getByText(/^A resend would write over the bed manager's ward with every check passed\./),
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

  it("shows the chosen mode's name and hint under the choice, and changes them with the choice", async () => {
    renderScenarios();
    const rules = await screen.findByRole('radio', { name: 'Rules only' });
    const hint = document.querySelector<HTMLElement>('[data-mode-hint]')!;
    expect(hint).toHaveTextContent(
      'Board: Three specialist agents review the evidence in parallel; a coordinator agent proposes one plan.',
    );
    await userEvent.click(rules);
    expect(hint).toHaveTextContent(
      'Rules only: No agents: resend unchanged unless the gate objects. The baseline to compare with.',
    );
    expect(hint).not.toHaveTextContent('Three specialist agents');
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
    renderScenarios();
    const prompt = await screen.findByText('Shutter is running on the shipped site profile');
    const heading = screen.getByRole('heading', { name: 'Scenarios' });
    expect(prompt.compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
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

  it("greys out Run and Reset for the public demo's role, and says once why", async () => {
    resetMock('demo');
    renderScenarios();
    const list = await screen.findByRole('region', { name: 'Every scenario' });
    const why = await screen.findByText(
      'This hospital plays its stories by itself, so running one needs the operator or approver role, which the trial and your own instance offer.',
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
    expect(screen.queryByText(/Resetting needs/)).not.toBeInTheDocument();
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
  });

  it('gives the public demo its own three, in the mode its hospital plays them, each with the case it has', async () => {
    resetMock('demo');
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
    expect(within(s23a).getByText('One case waits for another')).toBeInTheDocument();
    expect(within(s23a).getByText('Site policy')).toBeInTheDocument();
    expect(
      within(s23a).getByText('No case yet: the hospital plays one every few minutes.'),
    ).toBeInTheDocument();
    expect(within(first).queryByText(/Not played since the last reset/)).not.toBeInTheDocument();
    expect(within(first).queryByText(/none in .* mode/)).not.toBeInTheDocument();
  });

  it('shows the three cards on a fresh demo, before its hospital has played any of them', async () => {
    resetMock('demo');
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
    renderScenarios();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    expect(
      await within(first).findByText(/holds the one conditional resend for a person/),
    ).toBeInTheDocument();
    expect(within(first).getByText(/this one is resent into the bed/)).toBeInTheDocument();
    expect(within(first).getByText(/the gate blocks every plan/)).toBeInTheDocument();
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
    expect(screen.getByText('Resetting needs the operator or approver role')).toBeInTheDocument();
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
    const s20 = within(await card('S20')).getByRole('img', { name: /^S20 in a diagram/ });
    expect(s20).toHaveAccessibleName(
      expect.stringContaining('a person changes the record at the receiver by hand'),
    );
    expect(s20).toHaveAccessibleName(expect.stringContaining('It should end: nothing written, superseded'));
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
    // The words a reader sees (the definitions the terms carry for screen readers aside)
    expect(visibleText(line)).toContain(
      `Tested on ${board.scored} recorded board runs, each against its scenario's expected action: the board chose it every time. Played end to end on ${played.of} of them: the board ${played.board}, Rules only ${played.rules}.`,
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
      /^Three specialist agents review the evidence in parallel; a coordinator agent proposes one plan\. Plays \d+ of the \d+ scenarios$/,
    );
    await screen.findByRole('button', { name: 'Run S2' });
    const count = document.getElementById('mode-board-count')!;
    expect(count).toHaveClass('mantine-Badge-root');
  });

  it("wraps the headline's HL7 transfer and the proof's Rules only in their definitions", async () => {
    renderScenarios();
    await userEvent.click(await screen.findByRole('button', { name: 'What a scenario does' }));
    const heading = await screen.findByRole('heading', { name: /^Shutter fixes a failed HL7 transfer/ });
    expect(within(heading).getByText('HL7 transfer')).toHaveAccessibleDescription(
      'A message telling another hospital system that a patient moved ward.',
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
