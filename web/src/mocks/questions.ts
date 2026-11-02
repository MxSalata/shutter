import type {
  Answer,
  BoardAnswer,
  CaseQuestion,
  CaseQuestionDetail,
  QuestionState,
  QuestionTier,
  SuggestedQuestions,
  WhatIf,
} from '@/api/types';
import fixtures from './fixtures.json';
import recordedFile from './recorded-questions.json';

/**
 * RECORDED ANSWERS. The answers the demo serves to "Ask about this case" are real recorded runs, not written by hand:
 * every suggested turn of the scenarios S1, S2, S8, S20 and S22 was asked live and recorded (mode record), and
 * scripts/export-recorded-answers.mjs copies those answers, the members' answers behind each board answer, what the
 * core resolved, the case's What-if card and the time of each recording into recorded-questions.json. The demo replays
 * them at no cost, so the page labels each "Recorded live on <date> with <model>" (DEMO_ANSWERS_RECORDED in
 * features/cases/ask/recorded.ts). The ids in them are the demo case's own (the export rewrites the recording
 * instance's), and the What-if facts are what that instance's Shutter.Util.WhatIf returned for the same story, so
 * the W ids an answer cites exist on the case's card.
 */

/** The scenario files as knowledge/questions write them: turns with no `asked` yet. */
type QuestionsFile = {
  scenario: string;
  conversations: { id: string; turns: { turn: number; tier: QuestionTier; text: string }[] }[];
};
const SUGGESTED: Record<string, QuestionsFile> = Object.fromEntries(
  Object.values(
    import.meta.glob<QuestionsFile>('../../../knowledge/questions/S*.json', {
      eager: true,
      import: 'default',
    }),
  ).map((file) => [file.scenario, file]),
);

/** One recorded turn, as the export writes it. */
export interface RecordedQuestion {
  question: string;
  tier: QuestionTier;
  answer: Answer | BoardAnswer;
  memberAnswers: CaseQuestionDetail['memberAnswers'];
  resolved: CaseQuestionDetail['resolved'];
  model: string;
  recordedAt: string;
}

/** A demo case's recordings: its What-if card and its turns, by "conversation.turn". */
export interface RecordedCase {
  caseId: string;
  whatif: WhatIf;
  questions: Record<string, RecordedQuestion>;
}

/** The recordings by scenario, then by the receiver the case is about (S22 has a case for each of its two). */
export const RECORDED: Record<string, Record<string, RecordedCase>> = (
  recordedFile as unknown as { scenarios: Record<string, Record<string, RecordedCase>> }
).scenarios;

/** The demo cases the recordings belong to: each one's scenario and receiver. */
export const DEMO_CASES: Record<string, { scenario: string; receiver: string }> = Object.fromEntries(
  Object.entries(RECORDED).flatMap(([scenario, byReceiver]) =>
    Object.entries(byReceiver).map(([receiver, c]) => [c.caseId, { scenario, receiver }]),
  ),
);

/** The recordings of a demo case, or undefined for any other case. */
function recordedCase(caseId: string): RecordedCase | undefined {
  const demo = DEMO_CASES[caseId];
  return demo ? RECORDED[demo.scenario]?.[demo.receiver] : undefined;
}

/** The scenario's file for the case, or null when it has no scenario or no file. */
export function suggestedFor(caseId: string): QuestionsFile | null {
  const s = DEMO_CASES[caseId]?.scenario;
  const file = s ? SUGGESTED[s] : undefined;
  return file ? structuredClone(file) : null;
}

/** The suggested route's answer: the file's turns, each with the newest question asked for it; empty without a file. */
export function suggestedWithAsked(
  caseId: string,
  asked: Pick<CaseQuestion, 'questionId' | 'conversation' | 'turn' | 'state'>[],
): SuggestedQuestions {
  const file = suggestedFor(caseId);
  if (!file) return { scenario: DEMO_CASES[caseId]?.scenario ?? '', conversations: [] };
  return {
    scenario: file.scenario,
    conversations: file.conversations.map((c) => ({
      id: c.id,
      turns: c.turns.map((t) => {
        const q = asked.filter((x) => x.conversation === c.id && x.turn === t.turn).at(-1);
        return { ...t, asked: q ? { questionId: q.questionId, state: q.state } : null };
      }),
    })),
  };
}

/** The deterministic card: the recorded one for a demo case, otherwise a case with no catalogue entry and no facts. */
export function whatIfFor(caseId: string): WhatIf {
  const recorded = recordedCase(caseId);
  if (recorded) return structuredClone(recorded.whatif);
  return {
    case_id: caseId,
    receiver: '',
    category: 'current_state',
    entry: '',
    outcome: 'none',
    outcome_ref: '',
    disposition: '',
    profile_version: fixtures.siteProfile.version,
    note: 'Sample data: this case matched no catalogue entry that a site profile setting selects.',
    facts: [],
  };
}

/** The recorded turn of a demo case's suggested conversation, or undefined when there is none. */
const recordedTurn = (caseId: string, conversation: string, turn: number) =>
  recordedCase(caseId)?.questions[`${conversation}.${turn}`];

let next = 1;

/** A recorded answer as the question routes store a replay: no cost, the recording's model and time. */
export function recordedQuestion(
  caseId: string,
  conversation: string,
  turn: number,
  askedBy: string,
  askedAt: string,
): CaseQuestion | null {
  const found = recordedTurn(caseId, conversation, turn);
  if (!found) return null;
  const state: QuestionState = 'answered';
  return {
    questionId: `Q-${String(next++).padStart(6, '0')}`,
    caseId,
    conversation,
    turn,
    tier: found.tier,
    source: 'suggested',
    question: found.question,
    state,
    answer: structuredClone(found.answer),
    error: null,
    mode: 'replay',
    model: found.model,
    costUsd: 0,
    runs: found.tier === 'board' ? found.memberAnswers.length + 1 : 1,
    recordKey: null,
    ensMessageId: null,
    askedBy,
    askedAt,
    answeredAt: askedAt,
    recordedAt: found.recordedAt,
  };
}

/** A stored question as GET /cases/{id}/questions/{qid} reads it: the facts, the members' answers, the resolved change. */
export function questionDetail(q: CaseQuestion): CaseQuestionDetail {
  const found = recordedTurn(q.caseId, q.conversation, q.turn);
  const memberAnswers = structuredClone(found?.memberAnswers ?? []);
  const members = q.tier === 'board' ? [...memberAnswers.map((m) => m.member), 'coordinator'] : ['explain'];
  return {
    ...q,
    facts: whatIfFor(q.caseId).facts,
    memberAnswers,
    resolved: structuredClone(found?.resolved ?? {}),
    agentRuns: members.map((member, i) => ({
      runId: `${q.questionId}-${i + 1}`,
      role: member === 'coordinator' ? 'coordinator' : member === 'explain' ? 'explain' : 'member',
      member,
      status: 'ok',
      mode: 'replay',
      model: q.model,
      costUsd: 0,
      durationMs: null,
      ensMessageId: null,
      error: null,
    })),
  };
}

/**
 * The questions a demo case starts with: its scenario's first conversation, as the recording stores it on the case, so
 * the panel opens on an example.
 */
export function startingQuestions(caseId: string, at: string): CaseQuestion[] {
  const s = suggestedFor(caseId);
  const first = s?.conversations[0];
  if (!first) return [];
  return first.turns.flatMap((t) => recordedQuestion(caseId, first.id, t.turn, 'setup', at) ?? []);
}

/** For tests: number the questions afresh. */
export function resetQuestionIds() {
  next = 1;
}
