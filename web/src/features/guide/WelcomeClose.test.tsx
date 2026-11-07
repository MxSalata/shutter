import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { LIVE_WELCOME_KEY, LiveWelcome } from '@/trial/LiveWelcome';
import { INITIAL } from './controller';
import { Guide } from './Guide';
import { forgetProgress } from './storage';
import { useGuide } from './store';

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = () => {};
});
afterAll(() => server.close());

function renderInApp(element: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/', element }]);
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** A first visit's prompt is gone the moment it closes: no fading layer for a screenshot or a first click to meet. */
describe('a welcome closes at once', () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.clear();
    forgetProgress();
    useGuide.setState({ progress: INITIAL, phase: 'closed', snoozed: false });
  });

  it('the trial guide', async () => {
    renderInApp(<Guide />);
    const dialog = await screen.findByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await userEvent.click(dialog.querySelector('button.mantine-Modal-close') as HTMLElement);
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(document.querySelector('.mantine-Modal-overlay')).toBeNull();
  });

  it('the live prompt', async () => {
    expect(localStorage.getItem(LIVE_WELCOME_KEY)).toBeNull();
    renderInApp(<LiveWelcome />);
    await screen.findByRole('dialog', { name: 'New here?' });
    await userEvent.click(screen.getByRole('button', { name: 'Not now' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(document.querySelector('.mantine-Modal-overlay')).toBeNull();
  });
});
