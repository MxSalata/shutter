import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { api } from '@/api/client';
import type {
  CaseQuestionDetail,
  CaseQuestions,
  QuestionAsked,
  SuggestedQuestions,
  WhatIf,
} from '@/api/types';
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

/** The mock's question routes (sample data until the re-record), in the shapes of CONTRACTS 14.5. */
describe('the mock question routes', () => {
  it('serves the scenario file, and the example conversation already asked on the showcase case', async () => {
    const s = await api.get<SuggestedQuestions>('/cases/C-000008/questions/suggested');
    expect(s.scenario).toBe('S8');
    expect(s.conversations[0]).toMatchObject({ id: 'c1' });
    expect(s.conversations[0].turns.map((t) => t.tier)).toEqual(['explain', 'explain', 'board']);
    const { items, total } = await api.get<CaseQuestions>('/cases/C-000008/questions');
    expect(items.map((q) => `${q.conversation}.${q.turn} ${q.state}`)).toEqual([
      'c1.1 answered',
      'c1.2 answered',
      'c1.3 answered',
    ]);
    expect(total).toBe(3);
    expect(items.every((q) => q.mode === 'replay' && q.model === null)).toBe(true);
    // Each turn links to its stored question; a case with no scenario answers an empty list, not a 404
    expect(s.conversations[0].turns.map((t) => t.asked?.questionId)).toEqual(items.map((q) => q.questionId));
    expect(s.conversations[1].turns[0].asked).toBeNull();
    expect(await api.get('/cases/C-000009/questions/suggested')).toMatchObject({ conversations: [] });
  });

  it('answers a suggested turn by its place, once, and refuses free text with no key', async () => {
    const asked = await api.post<QuestionAsked>('/cases/C-000008/questions', {
      tier: 'board',
      suggested: { conversation: 'c4', turn: 1 },
    });
    expect(asked).toMatchObject({
      conversation: 'c4',
      turn: 1,
      tier: 'board',
      source: 'suggested',
      state: 'answered',
    });
    const q = await api.get<CaseQuestionDetail>(`/cases/C-000008/questions/${asked.questionId}`);
    expect(q).toMatchObject({ tier: 'board', source: 'suggested', state: 'answered', mode: 'replay' });
    expect(q.memberAnswers.map((m) => m.member)).toEqual(['conformance', 'encounter', 'impact']);
    expect(q.agentRuns.at(-1)).toMatchObject({ role: 'coordinator' });
    const again = await api.post<QuestionAsked>('/cases/C-000008/questions', {
      tier: 'board',
      suggested: { conversation: 'c4', turn: 1 },
    });
    expect(again.questionId).toBe(asked.questionId);
    expect(
      await refusal(api.post('/cases/C-000008/questions', { tier: 'explain', question: 'Why?' })),
    ).toEqual({ status: 503, code: 'no_service' });
    expect(await refusal(api.post('/cases/C-000008/questions', { tier: 'robot', question: 'Why?' }))).toEqual(
      { status: 400, code: 'bad_request' },
    );
    expect(await refusal(api.post('/cases/C-000008/questions', { tier: 'explain' }))).toEqual({
      status: 400,
      code: 'bad_request',
    });
    expect(
      await refusal(
        api.post('/cases/C-000008/questions', {
          tier: 'explain',
          suggested: { conversation: 'c9', turn: 1 },
        }),
      ),
    ).toEqual({ status: 404, code: 'unknown_suggested' });
    expect(
      await refusal(api.post('/cases/C-999999/questions', { tier: 'explain', question: 'Why?' })),
    ).toEqual({
      status: 404,
      code: 'not_found',
    });
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
    expect(w.facts[0]).toMatchObject({ id: 'W1', field: 'authoritative_source', from: '', to: 'BEDMGR' });
    expect(w.facts[0].suggested_change).toMatchObject({ valid: true, stale: false, to: 'BEDMGR' });
    expect(w.facts[0].alternative).toMatchObject({
      outcome: e7.alternatives[0].outcome,
      when: e7.alternatives[0].when,
    });
    const s2 = await api.get<WhatIf>('/cases/C-000002/whatif');
    expect(s2).toMatchObject({ entry: 'E2', facts: [] });
  });
});
