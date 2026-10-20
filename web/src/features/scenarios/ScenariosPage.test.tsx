import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import ScenariosPage from './ScenariosPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderScenarios() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <ScenariosPage />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** A scenario's card, found by its Run button. */
async function card(id: string) {
  const run = await screen.findByRole('button', { name: `Run ${id}` });
  return run.closest<HTMLElement>('.mantine-Card-root')!;
}

describe('ScenariosPage', () => {
  beforeEach(() => resetMock('approver'));

  it('offers every mode outside the demo', async () => {
    renderScenarios();
    expect(await screen.findByRole('radio', { name: 'Single investigator' })).toBeInTheDocument();
  });

  it("greys out a scenario in a mode it isn't defined for, and says which modes it is", async () => {
    renderScenarios();
    expect(await screen.findByRole('button', { name: 'Run S7' })).toBeEnabled();
    await userEvent.click(screen.getByRole('radio', { name: 'Site policy' }));
    const s7 = await card('S7');
    expect(within(s7).getByRole('button', { name: 'Run S7' })).toBeDisabled();
    expect(
      within(s7).getByText(
        'Not defined for Site policy mode. Its modes: Board, Single investigator, Rules only.',
      ),
    ).toBeInTheDocument();
    expect(within(await card('S2')).getByRole('button', { name: 'Run S2' })).toBeEnabled();
  });
});
