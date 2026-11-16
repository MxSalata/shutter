import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { DEMO_LOCKED } from '@/api/saveLocked';
import { AssistantFrame } from '@/features/assistant/AssistantSurface';
import { HeaderAssistantButton } from '@/features/assistant/HeaderAssistantButton';
import { resetAssistantForTests } from '@/features/assistant/store';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { recordedSiteProfile } from '@/mocks/profile';
import { axeViolations } from '@/test/axe';
import { theme } from '@/theme';
import SiteProfilePage from '../SiteProfilePage';
import { questionById } from './fields';
import SetupPage from './SetupPage';
import { isDirty, resetSetupForTests, useSetup } from './setupStore';

/**
 * Set up the site, slice 1a: one receiver from its name to the existing review with the page's own controls, Ask
 * Shutter explaining through the page question route, and nothing stored but by the review's save.
 */

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return env.trial;
  },
}));

const BASE = '/api/shutter';
const recorded = recordedSiteProfile()!;
let requests: { method: string; path: string; body: Record<string, unknown> | null }[] = [];
const writes = () => requests.filter((r) => r.method !== 'GET');
const puts = () => requests.filter((r) => r.method === 'PUT');

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  resetSetupForTests();
  resetAssistantForTests();
  notifications.clean();
  env.trial = false;
  requests = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    requests.push({
      method: request.method,
      path: new URL(request.url).pathname,
      body:
        request.method === 'GET'
          ? null
          : ((await request
              .clone()
              .json()
              .catch(() => null)) as Record<string, unknown> | null),
    });
  });
});

function renderApp(path = '/site-setup') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <header>
              <HeaderAssistantButton />
            </header>
            <main id="main">
              <AssistantFrame />
            </main>
          </>
        ),
        children: [
          { path: '/site-setup', element: <SetupPage /> },
          { path: '/site-profile', element: <SiteProfilePage /> },
          { path: '/home', element: <h1>Home</h1> },
        ],
      },
    ],
    { initialEntries: [path] },
  );
  const view = render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return { router, ...view };
}

const card = (name: string) => within(screen.getByRole('region', { name }));
const KIND = 'What kind of system is it?';
const TIER = 'Its tier';
const NAME = 'Which receiver? Name it by its production item.';

/** A receiver added and described through the page's controls, as far as its tier. */
async function describeBedBoard(user: ReturnType<typeof userEvent.setup>, name = 'Bed Board') {
  await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
  await user.type(screen.getByRole('textbox', { name: 'Production item' }), name);
  await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
  await user.type(screen.getByRole('textbox', { name: /What it does/ }), 'the ward whiteboard');
  await user.click(screen.getByRole('button', { name: 'Next question' }));
  await user.click(card(KIND).getByRole('radio', { name: /Current state/ }));
  await user.click(card(KIND).getByRole('button', { name: 'Next question' }));
  await user.click(card(TIER).getByRole('radio', { name: /2, operations/ }));
  await user.click(card(TIER).getByRole('button', { name: 'Next question' }));
}

/** The rest of the checklist: two questions left for now, cancels and merges answered no. */
async function finishChecklist(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole('button', { name: 'Leave for now' }));
  await user.click(screen.getByRole('button', { name: 'Leave for now' }));
  await user.click(screen.getByRole('button', { name: 'It accepts neither' }));
  await user.click(screen.getByRole('button', { name: 'Done' }));
}

/** A draft with one receiver added, made in the store as the page's controls make it. */
function draftInStore(baseVersion = recorded.version) {
  act(() => {
    const s = useSetup.getState();
    s.open(recorded);
    const rid = s.addReceiver();
    s.setKey(rid, 'name', 'Bed Board');
    s.setKey(rid, 'category', 'current_state');
    s.setKey(rid, 'tier', 2);
    useSetup.getState().handOver();
    if (baseVersion !== recorded.version)
      useSetup.setState({ handover: { ...useSetup.getState().handover!, baseVersion } });
  });
}

