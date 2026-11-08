import type { Answer, PageQuestion, QuestionState } from '@/api/types';
import { GUIDES } from '@/features/assistant/guides';

/**
 * SAMPLE ANSWERS. The trial's answers to the pages' suggested questions (features/assistant/guides.ts) are written by
 * hand from what each page shows: no model answered them, and nothing is recorded. The panel labels each "Example
 * (sample data)" (PAGE_ANSWERS_RECORDED in features/assistant/recorded.ts). On a live install with a model the same
 * questions go to the Explain agent in the tier page (CONTRACTS 14.6).
 */

type Answers = Record<string, Record<string, string>>;

const ANSWERS: Answers = {
  home: {
    'Where should I start?':
      'Start with Scenarios: each one replays a known failure on the demo hospital, so you can watch a recovery from the failed message to the verified write. Then open Cases to read what each recovery did and who decided.',
    'What does each section do?':
      'Operate holds the recovery itself: Scenarios to play a failure, Cases for each failed delivery, Incidents for many failures handled together, and Production review for a read-only check of a production. Results holds the proof: Evaluation and Health. Configure holds the site profile, the agent library and the settings.',
  },
  scenarios: {
    'What is a scenario?':
      'A scenario is one known failure of a hospital message, replayed on the demo hospital: a transfer that reaches the bed system too late, a discharge before its admission, a merge that must not be resent. Playing it runs the whole recovery and makes a case you can open.',
    'Which scenario should I play first?':
      'The page suggests a path under Try first: the first scenario on it is the plainest recovery, a transfer that is resent and verified at the receiver. The path then goes on to a failure the board escalates to a person.',
    'What do the outcomes mean?':
      "Each row's outcome is the case's: Delivered, verified means a write landed and was read back at the receiver; Nothing to send means the receiver already had it; Escalated means a person decides; Blocked means the gate refused a write and nothing was sent. As expected says the outcome is the one the scenario expects.",
  },
  cases: {
    'Which cases need me?':
      'The tiles at the top count the cases waiting for a person: an approval to release, or an escalation to decide. Press a tile and the list shows only those. A case needing nobody is closed, or still running.',
    'What does each outcome colour mean?':
      'Green is a result verified at the receiver: a delivery, or nothing to send. Yellow means a person is needed: waiting for approval, or escalated. Red means refused, failed or contradicted at the receiver: blocked, failed, or not the expected outcome. Grey is closed with nothing waiting.',
    'What is a case?':
      "A case is one failed delivery of a hospital message to one receiving system. Shutter collects the evidence, a board of agents proposes what to do, a deterministic gate decides what may happen, and a person approves where the site's policy says so. The case page tells that story step by step.",
  },
  incidents: {
    'What is an incident?':
      'An incident is many failures to one receiver within a few minutes, handled together instead of one case at a time. Its cases are grouped into chains, one per patient visit, and released in event order under one approval.',
    'What is a chain?':
      "A chain is one patient visit's failed messages inside an incident, sent in the order the events happened, so a transfer never lands before its admission. The incident page lists each chain with how it stands.",
  },
  incident: {
    'What is a chain?':
      "A chain is one patient visit's failed messages inside this incident, sent in event order. Each chain on the page shows its cases and whether it was resolved, stopped by the gate or escalated.",
    'Who released this incident?':
      "The incident's approval section names who released it and when, or that it waits for an approver. One approval binds every chain; the timeline below shows each step as it happened.",
  },
  reviews: {
    'What does a review check?':
      "A review reads a production's settings and its recent errors, with no change to either, and an agent ranks what it found by severity. Each finding names the setting or the error signature it rests on and the cases it touched.",
    'What do the severities mean?':
      'The findings are ranked High, Medium, Low and Info by the agent that reviewed the production. High is drawn in red, the tone for something refused, failed or contradicted; Medium in yellow, where a person is needed; Low in blue, worth seeing; Info in grey, a fact. An approver may annotate a finding as intended or an accepted risk, and it stays noted in later reviews.',
  },
  review: {
    'What do the severities mean?':
      'The findings are ranked High, Medium, Low and Info by the agent that reviewed the production. High is drawn in red, the tone for something refused, failed or contradicted; Medium in yellow, where a person is needed; Low in blue, worth seeing; Info in grey, a fact.',
    'What does an annotation do?':
      "An approver's annotation marks a finding intended, an accepted risk or a false positive. It is stored in Shutter, never in the production, and applies to every review of this production until the value changes, it expires or it is removed.",
  },
  'site-profile': {
    'Who releases a write?':
      "Each receiver's tier says who releases a write to it: the site's written policy lets some writes go by themselves, and a person with the approver role releases the rest. The policy section shows the rule for each tier, and a case's receiver line repeats it.",
    'What is a receiver category?':
      'A receiver either needs only where the patient is now (current state, such as a bed system) or every movement in order (history of record, such as the patient record). The category decides whether a late message is still worth sending.',
    'What is a tier?':
      'A tier is how sensitive a receiver is: 1 information, 2 operations, 3 clinical safety. It sets who releases a write there, the written policy or a person.',
  },
  library: {
    'What does each agent do?':
      'Three specialist agents each read the same evidence from one angle: conformance of the message, the integrity of the patient encounter, and the impact on the receiving system. Each card says what it asks and what it knows.',
    'What is the coordinator for?':
      "The coordinator agent turns the three specialists' findings into one plan, keeping any disagreement in it. The plan then goes to the deterministic gate, which decides what may happen.",
  },
  settings: {
    'What does the mode mean?':
      "The mode says how the agents answer: live, with a model, or replay, from recorded runs at no cost. Auto is what the instance decides from its configuration. Each agent item's row shows the mode it resolved to.",
    'What is the budget?':
      "The day's budget caps what the live agents may spend between one midnight UTC and the next; a share of it is each judge's. When it is spent, live runs are refused until the reset and recorded runs still work.",
    'Where do the costs come from?':
      'Each run is costed from its tokens at the prices listed on this page, which name their source and date. A replay and a run the API mimic answered cost nothing.',
  },
  evaluation: {
    'What is being compared?':
      'For each scenario, what the board proposed is set against what the scenario expects, beside what the single investigator and rules alone proposed on the same failures. The comparisons share one base, so the figures can be read side by side.',
    'What does "as expected" mean?':
      "A pass is as expected when the proposed action matches the scenario's expected disposition and no forbidden write was made. Not as expected is marked in red, and stopped by the gate means a wrong proposal was caught before anything was sent.",
  },
  health: {
    'Is the installation healthy?':
      'The verdict at the top says so: every required check passed, or which one failed. Each group below lists its checks with their results; a part that is optional and absent is marked neutral, not failed.',
    'What does a failed check mean?':
      'A required check that failed names the part that is not working: the message engine, a web page, an agent item or the licence. The row says what it means; the installation notes in the repository say how to put it right.',
  },
};

