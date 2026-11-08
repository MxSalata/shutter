import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import type { WarehouseHistoryView, WarehouseRead } from '@/api/types';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { WarehouseHistoryPanel } from './WarehouseHistoryPanel';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const URL = '/api/shutter/cases/C-1/warehouse-history';

const read: WarehouseRead = {
  readAt: '2026-11-06T12:00:00Z',
  readBy: 'operator',
  status: 'ok',
  category: '',
  dataset: 'PAS-HISTORY',
  generation: 'G1',
  batch: 'B7',
  sequence: 7,
  sourceSystem: 'PAS',
  receiverReference: 'the bed manager',
  sourceWatermark: '2026-11-06T11:00:00Z',
  watermarkKnown: true,
  historyCompleteFrom: '2020-01-01T00:00:00Z',
  publishedAt: '2026-11-06T11:30:00Z',
  ageMinutes: 60,
  freshness: 'within',
  rowCount: 2,
  truncated: false,
  generationChanged: false,
  queryVersion: '1',
  resultDigest: 'abc',
  rows: [
    {
      source_event_id: 'E1',
      revision: 1,
      record_status: 'active',
      encounter_authority: null,
      encounter_id: 'ENC-OLD',
      event_kind: 'transfer',
      event_time: '2026-11-01T10:00:00Z',
      time_precision: 'second',
      source_recorded_at: null,
      source_modified_at: null,
      ward: 'WARD-B',
      bed: null,
      supersedes_event_id: null,
    },
    {
      source_event_id: 'E2',
      revision: 2,
      record_status: 'cancelled',
      encounter_authority: null,
      encounter_id: null,
      event_kind: 'admit',
      event_time: null,
      time_precision: 'unknown',
      source_recorded_at: null,
      source_modified_at: null,
      ward: null,
      bed: null,
      supersedes_event_id: null,
    },
  ],
};

function answer(view: WarehouseHistoryView) {
  server.use(http.get(`*${URL}`, () => HttpResponse.json(view)));
}

function show() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <WarehouseHistoryPanel caseId="C-1" canRead />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('the warehouse history panel', () => {
  it('is not there at all while it is off', async () => {
    let asked = false;
    server.use(
      http.get(`*${URL}`, () => {
        asked = true;
        return HttpResponse.json({ enabled: false, read: null });
      }),
    );
    const { container } = show();
    await waitFor(() => expect(asked).toBe(true));
    await new Promise((r) => setTimeout(r, 20));
    expect(screen.queryByText(/warehouse/i)).toBeNull();
    expect(container.querySelector('section, h2, h3')).toBeNull();
  });

  it('is not there either for a server without the route', async () => {
    server.use(http.get(`*${URL}`, () => HttpResponse.json({ error: 'not_found' }, { status: 404 })));
    const { container } = show();
    await new Promise((r) => setTimeout(r, 30));
    expect(container.querySelector('h2, h3')).toBeNull();
  });

  it('says what it is before anything has been read, and reads only when asked', async () => {
    let posts = 0;
    server.use(
      http.get(`*${URL}`, () => HttpResponse.json({ enabled: true, read: posts ? read : null })),
      http.post(`*${URL}`, () => {
        posts += 1;
        return HttpResponse.json({ enabled: true, read });
      }),
    );
    show();
    const button = await screen.findByRole('button', { name: 'Read warehouse history' });
    expect(screen.getByText(/It is not used to authorise or verify a resend/)).toBeTruthy();
    expect(posts).toBe(0);
    await userEvent.click(button);
    await screen.findByText('WARD-B');
    expect(posts).toBe(1);
  });

  it('keeps its limits beside the rows, and names the batch and the watermark', async () => {
    answer({ enabled: true, read });
    show();
    await screen.findByText('WARD-B');
    expect(screen.getByRole('heading', { name: 'Warehouse history: historical context only' })).toBeTruthy();
    expect(screen.getByText(/This may be hours behind/)).toBeTruthy();
    expect(screen.getByText(/It is not used to authorise or verify a resend/)).toBeTruthy();
    expect(screen.getByText(/Source complete through/)).toBeTruthy();
    expect(screen.getByText(/batch B7/)).toBeTruthy();
    expect(screen.getByText('cancelled')).toBeTruthy();
    expect(screen.getByText('ENC-OLD')).toBeTruthy();
  });

  it('never calls a warehouse row the current state, a receipt or proof', async () => {
    answer({ enabled: true, read });
    const { container } = show();
    await screen.findByText('WARD-B');
    const text = container.textContent ?? '';
    expect(text).not.toMatch(/current (ward|state|location)/i);
    expect(text).not.toMatch(/\bverified\b|\breceipt\b/i);
  });

  it('says that no rows does not mean absent', async () => {
    answer({ enabled: true, read: { ...read, status: 'no_rows', rows: [], rowCount: 0 } });
    show();
    expect(
      await screen.findByText(
        /No matching rows were returned from this batch. This does not establish that the patient or movement is absent at the receiver/,
      ),
    ).toBeTruthy();
  });

  it('says an unknown watermark is unknown', async () => {
    answer({
      enabled: true,
      read: {
        ...read,
        status: 'withheld',
        rows: [],
        watermarkKnown: false,
        sourceWatermark: '',
        freshness: 'unknown',
        ageMinutes: null,
      },
    });
    show();
    expect(await screen.findByText(/Source complete through: unknown/)).toBeTruthy();
    expect(screen.getByText(/rows are not shown/i)).toBeTruthy();
  });

  it('says a list was cut short, and that a new generation was published', async () => {
    answer({ enabled: true, read: { ...read, truncated: true, generationChanged: true } });
    show();
    expect(await screen.findByText(/The newest 200 rows/)).toBeTruthy();
    expect(screen.getByText(/The export was rebuilt since the last read/)).toBeTruthy();
  });

  it('marks rows older than the limit when a site chose to show them', async () => {
    answer({ enabled: true, read: { ...read, freshness: 'older', ageMinutes: 1440 } });
    show();
    expect(await screen.findByText(/older than this site's limit/)).toBeTruthy();
  });

  it('says why when a read was refused or could not be made, and the case carries on', async () => {
    answer({
      enabled: true,
      read: { ...read, status: 'invalid', category: 'row_count_mismatch', rows: [], rowCount: 0 },
    });
    const first = show();
    expect(await screen.findByText(/holds fewer or more rows than its manifest says/)).toBeTruthy();
    first.unmount();
    answer({
      enabled: true,
      read: { ...read, status: 'unavailable', category: 'unreachable', rows: [], rowCount: 0 },
    });
    show();
    expect(await screen.findByText(/could not be read just now/)).toBeTruthy();
    expect(screen.getByText(/The investigation is not affected/)).toBeTruthy();
  });

  it('offers no read to someone who cannot operate', async () => {
    answer({ enabled: true, read: null });
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={client}>
          <WarehouseHistoryPanel caseId="C-1" canRead={false} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    await screen.findByRole('heading', { name: 'Warehouse history: historical context only' });
    expect(screen.queryByRole('button', { name: 'Read warehouse history' })).toBeNull();
  });
});
