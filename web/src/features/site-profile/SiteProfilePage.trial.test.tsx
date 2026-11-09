import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import SiteProfilePage from './SiteProfilePage';

/** The Site profile in the trial: the words of a save that lasts until the page is left, and the "Trial only" chip. */

vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return true;
  },
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  notifications.clean();
});

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/site-profile', element: <SiteProfilePage /> }], {
    initialEntries: ['/site-profile'],
  });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const SAVE_NOTE = 'A save lasts until you reload or leave.';

describe('SiteProfilePage in the trial', () => {
  it('says a save lasts until you reload or leave, once, wherever the button is', async () => {
    renderPage();
    const notice = (await screen.findByText("Shutter is running on the demo's answers")).closest(
      '[data-tone]',
    )!;
    expect(within(notice as HTMLElement).getByText(SAVE_NOTE)).toBeInTheDocument();
    expect(screen.getAllByText(SAVE_NOTE)).toHaveLength(1);
    // A change moves the button, and the note with it, to the save bar
    await userEvent.click(screen.getByRole('switch', { name: /Downstream Out accepts cancels/ }));
    const bar = await screen.findByRole('region', { name: 'Unsaved changes' });
    expect(within(bar).getByText(SAVE_NOTE)).toBeInTheDocument();
    expect(screen.getAllByText(SAVE_NOTE)).toHaveLength(1);
  });

  it('opens the confirm with the trial’s words and “Trial only”, and saves with the trial’s toast', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('switch', { name: /Downstream Out accepts cancels/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Trial only')).toBeInTheDocument();
    expect(within(dialog).queryByText('Live system')).not.toBeInTheDocument();
    expect(
      within(dialog).getByText(
        "In the trial, saving changes only this browser's copy, until you reload or leave.",
      ),
    ).toBeInTheDocument();
    expect(
      within(dialog).queryByText('This changes what Shutter does at this hospital from the next case.'),
    ).not.toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(screen.getByText('Saved in the trial. It lasts until you reload or leave.')).toBeInTheDocument();
  });

  it('never says “live” in its first layer', async () => {
    const { container } = renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    const text = layer1Words(container).join(' ');
    expect(text).not.toMatch(/\blive\b/i);
  });
});

describe('the reminder for cases left open, in the trial', () => {
  it('is off, and previews a digest with made-up patients, with nothing sent', async () => {
    renderPage();
    const on = await screen.findByRole('switch', { name: /Send reminders for cases left open/ });
    expect(on).not.toBeChecked();
    expect(screen.getByRole('button', { name: 'Preview with made-up patients' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(screen.getByText(/Nothing is sent from here/)).toBeInTheDocument();
    expect(screen.getByText(/C-000101, hospital number TEST-0001/)).toBeInTheDocument();
  });

  it('says whose decision the patient detail is, and the preview follows it', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('switch', { name: /Send reminders for cases left open/ }));
    const select = await screen.findByRole('combobox', { name: 'Patient detail in the mail' });
    expect(select).toHaveValue('identifiers');
    expect(select).toHaveAccessibleDescription(
      "This mail goes out with nobody reviewing it. What it carries is your site's information governance decision.",
    );
    await userEvent.selectOptions(select, 'identifiers_initial');
    expect(screen.getByText(/visit V-1001, first name A/)).toBeInTheDocument();
    await userEvent.selectOptions(select, 'none');
    expect(screen.queryByText(/TEST-0001/)).not.toBeInTheDocument();
  });
});
