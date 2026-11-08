import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { CaseBundleDownload } from './CaseBundleDownload';

const trial = vi.hoisted(() => ({ value: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return trial.value;
  },
}));

const BUNDLE = '{"redaction":"REDACTED: tokens stand in.",\n"format":"shutter-case-bundle/1"}';
const ROUTE = '/api/shutter/cases/C-000009/bundle';
const WHOLE =
  '{"redaction":"UNREDACTED: this file holds identifiable patient data.",\n"format":"shutter-case-bundle-unredacted/1"}';
const WHOLE_ROUTE = '/api/shutter/cases/C-000009/bundle-unredacted';

function show() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <CaseBundleDownload caseId="C-000009" />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** What the browser was handed to save: the blob's text and the link's file name. */
function watchSave() {
  const saved: { blob?: Blob; name?: string } = {};
  URL.createObjectURL = vi.fn((b: Blob) => {
    saved.blob = b;
    return 'blob:bundle';
  });
  URL.revokeObjectURL = vi.fn();
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
    saved.name = this.download;
  });
  return saved;
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  vi.restoreAllMocks();
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  trial.value = false;
});

describe('Download case bundle', () => {
  it('saves the file as the server wrote it, first line included, with the CSRF header', async () => {
    const saved = watchSave();
    let header: string | null = null;
    server.use(
      http.post(ROUTE, ({ request }) => {
        header = request.headers.get('X-Requested-With');
        return new HttpResponse(BUNDLE, { headers: { 'Content-Type': 'application/json' } });
      }),
    );
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Download case bundle' }));
    await waitFor(() => expect(saved.name).toBe('shutter-case-C-000009-redacted.json'));
    expect(header).toBe('Shutter');
    const text = await new Promise<string>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.readAsText(saved.blob as Blob);
    });
    expect(text).toBe(BUNDLE);
    expect(text.split('\n')[0]).toContain('REDACTED');
  });

  it("shows the server's reason and saves nothing when the case can't be redacted", async () => {
    const saved = watchSave();
    server.use(
      http.post(ROUTE, () =>
        HttpResponse.json(
          { error: 'not_redactable', detail: 'The bundle of case C-000009 cannot be redacted' },
          { status: 409 },
        ),
      ),
    );
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Download case bundle' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('cannot be redacted');
    expect(saved.name).toBeUndefined();
  });

  it("never saves a 200 that isn't a redacted bundle", async () => {
    const saved = watchSave();
    server.use(http.post(ROUTE, () => HttpResponse.json({ evidence: [] })));
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Download case bundle' }));
    await screen.findByRole('alert');
    expect(saved.name).toBeUndefined();
  });

  it('is not offered to someone who is not an operator', async () => {
    server.use(
      http.get('/api/shutter/me', () =>
        HttpResponse.json({ username: 'x', operator: false, approver: false }),
      ),
    );
    const { container } = show();
    await waitFor(() => expect(container.querySelector('button')).toBeNull());
  });

  it('is disabled in the trial, with its reason', async () => {
    trial.value = true;
    show();
    expect(await screen.findByRole('button', { name: 'Download case bundle' })).toBeDisabled();
    expect(screen.getByText("Not in the trial's recording")).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Download with identifiers' })).toBeNull();
  });

  it('offers an approver the unredacted file, which needs a reason and sends it with the CSRF header', async () => {
    const saved = watchSave();
    let header: string | null = null;
    let sent: unknown = null;
    server.use(
      http.post(WHOLE_ROUTE, async ({ request }) => {
        header = request.headers.get('X-Requested-With');
        sent = await request.json();
        return new HttpResponse(WHOLE, { headers: { 'Content-Type': 'application/json' } });
      }),
    );
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Download with identifiers' }));
    expect(screen.getByText(/holds identifiable patient data/)).toBeInTheDocument();
    const go = screen.getByRole('button', { name: 'Download unredacted bundle' });
    expect(go).toBeDisabled();
    await userEvent.type(screen.getByLabelText(/Why you need the identifiers/), 'A subject access request');
    expect(go).toBeEnabled();
    await userEvent.click(go);
    await waitFor(() => expect(saved.name).toBe('shutter-case-C-000009-UNREDACTED.json'));
    expect(header).toBe('Shutter');
    expect(sent).toEqual({ reason: 'A subject access request' });
  });

  it("never saves a 200 that doesn't say it is unredacted", async () => {
    const saved = watchSave();
    server.use(http.post(WHOLE_ROUTE, () => new HttpResponse(BUNDLE)));
    show();
    await userEvent.click(await screen.findByRole('button', { name: 'Download with identifiers' }));
    await userEvent.type(screen.getByLabelText(/Why you need the identifiers/), 'A subject access request');
    await userEvent.click(screen.getByRole('button', { name: 'Download unredacted bundle' }));
    await screen.findByRole('alert');
    expect(saved.name).toBeUndefined();
  });

  it('does not offer an operator the unredacted file', async () => {
    resetMock('operator');
    show();
    expect(await screen.findByRole('button', { name: 'Download case bundle' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Download with identifiers' })).toBeNull();
  });
});
