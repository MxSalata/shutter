import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasePage from './CasePage';

/**
 * What the agents contributed, on the case, beside what happened (the clarity review of 13 Nov, item 2): the decision
 * receipt names who proposed the plan, the plan's recorded reason opens under it with its evidence as links, and the
 * gate's result and the writes stay facts of their own. A plan no agent's run made is never called an agent's.
 */

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return env.trial;
    },
  };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

beforeEach(() => {
  resetMock('approver');
  env.trial = false;
  window.localStorage.removeItem('shutter.outcomeBand');
  useAppearance.setState({ detail: 'plain' });
});

type Id = keyof typeof fixtures.cases;

function renderCase(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The Outcome band, opened: a closed case's starts closed. */
async function band() {
  const top = await screen.findByRole('region', { name: 'Outcome' });
  const toggle = within(top).getByRole('button', { name: 'Outcome' });
  if (toggle.getAttribute('aria-expanded') !== 'true') await userEvent.click(toggle);
  return top;
}

/** The receipt inside the band, once the band has opened. */
const receiptOf = (top: HTMLElement) => within(top).findByRole('region', { name: 'Decision receipt' });

/** The receipt's facts by name: each `dt` with the words of its `dd`. */
function facts(receipt: HTMLElement): Record<string, string> {
  return Object.fromEntries(
    [...receipt.querySelectorAll('.receipt-fact')].map((f) => [
      f.querySelector('dt')?.textContent ?? '',
      f.querySelector('dd')?.textContent ?? '',
    ]),
  );
}

const why = (id: Id) => (fixtures.cases[id].plan as { plan: { why: string } }).plan.why;

describe('the decision receipt on S2, S3 and S8', () => {
  it.each([
    {
      id: 'C-000002',
      proposal: 'Resend the PAS transfer to WARD-B, once',
      reason: 'Why: Not delivered, still current',
      gate: 'Eligible for approval',
      evidence: ['Encounter', 'Receipt'],
    },
    {
      id: 'C-000003',
      proposal: 'Reconcile: no write to the receiver',
      reason: 'Why: Committed after all',
      gate: 'Passed: no write',
      evidence: ['Encounter', 'Receipt'],
    },
    {
      id: 'C-000008',
      proposal: 'Escalate: no write to the receiver',
      reason: 'Why: Two sources at the same time',
      gate: 'Passed: no write',
      evidence: ['Encounter', 'Receipt', 'Timeline'],
    },
  ] as const)(
    'names who proposed, the proposal, its reason, the gate result and the writes on $id',
    async ({ id, proposal, reason, gate, evidence }) => {
      renderCase(id);
      const top = await band();
      const receipt = await receiptOf(top);
      await within(receipt).findByText("Coordinator agent's proposal", { selector: 'dt' });
      const said = facts(receipt);
      expect(said["Coordinator agent's proposal"]).toContain(proposal);
      expect(said.Gate).toContain(gate);
      expect(said.Writes).toContain('0 writes');
      // The reason is named under the proposal and closed at first, in Technical too
      const toggle = within(receipt).getByRole('button', { name: reason });
      expect(toggle).toHaveAttribute('aria-expanded', 'false');
      expect(document.getElementById('proposal-reason')).not.toBeVisible();
      await userEvent.click(toggle);
      const body = document.getElementById('proposal-reason')!;
      expect(body).toBeVisible();
      // The plan's own words, whole, and whose they are; never a summary written for the page
      expect(
        within(body).getByText("The coordinator agent's reason, as its run recorded it"),
      ).toBeInTheDocument();
      expect(within(body).getByTestId('proposal-reason-words')).toHaveTextContent(why(id));
      expect(
        within(body).getByText(
          "An agent only proposes. The gate's checks and the release, in this receipt, decide whether anything is sent.",
        ),
      ).toBeInTheDocument();
      expect(within(body).getByRole('button', { name: "See each agent's finding" })).toBeInTheDocument();
      // The facts under What happened name the evidence they were read from, each a link to its section
      const links = within(top).getByRole('group', { name: 'The evidence this was read from' });
      expect(
        within(links)
          .getAllByRole('button')
          .map((b) => b.textContent),
      ).toEqual([...evidence]);
    },
  );

  it('keeps the reason closed in Technical too, so the band stays short', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderCase('C-000008');
    const receipt = await receiptOf(await band());
    expect(
      await within(receipt).findByRole('button', { name: 'Why: Two sources at the same time' }),
    ).toHaveAttribute('aria-expanded', 'false');
  });

  it('says how the specialists stood to the plan, with the dissent it keeps', async () => {
    renderCase('C-000008');
    const receipt = await receiptOf(await band());
    await userEvent.click(
      await within(receipt).findByRole('button', { name: 'Why: Two sources at the same time' }),
    );
    expect(
      within(receipt).getByText(
        'Encounter Integrity and Impact Analysis proposed the same; Conformance proposed resend, which the plan keeps as dissent.',
      ),
    ).toBeInTheDocument();
  });
});

