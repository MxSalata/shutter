import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { chooseTransport, resetTransportForTests } from '@/api/transport';
import { server } from '@/mocks/node';
import { NO_RECORDED_ANSWER, resetMock } from '@/mocks/handlers';
import { journal } from '@/trial/journal';
import { createTrialTransport } from '@/trial/transport';
import { theme } from '@/theme';
import CasePage from '../CasePage';
import recordedAnswers from '@/mocks/recorded-questions.json';
import type { CaseQuestion, WhatIfFact } from '@/api/types';
import { SAMPLE_LABEL, TRIAL_NO_ANSWER, answerParts, answersBadge, provenanceText } from './labels';
import { WhatIfCard } from './WhatIfCard';
import { layer1Words } from '@/test/words';
import { useAppearance } from '@/stores/appearance';
import { guideCard, guideDock } from '@/lib/guideDock';

/**
 * What the recorded answers say about themselves: the day of the recording and its model. The trial keeps the word
 * "live" for the live system, so there a recording is one made from a real run.
 */
const RECORDED_LABEL = 'Recorded from a real run on 1 November 2026 with claude-opus-5-5';
const LIVE_RECORDED_LABEL = 'Recorded live on 1 November 2026 with claude-opus-5-5';

// The demo's answers are labelled by the page's TRIAL flag, switched here per test
const demo = vi.hoisted(() => ({ value: true }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return demo.value;
  },
}));
// The constant that says the demo's answers are recordings (true since the live re-record), switched here per test
const recorded = vi.hoisted(() => ({ value: true }));
vi.mock('./recorded', () => ({
  get DEMO_ANSWERS_RECORDED() {
    return recorded.value;
  },
}));

const BASE = '/api/shutter';

/** A what-if fact as CONTRACTS 14.1 gives it, with the suggested change made from the same field and values. */
function fact(
  f: Pick<WhatIfFact, 'id' | 'kind' | 'field' | 'from' | 'to' | 'would' | 'affects'> & Partial<WhatIfFact>,
  change: Partial<WhatIfFact['suggested_change']> = {},
): WhatIfFact {
  return {
    role: 'alternative',
    flag: f.field,
    current: f.from,
    holds_now: false,
    ...f,
    suggested_change: {
      field: f.field,
      ...(f.receiver ? { receiver: f.receiver } : {}),
      from: f.from,
      to: f.to,
      why: `Set ${f.field} so the other case applies.`,
      affects: f.affects,
      valid: true,
      stale: false,
      ...change,
    },
  };
}

const whatif = (entry: string, outcome: string, disposition: string, facts: WhatIfFact[]) => ({
  case_id: 'C-000008',
  receiver: 'Downstream Out',
  category: 'current_state',
  entry,
  outcome,
  outcome_ref: 'preferred',
  disposition,
  profile_version: 9,
  note: '',
  facts,
});
let posts: { path: string; body: unknown }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
  demo.value = true;
  recorded.value = true;
  posts = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'POST')
      posts.push({ path: new URL(request.url).pathname, body: await request.clone().json() });
  });
});

function renderCase(caseId: string, query = '?ask=1') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/cases/:caseId', element: <CasePage /> },
      { path: '/site-profile', element: <p>Site profile page</p> },
    ],
    { initialEntries: [`/cases/${caseId}${query}`] },
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

/** The same, for a test that renders more than one case in turn. */
function renderCaseUnmountable(caseId: string, query = '?ask=1') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}${query}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Below 1440 px (jsdom matches no media query) the panel is a drawer: a dialog named by its title. */
const panel = () => screen.findByRole('dialog', { name: 'Ask about this case' });

// The recorded answers' own words, so a recording made again doesn't break the tests: the first sentence of an answer.
type Recorded = {
  scenarios: Record<string, Record<string, { questions: Record<string, { answer: { answer: string } }> }>>;
};
function firstSentence(scenario: string, receiver: string, turn: string): string {
  const text = (recordedAnswers as unknown as Recorded).scenarios[scenario][receiver].questions[turn].answer
    .answer;
  return text.split(/(?<=\.)\s/)[0];
}

