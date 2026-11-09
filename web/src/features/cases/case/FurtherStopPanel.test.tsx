import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { CaseDetail } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { axeViolations } from '@/test/axe';
import { layer1WordCount } from '@/test/words';
import { theme } from '@/theme';
import { FurtherStopPanel } from './FurtherStopPanel';

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return env.trial;
    },
  };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const LINE =
  'Another visit for patient MRN1027 (HOSP): an admission (ADT_A01) on visit ENC-2027 timed 2026-10-15T08:30:00Z.';
const VIEW = {
  rows: [{ line: LINE, visit: 'ENC-2027' }],
  digest: 'sha256:rows',
  releasable: true,
  whyNot: '',
  release: null,
};
const C = { caseId: 'C-000099', state: 'blocked', version: 3 } as unknown as CaseDetail;

function show(view: unknown = VIEW, c: CaseDetail = C) {
  server.use(http.get('/api/shutter/cases/:id/further-stop', () => HttpResponse.json(view as object)));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <FurtherStopPanel c={c} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('FurtherStopPanel', () => {
  beforeEach(() => {
    resetMock('approver');
    env.trial = false;
  });

  it('shows the rows, says what the approver confirms, and posts the digest of what was shown with the typed reason', async () => {
    let posted: unknown = null;
    server.use(
      http.post('/api/shutter/cases/:id/further-release', async ({ request }) => {
        posted = await request.json();
        return HttpResponse.json({ caseId: 'C-000099', state: 'reopening' }, { status: 202 });
      }),
    );
    show();
    expect(await screen.findByText(LINE)).toBeInTheDocument();
    expect(screen.getByText(/You're confirming you've read these messages/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Release this stop…' }));
    const go = await screen.findByRole('button', { name: 'Release for these rows' });
    expect(go).toBeDisabled();
    await userEvent.type(screen.getByLabelText(/Why it's safe to send/), 'A separate spell');
    await userEvent.click(go);
    await vi.waitFor(() => expect(posted).toEqual({ digest: 'sha256:rows', reason: 'A separate spell' }));
  });

  it('says so when the rows changed under the person, and takes no second press', async () => {
    server.use(
      http.post('/api/shutter/cases/:id/further-release', () =>
        HttpResponse.json({ error: 'rows_changed', detail: 'read them again' }, { status: 409 }),
      ),
    );
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Release this stop…' }));
    await userEvent.type(await screen.findByLabelText(/Why it's safe to send/), 'A separate spell');
    await userEvent.click(screen.getByRole('button', { name: 'Release for these rows' }));
    expect(await screen.findByText(/The messages changed while you read them/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Release for these rows' })).toBeDisabled();
  });

  it('offers an operator no button, and says who can', async () => {
    resetMock('operator');
    show();
    expect(await screen.findByText(LINE)).toBeInTheDocument();
    expect(await screen.findByText(/An approver can release this stop/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Release this stop…' })).not.toBeInTheDocument();
  });

  it("offers nothing on what a release can't cover, and says why", async () => {
    show({ ...VIEW, releasable: false, whyNot: 'Further messages could not all be read.' });
    expect(
      await screen.findByText(/This stop can't be released here\. Further messages could not all be read\./),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Release this stop…' })).not.toBeInTheDocument();
  });

  it("says this visit, not another, when every row is on the case's own visit", async () => {
    const line = 'For patient MRN1034 (HOSP), a later A08 on this visit named another place.';
    show(
      {
        ...VIEW,
        rows: [{ line, visit: 'ENC-1034' }],
        releasable: false,
        whyNot: 'It needs correcting by hand.',
      },
      { ...C, encounterId: 'ENC-1034' } as CaseDetail,
    );
    expect(await screen.findByText(line)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'A later message on this visit' })).toBeInTheDocument();
    expect(screen.queryByText(/on another visit/)).not.toBeInTheDocument();
  });

  it('says when an earlier release no longer holds', async () => {
    show({
      ...VIEW,
      release: {
        digest: 'sha256:old',
        by: 'approver',
        at: '2026-11-07T10:00:00Z',
        reason: 'x',
        stands: false,
      },
    });
    expect(await screen.findByText(/no longer holds/)).toBeInTheDocument();
  });

  it('in the trial says what it does, with the button disabled and no call made', async () => {
    env.trial = true;
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={client}>
          <FurtherStopPanel c={C} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    expect(screen.getByRole('button', { name: 'Release this stop…' })).toBeDisabled();
    expect(screen.getByText(/You're confirming you've read these messages/)).toBeInTheDocument();
  });

  it('has no accessibility violations and keeps to 100 words beside its rows', async () => {
    const { container } = show();
    await screen.findByText(LINE);
    expect(await axeViolations(container)).toEqual([]);
    expect(layer1WordCount(container) - LINE.split(/\s+/).length).toBeLessThanOrEqual(100);
  });
});
