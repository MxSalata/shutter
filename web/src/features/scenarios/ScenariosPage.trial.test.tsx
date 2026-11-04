import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
import { SCENARIOS_LEAD } from './scenarioText';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';

/** The page as the trial shows it: the recorded cases, answered in the browser. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  notifications.clean();
});
afterAll(() => server.close());

function renderTrial(detail: DetailLevel = 'plain') {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <ScenariosPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Waits for every part of the page that loads: the rows, the guided path, S8's cited entry. */
async function loaded() {
  await screen.findByRole('button', { name: 'Run S2' });
  await screen.findByRole('region', { name: 'Then follow this path' });
  await screen.findByText('citing catalogue entry E7,', { exact: false });
  const s5 = (await screen.findByRole('button', { name: 'Run S5' })).closest('tr')!;
  await within(s5).findByText('Delivered, verified');
}

describe('ScenariosPage in the trial', () => {
  beforeEach(() => resetMock('approver'));

  it("leads with the trial's words, which are not the live system's", async () => {
    renderTrial();
    expect(SCENARIOS_LEAD.trial).not.toBe(SCENARIOS_LEAD.live);
    expect(await screen.findByText(SCENARIOS_LEAD.trial)).toBeInTheDocument();
    expect(screen.queryByText(SCENARIOS_LEAD.live)).not.toBeInTheDocument();
    expect(SCENARIOS_LEAD.trial).not.toMatch(/production/);
  });

  it('lists the guided path as numbered steps, each a title, one sentence and its links, the rest behind More', async () => {
    renderTrial();
    const card = await screen.findByRole('region', { name: 'Then follow this path' });
    const steps = within(card).getAllByRole('listitem');
    expect(steps).toHaveLength(6);
    for (const [i, step] of steps.entries())
      expect(within(step).getByRole('button', { name: `More about step ${i + 1}` })).toHaveAttribute(
        'aria-expanded',
        'false',
      );
    // The links keep their words, which the browser tests follow
    expect(within(steps[0]).getByRole('link', { name: 'Case C-000002' })).toHaveAttribute(
      'href',
      '/cases/C-000002',
    );
    expect(within(steps[2]).getByRole('link', { name: 'Rules and board side by side' })).toHaveAttribute(
      'href',
      '/cases/C-000008?show=compare',
    );
    expect(within(steps[4]).getByRole('link', { name: 'Incident I-000001' })).toBeInTheDocument();
  });

  it('says a run plays from its recording in the browser', async () => {
    renderTrial();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    const run = await within(first).findByRole('button', { name: 'Run S8 in Board mode' });
    // A click without the hover that would open the button's tooltip, which jsdom positions slowly
    fireEvent.click(run);
    expect(await screen.findByText('S8 is playing from its recording in your browser.')).toBeInTheDocument();
    expect(screen.queryByText(/The case appears in a few seconds/)).not.toBeInTheDocument();
  });

  it("says, once a run is done, that its case is the recorded one, with no age, since its times are a recording's", async () => {
    renderTrial();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    fireEvent.click(await within(first).findByRole('button', { name: 'Run S8 in Board mode' }));
    // The mock plays the run over eight seconds; the page reads it as done once the clock has passed them
    const realNow = Date.now;
    Date.now = () => realNow() + 9_000;
    try {
      const done = await screen.findByText(/^S8 played \(Board\)$/, {}, { timeout: 10_000 });
      const alert = done.closest('[role="alert"]')!;
      expect(alert).toHaveTextContent(
        /Its case is C-\d{6}, replayed from the recording, as far as the recording goes: open it from the row below\./,
      );
      expect(alert).not.toHaveTextContent('The production does the rest');
    } finally {
      Date.now = realNow;
    }
  });

  it('keeps the first layer within its word budget, in Plain and in Technical', async () => {
    renderTrial();
    await loaded();
    const plain = layer1WordCount(document.body);
    expect(plain).toBeLessThanOrEqual(PLAIN_BUDGET);
    cleanup();
    resetMock('approver');
    renderTrial('technical');
    await loaded();
    const technical = layer1WordCount(document.body);
    expect(technical).toBeLessThanOrEqual(TECHNICAL_BUDGET);
    // Technical adds the detail without rebuilding the wall of text
    expect(technical).toBeLessThanOrEqual(plain * 1.5);
    expect(technical).toBeGreaterThan(plain);
  });
});