describe('Ask about this case', () => {
  it('opens from the case header, says it is read only, and shuts with Escape, back to its button', async () => {
    const router = renderCase('C-000008', '');
    const button = await screen.findByRole('button', { name: 'Ask about this case' });
    expect(button).toHaveAttribute('aria-expanded', 'false');
    expect(button.closest('[data-tour]')).toHaveAttribute('data-tour', 'case-ask');
    await userEvent.click(button);
    const p = await panel();
    expect(router.state.location.search).toBe('?ask=1');
    expect(
      within(p).getByText(
        /Answers explain this case\. They never write to the receiver, change the case or save a setting\./,
      ),
    ).toBeInTheDocument();
    expect(within(p).getByText('Read-only.')).toBeInTheDocument();
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(router.state.location.search).toBe(''));
    await waitFor(() => expect(screen.getByRole('button', { name: 'Ask about this case' })).toHaveFocus());
  });

  it("opens as a sheet beside the tour's card, with no overlay and a dock just before it, until it closes", async () => {
    guideCard.set(true);
    try {
      const router = renderCase('C-000008', '');
      await userEvent.click(await screen.findByRole('button', { name: 'Ask about this case' }));
      const sheet = await screen.findByRole('region', { name: 'Ask about this case' });
      expect(sheet).toHaveClass('ask-sheet');
      // Not a dialog: no overlay, no focus trap, so the tour's card stays in reach
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      await waitFor(() =>
        expect(within(sheet).getByRole('heading', { name: 'Ask about this case' })).toHaveFocus(),
      );
      // The dock the card moves into, just before the sheet in the reading and tab order
      const dock = document.querySelector('[data-guide-dock]');
      expect(dock).not.toBeNull();
      expect(guideDock.get()).toBe(dock);
      expect(dock!.nextElementSibling).toBe(sheet);
      // The tour ends meanwhile: the sheet stays as it is until Ask closes, with no overlay dropping over the page
      act(() => guideCard.set(false));
      expect(screen.getByRole('region', { name: 'Ask about this case' })).toBe(sheet);
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      await userEvent.keyboard('{Escape}');
      await waitFor(() => expect(router.state.location.search).toBe(''));
      expect(guideDock.get()).toBeNull();
      await waitFor(() => expect(screen.getByRole('button', { name: 'Ask about this case' })).toHaveFocus());
      // With no tour, Ask opens as the drawer
      await userEvent.click(screen.getByRole('button', { name: 'Ask about this case' }));
      expect(await panel()).toBeInTheDocument();
      expect(document.querySelector('[data-guide-dock]')).toBeNull();
    } finally {
      guideCard.set(false);
    }
  });

  it('lays its parts out as labelled sections: a quiet read-only line, how deep to ask, the questions', async () => {
    renderCase('C-000008');
    const p = await panel();
    // The read-only note is a line with its words, not a boxed notice
    const note = within(p).getByText('Read-only.').closest('.ask-note');
    expect(note).not.toBeNull();
    expect(p.querySelector('.ask-readonly')).toBeNull();
    // The choice of tier carries its visible label, which names the tab list
    expect(within(p).getByText('How deep to ask')).toBeVisible();
    expect(within(p).getByRole('tablist', { name: 'How deep to ask' })).toBeInTheDocument();
    // The suggested questions and the cited sections, at sizes that leave room around them
    const group = await within(p).findByRole('group', { name: 'Suggested questions' });
    const chips = within(group).getAllByRole('button');
    for (const chip of chips) expect(chip).toHaveClass('ask-chip');
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    const cite = within(thread).getAllByRole('button', { name: 'Operation' })[0];
    expect(cite).toHaveClass('ask-cite');
    expect(cite).toHaveAttribute('data-size', 'sm');
  });

  it('opens on the recorded example conversation, labelled with its recording in the demo', async () => {
    renderCase('C-000008');
    const p = await panel();
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    const turns = within(thread).getAllByRole('article');
    expect(turns.map((t) => within(t).getByRole('heading').textContent)).toEqual([
      'Why was nothing written?',
      'What would make this safe to resend?',
      "What if we trusted the bed manager's times?",
    ]);
    // In the trial the box below says what a question of one's own needs, so the head names the recording only
    expect(within(thread).getByText(`${RECORDED_LABEL}.`)).toBeInTheDocument();
    // Each turn says its tier; the board's turn gives each member's view and points at the What-if card
    expect(within(turns[0]).getByText(`Explain tier. ${RECORDED_LABEL}.`)).toBeInTheDocument();
    expect(within(thread).queryByText(/sample data/i)).not.toBeInTheDocument();
    expect(turns[0]).toHaveTextContent(firstSentence('S8', 'Downstream Out', 'c1.1'));
    expect(within(turns[2]).getByText('Encounter Integrity:')).toBeInTheDocument();
    expect(within(turns[2]).getByRole('button', { name: 'See it in What if' })).toBeInTheDocument();
    expect(within(turns[2]).getByRole('button', { name: 'What-if W1' })).toBeInTheDocument();
    // Nothing was asked to show it
    expect(posts).toEqual([]);
  });

  it('gives the two tiers as tabs, each with its suggested questions', async () => {
    renderCase('C-000008');
    const p = await panel();
    const explain = within(p).getByRole('tab', { name: /Explain/ });
    expect(explain).toHaveAttribute('aria-selected', 'true');
    expect(explain).toHaveTextContent('One agent, plain words. Quick.');
    const chips = () =>
      within(within(p).getByRole('tabpanel'))
        .getAllByRole('button')
        .map((b) => b.textContent);
    await waitFor(() =>
      expect(chips()).toEqual([
        'Why was nothing written? (answered, shown below)',
        'What would make this safe to resend? (answered, shown below)',
        'Which movement is current?',
        'What should I check first?',
      ]),
    );
    await userEvent.click(within(p).getByRole('tab', { name: /Ask the board/ }));
    expect(within(p).getByRole('tab', { name: /Ask the board/ })).toHaveTextContent(
      'Three specialist agents and the coordinator agent. Deeper, slower.',
    );
    expect(chips()).toEqual([
      "What if we trusted the bed manager's times? (answered, shown below)",
      'What did the dissenting specialist say?',
      'What would a resend have changed downstream?',
    ]);
  });

  it('asks a suggested question by its place in the file, shows its answer and moves focus to it', async () => {
    renderCase('C-000008');
    const p = await panel();
    await userEvent.click(await within(p).findByRole('button', { name: 'Which movement is current?' }));
    expect(posts).toEqual([
      {
        path: `${BASE}/cases/C-000008/questions`,
        body: { tier: 'explain', suggested: { conversation: 'c2', turn: 1 } },
      },
    ]);
    const thread = await within(p).findByRole('region', { name: 'Conversation' });
    const heading = within(thread).getByRole('heading', { name: 'Which movement is current?' });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(thread).toHaveTextContent(firstSentence('S8', 'Downstream Out', 'c2.1'));
    // Asked once: choosing it again shows it without asking
    await userEvent.click(within(p).getByRole('button', { name: /Which movement is current\? \(answered/ }));
    expect(posts).toHaveLength(1);
  });

  it('shows the box for a question of your own disabled in the trial, with its reason, steering to the suggested ones', async () => {
    renderCase('C-000008');
    const p = await panel();
    const box = await within(p).findByRole('textbox', { name: 'Your own question' });
    expect(box).toBeDisabled();
    expect(box).toHaveAttribute('placeholder', 'In the trial, pick a suggested question');
    expect(box).toHaveAccessibleDescription('Needs a real model: not in the trial.');
    expect(within(p).getByRole('button', { name: 'Ask' })).toBeDisabled();
    expect(within(p).queryByText('Locked: no key')).not.toBeInTheDocument();
    expect(within(p).queryByText(/model key/)).not.toBeInTheDocument();
  });

  it('answers a suggested question the trial has no recording for with its own words, not the server text', async () => {
    server.use(
      http.post(`${BASE}/cases/:id/questions`, () =>
        HttpResponse.json(
          {
            error: 'no_recorded_answer',
            detail: 'This question has no recorded answer; a judge can ask it live',
          },
          { status: 409 },
        ),
      ),
    );
    renderCase('C-000008');
    const p = await panel();
    await userEvent.click(await within(p).findByRole('button', { name: 'Which movement is current?' }));
    expect(await within(p).findByText('No recorded answer')).toBeInTheDocument();
    expect(within(p).getByText(TRIAL_NO_ANSWER)).toBeInTheDocument();
    expect(within(p).queryByText(/a judge can ask it live/)).not.toBeInTheDocument();
  });

  it('keeps free text for a judge on the public demo, and tells its own user so', async () => {
    demo.value = false;
    resetMock('demo');
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({
          providerConfigured: true,
          mock: false,
          mode: 'policy',
          agentItems: [],
          prices: [],
        }),
      ),
    );
    renderCase('C-000008');
    const p = await panel();
    expect(
      await within(p).findByText(/On the public demo, a question of your own is for a judge to ask live/),
    ).toBeInTheDocument();
    expect(within(p).getByText('Judges only')).toBeInTheDocument();
    expect(within(p).queryByRole('textbox')).not.toBeInTheDocument();
  });

  it('reads a question no recording answers as a note naming who can ask it, not as a fault', async () => {
    demo.value = false;
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({
          providerConfigured: true,
          mock: false,
          mode: 'policy',
          agentItems: [],
          prices: [],
        }),
      ),
      http.post(`${BASE}/cases/:id/questions`, () =>
        HttpResponse.json(
          {
            error: 'no_recorded_answer',
            detail: 'This question has no recorded answer; a judge can ask it live',
          },
          { status: 409 },
        ),
      ),
    );
    renderCase('C-000008');
    const p = await panel();
    await userEvent.type(await within(p).findByRole('textbox', { name: 'Your own question' }), 'Why?');
    await userEvent.click(within(p).getByRole('button', { name: 'Ask' }));
    expect(await within(p).findByText('No recorded answer')).toBeInTheDocument();
    expect(
      within(p).getByText('This question has no recorded answer; a judge can ask it live'),
    ).toBeInTheDocument();
    expect(within(p).queryByText('The question was not asked')).not.toBeInTheDocument();
  });

  it('locks free text on an instance with no model key, and opens it when one is configured', async () => {
    demo.value = false;
    renderCase('C-000008');
    let p = await panel();
    expect(
      await within(p).findByText(/Free text needs a model key, and none is configured here/),
    ).toBeInTheDocument();
    // Outside the demo the example says where it came from all the same: a replayed recording, with its day and model
    expect(within(p).queryByText(new RegExp(SAMPLE_LABEL.replace(/[()]/g, '\\$&')))).not.toBeInTheDocument();
    expect(within(p).getAllByText(new RegExp(LIVE_RECORDED_LABEL)).length).toBeGreaterThan(0);
    expect(
      within(p).getByText(`${LIVE_RECORDED_LABEL}. With an API key you can ask your own questions.`),
    ).toBeInTheDocument();
    await userEvent.keyboard('{Escape}');

    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({
          providerConfigured: true,
          mock: false,
          mode: 'board',
          agentItems: [],
          prices: [],
        }),
      ),
      http.post(`${BASE}/cases/:id/questions`, () =>
        HttpResponse.json({ questionId: 'Q-000099', conversation: 'c1', turn: 4 }, { status: 202 }),
      ),
    );
    await userEvent.click(screen.getByRole('button', { name: 'Ask about this case' }));
    p = await panel();
    const box = await within(p).findByRole('textbox', { name: 'Your own question' });
    expect(
      within(p).getByText(/Runs live with Explain, about 0\.05 to 0\.10 USD a question\./),
    ).toBeInTheDocument();
    await userEvent.type(box, 'Who should I call?');
    await userEvent.click(within(p).getByRole('button', { name: 'Ask' }));
    await waitFor(() => expect(posts).toHaveLength(1));
    expect(posts[0].body).toEqual({ tier: 'explain', question: 'Who should I call?', conversation: 'c1' });
  });

  it("shows the What-if card from the API's facts: today against the alternative, and the change as a draft", async () => {
    renderCase('C-000008');
    const p = await panel();
    const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(within(card).getByText(/is now none named\./)).toBeInTheDocument();
    expect(
      within(card).getByText(
        /The case matched catalogue entry E7, whose outcome here is escalate to a person/,
      ),
    ).toBeInTheDocument();
    expect(within(card).getByText('If it were BEDMGR')).toBeInTheDocument();
    expect(
      within(card).getByText(
        /Entry E7's alternative applies: nothing to send, proposed as superseded\. The case would have closed as superseded with no write instead of escalated to a person/,
      ),
    ).toBeInTheDocument();
    expect(within(card).getByText('Your decision')).toBeInTheDocument();
    expect(
      within(card).getByText(
        /Suggested change: set authoritative source from none named to BEDMGR\. The board names this change/,
      ),
    ).toBeInTheDocument();
    // Never the draft's backwards wording: the PAS is not the alternative here
    expect(card).not.toHaveTextContent(/PAS were authoritative/);
    const open = within(card).getByRole('link', { name: 'Open in Site profile' });
    const href = open.getAttribute('href')!;
    // The link names the case and the fact only: the Site profile page reads the change from the facts again
    expect(href).toBe('/site-profile?suggest=C-000008&fact=W1');
    expect(open).toHaveAccessibleDescription(
      /Opens a pre-filled draft\. An approver reviews it and saves it\./,
    );
  });

  it("shows S2's policy fact on the card the board's answers cite, with the example conversation", async () => {
    renderCase('C-000002');
    const p = await panel();
    const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(
      within(card).getByRole('heading', { name: 'W1: Approval of tier 2 single failures' }),
    ).toBeInTheDocument();
    expect(within(card).getByText('If it were approval')).toBeInTheDocument();
    expect(within(card).getByRole('link', { name: 'Open in Site profile' })).toHaveAttribute(
      'href',
      '/site-profile?suggest=C-000002&fact=W1',
    );
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    expect(within(thread).getAllByRole('article')).toHaveLength(3);
    expect(within(thread).getByRole('button', { name: 'What-if W1' })).toBeInTheDocument();
  });

  it.each([
    ['C-000054', firstSentence('S22', 'Downstream Out', 'c1.1'), 'W1: Category of Downstream Out'],
    ['C-000055', firstSentence('S22', 'Records Out', 'c1.1'), 'W1: Category of Records Out'],
  ] as const)(
    "shows S22's case %s with its own receiver's recorded answers and card",
    async (caseId, text, w1) => {
      renderCase(caseId);
      const p = await panel();
      const thread = await within(p).findByRole('region', { name: 'Example conversation' });
      expect(within(thread).getAllByRole('article')).toHaveLength(3);
      expect(thread).toHaveTextContent(text);
      expect(thread).toHaveTextContent(RECORDED_LABEL);
      const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
      expect(within(card).getByRole('heading', { name: w1 })).toBeInTheDocument();
    },
  );

  it('shows a scenario with no suggested questions plainly, and a card that says no setting changes the outcome', async () => {
    renderCase('C-000009');
    const p = await panel();
    expect(
      await within(within(p).getByRole('tabpanel')).findByText(
        "This case's scenario has no suggested questions yet.",
      ),
    ).toBeInTheDocument();
    const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(within(card).getByText('No setting changes this outcome')).toBeInTheDocument();
  });
});

