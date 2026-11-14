import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { GLOSSARY } from '@/lib/glossary';
import { CASE_STATES } from '@/lib/status';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasePage from './CasePage';

/**
 * Plain view's words for Shutter's own terms on a case (clarity item 6): the stage line names the gate, rehearsal and
 * dispatch stages in words, the outcome says what the gate is, and the receiver's receipt is named apart from Shutter's
 * decision receipt. Each term stays one press away, and Technical keeps the terms as they were.
 */

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

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

const band = () => screen.findByRole('region', { name: 'Outcome' });
const progress = () => screen.findByLabelText("The case's progress");

beforeEach(() => {
  resetMock('approver');
  window.localStorage.removeItem('shutter.outcomeBand');
  useAppearance.setState({ detail: 'plain' });
});

afterEach(() => useAppearance.setState({ detail: 'plain' }));

describe('a blocked case in Plain', () => {
  it('names the stages in words and ties each to its term under What the stages mean', async () => {
    renderCase('C-000016');
    const strip = await progress();
    expect(
      await within(strip).findByRole('button', {
        name: 'Plan and checks: stopped here, show the plan and its checks',
      }),
    ).toBeInTheDocument();
    expect(within(strip).getByText('Test run')).toBeInTheDocument();
    expect(within(strip).getByText('Sending')).toBeInTheDocument();
    for (const term of ['Plan and gate', 'Rehearsal', 'Dispatch'])
      expect(within(strip).queryByText(term)).not.toBeInTheDocument();
    // The terms are one press away, in the disclosure under the strip
    const meaning = screen.getByText(/^Plan and checks: the safety checks \(the gate\)/);
    expect(meaning).toHaveTextContent('Test run: the rehearsal');
    expect(meaning).toHaveTextContent('Sending: the dispatch');
  });

  it('says what stopped the plan, and whose receipt the evidence read', async () => {
    renderCase('C-000016');
    const top = await band();
    expect(
      await within(top).findByText('Sent nothing: the safety checks (the gate) stopped the plan'),
    ).toBeInTheDocument();
    // The reason under it does not say the gate again
    expect(
      within(top).getByText('Blocked: the downstream system already committed this movement.'),
    ).toBeInTheDocument();
    expect(
      within(top).getByText(/its receipt shows it committed this operation, version 1 to 2\.$/),
    ).toBeInTheDocument();
    const links = within(top).getByRole('group', { name: 'The evidence this was read from' });
    expect(within(links).getByRole('button', { name: "Receiver's receipt" })).toBeInTheDocument();
    // Shutter's own record is named apart from it, its definition one press away
    const heading = within(top).getByRole('heading', { name: 'Decision receipt' });
    const term = within(heading).getByText('Decision receipt');
    expect(term).toHaveAccessibleDescription(GLOSSARY['decision-receipt'].definition);
    expect(GLOSSARY['decision-receipt'].definition).toMatch(/Not the receiver's receipt\.$/);
    // The receipt's Gate is a term too
    const gate = within(top).getByText('Gate', { selector: 'dt .term' });
    expect(gate).toHaveAccessibleDescription(GLOSSARY.gate.definition);
  });
});

describe('an escalated case in Plain', () => {
  it("gives the reason a fact of its own and names the receiver's missing receipt", async () => {
    renderCase('C-000008');
    const top = await band();
    expect(await within(top).findByText('Asked a person to decide; sent nothing')).toBeInTheDocument();
    expect(
      within(top).getByText(
        "PAS and the bed manager (BEDMGR) moved the encounter at the same event time, so the times can't say which movement is current.",
      ),
    ).toBeInTheDocument();
    expect(within(top).queryByText(/^Handed to a person;/)).not.toBeInTheDocument();
    expect(
      within(top).getByText(
        /; the receiver has no receipt for this operation; PAS and BEDMGR have the same event time\.$/,
      ),
    ).toBeInTheDocument();
  });
});

describe('a case waiting for approval in Plain', () => {
  it('says the plan passed the safety checks and waits for an approver, and whose receipt is missing', async () => {
    renderCase('C-000002');
    const top = await band();
    expect(
      await within(top).findByText(
        'The plan passed the safety checks (the gate) and waits for a person with the approver role to approve or reject it.',
      ),
    ).toBeInTheDocument();
    expect(
      within(await progress()).getByRole('button', {
        name: 'Approval: waiting for approval, show the approval',
      }),
    ).toBeInTheDocument();
    // The checks still to come, named as the case names them
    expect(within(top).getByText('Checked before sending: the approval, the test run.')).toBeInTheDocument();
    // The receiver's missing receipt is the receiver's, a few lines above Shutter's Decision receipt
    expect(within(top).getByText(/; the receiver has no receipt for this operation\.$/)).toBeInTheDocument();
    expect(within(top).getByRole('heading', { name: 'Decision receipt' })).toBeInTheDocument();
  });
});

describe('the same cases in Technical', () => {
  it('keeps the stage names, the gate and the short chip as they were', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderCase('C-000016');
    const strip = await progress();
    expect(
      await within(strip).findByRole('button', {
        name: 'Plan and gate: stopped here, show the plan and the gate',
      }),
    ).toBeInTheDocument();
    expect(within(strip).getByText('Rehearsal')).toBeInTheDocument();
    expect(within(strip).getByText('Dispatch')).toBeInTheDocument();
    expect(screen.getByText(/^Rehearsal is a dry run of the write at the receiver/)).toBeInTheDocument();
    const top = await band();
    expect(await within(top).findByText('Sent nothing: the gate stopped the plan')).toBeInTheDocument();
    expect(
      within(top).getByText('Blocked by the gate: the downstream system already committed this movement.'),
    ).toBeInTheDocument();
    expect(within(top).getByText(/; it committed this operation, version 1 to 2\.$/)).toBeInTheDocument();
    const links = within(top).getByRole('group', { name: 'The evidence this was read from' });
    expect(within(links).getByRole('button', { name: 'Receipt' })).toBeInTheDocument();
    expect(within(top).getByRole('heading', { name: 'Decision receipt' })).toBeInTheDocument();
  });

  it('keeps the waiting sentence in its terms', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderCase('C-000002');
    expect(
      await within(await band()).findByText(
        'The plan passed the gate and waits for a person with the approver role to approve or reject it.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Checked at dispatch: authorization, rehearsal.')).toBeInTheDocument();
    expect(screen.getByText(/; no receipt for this operation\.$/)).toBeInTheDocument();
  });
});

describe('pending, blocked, failed and completed in words', () => {
  it('gives each state its own word, never colour alone', () => {
    const words = (['awaiting_approval', 'blocked', 'failed', 'resolved', 'escalated'] as const).map(
      (s) => CASE_STATES[s].label,
    );
    expect(new Set(words).size).toBe(words.length);
    for (const w of words) expect(w).toMatch(/\p{L}{3}/u);
  });
});
