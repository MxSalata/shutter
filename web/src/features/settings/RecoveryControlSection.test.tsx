import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { RecoveryControl } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { RecoveryBanner } from '@/features/shell/RecoveryBanner';
import { RecoveryControlSection } from './RecoveryControlSection';

const BASE = '/api/shutter';

const control = (over: Partial<RecoveryControl> = {}): RecoveryControl => ({
  mode: 'enabled',
  generation: 3,
  stopped: false,
  stoppedAt: '',
  stoppedBy: '',
  stopReason: '',
  outstanding: [],
  outstandingCount: 0,
  readable: true,
  covers: 'Rehearsals.',
  doesNotCover: "The hospital's ordinary feed.",
  ...over,
});

function page(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MantineProvider theme={theme}>{ui}</MantineProvider>
    </QueryClientProvider>,
  );
}

const answering = (body: RecoveryControl) =>
  server.use(http.get(`${BASE}/recovery-control`, () => HttpResponse.json(body)));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

describe('the recovery control', () => {
  it('says what it stops and what it does not, beside the switch', async () => {
    answering(control());
    page(<RecoveryControlSection />);
    expect(await screen.findByRole('button', { name: 'Stop Shutter recovery' })).toBeDisabled();
    expect(screen.getByText(/It does not stop: The hospital's ordinary feed/)).toBeInTheDocument();
  });

  it('needs a reason, and sends it', async () => {
    answering(control());
    let sent: unknown;
    server.use(
      http.post(`${BASE}/recovery-control/stop`, async ({ request }) => {
        sent = await request.json();
        return HttpResponse.json(control({ stopped: true, stoppedBy: 'approver', stoppedAt: 'now' }));
      }),
    );
    page(<RecoveryControlSection />);
    const button = await screen.findByRole('button', { name: 'Stop Shutter recovery' });
    await userEvent.type(screen.getByRole('textbox', { name: /Reason/ }), 'the receiver looks wrong');
    await userEvent.click(button);
    expect(sent).toEqual({ reason: 'the receiver looks wrong' });
  });

  it('clearing says it stays in shadow mode, and sends the generation it read', async () => {
    answering(
      control({ mode: 'shadow', stopped: true, stoppedBy: 'operator', stoppedAt: 'then', generation: 7 }),
    );
    let sent: unknown;
    server.use(
      http.post(`${BASE}/recovery-control/clear`, async ({ request }) => {
        sent = await request.json();
        return HttpResponse.json(control({ mode: 'shadow' }));
      }),
    );
    page(<RecoveryControlSection />);
    const button = await screen.findByRole('button', { name: 'Clear the stop, remain in shadow mode' });
    await userEvent.type(screen.getByRole('textbox', { name: /Reason/ }), 'seen');
    await userEvent.click(button);
    expect(sent).toEqual({ reason: 'seen', expectedGeneration: 7 });
  });

  it('an operator can stop but not clear', async () => {
    resetMock('operator');
    answering(control({ stopped: true, stoppedBy: 'operator', stoppedAt: 'then' }));
    page(<RecoveryControlSection />);
    expect(await screen.findByText(/Clearing needs a person/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Clear the stop/ })).toBeNull();
  });

  it('a server without the control shows nothing', async () => {
    server.use(
      http.get(`${BASE}/recovery-control`, () => HttpResponse.json({ error: 'not_found' }, { status: 404 })),
    );
    page(<RecoveryBanner />);
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByText(/Shadow mode|recovery stopped/)).toBeNull();
  });
});

describe('the banner', () => {
  it('is silent when recovery is enabled and not stopped', async () => {
    answering(control());
    page(<RecoveryBanner />);
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByText(/Shadow mode|recovery stopped/)).toBeNull();
  });

  it('says what shadow mode does, and that the feed continues', async () => {
    answering(control({ mode: 'shadow' }));
    page(<RecoveryBanner />);
    expect(await screen.findByText('Shadow mode.')).toBeInTheDocument();
    expect(screen.getByText(/sends no recovery write, rehearsal or resend preview/)).toBeInTheDocument();
    expect(screen.getByText(/ordinary\s+feed continues/)).toBeInTheDocument();
  });

  it('names who stopped it and the calls that may still complete', async () => {
    answering(control({ stopped: true, stoppedBy: 'operator', stoppedAt: '10:00', outstandingCount: 2 }));
    page(<RecoveryBanner />);
    expect(await screen.findByText('Shutter recovery stopped by operator at 10:00.')).toBeInTheDocument();
    expect(screen.getByText(/2 earlier calls may still complete/)).toBeInTheDocument();
  });
});
