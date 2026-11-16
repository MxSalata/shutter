import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, renderHook, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { SIGNED_OUT, useSignIn } from '@/api/hooks';
import { ApiError } from '@/lib/errors';
import { forgetSessionOn401, queryClient } from '@/query';
import type { SetupTurnBody, SetupTurnView } from '@/api/types';
import { resetAssistantForTests } from '@/features/assistant/store';
import { mockSetupAnswers, mockSetupTurnPause, resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { recordedSiteProfile } from '@/mocks/profile';
import { theme } from '@/theme';
import SiteProfilePage from '../SiteProfilePage';
import { questionById } from './fields';
import SetupPage from './SetupPage';
import { CHANGED_MEANWHILE, inForce, resetSetupForTests, statusOf, useSetup } from './setupStore';

/**
 * Set up the site, slice 1b: Ask Shutter reads a typed answer and drafts a receiver's description, and the kind and
 * tier of a receiver being added, and nothing else; behind the site's own switch, which is off unless saved on. What it
 * drafts enters the draft marked, with Undo, and is saved only by the review, after a tick.
 */

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return env.trial;
  },
}));

const BASE = '/api/shutter';
const TURNS = `${BASE}/site-profile/setup-turns`;
const recorded = recordedSiteProfile()!;
let requests: { method: string; path: string; body: Record<string, unknown> | null }[] = [];
const writes = () => requests.filter((r) => r.method !== 'GET');
const posts = () => requests.filter((r) => r.method === 'POST' && r.path === TURNS);
const puts = () => requests.filter((r) => r.method === 'PUT');

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  mockSetupAnswers(true);
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
      { path: '/site-setup', element: <SetupPage /> },
      { path: '/site-profile', element: <SiteProfilePage /> },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const card = (name: string) => within(screen.getByRole('region', { name }));
const SYSTEM = 'What is the system, in a few words?';
const KIND = 'What kind of system is it?';
const TIER = 'Its tier';
const NAME = 'Which receiver? Name it by its production item.';
const BOX = 'Or answer in your own words';
// Tier 3: the demo's own policy releases tiers 1 and 2 without a person, so Ask Shutter may not draft either there
const ANSWER = 'It is the ward whiteboard, it only shows where patients are now, tier 3';

const added = () => useSetup.getState().draft!.receivers.at(-1) as Record<string, unknown>;
const rid = () => useSetup.getState().rids.at(-1)!;

/** A receiver added and named, with the description's card open. */
async function nameBedBoard(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
  await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
  await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
  await screen.findByRole('textbox', { name: BOX });
}

/** Types an answer in the open card's box and sends it. */
async function sendTyped(user: ReturnType<typeof userEvent.setup>, text = ANSWER) {
  await user.type(screen.getByRole('textbox', { name: BOX }), text);
  await user.click(screen.getByRole('button', { name: 'Send to Ask Shutter' }));
}

/**
 * The run's message as the server links it: under the portal path of the namespace the agent ran in, a site's own
 * namespace here (Setup.InstallInto), so a link built from a fixed path would show.
 */
const RUN_LINK = '/csp/trust/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=77';

/** The route as a server that answers a turn with what the test gives it, checked by nobody: a forged answer. */
function answersWith(turn: unknown, more: Partial<SetupTurnView> = {}) {
  server.use(
    http.post(TURNS, () =>
      HttpResponse.json(
        { turnId: 'ST-000900', conversation: 'SC-000900', state: 'pending' },
        { status: 202 },
      ),
    ),
    http.get(`${TURNS}/:id`, () =>
      HttpResponse.json({
        turnId: 'ST-000900',
        conversation: 'SC-000900',
        receiver: 'Bed Board',
        text: ANSWER,
        state: 'answered',
        baseVersion: recorded.version,
        draftRevision: 1,
        askedBy: 'approver',
        askedAt: '2026-11-15T10:00:00Z',
        answeredAt: '2026-11-15T10:00:05Z',
        error: null,
        mode: 'live',
        model: 'claude-opus-5-5',
        costUsd: 0.01,
        ensMessageId: '77',
        messageLink: RUN_LINK,
        turn: turn as SetupTurnBody,
        ...more,
      } satisfies SetupTurnView),
    ),
  );
}

