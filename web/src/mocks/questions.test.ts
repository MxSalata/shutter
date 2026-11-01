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
import fixtures from './fixtures.json';
import { resetMock } from './handlers';
import { server } from './node';
import { DEMO_CASES, RECORDED, suggestedFor, whatIfFor, type RecordedQuestion } from './questions';

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

/** The mock's question routes (the recorded answers), in the shapes of CONTRACTS 14.5. */
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
    expect(
      items.every(
        (q) =>
          q.mode === 'replay' &&
          q.model === 'claude-opus-5-5' &&
          q.costUsd === 0 &&
          /^2026-11-01T\d\d:\d\d:\d\dZ$/.test(q.recordedAt ?? ''),
      ),
    ).toBe(true);
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
    expect(q.memberAnswers.every((m) => m.status === 'ok' && !!m.answer?.answer)).toBe(true);
    expect(q.agentRuns.at(-1)).toMatchObject({ role: 'coordinator', model: 'claude-opus-5-5' });
    expect(q.recordedAt).toMatch(/^2026-11-01T/);
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
    expect(w.case_id).toBe('C-000008');
    expect(w.profile_version).toBe(fixtures.siteProfile.version);
    const s2 = await api.get<WhatIf>('/cases/C-000002/whatif');
    expect(s2).toMatchObject({ entry: 'E2', outcome: 'resend' });
    expect(s2.facts).toHaveLength(1);
    expect(s2.facts[0]).toMatchObject({ id: 'W1', kind: 'policy', field: 'policy.2.single', to: 'approval' });
  });
});

const demoCase = (id: string) =>
  (fixtures.cases as unknown as Record<string, { summary: Record<string, string> }>)[id].summary;
const recordedCases = Object.entries(RECORDED).flatMap(([scenario, byReceiver]) =>
  Object.entries(byReceiver).map(([receiver, c]) => ({ scenario, receiver, ...c })),
);

/** Every text a recorded turn shows: the answer, the members' answers and what the core resolved. */
const textsOf = (q: RecordedQuestion) => JSON.stringify([q.answer, q.memberAnswers, q.resolved]);

/** The fact ids a recorded turn names: in its cites, its setting references and its texts. */
function namedFacts(q: RecordedQuestion): string[] {
  const a = q.answer as {
    setting?: { fact: string };
    under_alternative?: { fact: string };
    suggested_change?: { fact: string };
  };
  return [
    ...new Set([
      ...(textsOf(q).match(/\bW\d+\b/g) ?? []),
      ...[a.setting, a.under_alternative, a.suggested_change].flatMap((r) => (r ? [r.fact] : [])),
    ]),
  ];
}

describe('the recorded answers', () => {
  it('belong to the demo cases of S1, S2, S8, S20 and S22, one case for each receiver', () => {
    expect(recordedCases.map((c) => `${c.scenario} ${c.receiver} ${c.caseId}`).sort()).toEqual([
      'S1 Downstream Out C-000001',
      'S2 Downstream Out C-000002',
      'S20 Downstream Out C-000053',
      'S22 Downstream Out C-000054',
      'S22 Records Out C-000055',
      'S8 Downstream Out C-000008',
    ]);
    expect(Object.keys(DEMO_CASES).sort()).toEqual(recordedCases.map((c) => c.caseId).sort());
    for (const c of recordedCases) {
      const summary = demoCase(c.caseId);
      expect(summary).toMatchObject({ scenario: c.scenario, receiver: c.receiver });
    }
  });

  it("answer every turn of the scenario's file, with its question and tier, recorded live", () => {
    for (const c of recordedCases) {
      const file = suggestedFor(c.caseId)!;
      const turns = file.conversations.flatMap((conv) =>
        conv.turns.map((t) => ({ key: `${conv.id}.${t.turn}`, ...t })),
      );
      expect(Object.keys(c.questions).sort(), c.caseId).toEqual(turns.map((t) => t.key).sort());
      for (const t of turns) {
        const q = c.questions[t.key];
        expect(q.question, `${c.caseId} ${t.key}`).toBe(t.text);
        expect(q.tier, `${c.caseId} ${t.key}`).toBe(t.tier);
        expect(q.model).toBe('claude-opus-5-5');
        expect(q.recordedAt).toMatch(/^2026-11-01T\d\d:\d\d:\d\dZ$/);
        expect(q.answer.answer.length).toBeGreaterThan(40);
        // A board turn's answer is the coordinator's, with the three members' behind it
        expect(Array.isArray((q.answer as { perspectives?: unknown }).perspectives)).toBe(t.tier === 'board');
        expect(q.memberAnswers.map((m) => m.member)).toEqual(
          t.tier === 'board' ? ['conformance', 'encounter', 'impact'] : [],
        );
      }
    }
  });

  it("name only facts that exist on the case's What-if card, with the field the card gives them", () => {
    for (const c of recordedCases) {
      const facts = whatIfFor(c.caseId).facts;
      expect(facts.length, c.caseId).toBeGreaterThan(0);
      for (const [key, q] of Object.entries(c.questions)) {
        for (const id of namedFacts(q))
          expect(
            facts.map((f) => f.id),
            `${c.caseId} ${key}`,
          ).toContain(id);
        // What the core resolved is the card's own fact, and the change names the same field and receiver
        const answer = q.answer as unknown as Record<string, { fact?: string } | undefined>;
        for (const slot of ['setting', 'under_alternative', 'suggested_change'] as const) {
          const named = answer[slot]?.fact;
          expect(!!q.resolved[slot], `${c.caseId} ${key} ${slot}`).toBe(!!named);
          if (!named) continue;
          const card = facts.find((f) => f.id === named)!;
          if (slot === 'suggested_change')
            expect(q.resolved.suggested_change).toMatchObject({
              field: card.suggested_change.field,
              from: card.suggested_change.from,
              to: card.suggested_change.to,
              ...(card.receiver ? { receiver: card.receiver } : {}),
            });
          else expect(q.resolved[slot]).toEqual(card);
        }
      }
    }
  });

  it("name no encounter, patient or case but the demo case's own, and no dash", () => {
    for (const c of recordedCases) {
      const summary = demoCase(c.caseId);
      const own = new Set([c.caseId, summary.encounterId, summary.patientId]);
      const text = JSON.stringify([c.whatif, c.questions]);
      const named = text.match(/\b(?:C-\d{6}|ENC-\d+|MRN\d+)\b/g) ?? [];
      expect(
        named.filter((id) => !own.has(id)),
        c.caseId,
      ).toEqual([]);
      expect(text).not.toMatch(/[\u2013\u2014]/);
      expect(c.whatif.case_id).toBe(c.caseId);
      expect(c.whatif.receiver).toBe(c.receiver);
      expect(c.whatif.profile_version).toBe(fixtures.siteProfile.version);
    }
  });
});
