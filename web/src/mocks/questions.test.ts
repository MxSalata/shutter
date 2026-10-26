import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { api } from '@/api/client';
import type { CaseQuestion, QuestionAsked, SuggestedQuestions, WhatIf } from '@/api/types';
import { isApiError } from '@/lib/errors';
import catalogue from '../../../knowledge/catalogue/catalogue.json';
import { resetMock } from './handlers';
import { server } from './node';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

async function refusal(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    if (isApiError(e)) return { status: e.status, code: e.code };
    throw e;
  }
  throw new Error('expected a refusal');
}

/** The mock's question routes (sample data until the re-record), in the shapes of the case-chat design. */
describe('the mock question routes', () => {
  it('serves the scenario file, and the example conversation already asked on the showcase case', async () => {
    const s = await api.get<SuggestedQuestions>('/cases/C-000008/questions/suggested');
    expect(s.scenario).toBe('S8');
    expect(s.conversations[0]).toMatchObject({ id: 'c1' });
    expect(s.conversations[0].turns.map((t) => t.tier)).toEqual(['explain', 'explain', 'board']);
    const { items } = await api.get<{ items: CaseQuestion[] }>('/cases/C-000008/questions');
    expect(items.map((q) => `${q.conversation}.${q.turn} ${q.state}`)).toEqual([
      'c1.1 answered',
      'c1.2 answered',
      'c1.3 answered',
    ]);
    expect(items.every((q) => q.recording === null)).toBe(true);
    expect(await refusal(api.get('/cases/C-000009/questions/suggested'))).toEqual({
      status: 404,
      code: 'no_questions',
    });
  });

  it('answers a suggested turn by its place, once, and refuses free text with no key', async () => {
    const asked = await api.post<QuestionAsked>('/cases/C-000008/questions', {
      tier: 'board',
      suggested: { conversation: 'c4', turn: 1 },
    });
    expect(asked).toMatchObject({ conversation: 'c4', turn: 1 });
    const q = await api.get<CaseQuestion>(`/cases/C-000008/questions/${asked.questionId}`);
    expect(q).toMatchObject({ tier: 'board', source: 'suggested', state: 'answered' });
    const again = await api.post<QuestionAsked>('/cases/C-000008/questions', {
      tier: 'board',
      suggested: { conversation: 'c4', turn: 1 },
    });
    expect(again.questionId).toBe(asked.questionId);
    expect(
      await refusal(api.post('/cases/C-000008/questions', { tier: 'explain', question: 'Why?' })),
    ).toEqual({ status: 409, code: 'live_only' });
    expect(
      await refusal(
        api.post('/cases/C-000008/questions', {
          tier: 'explain',
          suggested: { conversation: 'c4', turn: 1 },
        }),
      ),
    ).toEqual({ status: 404, code: 'no_recording' });
  });

  it('needs a session to read or ask', async () => {
    resetMock(null);
    expect(await refusal(api.get('/cases/C-000008/whatif'))).toMatchObject({ status: 401 });
    expect(
      await refusal(
        api.post('/cases/C-000008/questions', { tier: 'board', suggested: { conversation: 'c4', turn: 1 } }),
      ),
    ).toMatchObject({ status: 401 });
  });

  it("gives S8 the catalogue's own alternative: the bed manager authoritative, nothing written", async () => {
    const w = await api.get<WhatIf>('/cases/C-000008/whatif');
    const e7 = (catalogue as { id: string; alternatives: { outcome: string; when: string }[] }[]).find(
      (e) => e.id === 'E7',
    )!;
    expect(w.entry).toBe('E7');
    expect(w.facts).toHaveLength(1);
    expect(w.facts[0]).toMatchObject({ field: 'authoritative_source', from: '', to: 'BEDMGR' });
    expect(w.facts[0].alternative).toMatchObject({
      outcome: e7.alternatives[0].outcome,
      when: e7.alternatives[0].when,
    });
    const s2 = await api.get<WhatIf>('/cases/C-000002/whatif');
    expect(s2).toMatchObject({ entry: 'E2', facts: [] });
  });
});
