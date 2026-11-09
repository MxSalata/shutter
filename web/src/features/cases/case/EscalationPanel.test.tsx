import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Escalation } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { recordedSiteProfile } from '@/mocks/profile';
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
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    // The confirm says first that sending is real, and that with no mail server it is only saved, with the live chip
    // beside its title
    expect(within(dialog).getByTestId('confirm-consequence')).toHaveTextContent(
      /^This emails the .+ team through the site's mail server\. With no mail server set, it is saved as an email file and nobody is emailed\.$/,
    );
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
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
    expect(await screen.findByText('Escalation 1 queued')).toBeInTheDocument();
    expect(
      screen.getByText(/Its line shows whether the mail server took it or it was saved as an email file\./),
    ).toBeInTheDocument();
    // The edited draft is stored first, then sent bound to the stored text's digest
    expect(sent.map((s) => s.path.replace(/.*\/escalations/, ''))).toEqual(['', '/1', '/1/send']);
    expect(sent[1].body.to).toBe('bed.management@example.nhs.uk');
    expect(sent[2].body.bodyDigest).toEqual(expect.any(String));
    // The mock saves it as an instance with no mail server does: saved, not delivered, and never Sent
    expect(await within(panel).findByText('Saved, not delivered')).toBeInTheDocument();
    expect(within(panel).queryByText('Sent')).toBeNull();
    await userEvent.click(within(panel).getByRole('button', { name: /Escalation 1/ }));
    expect(await within(panel).findByTestId('escalation-saved')).toHaveTextContent(
      'Saved as an email file, not delivered: no mail server is set, so nobody was emailed. Pass the file on, or set the mail server and send it again.',
    );
    expect(within(panel).getByText('Queued by approver; saved as an email file')).toBeInTheDocument();
    expect(within(panel).getByText(/^Digest of the text saved: demo:/)).toBeInTheDocument();
    expect(within(panel).queryByText(/Sent by /)).toBeNull();
  });

  it("asks about a failed order to check the source's Message Viewer, not to correct the systems by hand", async () => {
    const detail = fixtures.cases['C-000008'].detail;
    server.use(
      http.get('/api/shutter/cases/C-000008', () =>
        HttpResponse.json({
          ...detail,
          failureKind: 'unmappable',
          failureText: 'This message is ORM^O01, not ADT: Shutter resends only ADT',
          failureOutcome: 'error',
        }),
      ),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await within(panel).findByText(/check the source's Message Viewer before anyone re-enters it/);
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    await within(dialog).findByText(/who check the source's Message Viewer before anyone re-enters it/);
    expect(within(dialog).queryByText(/correct them by hand\.$/)).not.toBeInTheDocument();
    expect(panel).not.toHaveTextContent('corrects the systems by hand');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    await screen.findByText('Escalation 1 queued');
    expect(
      await within(panel).findByText(/When the team has checked the source's Message Viewer/),
    ).toBeInTheDocument();
    expect(
      within(panel).queryByText('When the team has corrected the systems by hand. Nothing is sent.'),
    ).toBeNull();
  });

  it('says before the send that shadow mode emails nobody and saves no file, and the toast says the same', async () => {
    const view = recordedSiteProfile()!;
    view.profile.recovery = { mode: 'shadow' };
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    // The button names the team the draft is made for, as the dialog's title does
    const button = await within(panel).findByRole('button', { name: 'Escalate to Integration team…' });
    await userEvent.click(button);
    const dialog = await screen.findByRole('dialog', { name: 'Escalate to Integration team' });
    await waitFor(() =>
      expect(within(dialog).getByTestId('confirm-consequence')).toHaveTextContent(
        /^Shutter is in shadow mode, so sending emails nobody and saves no email file: the escalation will read Not sent\./,
      ),
    );
    expect(within(dialog).getByTestId('confirm-consequence')).not.toHaveTextContent(
      /it is saved as an email file/,
    );
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    expect(await screen.findByText('Escalation 1 recorded, not sent')).toBeInTheDocument();
    expect(
      screen.getByText(/Shadow mode emails nobody and saves no email file, so its line reads Not sent\./),
    ).toBeInTheDocument();
  });

  it("checks the addresses against the site's allowed domains as they are typed", async () => {
    const view = recordedSiteProfile()!;
    view.profile.mail = { allowed_domains: ['nhs.uk'] };
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
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
      /Not allowed: oncall: must be one address with one @/,
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
            detail: 'The cc address is not allowed: it@example.nhs.uk: not in the allowed domains',
          },
          { status: 422 },
        ),
      ),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    // Addresses the page lets through, which the server refuses: the domains changed meanwhile
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    await userEvent.clear(to);
    await userEvent.type(to, 'bed.management@example.nhs.uk');
    const cc = within(dialog).getByRole('textbox', { name: /Cc/ });
    await userEvent.type(cc, 'it@example.nhs.uk');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    await waitFor(() =>
      expect(cc).toHaveAccessibleDescription(/The cc address is not allowed: it@example\.nhs\.uk/),
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
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
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
    // The case reads as handled by the team, and the email it followed stays as its record in the audit trail,
    // with no actions
    const top = await screen.findByRole('region', { name: 'Outcome' });
    await waitFor(() => expect(within(top).getByTestId('outcome-line')).toHaveTextContent('Handled by hand'));
    expect(within(top).getByText('Handed it to the team, who corrected it by hand')).toBeInTheDocument();
    expect(within(top).getByText('Not verified by Shutter')).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole('region', { name: 'Escalations' })).toBeNull());
    await userEvent.click(screen.getByRole('tab', { name: 'Audit trail' }));
    const record = await screen.findByRole('region', { name: 'Escalations' });
    expect(within(record).queryByRole('button', { name: /^Escalate to /i })).toBeNull();
    expect(within(record).queryByRole('button', { name: /Mark as handled/ })).not.toBeInTheDocument();
    expect(within(record).getByText('Saved, not delivered')).toBeInTheDocument();
    expect(within(record).queryByText('Sent')).toBeNull();
    await userEvent.click(within(record).getByRole('button', { name: /Escalation 1/ }));
    expect(await within(record).findByText(/^Digest of the text saved: demo:/)).toBeInTheDocument();
    // The timeline names who closed it, the reason and the email it followed
    const timeline = screen.getByRole('region', { name: 'Timeline' });
    expect(
      await within(timeline).findByText(
        'Handled by hand: The bed manager placed the patient in WARD-C by hand; after escalation 1 to Integration team (saved)',
      ),
    ).toBeInTheDocument();
    expect(
      within(timeline).getByText(/^Escalation 1 queued by approver for .*; digest of the text queued demo:/),
    ).toBeInTheDocument();
    expect(
      within(timeline).getByText(
        /^Escalation 1 saved as an email file, not delivered: .*\. No mail server is set, so nobody was emailed\.$/,
      ),
    ).toBeInTheDocument();
  });

  it('offers an operator the closing by default', async () => {
    resetMock('operator');
    renderCase('C-000012');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByRole('button', { name: /Mark as handled by the team/ }),
    ).toBeInTheDocument();
  });

  it('offers the closing after a sent email whatever was drafted since, as the action button says', async () => {
    const sentOne: Escalation = {
      caseId: 'C-000008',
      seq: 1,
      state: 'sent',
      teamName: 'Integration team',
      to: 'integration@example.nhs.uk',
      subject: 'Correct encounter by hand',
      body: 'Please correct the encounter by hand.',
      bodyDigest: 'sha256:abc123',
    };
    const draftAfter: Escalation = { ...sentOne, seq: 2, state: 'draft', bodyDigest: 'sha256:def456' };
    server.use(
      http.get('/api/shutter/cases/:id/escalations', () => HttpResponse.json([sentOne, draftAfter])),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByRole('button', { name: /Mark as handled by the team/ }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByTestId('case-action')).toHaveAccessibleName('Needs you: mark as handled'),
    );
  });

  it('shows an email the mail server took as Sent, with what that does and does not show', async () => {
    const smtp: Escalation = {
      caseId: 'C-000008',
      seq: 1,
      state: 'sent',
      teamName: 'Integration team',
      to: 'integration@example.nhs.uk',
      subject: 'Correct encounter by hand',
      body: 'Please correct the encounter by hand.',
      bodyDigest: 'sha256:abc123',
      sentBy: 'approver',
      sentAt: '2026-11-09T10:00:00Z',
      transport: 'smtp',
      result: '250 2.0.0 Ok: queued as 4F1C2',
    };
    server.use(http.get('/api/shutter/cases/:id/escalations', () => HttpResponse.json([smtp])));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(await within(panel).findByText('Sent')).toBeInTheDocument();
    expect(within(panel).queryByText('Saved, not delivered')).toBeNull();
    await userEvent.click(within(panel).getByRole('button', { name: /Escalation 1/ }));
    expect(
      await within(panel).findByText(
        'Sent through the mail server, which accepted it; that does not show anyone has read it',
      ),
    ).toBeInTheDocument();
    expect(within(panel).getByText('Sent by approver')).toBeInTheDocument();
    expect(within(panel).getByText('Digest of the text sent: sha256:abc123')).toBeInTheDocument();
    expect(within(panel).queryByTestId('escalation-saved')).toBeNull();
    expect(within(panel).queryByRole('button', { name: 'Send it again…' })).toBeNull();
  });

  it('shows a saved email as not delivered, offers the closing after it, and sends the same text again', async () => {
    const saved: Escalation = {
      caseId: 'C-000008',
      seq: 1,
      state: 'saved',
      teamName: 'Integration team',
      to: 'integration@example.nhs.uk',
      subject: 'Correct encounter by hand',
      body: 'Please correct the encounter by hand.',
      bodyDigest: 'sha256:abc123',
      sentBy: 'approver',
      sentAt: '',
      savedAt: '2026-11-09T10:00:00Z',
      transport: 'file',
      result: '/usr/irissys/mgr/Shutter/mail/C-000008-1.eml',
    };
    let sends = 0;
    server.use(
      http.get('/api/shutter/cases/:id/escalations', () => HttpResponse.json([saved])),
      http.post('/api/shutter/cases/:id/escalations/:seq/send', () => {
        sends += 1;
        return HttpResponse.json({ ...saved, state: 'queued' }, { status: 202 });
      }),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    const badge = await within(panel).findByText('Saved, not delivered');
    expect(badge.closest('[data-tone]')).toHaveAttribute('data-tone', 'attention');
    expect(within(panel).queryByText('Sent')).toBeNull();
    expect(
      await within(panel).findByRole('button', { name: /Mark as handled by the team/ }),
    ).toBeInTheDocument();
    await userEvent.click(within(panel).getByRole('button', { name: /Escalation 1/ }));
    await userEvent.click(await within(panel).findByRole('button', { name: 'Send it again…' }));
    const dialog = await screen.findByRole('dialog', { name: 'Send escalation 1 again' });
    expect(within(dialog).getByTestId('confirm-consequence')).toHaveTextContent(
      "This sends the same text to integration@example.nhs.uk through the site's mail server. With no mail server set, it is saved as an email file again and nobody is emailed.",
    );
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send again' }));
    expect(await screen.findByText('Escalation 1 queued again')).toBeInTheDocument();
    expect(sends).toBe(1);
    expect(sent.at(-1)?.body).toEqual({ bodyDigest: 'sha256:abc123' });
  });

  it('names the closing at the top of a withheld case, where the panel offers it at once', async () => {
    renderCase('C-000012');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByRole('button', { name: /Mark as handled by the team/ }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByTestId('case-action')).toHaveAccessibleName('Needs you: mark as handled'),
    );
  });

  it("keeps the closing from an operator where the site's two-person rule needs an approver", async () => {
    const view = recordedSiteProfile()!;
    view.profile.approvers = { ...view.profile.approvers, close_needs_approver: true };
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    resetMock('operator');
    renderCase('C-000012');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByText(/On this site closing a case by hand needs an approver/),
    ).toBeInTheDocument();
    expect(within(panel).queryByRole('button', { name: /Mark as handled/ })).not.toBeInTheDocument();
    // Escalating stays the operator's
    expect(within(panel).getByRole('button', { name: /^Escalate to /i })).toBeEnabled();
  });

  it('offers an approver the closing under the two-person rule', async () => {
    const view = recordedSiteProfile()!;
    view.profile.approvers = { ...view.profile.approvers, close_needs_approver: true };
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000012');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByRole('button', { name: /Mark as handled by the team/ }),
    ).toBeInTheDocument();
    expect(within(panel).queryByText(/needs an approver/)).not.toBeInTheDocument();
  });

  it('keeps the closing from a user with the approver role but not the operator role, as the server does', async () => {
    server.use(
      http.get('/api/shutter/me', () =>
        HttpResponse.json({ username: 'reviewer', operator: false, approver: true }),
      ),
    );
    renderCase('C-000012');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    expect(
      await within(panel).findByText('Escalating and marking a case handled need the operator role.'),
    ).toBeInTheDocument();
    expect(within(panel).queryByRole('button', { name: /Mark as handled/ })).not.toBeInTheDocument();
  });

  it('refuses a second @ and, with no allowed domains in the profile, every address', async () => {
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    await waitFor(() => expect(to).toHaveAccessibleDescription(/in example\.nhs\.uk/));
    await userEvent.clear(to);
    await userEvent.type(to, 'a@nhs.net@evil.com');
    expect(to).toHaveAccessibleDescription(
      /Not allowed: a@nhs\.net@evil\.com: must be one address with one @/,
    );
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
  });

  it('says when the team drafted to does not list the receiver, so a person looks before patient identifiers go', async () => {
    const view = recordedSiteProfile()!;
    view.profile.teams = [
      { id: 'integration', name: 'Integration team', mailbox: 'integration@example.nhs.uk' },
    ];
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await within(panel).findByRole('option', { name: /^Automatic/ });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    expect(within(dialog).getByTestId('team-not-listed')).toHaveTextContent(
      /Integration team does not list .+ in the site profile\. Check it is the right team/,
    );
  });

  it('says nothing about the team when it lists the receiver', async () => {
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    expect(within(dialog).queryByTestId('team-not-listed')).not.toBeInTheDocument();
  });

  it('allows no address while the site profile names no mail domains', async () => {
    const view = recordedSiteProfile()!;
    view.profile.mail = {};
    server.use(http.get('/api/shutter/site-profile', () => HttpResponse.json(view)));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    const to = within(dialog).getByRole('textbox', { name: /To/ });
    await userEvent.clear(to);
    await userEvent.type(to, 'bed.management@example.nhs.uk');
    expect(to).toHaveAccessibleDescription(
      /bed\.management@example\.nhs\.uk: no allowed mail domains are set in the site profile \(mail\.allowed_domains\)/,
    );
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
  });

  it('keeps a control character out of the subject, and shows the server refusing one on the subject', async () => {
    server.use(
      http.patch('/api/shutter/cases/:id/escalations/:seq', () =>
        HttpResponse.json(
          {
            error: 'subject_not_allowed',
            field: 'subject',
            detail: 'The subject must not contain line breaks or control characters',
          },
          { status: 422 },
        ),
      ),
    );
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /^Escalate to /i }));
    const dialog = await screen.findByRole('dialog', { name: /^Escalate to / });
    const subject = within(dialog).getByRole('textbox', { name: 'Subject' });
    // A text input drops CR and LF from its value, so the control character here is a tab, which it keeps
    fireEvent.change(subject, { target: { value: 'x\tBcc: e@evil.com' } });
    expect(subject).toHaveAccessibleDescription(
      /Not allowed: must not contain line breaks or control characters/,
    );
    expect(within(dialog).getByRole('button', { name: 'Send' })).toBeDisabled();
    // A subject the page lets through but the server refuses: its word shows on the field it names
    fireEvent.change(subject, { target: { value: 'Correct encounter by hand' } });
    await userEvent.click(within(dialog).getByRole('button', { name: 'Send' }));
    await waitFor(() =>
      expect(subject).toHaveAccessibleDescription(/The subject must not contain line breaks/),
    );
    expect(within(dialog).getByRole('alert')).toHaveTextContent('Nothing was sent');
  });

  it('shows the digest, not the text, of an escalation the retention task purged, and offers no send', async () => {
    const purged: Escalation = {
      caseId: 'C-000008',
      seq: 1,
      state: 'failed',
      teamName: 'Integration team',
      to: 'integration@example.nhs.uk',
      subject: 'Correct encounter by hand',
      body: '',
      bodyDigest: 'sha256:abc123',
      result: 'The mail server refused the message',
      purgedAt: '2026-10-20T09:00:00Z',
    };
    server.use(http.get('/api/shutter/cases/:id/escalations', () => HttpResponse.json([purged])));
    renderCase('C-000008');
    const panel = await screen.findByRole('region', { name: 'Escalations' });
    await userEvent.click(await within(panel).findByRole('button', { name: /Escalation 1/ }));
    expect(
      await within(panel).findByText(
        /^Text removed on .* by the retention task; digest of the text sent sha256:abc123$/,
      ),
    ).toBeInTheDocument();
    expect(within(panel).queryByRole('button', { name: /Check and send/ })).not.toBeInTheDocument();
  });

  it('is not offered on a case Shutter resolved', async () => {
    renderCase('C-000009');
    await waitFor(() =>
      expect(screen.getByTestId('outcome-line')).toHaveTextContent('Delivered: verified at the receiver'),
    );
    expect(screen.queryByRole('region', { name: 'Escalations' })).not.toBeInTheDocument();
  });
});
