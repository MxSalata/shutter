import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { keys } from '@/api/hooks';
import type { Me } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import LoginPage from './LoginPage';

/** The demo build opened with `?as=demo`: "Try the demo" signs in as the public demo's role (src/env/mode.ts). */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('?as=demo', true) };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('LoginPage, the demo opened as the public demo', () => {
  beforeEach(() => resetMock(null));

  it("signs in as the public demo's role, which cannot configure or run scenarios", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const router = createMemoryRouter(
      [
        { path: '/login', element: <LoginPage /> },
        { path: '/scenarios', element: <h1>Scenarios</h1> },
      ],
      { initialEntries: ['/login'] },
    );
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={client}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    await userEvent.click(await screen.findByRole('button', { name: /^Try the demo \(live hospital/ }));
    expect(await screen.findByRole('heading', { name: 'Scenarios' })).toBeInTheDocument();
    await waitFor(() => expect(client.getQueryData<Me>(keys.me)?.username).toBe('demo'));
    expect(client.getQueryData<Me>(keys.me)?.can).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: false,
      liveAgents: false,
    });
  });
});
