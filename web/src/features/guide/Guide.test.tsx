import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, Outlet, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from '@/features/cases/CasePage';
import EvaluationPage from '@/features/evaluation/EvaluationPage';
import ScenariosPage from '@/features/scenarios/ScenariosPage';
import { INITIAL } from './controller';
import { Guide } from './Guide';
import { HelpMenu } from './HelpMenu';
import { forgetProgress, GUIDE_KEY, saveProgress } from './storage';
import { useGuide } from './store';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/**
 * The app's frame as far as the guide needs it: Help in a header, the guide, and the pages it visits. Tests that do
 * not show a section start on a small page: role queries over a whole screen are slow in jsdom.
 */
function renderApp(path = '/start') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <header>
              <HelpMenu />
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

const stored = () => JSON.parse(localStorage.getItem(GUIDE_KEY) ?? 'null');
const dialog = () => screen.findByRole('dialog');
const noDialog = () => waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());

async function startQuick(path?: string) {
  renderApp(path);
  await userEvent.click(await within(await dialog()).findByRole('button', { name: 'Start guide' }));
  expect(await within(await dialog()).findByText('Step 1 of 3 · Scenarios')).toBeInTheDocument();
}

/**
 * Help's items, as the menu calls them. Mantine's menu takes tens of seconds to position itself in jsdom, so the
 * menu itself is opened in the end-to-end tests; here the header only has to offer it.
 */
async function help(item: 'Resume guide' | 'Restart guide' | 'Choose a chapter') {
  expect(screen.getByRole('button', { name: 'Help' })).toBeInTheDocument();
  const s = useGuide.getState();
  act(() =>
    item === 'Resume guide' ? s.resume() : item === 'Restart guide' ? s.openWelcome() : s.openChapters(),
  );
}

