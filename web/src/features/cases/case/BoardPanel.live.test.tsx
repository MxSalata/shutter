import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { BoardPanel } from './BoardPanel';

// The page's environment is fixed when it starts, and BoardPanel reads it in a top-level constant
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  TRIAL: false,
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
beforeEach(() => resetMock('approver'));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

it('has no recording control on a live page, and loads nothing for one', async () => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <BoardPanel caseId="C-000008" open mode="board" portalBase="/csp/" />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
  await screen.findByRole('region', { name: 'Coordinator' });
  expect(screen.getAllByRole('button', { name: 'Show the finding' })).toHaveLength(3);
  expect(screen.queryByRole('button', { name: 'Show the recording' })).toBeNull();
  expect(screen.queryByTestId('run-recording')).toBeNull();
});