describe('the site switch for typed answers', () => {
  it('is off by default: no box for a typed answer, the page says why, and nothing is sent', async () => {
    mockSetupAnswers(false);
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
    await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
    expect(screen.getByRole('textbox', { name: /What it does/ })).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
    expect(screen.getByTestId('setup-ask-shutter-does')).toHaveTextContent(
      /It does not read typed answers: reading typed answers is switched off in the site profile/,
    );
    expect(screen.queryByText('What you type')).not.toBeInTheDocument();
    // The control still answers
    await user.type(screen.getByRole('textbox', { name: /What it does/ }), 'a board');
    expect(added().system).toBe('a board');
    expect(writes()).toEqual([]);
  });

  it('is refused by the route with its own code while it is off, whoever asks', async () => {
    mockSetupAnswers(false);
    for (const role of ['approver', 'demo', 'judge'] as const) {
      resetMock(role);
      const answer = await fetch(TURNS, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
        body: JSON.stringify({
          receiver: recorded.profile.receivers[0].name,
          text: 'it is a whiteboard',
          draft: recorded.profile,
          baseVersion: recorded.version,
          draftRevision: 0,
        }),
      });
      expect([role, answer.status]).toEqual([role, 409]);
      expect(((await answer.json()) as { error: string }).error).toBe('setup_drafting_off');
    }
  });

  it('is on only when the stored profile says so: the box is on the three questions Ask Shutter may draft', async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    expect(screen.getByTestId('setup-ask-shutter-does')).toHaveTextContent(
      "it drafts a receiver's description, and the kind and tier of a receiver being added, for you to review. It sets nothing else and saves nothing.",
    );
    const band = within(screen.getByRole('region', { name: 'Where this page stands' }));
    expect(band.getByText(/goes to the model with this receiver's name and description/)).toBeInTheDocument();
    // No promise that no name reaches the model
    expect(document.body.textContent).not.toMatch(/no name (is sent|reaches)/i);
    expect(card(SYSTEM).getByRole('textbox', { name: BOX })).toBeInTheDocument();
    await user.click(card(SYSTEM).getByRole('button', { name: 'Leave for now' }));
    expect(card(KIND).getByRole('textbox', { name: BOX })).toBeInTheDocument();
    await user.click(card(KIND).getByRole('button', { name: 'Leave for now' }));
    expect(card(TIER).getByRole('textbox', { name: BOX })).toBeInTheDocument();
    await user.click(card(TIER).getByRole('button', { name: 'Leave for now' }));
    // A capability is a person's: the card says so, and has no box
    const applies = card('Does it apply messages in arrival order or by event time?');
    expect(applies.getByText('Only a person sets this.')).toBeInTheDocument();
    expect(applies.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
  });

  it.each([
    ['demo', "Live answers need the judges' account."],
    ['operator', null],
  ] as const)('follows the reader, with the switch on: %s', async (role, why) => {
    resetMock(role);
    mockSetupAnswers(true);
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
    await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
    if (why) {
      expect(screen.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
      expect(screen.getByTestId('setup-ask-shutter-does')).toHaveTextContent(
        "It cannot read typed answers now: live answers need the judges' account.",
      );
    } else expect(await screen.findByRole('textbox', { name: BOX })).toBeInTheDocument();
  });

  it('is never offered in the trial, which has no model', async () => {
    env.trial = true;
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole('button', { name: 'Add a receiver' }));
    await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
    await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
    expect(screen.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
    expect(screen.getByTestId('setup-ask-shutter-does')).toHaveTextContent(
      'It does not read typed answers in the trial, which has no model.',
    );
  });

  it('offers only the description on a receiver in force', async () => {
    const user = userEvent.setup();
    renderApp('/site-setup?receiver=Downstream%20Out');
    await user.click(await screen.findByRole('button', { name: 'Change: What it is' }));
    expect(await card(SYSTEM).findByRole('textbox', { name: BOX })).toBeInTheDocument();
    await user.click(card(KIND).getByRole('button', { name: 'Change: Kind of system' }));
    expect(card(KIND).getByText('Only a person changes this on a receiver in force.')).toBeInTheDocument();
    expect(card(KIND).queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
  });
});

describe('a typed answer read by Ask Shutter', () => {
  it('drafts the description, the kind and the tier at once, marked, and Undo puts back what they replaced', async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    const exchange = within(
      await screen.findByRole('list', { name: 'Your answers in your own words: What it is' }),
    );
    expect(await exchange.findByText(/Drafted: What it is, Kind of system, Tier\./)).toBeInTheDocument();
    expect(exchange.getByText(/\[mock\] Read from your words about Bed Board/)).toBeInTheDocument();
    // Who read it is said under what it said: here the mock, which calls no model
    expect(exchange.getByText('Read by the API mimic: no model was called.')).toBeInTheDocument();
    expect(added()).toMatchObject({ system: 'the ward whiteboard', category: 'current_state', tier: 3 });
    const s = useSetup.getState();
    for (const q of ['system', 'category', 'tier'] as const)
      expect([q, statusOf(s, rid(), questionById(q))]).toEqual([q, 'ask']);
    expect(card(SYSTEM).getByText('Drafted by Ask Shutter')).toBeInTheDocument();
    // What was sent: the receiver, the text, the draft and the version it was made from; no conversation on a first turn
    expect(posts()).toHaveLength(1);
    expect(posts()[0].body).toMatchObject({
      receiver: 'Bed Board',
      text: ANSWER,
      baseVersion: recorded.version,
    });
    expect(posts()[0].body).not.toHaveProperty('conversation');
    expect((posts()[0].body!.draft as { receivers: unknown[] }).receivers.at(-1)).toMatchObject({
      name: 'Bed Board',
    });
    // Nothing was stored: no profile was saved by the conversation
    expect(puts()).toEqual([]);
    await user.click(exchange.getByRole('button', { name: /^Undo what Ask Shutter drafted/ }));
    expect(added()).not.toHaveProperty('system');
    expect(added()).not.toHaveProperty('category');
    expect(added()).not.toHaveProperty('tier');
    expect(exchange.getByText(/^Undone: What it is, Kind of system, Tier\.$/)).toBeInTheDocument();
    // A second answer goes on in the same conversation
    // The card stays on the page, unanswered again
    await user.click(card(SYSTEM).getByRole('button', { name: 'Answer: What it is' }));
    await sendTyped(user, 'it keeps the movement history');
    await waitFor(() => expect(added().category).toBe('history_of_record'));
    expect(posts()[1].body).toMatchObject({
      conversation: 'SC-000001',
      text: 'it keeps the movement history',
    });
  });

  it("makes a hand edit the person's own, which Undo then leaves alone", async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    await waitFor(() => expect(added().tier).toBe(3));
    act(() => useSetup.getState().setKey(rid(), 'tier', 2));
    expect(statusOf(useSetup.getState(), rid(), questionById('tier'))).toBe('you');
    await user.click(screen.getByRole('button', { name: /^Undo what Ask Shutter drafted/ }));
    expect(added().tier).toBe(2);
    expect(added()).not.toHaveProperty('system');
  });

  it('lists what was drafted in the review, and saves only after the tick', async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    await waitFor(() => expect(added().tier).toBe(3));
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Review and save…',
      }),
    );
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    const block = within(dialog.getByRole('list', { name: 'Drafted by Ask Shutter (3)' }));
    expect(block.getAllByRole('listitem')).toHaveLength(3);
    expect(
      block.getByText(
        /Bed Board, kind of system:.*Read from the words .whiteboard.\. A bed manager, a ward whiteboard, portering\. Overtaken failure: closes, no write\./,
      ),
    ).toBeInTheDocument();
    expect(block.getByText(/Bed Board, tier:.*Who releases a write at tier 3/)).toBeInTheDocument();
    const save = dialog.getByRole('button', { name: /^Save version/ });
    const tick = dialog.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' });
    expect(tick).not.toBeChecked();
    expect(save).toBeDisabled();
    // The tick is clear on every opening
    await user.click(tick);
    expect(save).toBeEnabled();
    await user.click(dialog.getByRole('button', { name: 'Cancel' }));
    await user.click(
      within(await screen.findByRole('region', { name: 'A draft from Set up the site' })).getByRole(
        'button',
        {
          name: 'Review and save…',
        },
      ),
    );
    const again = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    expect(
      again.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }),
    ).not.toBeChecked();
    expect(again.getByRole('button', { name: /^Save version/ })).toBeDisabled();
    await user.click(again.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }));
    await user.click(again.getByRole('button', { name: /^Save version/ }));
    expect(await screen.findByText(`Version ${recorded.version + 1} saved`)).toBeInTheDocument();
    // The body saved is the profile alone: nothing of the conversation is in it
    expect(puts()).toHaveLength(1);
    const body = puts()[0].body as { receivers: Record<string, unknown>[]; expectedVersion: number };
    expect(body.receivers.at(-1)).toEqual({
      name: 'Bed Board',
      system: 'the ward whiteboard',
      category: 'current_state',
      tier: 3,
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    });
    expect(JSON.stringify(body)).not.toMatch(/quote|turnId|drafted|conversation/);
  });

  it('drops a turn still being read when the review opens, and never uses what comes back for it', async () => {
    let state: 'answering' | 'answered' = 'answering';
    server.use(
      http.post(TURNS, () =>
        HttpResponse.json(
          { turnId: 'ST-000900', conversation: 'SC-000900', state: 'pending' },
          { status: 202 },
        ),
      ),
      http.get(`${TURNS}/:id`, () =>
        HttpResponse.json({
          turnId: 'ST-000900',
          conversation: 'SC-000900',
          receiver: 'Bed Board',
          text: ANSWER,
          state,
          baseVersion: recorded.version,
          draftRevision: 1,
          askedBy: 'approver',
          askedAt: '2026-11-15T10:00:00Z',
          answeredAt: null,
          error: null,
          mode: null,
          model: null,
          costUsd: 0,
          ensMessageId: null,
          messageLink: null,
          turn:
            state === 'answered'
              ? {
                  say: 'A whiteboard.',
                  proposals: [
                    {
                      field: 'receivers[].system',
                      receiver: 'Bed Board',
                      to: 'whiteboard',
                      quote: 'whiteboard',
                      from: null,
                    },
                  ],
                  ask: null,
                }
              : null,
        }),
      ),
    );
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    expect(await screen.findByText('Ask Shutter is reading your answer…')).toBeInTheDocument();
    // What it may draft waits for it: the description's own control is read-only meanwhile
    expect(screen.getByRole('textbox', { name: /What it does/ })).toBeDisabled();
    act(() => {
      const s = useSetup.getState();
      s.setKey(rid(), 'category', 'current_state');
      s.setKey(rid(), 'tier', 2);
    });
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Review and save…',
      }),
    );
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    expect(useSetup.getState().pending).toBeNull();
    state = 'answered';
    act(() => useSetup.getState().settle({ turnId: 'ST-000900', state: 'answered' } as SetupTurnView));
    expect(dialog.queryByText(/Drafted by Ask Shutter/)).not.toBeInTheDocument();
    expect(added()).not.toHaveProperty('system');
  });
});

