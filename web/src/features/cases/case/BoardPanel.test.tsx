import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { BoardPanel } from './BoardPanel';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
beforeEach(() => resetMock('approver'));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderBoard(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <BoardPanel caseId={caseId} open mode="board" portalBase="/csp/" />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** A case whose recorded runs lost or changed some: what a board with a member missing leaves in the store. */
function withRuns(change: (runs: Record<string, unknown>[]) => Record<string, unknown>[]) {
  const runs = structuredClone(fixtures.cases['C-000009'].runs) as unknown as Record<string, unknown>[];
  server.use(http.get('/api/shutter/cases/C-000009/runs', () => HttpResponse.json(change(runs))));
  renderBoard('C-000009');
}

describe('a board that sat twice (C-000007)', () => {
  it('counts members, not runs, and marks only the dissent from its own round', async () => {
    renderBoard('C-000007');
    const board = await screen.findByRole('region', { name: 'Coordinator Round 2' });
    const panel = board.closest('section[id="board"]') as HTMLElement;
    expect(panel).toHaveTextContent('Three specialist agents read the same evidence');
    expect(panel).not.toHaveTextContent('Six');
    // Round 1's three proposed the resend its plan adopted: that is no dissent, though round 2's plan differs
    expect(within(panel).getAllByText('Dissent')).toHaveLength(1);
    expect(within(panel).getByText('1 dissent kept')).toBeInTheDocument();
    expect(within(panel).getByText('With the majority')).toBeInTheDocument();
    expect(
      within(within(panel).getByRole('region', { name: 'Conformance Round 2' })).getByText('Dissent'),
    ).toBeInTheDocument();
    expect(
      within(within(panel).getByRole('region', { name: 'Conformance Round 1' })).queryByText('Dissent'),
    ).not.toBeInTheDocument();
  });

  it("labels each round's cards and the plan that round reached", async () => {
    renderBoard('C-000007');
    const first = await screen.findByRole('group', { name: 'Round 1 of 2' });
    const second = screen.getByRole('group', { name: 'Round 2 of 2' });
    expect(
      within(first)
        .getAllByRole('region')
        .map((r) => r.getAttribute('data-member')),
    ).toEqual(['conformance', 'encounter', 'impact']);
    expect(within(first).getAllByText('Round 1')).toHaveLength(3);
    expect(within(second).getAllByText('Round 2')).toHaveLength(3);
    expect(within(first).getAllByText('Proposed: Resend').length).toBeGreaterThan(3);
    expect(within(first).getByText('Then Shutter collected the evidence again.')).toBeInTheDocument();
    expect(within(second).getByText('The coordinator below proposed this plan.')).toBeInTheDocument();
  });
});

describe('a board of one sitting', () => {
  it('has no round labels', async () => {
    renderBoard('C-000008');
    await screen.findByRole('region', { name: 'Coordinator' });
    expect(screen.queryByText(/^Round \d/)).not.toBeInTheDocument();
    expect(screen.getByText('With the majority')).toBeInTheDocument();
  });
});

describe('a board with a member missing', () => {
  it('with two runs, as a timeout or a member switched off leaves it: no agreement claimed', async () => {
    withRuns((runs) => runs.filter((r) => r.memberCode !== 'impact'));
    const card = await screen.findByRole('region', { name: 'Coordinator' });
    expect(screen.getByText('2 specialists answered')).toBeInTheDocument();
    expect(screen.getByText(/^Two specialist agents read/)).toBeInTheDocument();
    expect(screen.queryByText('Unanimous')).not.toBeInTheDocument();
    expect(screen.queryByText(/the specialists agreed/)).not.toBeInTheDocument();
    expect(card).toHaveTextContent('2 specialists answered; the coordinator kept no disagreements.');
  });

  it('with a run that has no answer: the same, and its card says so', async () => {
    withRuns((runs) =>
      runs.map((r) =>
        r.memberCode === 'impact' ? { ...r, status: 'no_record', result: null, finding: null } : r,
      ),
    );
    const card = await screen.findByRole('region', { name: 'Impact Analysis' });
    expect(within(card).getByText('No answer from this agent.')).toBeInTheDocument();
    expect(screen.getByText('2 specialists answered')).toBeInTheDocument();
    // The hollow dot would say it proposed something else
    expect(screen.queryByText('With the majority')).not.toBeInTheDocument();
    expect(screen.queryByText(/the specialists agreed/)).not.toBeInTheDocument();
  });

  it('with a run over its budget: the result it keeps is not a view, a dissent or a confidence', async () => {
    // The server keeps an over-budget run's result for inspection but does not use it
    withRuns((runs) =>
      runs.map((r) =>
        r.memberCode === 'impact'
          ? {
              ...r,
              status: 'budget_exceeded',
              result: { disposition: 'hold', confidence: 0.9 },
              finding: {
                disposition: 'hold',
                confidence: 0.9,
                findings: { disposition: 'hold', confidence: 0.9 },
              },
            }
          : r,
      ),
    );
    const card = await screen.findByRole('region', { name: 'Impact Analysis' });
    expect(within(card).getByText('No answer from this agent.')).toBeInTheDocument();
    expect(within(card).queryByText('Dissent')).not.toBeInTheDocument();
    expect(within(card).queryByTestId('own-confidence')).not.toBeInTheDocument();
    expect(screen.getByText('2 specialists answered')).toBeInTheDocument();
  });

  it('keeps a dissent the coordinator kept, from a member with no answer of its own', async () => {
    withRuns((runs) =>
      runs.map((r) => {
        if (r.memberCode === 'impact') return { ...r, status: 'budget_exceeded' };
        if (r.memberCode !== 'coordinator') return r;
        const kept = { member: 'impact', said: 'hold: the receiver moved', why_kept: 'Worth keeping.' };
        return { ...r, result: { ...(r.result as object), disagreements: [kept] } };
      }),
    );
    const card = await screen.findByRole('region', { name: 'Impact Analysis' });
    expect(within(card).getByText('Dissent')).toBeInTheDocument();
  });

  it('gives the definition of confidence to the first card that shows one', async () => {
    // Conformance comes first in the recording; with no answer its card shows no confidence to define
    withRuns((runs) =>
      runs.map((r) => (r.memberCode === 'conformance' ? { ...r, status: 'budget_exceeded' } : r)),
    );
    const card = await screen.findByRole('region', { name: 'Encounter Integrity' });
    expect(within(card).getByText('own confidence')).toHaveAccessibleDescription(
      "The agent's own report, not calibrated. The gate does not use it.",
    );
  });

  it('says one specialist in the singular', async () => {
    withRuns((runs) => runs.filter((r) => r.memberCode === 'coordinator' || r.memberCode === 'conformance'));
    expect(await screen.findByText('1 specialist answered')).toBeInTheDocument();
    expect(screen.getByText(/^One specialist agent reads the evidence/)).toBeInTheDocument();
  });

  it('with all three agreeing keeps the words of a full board', async () => {
    withRuns((runs) => runs);
    await screen.findByRole('region', { name: 'Coordinator' });
    expect(screen.queryByText(/specialists? answered/)).not.toBeInTheDocument();
    expect(screen.getByText(/the specialists agreed/)).toBeInTheDocument();
    expect(screen.getByText('Unanimous')).toBeInTheDocument();
  });
});
