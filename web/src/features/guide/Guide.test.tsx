import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, Outlet, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import type { CaseDetail } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { bannerForm } from '@/trial/visit';
import CasePage from '@/features/cases/CasePage';
import EvaluationPage from '@/features/evaluation/EvaluationPage';
import ScenariosPage from '@/features/scenarios/ScenariosPage';
import { INITIAL, type GuideProgress } from './controller';
import { APPROVED_FOR_YOU, Guide, REPLAY_DONE } from './Guide';
import { TrialHelpMenu } from './HelpMenu';
import { welcomeActions } from './registry';
import { forgetProgress, GUIDE_KEY, saveProgress } from './storage';
import { useGuide } from './store';

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/**
 * The trial's frame as far as the guide needs it: Help in a header, the guide, and the pages it visits. Tests that do
 * not place a card start on a small page: role queries over a whole screen are slow in jsdom.
 */
function renderApp(path = '/start') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <header>
              <TrialHelpMenu />
            </header>
            <main>
              <Outlet />
            </main>
            <Guide />
          </>
        ),
        children: [
          { path: '/start', element: <h1>Start</h1> },
          { path: '/scenarios', element: <ScenariosPage /> },
          { path: '/cases/:caseId', element: <CasePage /> },
          { path: '/evaluation', element: <EvaluationPage /> },
        ],
      },
    ],
    { initialEntries: [path] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return router;
}

describe('the welcome, by role', () => {
  const can = { operate: true, approve: true, configure: true, scenarios: true, liveAgents: false };
  it('promises only what the role can do', () => {
    expect(welcomeActions(can)).toBe('Approve, run, save or escalate');
    expect(welcomeActions({ ...can, approve: false, configure: false })).toBe('Run or escalate');
    expect(welcomeActions({ ...can, configure: false, scenarios: false })).toBe('Approve or escalate');
  });
});

const stored = () => JSON.parse(localStorage.getItem(GUIDE_KEY) ?? 'null');
const welcome = () => screen.findByRole('dialog', { name: 'Welcome to the Shutter trial' });
const noDialog = () => waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
const card = () => screen.findByRole('region', { name: 'Guide' }, { timeout: 15_000 });
const at = (path: string, more: Partial<GuideProgress> = {}) =>
  useGuide.setState({ progress: { ...INITIAL, at: path, ...more }, phase: 'step', openedAt: Date.now() });
const announced = () => document.querySelector('[data-guide-announcer]');

/** Under reduced motion every movement stands at rest from the start. */
function preferReducedMotion() {
  vi.spyOn(window, 'matchMedia').mockImplementation(
    (query: string) =>
      ({
        matches: query.includes('prefers-reduced-motion'),
        media: query,
        onchange: null,
        addListener: () => {},
        removeListener: () => {},
        addEventListener: () => {},
        removeEventListener: () => {},
        dispatchEvent: () => false,
      }) as MediaQueryList,
  );
}

