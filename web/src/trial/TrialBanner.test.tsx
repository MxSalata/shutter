import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import { AppLayout } from '@/features/shell/AppLayout';
import { INITIAL } from '@/features/guide/controller';
import { useGuide } from '@/features/guide/store';
import { GUIDE_KEY } from '@/features/guide/storage';
import { LIVE_WELCOME_KEY } from './LiveWelcome';
import { journal } from './journal';
import { journalLine, TRIAL_ONLY_WORDS, TRIAL_WORDS } from './words';
import { provideTrialChrome } from './slot';
import { bannerForm, compactBanner, enterTrialPage } from './visit';

/** The page's environment, switched per test: a live page, a trial page of a build IRIS serves, the demo build. */
const page = vi.hoisted(() => ({ trial: true, demoBuild: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return page.trial;
    },
    get ENV() {
      return mode.envFrom(page.trial && !page.demoBuild ? '?trial' : '', page.demoBuild);
    },
  };
});

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

async function renderShell(trial: boolean, demoBuild = false) {
  page.trial = trial;
  page.demoBuild = demoBuild;
  provideTrialChrome(trial ? await import('./chrome') : null);
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: <AppLayout />,
        children: [
          { path: '/cases', element: <h1>Cases page</h1> },
          { path: '/health', element: <h1>Health page</h1> },
        ],
      },
    ],
    { initialEntries: ['/cases'] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  await screen.findByRole('heading', { name: 'Cases page' });
  return router;
}

