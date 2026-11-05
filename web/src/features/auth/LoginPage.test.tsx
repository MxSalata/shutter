import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import type { DetailLevel } from '@/env/mode';
import { PROOF, proofFrom } from '@/lib/proof';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import LoginPage from './LoginPage';
import { ProofPanel } from './ProofPanel';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
// Each render sets the Detail level it needs, so nothing is reset after a test, while its components still listen
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const HEADLINE =
  'Shutter fixes a failed HL7 transfer only when it can show the fix is safe.';
const PURPOSE =
  'When a patient movement fails to reach another system, Shutter finds out why and writes a fix only when it is safe to.';

function renderLogin(demo: boolean, detail: DetailLevel = 'plain') {
  useAppearance.setState({ detail });
  server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo })));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/login', element: <LoginPage /> },
      { path: '/home', element: <h1>Home</h1> },
    ],
    { initialEntries: ['/login'] },
  );
  const view = render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return { client, ...view };
}

/** A demo install's page, once its health report has said so (the proof panel's figures wait for it). */
async function renderDemoLogin(detail: DetailLevel = 'plain') {
  const view = renderLogin(true, detail);
  await screen.findByText(/The demo installs two users/);
  return view;
}

/**
 * The words one viewport reads on the first layer: the other viewport's pieces (marked `data-viewport`; the CSS hides
 * them from a phone or a laptop, and jsdom has no CSS) and the closed disclosures are left out.
 */
function wordsOn(container: HTMLElement, viewport: 'laptop' | 'phone'): string[] {
  const clone = container.cloneNode(true) as HTMLElement;
  const other = viewport === 'laptop' ? 'phone' : 'laptop';
  for (const el of clone.querySelectorAll(`[data-viewport="${other}"]`)) el.remove();
  return layer1Words(clone);
}

const wordCount = (text: string | null | undefined) => (text ?? '').split(/\s+/).filter(Boolean).length;

