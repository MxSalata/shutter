import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import ReviewPage from './ReviewPage';
import ReviewsPage from './ReviewsPage';

/** The pages as the trial shows them: recorded reviews on the in-browser mock, nothing sent to IRIS. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

function renderAt(path: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/reviews', element: <ReviewsPage /> },
      { path: '/reviews/:reviewId', element: <ReviewPage /> },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** What a reader sees of a trial page, with the one place "live" may stand ("live system") taken out. */
const visibleWords = () =>
  layer1Words(document.body)
    .join(' ')
    .replace(/live system/gi, '');

describe('the production review in the trial', () => {
  it('offers Start a review, says it replays a recorded one, and names where the dialog takes effect', async () => {
    resetMock('operator');
    renderAt('/reviews');
    const start = await screen.findByRole('button', { name: 'Start a review' });
    expect(screen.getByText('The trial replays a recorded review.')).toBeInTheDocument();
    expect(start).toHaveAttribute('data-tour-action', 'start-review');
    expect(start.closest('[data-tour="reviews-start"]')).not.toBeNull();
    await userEvent.click(start);
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Trial only')).toBeInTheDocument();
    // The dialog says what the trial does, with no word about a live run
    expect(
      await within(dialog).findByText(/The trial replays a recorded review, so no model is called/),
    ).toBeInTheDocument();
    expect(dialog.textContent).not.toMatch(/\blive\b/i);
  });

  it('starts a review in the trial: it opens the recorded one under its new id', async () => {
    renderAt('/reviews');
    await userEvent.click(await screen.findByRole('button', { name: 'Start a review' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(await within(dialog).findByRole('button', { name: 'Start the review' }));
    expect(await screen.findByRole('heading', { name: 'Review PR-000005' })).toBeInTheDocument();
  });

  it('keeps the word "live" to "live system" in the list and in a review, in Plain', async () => {
    renderAt('/reviews');
    await screen.findByRole('link', { name: 'PR-000004' });
    expect(visibleWords()).not.toMatch(/\blive\b/i);
    expect(visibleWords()).toMatch(/Start a review/);
  });

  it('keeps the word "live" out of a review, ranked by the agent or not', async () => {
    renderAt('/reviews/PR-000004');
    await screen.findByRole('heading', { name: 'Review PR-000004' });
    expect(layer1Words(document.body).join(' ')).toMatch(/Ranked and explained \(recorded\)/);
    expect(visibleWords()).not.toMatch(/\blive\b/i);
    cleanup();
    renderAt('/reviews/PR-000001');
    await screen.findByRole('heading', { name: 'Review PR-000001' });
    expect(visibleWords()).not.toMatch(/\blive\b/i);
  });

  it('shows a recorded time as its date and time, never as an age', async () => {
    renderAt('/reviews');
    await screen.findByRole('link', { name: 'PR-000004' });
    expect(screen.queryByText(/ago$/)).not.toBeInTheDocument();
  });
});
