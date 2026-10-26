import type {
  Answer,
  BoardAnswer,
  CaseQuestion,
  QuestionTier,
  SuggestedQuestions,
  WhatIf,
} from '@/api/types';
import s2 from '../../../knowledge/questions/S2.json';
import s8 from '../../../knowledge/questions/S8.json';

/**
 * MOCK DATA, NOT RECORDINGS. The answers below are sample answers, written for the demo from the recorded findings and
 * plans of C-000008 (S8, board) and C-000002 (S2, board) in fixtures.json, so that the panel can be shown and tested
 * before the server's question routes exist. The live re-record replaces them with real recorded runs (every message a
 * real run, never hand-written); until then the page labels them "Example (sample data)" (DEMO_ANSWERS_RECORDED in
 * features/cases/ask/labels.ts). The What-if facts are what Shutter.Util.WhatIf should compute for these two cases from
 * catalogue entries E7 and E2 and the recorded site profile (version 9).
 */

/** The suggested questions, as the scenario files in knowledge/questions write them. */
const SUGGESTED: Record<string, SuggestedQuestions> = {
  S2: s2 as SuggestedQuestions,
  S8: s8 as SuggestedQuestions,
};

/** The cases the sample answers were written for, by scenario. */
export const SAMPLE_CASES: Record<string, string> = { 'C-000008': 'S8', 'C-000002': 'S2' };

type SampleAnswer = Answer | BoardAnswer;