/**
 * The trial's own path (trial-architecture.md 7, test 12): every call is answered in memory by the recorded mock through
 * the trial's transport, as in a trial page, not by `msw/node`, and `fetch` is a spy that fails the test if anything
 * reaches it.
 */
describe("in the trial, through the trial's own transport", () => {
  const sent = vi.fn(() => Promise.reject(new Error('fetch was called from the trial')));
  beforeAll(() => {
    vi.stubGlobal('fetch', sent);
    resetTransportForTests();
    chooseTransport(createTrialTransport('approver'));
  });
  afterEach(() => {
    expect(sent).not.toHaveBeenCalled();
  });
  afterAll(() => {
    vi.unstubAllGlobals();
    resetTransportForTests();
  });

  it('opens on the recorded example and answers a suggested question from its recording, in this browser', async () => {
    renderCase('C-000008');
    const p = await panel();
    const example = await within(p).findByRole('region', { name: 'Example conversation' });
    expect(within(example).getByText(`${RECORDED_LABEL}.`)).toBeInTheDocument();
    await userEvent.click(await within(p).findByRole('button', { name: 'Which movement is current?' }));
    const thread = await within(p).findByRole('region', { name: 'Conversation' });
    await waitFor(() => expect(thread).toHaveTextContent(firstSentence('S8', 'Downstream Out', 'c2.1')));
    // The trial's journal holds the question, answered by the mock, not sent anywhere
    const asked = journal
      .entries()
      .filter((e) => e.method === 'POST' && e.path === `${BASE}/cases/C-000008/questions`);
    expect(asked).toHaveLength(1);
    expect(asked[0].status).toBeLessThan(300);
  });

  it("reads the What-if card and its draft link from the trial's recording", async () => {
    renderCase('C-000008');
    const p = await panel();
    const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(await within(card).findByText('If it were BEDMGR')).toBeInTheDocument();
    expect(within(card).getByRole('link', { name: 'Open in Site profile' })).toHaveAttribute(
      'href',
      '/site-profile?suggest=C-000008&fact=W1',
    );
  });

  it("keeps the box for a question of one's own disabled, and words a question with no recording as the mock does", async () => {
    renderCase('C-000008');
    const p = await panel();
    const box = await within(p).findByRole('textbox', { name: 'Your own question' });
    expect(box).toBeDisabled();
    expect(box).toHaveAccessibleDescription('Needs a real model: not in the trial.');
    // The panel's own words for a question the trial has no recording of are the mock's refusal, word for word
    expect(TRIAL_NO_ANSWER).toBe(NO_RECORDED_ANSWER);
  });
});

