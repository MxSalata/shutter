import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, request } from '@/api/client';
import { chooseTransport, resetTransportForTests } from '@/api/transport';
import { isApiError } from '@/lib/errors';
import fixtures from '@/mocks/fixtures.json';
import { handlers } from '@/mocks/handlers';
import { journal } from './journal';
import { createTrialTransport, NOT_IN_TRIAL_ANSWER } from './transport';

/**
 * The trial's guarantee, proved without a browser: every route the recorded mock answers is called through the app's
 * own `request()` on the trial transport, as the approver and as the operator, while `fetch` is a spy that fails the
 * test if it is ever called. No answer may be the trial's own "no recorded answer", and none may reach the network.
 */
const sent = vi.fn(() => {
  throw new Error('fetch was called from the trial');
});

beforeAll(() => {
  vi.stubGlobal('fetch', sent);
});
afterAll(() => {
  vi.unstubAllGlobals();
  resetTransportForTests();
});

/** A sample value for each parameter of a route, from the recording. */
function sample(path: string, name: string): string {
  if (name === 'id')
    return path.startsWith('/api/shutter/incidents')
      ? Object.keys(fixtures.incidents)[0]
      : path.startsWith('/api/shutter/production-reviews')
        ? fixtures.productionReviews.list[0].reviewId
        : path.startsWith('/api/shutter/scenarios')
          ? 'S2'
          : 'C-000008';
  if (name === 'code') return fixtures.library[0].code;
  if (name === 'seq') return '1';
  if (name === 'qid') return 'Q-1';
  return 'X-1';
}

/** Every handler's method and path, with its parameters filled in. */
const ROUTES = handlers.map((h) => {
  const { method, path } = h.info as { method: string; path: string };
  return {
    method: method.toUpperCase(),
    path: path.replace(/:(\w+)/g, (_, name: string) => sample(path, name)).replace(/^\/api\/shutter/, ''),
  };
});

async function callEvery() {
  const answers: { route: string; status: number; code: string }[] = [];
  for (const r of ROUTES) {
    const route = `${r.method} ${r.path}`;
    try {
      await request(
        r.method as 'GET',
        r.path,
        r.method === 'GET' || r.method === 'DELETE' ? {} : { body: {} },
      );
      answers.push({ route, status: 200, code: '' });
    } catch (e) {
      if (!isApiError(e)) throw e;
      answers.push({ route, status: e.status, code: e.code });
    }
  }
  return answers;
}

describe('the trial transport', () => {
  beforeAll(() => {
    resetTransportForTests();
    chooseTransport(createTrialTransport('approver'));
  });
  beforeEach(() => {
    sent.mockClear();
  });

  it('opens signed in as the role it was given', async () => {
    expect(await api.get<{ username: string }>('/me')).toMatchObject({ username: 'approver' });
  });

  it('answers every route of the recorded mock in the browser, as the approver and as the operator', async () => {
    expect(ROUTES.length).toBeGreaterThanOrEqual(51);
    const asApprover = await callEvery();
    await api.del('/session');
    await api.post('/session', { username: 'operator', password: 'shutter' });
    const asOperator = await callEvery();
    for (const a of [...asApprover, ...asOperator]) {
      expect(a.code, a.route).not.toBe(NOT_IN_TRIAL_ANSWER.error);
      // No answer is a failure to reach anything: there is nothing to reach
      expect(a.status, a.route).not.toBe(0);
    }
    expect(sent).not.toHaveBeenCalled();
    expect(journal.counts().reads + journal.counts().actions).toBeGreaterThanOrEqual(2 * ROUTES.length);
  });

  it('answers a route it has no recording for with its own 501, still with no fetch', async () => {
    const e = await api.get('/no-such-route').catch((x: unknown) => x);
    expect(isApiError(e) && [e.status, e.code]).toEqual([501, 'not_in_trial']);
    expect(journal.entries().at(-1)).toMatchObject({
      method: 'GET',
      path: '/api/shutter/no-such-route',
      status: 501,
    });
    expect(sent).not.toHaveBeenCalled();
  });

  it('rejects an aborted request as fetch would, with an AbortError', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(api.get('/scenarios', { signal: controller.signal })).rejects.toMatchObject({
      name: 'AbortError',
    });
    const late = new AbortController();
    const pending = api.post(
      '/cases/C-000008/questions',
      { suggested: { conversation: 'c1', turn: 1 } },
      {
        signal: late.signal,
      },
    );
    late.abort();
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    expect(sent).not.toHaveBeenCalled();
  });
});

describe('the recorded mock', () => {
  it('never hands a request to the network: no passthrough or bypass anywhere in it', () => {
    const dir = join(__dirname, '..', 'mocks');
    for (const name of readdirSync(dir).filter((n) => /\.ts$/.test(n) && !/\.test\.ts$/.test(n))) {
      const text = readFileSync(join(dir, name), 'utf8');
      expect(text, name).not.toMatch(/\bpassthrough\(|\bbypass\(/);
    }
  });
});
