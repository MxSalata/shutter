import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { axeViolations } from '@/test/axe';
import { theme } from '@/theme';
import { BoardPanel } from './BoardPanel';

/** Whether a recording, or only the plan's, fails to load, and the files read: set per test. */
const env = vi.hoisted(() => ({ recordingFails: false, planFails: false, read: [] as string[] }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  TRIAL: true,
}));
vi.mock('./recordedRun', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./recordedRun')>();
  return {
    ...actual,
    findRecording: async (...args: Parameters<typeof actual.findRecording>) => {
      if (env.recordingFails || (env.planFails && args[1].memberCode === 'coordinator'))
        throw new Error('chunk failed');
      const found = await actual.findRecording(...args);
      if (found) env.read.push(found.file);
      return found;
    },
  };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderBoard(caseId = 'C-000008') {
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

/** Opens a member's recording and waits for it. */
async function openRecording(member: string) {
  const card = await screen.findByRole('region', { name: member });
  await userEvent.click(await within(card).findByRole('button', { name: 'Show the recording' }));
  return card;
}

describe('what a board member was sent and did', () => {
  beforeEach(() => {
    resetMock('approver');
    env.recordingFails = false;
    env.planFails = false;
    env.read = [];
  });

  it("offers one button on each specialist's card and the coordinator's, closed", async () => {
    renderBoard();
    await screen.findByRole('region', { name: 'Coordinator' });
    await waitFor(() =>
      expect(screen.getAllByRole('button', { name: 'Show the recording' })).toHaveLength(4),
    );
    const buttons = screen.getAllByRole('button', { name: 'Show the recording' });
    for (const b of buttons) expect(b).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByTestId('run-recording')).toBeNull();
  });

  it('says what the recording is, with its own date, case and model, and links its public file', async () => {
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    const panel = await within(card).findByRole('region', { name: 'What this agent was sent and did' });
    const proof = within(panel).getByTestId('recording-proof');
    expect(proof).toHaveTextContent(
      'Recorded live on 25 Oct 2026 as case C-000112 on claude-opus-5-5; no model was called now. This trial shows it as C-000008.',
    );
    expect(within(proof).getByRole('link', { name: /Its public file/ })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/fixtures/records/scenario-S8-ENC-1008-transfer-encounter-1.json',
    );
    expect(within(panel).getByTestId('recording-limits')).toHaveTextContent(
      'This is what it read and called, not its reasoning. Its 15,356 tokens in and 895 out are for the whole run, not per call.',
    );
    expect(within(panel).getByTestId('recording-limits')).toHaveTextContent(
      'The encounter and patient appear as per-case stand-ins (ENC-T1, MRN-T1), not their real ids, as the model received them.',
    );
    expect(within(panel).getByTestId('recording-last-message')).toHaveTextContent(
      /^I recommended escalating case C-000112/,
    );
  });

  it("keeps the catalogue's advice in view, and who dissented, from the recording", async () => {
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    const line = await within(card).findByTestId('recording-catalogue');
    expect(line).toHaveTextContent(
      "The request includes the catalogue's match and its preferred outcome, as advice: E7 Two sources at the same time: escalate.",
    );
    await within(line).findByText(/The coordinator kept Conformance's dissent: resend \(0\.8\): MSG00802/);
  });

  it('adds no dissent where the plan kept none', async () => {
    renderBoard('C-000002');
    const card = await openRecording('Encounter Integrity');
    const line = await within(card).findByTestId('recording-catalogue');
    await waitFor(() => expect(line).toHaveTextContent('as advice'));
    expect(within(line).queryByText(/kept .* dissent/)).toBeNull();
  });

  it("reads the dissent from the run's own pass: none on S7's first round, Conformance's on its second", async () => {
    renderBoard('C-000007');
    const [first, second] = await screen.findAllByRole('region', { name: 'Conformance' });
    await userEvent.click(await within(first).findByRole('button', { name: 'Show the recording' }));
    const line = await within(first).findByTestId('recording-catalogue');
    await waitFor(() => expect(env.read).toContain('scenario-S7-ENC-1007-transfer-coordinator-1.json'));
    expect(env.read).not.toContain('scenario-S7-ENC-1007-transfer-coordinator-1-round2.json');
    expect(within(line).queryByText(/kept .* dissent/)).toBeNull();
    await userEvent.click(within(second).getByRole('button', { name: 'Show the recording' }));
    await within(second).findByText(/The coordinator kept Conformance's dissent: resend \(0\.85\)/);
    expect(within(line).queryByText(/kept .* dissent/)).toBeNull();
  });

  it("gives the catalogue's own reason after its preferred outcome, so none is not read as no outcome", async () => {
    renderBoard('C-000001');
    const none = await within(await openRecording('Encounter Integrity')).findByTestId('recording-catalogue');
    expect(none).toHaveTextContent(
      'E1 Superseded by a later transfer: none. A later transfer was applied for the encounter',
    );
  });

  it('says so quietly when only the plan cannot be read, and keeps the rest of the panel', async () => {
    env.planFails = true;
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    const line = await within(card).findByTestId('recording-plan-unavailable');
    expect(line).toHaveTextContent('any dissent it kept is missing from this panel');
    expect(within(line).getByRole('link', { name: /public recordings/ })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/tree/main/fixtures/records',
    );
    expect(within(card).getByTestId('recording-catalogue')).toHaveTextContent('E7');
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('adds no such line when the plan was read', async () => {
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    await within(card).findByText(/The coordinator kept Conformance's dissent/);
    expect(within(card).queryByTestId('recording-plan-unavailable')).toBeNull();
  });

  it("opens each part from closed, GetWardState's result whole", async () => {
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    const steps = await within(card).findByRole('button', { name: 'What it did: 4 tool calls' });
    for (const name of ['Its instructions', 'Its request', 'What it did: 4 tool calls'])
      expect(within(card).getByRole('button', { name })).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(steps);
    expect(steps).toHaveAttribute('aria-expanded', 'true');
    const panel = within(card).getByTestId('run-recording');
    const ward = panel.querySelector('[data-tool="GetWardState"]')!;
    expect(ward).toHaveTextContent('"ward": "WARD-C"');
    expect(ward).toHaveTextContent('"version": 2');
    expect(panel.querySelector('[data-tool="search_lifecycle"]')).toHaveTextContent('ELS-2.5');
    expect(await axeViolations(card)).toEqual([]);
  });

  it("opens on the coordinator's card, with the specialists' findings in its request", async () => {
    renderBoard();
    const card = await openRecording('Coordinator');
    const panel = await within(card).findByTestId('run-recording');
    expect(within(panel).getByTestId('recording-proof')).toHaveTextContent('as case C-000112');
    expect(panel).toHaveTextContent('"findings"');
    expect(panel).toHaveTextContent("Read the specialists' findings");
  });

  it('says it quietly when the recording cannot be read, never as an error', async () => {
    env.recordingFails = true;
    renderBoard();
    const card = await openRecording('Encounter Integrity');
    const link = await within(card).findByRole('link', { name: /public recordings/ });
    expect(link).toHaveAttribute('href', 'https://github.com/MxSalata/shutter/tree/main/fixtures/records');
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByRole('region', { name: 'Coordinator' })).toBeInTheDocument();
  });
});
