import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { http, HttpResponse } from 'msw';
import { LOOK_ONLY_DEMO, resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';
import { SCENARIOS_LEAD } from './scenarioText';
import { S8_RULES_DIAGRAM_NOTE, S8_RULES_SEE } from './TryFirst';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';
import definitions from '../../../../fixtures/scenarios.json';

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

function renderTrial(detail: DetailLevel = 'plain', path = '/') {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={[path]}>
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
    // Why it can't be chosen, and the way to it, in the card itself
    expect(
      within(single).getByText(
        "To run it: your own install with a model key, or the judges' sign-in on the online demo.",
      ),
    ).toBeVisible();
    expect(screen.getAllByRole('radio')).toHaveLength(4);
    const policy = screen.getByRole('radio', { name: 'Site policy' });
    await userEvent.click(policy);
    expect(policy).toBeChecked();
    await userEvent.keyboard('{ArrowRight}');
    expect(screen.getByRole('radio', { name: 'Rules only' })).toBeChecked();
    expect(single).not.toBeChecked();
  });

  it("describes all four modes to a role that can't choose, and says the trial has no recording of one", async () => {
    resetMock('demo');
    // The public demo's account as a server before 1.4.4 answered, which ran no scenarios
    server.use(http.get('/api/shutter/me', () => HttpResponse.json(LOOK_ONLY_DEMO)));
    renderTrial();
    const modes = await screen.findByRole('radiogroup', { name: 'Investigation modes' });
    for (const name of ['Board', 'Site policy', 'Single investigator', 'Rules only'])
      expect(within(modes).getByText(name)).toBeInTheDocument();
    expect(within(modes).getByText('Not in the trial: no recording')).toBeInTheDocument();
    expect(within(modes).getByRole('radio', { name: 'Site policy' })).toBeChecked();
    // What it is, in view: the line under the cards speaks only for the chosen mode, and this one can't be chosen
    expect(within(modes).getByText(/One AI Hub agent with the same evidence and tools/)).toBeVisible();
  });

  it("says where the online demo's words apply, and how to get a role that can run one", async () => {
    resetMock('demo');
    server.use(http.get('/api/shutter/me', () => HttpResponse.json(LOOK_ONLY_DEMO)));
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
    expect(within(steps[2]).getByRole('link', { name: 'Rules only and Board side by side' })).toHaveAttribute(
      'href',
      '/cases/C-000008?show=compare',
    );
    expect(within(steps[4]).getByRole('link', { name: 'Incident I-000001' })).toBeInTheDocument();
  });

  it('says under Run mode that S8 in Rules only is exempted on purpose, as its card does', async () => {
    renderTrial('plain', '/?mode=rules');
    await screen.findByRole('region', { name: 'Try these three first' });
    expect(
      screen.getByText(
        "Every Run button below uses it. The mode decides who proposes the plan. In every mode the same gate checks the plan, and a person or the site's policy releases any write.",
      ),
    ).toBeInTheDocument();
    // The exemption is said in Rules only's own card, in view whichever mode is chosen
    expect(
      within(screen.getByRole('radio', { name: 'Rules only' })).getByText(
        'No agents: the baseline. Shutter resends the message unchanged unless the gate objects, as a plain Resend would. In S8 one gate check is lifted on purpose, to show what that writes.',
      ),
    ).toBeVisible();
    expect(document.querySelector('[data-mode-hint]')).toBeNull();
  });

  it('reads all four modes in their cards without choosing any, and says every run here is a recording, Board included', async () => {
    renderTrial();
    const modes = await screen.findByRole('radiogroup', { name: 'Run mode' });
    for (const text of [
      /^Four AI Hub agents\. Three specialists read the sealed evidence at once/,
      /^How a hospital would run it\./,
      /^One AI Hub agent with the same evidence and tools proposes the plan alone, to compare with the board\.$/,
      /^No agents: the baseline\./,
    ])
      expect(within(modes).getByText(text)).toBeVisible();
    // Who proposes is the mode; how a run executes is said apart from it, from the page's own kind
    const how = screen.getByRole('region', { name: 'How a run executes here' });
    expect(within(how).getByText('Browser recording')).toBeInTheDocument();
    expect(how).toHaveTextContent(
      'The mode says who proposes the plan, not how a run executes. Here every run plays a recording in your browser, Board included: no new inference, and nothing reaches IRIS.',
    );
    expect(how).toHaveTextContent(
      "Agents that call a model run on your own install with a model key, and from the judges' sign-in on the online demo.",
    );
    expect(within(how).getByRole('link', { name: /^how to install/ })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter#try-it',
    );
    // The trial never calls itself live
    expect(how).not.toHaveTextContent(/Live model/);
  });

  it("plays S8's card in the mode chosen under Run mode, and says so on its Run", async () => {
    renderTrial('plain', '/?mode=rules');
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    const run = await within(first).findByRole('button', { name: 'Run S8 in Rules only mode' });
    expect(run).toHaveTextContent(/^Run S8 in Rules only$/);
    const card = run.closest<HTMLElement>('[data-first="S8"]')!;
    expect(within(card).getByRole('heading', { name: 'Rules only writes over a ward' })).toBeInTheDocument();
    expect(card).toHaveTextContent(S8_RULES_SEE);
    // The diagram draws how S8 should end (a person decides); the card says so where Rules only writes instead
    const diagram = within(card).getByRole('img', { name: /^S8, Rules only mode, in a diagram:/ });
    expect(diagram).toHaveAccessibleName(/Expected: a person decides, nothing written\.$/);
    const note = within(card).getByText(S8_RULES_DIAGRAM_NOTE);
    expect(note.compareDocumentPosition(diagram) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(S8_RULES_DIAGRAM_NOTE).toBe('Should end: a person decides. Rules only writes instead.');
    expect(
      within(card).getByRole('link', { name: 'Open C-000021, the latest S8 case in Rules only mode' }),
    ).toHaveAttribute('href', '/cases/C-000021');
    // The other two keep Board, and the optional S20 its own mode; their Run says only the scenario
    expect(within(first).getByRole('button', { name: 'Run S2 in Board mode' })).toHaveTextContent(/^Run S2$/);
    expect(within(first).getByRole('button', { name: 'Run S3 in Board mode' })).toHaveTextContent(/^Run S3$/);
    expect(within(first).getByRole('button', { name: 'Run S20 in Rules only mode' })).toHaveTextContent(
      /^Run S20$/,
    );
    fireEvent.click(run);
    expect(await screen.findByText('S8 is playing from its recording in your browser.')).toBeInTheDocument();
    expect(await screen.findByText(/^Playing S8 \(Rules\)$/)).toBeInTheDocument();
  });

  it("follows a change of mode: Board's words and Run for S8 when Board is chosen", async () => {
    renderTrial('plain', '/?mode=rules');
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    await within(first).findByRole('button', { name: 'Run S8 in Rules only mode' });
    fireEvent.click(screen.getByRole('radio', { name: /^Board/ }));
    const run = await within(first).findByRole('button', { name: 'Run S8 in Board mode' });
    expect(run).toHaveTextContent(/^Run S8 in Board$/);
    const card = run.closest<HTMLElement>('[data-first="S8"]')!;
    expect(within(card).getByRole('heading', { name: 'The board withholds a write' })).toBeInTheDocument();
    // In Board the diagram's end is what happens, so it needs no note
    expect(within(card).queryByText(S8_RULES_DIAGRAM_NOTE)).not.toBeInTheDocument();
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

  /** Plays a card's Run to its end: the mock plays a run over eight seconds, read as done once the clock has passed them. */
  async function played(run: string, title: RegExp) {
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    fireEvent.click(await within(first).findByRole('button', { name: run }));
    const realNow = Date.now;
    Date.now = () => realNow() + 9_000;
    try {
      const done = await screen.findByText(title, {}, { timeout: 10_000 });
      return done.closest<HTMLElement>('[role="alert"]')!;
    } finally {
      Date.now = realNow;
    }
  }

  it("says, once a run is done, that it was a recording with no new inference, and opens the run's own case, with no age", async () => {
    renderTrial();
    const alert = await played('Run S8 in Board mode', /^S8 played \(Board\)$/);
    // How it executed, from the page's own kind, never called live: the trial plays recordings in the browser
    expect(within(alert).getByTestId('run-execution')).toHaveTextContent(
      'Browser recordingPlayed from its recording in your browser: no new inference, and nothing reached IRIS.',
    );
    // The next action is the run's own case, found among the recorded cases by scenario and mode
    expect(within(alert).getByRole('link', { name: 'Open its case, C-000008' })).toHaveAttribute(
      'href',
      '/cases/C-000008',
    );
    // Never the Cases list
    expect(within(alert).queryByRole('link', { name: 'Cases' })).not.toBeInTheDocument();
    expect(alert).not.toHaveTextContent('The production does the rest');
    // S8's board case is the one whose trace the trial pictures, and the banner says what that picture is
    expect(alert).toHaveTextContent(
      "In IRIS: Message trace on this case opens a screenshot of an S8 Board case's trace, taken on a test instance, not this case's own session.",
    );
    expect(alert).toHaveTextContent(
      'That is the short route. S20 below shows the approval boundary, and every scenario is listed under it.',
    );
  });

  it("leads from S2's run to its own case, says its trace is a note here and links the one pictured trace as S8's", async () => {
    renderTrial();
    const alert = await played('Run S2 in Board mode', /^S2 played \(Board\)$/);
    expect(within(alert).getByRole('link', { name: 'Open its case, C-000002' })).toHaveAttribute(
      'href',
      '/cases/C-000002',
    );
    // The trial has one picture of a trace, an S8 Board case's: it is labelled and linked as that, never as S2's
    expect(alert).toHaveTextContent(
      "The trial runs in your browser, so this case's Message trace is a note of what it opens on IRIS.",
    );
    expect(
      within(alert).getByRole('link', { name: "a screenshot of an S8 Board case's trace, on C-000008" }),
    ).toHaveAttribute('href', '/cases/C-000008');
    // What comes next is said, and nothing is started: the next card's Run is still to be chosen
    expect(alert).toHaveTextContent('Next on the short route: S3, in its card below.');
    expect(screen.queryByText(/^Playing S3/)).not.toBeInTheDocument();
  });

  it("names the recording there is when the trial has none of the run's mode, and never offers it as the run's case", async () => {
    // S20 is recorded in Rules only alone; a run that names another mode has no case of its own here
    server.use(
      http.get('/api/shutter/scenarios', async () => {
        const recorded = (await import('@/mocks/fixtures.json')).default;
        return HttpResponse.json({
          scenarios: recorded.scenarios.map((d) => ({ ...d, latestCase: null })),
          run: {
            scenario: 'S20',
            mode: 'board',
            startedAt: new Date().toISOString(),
            finishedAt: new Date().toISOString(),
            state: 'done',
            files: [],
            timeouts: [],
          },
        });
      }),
    );
    renderTrial();
    const done = await screen.findByText(/^S20 played \(Board\)$/);
    const alert = done.closest<HTMLElement>('[role="alert"]')!;
    expect(alert).toHaveTextContent(
      'The trial has no recording of S20 in Board mode. Its recorded case is C-000053, played in Rules only mode.',
    );
    expect(within(alert).queryByRole('link', { name: /^Open its case/ })).not.toBeInTheDocument();
  });

  it('says how many of the scenarios have recordings here, and that the rest run on an install', async () => {
    renderTrial();
    await loaded();
    const list = screen.getByRole('region', { name: 'Every scenario' });
    const rows = within(list).getAllByRole('button', { name: /^Run S\d+[a-z]?$/ }).length;
    expect(
      within(list).getByText(
        `${rows} of the ${definitions.length} scenarios have recordings here; the rest run on an install.`,
        { exact: false },
      ),
    ).toBeInTheDocument();
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
