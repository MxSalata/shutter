import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import { Timestamp } from '@/components/Timestamp';
import LoginPage from '@/features/auth/LoginPage';
import CasePage from '@/features/cases/CasePage';
import ReviewPage from '@/features/reviews/ReviewPage';
import ReviewsPage from '@/features/reviews/ReviewsPage';
import ScenariosPage from '@/features/scenarios/ScenariosPage';
import SettingsPage from '@/features/settings/SettingsPage';

/** The screens as the demo build shows them: recorded data on the in-browser mock, with no IRIS behind it. */
vi.mock('@/demo', () => ({ DEMO: true, DEMO_USER: { username: 'approver', password: 'shutter' } }));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderAt(path: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/login', element: <LoginPage /> },
      { path: '/scenarios', element: <ScenariosPage /> },
      { path: '/cases/:caseId', element: <CasePage /> },
      { path: '/settings', element: <SettingsPage /> },
      { path: '/reviews', element: <ReviewsPage /> },
      { path: '/reviews/:reviewId', element: <ReviewPage /> },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('the demo', () => {
  beforeEach(() => resetMock('approver'));

  it('leads its sign-in page with Try the demo, filled, and signs in with it', async () => {
    resetMock(null);
    renderAt('/login');
    const demo = await screen.findByRole('button', { name: 'Try the demo (recorded runs)' });
    const signIn = screen.getByRole('button', { name: 'Sign in' });
    expect(demo).toHaveAttribute('data-variant', 'filled');
    expect(signIn).toHaveAttribute('data-variant', 'default');
    // The demo's button comes first; the form with the demo users' password is second
    expect(demo.compareDocumentPosition(signIn) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getByText('or sign in as a demo user')).toBeInTheDocument();
    await userEvent.click(demo);
    expect(await screen.findByRole('heading', { name: 'Scenarios' })).toBeInTheDocument();
  });

  it('leaves out the single investigator, which has no recordings', async () => {
    renderAt('/scenarios');
    expect(await screen.findByRole('radio', { name: 'Board' })).toBeInTheDocument();
    expect(screen.queryByRole('radio', { name: 'Single investigator' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('radio', { name: 'Site policy' }));
    expect(
      await screen.findByText('Not defined for Site policy mode. Its modes: Board, Rules only.'),
    ).toBeInTheDocument();
  });

  it('starts a judge on the recorded cases, found by scenario and mode', async () => {
    renderAt('/scenarios');
    const card = await screen.findByRole('region', { name: 'Start here' });
    const links = await within(card).findAllByRole('link');
    expect(links.map((a) => [a.textContent, a.getAttribute('href')])).toEqual([
      ['Case C-000002', '/cases/C-000002'],
      ['Case C-000021', '/cases/C-000021'],
      ['Case C-000008', '/cases/C-000008'],
      ['Rules and board side by side', '/cases/C-000008?show=compare'],
      ['Case C-000012', '/cases/C-000012'],
      ['Incident I-000001', '/incidents/I-000001'],
      ['Settings and costs', '/settings'],
      ['Evaluation', '/evaluation'],
    ]);
    expect(within(card).getByText(/S8 in Rules only mode/)).toBeInTheDocument();
    expect(within(card).getByText(/^A short path through the recorded cases\./)).toBeInTheDocument();
  });

  it("puts the scenario cards' headings under their own heading, not under Start here", async () => {
    renderAt('/scenarios');
    const start = await screen.findByRole('heading', { name: 'Start here', level: 2 });
    const run = await screen.findByRole('button', { name: 'Run S2' });
    const every = screen.getByRole('heading', { name: 'Every scenario', level: 2 });
    const card = within(run.closest<HTMLElement>('.mantine-Card-root')!).getByRole('heading', { level: 3 });
    expect(start.compareDocumentPosition(every) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(every.compareDocumentPosition(card) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('keeps the induction prompt below the scenarios, under the guided path', async () => {
    renderAt('/scenarios');
    const prompt = await screen.findByText('Shutter is running on the shipped site profile');
    const card = screen.getByRole('region', { name: 'Start here' });
    const last = screen.getByRole('button', { name: 'Run S19' });
    expect(card.compareDocumentPosition(prompt) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(last.compareDocumentPosition(prompt) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('shows the recorded reviews of both productions and starts none', async () => {
    renderAt('/reviews');
    const past = await screen.findByRole('region', { name: 'Past reviews' });
    expect(await within(past).findByRole('link', { name: 'PR-000003' })).toBeInTheDocument();
    expect(within(past).getAllByText('Shutter.Production')).toHaveLength(2);
    expect(within(past).getAllByText('Hospital.Production')).toHaveLength(2);
    expect(
      screen.getByText(/The online demo shows the recorded reviews of both productions/),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Start the review' })).not.toBeInTheDocument();
  });

  it('says before an annotation that the demo keeps none, and shows its polite refusal', async () => {
    renderAt('/reviews/PR-000003');
    expect(await screen.findByRole('heading', { name: 'Review PR-000003' })).toBeInTheDocument();
    const findings = screen.getByRole('region', { name: 'Findings' });
    await userEvent.click((await within(findings).findAllByRole('button', { name: /^Annotate F\d+, / }))[0]);
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/The online demo keeps no annotations: it answers/)).toBeInTheDocument();
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Reason/ }), 'Tried in the demo');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Mark as intended' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(/never in the production/);
  });

  it('shows a recorded time as its date and time, never as an age', () => {
    render(
      <MantineProvider theme={theme}>
        <Timestamp iso="2026-10-15T08:20:00Z" age />
      </MantineProvider>,
    );
    expect(screen.getByText('15 Oct, 09:20:00 BST')).toBeInTheDocument();
    expect(screen.queryByText(/ago/)).not.toBeInTheDocument();
  });

  it('says the held case is a replay, and links nothing into a portal it does not have', async () => {
    const { container } = renderAt('/cases/C-000002');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(await within(approval).findByText('Demo replay')).toBeInTheDocument();
    expect(await screen.findByText('Message trace (on an instance)')).toBeInTheDocument();
    expect(screen.getByText('Workflow trace (on an instance)')).toBeInTheDocument();
    await userEvent.click(await screen.findByRole('button', { name: /^3\. What was proposed/ }));
    const board = await screen.findByRole('region', { name: 'The board' });
    for (const row of within(board).getAllByRole('button', { name: /^(Resend|Escalate) / }))
      if (row.getAttribute('aria-expanded') !== 'true') await userEvent.click(row);
    expect(
      (await within(board).findAllByText("The run's message in the production (on an instance)")).length,
    ).toBe(4);
    // The audit trail gathers the same links, each a note in the demo
    await userEvent.click(screen.getByRole('tab', { name: 'Audit trail' }));
    const portal = await screen.findByRole('region', { name: 'In the Management Portal' });
    expect(within(portal).getAllByText(/: its message \(on an instance\)$/)).toHaveLength(4);
    expect(container.querySelectorAll('a[href*="/csp/"]')).toHaveLength(0);
  });

  it("shows the S8 board case's Visual Trace as a screenshot where it can't link to the portal", async () => {
    const { container } = renderAt('/cases/C-000008?show=compare');
    const compare = await screen.findByRole('region', { name: 'S8 side by side: rules alone and the board' });
    expect(await within(compare).findByText('Wrote WARD-B over WARD-C: version 2 to 3')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Message trace (screenshot)' }));
    const dialog = await screen.findByRole('dialog', {
      name: 'The Visual Trace of an S8 case in board mode',
    });
    expect(within(dialog).getByRole('img')).toHaveAttribute('src', '/s8-visual-trace.png');
    expect(
      within(dialog).getByText(/On an IRIS instance this link opens the Visual Trace/),
    ).toBeInTheDocument();
    expect(within(compare).getByRole('button', { name: 'Visual Trace (screenshot)' })).toBeInTheDocument();
    expect(container.querySelectorAll('a[href*="/csp/"]')).toHaveLength(0);
  });
});

describe('Settings', () => {
  beforeEach(() => resetMock('approver'));

  it('leads with what is configured, not with what is missing', async () => {
    renderAt('/settings');
    expect(
      await screen.findByText('4 agents, replaying recorded live runs (64 replays so far)'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        'Not on this instance: AI Hub, the live runner and a model provider. A replay needs none of them: the recorded runs answer.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/^No AI Hub/)).not.toBeInTheDocument();
    expect(await screen.findByText(/64 replayed runs cost nothing/)).toBeInTheDocument();
  });
});