describe('the trial banner', () => {
  beforeEach(() => {
    resetMock('approver');
    sessionStorage.clear();
    // The guide's welcome and the live first-run prompt have tests of their own
    localStorage.setItem(GUIDE_KEY, JSON.stringify({ ...INITIAL, dismissed: true }));
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
    journal.clear();
  });

  it('stands on every page of a trial, with Leave trial on a build that has a live system', async () => {
    const router = await renderShell(true);
    const banner = screen.getByRole('region', { name: 'Trial environment' });
    expect(banner).toHaveTextContent('Trial environment');
    expect(banner).toHaveTextContent(TRIAL_WORDS);
    expect(within(banner).getByRole('button', { name: "What's different?" })).toBeInTheDocument();
    expect(within(banner).getByRole('button', { name: 'Leave trial' })).toBeInTheDocument();
    expect(screen.getByText('Trial').closest('.trial-pill')).not.toBeNull();
    await act(() => router.navigate('/health'));
    expect(await screen.findByRole('heading', { name: 'Health page' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Trial environment' })).toBeInTheDocument();
  });

  it('has no Leave trial on the demo build, which has no live system to go to', async () => {
    await renderShell(true, true);
    const banner = screen.getByRole('region', { name: 'Trial environment' });
    expect(within(banner).queryByRole('button', { name: 'Leave trial' })).not.toBeInTheDocument();
  });

  it('is not on a live page, nor the pill', async () => {
    await renderShell(false);
    expect(screen.queryByRole('region', { name: 'Trial environment' })).not.toBeInTheDocument();
    expect(document.querySelector('.trial-pill')).toBeNull();
  });

  it('turns to its one-line form once the welcome closes, and stays so on a later page load in the tab', async () => {
    enterTrialPage();
    expect(bannerForm.get()).toBe('full');
    expect(document.documentElement.dataset.shutterBanner).toBe('full');
    await renderShell(true);
    const banner = screen.getByRole('region', { name: 'Trial environment' });
    expect(banner).not.toHaveAttribute('data-compact');
    act(() => compactBanner());
    expect(banner).toHaveAttribute('data-compact');
    expect(banner).toHaveTextContent('Made-up patients; nothing leaves this browser');
    expect(banner).not.toHaveTextContent(TRIAL_WORDS);
    expect(document.documentElement.dataset.shutterBanner).toBe('compact');
    // The tab's next trial page starts in the one-line form
    enterTrialPage();
    expect(bannerForm.get()).toBe('compact');
    expect(document.title).toBe('Shutter (trial)');
  });

  it("lists under Works here only what the role may do: the public demo's role cannot run or configure", async () => {
    resetMock('demo');
    await renderShell(true);
    await userEvent.click(screen.getByRole('button', { name: "What's different?" }));
    const popover = await screen.findByRole('dialog', { name: 'The trial environment' });
    expect(await within(popover).findByText('Approve or reject a plan')).toBeInTheDocument();
    expect(within(popover).getByText('Switch role')).toBeInTheDocument();
    expect(within(popover).queryByText('Run a scenario')).not.toBeInTheDocument();
    expect(within(popover).queryByText('Save the site profile')).not.toBeInTheDocument();
  });

  it('lists running a scenario and saving the site profile for the approver, who may', async () => {
    await renderShell(true);
    await userEvent.click(screen.getByRole('button', { name: "What's different?" }));
    const popover = await screen.findByRole('dialog', { name: 'The trial environment' });
    expect(await within(popover).findByText('Run a scenario')).toBeInTheDocument();
    expect(within(popover).getByText('Save the site profile')).toBeInTheDocument();
    expect(within(popover).getByText('Approve or reject a plan')).toBeInTheDocument();
  });

  it('counts what was answered in the browser, and nothing sent to IRIS', () => {
    journal.add('GET', '/api/shutter/cases', 200);
    journal.add('GET', '/api/shutter/me', 200);
    journal.add('POST', '/api/shutter/cases/C-000002/approvals', 202);
    expect(journalLine(journal.counts())).toBe(
      'Answered in this browser: 2 reads, 1 action. Sent to IRIS: none. Refused by the browser: 0.',
    );
  });
});

describe("the header's help and user menus", () => {
  beforeEach(() => {
    resetMock('approver');
    sessionStorage.clear();
    localStorage.setItem(GUIDE_KEY, JSON.stringify({ ...INITIAL, dismissed: true }));
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
    useGuide.setState({ progress: { ...INITIAL, dismissed: true }, phase: 'closed' });
  });

  const header = () => document.querySelector('header')!;

  it('names the button for the tour in the trial, in words beside its icon', async () => {
    await renderShell(true);
    const tour = within(header()).getByRole('button', { name: 'Tour' });
    expect(tour).toHaveTextContent('Tour');
    expect(tour).toHaveClass('header-help');
    // A tour left part way on this device: Resume tour
    act(() => useGuide.setState({ progress: { ...INITIAL, at: 's8/ask', dismissed: true } }));
    expect(within(header()).getByRole('button', { name: 'Resume tour' })).toHaveTextContent('Resume tour');
    // While the tour runs, the button is the tour's again
    act(() => useGuide.setState({ phase: 'step' }));
    expect(within(header()).getByRole('button', { name: 'Tour' })).toBeInTheDocument();
  });

  it('names it Help on a live page', async () => {
    await renderShell(false);
    const help = within(header()).getByRole('button', { name: 'Help' });
    expect(help).toHaveTextContent('Help');
    expect(help).toHaveClass('header-help');
  });

  it('offers Leave trial in both menus where a live system waits, with no trial-only line', async () => {
    await renderShell(true);
    await userEvent.click(within(header()).getByRole('button', { name: 'Tour' }));
    let menu = await screen.findByRole('menu');
    expect(within(menu).getByRole('menuitem', { name: 'Leave trial' })).toBeInTheDocument();
    expect(screen.queryByText(TRIAL_ONLY_WORDS)).not.toBeInTheDocument();
    expect(menu).not.toHaveAttribute('aria-describedby');
    await userEvent.keyboard('{Escape}');
    await userEvent.click(within(header()).getByRole('button', { name: /^Signed in as / }));
    menu = await screen.findByRole('menu');
    expect(within(menu).getByRole('menuitem', { name: 'Leave trial' })).toBeInTheDocument();
    expect(screen.queryByText(TRIAL_ONLY_WORDS)).not.toBeInTheDocument();
  });

  it('says the demo build is the trial only where Leave trial would be, in both menus', async () => {
    await renderShell(true, true);
    await userEvent.click(within(header()).getByRole('button', { name: 'Tour' }));
    let menu = await screen.findByRole('menu');
    expect(within(menu).queryByRole('menuitem', { name: 'Leave trial' })).not.toBeInTheDocument();
    expect(within(menu).getByText(TRIAL_ONLY_WORDS)).toBeInTheDocument();
    expect(menu).toHaveAccessibleDescription(TRIAL_ONLY_WORDS);
    await userEvent.keyboard('{Escape}');
    await userEvent.click(within(header()).getByRole('button', { name: /^Signed in as / }));
    menu = await screen.findByRole('menu');
    expect(within(menu).queryByRole('menuitem', { name: 'Leave trial' })).not.toBeInTheDocument();
    expect(within(menu).getByText(TRIAL_ONLY_WORDS)).toBeInTheDocument();
    expect(menu).toHaveAccessibleDescription(TRIAL_ONLY_WORDS);
    // The trial's words: "live" only in "live system", no dashes
    expect(TRIAL_ONLY_WORDS).toBe(
      'This copy is the trial only. The live system runs on an IRIS instance: your own install or the online demo.',
    );
    expect(TRIAL_ONLY_WORDS.replace(/\blive system\b/g, '')).not.toMatch(/\blive\b/i);
    expect(TRIAL_ONLY_WORDS).not.toMatch(/[\u2013\u2014]/);
  });
});