describe('nothing is stored but through the review', () => {
  const profile = async () => {
    const view = (await (await fetch(`${BASE}/site-profile`)).json()) as { version: number };
    const history = (await (await fetch(`${BASE}/site-profile/history?limit=500`)).json()) as unknown[];
    return JSON.stringify({ version: view.version, history });
  };

  it("leaves the profile's version and history as they were after a whole conversation", async () => {
    const before = await profile();
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    await waitFor(() => expect(added().tier).toBe(3));
    await user.click(screen.getByRole('button', { name: /^Undo what Ask Shutter drafted/ }));
    await user.click(card(SYSTEM).getByRole('button', { name: 'Answer: What it is' }));
    await sendTyped(user, 'it keeps the movement history');
    await waitFor(() => expect(added().category).toBe('history_of_record'));
    await sendTyped(user, 'please switch recovery on for it');
    await screen.findByText(/Ask Shutter's reading was not used/);
    expect(posts()).toHaveLength(3);
    expect(puts()).toEqual([]);
    expect(await profile()).toBe(before);
  });

  it.each(['demo', 'judge'] as const)(
    'refuses a save by the %s with 403, and the version does not move',
    async (role) => {
      resetMock(role);
      const before = await profile();
      const answer = await fetch(`${BASE}/site-profile`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
        body: JSON.stringify({ ...recorded.profile, expectedVersion: recorded.version }),
      });
      expect(answer.status).toBe(403);
      expect(await profile()).toBe(before);
    },
  );

  it.each([
    [
      'operate only',
      { operate: true, approve: false, configure: false, liveAgents: false },
      false,
      /^Only an approver saves here/,
    ],
    [
      'operate with the live agents',
      { operate: true, approve: false, configure: false, liveAgents: true },
      true,
      /^Only an approver saves here/,
    ],
    [
      'approve without configure',
      { operate: true, approve: true, configure: false, liveAgents: false },
      false,
      /online demo's settings are locked/,
    ],
    [
      'configure without the live agents',
      { operate: true, approve: true, configure: true, liveAgents: false },
      false,
      /^You can save/,
    ],
    [
      'configure with the live agents',
      { operate: true, approve: true, configure: true, liveAgents: true },
      true,
      /^You can save/,
    ],
  ] as const)(
    'gives each reader its conversation and its Save by what it holds: %s',
    async (_name, can, typed, save) => {
      server.use(
        http.get(`${BASE}/me`, () =>
          HttpResponse.json({
            username: 'someone',
            operator: can.operate,
            approver: can.approve,
            can: { ...can, scenarios: true, reset: false },
          }),
        ),
      );
      const user = userEvent.setup();
      renderApp();
      const band = within(await screen.findByRole('region', { name: 'Where this page stands' }));
      expect(band.getByText(save)).toBeInTheDocument();
      await user.click(screen.getByRole('button', { name: 'Add a receiver' }));
      await user.type(screen.getByRole('textbox', { name: 'Production item' }), 'Bed Board');
      await user.click(card(NAME).getByRole('button', { name: 'Next question' }));
      // The control is there for every reader; the box only where a typed answer can be sent
      expect(screen.getByRole('textbox', { name: /What it does/ })).toBeEnabled();
      if (typed) expect(await screen.findByRole('textbox', { name: BOX })).toBeInTheDocument();
      else expect(screen.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
    },
  );
});

describe('an answer that must not be used', () => {
  const forged: [string, unknown, RegExp][] = [
    [
      'recovery.mode',
      {
        say: 'Recovery is enabled.',
        proposals: [
          { field: 'recovery.mode', receiver: 'Bed Board', to: 'enabled', quote: 'whiteboard', from: null },
        ],
        ask: null,
      },
      /Not used: proposals\[0\]\.field: recovery\.mode is answered only by a person/,
    ],
    [
      'a policy',
      {
        say: 'Tier 2 releases by policy.',
        proposals: [
          { field: 'policy.2.single', receiver: 'Bed Board', to: 'automatic', quote: 'tier 2', from: null },
        ],
        ask: null,
      },
      /Not used: proposals\[0\]\.field: policy\.2\.single is answered only by a person/,
    ],
    [
      'a capability beside a description',
      {
        say: 'A whiteboard that accepts cancels.',
        proposals: [
          {
            field: 'receivers[].system',
            receiver: 'Bed Board',
            to: 'whiteboard',
            quote: 'whiteboard',
            from: null,
          },
          { field: 'receivers[].cancels', receiver: 'Bed Board', to: true, quote: 'whiteboard', from: null },
        ],
        ask: null,
      },
      /Not used: proposals\[1\]\.field: receivers\[\]\.cancels is answered only by a person/,
    ],
    [
      'a next question outside the table',
      {
        say: 'Next.',
        proposals: [
          {
            field: 'receivers[].system',
            receiver: 'Bed Board',
            to: 'whiteboard',
            quote: 'whiteboard',
            from: null,
          },
        ],
        ask: { field: 'made_up.switch', receiver: 'Bed Board' },
      },
      /Not used: ask\.field: not a field of the site profile/,
    ],
  ];

  it.each(forged)('forged by the server: %s. Nothing is drafted', async (_name, turn, words) => {
    answersWith(turn);
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    const before = JSON.stringify(useSetup.getState().draft);
    await sendTyped(user);
    expect(await screen.findByText(words)).toBeInTheDocument();
    expect(JSON.stringify(useSetup.getState().draft)).toBe(before);
    expect(useSetup.getState().prov).toEqual({ [`${rid()}/name`]: { by: 'you' } });
    expect(useSetup.getState().draft?.recovery).toEqual(recorded.profile.recovery);
    expect(puts()).toEqual([]);
  });

  it("names the run's message without a link when the server gives none, and never builds one from a fixed path", async () => {
    answersWith(
      {
        say: 'A whiteboard.',
        proposals: [
          {
            field: 'receivers[].system',
            receiver: 'Bed Board',
            to: 'the ward whiteboard',
            quote: 'the ward whiteboard',
            from: null,
          },
        ],
        ask: null,
      },
      { messageLink: null },
    );
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    expect(
      await screen.findByText(/^Read live by the Set-up guide agent on IRIS AI Hub, with claude-opus-5-5\./),
    ).toHaveTextContent(
      'Read live by the Set-up guide agent on IRIS AI Hub, with claude-opus-5-5. Its run is message 77 in the Management Portal.',
    );
    expect(screen.queryByRole('link', { name: 'message 77' })).not.toBeInTheDocument();
  });

  it('shows markup and a link in what Ask Shutter says, and in a quote, as plain text', async () => {
    answersWith({
      say: '<img src=x onerror="alert(1)"> see [the docs](https://evil.example) <b>now</b>',
      proposals: [
        {
          field: 'receivers[].system',
          receiver: 'Bed Board',
          to: 'whiteboard',
          quote: '<a href="https://evil.example">whiteboard</a>',
          from: null,
        },
      ],
      ask: null,
    });
    const user = userEvent.setup();
    const { container } = renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    expect(await screen.findByText(/<img src=x onerror="alert\(1\)"> see \[the docs\]/)).toBeInTheDocument();
    // A live run names its agent and its model, and links to the run's message in the Management Portal
    const run = await screen.findByRole('link', { name: 'message 77' });
    expect(run.parentElement).toHaveTextContent(
      'Read live by the Set-up guide agent on IRIS AI Hub, with claude-opus-5-5. Its run is message 77 in the Management Portal.',
    );
    // The server's link, under the namespace's own portal path, never one built from a fixed path
    expect(run).toHaveAttribute('href', RUN_LINK);
    await waitFor(() => expect(added().system).toBe('whiteboard'));
    expect(container.querySelector('img')).toBeNull();
    expect(container.querySelector('a[href*="evil.example"]')).toBeNull();
    expect(container.querySelector('.setup-exchange b')).toBeNull();
    await user.click(screen.getByRole('tab', { name: /^Draft/ }));
    expect(screen.getByTestId('setup-quote-system')).toHaveTextContent(
      '<a href="https://evil.example">whiteboard</a>',
    );
    expect(container.querySelector('a[href*="evil.example"]')).toBeNull();
  });

  it.each([
    ['a link', 'see https://intranet.example/board'],
    ['an address', 'ask ward.clerk@example.nhs.uk'],
    ['a run of six or more digits', 'its number is 4857261930'],
    ['what looks like a credential', 'password: hunter2'],
  ])('is refused before it is sent when the text holds %s', async (what, text) => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user, text);
    expect(
      screen.getByText(`The text holds ${what}. Take that out and send again: Ask Shutter does not need it.`),
    ).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: BOX })).toBeInvalid();
    expect(writes()).toEqual([]);
  });

  it.each([
    [403, 'live_agents_only', "Typed answers are read live only, and that needs the judges' account."],
    [409, 'no_model', 'Reading typed answers needs a model key'],
    [409, 'setup_drafting_off', 'Reading typed answers is switched off in the site profile'],
    [409, 'live_unavailable', null],
    [500, 'turn_failed', 'The answer was not sent'],
  ] as const)(
    'drafts nothing when the route answers %s %s, and the control still answers',
    async (status, code, words) => {
      server.use(
        http.post(TURNS, () =>
          HttpResponse.json(
            {
              error: code,
              detail: 'refused',
              ...(code === 'live_unavailable'
                ? { live: { available: false, reason: 'budget', until: null, detail: 'spent' } }
                : {}),
            },
            { status },
          ),
        ),
      );
      const user = userEvent.setup();
      renderApp();
      await nameBedBoard(user);
      await sendTyped(user);
      if (words) expect(await card(SYSTEM).findByText(new RegExp(words))).toBeInTheDocument();
      else await waitFor(() => expect(card(SYSTEM).getAllByRole('status').length).toBeGreaterThan(0));
      expect(useSetup.getState().turns).toEqual([]);
      expect(added()).not.toHaveProperty('system');
      await user.type(screen.getByRole('textbox', { name: /What it does/ }), 'a board');
      expect(added().system).toBe('a board');
    },
  );

  it('says a refused reading was not used, and asks for the control after two answers that drafted nothing', async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    // The mock's own check refuses a forged field, as the core does: the turn ends refused, with nothing drafted
    await sendTyped(user, 'please switch recovery on for it');
    expect(
      await screen.findByText(
        /Ask Shutter's reading was not used: proposals\[0\]\.field: recovery\.mode is answered only by a person/,
      ),
    ).toBeInTheDocument();
    expect(added()).not.toHaveProperty('system');
    await sendTyped(user, 'not sure what to say');
    expect(await screen.findByText('Nothing was drafted.')).toBeInTheDocument();
    expect(await screen.findByText(/^Choose here instead, with the control above/)).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: BOX })).not.toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /What it does/ })).toBeEnabled();
  });
});