describe('the guide', () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.clear();
    forgetProgress();
    useGuide.setState({
      progress: INITIAL,
      phase: 'closed',
      snoozed: false,
      approvedForYou: null,
      pointAt: null,
      openedAt: 0,
    });
  });
  afterEach(() => vi.restoreAllMocks());

  it('welcomes a first visit with what Shutter does, what the trial is, and three tours', async () => {
    renderApp();
    const d = await welcome();
    expect(d).toHaveTextContent(
      'When a patient movement fails to reach another system, Shutter finds out why and writes a fix only when it is safe to.',
    );
    expect(d).toHaveTextContent(
      "Mikolaj's Fictional Hospital: a demo hospital with made-up patients, recorded.",
    );
    expect(d).not.toHaveTextContent(/try anything|every action works|it never plays/i);
    const quick = within(d).getByRole('radio', { name: /Quick tour/ });
    expect(quick).toBeChecked();
    expect(quick).toHaveTextContent('9 steps, about 4 min');
    expect(within(d).getByRole('radio', { name: /Every screen/ })).toHaveTextContent(
      '32 steps in 15 chapters',
    );
    expect(within(d).getByRole('radio', { name: /For integration engineers/ })).toHaveTextContent('6 steps');
    expect(within(d).getByRole('button', { name: 'Start the tour' })).toBeInTheDocument();
    expect(within(d).getByRole('button', { name: 'Explore on my own' })).toBeInTheDocument();
    expect(within(d).getByRole('button', { name: "Don't show again" })).toBeInTheDocument();
  });

  it("closes for the visit on Explore on my own, for good on Don't show again, and compacts the banner", async () => {
    renderApp();
    await userEvent.click(within(await welcome()).getByRole('button', { name: 'Explore on my own' }));
    await noDialog();
    expect(stored()).toBeNull();
    expect(useGuide.getState().snoozed).toBe(true);
    expect(bannerForm.get()).toBe('compact');

    act(() => useGuide.setState({ snoozed: false, phase: 'welcome' }));
    await userEvent.click(within(await welcome()).getByRole('button', { name: "Don't show again" }));
    await noDialog();
    expect(stored()).toMatchObject({ version: 2, dismissed: true, at: null });
  });

  it('does not welcome a visit after the tour was dismissed', async () => {
    saveProgress({ ...INITIAL, dismissed: true });
    useGuide.setState({ progress: { ...INITIAL, dismissed: true } });
    renderApp();
    expect(await screen.findByRole('heading', { name: 'Start', level: 1 })).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('places the first step as a card just before its section, focuses its title and announces it', async () => {
    const router = renderApp();
    await userEvent.click(within(await welcome()).getByRole('button', { name: 'Start the tour' }));
    await noDialog();
    await waitFor(() => expect(router.state.location.pathname).toBe('/scenarios'));
    const guide = await card();
    expect(guide).toHaveTextContent('Trial tour · Scenarios');
    expect(guide).toHaveTextContent('Step 1 of 9');
    const title = within(guide).getByRole('heading', { name: 'Three stories to start with', level: 2 });
    await waitFor(() => expect(title).toHaveFocus());
    // The card comes first in the page's order, then the section it is about
    const section = document.querySelector('[data-tour="scenarios"]')!;
    expect(guide.compareDocumentPosition(section) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    await waitFor(() => expect(section).toHaveAttribute('data-tour-active', 'true'));
    expect(stored()).toMatchObject({ scope: 'quick', at: 'scenarios/start' });
    await waitFor(() =>
      expect(announced()).toHaveTextContent('Step 1 of 9, scenarios. Three stories to start with.'),
    );
  });

  it('approves the held S2 case for the reader on Next, and says so on the next card', async () => {
    at('s2/decision');
    const router = renderApp();
    await waitFor(() => expect(router.state.location.pathname).toBe('/cases/C-000002'));
    const guide = await card();
    expect(guide).toHaveTextContent('Step 3 of 9');
    expect(within(guide).getByRole('heading', { name: 'Your turn: approve the fix' })).toBeInTheDocument();
    const sent: unknown[] = [];
    server.events.on('request:start', async ({ request }) => {
      if (request.method === 'POST' && new URL(request.url).pathname.endsWith('/approvals'))
        sent.push(await request.clone().json());
    });
    await userEvent.click(within(guide).getByRole('button', { name: 'Next' }));
    // Through the same call Approve plan makes, with its own comment
    await waitFor(async () => expect((await api.get<CaseDetail>('/cases/C-000002')).state).toBe('resolved'));
    expect(sent).toEqual([expect.objectContaining({ decision: 'approve', comment: APPROVED_FOR_YOU })]);
    server.events.removeAllListeners();
    const nextCard = await screen.findByText('Approved for you, in the trial.', undefined, {
      timeout: 15_000,
    });
    expect(nextCard.closest('[role="region"]')).toHaveTextContent('Step 4 of 9');
    await waitFor(() =>
      expect(announced()).toHaveTextContent(/^Approved for you, in the trial\. Step 4 of 9/),
    );
  });

  it('tells an operator an approver decides, offers no approval on the way, and never says it landed', async () => {
    resetMock('operator');
    const approve = vi.spyOn(api, 'post');
    at('s2/decision');
    renderApp();
    const guide = await card();
    await within(guide).findByRole('heading', { name: 'An approver decides here' });
    expect(within(guide).queryByRole('button', { name: /^Try it/ })).not.toBeInTheDocument();
    await userEvent.click(within(guide).getByRole('button', { name: 'Next' }));
    const heading = await screen.findByRole(
      'heading',
      { name: 'What would be checked' },
      // The whole case page renders first, which is slow in jsdom
      { timeout: 15_000 },
    );
    const nextCard = heading.closest('[role="region"]')!;
    expect(nextCard).toHaveTextContent(/Not approved, so nothing is written yet/);
    expect(nextCard).not.toHaveTextContent(/it landed\./);
    expect(approve).not.toHaveBeenCalled();
    approve.mockRestore();
    resetMock('approver');
  });

  it('points at the control a step invites the reader to try, at rest under reduced motion', async () => {
    preferReducedMotion();
    at('s2/decision');
    renderApp();
    const guide = await card();
    const chip = await within(guide).findByRole('button', { name: 'Try it: press Approve plan' });
    const control = document.querySelector<HTMLElement>('[data-tour-action="approve-plan"]')!;
    expect(control).toBeTruthy();
    // jsdom has no IntersectionObserver, so the control counts as in view: the pointer and halo stand at rest
    const pointer = await screen.findByTestId('guide-try-pointer');
    expect(pointer).toHaveAttribute('data-motion', 'rest');
    expect(pointer).toHaveAttribute('aria-hidden', 'true');
    expect(control).toHaveAttribute('data-tour-try', 'rest');
    expect(guide.querySelector('.guide-notch')).toHaveAttribute('data-motion', 'rest');
    // The chip moves focus to the control
    await userEvent.click(chip);
    expect(control).toHaveFocus();
  });

  it("moves on from the decision step when the replay of the reader's own approval has played, and only for its case", async () => {
    preferReducedMotion();
    at('s2/decision');
    renderApp();
    const guide = await card();
    await within(guide).findByRole('button', { name: 'Try it: press Approve plan' });
    const played = (detail: string) =>
      act(() => {
        window.dispatchEvent(new CustomEvent(REPLAY_DONE, { detail }));
      });
    played('C-000099');
    expect(guide).toHaveTextContent('Step 3 of 9');
    expect(useGuide.getState().progress.at).toBe('s2/decision');
    played('C-000002');
    expect(useGuide.getState().progress.at).toBe('s2/verified');
    // The reader's own hand: the card says nothing of the tour having done it
    expect(useGuide.getState().approvedForYou).toBeNull();
    expect(await screen.findByRole('heading', { name: 'Checked at the bed system' })).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByTestId('guide-try-pointer')).not.toBeInTheDocument());
  });

  it('exits on Escape without finishing, and resumes from the header where it stopped', async () => {
    at('s2/receipt');
    renderApp();
    const guide = await card();
    expect(screen.getByRole('button', { name: 'Tour' })).toHaveTextContent('Tour');
    await waitFor(() => expect(within(guide).getByRole('heading', { level: 2 })).toHaveFocus());
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('region', { name: 'Guide' })).not.toBeInTheDocument());
    expect(useGuide.getState().phase).toBe('closed');
    await waitFor(() =>
      expect(announced()).toHaveTextContent(
        'The tour is closed. Resume tour, in the header, takes you back to it.',
      ),
    );
    // Left part way: the header's button says it can be resumed
    expect(screen.getByRole('button', { name: 'Resume tour' })).toHaveTextContent('Resume tour');
    act(() => useGuide.getState().resume());
    expect(await card()).toHaveTextContent('Step 2 of 9');
  });

  it('keeps its card when Ask opens on the Ask step: docked beside Ask, and Next goes on', async () => {
    preferReducedMotion();
    at('s8/ask');
    const router = renderApp();
    const guide = await card();
    expect(guide).toHaveTextContent('Step 7 of 9');
    expect(
      await within(guide).findByRole('button', { name: 'Try it: open Ask, pick a question' }),
    ).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Ask about this case' }));
    const sheet = await screen.findByRole('region', { name: 'Ask about this case' });
    expect(router.state.location.search).toBe('?ask=1');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    // The same step's card, now in the dock just before the sheet, with no notch pointing down
    await waitFor(() => expect(document.querySelector('[data-guide-dock] [data-guide-card]')).not.toBeNull());
    const docked = screen.getByRole('region', { name: 'Guide' });
    expect(docked).toHaveTextContent('Step 7 of 9');
    expect(docked).toHaveAttribute('data-docked', 'true');
    expect(docked.querySelector('.guide-notch')).toBeNull();
    expect(docked.closest('[data-guide-dock]')!.nextElementSibling).toBe(sheet);
    // Ask is open: the try-it and its pointer have done their work
    await waitFor(() =>
      expect(within(docked).queryByRole('button', { name: /^Try it/ })).not.toBeInTheDocument(),
    );
    expect(screen.queryByTestId('guide-try-pointer')).not.toBeInTheDocument();
    await userEvent.click(within(docked).getByRole('button', { name: 'Next' }));
    await waitFor(
      () => expect(screen.getByRole('region', { name: 'Guide' })).toHaveTextContent('Step 8 of 9'),
      { timeout: 15_000 },
    );
    expect(screen.queryByRole('region', { name: 'Ask about this case' })).not.toBeInTheDocument();
  });

  it('lists the chapters by the navigation groups, the current one marked, and opens one', async () => {
    useGuide.setState({ progress: { ...INITIAL, at: 's8/receipt', completed: ['scenarios'] } });
    renderApp();
    act(() => useGuide.getState().openChapters());
    const d = await screen.findByRole('dialog', { name: 'Choose a chapter' });
    expect(
      within(d)
        .getAllByRole('group')
        .map((g) => g.getAttribute('aria-labelledby')),
    ).toEqual(['guide-group-Operate', 'guide-group-Results', 'guide-group-Configure']);
    expect(within(d).getByRole('button', { name: /^Scenarios 1 step \(finished\)/ })).toBeInTheDocument();
    expect(
      within(d).getByRole('button', { name: /^A fix held back \(S8\) 3 steps Current$/ }),
    ).toBeInTheDocument();
    await userEvent.click(within(d).getByRole('button', { name: /^Evaluation/ }));
    await noDialog();
    expect(useGuide.getState().progress).toMatchObject({ scope: 'quick', at: 'evaluation/headline' });
  });

  it('finishes on the last step with the finish card, and stays closed on the next visit', async () => {
    at('evaluation/headline');
    renderApp();
    const guide = await card();
    expect(guide).toHaveTextContent('Step 9 of 9');
    await userEvent.click(within(guide).getByRole('button', { name: 'Finish' }));
    const finish = await screen.findByRole('heading', { name: 'That is the tour.' });
    const region = finish.closest('[role="region"]') as HTMLElement;
    expect(region).toHaveTextContent(
      "You saw a transfer delivered and verified, a resend that would have overwritten the bed manager's ward held back for a person, and the gate stopping one.",
    );
    expect(within(region).getByRole('button', { name: 'Run S20 yourself' })).toBeInTheDocument();
    expect(within(region).getByRole('button', { name: 'Explore on my own' })).toBeInTheDocument();
    expect(stored()).toMatchObject({ at: null, dismissed: true, completed: ['evaluation'] });
    await waitFor(() => expect(announced()).toHaveTextContent('That is the tour.'));
  });

  it("offers a reader who cannot run scenarios S20's case to see instead of Run S20", async () => {
    resetMock('demo');
    at('evaluation/headline');
    const router = renderApp();
    const guide = await card();
    await userEvent.click(within(guide).getByRole('button', { name: 'Finish' }));
    const finish = await screen.findByRole('heading', { name: 'That is the tour.' });
    const region = finish.closest('[role="region"]') as HTMLElement;
    expect(within(region).queryByRole('button', { name: 'Run S20 yourself' })).not.toBeInTheDocument();
    await userEvent.click(within(region).getByRole('button', { name: 'See the gate stop a fix' }));
    // S20's newest rules case, as the guide's own steps find it
    await waitFor(() => expect(router.state.location.pathname).toBe('/cases/C-000053'));
    expect(useGuide.getState().phase).toBe('closed');
  });

  it("closes the engineers' tour with what that route showed", async () => {
    at('evaluation/rules-differs', { scope: 'engineer' });
    renderApp();
    const guide = await card();
    expect(guide).toHaveTextContent('Step 6 of 6');
    await userEvent.click(within(guide).getByRole('button', { name: 'Finish' }));
    const finish = await screen.findByRole('heading', { name: 'That is the tour.' });
    const region = finish.closest('[role="region"]') as HTMLElement;
    expect(region).toHaveTextContent(
      "You saw the decision receipt as JSON, the gate's reason codes, what each agent cited, S8 beside its Rules only run, the message trace in IRIS, and where Rules only went wrong.",
    );
    expect(region).not.toHaveTextContent('transfer delivered and verified');
  });

  it("starts the engineers' tour with Technical on", async () => {
    useAppearance.setState({ detail: 'plain' });
    act(() => useGuide.getState().begin('engineer'));
    expect(useAppearance.getState().detail).toBe('technical');
    expect(useGuide.getState().progress).toMatchObject({ scope: 'engineer', at: 's2/receipt-json' });
    act(() => useGuide.getState().begin('quick'));
    expect(useAppearance.getState().detail).toBe('technical');
    useAppearance.setState({ detail: 'plain' });
  });

  it('drops its place in memory on sign-out and keeps the one stored on the device', () => {
    const kept = { ...INITIAL, at: 's8/receipt' };
    saveProgress(kept);
    useGuide.setState({ progress: { ...INITIAL, at: 's2/receipt' }, phase: 'step' });
    useGuide.getState().reset();
    expect(useGuide.getState()).toMatchObject({ phase: 'closed', progress: kept });
  });

  it('drops its place on sign-out when the device refuses storage, kept only in memory', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('refused');
    });
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('refused');
    });
    const kept = { ...INITIAL, at: 's2/decision' };
    saveProgress(kept);
    useGuide.setState({ progress: kept, phase: 'step' });
    useGuide.getState().reset();
    expect(useGuide.getState()).toMatchObject({ phase: 'closed', progress: INITIAL });
  });
});
