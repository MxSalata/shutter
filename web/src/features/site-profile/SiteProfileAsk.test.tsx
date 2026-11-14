import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { PageChat } from '@/features/assistant/PageChat';
import { ASSISTANT_WIDE_QUERY } from '@/features/assistant/panel';
import { resetAssistantForTests, useAssistant } from '@/features/assistant/store';
import { layer1WordCount } from '@/test/words';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { RECOVERY_WRITTEN, TIER_WRITTEN } from './askAbout';
import SiteProfilePage from './SiteProfilePage';

/**
 * "Ask Shutter about this" on the Site profile's consequential questions: a receiver's kind and tier, and enabling recovery.
 * Below the wide breakpoint (jsdom matches no media query) it opens under the question, in the page, so the form stays in
 * view; asking changes nothing in the draft and sends no profile.
 */

const BASE = '/api/shutter';

/** The words of what opens under a question with no live answer: its heading, the note, why, and the written text. */
const REGION_WORDS = 65;
let requests: { method: string; path: string; body: Record<string, unknown> | null }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  resetAssistantForTests();
  notifications.clean();
  useAppearance.setState({ detail: 'plain' });
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

/** The page, and with `panel` the Ask Shutter panel's page conversation beside it, as the layout puts it from 1200 px. */
function renderPage({ panel = false } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const element = panel ? (
    <>
      <SiteProfilePage />
      <PanelBeside />
    </>
  ) : (
    <SiteProfilePage />
  );
  const router = createMemoryRouter([{ path: '/site-profile', element }], {
    initialEntries: ['/site-profile'],
  });
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The panel's page conversation while the panel is open, as AssistantSurface shows it. */
function PanelBeside() {
  const open = useAssistant((st) => st.open);
  return open ? (
    <section aria-label="Ask Shutter">
      <PageChat page="site-profile" />
    </section>
  ) : null;
}

/** From the wide breakpoint (jsdom matches no media query): the panel sits beside the page. */
function wideScreen(): () => void {
  const matchMedia = window.matchMedia;
  window.matchMedia = ((query: string) => ({
    ...matchMedia(query),
    matches: query === ASSISTANT_WIDE_QUERY,
  })) as typeof window.matchMedia;
  return () => {
    window.matchMedia = matchMedia;
  };
}

const ANSWER =
  "Tier 2 is operations: the policy's tier 2 row decides who releases a write to Downstream Out. Tier 3 would follow the clinical safety row instead.";

function answersLive() {
  server.use(
    http.post(`${BASE}/page-questions`, () =>
      HttpResponse.json(
        { questionId: 'P-000201', page: 'site-profile', state: 'pending', askedBy: 'approver' },
        { status: 202 },
      ),
    ),
    http.get(`${BASE}/page-questions/:qid`, () =>
      HttpResponse.json({
        questionId: 'P-000201',
        tier: 'page',
        page: 'site-profile',
        question:
          'What does tier 2 mean for Downstream Out, and what would each other tier change? Explain each; do not recommend one.',
        state: 'answered',
        askedBy: 'approver',
        askedAt: '2026-11-14T10:00:00Z',
        answeredAt: '2026-11-14T10:00:09Z',
        error: null,
        mode: 'live',
        model: 'claude-opus-5-5',
        costUsd: 0.004,
        ensMessageId: null,
        answer: { answer: ANSWER, cites: ['page'], confidence: 'high' },
      }),
    ),
  );
}

describe('Ask Shutter about this, on the Site profile', () => {
  it('is on each receiver’s kind and tier and on enabling recovery, and nowhere else', async () => {
    renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    const buttons = screen.getAllByRole('button', { name: /^Ask Shutter about this: / });
    expect(buttons.map((b) => b.getAttribute('aria-label'))).toEqual([
      'Ask Shutter about this: What kind of system is Downstream Out?',
      'Ask Shutter about this: The tier of Downstream Out',
      'Ask Shutter about this: What kind of system is Records Out?',
      'Ask Shutter about this: The tier of Records Out',
      'Ask Shutter about this: Enable recovery',
    ]);
    for (const b of buttons) expect(b).toHaveAttribute('aria-expanded', 'false');
  });

  it('opens under the question with the written explanation where no live answer is given, and asks nothing', async () => {
    resetMock('demo');
    renderPage();
    const button = await screen.findByRole('button', { name: 'Ask Shutter about this: Enable recovery' });
    const enabled = (document.getElementById('site-recovery-mode') as HTMLInputElement).checked;
    await userEvent.click(button);
    expect(button).toHaveAttribute('aria-expanded', 'true');
    const region = await screen.findByRole('region', { name: 'Ask Shutter: Enable recovery' });
    expect(button).toHaveAttribute('aria-controls', region.parentElement?.id);
    expect(await within(region).findByText(RECOVERY_WRITTEN)).toBeVisible();
    expect(within(region).getByText("Live answers need the judges' account.")).toBeInTheDocument();
    // What opens is one card under the question: the written explanation within a card body's 40 words (DESIGN 1.4),
    // and the whole region held near its measured 63 words
    expect(layer1WordCount(within(region).getByText(RECOVERY_WRITTEN))).toBeLessThanOrEqual(40);
    expect(layer1WordCount(region)).toBeLessThanOrEqual(REGION_WORDS);
    // The switch it is about is still there, as it was
    expect((document.getElementById('site-recovery-mode') as HTMLInputElement).checked).toBe(enabled);
    expect(requests).toEqual([]);
    await userEvent.click(button);
    expect(screen.queryByRole('region', { name: 'Ask Shutter: Enable recovery' })).not.toBeInTheDocument();
  });

  it('asks the tier’s question live with the question in the summary, and leaves the draft as it was', async () => {
    answersLive();
    renderPage();
    const group = await screen.findByRole('group', { name: 'Receiver 1: Downstream Out' });
    await userEvent.click(
      within(group).getByRole('button', { name: 'Ask Shutter about this: The tier of Downstream Out' }),
    );
    const region = await screen.findByRole('region', { name: 'Ask Shutter: The tier of Downstream Out' });
    expect(await within(region).findByText(ANSWER)).toBeInTheDocument();
    expect(
      within(region).getByText('Answered live by the Explain agent on IRIS AI Hub, with claude-opus-5-5.'),
    ).toBeInTheDocument();
    // The written explanation one click away, the tier still the person's
    expect(within(region).getByRole('button', { name: 'Written explanation' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(within(region).getByText(TIER_WRITTEN, { exact: false })).not.toBeVisible();
    expect(within(group).getByRole('radio', { name: /2, operations/ })).toBeChecked();
    // One question went out, with the page's summary and the question it is about; nothing else was sent
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({
      method: 'POST',
      path: `${BASE}/page-questions`,
      body: {
        page: 'site-profile',
        question:
          'What does tier 2 mean for Downstream Out, and what would each other tier change? Explain each; do not recommend one.',
        context: {
          page: 'site-profile',
          title: 'Site profile',
          focus: {
            question: 'The tier of Downstream Out',
            answer: 'Tier 2, operations',
            consequence: expect.stringMatching(/^Who releases a write at tier 2: single failures, /),
          },
        },
      },
    });
    // Asking made no change to save
    expect(screen.queryByRole('region', { name: 'Unsaved changes' })).not.toBeInTheDocument();
  });

  it('asks again only when the person presses, once the answer has changed', async () => {
    answersLive();
    renderPage();
    const group = await screen.findByRole('group', { name: 'Receiver 1: Downstream Out' });
    await userEvent.click(
      within(group).getByRole('button', { name: 'Ask Shutter about this: The tier of Downstream Out' }),
    );
    const region = await screen.findByRole('region', { name: 'Ask Shutter: The tier of Downstream Out' });
    await within(region).findByText(ANSWER);
    await userEvent.click(within(group).getByRole('radio', { name: /3, clinical safety/ }));
    // The new answer is the person's own change, the only one in the draft; nothing is asked until they press
    expect(await screen.findByRole('region', { name: 'Unsaved changes' })).toHaveTextContent('1 change');
    const ask = await within(region).findByRole('button', { name: 'Ask about this answer' });
    expect(requests.filter((r) => r.method === 'POST')).toHaveLength(1);
    await userEvent.click(ask);
    await waitFor(() => expect(requests.filter((r) => r.method === 'POST')).toHaveLength(2));
    expect(requests[1].body).toMatchObject({
      question:
        'What does tier 3 mean for Downstream Out, and what would each other tier change? Explain each; do not recommend one.',
    });
    expect(requests.some((r) => r.method === 'PUT')).toBe(false);
  });

  it('from 1200 px follows the page in the panel: a changed answer shows there, and is asked about only on a press', async () => {
    const restore = wideScreen();
    try {
      answersLive();
      renderPage({ panel: true });
      const group = await screen.findByRole('group', { name: 'Receiver 1: Downstream Out' });
      const button = within(group).getByRole('button', {
        name: 'Ask Shutter about this: The tier of Downstream Out',
      });
      await userEvent.click(button);
      const panel = await screen.findByRole('region', { name: 'Ask Shutter' });
      const card = await within(panel).findByRole('region', { name: 'The tier of Downstream Out' });
      expect(await within(card).findByText(ANSWER)).toBeInTheDocument();
      expect(card).toHaveTextContent('On the page: Tier 2, operations');
      expect(button).toHaveAttribute('aria-expanded', 'true');
      // No inline region: the panel beside the page has it
      expect(
        screen.queryByRole('region', { name: 'Ask Shutter: The tier of Downstream Out' }),
      ).not.toBeInTheDocument();
      await userEvent.click(within(group).getByRole('radio', { name: /3, clinical safety/ }));
      // The panel states the answer the page has now, and what it does, in the page's own words
      await waitFor(() => expect(card).toHaveTextContent('On the page: Tier 3, clinical safety'));
      expect(card).toHaveTextContent('What it does: Who releases a write at tier 3:');
      expect(card).not.toHaveTextContent('Tier 2, operations');
      expect(button).toHaveAttribute('aria-expanded', 'true');
      expect(button).toHaveAttribute('aria-controls', 'ask-panel');
      // The same card, not a new one: nothing was asked until the person presses
      expect(within(panel).getAllByRole('region', { name: 'The tier of Downstream Out' })).toHaveLength(1);
      const ask = await within(card).findByRole('button', { name: 'Ask about this answer' });
      expect(requests.filter((r) => r.method === 'POST')).toHaveLength(1);
      // The tier 2 answer stays in the panel's conversation below
      expect(within(panel).getByRole('region', { name: 'Conversation' })).toHaveTextContent(ANSWER);
      await userEvent.click(ask);
      await waitFor(() => expect(requests.filter((r) => r.method === 'POST')).toHaveLength(2));
      expect(requests[1].body).toMatchObject({
        question:
          'What does tier 3 mean for Downstream Out, and what would each other tier change? Explain each; do not recommend one.',
        context: { focus: { answer: 'Tier 3, clinical safety' } },
      });
      expect(requests.some((r) => r.method === 'PUT')).toBe(false);
      // Another question's button moves the panel to that question
      await userEvent.click(
        within(group).getByRole('button', {
          name: 'Ask Shutter about this: What kind of system is Downstream Out?',
        }),
      );
      expect(
        await within(panel).findByRole('region', { name: 'What kind of system is Downstream Out?' }),
      ).toBeVisible();
      expect(button).toHaveAttribute('aria-expanded', 'false');
      act(() => useAssistant.getState().setOpen(false));
    } finally {
      restore();
    }
  });
});
