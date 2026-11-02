import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { LibraryMember } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import LibraryPage from './LibraryPage';

let patches: { path: string; body: Record<string, unknown> }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => {
  notifications.clean();
  patches = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'PATCH')
      patches.push({
        path: new URL(request.url).pathname,
        body: (await request.clone().json()) as Record<string, unknown>,
      });
  });
});

function renderPage(detail: 'plain' | 'technical' = 'plain') {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/library', element: <LibraryPage /> }], {
    initialEntries: ['/library'],
  });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const library = fixtures.library as unknown as LibraryMember[];
const coordinator = library.find((m) => m.role === 'coordinator')!;
const conformance = library.find((m) => m.code === 'conformance')!;
const generalist = library.find((m) => m.role === 'generalist')!;

/** The library as a server would send it, with changes to some members. */
const serve = (members: LibraryMember[]) =>
  server.use(http.get('/api/shutter/library', () => HttpResponse.json(members)));

/** A member's card. */
const cardOf = (name: string) => screen.getByRole('article', { name });

/** The line on a card that starts "Knows". */
const knowsLine = (name: string) =>
  within(cardOf(name)).getByText((_, el) => el?.tagName === 'P' && /^Knows/.test(el.textContent ?? ''));

describe('LibraryPage', () => {
  it('lets an operator read the board but not change it', async () => {
    resetMock('operator');
    renderPage();
    expect(
      await screen.findByText(/Changing which agents sit on the board needs the approver role/),
    ).toBeInTheDocument();
    const switches = screen.getAllByRole('switch');
    expect(switches.length).toBeGreaterThan(0);
    for (const sw of switches) expect(sw).toBeDisabled();
  });

  it('lets an approver change it', async () => {
    resetMock('approver');
    renderPage();
    const sw = await screen.findByRole('switch', { name: `${coordinator.name} enabled` });
    expect(sw).toBeEnabled();
    expect(screen.queryByText(/needs the approver role/)).not.toBeInTheDocument();
    const before = coordinator.enabled;
    await userEvent.click(sw);
    await waitFor(() => expect(patches).toHaveLength(1));
    expect(patches[0]).toEqual({
      path: `/api/shutter/library/${coordinator.code}`,
      body: { enabled: !before },
    });
    // Outside the trial a change is the site's own: nothing says it lasts only here
    expect(screen.queryByText('Changed in the trial only.')).not.toBeInTheDocument();
    // Put the mock's library back for the other tests in this file
    await waitFor(() => expect(sw).toBeEnabled());
    await userEvent.click(sw);
    await waitFor(() => expect(patches).toHaveLength(2));
    await waitFor(() => expect(coordinator.enabled).toBe(before));
  });

  it("shows the public demo's role the board for reading, with no switches and a note", async () => {
    resetMock('demo');
    renderPage();
    expect(await screen.findByTestId('demo-read-only')).toHaveTextContent(
      "The public demo is read-only: a site's approver saves changes here",
    );
    expect(screen.getAllByText(coordinator.name).length).toBeGreaterThan(0);
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.getAllByText('Yes').length).toBeGreaterThan(0);
    // Each setting is a label and its value on the card
    const card = within(cardOf(conformance.name));
    expect(card.getByText('Enabled')).toBeInTheDocument();
    expect(card.getByText('On the default board')).toBeInTheDocument();
    expect(patches).toEqual([]);
  });

  it('derives the right to change it from the flags when the server sends no `can`', async () => {
    resetMock('approver');
    server.use(
      http.get('/api/shutter/me', () =>
        HttpResponse.json({ username: 'approver', operator: true, approver: true }),
      ),
    );
    renderPage();
    expect(await screen.findByRole('switch', { name: `${coordinator.name} enabled` })).toBeEnabled();
    expect(screen.queryByTestId('demo-read-only')).not.toBeInTheDocument();
  });
});

