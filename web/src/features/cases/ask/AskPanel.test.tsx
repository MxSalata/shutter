import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from '../CasePage';
import { SAMPLE_LABEL } from './labels';
import { WhatIfCard } from './WhatIfCard';

// The demo's answers are labelled as sample data: the page reads the build's DEMO flag, switched here per test
const demo = vi.hoisted(() => ({ value: true }));
vi.mock('@/demo', () => ({
  get DEMO() {
    return demo.value;
  },
  DEMO_USER: { username: 'approver', password: 'shutter' },
}));

const BASE = '/api/shutter';
let posts: { path: string; body: unknown }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  demo.value = true;
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

/** Below laptop width (jsdom matches no media query) the panel is a drawer: a dialog named by its title. */
const panel = () => screen.findByRole('dialog', { name: 'Ask about this case' });

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

  it('opens on the recorded example conversation, labelled as sample data in the demo', async () => {
    renderCase('C-000008');
    const p = await panel();
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    const turns = within(thread).getAllByRole('article');
    expect(turns.map((t) => within(t).getByRole('heading').textContent)).toEqual([
      'Why was nothing written?',
      'What would make this safe to resend?',
      "What if we trusted the bed manager's times?",
    ]);
    expect(
      within(thread).getByText(`${SAMPLE_LABEL}. With an API key you can ask your own questions.`),
    ).toBeInTheDocument();
    // Each turn says its tier; the board's turn gives each member's view and points at the What-if card
    expect(within(turns[0]).getByText(/Explain tier\. Example \(sample data\)\./)).toBeInTheDocument();
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
      'Three specialists and the coordinator. Deeper, slower.',
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
    expect(
      within(thread).getByText(/Shutter cannot tell, and that is why the case was escalated/),
    ).toBeInTheDocument();
    // Asked once: choosing it again shows it without asking
    await userEvent.click(within(p).getByRole('button', { name: /Which movement is current\? \(answered/ }));
    expect(posts).toHaveLength(1);
  });

  it('locks free text without a key and says so, in the demo', async () => {
    renderCase('C-000008');
    const p = await panel();
    expect(
      await within(p).findByText(
        'Free text needs a model key. In this demo, pick a suggested question above.',
      ),
    ).toBeInTheDocument();
    expect(within(p).getByText('Locked: no key')).toBeInTheDocument();
    expect(within(p).queryByRole('textbox')).not.toBeInTheDocument();
  });

  it('locks free text on an instance with no model key, and opens it when one is configured', async () => {
    demo.value = false;
    renderCase('C-000008');
    let p = await panel();
    expect(
      await within(p).findByText(/Free text needs a model key, and none is configured here/),
    ).toBeInTheDocument();
    // Outside the demo the example says where it came from: here, a replayed answer with no recording behind it
    expect(within(p).queryByText(new RegExp(SAMPLE_LABEL.replace(/[()]/g, '\\$&')))).not.toBeInTheDocument();
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
        /Entry E7's alternative applies: nothing to send, proposed as superseded\. The bed manager's WARD-C placement would stand/,
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
    expect(href.startsWith('/site-profile?suggest=')).toBe(true);
    expect(JSON.parse(new URLSearchParams(href.split('?')[1]).get('suggest')!)).toMatchObject({
      caseId: 'C-000008',
      fact: 'W1',
      field: 'authoritative_source',
      from: '',
      to: 'BEDMGR',
    });
    expect(open).toHaveAccessibleDescription(
      /Opens a pre-filled draft\. An approver reviews it and saves it\./,
    );
  });

  it('says when no setting changes the outcome (S2, entry E2 has no alternative)', async () => {
    renderCase('C-000002');
    const p = await panel();
    const card = await within(p).findByRole('region', { name: 'What if: the setting behind this outcome' });
    expect(within(card).getByText('No setting changes this outcome')).toBeInTheDocument();
    expect(within(card).queryByRole('link', { name: 'Open in Site profile' })).not.toBeInTheDocument();
    const thread = await within(p).findByRole('region', { name: 'Example conversation' });
    expect(within(thread).getAllByRole('article')).toHaveLength(3);
  });

  it('shows a scenario with no suggested questions plainly, and no card when there are no facts', async () => {
    renderCase('C-000009');
    const p = await panel();
    expect(
      await within(within(p).getByRole('tabpanel')).findByText(
        "This case's scenario has no suggested questions yet.",
      ),
    ).toBeInTheDocument();
    await waitFor(() => expect(within(p).queryByRole('region', { name: /What if/ })).not.toBeInTheDocument());
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
        HttpResponse.json({
          entry: 'E1',
          outcome: 'none',
          disposition: 'superseded',
          facts: [
            {
              id: 'W2',
              kind: 'alternative',
              field: 'receivers[].category',
              receiver: 'Downstream Out',
              from: 'current_state',
              to: 'history_of_record',
              alternative: {
                outcome: 'correct_history',
                disposition: 'escalate',
                when: 'history_policy: correct',
              },
              would: 'The case would have escalated with the correcting steps.',
              affects: ['an overtaken transfer at this receiver'],
            },
          ],
        }),
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

  it('offers no draft for a stale fact, and says why', async () => {
    server.use(
      http.get(`${BASE}/cases/:id/whatif`, () =>
        HttpResponse.json({
          entry: 'E7',
          outcome: 'escalate',
          disposition: 'escalate',
          facts: [
            {
              id: 'W1',
              kind: 'alternative',
              field: 'authoritative_source',
              from: '',
              to: 'BEDMGR',
              would: 'It would close with nothing written.',
              affects: [],
              stale: true,
            },
          ],
        }),
      ),
    );
    renderCard();
    expect(await screen.findByText('The profile has changed since')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Open in Site profile' })).not.toBeInTheDocument();
  });
});
