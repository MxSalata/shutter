import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import fixtures from '@/mocks/fixtures.json';
import { theme } from '@/theme';
import { useAppearance } from '@/stores/appearance';
import { AssistantFrame } from './AssistantSurface';
import { FOCUS_NOTE, FOCUS_NOTE_LIVE, WRITTEN_LABEL } from './FocusAsk';
import { HeaderAssistantButton } from './HeaderAssistantButton';
import { FOCUS_CHOSEN_BY } from './screen';
import { resetAssistantForTests, useAssistant, type PageFocus } from './store';

/**
 * "Ask Shutter about this" in the panel: the question it was opened on, asked once for the reader where a live answer can
 * be given, with the question in the summary; the written explanation wherever no live answer is given; nothing written.
 */

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return env.trial;
  },
}));

const BASE = '/api/shutter';
let requests: { method: string; path: string; body: Record<string, unknown> | null }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  resetAssistantForTests();
  useAppearance.setState({ detail: 'plain' });
  env.trial = false;
  requests = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method !== 'GET')
      requests.push({
        method: request.method,
        path: new URL(request.url).pathname,
        body: (await request
          .clone()
          .json()
          .catch(() => null)) as Record<string, unknown> | null,
      });
  });
});

const FOCUS: PageFocus = {
  page: 'site-profile',
  id: 'site-receivers-1-tier',
  title: 'The tier of Records Out',
  question: 'What does tier 2 mean for Records Out, and what would another tier change?',
  answer: 'Tier 2, operations',
  consequence: 'Who releases a write at tier 2: single failures, one approval.',
  written: 'The tier is how sensitive the system is.',
};

const ANSWER = 'Tier 2 is operations: a write to Records Out is released by one approval here.';

/** A live instance's page question route: 202, then the answer, with its run's message. */
function answersLive() {
  server.use(
    http.post(`${BASE}/page-questions`, () =>
      HttpResponse.json(
        { questionId: 'P-000101', page: 'site-profile', state: 'pending', askedBy: 'approver' },
        { status: 202 },
      ),
    ),
    http.get(`${BASE}/page-questions/:qid`, () =>
      HttpResponse.json({
        questionId: 'P-000101',
        tier: 'page',
        page: 'site-profile',
        question: FOCUS.question,
        state: 'answered',
        askedBy: 'approver',
        askedAt: '2026-11-14T10:00:00Z',
        answeredAt: '2026-11-14T10:00:09Z',
        error: null,
        mode: 'live',
        model: 'claude-opus-5-5',
        costUsd: 0.004,
        ensMessageId: '4321',
        answer: { answer: ANSWER, cites: ['page'], confidence: 'high' },
      }),
    ),
  );
}