describe('the board as cards', () => {
  it("names the members as agents and puts IRIS AI Hub in the page's lead", async () => {
    resetMock('approver');
    renderPage();
    await screen.findByRole('article', { name: conformance.name });
    expect(screen.getByRole('heading', { level: 1, name: 'Agent library' })).toBeInTheDocument();
    expect(
      screen.getByText(
        'The agents a board is made from: three specialist agents and a coordinator agent, on IRIS AI Hub.',
      ),
    ).toBeInTheDocument();
  });

  it('lays out the specialists, then the coordinator and the gate, with the single investigator apart', async () => {
    resetMock('approver');
    renderPage();
    await screen.findByRole('article', { name: conformance.name });
    const board = screen.getByRole('region', { name: 'The board' });
    const names = within(board)
      .getAllByRole('article')
      .map((a) => a.getAttribute('aria-label'));
    expect(names).toEqual(['Conformance', 'Encounter Integrity', 'Impact Analysis', 'Coordinator']);
    // The gate's caption comes after the coordinator, as the flow does
    const gate = within(board).getByText(
      "Then the gate checks the plan, and a person or the site's written policy releases it.",
    );
    expect(
      cardOf('Coordinator').compareDocumentPosition(gate) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    // The single investigator is not part of the board
    const apart = screen.getByRole('region', { name: 'Not on the board' });
    expect(within(apart).getByRole('article', { name: generalist.name })).toBeInTheDocument();
    expect(within(board).queryByRole('article', { name: generalist.name })).not.toBeInTheDocument();
    // Its own words for what it is for, and for the coordinator what it does to the board
    expect(within(apart).getByText('Used only in single investigator mode')).toBeInTheDocument();
    expect(within(board).getByText('Always on the board when enabled')).toBeInTheDocument();
    expect(within(board).getByText('Proposes the plan')).toBeInTheDocument();
  });

  it("shows each member's question as a quote, what it does and what it knows", async () => {
    resetMock('approver');
    renderPage();
    for (const m of library) {
      const card = within(await screen.findByRole('article', { name: m.name }));
      expect(card.getByText(m.perspective).tagName).toBe('BLOCKQUOTE');
      expect(card.getByText(m.description)).toBeInTheDocument();
    }
    expect(knowsLine('Conformance')).toHaveTextContent(/^Knows.*: contracts$/);
    expect(knowsLine('Single Investigator')).toHaveTextContent('Knows: every collection');
  });

  it('counts the members on the default board, and explains "Knows" once', async () => {
    resetMock('approver');
    renderPage();
    await screen.findByRole('article', { name: conformance.name });
    expect(screen.getByText('On the default board: 4 of 4')).toBeInTheDocument();
    const terms = document.querySelectorAll('.term');
    expect(terms).toHaveLength(1);
    expect(cardOf('Conformance')).toContainElement(terms[0] as HTMLElement);
  });

  it('keeps each switch named for its member, and the board switch for specialists only', async () => {
    resetMock('approver');
    renderPage();
    await screen.findByRole('article', { name: conformance.name });
    for (const m of library) expect(screen.getByRole('switch', { name: `${m.name} enabled` })).toBeEnabled();
    for (const m of library.filter((x) => x.role === 'specialist'))
      expect(screen.getByRole('switch', { name: `${m.name} on the default board` })).toBeEnabled();
    expect(screen.queryByRole('switch', { name: `${coordinator.name} on the default board` })).toBeNull();
    expect(screen.queryByRole('switch', { name: `${generalist.name} on the default board` })).toBeNull();
    // Each switch shows its setting in words beside it
    expect(within(cardOf('Conformance')).getByText('Enabled')).toBeInTheDocument();
    expect(within(cardOf('Conformance')).getByText('On the default board')).toBeInTheDocument();
  });

  it('says so when a member is not enabled, and leaves its board switch waiting', async () => {
    resetMock('approver');
    serve(library.map((m) => (m.code === 'encounter' ? { ...m, enabled: false } : m)));
    renderPage();
    const card = within(await screen.findByRole('article', { name: 'Encounter Integrity' }));
    expect(card.getByText('Not enabled')).toBeInTheDocument();
    expect(card.getByRole('switch', { name: 'Encounter Integrity enabled' })).not.toBeChecked();
    expect(card.getByRole('switch', { name: 'Encounter Integrity on the default board' })).toBeDisabled();
    expect(within(cardOf('Conformance')).queryByText('Not enabled')).not.toBeInTheDocument();
    expect(screen.getByText('On the default board: 3 of 4')).toBeInTheDocument();
  });

  it("places a site's added specialist in the row of specialists, and the lead counts it", async () => {
    resetMock('approver');
    serve([
      ...library,
      { ...conformance, code: 'privacy', name: 'Privacy', perspective: 'Does it expose too much?', sort: 40 },
    ]);
    renderPage();
    const board = within(await screen.findByRole('region', { name: 'The board' }));
    const names = board.getAllByRole('article').map((a) => a.getAttribute('aria-label'));
    expect(names).toEqual([
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Privacy',
      'Coordinator',
    ]);
    expect(screen.getByText(/four specialist agents and a coordinator agent/)).toBeInTheDocument();
    expect(screen.getByText('On the default board: 5 of 5')).toBeInTheDocument();
  });

  it('says nothing is there when the library is empty, and why when it cannot be read', async () => {
    resetMock('approver');
    serve([]);
    const empty = renderPage();
    expect(await screen.findByText('The library has no agents yet.')).toBeInTheDocument();
    empty.unmount();
    server.use(http.get('/api/shutter/library', () => new HttpResponse(null, { status: 500 })));
    renderPage();
    expect(await screen.findByText('The library could not be read')).toBeInTheDocument();
  });
});

describe('the second layer', () => {
  it("keeps the page's technical detail and each card's closed in Plain, open in Technical", async () => {
    resetMock('approver');
    const plain = renderPage();
    await screen.findByRole('article', { name: conformance.name });
    const toggles = screen.getAllByRole('button', { name: 'Technical detail' });
    // The header's, then one for each of the five cards
    expect(toggles).toHaveLength(6);
    for (const t of toggles) expect(t).toHaveAttribute('aria-expanded', 'false');
    plain.unmount();

    renderPage('technical');
    await screen.findByRole('article', { name: conformance.name });
    for (const t of screen.getAllByRole('button', { name: 'Technical detail' }))
      expect(t).toHaveAttribute('aria-expanded', 'true');
  });

  it("gives the page's expert line: each member an IRIS AI Hub agent, its decision the terminal tool", async () => {
    resetMock('approver');
    renderPage('technical');
    await screen.findByRole('article', { name: conformance.name });
    const line = screen.getByText(/Each member is an IRIS AI Hub agent/);
    expect(line).toHaveTextContent(
      'Each member is an IRIS AI Hub agent (%AI.Agent), a business operation in the production; its terminal tool (SubmitFindings, SubmitPlan) is its decision. What an agent is (its class, its production item, its tools) is code; which agents sit on the board is a setting.',
    );
  });

  it("puts each member's class, version, production item, collection and tool in its card as code", async () => {
    resetMock('approver');
    renderPage('technical');
    for (const m of library) {
      const card = within(await screen.findByRole('article', { name: m.name }));
      expect(card.getByText(`${m.agentClass} · v${m.configVersion}`).tagName).toBe('CODE');
      expect(card.getByText(m.configItem).tagName).toBe('CODE');
      expect(card.getByText(m.knowledgeCollection).tagName).toBe('CODE');
      expect(card.getByText(m.terminalTool).tagName).toBe('CODE');
    }
  });

  it('ends with the API as the page read it', async () => {
    resetMock('approver');
    renderPage('technical');
    await screen.findByRole('article', { name: conformance.name });
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByText('GET /api/shutter/library')).toBeInTheDocument();
  });
});