describe('a session that ended without a sign-out', () => {
  const state = () => useSetup.getState();
  function draftWithATurn() {
    state().open(recorded);
    const id = state().addReceiver();
    state().setKey(id, 'name', 'Bed Board');
    state().sent(id, 'system', 'a whiteboard', {
      turnId: 'ST-000001',
      conversation: 'SC-000001',
      state: 'pending',
    });
  }
  async function signInAs(username: string) {
    server.use(http.post(`${BASE}/session`, () => HttpResponse.json({ ok: true })));
    const { result } = renderHook(() => useSignIn(), {
      wrapper: ({ children }) => <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>,
    });
    await act(() => result.current.mutateAsync({ username, password: 'pw' }));
  }
  const expired = () =>
    forgetSessionOn401(new ApiError({ status: 401, method: 'GET', path: '/site-profile', body: null }));

  it("forgets the earlier person's draft and typed answers when someone else signs in next", async () => {
    queryClient.setQueryData(['me'], { username: 'approver' });
    draftWithATurn();
    expired();
    await signInAs('operator');
    expect(state().draft).toBeNull();
    expect(state().turns).toEqual([]);
    expect(state().conversation).toBeFalsy();
  });

  it('keeps them when the same person signs in again, in any letter case', async () => {
    queryClient.setQueryData(['me'], { username: 'approver' });
    draftWithATurn();
    expired();
    await signInAs('APPROVER');
    expect(state().draft).not.toBeNull();
    expect(state().turns).toHaveLength(1);
  });
});