describe('Set up the site', () => {
  it('says what the page does, where it stands, and that Ask Shutter reads no typed answer here', async () => {
    renderApp();
    expect(await screen.findByRole('heading', { name: 'Set up the site', level: 1 })).toBeInTheDocument();
    // Off unless the site's approver switched it on: the page says so, and offers no box for a typed answer
    expect(await screen.findByTestId('setup-ask-shutter-does')).toHaveTextContent(
      'Ask Shutter explains each question here. It does not read typed answers: reading typed answers is switched off in the site profile (question 11, What the model sees).',
    );
    const band = within(await screen.findByRole('region', { name: 'Where this page stands' }));
    expect(band.getByText(new RegExp(`version ${recorded.version}`))).toBeInTheDocument();
    expect(
      band.getByText(/It does not read typed answers: that is switched off in the site profile\./),
    ).toBeInTheDocument();
    expect(band.getByText('You can save, through the review.')).toBeInTheDocument();
    const list = within(screen.getByRole('list', { name: 'The receivers in this draft' }));
    expect(list.getByText('Downstream Out')).toBeInTheDocument();
    expect(list.getAllByText(': in force')).toHaveLength(recorded.profile.receivers.length);
    // No promise that no name reaches the model: the page says only what Ask Shutter does
    expect(document.body.textContent).not.toMatch(/no name (is sent|reaches)/i);
  });

  it('takes a receiver from its name to the existing review, and an approver saves the next version', async () => {
    const user = userEvent.setup();
    renderApp();
    await describeBedBoard(user);
    // The consequence beside the answer is the page's own line
    expect(card(KIND).getByText(/^You: Current state$/)).toBeInTheDocument();
    await finishChecklist(user);
    const summary = card('Summary: Bed Board');
    expect(within(summary.getByRole('list', { name: 'Not answered' })).getAllByRole('listitem')).toHaveLength(
      2,
    );
    expect(
      within(summary.getByRole('list', { name: 'What Shutter will do here, in short' })).getByText(
        /the gate blocks every write\. Shutter investigates and sends nothing\./,
      ),
    ).toBeInTheDocument();
    expect(puts()).toEqual([]);
    await user.click(summary.getByRole('button', { name: 'Review and save…' }));
    // The Site profile page's own review opens at once on the draft
    const dialog = within(
      await screen.findByRole('dialog', { name: `Save version ${recorded.version + 1} of the site profile` }),
    );
    expect(dialog.getByText('Receiver added: Bed Board')).toBeInTheDocument();
    await user.click(dialog.getByRole('button', { name: `Save version ${recorded.version + 1}` }));
    expect(await screen.findByText(`Version ${recorded.version + 1} saved`)).toBeInTheDocument();
    expect(puts()).toHaveLength(1);
    const body = puts()[0].body as { expectedVersion: number; receivers: Record<string, unknown>[] };
    expect(puts()[0].path).toBe(`${BASE}/site-profile`);
    expect(body.expectedVersion).toBe(recorded.version);
    expect(body.receivers.at(-1)).toEqual({
      name: 'Bed Board',
      system: 'the ward whiteboard',
      category: 'current_state',
      tier: 2,
      cancels: false,
      merges: false,
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    });
    // Nothing but the review's save wrote anything
    expect(writes()).toHaveLength(1);
    // The saved version is the one Set up the site starts from
    await waitFor(() => expect(useSetup.getState().base?.version).toBe(recorded.version + 1));
    expect(isDirty(useSetup.getState())).toBe(false);
  });

  it('opens the review on arrival, shows the band on Cancel with focus on it, and goes back with the draft', async () => {
    const user = userEvent.setup();
    draftInStore();
    renderApp('/site-profile');
    const dialog = await screen.findByRole('dialog', { name: /^Save version/ });
    await waitFor(() => expect(dialog.contains(document.activeElement)).toBe(true));
    await user.click(within(dialog).getByRole('button', { name: 'Cancel' }));
    const band = within(await screen.findByRole('region', { name: 'A draft from Set up the site' }));
    await waitFor(() =>
      expect(band.getByRole('heading', { name: 'A draft from Set up the site' })).toHaveFocus(),
    );
    const row = within(band.getByRole('row', { name: /Bed Board: kind of system/ }));
    expect(row.getByText('not in the profile')).toBeInTheDocument();
    expect(row.getByText('Current state')).toBeInTheDocument();
    expect(band.getByText('Receiver added: Bed Board')).toBeInTheDocument();
    expect(band.getByText(/Nothing is saved until an approver reviews and saves it\./)).toBeInTheDocument();
    // An answer changed on the form goes back with the reader, as the person's own
    await user.click(
      within(screen.getByRole('group', { name: /Receiver \d: Bed Board/ })).getByRole('radio', {
        name: /3, clinical safety/,
      }),
    );
    await user.click(band.getByRole('button', { name: 'Back to Set up the site' }));
    expect(await screen.findByRole('heading', { name: 'Set up the site', level: 1 })).toBeInTheDocument();
    expect(await screen.findByText(/^You: Tier 3, clinical safety$/)).toBeInTheDocument();
    expect(puts()).toEqual([]);
  });

  it('pre-fills nothing when the stored version moved while the draft was made', async () => {
    draftInStore(recorded.version - 1);
    renderApp('/site-profile');
    const band = within(await screen.findByRole('region', { name: 'A draft from Set up the site' }));
    expect(band.getByText(/so nothing was\s+pre-filled/)).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Unsaved changes' })).not.toBeInTheDocument();
    expect(band.queryByRole('button', { name: 'Review and save…' })).not.toBeInTheDocument();
  });

  it('stops the review at an unanswered kind, then at a name another receiver has, on the question itself', async () => {
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Downstream Out');
    const bar = () => within(screen.getByRole('region', { name: 'Unsaved changes' }));
    await user.click(bar().getByRole('button', { name: 'Review and save…' }));
    expect(bar().getByRole('alert')).toHaveTextContent('Answer the kind of Downstream Out before review');
    await waitFor(() => expect(screen.getByRole('heading', { name: KIND })).toHaveFocus());
    expect(card(KIND).getByText('Answer the kind of Downstream Out before review')).toBeInTheDocument();
    await user.click(card(KIND).getByRole('radio', { name: /Orders and results/ }));
    // The problem was about the draft as it was
    expect(bar().queryByRole('alert')).not.toBeInTheDocument();
    await user.click(bar().getByRole('button', { name: 'Review and save…' }));
    expect(bar().getByRole('alert')).toHaveTextContent('Answer the tier of Downstream Out before review');
    await user.click(card(TIER).getByRole('radio', { name: /3, clinical safety/ }));
    await user.click(bar().getByRole('button', { name: 'Review and save…' }));
    expect(bar().getByRole('alert')).toHaveTextContent('another receiver already has this name');
    await waitFor(() => expect(screen.getByRole('heading', { name: NAME })).toHaveFocus());
    expect(screen.getByRole('textbox', { name: 'Production item' })).toBeInvalid();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(writes()).toEqual([]);
  });

  it('discards the draft after a confirmation, with nothing sent', async () => {
    const user = userEvent.setup();
    renderApp();
    await describeBedBoard(user);
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Discard the draft',
      }),
    );
    const dialog = within(await screen.findByRole('dialog', { name: 'Discard this draft?' }));
    expect(dialog.getByText('Nothing has been saved, and nothing will be.')).toBeInTheDocument();
    await user.click(dialog.getByRole('button', { name: 'Discard the draft' }));
    expect(await screen.findByRole('heading', { name: 'Choose a receiver' })).toBeInTheDocument();
    expect(screen.queryByText(/Bed Board/)).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Unsaved changes' })).not.toBeInTheDocument();
    expect(useSetup.getState().draft).toEqual(recorded.profile);
    expect(writes()).toEqual([]);
  });

  it('shows a receiver in force with every answer, changed only by the controls', async () => {
    const user = userEvent.setup();
    renderApp('/site-setup?receiver=Downstream%20Out');
    const tier = await screen.findByRole('region', { name: TIER });
    expect(
      within(tier).getByText(`In force, version ${recorded.version}: Tier 2, operations`),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Leave for now' })).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Summary: Downstream Out' })).toBeInTheDocument();
    await user.click(within(tier).getByRole('button', { name: 'Change: Tier' }));
    await user.click(within(tier).getByRole('radio', { name: /3, clinical safety/ }));
    await user.click(within(tier).getByRole('button', { name: 'Done' }));
    expect(within(tier).getByText('You: Tier 3, clinical safety')).toBeInTheDocument();
    expect(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByText('1 change'),
    ).toBeInTheDocument();
    // Its name is the form's to change
    await user.click(card(NAME).getByRole('button', { name: 'Change: Production item' }));
    expect(card(NAME).getByText(/renamed or removed on the/)).toBeInTheDocument();
    expect(card(NAME).queryByRole('textbox')).not.toBeInTheDocument();
  });

  it.each([
    ['approver', 'You can save, through the review.'],
    ['operator', /^Only an approver saves here: /],
    ['demo', DEMO_LOCKED],
    ['judge', DEMO_LOCKED],
  ] as const)('tells the %s what a save needs', async (role, words) => {
    resetMock(role);
    renderApp();
    const band = within(await screen.findByRole('region', { name: 'Where this page stands' }));
    expect(band.getByText(words)).toBeInTheDocument();
  });

  it("keeps the demo's Save locked in the review, with the note that says why, and sends nothing", async () => {
    resetMock('demo');
    const user = userEvent.setup();
    renderApp();
    await describeBedBoard(user);
    const bar = within(screen.getByRole('region', { name: 'Unsaved changes' }));
    expect(bar.getByText(DEMO_LOCKED)).toBeInTheDocument();
    await user.click(bar.getByRole('button', { name: 'Review and save…' }));
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    const save = dialog.getByRole('button', { name: /^Save version/ });
    expect(save).toHaveAttribute('aria-disabled', 'true');
    expect(save).toHaveAccessibleDescription(DEMO_LOCKED);
    await user.click(save);
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(writes()).toEqual([]);
  });

  it('asks the page question route why a question matters, and writes nothing to the draft', async () => {
    const answer = 'The kind decides what an overtaken failure gets at this receiver.';
    server.use(
      http.post(`${BASE}/page-questions`, () =>
        HttpResponse.json(
          { questionId: 'P-000201', page: 'site-setup', state: 'pending', askedBy: 'approver' },
          { status: 202 },
        ),
      ),
      http.get(`${BASE}/page-questions/:qid`, () =>
        HttpResponse.json({
          questionId: 'P-000201',
          tier: 'page',
          page: 'site-setup',
          question: 'q',
          state: 'answered',
          askedBy: 'approver',
          askedAt: '2026-11-15T10:00:00Z',
          answeredAt: '2026-11-15T10:00:09Z',
          error: null,
          mode: 'live',
          model: 'claude-opus-5-5',
          costUsd: 0.004,
          ensMessageId: '4321',
          answer: { answer, cites: ['page'], confidence: 'high' },
        }),
      ),
    );
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
    await user.click(screen.getByRole('button', { name: 'Next question' }));
    await user.click(screen.getByRole('button', { name: 'Leave for now' }));
    const before = JSON.stringify(useSetup.getState().draft);
    await user.click(card(KIND).getByRole('button', { name: 'Why does this matter?' }));
    expect(await card(KIND).findByText(answer)).toBeInTheDocument();
    expect(card(KIND).getByText(/Answered live by the Explain agent on IRIS AI Hub/)).toBeInTheDocument();
    const posts = requests.filter((r) => r.method === 'POST');
    expect(posts).toHaveLength(1);
    expect(posts[0].path).toBe(`${BASE}/page-questions`);
    expect(posts[0].body).toMatchObject({
      page: 'site-setup',
      context: {
        page: 'site-setup',
        title: 'Set up the site',
        focus: { question: KIND, answer: 'Not answered', consequence: questionById('category').unanswered },
      },
    });
    expect(String(posts[0].body?.question)).toMatch(/Explain; do not recommend one\.$/);
    expect(JSON.stringify(useSetup.getState().draft)).toBe(before);
  });

  it.each([
    ['demo', "Live answers need the judges' account."],
    ['approver', null],
  ] as const)(
    'explains in writing where no live answer is given (%s), and the control still answers',
    async (role, why) => {
      resetMock(role);
      // A live question that the server refuses or fails: the written explanation stands
      if (!why)
        server.use(
          http.post(`${BASE}/page-questions`, () =>
            HttpResponse.json({ error: 'question_failed', detail: 'The run failed' }, { status: 500 }),
          ),
        );
      const user = userEvent.setup();
      renderApp();
      await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
      await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
      await user.click(screen.getByRole('button', { name: 'Next question' }));
      await user.click(screen.getByRole('button', { name: 'Leave for now' }));
      await user.click(card(KIND).getByRole('button', { name: 'Why does this matter?' }));
      expect(await card(KIND).findByText(questionById('category').written)).toBeVisible();
      if (why) {
        expect(card(KIND).getByText(why)).toBeInTheDocument();
        expect(requests.filter((r) => r.method === 'POST')).toEqual([]);
      }
      await user.click(card(KIND).getByRole('radio', { name: /History of record/ }));
      expect(useSetup.getState().draft?.receivers.at(-1)?.category).toBe('history_of_record');
      expect(puts()).toEqual([]);
    },
  );

  it("goes to Ask Shutter in the page from the header, with no panel, and labels the trial's sample answers", async () => {
    env.trial = true;
    const user = userEvent.setup();
    renderApp();
    await screen.findByRole('heading', { name: 'Choose a receiver' });
    await user.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const ask = within(await screen.findByRole('region', { name: 'Ask Shutter about this page' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    await user.click(await ask.findByRole('button', { name: 'What does this page save?' }));
    expect(
      await ask.findByText(/Nothing by itself\. The page keeps a draft in this browser tab/),
    ).toBeInTheDocument();
    expect(ask.getByText(/Example \(sample data\)/)).toBeInTheDocument();
    expect(puts()).toEqual([]);
  });

  it('works the two panes as tabs by keyboard, with no accessibility violation in either', async () => {
    const user = userEvent.setup();
    const { container } = renderApp('/site-setup?receiver=Records%20Out');
    const tabs = within(await screen.findByRole('tablist', { name: 'The conversation and the draft' }));
    expect(tabs.getByRole('tab', { name: 'Conversation' })).toHaveAttribute('aria-selected', 'true');
    expect(await axeViolations(container)).toEqual([]);
    act(() => tabs.getByRole('tab', { name: 'Conversation' }).focus());
    await user.keyboard('{ArrowRight}');
    expect(tabs.getByRole('tab', { name: 'Draft' })).toHaveAttribute('aria-selected', 'true');
    const effects = within(screen.getByRole('list', { name: 'What Shutter will do here' }));
    expect(effects.getByText('Overtaken failure: asks a person to correct by hand.')).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { name: /declared by the site; Shutter has not checked these/ }),
    ).toBeVisible();
    expect(await axeViolations(container)).toEqual([]);
    // Edit goes to the question's card, in the other tab
    await user.click(screen.getByRole('button', { name: 'Edit: Tier' }));
    expect(tabs.getByRole('tab', { name: 'Conversation' })).toHaveAttribute('aria-selected', 'true');
    await waitFor(() => expect(screen.getByRole('heading', { name: TIER })).toHaveFocus());
    expect(card(TIER).getByRole('radio', { name: /2, operations/ })).toBeChecked();
  });

  it('asks once before leaving with changes, and not at all for the hand-over to the review', async () => {
    const user = userEvent.setup();
    const { router } = renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
    act(() => void router.navigate('/home'));
    const dialog = within(await screen.findByRole('dialog', { name: 'Leave Set up the site?' }));
    await user.click(dialog.getByRole('button', { name: 'Stay' }));
    expect(screen.getByRole('heading', { name: 'Set up the site', level: 1 })).toBeInTheDocument();
    act(() => void router.navigate('/home'));
    await user.click(
      within(await screen.findByRole('dialog', { name: 'Leave Set up the site?' })).getByRole('button', {
        name: 'Leave',
      }),
    );
    expect(await screen.findByRole('heading', { name: 'Home' })).toBeInTheDocument();
    // The draft is still this tab's
    expect(useSetup.getState().draft?.receivers.at(-1)?.name).toBe('Bed Board');
    expect(writes()).toEqual([]);
  });
});
