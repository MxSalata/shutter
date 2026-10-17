import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { keys } from '@/api/hooks';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import LoginPage from './LoginPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderLogin(demo: boolean) {
  server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo })));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/login', element: <LoginPage /> }], {
    initialEntries: ['/login'],
  });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return client;
}

describe('LoginPage', () => {
  beforeEach(() => resetMock(null));

  it('names the demo users and their password on a demo instance', async () => {
    renderLogin(true);
    expect(await screen.findByText(/The demo installs two users/)).toBeInTheDocument();
  });

  it('keeps the demo password off the page elsewhere', async () => {
    const client = renderLogin(false);
    expect(await screen.findByRole('button', { name: 'Sign in' })).toBeInTheDocument();
    await waitFor(() => expect(client.getQueryState(keys.health)?.status).toBe('success'));
    expect(screen.queryByText(/The demo installs two users/)).not.toBeInTheDocument();
  });
});
