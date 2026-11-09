import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { isValidElement, useEffect, useRef, type ReactElement } from 'react';
import { createMemoryRouter, RouterProvider, useLocation } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetAssistantForTests } from '@/features/assistant/store';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { LIVE_WELCOME_KEY } from '@/trial/LiveWelcome';
import { routes } from '@/routes';
import { AppLayout } from './AppLayout';
import { RouteError } from './RouteError';

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/** The pages under the shell, as src/routes.tsx nests them: their errors stay in the shell's outlet. */
function renderFrame(path = '/cases/C-000002', page: ReactElement = <h1>A page</h1>) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: <AppLayout />,
        children: [{ errorElement: <RouteError />, children: [{ path: '*', element: page }] }],
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

describe('the shell', () => {
  beforeEach(() => {
    resetMock('approver');
    resetAssistantForTests();
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
  });

  it('links to the page inside IRIS on a demo instance, in a new tab, apart from the sections', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: true })));
    renderFrame();
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    const link = await within(nav).findByRole('link', { name: 'Shutter in IRIS (opens in a new tab)' });
    expect(link).toHaveAttribute('href', '/csp/healthshare/shutter/Shutter.Portal.Guide.cls');
    expect(link).toHaveAttribute('target', '_blank');
    for (const group of within(nav).getAllByRole('group')) expect(group).not.toContainElement(link);
  });

  it('has no link to it on a site install, where the page answers 404, or before the instance has said', async () => {
    let answered = false;
    server.use(
      http.get('/api/shutter/health', () => {
        answered = true;
        return HttpResponse.json({ ok: true, demo: false });
      }),
    );
    renderFrame();
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    expect(within(nav).queryByRole('link', { name: /Shutter in IRIS/ })).not.toBeInTheDocument();
    await vi.waitFor(() => expect(answered).toBe(true));
    await within(nav).findByRole('link', { name: 'Cases' });
    expect(within(nav).queryByRole('link', { name: /Shutter in IRIS/ })).not.toBeInTheDocument();
  });

  it('moves focus to the page after a page is chosen in the menu, and leaves it alone on the first load', async () => {
    renderFrame('/home');
    const main = document.getElementById('main-content')!;
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    expect(main).not.toHaveFocus();
    const link = within(nav).getByRole('link', { name: /^Cases/ });
    link.focus();
    await userEvent.keyboard('{Enter}');
    await waitFor(() => expect(main).toHaveFocus());
  });

  it('leaves focus where a page put it after a change of page', async () => {
    function OwnFocus() {
      const { pathname } = useLocation();
      const field = useRef<HTMLInputElement>(null);
      useEffect(() => {
        if (pathname === '/cases') field.current?.focus();
      }, [pathname]);
      return <input ref={field} aria-label="Own field" />;
    }
    renderFrame('/home', <OwnFocus />);
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    within(nav)
      .getByRole('link', { name: /^Cases/ })
      .focus();
    await userEvent.keyboard('{Enter}');
    await waitFor(() => expect(screen.getByRole('textbox', { name: 'Own field' })).toHaveFocus());
  });

  it('leaves focus in the Ask Shutter panel when the page changes behind it', async () => {
    const router = renderFrame('/home');
    const main = document.getElementById('main-content')!;
    await userEvent.click(await screen.findByRole('button', { name: 'Ask Shutter' }));
    const panel = await screen.findByRole('dialog', { name: 'Ask Shutter' });
    const heading = within(panel).getByRole('heading', { name: 'Ask Shutter' });
    await waitFor(() => expect(heading).toHaveFocus());
    await act(() => router.navigate('/scenarios'));
    await waitFor(() => expect(router.state.location.pathname).toBe('/scenarios'));
    expect(main).not.toHaveFocus();
    expect(panel).toContainElement(document.activeElement as HTMLElement);
  });

  it('groups the navigation as Operate, Results and Configure, each icon in its section hue', async () => {
    renderFrame();
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    const groups = within(nav).getAllByRole('group');
    expect(groups.map((g) => within(g).getAllByText(/./)[0].textContent)).toEqual([
      'Operate',
      'Results',
      'Configure',
    ]);
    expect(
      within(groups[1])
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toEqual(['Evaluation', 'Health']);
    const hues = Object.fromEntries(
      within(nav)
        .getAllByRole('link')
        .map((a) => [a.textContent?.replace(/\d+$/, ''), a.style.getPropertyValue('--nav-icon')]),
    );
    expect(hues).toMatchObject({
      Scenarios: 'var(--shutter-hue-cyan)',
      Cases: 'var(--shutter-hue-indigo)',
      Incidents: 'var(--shutter-hue-pink)',
      'Production review': 'var(--shutter-hue-violet)',
      Evaluation: 'var(--shutter-hue-teal)',
      Health: 'var(--shutter-hue-indigo)',
      'Site profile': 'var(--shutter-hue-teal)',
      'Agent library': 'var(--shutter-hue-violet)',
      'Settings and costs': 'var(--shutter-hue-cyan)',
    });
    // A case's page is under Cases: its entry is the active one
    expect(within(nav).getByRole('link', { name: /^Cases/ })).toHaveAttribute('data-active');
    expect(within(nav).getByRole('link', { name: 'Scenarios' })).not.toHaveAttribute('data-active');
  });

  it('shows the Technical group, with the API reference, only while the Detail switch is on Technical', async () => {
    renderFrame();
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    await within(nav).findByRole('link', { name: 'Cases' });
    expect(within(nav).queryByRole('link', { name: 'API reference' })).not.toBeInTheDocument();
    expect(within(nav).queryByRole('group', { name: 'Technical' })).not.toBeInTheDocument();
    act(() => useAppearance.setState({ detail: 'technical' }));
    try {
      const group = within(nav).getByRole('group', { name: 'Technical' });
      const link = within(group).getByRole('link', { name: 'API reference' });
      expect(link).toHaveAttribute('href', '/api');
      expect(link.style.getPropertyValue('--nav-icon')).toBe('var(--shutter-hue-pink)');
      expect(within(nav).getAllByRole('group')).toHaveLength(4);
    } finally {
      act(() => useAppearance.setState({ detail: 'plain' }));
    }
    expect(within(nav).queryByRole('link', { name: 'API reference' })).not.toBeInTheDocument();
  });

  it('keeps the header and the navigation when a page fails, with a way to another page', async () => {
    // The pages' boundary sits between AppLayout and the pages in the app's own routes, as here
    const appLayout = routes[1].children![0];
    expect(isValidElement(appLayout.element) && appLayout.element.type).toBe(AppLayout);
    expect(appLayout.children).toHaveLength(1);
    const pages = appLayout.children![0];
    expect(isValidElement(pages.errorElement) && pages.errorElement.type).toBe(RouteError);
    expect(pages.children!.length).toBeGreaterThan(10);

    const silenced = vi.spyOn(console, 'error').mockImplementation(() => {});
    function BrokenPage(): never {
      throw new Error('a recorded case with an unexpected shape');
    }
    renderFrame('/cases/C-000002', <BrokenPage />);
    const main = await screen.findByRole('main');
    expect(within(main).getByRole('heading', { name: 'This page failed' })).toBeInTheDocument();
    expect(within(main).getByText('a recorded case with an unexpected shape')).toBeInTheDocument();
    expect(within(main).getByRole('link', { name: 'Go to Home' })).toHaveAttribute('href', '/home');
    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument();
    expect(screen.getByRole('banner')).toBeInTheDocument();
    silenced.mockRestore();
  });

  it('counts the cases that need a person beside Cases, in words for a screen reader', async () => {
    renderFrame();
    // The recording holds one case waiting for an approval, and its escalated and blocked cases
    const cases = await screen.findByRole('link', { name: /^Cases \d+ cases? needs? a person$/ });
    expect(within(cases).getByText(/^\d+$/)).toBeInTheDocument();
  });

  it('counts a failed case beside Cases, and not one a person gave up', async () => {
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        if (new URL(request.url).searchParams.get('state') !== 'failed')
          return HttpResponse.json({ items: [], total: 0 });
        return HttpResponse.json({
          items: [
            { caseId: 'C-1', state: 'failed', disposition: '' },
            { caseId: 'C-2', state: 'failed', disposition: 'abandoned' },
          ],
          total: 2,
        });
      }),
    );
    renderFrame();
    expect(await screen.findByRole('link', { name: 'Cases 1 case needs a person' })).toBeInTheDocument();
  });

  it('shows no count when no case needs a person', async () => {
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    renderFrame();
    expect(await screen.findByRole('heading', { name: 'A page' })).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 200));
    expect(screen.getByRole('link', { name: 'Cases' })).toBeInTheDocument();
    expect(screen.queryByText(/needs? a person/)).not.toBeInTheDocument();
  });

  it('carries the Detail switch in the header, and offers the trial from Help on a live page', async () => {
    renderFrame();
    const header = (await screen.findByRole('heading', { name: 'A page' })).ownerDocument.querySelector(
      'header',
    )!;
    expect(within(header).getByRole('radiogroup', { name: 'Detail' })).toBeInTheDocument();
    expect(within(header).getByRole('button', { name: 'Help' })).toBeInTheDocument();
    // A live page has no trial chrome: no banner, no pill
    expect(screen.queryByRole('region', { name: 'Trial environment' })).not.toBeInTheDocument();
    expect(header.querySelector('.trial-pill')).toBeNull();
    expect(within(header).queryByText('DEMO')).not.toBeInTheDocument();
  });
});
