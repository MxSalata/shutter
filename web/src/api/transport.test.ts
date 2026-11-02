import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { isApiError } from '@/lib/errors';
import { api } from './client';
import { chooseTransport, liveTransport, resetTransportForTests, TRIAL_OPENING } from './transport';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  resetTransportForTests();
  vi.restoreAllMocks();
  window.history.replaceState(null, '', '/');
});
afterAll(() => server.close());

describe('the transport', () => {
  it('is chosen once per page load: a second choice is a bug', () => {
    chooseTransport(liveTransport);
    expect(() => chooseTransport(liveTransport)).toThrow(/once per page load/);
  });

  it('refuses in a trial page before the trial is ready, and never calls fetch', async () => {
    window.history.replaceState(null, '', '/shutter/?trial#/scenarios');
    const sent = vi.spyOn(globalThis, 'fetch');
    const error = await api.get('/me').catch((e: unknown) => e);
    expect(isApiError(error) && [error.status, error.path, error.message]).toEqual([0, '/me', TRIAL_OPENING]);
    expect(sent).not.toHaveBeenCalled();
  });

  it('sends in a live page exactly what it sent before: method, headers, key, body and credentials', async () => {
    let seen: Request | undefined;
    let body = '';
    server.use(
      http.post('/api/shutter/cases/C-1/approvals', async ({ request }) => {
        seen = request.clone();
        body = await request.text();
        return HttpResponse.json({ ok: true });
      }),
    );
    chooseTransport(liveTransport);
    expect(await api.post('/cases/C-1/approvals', { action: 'approve' }, { idempotencyKey: 'k-1' })).toEqual({
      ok: true,
    });
    expect(seen?.method).toBe('POST');
    expect(new URL(seen!.url).pathname).toBe('/api/shutter/cases/C-1/approvals');
    expect(Object.fromEntries(seen!.headers)).toMatchObject({
      accept: 'application/json',
      'content-type': 'application/json',
      'x-requested-with': 'Shutter',
      'idempotency-key': 'k-1',
    });
    expect(JSON.parse(body)).toEqual({ action: 'approve' });
    expect(seen?.credentials).toBe('same-origin');
  });

  it('sends a read without a body or the CSRF header, as before', async () => {
    let seen: Request | undefined;
    server.use(
      http.get('/api/shutter/me', ({ request }) => {
        seen = request.clone();
        return HttpResponse.json({ username: 'approver' });
      }),
    );
    expect(await api.get('/me')).toEqual({ username: 'approver' });
    expect(seen?.headers.get('x-requested-with')).toBeNull();
    expect(seen?.headers.get('content-type')).toBeNull();
  });
});