describe('the guide', () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.clear();
    forgetProgress();
    useGuide.setState({ progress: INITIAL, phase: 'closed', snoozed: false, shownAt: 0 });
  });
  afterEach(() => vi.restoreAllMocks());

  it('welcomes a first visit, read only, with the release wording and a choice of scope', async () => {
    renderApp();
    const d = await dialog();
    expect(within(d).getByRole('heading', { name: 'Welcome to Shutter' })).toBeInTheDocument();
    expect(d).toHaveTextContent(
      'it never plays a scenario, approves, dispatches, saves configuration or sends mail',
    );
    expect(d).toHaveTextContent(
      "Every write passes the gate, then a person, or the site's written policy, releases it",
    );
    expect(within(d).getByRole('radio', { name: /Quick demonstration/ })).toBeChecked();
    expect(within(d).getByRole('radio', { name: /All sections/ })).not.toBeChecked();
    expect(within(d).getByRole('button', { name: 'Not now' })).toBeInTheDocument();
    expect(within(d).getByRole('button', { name: "Don't show again" })).toBeInTheDocument();
  });

  it("closes for the visit on Not now, and for good on Don't show again", async () => {
    renderApp();
    await userEvent.click(await within(await dialog()).findByRole('button', { name: 'Not now' }));
    await noDialog();
    // Nothing is stored: the next visit welcomes again
    expect(stored()).toBeNull();
    expect(useGuide.getState().snoozed).toBe(true);

    useGuide.setState({ snoozed: false, phase: 'welcome' });
    await userEvent.click(await within(await dialog()).findByRole('button', { name: "Don't show again" }));
    await noDialog();
    expect(stored()).toMatchObject({ version: 1, dismissed: true, chapter: null });
  });

  it('does not welcome a visit after the guide was dismissed', async () => {
    localStorage.setItem(GUIDE_KEY, JSON.stringify({ ...INITIAL, dismissed: true }));
    useGuide.setState({ progress: { ...INITIAL, dismissed: true } });
    renderApp();
    expect(await screen.findByRole('heading', { name: 'Start', level: 1 })).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('steps with Next and Back, and keeps the place on the device', async () => {
    await startQuick();
    const d = await dialog();
    expect(within(d).getByRole('button', { name: 'Back' })).toBeDisabled();
    await userEvent.click(within(d).getByRole('button', { name: 'Next' }));
    expect(await within(d).findByText('Step 2 of 3 · Scenarios')).toBeInTheDocument();
    expect(within(d).getByRole('heading', { name: 'Who makes the proposal' })).toBeInTheDocument();
    expect(stored()).toMatchObject({ scope: 'quick', chapter: 'scenarios', step: 1 });
    await userEvent.click(within(d).getByRole('button', { name: 'Back' }));
    expect(await within(d).findByText('Step 1 of 3 · Scenarios')).toBeInTheDocument();
    // The announcement is short: the step, never the page
    await waitFor(() =>
      expect(document.querySelector('[data-guide-announcer]')).toHaveTextContent(
        'Step 1 of 3 · Scenarios: Start with S2, then S8',
      ),
    );
  });

  it('shows a section: the dialog closes, focus goes to its heading and Continue guide follows it', async () => {
    await startQuick('/scenarios');
    await userEvent.click(within(await dialog()).getByRole('button', { name: 'Show this section' }));
    await noDialog();
    const heading = screen.getByRole('heading', { name: 'Scenarios', level: 1 });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(heading).toHaveAttribute('tabindex', '-1');
    expect(heading.closest('[data-tour]')).toHaveAttribute('data-tour-active', 'true');
    const guide = screen.getByRole('region', { name: 'Guide' });
    expect(guide).toHaveTextContent('Step 1 of 3 · Scenarios');
    // Continue guide is the next stop after the heading
    expect(heading.compareDocumentPosition(guide) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    await userEvent.click(within(guide).getByRole('button', { name: 'Continue guide' }));
    expect(await within(await dialog()).findByText('Step 1 of 3 · Scenarios')).toBeInTheDocument();
    await waitFor(() => expect(heading.closest('[data-tour]')).not.toHaveAttribute('data-tour-active'));
  });

  it("finds the case through the API and shows the section the step names: S8's kept dissent", async () => {
    useGuide.setState({ progress: { ...INITIAL, chapter: 's8', step: 1 }, phase: 'step' });
    const router = renderApp();
    const d = await dialog();
    expect(within(d).getByText('Step 2 of 3 · S8: a write withheld')).toBeInTheDocument();
    await userEvent.click(await within(d).findByRole('button', { name: 'Show this section' }));
    await waitFor(() => expect(router.state.location.pathname).toBe('/cases/C-000008'));
    // The board sits under the outcome, so no story step needs opening
    expect(router.state.location.search).toBe('');
    await waitFor(() => expect(screen.getByRole('heading', { name: 'The board' })).toHaveFocus());
  });

  it('explains a missing case and offers to skip it, never running the scenario', async () => {
    const posts: string[] = [];
    server.events.on('request:start', ({ request }) => {
      if (request.method !== 'GET') posts.push(`${request.method} ${new URL(request.url).pathname}`);
    });
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    useGuide.setState({ progress: { ...INITIAL, chapter: 's20', step: 0 }, phase: 'step' });
    renderApp();
    const d = await dialog();
    expect(
      await within(d).findByText(
        /There is no S20 case in Rules only mode here yet\. The guide never plays a scenario/,
      ),
    ).toBeInTheDocument();
    expect(within(d).queryByRole('button', { name: 'Show this section' })).not.toBeInTheDocument();
    await userEvent.click(within(d).getByRole('button', { name: 'Skip this step' }));
    expect(
      await within(d).findByText('Step 2 of 2 · S20 in Rules only mode: an approval no longer valid'),
    ).toBeInTheDocument();
    server.events.removeAllListeners();
    expect(posts).toEqual([]);
  });

  it('skips a chapter, exits on Escape without finishing, and resumes from Help where it stopped', async () => {
    await startQuick();
    await userEvent.click(within(await dialog()).getByRole('button', { name: 'Skip chapter' }));
    expect(
      await within(await dialog()).findByText('Step 1 of 4 · S2: a transfer recovered'),
    ).toBeInTheDocument();
    expect(stored()).toMatchObject({ chapter: 's2', step: 0, completed: [] });
    await userEvent.keyboard('{Escape}');
    await noDialog();
    expect(stored()).toMatchObject({ chapter: 's2', completed: [], dismissed: false });
    await help('Resume guide');
    expect(
      await within(await dialog()).findByText('Step 1 of 4 · S2: a transfer recovered'),
    ).toBeInTheDocument();
  });

  it('restarts from the welcome and opens a chapter from the picker', async () => {
    useGuide.setState({ progress: { ...INITIAL, chapter: 's8', step: 2, completed: ['scenarios'] } });
    renderApp();
    await help('Restart guide');
    expect(
      await within(await dialog()).findByRole('heading', { name: 'Welcome to Shutter' }),
    ).toBeInTheDocument();
    await userEvent.click(within(await dialog()).getByRole('radio', { name: /All sections/ }));
    await userEvent.click(within(await dialog()).getByRole('button', { name: 'Start guide' }));
    expect(stored()).toMatchObject({ scope: 'all', chapter: 'scenarios', step: 0, completed: ['scenarios'] });
    await userEvent.keyboard('{Escape}');
    await noDialog();

    await help('Choose a chapter');
    const d = await dialog();
    expect(within(d).getByRole('button', { name: 'Scenarios (finished) (current)' })).toBeInTheDocument();
    await userEvent.click(within(d).getByRole('button', { name: 'Evaluation' }));
    expect(await within(await dialog()).findByText('Step 1 of 2 · Evaluation')).toBeInTheDocument();
  });

  it('finishes after the last step and stays closed on the next visit', async () => {
    useGuide.setState({ progress: { ...INITIAL, chapter: 'evaluation', step: 1 }, phase: 'step' });
    renderApp();
    await userEvent.click(await within(await dialog()).findByRole('button', { name: 'Finish' }));
    await noDialog();
    expect(stored()).toMatchObject({ chapter: null, dismissed: true, completed: ['evaluation'] });
    await waitFor(() =>
      expect(document.querySelector('[data-guide-announcer]')).toHaveTextContent('The guide is finished'),
    );
  });

  it('drops its place in memory on sign-out and keeps the one stored on the device', () => {
    const stored = { ...INITIAL, chapter: 's8', step: 1 };
    saveProgress(stored);
    useGuide.setState({ progress: { ...INITIAL, chapter: 's2' }, phase: 'step' });
    useGuide.getState().reset();
    expect(useGuide.getState()).toMatchObject({ phase: 'closed', progress: stored });
  });

  it('drops its place on sign-out when the device refuses storage, kept only in memory', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('refused');
    });
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('refused');
    });
    const kept = { ...INITIAL, chapter: 's2', step: 1 };
    saveProgress(kept);
    useGuide.setState({ progress: kept, phase: 'step' });
    useGuide.getState().reset();
    expect(useGuide.getState()).toMatchObject({ phase: 'closed', progress: INITIAL });
  });
});