describe('the evidence links', () => {
  it("opens the case's own evidence from What happened: the Evidence tab, at the section, with what it recorded", async () => {
    renderCase('C-000008');
    const top = await band();
    const links = await within(top).findByRole('group', { name: 'The evidence this was read from' });
    const chip = within(links).getByRole('button', { name: 'Receipt' });
    expect(chip).not.toHaveAttribute('href');
    await userEvent.click(chip);
    expect(await screen.findByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    const evidence = await screen.findByRole('region', { name: 'Evidence' });
    const section = await within(evidence).findByRole('button', {
      name: /Downstream Out's receipt for this operation: What was recorded/,
    });
    await waitFor(() => expect(section).toHaveAttribute('aria-expanded', 'true'));
  });

  it("opens the catalogue entry and the sections the plan cites from the proposal's reason", async () => {
    renderCase('C-000008');
    const receipt = await receiptOf(await band());
    await userEvent.click(
      await within(receipt).findByRole('button', { name: 'Why: Two sources at the same time' }),
    );
    const body = document.getElementById('proposal-reason')!;
    expect(
      within(body)
        .getAllByRole('button')
        .map((b) => b.textContent),
    ).toEqual([
      'E7',
      'HL7 message',
      'Schema validation',
      'Connector error',
      'Failed operation',
      'Route',
      'Encounter',
      'Receipt',
      'Timeline',
      "See each agent's finding",
    ]);
    await userEvent.click(within(body).getByRole('button', { name: 'Catalogue entry E7' }));
    expect(await screen.findByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await waitFor(() => expect(document.getElementById('evidence-catalogue')).toHaveFocus());
  });

  it("leads from the reason to each agent's finding on the board", async () => {
    renderCase('C-000008');
    const receipt = await receiptOf(await band());
    await userEvent.click(
      await within(receipt).findByRole('button', { name: 'Why: Two sources at the same time' }),
    );
    await userEvent.click(within(receipt).getByRole('button', { name: "See each agent's finding" }));
    await waitFor(() => expect(screen.getByRole('heading', { name: 'The board' })).toHaveFocus());
  });
});

describe('a plan no agent made', () => {
  it("calls a site policy plan the policy's, with the policy's reason and no agent", async () => {
    renderCase('C-000028');
    const top = await band();
    const receipt = await receiptOf(top);
    const toggle = await within(receipt).findByRole('button', { name: 'Why: Not delivered, still current' });
    expect(
      within(receipt).getByText("Site policy's proposal, no agent", { selector: 'dt' }),
    ).toBeInTheDocument();
    await userEvent.click(toggle);
    const body = document.getElementById('proposal-reason')!;
    expect(within(body).getByText("The site's policy gives this reason; no agent ran")).toBeInTheDocument();
    expect(within(body).getByTestId('proposal-reason-words')).toHaveTextContent(why('C-000028'));
    expect(within(body).getByText('No agent proposed this plan.')).toBeInTheDocument();
    expect(within(body).queryByRole('button', { name: /finding/ })).not.toBeInTheDocument();
    expect(top).not.toHaveTextContent(/agent's (proposal|reason)/);
    expect(top).not.toHaveTextContent('An agent only proposes');
  });

  it("calls the rules' plan the rules', with no reason to open, since it records none", async () => {
    renderCase('C-000021');
    const top = await band();
    const receipt = await receiptOf(top);
    expect(
      await within(receipt).findByText("The rules' proposal, no agent", { selector: 'dt' }),
    ).toBeInTheDocument();
    expect(within(receipt).queryByRole('button', { name: /^Why/ })).not.toBeInTheDocument();
    expect(document.getElementById('proposal-reason')).toBeNull();
    expect(top).not.toHaveTextContent(/agent's (proposal|reason)/);
    // What was written is its own fact, apart from who proposed it
    expect(facts(receipt).Writes).toContain('1 write');
  });

  it('claims no agent when the agents of the case gave no answer', async () => {
    const failed = (fixtures.cases['C-000008'].runs as unknown as Record<string, unknown>[]).map((r) => ({
      ...r,
      status: 'error',
      result: null,
      finding: null,
    }));
    server.use(http.get('/api/shutter/cases/C-000008/runs', () => HttpResponse.json(failed)));
    renderCase('C-000008');
    const top = await band();
    const board = await screen.findByRole('region', { name: 'The board' });
    expect((await within(board).findAllByText('No answer from this agent.')).length).toBe(3);
    const receipt = await receiptOf(top);
    expect(within(receipt).getByText('Proposal', { selector: 'dt' })).toBeInTheDocument();
    expect(top).not.toHaveTextContent(/agent's (proposal|reason)/);
    // The plan's own reason is still the plan's, named as no more than that
    await userEvent.click(within(receipt).getByRole('button', { name: 'Why: Two sources at the same time' }));
    const body = document.getElementById('proposal-reason')!;
    expect(within(body).getByText('The reason recorded with the plan')).toBeInTheDocument();
    expect(within(body).queryByRole('button', { name: /finding/ })).not.toBeInTheDocument();
    expect(body).not.toHaveTextContent('proposed the same');
    expect(body).not.toHaveTextContent('An agent only proposes');
  });

  it('claims no agent while the runs cannot be read', async () => {
    server.use(
      http.get('/api/shutter/cases/C-000008/runs', () => HttpResponse.json({ error: 'x' }, { status: 500 })),
    );
    renderCase('C-000008');
    const top = await band();
    await within(top).findByText('Passed: no write');
    expect(within(await receiptOf(top)).getByText('Proposal', { selector: 'dt' })).toBeInTheDocument();
    expect(top).not.toHaveTextContent(/agent's (proposal|reason)/);
  });
});

describe("a run's provenance on the board", () => {
  /** Opens a specialist's finding and returns its card. */
  async function finding(name: string) {
    const board = await screen.findByRole('region', { name: 'The board' });
    const card = await within(board).findByRole('region', { name });
    await userEvent.click(within(card).getByRole('button', { name: 'Show the finding' }));
    return card;
  }

  it('calls a replay on IRIS a replay, and its tool calls recorded ones', async () => {
    renderCase('C-000008');
    const card = await finding('Conformance');
    expect(card).toHaveTextContent('Replay · claude-opus-5-5 · 14.7 s · 3 steps · 5 tool calls');
    expect(within(card).getByText('Recorded replay · claude-opus-5-5')).toBeInTheDocument();
    expect(
      within(card).getByText(/when recorded, nothing now · 14\.7 s · 5 recorded tool calls$/),
    ).toBeInTheDocument();
    expect(within(card).getByText('Recorded tool calls (5)')).toBeInTheDocument();
  });

  it("names a live run's tool calls as made by it", async () => {
    const live = (fixtures.cases['C-000008'].runs as unknown as Record<string, unknown>[]).map((r) => ({
      ...r,
      mode: 'live',
    }));
    server.use(http.get('/api/shutter/cases/C-000008/runs', () => HttpResponse.json(live)));
    renderCase('C-000008');
    const card = await finding('Conformance');
    expect(card).toHaveTextContent('Live · claude-opus-5-5 · 14.7 s · 3 steps · 5 tool calls');
    expect(within(card).getByText('Live model · claude-opus-5-5')).toBeInTheDocument();
    expect(within(card).getByText('Tool calls (5)')).toBeInTheDocument();
    expect(card).not.toHaveTextContent(/recorded tool call/i);
  });

  it('calls every run of the trial a browser recording, as the case header does, never a replay or a live run', async () => {
    env.trial = true;
    renderCase('C-000008');
    await userEvent.click(await screen.findByRole('button', { name: 'Details' }));
    expect(await screen.findByText('Browser recording: no new inference')).toBeInTheDocument();
    const card = await finding('Conformance');
    expect(card).toHaveTextContent('Browser recording · claude-opus-5-5 · 14.7 s · 3 steps · 5 tool calls');
    const board = screen.getByRole('region', { name: 'The board' });
    expect(board).not.toHaveTextContent(/Recorded replay|Replay ·|Live model|Live ·/);
    expect(within(card).getByText('Browser recording')).toBeInTheDocument();
    expect(
      within(card).getByText(
        'No model call now: this browser shows a recording of a run on claude-opus-5-5.',
      ),
    ).toBeInTheDocument();
    expect(
      within(card).getByText(/when recorded, nothing now · 14\.7 s · 5 recorded tool calls$/),
    ).toBeInTheDocument();
    expect(within(card).getByText('Recorded tool calls (5)')).toBeInTheDocument();
  });

  it("keeps a recording of a live run a browser recording in the trial, its cost the recording's", async () => {
    env.trial = true;
    const live = (fixtures.cases['C-000008'].runs as unknown as Record<string, unknown>[]).map((r) => ({
      ...r,
      mode: 'live',
    }));
    server.use(http.get('/api/shutter/cases/C-000008/runs', () => HttpResponse.json(live)));
    renderCase('C-000008');
    const card = await finding('Conformance');
    expect(card).toHaveTextContent('Browser recording · claude-opus-5-5 · 14.7 s');
    expect(card).not.toHaveTextContent(/Live model|Live ·/);
    expect(
      within(card).getByText(/when recorded, nothing now · 14\.7 s · 5 recorded tool calls$/),
    ).toBeInTheDocument();
  });
});

describe('the board, trimmed to pay for the receipt', () => {
  it("opens why a dissent was kept from the line that names it, and the coordinator's entry as a chip", async () => {
    renderCase('C-000008');
    const board = await screen.findByRole('region', { name: 'The board' });
    const coordinator = await within(board).findByRole('region', { name: 'Coordinator' });
    const kept = within(coordinator).getByRole('button', { name: 'Dissent kept: Conformance' });
    expect(kept).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(kept);
    expect(kept).toHaveAttribute('aria-expanded', 'true');
    expect(
      within(coordinator)
        .getByText(/^Conformance only checks the message/)
        .closest('[data-tech-detail]'),
    ).toHaveAttribute('data-tech-detail', 'open');
    await userEvent.click(
      within(coordinator).getByRole('button', {
        name: /^Cited 8 evidence sections and catalogue entry E7\s?, Coordinator$/,
      }),
    );
    await userEvent.click(await within(coordinator).findByRole('button', { name: 'Catalogue entry E7' }));
    expect(await screen.findByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
  });
});