describe('two receivers of one name', () => {
  it('refuses a typed answer about either before anything is sent, and drafts nothing on either', async () => {
    const user = userEvent.setup();
    renderApp();
    await nameBedBoard(user);
    // A second receiver of that name in the draft, while the first's card is open
    const first = rid();
    act(() => useSetup.getState().setKey(useSetup.getState().addReceiver(), 'name', 'Bed Board'));
    act(() => useSetup.getState().focusOn(first));
    await sendTyped(user);
    expect(
      await screen.findByText(
        'Another receiver in the draft has this name: give each receiver its own name before Ask Shutter reads an answer about it.',
      ),
    ).toBeInTheDocument();
    expect(posts()).toHaveLength(0);
    const both = useSetup.getState().draft!.receivers.filter((r) => r.name === 'Bed Board');
    expect(both.map((r) => (r as Record<string, unknown>).system ?? null)).toEqual([null, null]);
  });

  it('is refused by the route too', async () => {
    const draft = structuredClone(recorded.profile);
    draft.receivers.push({ name: 'Bed Board' } as never, { name: 'Bed Board' } as never);
    const res = await fetch(TURNS, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({
        receiver: 'Bed Board',
        text: 'a whiteboard',
        draft,
        baseVersion: recorded.version,
      }),
    });
    expect(res.status).toBe(400);
    expect(((await res.json()) as { detail: string }).detail).toMatch(
      /^another receiver in the draft has this name/,
    );
  });
});