describe('LoginPage', () => {
  beforeEach(() => resetMock(null));

  it('names the demo users and their password on a demo instance', async () => {
    renderLogin(true);
    expect(await screen.findByText(/The demo installs two users/)).toBeInTheDocument();
  });

  it('keeps the demo password off the page elsewhere', async () => {
    const { client } = renderLogin(false);
    expect(await screen.findByRole('button', { name: 'Sign in' })).toBeInTheDocument();
    await waitFor(() => expect(client.getQueryState(keys.health)?.status).toBe('success'));
    expect(screen.queryByText(/The demo installs two users/)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Demo users' })).not.toBeInTheDocument();
  });

  it("names the online demo's account outside the disclosure on a demo instance", async () => {
    await renderDemoLogin();
    const line = screen.getByText(/On the online demo, sign in as/);
    expect(line).toHaveTextContent('On the online demo, sign in as demo / shutter.');
    expect(screen.getByRole('button', { name: 'Demo users' })).toHaveAttribute('aria-expanded', 'false');
    expect(line.closest('[data-tech-detail]')).toBeNull();
    expect(screen.getByText(/They are for your own instance/)).toBeInTheDocument();
  });

  it('names no online demo account on a site install', async () => {
    const { client } = renderLogin(false);
    expect(await screen.findByRole('button', { name: 'Sign in' })).toBeInTheDocument();
    await waitFor(() => expect(client.getQueryState(keys.health)?.status).toBe('success'));
    expect(screen.queryByText(/On the online demo, sign in as/)).not.toBeInTheDocument();
  });

  it('keeps the demo users in a disclosure, closed until it is opened', async () => {
    renderLogin(true);
    const toggle = await screen.findByRole('button', { name: 'Demo users' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'true');
  });

  it('has one h1, "Sign in", and the sign-in form with its labels', async () => {
    renderLogin(true);
    expect(await screen.findByRole('heading', { level: 1, name: 'Sign in' })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
    expect(screen.getByLabelText(/User name/)).toBeRequired();
    expect(screen.getByLabelText(/Password/)).toBeRequired();
    expect(screen.getByLabelText(/User name/)).toHaveAttribute('autocomplete', 'username');
    expect(screen.getByLabelText(/Password/)).toHaveAttribute('autocomplete', 'current-password');
  });

  it('signs in with the form and goes on to Home', async () => {
    const { client } = renderLogin(true);
    await userEvent.type(await screen.findByLabelText(/User name/), 'approver');
    await userEvent.type(screen.getByLabelText(/Password/), 'shutter');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('heading', { name: 'Home' })).toBeInTheDocument();
    await waitFor(() =>
      expect(client.getQueryData<{ username: string }>(keys.me)?.username).toBe('approver'),
    );
  });

  it('says the user name or the password is wrong, in an alert, when the sign-in is refused', async () => {
    renderLogin(true);
    await userEvent.type(await screen.findByLabelText(/User name/), 'approver');
    await userEvent.type(screen.getByLabelText(/Password/), 'not-the-password');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('The user name or the password is wrong.');
  });

  it("shows a 403's own reason: it comes from outside the API, not from the password", async () => {
    server.use(
      http.post('/api/shutter/session', () =>
        HttpResponse.json({ error: 'forbidden', detail: 'This needs Shutter_WebApp' }, { status: 403 }),
      ),
    );
    renderLogin(true);
    await userEvent.type(await screen.findByLabelText(/User name/), 'approver');
    await userEvent.type(screen.getByLabelText(/Password/), 'shutter');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('This needs Shutter_WebApp (forbidden)');
    expect(alert).not.toHaveTextContent('The user name or the password is wrong.');
  });
});

describe('LoginPage, the headline and what it is for', () => {
  beforeEach(() => resetMock(null));

  it("leads with the app's best line in a section it names, the plain purpose line right under it", async () => {
    renderLogin(false);
    const headline = await screen.findByRole('heading', { level: 2, name: HEADLINE });
    const section = screen.getByRole('region', { name: HEADLINE });
    expect(section).toContainElement(headline);
    expect(section).toHaveTextContent(PURPOSE);
    expect(section).toHaveTextContent('Failed messages, investigated, gated, released and verified');
  });

  it('explains "HL7 transfer" in a term the keyboard reaches', async () => {
    renderLogin(false);
    const term = (await screen.findByText('HL7 transfer')).closest('.term');
    expect(term).not.toBeNull();
    expect(term).toHaveAttribute('tabindex', '0');
    const described = term?.getAttribute('aria-describedby');
    expect(document.getElementById(described ?? '')).toHaveTextContent(
      'A message telling another hospital system that a patient moved ward.',
    );
  });

  it('shows HL7 transfer as plain text in Technical, where an engineer knows the term', async () => {
    const { container } = renderLogin(false, 'technical');
    await screen.findByRole('heading', { level: 2, name: HEADLINE });
    expect(container.querySelector('.term')).toBeNull();
  });

  it('gives the expert sentence in a disclosure, closed in Plain and open in Technical', async () => {
    const { unmount } = renderLogin(false);
    expect(await screen.findByRole('button', { name: 'How it decides' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    unmount();
    renderLogin(false, 'technical');
    expect(await screen.findByRole('button', { name: 'How it decides' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByText(/For HL7 v2 ADT feeds on InterSystems IRIS for Health/)).toBeInTheDocument();
  });
});

describe('LoginPage, the proof on a demo install', () => {
  beforeEach(() => resetMock(null));

  it("shows 24 of 24 as the board's own figure, with its words and its status", async () => {
    await renderDemoLogin();
    const board = PROOF.board!;
    const tile = screen.getByText(`${board.matched} of ${board.scored}`).closest('.stat-tile');
    expect(tile).toHaveAttribute('data-tone', 'positive');
    expect(tile).toHaveTextContent('where the board chose the expected action');
    expect(tile).toHaveTextContent('As expected');
  });

  it('draws the board against Rules only as two bars on the same failures, never a lone 4 of 11', async () => {
    const { container } = await renderDemoLogin();
    const played = PROOF.played!;
    expect(
      screen.getByRole('img', { name: `The board: ${played.board} of ${played.of}` }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('img', { name: `Rules only: ${played.rules} of ${played.of}` }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('figure', {
        name: `the board against Rules only (no agents), on the same ${played.of} failures`,
      }),
    ).toBeInTheDocument();
    expect(screen.getByText(`${played.board} against ${played.rules}`)).toBeInTheDocument();
    // The visible text never gives Rules only's score as a figure of its own
    expect(container.textContent).not.toContain(`${played.rules} of ${played.of}`);
  });

  it('takes every figure from the evaluation (lib/proof.ts), never from typing', async () => {
    const { container } = await renderDemoLogin();
    expect(PROOF.board).toMatchObject({ matched: 24, scored: 24 });
    expect(PROOF.played).toMatchObject({ of: 11, board: 11, rules: 4 });
    expect(container).toHaveTextContent(
      `From ${PROOF.runs} runs recorded with the real agents on IRIS AI Hub.`,
    );
  });

  it('shows another evaluation own figures, and says when not all were as expected', () => {
    const other = proofFrom({
      sources: { recorded_on: 'irishealth-community:2026.3.0AI.154.0' },
      totals: { runs: 40, passes: 10, scored_passes: 9, board_matches: 8, cases: 9 },
      passes: [],
    });
    render(
      <MantineProvider theme={theme}>
        <ProofPanel figures proof={other} />
      </MantineProvider>,
    );
    const tile = screen.getByText('8 of 9').closest('.stat-tile');
    expect(tile).toHaveAttribute('data-tone', 'attention');
    expect(tile).toHaveTextContent('Not all as expected');
    expect(screen.getByText(/From 40 runs recorded with the real agents/)).toBeInTheDocument();
  });

  it('leaves out the tile a figure is missing from, and keeps the headline', () => {
    const none = proofFrom({ sources: {}, totals: {}, passes: [] });
    const { container } = render(
      <MantineProvider theme={theme}>
        <ProofPanel figures proof={none} />
      </MantineProvider>,
    );
    expect(screen.getByRole('heading', { level: 2, name: HEADLINE })).toBeInTheDocument();
    expect(container.querySelector('.stat-tile')).toBeNull();
    expect(container).not.toHaveTextContent(/recorded with the real agents/);
  });

  it('opens the evaluation in the trial from a link that says so, since a signed-out page has no session', async () => {
    await renderDemoLogin();
    const links = screen.getAllByRole('link', { name: 'Evaluation in the trial' });
    expect(links.length).toBeGreaterThan(0);
    for (const link of links) expect(link.getAttribute('href')).toMatch(/\?trial#\/evaluation$/);
  });

  it('says every write is gated, rehearsed, released and verified', async () => {
    await renderDemoLogin();
    const tile = screen.getByText('Every write').closest('.stat-tile');
    expect(tile).toHaveTextContent('gated, rehearsed, released and verified');
  });

  it('gives a phone one line with both bases in place of the tiles', async () => {
    const { container } = await renderDemoLogin();
    const line = container.querySelector('p[data-viewport="phone"]');
    expect(line).toHaveTextContent(
      'Recorded failures: the board 24 of 24. On the same 11 failures: the board 11, Rules only 4.',
    );
    expect(
      within(line as HTMLElement).getByRole('link', { name: 'Evaluation in the trial' }),
    ).toBeInTheDocument();
    expect(container.querySelector('.stat-tile')?.closest('[data-viewport]')).toHaveAttribute(
      'data-viewport',
      'laptop',
    );
  });

  it('adds the technical captions and the recorded image in Technical', async () => {
    const plain = await renderDemoLogin();
    expect(plain.container).not.toHaveTextContent('scored passes, proposed action');
    expect(plain.container).not.toHaveTextContent('same scenarios, played end to end');
    plain.unmount();
    const technical = await renderDemoLogin('technical');
    expect(technical.container).toHaveTextContent('scored passes, proposed action');
    expect(technical.container).toHaveTextContent('same scenarios, played end to end');
    expect(technical.container).toHaveTextContent(PROOF.recordedOn!.image);
    for (const model of PROOF.models) expect(technical.container).toHaveTextContent(model);
  });

  it("shows the headline and the purpose alone on a hospital's own install", async () => {
    const { client, container } = renderLogin(false);
    await screen.findByRole('button', { name: 'Sign in' });
    await waitFor(() => expect(client.getQueryState(keys.health)?.status).toBe('success'));
    expect(screen.getByRole('heading', { level: 2, name: HEADLINE })).toBeInTheDocument();
    expect(container.querySelector('.stat-tile')).toBeNull();
    expect(container).not.toHaveTextContent(/24 of 24/);
    expect(container).not.toHaveTextContent(/recorded with the real agents/);
    // The way into the trial is for every install
    expect(screen.getByRole('link', { name: 'Open the trial' })).toBeInTheDocument();
  });
});

describe('LoginPage, the way into the trial', () => {
  beforeEach(() => resetMock(null));

  it('is a card of its own with two real links that name the trial, and no password field', async () => {
    renderLogin(false);
    const card = await screen.findByRole('region', { name: 'New to Shutter?' });
    expect(card).toHaveTextContent(
      "Try it in the trial environment: Mikolaj's Fictional Hospital, with made-up patients, where each action replays a recording. Nothing reaches IRIS.",
    );
    const tour = within(card).getByRole('link', { name: 'Take the guided tour of the trial' });
    const open = within(card).getByRole('link', { name: 'Open the trial' });
    expect(tour.getAttribute('href')).toMatch(/\?trial=tour#\/scenarios$/);
    expect(open.getAttribute('href')).toMatch(/\?trial#\/home$/);
    expect(card.querySelector('input')).toBeNull();
    expect(within(card).getByText('No sign-in required')).toBeInTheDocument();
    // The words on the link are "Take the guided tour"; "of the trial" is only for those who do not see the card
    expect(tour).toHaveTextContent(/^Take the guided tour/);
  });

  it('names no trial user and offers none: the trial has its own sign-in page', async () => {
    renderLogin(true);
    await screen.findByText(/The demo installs two users/);
    for (const name of ['Online demo role', 'Judge', 'Choose who you are in the trial'])
      expect(screen.queryByText(name)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Continue/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/Try the demo/)).not.toBeInTheDocument();
    // Only the live form's own password field is on the page
    expect(document.querySelectorAll('input[type="password"]')).toHaveLength(1);
  });

  it("has none of the trial's own chrome: no banner and no Leave trial", async () => {
    renderLogin(true);
    await screen.findByText(/The demo installs two users/);
    expect(screen.queryByRole('button', { name: 'Leave trial' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Trial environment' })).not.toBeInTheDocument();
  });
});

describe('LoginPage, how much it says', () => {
  beforeEach(() => resetMock(null));

  // The spec's budget for the whole page is 110 words (specs/sign-in.md 3). The copy that same spec lists (the headline,
  // the purpose line, three tiles with the comparison's bars, the provenance line, the form and the trial card)
  // comes to more than that, so the budget here is what that copy needs, to stop it growing; each element keeps the
  // limit DESIGN.md 1.4 gives it, checked in the last test.
  const PLAIN_BUDGET = 170;
  const TECHNICAL_BUDGET = Math.round(PLAIN_BUDGET * 1.5);

  it('stays within its budget in Plain, on a laptop and on a phone', async () => {
    const { container } = await renderDemoLogin('plain');
    const laptop = wordsOn(container, 'laptop').length;
    const phone = wordsOn(container, 'phone').length;
    console.log(`sign-in words, Plain: laptop ${laptop}, phone ${phone}`);
    expect(laptop).toBeLessThanOrEqual(PLAIN_BUDGET);
    expect(phone).toBeLessThanOrEqual(PLAIN_BUDGET);
    expect(phone).toBeLessThan(laptop);
  });

  it('stays within 1.5 times that in Technical', async () => {
    const { container } = await renderDemoLogin('technical');
    const laptop = wordsOn(container, 'laptop').length;
    const phone = wordsOn(container, 'phone').length;
    console.log(`sign-in words, Technical: laptop ${laptop}, phone ${phone}`);
    expect(laptop).toBeLessThanOrEqual(TECHNICAL_BUDGET);
    expect(phone).toBeLessThanOrEqual(TECHNICAL_BUDGET);
  });

  it('keeps each element to its limit', async () => {
    await renderDemoLogin('plain');
    // The headline is a hero statement: at most 24 words; the purpose line is one sentence of at most 25
    // (found by its name, so the name is the headline's words)
    expect(screen.getByRole('heading', { level: 2, name: HEADLINE })).toBeInTheDocument();
    expect(wordCount(HEADLINE)).toBeLessThanOrEqual(24);
    expect(wordCount(screen.getByText(/^When a patient movement fails/).textContent)).toBeLessThanOrEqual(25);
    // The trial card's body: at most 40 words
    const card = screen.getByRole('region', { name: 'New to Shutter?' });
    expect(wordCount(card.querySelector('p')?.textContent)).toBeLessThanOrEqual(40);
    // A button's label: at most 4 words (the hidden "of the trial" is for those who cannot see the card)
    for (const link of within(card).getAllByRole('link'))
      expect(layer1Words(link).length).toBeLessThanOrEqual(4);
    // A tile's caption: at most 8 words
    for (const caption of [/^where the board chose/, /^gated, rehearsed/])
      expect(wordCount(screen.getByText(caption).textContent)).toBeLessThanOrEqual(8);
    // The proof line: at most 30 words
    const proof = screen.getAllByText(/recorded with the real agents on IRIS AI Hub/)[0];
    expect(wordCount(proof.textContent)).toBeLessThanOrEqual(30);
  });
});
