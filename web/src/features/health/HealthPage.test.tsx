import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import HealthPage from './HealthPage';

// The page reads TRIAL when it renders, so each test can say whether it is the demo
const demo = vi.hoisted(() => ({ on: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return demo.on;
  },
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/** A report with a Yes, a No the demo explains, a No it does not, and a value the report left out. */
const REPORT = {
  production_class: true,
  ai_hub_present: false,
  interoperability: false,
  adt_in: null,
};

function renderHealth() {
  server.use(http.get('/api/shutter/health', () => HttpResponse.json(REPORT)));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <HealthPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The report's row for a check, by its name in words. */
async function row(name: string) {
  return (await screen.findByRole('rowheader', { name })).closest('tr')!;
}

describe('HealthPage', () => {
  beforeEach(() => resetMock('approver'));

  it('writes Yes, No or Not reported beside every mark, and says nothing of the demo outside it', async () => {
    demo.on = false;
    renderHealth();
    expect(within(await row('Production class compiled')).getByText('Yes')).toBeInTheDocument();
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(hub).not.toHaveTextContent('Not in the demo');
    expect(
      within(await row('Interoperability enabled in the namespace')).getByText('No'),
    ).toBeInTheDocument();
    expect(within(await row('ADT inbound folder')).getByText('Not reported')).toBeInTheDocument();
    expect(screen.queryByText(/A No that carries a note saying/)).not.toBeInTheDocument();
  });

  it('says in the demo why a piece the recorded instance did not have is No, and only for those pieces', async () => {
    demo.on = true;
    renderHealth();
    const hub = await row('AI Hub installed');
    expect(within(hub).getByText('No')).toBeInTheDocument();
    expect(hub).toHaveTextContent(/Not in the demo: the demo was recorded on an instance without AI Hub\./);
    const interop = await row('Interoperability enabled in the namespace');
    expect(interop).not.toHaveTextContent('Not in the demo');
    expect(screen.getByText(/A No that carries a note saying/)).toBeInTheDocument();
  });
});