describe('a late answer', () => {
  const turn: SetupTurnBody = {
    say: 'A whiteboard.',
    proposals: [
      {
        field: 'receivers[].system',
        receiver: 'Bed Board',
        to: 'whiteboard',
        quote: 'whiteboard',
        from: null,
      },
    ],
    ask: null,
  };
  const view = (more: Partial<SetupTurnView> = {}): SetupTurnView => ({
    turnId: 'ST-000001',
    conversation: 'SC-000001',
    receiver: 'Bed Board',
    text: 'a whiteboard',
    state: 'answered',
    baseVersion: recorded.version,
    draftRevision: 1,
    askedBy: 'approver',
    askedAt: '',
    answeredAt: '',
    error: null,
    mode: 'live',
    model: 'mock',
    costUsd: 0,
    ensMessageId: null,
    messageLink: null,
    turn,
    ...more,
  });
  const state = () => useSetup.getState();
  /** A receiver added and named, with one turn sent for its description. */
  function pending() {
    state().open(recorded);
    const id = state().addReceiver();
    state().setKey(id, 'name', 'Bed Board');
    state().sent(id, 'system', 'a whiteboard', {
      turnId: 'ST-000001',
      conversation: 'SC-000001',
      state: 'pending',
    });
    return id;
  }
  const last = () => state().turns.at(-1);

  it('is used when nothing changed meanwhile', () => {
    const id = pending();
    state().settle(view());
    expect(last()).toMatchObject({ state: 'used', say: 'A whiteboard.' });
    expect(state().prov[`${id}/system`]).toEqual({ by: 'ask', turnId: 'ST-000001', quote: 'whiteboard' });
    expect(state().pending).toBeNull();
  });

  it.each([
    ['the person answered the field by hand', (id: string) => state().setKey(id, 'system', 'typed by hand')],
    [
      'the receiver was removed and added again',
      (id: string) => {
        state().removeAdded(id);
        state().setKey(state().addReceiver(), 'name', 'Bed Board');
      },
    ],
    ['the receiver was renamed', (id: string) => state().setKey(id, 'name', 'Bed Board 2')],
    [
      'another receiver was given the same name',
      () => state().setKey(state().addReceiver(), 'name', 'Bed Board'),
    ],
  ])('is dropped whole when %s', (_name, change) => {
    const id = pending();
    change(id);
    const before = JSON.stringify(state().draft);
    state().settle(view());
    expect(JSON.stringify(state().draft)).toBe(before);
    expect(Object.values(state().prov).every((p) => p.by === 'you')).toBe(true);
    if (state().turns.length) expect(last()).toMatchObject({ state: 'unused', note: CHANGED_MEANWHILE });
  });

  it('is dropped when someone saved another version, or the conversation is another', () => {
    pending();
    state().settle(view({ baseVersion: recorded.version + 1 }));
    expect(last()).toMatchObject({ state: 'unused', note: CHANGED_MEANWHILE });
    resetSetupForTests();
    pending();
    state().settle(view({ conversation: 'SC-000777' }));
    expect(last()).toMatchObject({ state: 'unused', note: CHANGED_MEANWHILE });
  });

  it('is ignored after a discard, a cancel or a sign-out, and the conversation starts afresh', () => {
    pending();
    state().discard();
    state().settle(view());
    expect(state().draft).toEqual(recorded.profile);
    expect(state().turns).toEqual([]);
    expect(state().conversation).toBeNull();
    const id = pending();
    state().cancelPending();
    state().settle(view());
    expect(last()).toMatchObject({ state: 'cancelled' });
    expect(state().prov[`${id}/system`]).toBeUndefined();
    pending();
    window.dispatchEvent(new Event(SIGNED_OUT));
    state().settle(view());
    expect(state().draft).toBeNull();
  });

  it('is dropped when a policy row was made automatic in the draft meanwhile', () => {
    const id = pending();
    useSetup.setState({
      draft: {
        ...state().draft!,
        policy: { ...state().draft!.policy, '2': { single: 'automatic' } },
      },
    });
    state().settle(
      view({
        turn: {
          say: 'Tier 2.',
          proposals: [
            { field: 'receivers[].tier', receiver: 'Bed Board', to: 2, quote: 'tier 2', from: null },
          ],
          ask: null,
        },
      }),
    );
    expect(last()?.state).toBe('unused');
    expect(last()?.note).toMatch(/a tier that releases without a person/);
    expect(state().draft!.receivers.at(-1)).not.toHaveProperty('tier');
    expect(state().prov[`${id}/tier`]).toBeUndefined();
  });

  it('keeps what is typed and not sent with the draft, and forgets it with the draft', () => {
    const id = pending();
    state().type(id, 'category', 'it keeps the movement');
    expect(state().typed[`${id}/category`]).toBe('it keeps the movement');
    // Nothing of it is a turn, and nothing of it is in the draft
    expect(state().turns).toHaveLength(1);
    expect(JSON.stringify(state().draft)).not.toContain('it keeps the movement');
    state().discard();
    expect(state().typed).toEqual({});
  });

  it('counts a failed turn and one that drafted nothing, and opens the question it suggests when it is unanswered', () => {
    const id = pending();
    state().settle(view({ state: 'schema_failed', error: 'proposals[0].field: refused', turn: null }));
    expect(last()).toMatchObject({ state: 'failed', note: 'proposals[0].field: refused' });
    expect(state().misses[`${id}/system`]).toBe(1);
    state().sent(id, 'system', 'hm', { turnId: 'ST-000002', conversation: 'SC-000001', state: 'pending' });
    state().settle(
      view({
        turnId: 'ST-000002',
        turn: {
          say: 'Nothing to read.',
          proposals: [],
          ask: { field: 'receivers[].tier', receiver: 'Bed Board' },
        },
      }),
    );
    expect(last()).toMatchObject({ state: 'nothing', say: 'Nothing to read.' });
    expect(state().misses[`${id}/system`]).toBe(2);
    expect(state().suggested).toEqual({ rid: id, question: 'tier' });
    // A suggestion of an answered question is ignored
    state().sent(id, 'system', 'hm', { turnId: 'ST-000003', conversation: 'SC-000001', state: 'pending' });
    state().settle(
      view({
        turnId: 'ST-000003',
        turn: { say: 'Next.', proposals: [], ask: { field: 'receivers[].name', receiver: 'Bed Board' } },
      }),
    );
    expect(state().suggested).toBeNull();
  });
});