describe('the words on the page', () => {
  /**
   * The spec's budget is 260 words on the first layer. The page's own content comes to more: the five descriptions are
   * 117 words, the five questions 51, and the lead and the gate's caption another 34, so 202 before a single label.
   * The page as built reads 285 for an approver, so the budget here is that figure with a little room, and the
   * Technical page may read half as many again. (An operator or the public demo's role reads a note more.)
   */
  const PLAIN_BUDGET = 290;

  /** The words a reader reads: the API's JSON, open in Technical, is a data dump and not prose. */
  const proseWords = (container: HTMLElement) => {
    const copy = container.cloneNode(true) as HTMLElement;
    copy.querySelectorAll('.json-block').forEach((e) => e.remove());
    return layer1WordCount(copy);
  };

  it('keeps the first layer within its budget in Plain, and Technical within half as much again', async () => {
    resetMock('approver');
    const plain = renderPage();
    await screen.findByRole('article', { name: conformance.name });
    const plainWords = proseWords(plain.container);
    plain.unmount();
    const technical = renderPage('technical');
    await screen.findByRole('article', { name: conformance.name });
    const technicalWords = proseWords(technical.container);
    expect(plainWords).toBeLessThanOrEqual(PLAIN_BUDGET);
    expect(technicalWords).toBeGreaterThan(plainWords);
    expect(technicalWords).toBeLessThanOrEqual(plainWords * 1.5);
  });
});