const SAMPLE_ANSWERS: Record<string, Record<string, SampleAnswer>> = {
  S8: {
    'c1.1': {
      answer:
        "The PAS transfer of ENC-1008 to WARD-B failed with HTTP 503 ward_unavailable, and the receiver holds no receipt for it (404), so it never arrived. The receiver shows the encounter in WARD-C at version 2, set by the bed manager's transfer MSG00803, which carries the same event time, 08:20:00Z. Neither movement is later, so Shutter cannot tell which one is current, and a resend would overwrite the bed manager's placement. The board escalated to a person, and the plan writes nothing. The gate passed it because a plan that writes nothing breaks none of its checks.",
      cites: ['error', 'receipt', 'ward_state', 'timeline', 'catalogue:E7'],
      confidence: 'high',
    },
    'c1.2': {
      answer:
        'Nothing in the evidence decides which system wins: the receiver still has WARD-C from the bed manager, and the site profile names no authoritative source. Until a person decides that the PAS movement to WARD-B should stand, a resend conditional on version 2 would apply and move the patient away from the bed manager’s placement. The person the case went to can check the ward first, then correct the receiver by hand or close the case as handled.',
      cites: ['ward_state', 'timeline', 'operation'],
      confidence: 'medium',
    },
    'c1.3': {
      answer:
        "If the site named the bed manager (BEDMGR) as the authoritative source for ward placement, catalogue entry E7's alternative would apply: the bed manager's WARD-C placement stands, and this PAS transfer closes with nothing written, without waiting for a person. Today the profile names no authoritative source, so the case escalated. It is a decision for the site: it applies to every case where the PAS and the bed manager move an encounter at the same event time, not only to this one.",
      perspectives: [
        {
          member: 'conformance',
          view: 'The message stays valid either way. The setting does not change what the PAS sent, only which movement the site keeps when two carry the same time.',
        },
        {
          member: 'encounter',
          view: "With the bed manager authoritative, the receiver's version 2 in WARD-C is the current state, and the unknown supersession of ELS-2.5 is settled by the site's rule instead of by the times.",
        },
        {
          member: 'impact',
          view: 'Nothing is written, so the bed board, pharmacy and the porters keep WARD-C. That is right only if the bed manager really is the system of record for beds.',
        },
      ],
      setting: { fact: 'W1' },
      under_alternative: { fact: 'W1' },
      suggested_change: {
        fact: 'W1',
        why: 'Name the bed manager as the system that wins a same-time tie, if that is how the wards work.',
      },
      cites: ['W1', 'ward_state', 'timeline', 'catalogue:E7'],
      confidence: 'medium',
    },
    'c2.1': {
      answer:
        "Shutter cannot tell, and that is why the case was escalated. The receiver shows WARD-C at version 2, set by the bed manager's transfer MSG00803. The PAS transfer to WARD-B, MSG00802, never arrived. Both carry the event time 2026-10-15T08:20:00Z, so neither is later (ELS-2.5).",
      cites: ['timeline', 'ward_state'],
      confidence: 'high',
    },
    'c3.1': {
      answer:
        'Ask the ward where the patient of encounter ENC-1008 is: in WARD-B, as the PAS says, or in WARD-C, as the bed manager and the receiver say. Then check on the Evidence tab that the receiver is still at version 2 in WARD-C. If the patient is in WARD-B, the receiver needs correcting by hand; if in WARD-C, nothing needs sending and the case can be closed as handled.',
      cites: ['ward_state', 'timeline'],
      confidence: 'medium',
    },
    'c4.1': {
      answer:
        'Conformance proposed a resend with confidence 0.8: the message is structurally valid, the WIC-2.1 fields are present and the WIC-2.2 key matches. The coordinator kept that dissent in the plan but chose to escalate: the message is acceptable as a message, and Conformance itself left the same-time bed manager transfer to the other specialists. A resend conditional on version 2 would overwrite the bed manager’s WARD-C placement while supersession is unknown.',
      perspectives: [
        {
          member: 'conformance',
          view: 'Seen as a message, MSG00802 is valid and would be accepted; whether it should be sent is not a conformance question.',
        },
        {
          member: 'encounter',
          view: 'Equal event times leave supersession unknown (ELS-2.5), so the movement must not be applied.',
        },
        {
          member: 'impact',
          view: 'A resend would move the patient from WARD-C to WARD-B, free and occupy beds, redirect pharmacy and create a porter task.',
        },
      ],
      cites: ['message', 'validation', 'timeline'],
      confidence: 'high',
    },
    'c5.1': {
      answer:
        'A resend conditional on version 2 would have applied: the receiver would have moved the patient from WARD-C to WARD-B. Under the dependency contracts that frees a bed on WARD-C, occupies one on WARD-B, sends pharmacy to a different ward and creates a porter task, all on the strength of a movement that may not be current. Doing nothing leaves WARD-C in place, which is right only if the bed manager’s placement is.',
      perspectives: [
        {
          member: 'impact',
          view: 'The route supports conditional writes, receipts and dry runs, but the version guard protects nothing here: version 2 is the state the resend would overwrite.',
        },
        {
          member: 'encounter',
          view: 'The transition from admitted is allowed, so the receiver would accept it; the question is which movement is current.',
        },
        {
          member: 'conformance',
          view: 'The receiver would read the message without trouble; nothing in it would stop the write.',
        },
      ],
      cites: ['route', 'ward_state', 'timeline'],
      confidence: 'medium',
    },
  },
  S2: {
    'c1.1': {
      answer:
        'The transfer MSG00202 of ENC-1002 to WARD-B failed with HTTP 503 ward_unavailable, and the receipt lookup returned 404, so the receiver never committed it. The receiver still showed the encounter admitted on WARD-A at version 1, and no later event had changed it. That is catalogue entry E2, not delivered and still current, whose preferred outcome is a resend. All three specialists agreed: the plan resends the transfer unchanged, conditional on version 1, once the gate has passed it and it is released.',
      cites: ['error', 'receipt', 'ward_state', 'timeline'],
      confidence: 'high',
    },
    'c1.2': {
      answer:
        'From two separate checks after the resend. The receiver acknowledges the write with a receipt naming the operation, the version it moved from and the version it moved to. Then verification reads the encounter back and looks for the transfer in its history (RP-4.1). Only the second says the effect is in place at the receiver, and the case page shows them apart.',
      cites: ['receipt', 'ward_state'],
      confidence: 'high',
    },
    'c1.3': {
      answer:
        'No. Catalogue entry E2 has no alternative outcome, so no site profile setting changes what this case should do: the transfer was due and still current. The profile decides who releases such a resend, a person or the site\u2019s written policy, not whether it is the right action.',
      perspectives: [
        {
          member: 'conformance',
          view: 'The message was valid and resent unchanged; no setting alters that.',
        },
        {
          member: 'encounter',
          view: 'Nothing later changed the encounter, so there was no history or source rule to weigh.',
        },
        {
          member: 'impact',
          view: 'One bounded movement, conditional on version 1, checked afterwards through the receipt and the history.',
        },
      ],
      cites: ['ward_state', 'timeline', 'route'],
      confidence: 'high',
    },
    'c2.1': {
      answer:
        "The gate checks the plan when it is proposed and again before dispatch. At the proposal every check passed: the patient's identity, the message's schema, that the plan does exactly the failed operation, ordering, the state transition, the effect, the version guard, fresh evidence, the receiver's capabilities and the catalogue entry; the approver's authority is checked at approval and dispatch.",
      cites: ['validation', 'route'],
      confidence: 'high',
    },
    'c3.1': {
      answer:
        'No. Conformance, Encounter Integrity and Impact Analysis each proposed a resend, with confidence 0.9, 0.9 and 0.88. Their open questions were about what the evidence cannot show, such as whether systems downstream acted on the stale WARD-A location; the condition on version 1 guards the one that matters to the write.',
      perspectives: [
        {
          member: 'conformance',
          view: 'Resend: the message parses, its required fields are present and its key matches the operation.',
        },
        {
          member: 'encounter',
          view: 'Resend: the receipt lookup returned 404 and no later event supersedes the transfer (ELS-2.1).',
        },
        {
          member: 'impact',
          view: 'Resend: one bounded movement; doing nothing leaves the bed board, pharmacy and the record on WARD-A.',
        },
      ],
      cites: ['receipt', 'timeline', 'route'],
      confidence: 'high',
    },
    'c4.1': {
      answer:
        'The resend was conditional on version 1. Had another movement reached the receiver first, its version would have moved on, the receiver would have refused the write and nothing would have changed; the case would have been investigated again on fresh evidence. Before dispatch, the gate checks the same version and the snapshot’s freshness.',
      perspectives: [
        {
          member: 'impact',
          view: 'The condition makes the write fail safe: a refusal changes nothing downstream.',
        },
        {
          member: 'encounter',
          view: 'A later movement would make this transfer superseded, which is catalogue entry E1, not a resend.',
        },
        {
          member: 'conformance',
          view: 'The message itself would not change; only whether it is still due.',
        },
      ],
      cites: ['ward_state', 'route'],
      confidence: 'medium',
    },
  },
};