describe("an answer's opening, and the rest one click away", () => {
  /** A recorded answer's whole text. */
  const answerOf = (scenario: string, receiver: string, turn: string) =>
    (recordedAnswers as unknown as Recorded).scenarios[scenario][receiver].questions[turn].answer.answer;

  it('opens on the first sentences up to about 40 words, never cutting one, and keeps the whole answer', () => {
    const text = answerOf('S8', 'Downstream Out', 'c1.1');
    const { lead, rest } = answerParts(text);
    expect(lead.startsWith(firstSentence('S8', 'Downstream Out', 'c1.1'))).toBe(true);
    expect(lead.split(/\s+/).length).toBeLessThanOrEqual(40);
    expect(lead).toMatch(/[.!?]$/);
    expect(`${lead} ${rest}`.replace(/\s+/g, ' ')).toBe(text.replace(/\s+/g, ' '));
    // A short first paragraph is the opening as it stands
    expect(answerParts('Short and plain.\nThe second paragraph.')).toEqual({
      lead: 'Short and plain.',
      rest: 'The second paragraph.',
    });
    expect(answerParts('One sentence only.')).toEqual({ lead: 'One sentence only.', rest: '' });
  });

  it("opens every recorded answer within a card body's 40 words", () => {
    const all = Object.values((recordedAnswers as unknown as Recorded).scenarios).flatMap((byReceiver) =>
      Object.values(byReceiver).flatMap((r) => Object.values(r.questions).map((q) => q.answer.answer)),
    );
    expect(all.length).toBeGreaterThan(20);
    for (const text of all) {
      const { lead, rest } = answerParts(text);
      expect(lead.split(/\s+/).length).toBeLessThanOrEqual(40);
      expect(`${lead} ${rest}`.replace(/\s+/g, ' ')).toBe(text.replace(/\s+/g, ' ').trim());
    }
  });

  it('closes the drawer for a citation, and lands on the cited evidence with its heading focused', async () => {
    if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => {};
    const router = renderCase('C-000008');
    const p = await panel();
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    const first = within(thread).getAllByRole('article')[0];
    await userEvent.click(within(first).getByRole('button', { name: 'Downstream state' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(router.state.location.search).toBe('?tab=evidence');
    const heading = await screen.findByRole('heading', { name: "Downstream Out's encounter" });
    await waitFor(() => expect(heading).toHaveFocus());
  });

  it('shows each turn its opening, with "Show the whole answer" for the rest', async () => {
    renderCase('C-000008');
    const p = await panel();
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    const first = within(thread).getAllByRole('article')[0];
    const more = within(first).getByRole('button', { name: 'Show the whole answer' });
    expect(more).toHaveAttribute('aria-expanded', 'false');
    // The whole answer stays on the page, out of the first layer until opened
    const text = answerOf('S8', 'Downstream Out', 'c1.1');
    const last = text.split(/(?<=[.!?])\s+/).at(-1)!;
    expect(first).toHaveTextContent(last);
    expect(layer1Words(first).join(' ')).not.toContain(last.split(' ').slice(0, 6).join(' '));
    await userEvent.click(more);
    expect(more).toHaveAttribute('aria-expanded', 'true');
    // The board's turn keeps each agent's view with the rest of its answer
    const board = within(thread).getAllByRole('article')[2];
    const views = board.querySelector('[aria-label="Each agent\'s view"]')!;
    expect(views.closest('[data-tech-detail]')).toHaveAttribute('data-tech-detail', 'closed');
    expect(views).toHaveTextContent('Encounter Integrity:');
  });

  // The spec gives Ask no budget of its own: each opening keeps to a card body's 40 words (DESIGN 1.4), and the
  // panel, the What-if card's 184 words included, to 550 in Plain and 1.5 times that in Technical
  it('keeps the panel to its word budget: 550 words in Plain, 1.5 times that in Technical', async () => {
    renderCase('C-000008');
    let p = await panel();
    await within(p).findByRole('region', { name: 'Example conversation' });
    await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(layer1Words(p).length).toBeLessThanOrEqual(550);
    await userEvent.keyboard('{Escape}');
    useAppearance.setState({ detail: 'technical' });
    await userEvent.click(screen.getByRole('button', { name: 'Ask about this case' }));
    p = await panel();
    await within(p).findByRole('region', { name: 'Example conversation' });
    await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(layer1Words(p).length).toBeLessThanOrEqual(825);
  });

  it('says "live" nowhere in its first layer in the trial, but for "live system"', async () => {
    for (const caseId of ['C-000008', 'C-000002']) {
      const { unmount } = renderCaseUnmountable(caseId);
      const p = await panel();
      await within(p).findByRole('region', { name: 'Example conversation' });
      await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
      const words = layer1Words(p)
        .join(' ')
        .replace(/live system/gi, '');
      expect(words).not.toMatch(/\blive\b/i);
      unmount();
    }
  });
});

describe('where the answers came from', () => {
  const question = (over: Partial<CaseQuestion>): CaseQuestion => ({
    questionId: 'Q-1',
    caseId: 'C-000008',
    conversation: 'c1',
    turn: 1,
    tier: 'explain',
    source: 'suggested',
    question: 'Why was nothing written?',
    state: 'answered',
    answer: null,
    askedBy: 'approver',
    askedAt: '2026-10-25T10:00:00Z',
    answeredAt: '2026-10-25T10:00:00Z',
    error: null,
    mode: null,
    model: null,
    costUsd: null,
    runs: 0,
    recordKey: null,
    ensMessageId: null,
    ...over,
  });
  const chipsBadge = (p: HTMLElement) =>
    within(within(p).getByRole('tabpanel')).queryByText(/^(Sample|Recorded) answers$/);

  it('reads the recording on the badge and on every turn in the demo, and sample data when the constant is off', async () => {
    renderCase('C-000008');
    let p = await panel();
    let thread = await within(p).findByRole('region', { name: 'Example conversation' });
    expect(chipsBadge(p)).toHaveTextContent('Recorded answers');
    expect(within(thread).getAllByText(new RegExp(RECORDED_LABEL)).length).toBe(4);
    expect(within(thread).queryByText(/Example \(sample data\)/)).not.toBeInTheDocument();
    await userEvent.keyboard('{Escape}');

    // Switched off: the same replays read as sample data again
    recorded.value = false;
    await userEvent.click(screen.getByRole('button', { name: 'Ask about this case' }));
    p = await panel();
    thread = await within(p).findByRole('region', { name: 'Example conversation' });
    expect(within(thread).getAllByText(/Example \(sample data\)\./).length).toBeGreaterThan(0);
    expect(chipsBadge(p)).toHaveTextContent('Sample answers');
  });

  it('calls answers recorded only when the server marks one as a replay', () => {
    demo.value = false;
    const stored = question({ mode: 'live', model: 'model-x' });
    const live = question({ mode: 'replay', model: 'model-x', answeredAt: '2026-10-25T10:00:00Z' });
    expect(answersBadge([stored])).toBeNull();
    expect(provenanceText(stored)).toBe('Answered');
    expect(answersBadge([stored, live])).toBe('Recorded answers');
    expect(provenanceText(live)).toBe('Recorded live on 25 October 2026 with model-x');
    // The server does not send recordedAt yet; when it does, it is the date
    expect(provenanceText({ ...live, recordedAt: '2026-10-20T10:00:00Z' })).toBe(
      'Recorded live on 20 October 2026 with model-x',
    );
    demo.value = true;
    expect(answersBadge([live])).toBe('Recorded answers');
    expect(provenanceText(live)).toBe('Recorded from a real run on 25 October 2026 with model-x');
    recorded.value = false;
    expect(answersBadge([live])).toBe('Sample answers');
    expect(provenanceText(live)).toBe(SAMPLE_LABEL);
  });
});

describe('WhatIfCard', () => {
  function renderCard() {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const router = createMemoryRouter([{ path: '/', element: <WhatIfCard caseId="C-000008" /> }]);
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={client}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </MantineProvider>,
    );
  }

  beforeEach(() => resetMock('approver'));

  it('reads every word of the setting from the API', async () => {
    server.use(
      http.get(`${BASE}/cases/:id/whatif`, () =>
        HttpResponse.json(
          whatif('E1', 'none', 'superseded', [
            fact({
              id: 'W2',
              kind: 'alternative',
              field: 'receivers[].category',
              receiver: 'Downstream Out',
              from: 'current_state',
              to: 'history_of_record',
              alternative: {
                n: 1,
                outcome: 'correct_history',
                disposition: 'escalate',
                when: 'history_policy: correct',
              },
              would: 'The case would have escalated with the correcting steps.',
              affects: ['an overtaken transfer at this receiver'],
            }),
          ]),
        ),
      ),
    );
    renderCard();
    const card = await screen.findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(within(card).getByRole('heading', { name: 'W2: Category of Downstream Out' })).toBeInTheDocument();
    expect(within(card).getByText('If it were history_of_record')).toBeInTheDocument();
    expect(
      within(card).getByText(/correct the history, proposed as escalate\. The case would have escalated/),
    ).toBeInTheDocument();
    expect(within(card).getByText('an overtaken transfer at this receiver')).toBeInTheDocument();
  });

  it("states a policy fact's value today and what the other value would do (the handoff's W3)", async () => {
    server.use(
      http.get(`${BASE}/cases/:id/whatif`, () =>
        HttpResponse.json(
          whatif('E3', 'resend', 'resend', [
            fact({
              id: 'W3',
              kind: 'policy',
              role: 'policy',
              field: 'policy.2.single',
              from: 'automatic',
              to: 'approval',
              would: 'An approver would have been asked before the resend',
              affects: ['every tier 2 single case'],
            }),
          ]),
        ),
      ),
    );
    renderCard();
    const card = await screen.findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(
      within(card).getByRole('heading', { name: 'W3: Approval of tier 2 single failures' }),
    ).toBeInTheDocument();
    expect(within(card).getByText('Approval of tier 2 single failures is automatic.')).toBeInTheDocument();
    expect(within(card).getByText('If it were approval')).toBeInTheDocument();
    expect(within(card).getByText('An approver would have been asked before the resend')).toBeInTheDocument();
    // Not the catalogue entry's wording: a policy fact does not turn on the entry's alternative
    expect(card).not.toHaveTextContent(/catalogue entry E3/);
    expect(card).not.toHaveTextContent(/alternative applies/);
    expect(
      within(card).getByText(
        /Suggested change: set approval of tier 2 single failures from automatic to approval\./,
      ),
    ).toBeInTheDocument();
    expect(within(card).getByRole('link', { name: 'Open in Site profile' })).toHaveAttribute(
      'href',
      '/site-profile?suggest=C-000008&fact=W3',
    );
  });

  const authoritative = (change: Partial<WhatIfFact['suggested_change']>) =>
    server.use(
      http.get(`${BASE}/cases/:id/whatif`, () =>
        HttpResponse.json(
          whatif('E7', 'escalate', 'escalate', [
            fact(
              {
                id: 'W1',
                kind: 'alternative',
                field: 'authoritative_source',
                from: '',
                to: 'BEDMGR',
                would: 'It would close with nothing written.',
                affects: [],
              },
              change,
            ),
          ]),
        ),
      ),
    );

  it('offers no draft for a stale change, and says why', async () => {
    authoritative({ stale: true });
    renderCard();
    expect(await screen.findByText('The profile has changed since')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Open in Site profile' })).not.toBeInTheDocument();
  });

  it('offers no draft for a change the server finds invalid, and shows its problem', async () => {
    authoritative({ valid: false, problem: 'authoritative_source must name a source system the site feeds' });
    renderCard();
    expect(await screen.findByText('This change would not be accepted')).toBeInTheDocument();
    expect(screen.getByText(/must name a source system the site feeds/)).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Open in Site profile' })).not.toBeInTheDocument();
  });
});
