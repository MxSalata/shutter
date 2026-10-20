import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { SiteProfile } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
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
    // Addressed to the team the site profile names for the case's receiver; the person may change it
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    expect(to).toHaveValue('integration@example.nhs.uk');
    await userEvent.clear(to);
    await userEvent.type(to, 'bed.management@example.nhs.uk');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    expect(await screen.findByText('Escalation 1 sent')).toBeInTheDocument();
    // The edited draft is stored first, then sent bound to the stored text's digest
    expect(sent.map((s) => s.path.replace(/.*\/escalations/, ''))).toEqual(['', '/1', '/1/send']);
    expect(sent[1].body.to).toBe('bed.management@example.nhs.uk');
    expect(sent[2].body.bodyDigest).toEqual(expect.any(String));
    expect(await within(panel).findByText('Sent')).toBeInTheDocument();
  });

  it("checks the addresses against the site's allowed domains as they are typed", async () => {
    const view = structuredClone(
      (fixtures as unknown as { siteProfile: { profile: SiteProfile } }).siteProfile,
    );
    view.profile.mail = { allowed_domains: ['nhs.uk'] };
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(within(panel).getByRole('button', { name: /Escalate to system administrators/ }));
    const dialog = await screen.findByRole('dialog', { name: 'Escalate to system administrators' });
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    await waitFor(() => expect(to).toHaveAccessibleDescription(/in nhs\.uk/));
    await userEvent.clear(to);
    await userEvent.type(to, 'bed.management@example.com');
    expect(to).toHaveAccessibleDescription(
      /Not allowed: bed\.management@example\.com: not in the allowed domains/,
    );
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
    await userEvent.clear(to);
    await userEvent.type(to, 'bed.management@trust.nhs.uk');
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Cc/ }), 'oncall');
    expect(within(dialog).getByRole('textbox', { name: /Cc/ })).toHaveAccessibleDescription(
      /Not allowed: oncall: must be an address/,
    );
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
    expect(sent).toEqual([{ path: '/api/shutter/cases/C-000008/escalations', body: {} }]);
  });

  it("shows the server's refusal of an address on the field it names", async () => {
    server.use(
      http.patch('/api/shutter/cases/:id/escalations/:seq', () =>
        HttpResponse.json(
          {
            error: 'address_not_allowed',
            field: 'cc',
            detail: 'The cc address is not allowed: it@trust.nhs.uk: not in the allowed domains',
          },
          { status: 422 },
        ),
      ),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(within(panel).getByRole('button', { name: /Escalate to system administrators/ }));
    const dialog = await screen.findByRole('dialog', { name: 'Escalate to system administrators' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /To/ }), 'bed.management@trust.nhs.uk');
    const cc = within(dialog).getByRole('textbox', { name: /Cc/ });
    await userEvent.type(cc, 'it@trust.nhs.uk');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    await waitFor(() =>
      expect(cc).toHaveAccessibleDescription(/The cc address is not allowed: it@trust\.nhs\.uk/),
    );
    expect(within(dialog).getByRole('alert')).toHaveTextContent('Nothing was sent');
    // Changing the address clears the server's word on it
    await userEvent.type(cc, 'x');
    expect(cc).not.toHaveAccessibleDescription(/not allowed/);
  });

  it('closes the case as handled once the email is sent, with the reason and the case version', async () => {
    const closes: Record<string, unknown>[] = [];
    server.events.on('request:start', async ({ request }) => {
      if (request.url.endsWith('/close'))
        closes.push((await request.clone().json()) as Record<string, unknown>);
    });
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(within(panel).queryByRole('button', { name: /Mark as handled/ })).not.toBeInTheDocument();
    await userEvent.click(within(panel).getByRole('button', { name: /Escalate to system administrators/ }));
    const dialog = await screen.findByRole('dialog', { name: 'Escalate to system administrators' });
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    if (!(to as HTMLInputElement).value) await userEvent.type(to, 'bed.management@example.nhs.uk');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    await userEvent.click(await within(panel).findByRole('button', { name: /Mark as handled by the team/ }));
    const close = await screen.findByRole('dialog', { name: 'Mark C-000008 as handled' });
    expect(within(close).getByRole('button', { name: 'Close the case' })).toBeDisabled();
    await userEvent.type(
      within(close).getByRole('textbox', { name: /What the team did/ }),
      'The bed manager placed the patient in WARD-C by hand',
    );
    await userEvent.click(within(close).getByRole('button', { name: 'Close the case' }));
    expect(await screen.findByText('C-000008 marked as handled')).toBeInTheDocument();
    expect(closes).toEqual([
      { reason: 'The bed manager placed the patient in WARD-C by hand', expectedVersion: expect.any(Number) },
    ]);
    // The case reads as resolved, handled by hand, so the escalation panel leaves the page
    await waitFor(() =>
      expect(screen.queryByRole('region', { name: 'Escalations' })).not.toBeInTheDocument(),
    );
  });

  it('is not offered on a case Shutter resolved', async () => {
    renderCase('C-000009');
    expect(await screen.findByText('Closed: verified')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Escalations' })).not.toBeInTheDocument();
  });
});