function SiteProfile() {
  return (
    <main id="main">
      <h1>Site profile</h1>
      <p>This hospital&apos;s answers: they decide what Shutter may do.</p>
      <h2>Receivers</h2>
    </main>
  );
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <header>
              <HeaderAssistantButton />
            </header>
            <AssistantFrame />
          </>
        ),
        children: [{ path: '/site-profile', element: <SiteProfile /> }],
      },
    ],
    { initialEntries: ['/site-profile'] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Opens the panel on the question, as the page's button does from the wide breakpoint. */
async function askAbout() {
  renderPage();
  act(() => useAssistant.getState().askAbout(FOCUS));
  const panel = await screen.findByRole('dialog', { name: 'Ask Shutter' });
  return within(await within(panel).findByRole('region', { name: FOCUS.title }));
}

const posts = () => requests.filter((r) => r.method === 'POST');

describe('Ask Shutter about one of the page’s questions, in the panel', () => {
  it('asks it once for the reader, with the question in the summary, and attributes the answer to the AI Hub agent', async () => {
    answersLive();
    const card = await askAbout();
    expect(card.getByText(FOCUS.answer)).toBeInTheDocument();
    expect(card.getByText(FOCUS.consequence)).toBeInTheDocument();
    expect(await card.findByText(FOCUS_NOTE_LIVE)).toBeInTheDocument();
    expect(await card.findByText(ANSWER)).toBeInTheDocument();
    // The run's message is a link into the Management Portal, as a case's agent runs are
    const run = card.getByRole('link', { name: 'message 4321' });
    expect(run).toHaveAttribute(
      'href',
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=4321',
    );
    expect(run).toHaveAttribute('target', '_blank');
    expect(run.parentElement).toHaveTextContent(
      'Answered live by the Explain agent on IRIS AI Hub, with claude-opus-5-5. Its run is message 4321 in the Management Portal.',
    );
    // Once, to the page question route, with the page's summary and the question it is about
    expect(posts()).toHaveLength(1);
    expect(posts()[0].path).toBe(`${BASE}/page-questions`);
    expect(posts()[0].body).toMatchObject({
      page: 'site-profile',
      question: FOCUS.question,
      context: {
        page: 'site-profile',
        title: 'Site profile',
        headings: ['Receivers'],
        focus: {
          question: FOCUS.title,
          answer: FOCUS.answer,
          consequence: FOCUS.consequence,
          chosenBy: FOCUS_CHOSEN_BY,
        },
      },
    });
    // Nothing but the question went out: no profile was saved
    expect(requests.filter((r) => r.path.includes('site-profile') && r.method !== 'GET')).toEqual([]);
    // The written explanation is one click away under a live answer
    expect(card.getByRole('button', { name: WRITTEN_LABEL })).toHaveAttribute('aria-expanded', 'false');
  });

  it('does not ask again when opened again on the same question', async () => {
    answersLive();
    const card = await askAbout();
    await card.findByText(ANSWER);
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    act(() => useAssistant.getState().askAbout(FOCUS));
    const again = await screen.findByRole('dialog', { name: 'Ask Shutter' });
    expect(await within(again).findByText(ANSWER)).toBeInTheDocument();
    expect(posts()).toHaveLength(1);
    // The question's own answer is shown with it, not again in the conversation below
    expect(within(again).queryByRole('heading', { name: 'Conversation' })).not.toBeInTheDocument();
  });

  it('shows the written explanation in the trial, and asks nothing', async () => {
    env.trial = true;
    const card = await askAbout();
    expect(await card.findByText('The trial gives no live answers.')).toBeInTheDocument();
    expect(card.getByText(FOCUS_NOTE)).toBeInTheDocument();
    expect(card.getByText(WRITTEN_LABEL)).toBeInTheDocument();
    expect(card.getByText(FOCUS.written)).toBeVisible();
    expect(posts()).toEqual([]);
  });

  it("shows the written explanation to the demo's public role, which has no live agents", async () => {
    resetMock('demo');
    const card = await askAbout();
    expect(await card.findByText("Live answers need the judges' account.")).toBeInTheDocument();
    expect(card.getByText(FOCUS.written)).toBeVisible();
    expect(posts()).toEqual([]);
  });

  it('shows the written explanation with no model key', async () => {
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({ ...fixtures.settings, providerConfigured: false, mock: false }),
      ),
    );
    const card = await askAbout();
    expect(
      await card.findByText('Live answers need a model key, and none is configured here.'),
    ).toBeInTheDocument();
    expect(card.getByText(FOCUS.written)).toBeVisible();
    expect(posts()).toEqual([]);
  });

  it('shows the written explanation and why while the budget is spent', async () => {
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({
          ...fixtures.settings,
          live: {
            ...fixtures.settings.live,
            agents: { available: false, reason: 'budget', until: '2099-01-01T00:00:00Z' },
          },
          budget: { ...fixtures.settings.budget, dailyUsd: 5, spentTodayUsd: 5, exhausted: true },
        }),
      ),
    );
    const card = await askAbout();
    expect(await card.findByText(/budget/i)).toBeInTheDocument();
    expect(card.getByText(FOCUS.written)).toBeVisible();
    expect(posts()).toEqual([]);
  });

  it('opens the written explanation when the live question is refused', async () => {
    server.use(
      http.post(`${BASE}/page-questions`, () =>
        HttpResponse.json(
          {
            error: 'live_unavailable',
            detail: 'The day is spent',
            live: {
              available: false,
              reason: 'budget',
              until: '2099-01-01T00:00:00Z',
              detail: 'The day is spent',
            },
          },
          { status: 409 },
        ),
      ),
    );
    const card = await askAbout();
    expect(await card.findByRole('status')).toHaveTextContent(/budget/i);
    expect(card.getByText(FOCUS.written)).toBeVisible();
    expect(posts()).toHaveLength(1);
  });

  it('goes back to the button that opened it when the panel closes', async () => {
    answersLive();
    renderPage();
    const button = document.createElement('button');
    button.id = 'ask-about-site-receivers-1-tier';
    document.body.append(button);
    act(() => useAssistant.getState().askAbout(FOCUS));
    await screen.findByRole('dialog', { name: 'Ask Shutter' });
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(button).toHaveFocus());
    expect(useAssistant.getState().focus).toBeNull();
    button.remove();
  });
});