/** The sample answer to one of a page's suggested questions, or null for any other question. */
export function pageAnswerFor(page: string, question: string): Answer | null {
  const text = ANSWERS[page]?.[question.trim()];
  if (!text) return null;
  return { answer: text, cites: ['page'], confidence: 'medium' };
}

/** Every suggested question has a sample answer, and nothing else does: a test holds the two lists together. */
export const PAGES_WITH_ANSWERS = Object.keys(ANSWERS);
export const questionsWithAnswers = (page: string) => Object.keys(ANSWERS[page] ?? {});
export const suggestedQuestions = (page: string) => GUIDES[page]?.questions ?? [];

let next = 1;

/** A page question as the route stores one the trial answered: a replay at no cost, with no model. */
export function samplePageQuestion(
  page: string,
  question: string,
  answer: Answer,
  askedBy: string,
  askedAt: string,
): PageQuestion {
  const state: QuestionState = 'answered';
  return {
    questionId: `P-${String(next++).padStart(6, '0')}`,
    tier: 'page',
    page,
    question,
    state,
    askedBy,
    askedAt,
    answeredAt: askedAt,
    error: null,
    mode: 'replay',
    model: null,
    costUsd: 0,
    ensMessageId: null,
    answer,
  };
}

export function resetPageQuestionIds(): void {
  next = 1;
}