describe('drafted answers after the hand-over', () => {
  /** A receiver added and named, its three answers drafted, handed over, and the review cancelled. */
  async function handedOver(user: ReturnType<typeof userEvent.setup>) {
    renderApp();
    await nameBedBoard(user);
    await sendTyped(user);
    await waitFor(() => expect(added().tier).toBe(3));
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Review and save…',
      }),
    );
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    await user.click(dialog.getByRole('button', { name: 'Cancel' }));
    return within(await screen.findByRole('region', { name: 'A draft from Set up the site' }));
  }

  it("keeps a renamed receiver's drafted answers in the review, the tick required, and marked when it goes back", async () => {
    const user = userEvent.setup();
    const band = await handedOver(user);
    const id = rid();
    // The setup page tells the person to name it by its production item: they correct the name here
    const name = screen.getAllByRole('textbox', { name: /^Production item/ }).at(-1)!;
    await user.clear(name);
    await user.type(name, 'Bed Board East');
    await user.click(band.getByRole('button', { name: 'Review and save…' }));
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    const block = within(dialog.getByRole('list', { name: 'Drafted by Ask Shutter (3)' }));
    expect(block.getByText(/Bed Board East, tier:/)).toBeInTheDocument();
    expect(dialog.getByRole('button', { name: /^Save version/ })).toBeDisabled();
    expect(
      dialog.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }),
    ).not.toBeChecked();
    await user.click(dialog.getByRole('button', { name: 'Cancel' }));
    await user.click(
      within(await screen.findByRole('region', { name: 'A draft from Set up the site' })).getByRole(
        'button',
        {
          name: 'Back to Set up the site',
        },
      ),
    );
    await waitFor(() => expect(added().name).toBe('Bed Board East'));
    const s = useSetup.getState();
    expect(s.rids.at(-1)).toBe(id);
    for (const q of ['system', 'category', 'tier'] as const)
      expect([q, statusOf(s, id, questionById(q))]).toEqual([q, 'ask']);
  }, 90_000);

  it('keeps the drafted answers and the tick when another approver saved meanwhile and the save was stale', async () => {
    const user = userEvent.setup();
    const band = await handedOver(user);
    // Another approver saves the stored profile as it is: the version moves on
    const other = await fetch(`${BASE}/site-profile`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({ ...recorded.profile, expectedVersion: recorded.version }),
    });
    expect(other.status).toBe(200);
    await user.click(band.getByRole('button', { name: 'Review and save…' }));
    let dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    await user.click(dialog.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }));
    await user.click(dialog.getByRole('button', { name: /^Save version/ }));
    await user.click(await dialog.findByRole('button', { name: 'Keep editing' }));
    const again = within(await screen.findByRole('region', { name: 'A draft from Set up the site' }));
    expect(again.queryByText('Not pre-filled')).toBeNull();
    await user.click(again.getByRole('button', { name: 'Review and save…' }));
    dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    expect(dialog.getByRole('list', { name: 'Drafted by Ask Shutter (3)' })).toBeInTheDocument();
    expect(dialog.getByRole('button', { name: /^Save version/ })).toBeDisabled();
    expect(
      dialog.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }),
    ).not.toBeChecked();
  }, 90_000);

  it('says what a drafted tier comes to under the form as it stands, the policy row changed since included', async () => {
    const user = userEvent.setup();
    const band = await handedOver(user);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Tier 3, single failures' }), 'automatic');
    await user.click(band.getByRole('button', { name: 'Review and save…' }));
    const dialog = within(await screen.findByRole('dialog', { name: /^Save version/ }));
    const block = dialog.getByRole('list', { name: 'Drafted by Ask Shutter (3)' });
    const tier = within(block)
      .getByText(/Bed Board, tier:/)
      .closest('li')!;
    expect(tier).toHaveTextContent(
      "Tier 3's row now releases a write with no person: only a person chooses this tier, with the page's control.",
    );
    expect(tier).not.toHaveTextContent('single failures, one approval');
  }, 90_000);

  it('discards the handed-over draft in Set up the site too when the save bar discards it', async () => {
    const user = userEvent.setup();
    await handedOver(user);
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Discard changes',
      }),
    );
    expect(screen.queryByRole('region', { name: 'A draft from Set up the site' })).not.toBeInTheDocument();
    const s = useSetup.getState();
    // The draft is the stored profile again, with no receiver added and nothing drafted
    expect(s.draft).toEqual(s.base!.profile);
    expect(s.draft!.receivers.some((r) => r.name === 'Bed Board')).toBe(false);
    expect(Object.values(s.prov).some((p) => p.by === 'ask')).toBe(false);
    expect(s.turns).toEqual([]);
    expect(s.conversation).toBeNull();
  }, 90_000);
});

