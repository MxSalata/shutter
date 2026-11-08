import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
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
import { HeaderAssistantButton } from './HeaderAssistantButton';
import { PAGE_JUDGES_ONLY, PAGE_SAMPLE_LABEL, pageProvenance } from './PageChat';
import { resetAssistantForTests, useAssistant } from './store';

// The panel's words follow the page's TRIAL flag, switched here per test
const env = vi.hoisted(() => ({ trial: true }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return env.trial;
  },
}));

const BASE = '/api/shutter';
let posts: { path: string; body: Record<string, unknown> }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  resetAssistantForTests();
  useAppearance.setState({ detail: 'plain' });
  env.trial = true;
  posts = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'POST')
      posts.push({
        path: new URL(request.url).pathname,
        body: (await request.clone().json()) as Record<string, unknown>,
      });
  });
});

/** A page of the app with the header's button, as the shell frames it (jsdom matches no media query: the drawer). */
function Scenarios() {
  return (
    <main id="main">
      <h1>Scenarios</h1>
      <p>Known failures replayed: what Shutter does and who decides.</p>
      <h2>Then follow this path</h2>
      <a href="#/cases/C-000008">Case C-000008</a>
      <a href="#/scenarios">S2: a transfer recovered</a>
    </main>
  );
}

function renderPage(path = '/scenarios') {
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
        children: [
          { path: '/scenarios', element: <Scenarios /> },
          { path: '/cases', element: <h1>Cases</h1> },
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

const panel = () => screen.findByRole('dialog', { name: 'Ask Shutter' });

describe('Ask Shutter about a page', () => {
  it('opens from the header, closed by default, and shuts with Escape, back to the button', async () => {
    renderPage();
    const button = screen.getByRole('button', { name: 'Ask Shutter' });
    expect(button).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    await userEvent.click(button);
    const p = await panel();
    expect(within(p).getByText('Read-only.')).toBeInTheDocument();
    expect(within(p).getByText(/Answers explain what is on this page/)).toBeInTheDocument();
    expect(button).toHaveAttribute('aria-expanded', 'true');
    expect(button).toHaveAttribute('aria-controls', 'ask-panel');
    await waitFor(() => expect(within(p).getByRole('heading', { name: 'Ask Shutter' })).toHaveFocus());
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await waitFor(() => expect(button).toHaveFocus());
    expect(useAssistant.getState().open).toBe(false);
  });

  it('remembers open or closed in this tab', async () => {
    renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    await panel();
    expect(window.sessionStorage.getItem('shutter:assistant:open')).toBe('1');
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(window.sessionStorage.getItem('shutter:assistant:open')).toBeNull());
  });

  it("asks the page's suggested question with a summary of the screen, ids and labels only, and shows the sample answer", async () => {
    renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const p = await panel();
    expect(within(p).getByText('Suggested questions about Scenarios')).toBeInTheDocument();
    await userEvent.click(within(p).getByRole('button', { name: 'What is a scenario?' }));
    const heading = await within(p).findByRole('heading', { name: 'What is a scenario?', level: 4 });
    await waitFor(() => expect(heading).toHaveFocus());
    await waitFor(() => expect(within(p).getByText(/replays a known failure/)).toBeInTheDocument());
    expect(within(p).getByText(`${PAGE_SAMPLE_LABEL}.`)).toBeInTheDocument();
    // What went to the server: the page's name, the question and the summary built from the page itself
    expect(posts).toHaveLength(1);
    expect(posts[0].path).toBe(`${BASE}/page-questions`);
    expect(posts[0].body).toEqual({
      page: 'scenarios',
      question: 'What is a scenario?',
      context: {
        page: 'scenarios',
        title: 'Scenarios',
        lead: 'Known failures replayed: what Shutter does and who decides.',
        headings: ['Then follow this path'],
        items: [
          { id: 'C-000008', kind: 'case', label: 'Case C-000008' },
          { id: 'S2', kind: 'scenario', label: 'S2: a transfer recovered' },
        ],
      },
    });
    // Asked once: the chip now leads to its answer
    await userEvent.click(within(p).getByRole('button', { name: 'What is a scenario?' }));
    expect(posts).toHaveLength(1);
    // The trial takes no question of one's own, and says why
    expect(within(p).getByRole('textbox', { name: 'Your own question' })).toBeDisabled();
    expect(within(p).getByRole('textbox', { name: 'Your own question' })).toHaveAccessibleDescription(
      'Needs a real model: not in the trial.',
    );
    // The written guide, with its links
    const guide = within(p).getByRole('region', { name: 'About this page: Scenarios' });
    expect(guide).toHaveTextContent('Known failures replayed');
    expect(within(guide).getByRole('link', { name: 'See the cases they made' })).toHaveAttribute(
      'href',
      '/cases',
    );
  });

  it('keeps each page its own thread while the tab lives', async () => {
    const router = renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    let p = await panel();
    await userEvent.click(within(p).getByRole('button', { name: 'What is a scenario?' }));
    await within(p).findByRole('heading', { name: 'What is a scenario?', level: 4 });
    await router.navigate('/cases');
    p = await panel();
    await waitFor(() => expect(within(p).getByText('Suggested questions about Cases')).toBeInTheDocument());
    expect(within(p).queryByRole('heading', { name: 'What is a scenario?' })).not.toBeInTheDocument();
    await router.navigate('/scenarios');
    p = await panel();
    expect(
      await within(p).findByRole('heading', { name: 'What is a scenario?', level: 4 }),
    ).toBeInTheDocument();
  });

  it("shows the guide and says live answers need the judges' account where the role has not the live agents", async () => {
    env.trial = false;
    resetMock('demo');
    renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const p = await panel();
    expect(await within(p).findByText(PAGE_JUDGES_ONLY)).toBeInTheDocument();
    expect(within(p).getByText('Judges only')).toBeInTheDocument();
    expect(within(p).getByRole('button', { name: 'What is a scenario?' })).toBeDisabled();
    expect(within(p).queryByRole('textbox', { name: 'Your own question' })).not.toBeInTheDocument();
    expect(within(p).getByRole('region', { name: 'About this page: Scenarios' })).toBeInTheDocument();
    expect(posts).toHaveLength(0);
  });

  it('locks asking on an instance with no model key, and opens it with a key, the guide one click away', async () => {
    env.trial = false;
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({ ...fixtures.settings, providerConfigured: false, mock: false }),
      ),
    );
    renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const p = await panel();
    expect(await within(p).findByText(/need a model key, and none is configured here/)).toBeInTheDocument();
    expect(within(p).getByText('Locked: no key')).toBeInTheDocument();
    server.resetHandlers();
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({ ...fixtures.settings, providerConfigured: true, mock: false }),
      ),
    );
    await userEvent.keyboard('{Escape}');
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const again = await panel();
    const box = await within(again).findByRole('textbox', { name: 'Your own question' });
    expect(box).toBeEnabled();
    expect(within(again).getByRole('button', { name: 'About this page: Scenarios' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });

  it('reads a 403 live_agents_only and a 409 live_unavailable as notes, not faults', async () => {
    env.trial = false;
    server.use(
      http.post(`${BASE}/page-questions`, () =>
        HttpResponse.json({ error: 'live_agents_only', detail: 'needs Shutter_LiveAgents' }, { status: 403 }),
      ),
    );
    renderPage();
    await userEvent.click(screen.getByRole('button', { name: 'Ask Shutter' }));
    const p = await panel();
    await userEvent.click(await within(p).findByRole('button', { name: 'What is a scenario?' }));
    expect(await within(p).findByText(PAGE_JUDGES_ONLY)).toBeInTheDocument();
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
    await userEvent.click(within(p).getByRole('button', { name: 'Which scenario should I play first?' }));
    expect(await within(p).findByRole('status')).toHaveTextContent(/budget/i);
  });

  it('labels where an answer came from: sample data in the trial, the mimic, or the live model', () => {
    const q = { mode: 'live', model: 'claude-opus-5-5', answeredAt: '2026-11-08T10:00:00Z' };
    expect(pageProvenance(q)).toBe(PAGE_SAMPLE_LABEL);
    env.trial = false;
    expect(pageProvenance(q)).toBe('Answered live with claude-opus-5-5');
    expect(pageProvenance({ ...q, model: 'mock' })).toBe('Answered by the API mimic: no model was called');
    expect(pageProvenance({ ...q, model: null })).toBe('Answered live');
  });
});
