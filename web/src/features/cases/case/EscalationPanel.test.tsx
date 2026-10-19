import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from '../CasePage';

let sent: { path: string; body: Record<string, unknown> }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  notifications.clean();
  sent = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method !== 'GET' && request.url.includes('/escalations'))
      sent.push({
        path: new URL(request.url).pathname,
        body: (await request.clone().json()) as Record<string, unknown>,
      });
  });
});

function renderCase(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}`],
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

describe('EscalationPanel', () => {
  it('drafts an email from the case, which a person checks and sends to the team', async () => {
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(within(panel).getByRole('button', { name: /Escalate to system administrators/ }));
    const dialog = await screen.findByRole('dialog', { name: 'Escalate to system administrators' });
    const message = within(dialog).getByRole('textbox', { name: 'Message' }) as HTMLTextAreaElement;
    expect(message.value).toContain('Hospital number: MRN1008 (HOSP)');
    expect(message.value).toContain('Transfer to WARD-B at 2026-10-15 08:20 UTC');
    expect(message.value).not.toMatch(/SYNTH/);
    // No team in the recorded profile: the person addresses it
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /To/ }),
      'bed.management@example.nhs.uk',
    );
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    expect(await screen.findByText('Escalation 1 sent')).toBeInTheDocument();
    // The edited draft is stored first, then sent bound to the stored text's digest
    expect(sent.map((s) => s.path.replace(/.*\/escalations/, ''))).toEqual(['', '/1', '/1/send']);
    expect(sent[1].body.to).toBe('bed.management@example.nhs.uk');
    expect(sent[2].body.bodyDigest).toEqual(expect.any(String));
    expect(await within(panel).findByText('Sent')).toBeInTheDocument();
  });

  it('is not offered on a case Shutter resolved', async () => {
    renderCase('C-000009');
    expect(await screen.findByText('Closed: verified')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Escalations' })).not.toBeInTheDocument();
  });
});