/** What Shutter.Util.WhatIf should give for the two cases, from the catalogue and the recorded profile (version 9). */
const SAMPLE_WHATIF: Record<string, WhatIf> = {
  S8: {
    entry: 'E7',
    outcome: 'escalate',
    disposition: 'escalate',
    profileVersion: 9,
    facts: [
      {
        id: 'W1',
        kind: 'alternative',
        field: 'authoritative_source',
        from: '',
        to: 'BEDMGR',
        alternative: {
          outcome: 'none',
          disposition: 'superseded',
          when: 'authoritative_source: other_source',
        },
        would:
          "The bed manager's WARD-C placement would stand, and this PAS transfer would close with nothing written instead of going to a person.",
        affects: ['every case where the PAS and the bed manager move an encounter at the same event time'],
      },
    ],
  },
  S2: { entry: 'E2', outcome: 'resend', disposition: 'resend', profileVersion: 9, facts: [] },
};

export function suggestedFor(caseId: string): SuggestedQuestions | null {
  const s = SAMPLE_CASES[caseId];
  return s ? structuredClone(SUGGESTED[s]) : null;
}

export function whatIfFor(caseId: string): WhatIf | null {
  const s = SAMPLE_CASES[caseId];
  return s ? structuredClone(SAMPLE_WHATIF[s]) : null;
}

/** The sample answer to a turn of a suggested conversation, or null when there is none. */
export function sampleAnswer(caseId: string, conversation: string, turn: number) {
  const s = SAMPLE_CASES[caseId];
  const answer = s ? SAMPLE_ANSWERS[s]?.[`${conversation}.${turn}`] : undefined;
  const text = s
    ? SUGGESTED[s].conversations.find((c) => c.id === conversation)?.turns.find((t) => t.turn === turn)
    : undefined;
  return answer && text ? { answer: structuredClone(answer), tier: text.tier, question: text.text } : null;
}

let next = 1;

/** A sample answer as the question routes would store it: replayed, at no cost, with no recording behind it. */
export function sampleQuestion(
  caseId: string,
  conversation: string,
  turn: number,
  askedBy: string,
  askedAt: string,
): CaseQuestion | null {
  const found = sampleAnswer(caseId, conversation, turn);
  if (!found) return null;
  const tier: QuestionTier = found.tier;
  const members = tier === 'board' ? ['conformance', 'encounter', 'impact', 'coordinator'] : ['explain'];
  return {
    questionId: `Q-${String(next++).padStart(6, '0')}`,
    caseId,
    conversation,
    turn,
    tier,
    source: 'suggested',
    question: found.question,
    state: 'answered',
    answer: found.answer,
    recording: null,
    runs: members.map((member) => ({
      member,
      model: null,
      mode: 'replay',
      promptTokens: null,
      completionTokens: null,
      costUsd: 0,
    })),
    askedBy,
    askedAt,
    answeredAt: askedAt,
  };
}

/**
 * The questions a showcase case starts with: its scenario's first conversation, as the re-record stores it on the case,
 * so the panel opens on an example.
 */
export function startingQuestions(caseId: string, at: string): CaseQuestion[] {
  const s = suggestedFor(caseId);
  const first = s?.conversations[0];
  if (!first) return [];
  return first.turns.flatMap((t) => sampleQuestion(caseId, first.id, t.turn, 'setup', at) ?? []);
}

/** For tests: number the questions afresh. */
export function resetQuestionIds() {
  next = 1;
}
