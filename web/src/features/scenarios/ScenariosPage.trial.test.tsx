import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
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

  it("shows all four modes, Single investigator can't be chosen and says why, and the arrow keys walk past it", async () => {
    renderTrial();
    const single = await screen.findByRole('radio', { name: 'Single investigator' });
    expect(single).toBeDisabled();
    expect(single).toHaveAccessibleDescription(expect.stringContaining('Not in the trial: no recording'));
    expect(screen.getAllByRole('radio')).toHaveLength(4);
    const policy = screen.getByRole('radio', { name: 'Site policy' });
    await userEvent.click(policy);
    expect(policy).toBeChecked();
    await userEvent.keyboard('{ArrowRight}');
    expect(screen.getByRole('radio', { name: 'Rules only' })).toBeChecked();
    expect(single).not.toBeChecked();
  });

  it("describes all four modes to a role that can't choose, and says the trial has no recording of one", async () => {
    resetMock('judge');
    renderTrial();
    const modes = await screen.findByRole('radiogroup', { name: 'Investigation modes' });
    for (const name of ['Board', 'Site policy', 'Single investigator', 'Rules only'])
      expect(within(modes).getByText(name)).toBeInTheDocument();
    expect(within(modes).getByText('Not in the trial: no recording')).toBeInTheDocument();
    expect(within(modes).getByRole('radio', { name: 'Site policy' })).toBeChecked();
    // What it is, in view: the line under the cards speaks only for the chosen mode, and this one can't be chosen
    expect(within(modes).getByText(/One generalist agent looks at everything/)).toBeVisible();
  });

  it("says where the online demo's words apply, and how to get a role that can run one", async () => {
    resetMock('judge');
    renderTrial();
    const first = await screen.findByRole('region', { name: 'Three to look at first' });
    expect(
      within(first).getByText("Recorded; the online demo's hospital plays these in Site policy mode."),
    ).toBeInTheDocument();
    expect(first).not.toHaveTextContent(/no board is convened/);
    expect(
      screen.getByText(/switch to Operator or Approver in the menu at the top right/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/which the trial and your own instance offer/)).not.toBeInTheDocument();
    expect(screen.getByText(/On the online demo the site's written policy/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: "S8's recording", hidden: true })).toHaveAttribute(
      'href',
      '/cases/C-000008',
    );
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
        /Its case is C-\d{6}, replayed from the recording, as far as the recording goes\./,
      );
      // Its case is a link from here, wherever on the page the Run was pressed
      expect(within(alert as HTMLElement).getByRole('link', { name: /^C-\d{6}$/ })).toHaveAttribute(
        'href',
        expect.stringMatching(/^\/cases\/C-\d{6}$/),
      );
      expect(alert).not.toHaveTextContent('below');
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