describe('the store, around a turn', () => {
  const state = () => useSetup.getState();
  const asked = (n: number) => ({
    turnId: `ST-00000${n}`,
    conversation: 'SC-000001',
    state: 'pending' as const,
  });
  const answered = (n: number, to: string, from: string | null): SetupTurnView => ({
    turnId: `ST-00000${n}`,
    conversation: 'SC-000001',
    receiver: 'Bed Board',
    text: 'it is the ward whiteboard display',
    state: 'answered',
    baseVersion: recorded.version,
    draftRevision: 1,
    askedBy: 'approver',
    askedAt: '',
    answeredAt: '',
    error: null,
    mode: 'live',
    model: 'mock',
    costUsd: 0,
    ensMessageId: null,
    messageLink: null,
    turn: {
      say: 'Read.',
      proposals: [{ field: 'receivers[].system', receiver: 'Bed Board', to, quote: to, from }],
      ask: null,
    },
  });
  function named() {
    state().open(recorded);
    const id = state().addReceiver();
    state().setKey(id, 'name', 'Bed Board');
    return id;
  }

  it('undoes overlapping turns in any order, leaving no drafted answer that cannot be undone', () => {
    const id = named();
    state().sent(id, 'system', 'a', asked(1));
    state().settle(answered(1, 'ward display', null));
    state().sent(id, 'system', 'b', asked(2));
    state().settle(answered(2, 'ward whiteboard display', 'ward display'));
    expect(added().system).toBe('ward whiteboard display');
    // A first: its answer is the later turn's now, so nothing is undone and A stays undoable
    state().undo('ST-000001');
    expect(added().system).toBe('ward whiteboard display');
    state().undo('ST-000002');
    expect(added().system).toBe('ward display');
    expect(state().prov[`${id}/system`]).toMatchObject({ by: 'ask', turnId: 'ST-000001' });
    state().undo('ST-000001');
    expect(added()).not.toHaveProperty('system');
    expect(Object.values(state().prov).some((p) => p.by === 'ask')).toBe(false);
  });

  it('does not take an answer to a send made before a discard into the next draft', () => {
    const id = named();
    const epoch = state().epoch;
    state().discard();
    state().sent(id, 'system', 'it is a bed manager', asked(1), epoch);
    expect(state().conversation).toBeNull();
    expect(state().turns).toEqual([]);
    expect(state().pending).toBeNull();
  });

  it('uses no answer while the stored version has moved under the draft', () => {
    const id = named();
    state().sent(id, 'system', 'a', asked(1));
    state().open({ ...recorded, version: recorded.version + 1 });
    expect(state().moved).toBe(true);
    const before = JSON.stringify(state().draft);
    state().settle(answered(1, 'ward display', null));
    expect(JSON.stringify(state().draft)).toBe(before);
    expect(state().turns.at(-1)).toMatchObject({ state: 'unused', note: CHANGED_MEANWHILE });
  });
});

describe('the mock route, as the server, takes who asked once', () => {
  it('keeps the turn as asked by who sent it when the session ends while it is being opened', async () => {
    const draft = JSON.parse(JSON.stringify(recorded.profile)) as typeof recorded.profile;
    draft.receivers.push({
      name: 'Bed Board',
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    } as never);
    mockSetupTurnPause(async () => {
      await fetch(`${BASE}/session`, { method: 'DELETE', headers: { 'X-Requested-With': 'Shutter' } });
    });
    const answer = await fetch(TURNS, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({
        receiver: 'Bed Board',
        text: 'it is a whiteboard',
        draft,
        baseVersion: recorded.version,
        draftRevision: 1,
      }),
    });
    expect(answer.status).toBe(202);
    const { turnId } = (await answer.json()) as { turnId: string };
    await fetch(`${BASE}/session`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({ username: 'approver', password: 'shutter' }),
    });
    const turn = (await (await fetch(`${TURNS}/${turnId}`)).json()) as SetupTurnView;
    expect(turn.askedBy).toBe('approver');
  });
});
