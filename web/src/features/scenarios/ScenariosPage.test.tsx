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
import recording from '@/mocks/fixtures.json';

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

/** A scenario's row in the list, found by its Run button. */
async function card(id: string) {
  const run = await screen.findByRole('button', { name: `Run ${id}` });
  return run.closest<HTMLElement>('tr')!;
}

const scenarioDefs = definitions as unknown as Scenario[];
/** The scenarios the mock lists: the recording's, with their definitions. */
const listed = scenarioDefs.filter((d) => recording.scenarios.some((s) => s.id === d.id));

describe('ScenariosPage', () => {
  beforeEach(() => resetMock('approver'));

  it('offers every mode outside the demo', async () => {
    renderScenarios();
    expect(await screen.findByRole('radio', { name: 'Single investigator' })).toBeInTheDocument();
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

  it('opens with the one sentence and the six steps every case goes through', async () => {
    renderScenarios();
    expect(
      await screen.findByRole('heading', {
        name: 'When an HL7 transfer fails, Shutter works out what is true and fixes it only when it is safe.',
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

  it('counts the scenarios each mode plays, and the list by outcome, from the list itself', async () => {
    renderScenarios();
    const rules = await screen.findByRole('radio', { name: 'Rules only' });
    await screen.findByRole('button', { name: 'Run S2' });
    const inRules = listed.filter((d) => !d.expected?.modes || d.expected.modes.includes('rules')).length;
    expect(rules).toHaveAccessibleDescription(
      new RegExp(`Plays ${inRules} of the ${listed.length} scenarios\\.$`),
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
    expect(within(s).getByText('EVENT_TIME_IMPLAUSIBLE')).toBeInTheDocument();
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
    // No card is greyed out for a mode when there is no mode to play in
    expect(screen.queryByText(/^Not defined for/)).not.toBeInTheDocument();
  });
});

describe('ScenariosPage, as each role has it', () => {
  const asServer = (me: object) =>
    server.use(http.get('/api/shutter/me', () => HttpResponse.json({ username: 'x', ...me })));

  it("hides Run and Reset from the public demo's role, and says the demo plays its stories by itself", async () => {
    resetMock('demo');
    renderScenarios();
    expect(await screen.findByRole('region', { name: 'Every scenario' })).toBeInTheDocument();
    expect(await screen.findByText(/The public demo plays its stories by itself/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Run / })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument();
    // No Play column, no mode to choose; the modes are described and the cards still open their cases
    expect(screen.queryByRole('columnheader', { name: 'Play' })).not.toBeInTheDocument();
    expect(screen.queryByRole('radio', { name: 'Board' })).not.toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Investigation modes' })).toBeInTheDocument();
    const first = screen.getByRole('region', { name: 'Try these three first' });
    expect(await within(first).findByRole('link', { name: /the latest S8 case/ })).toBeInTheDocument();
    // Nobody is asked to answer the induction questions in a read-only demo
    expect(screen.queryByText('Shutter is running on the shipped site profile')).not.toBeInTheDocument();
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
  });
});
