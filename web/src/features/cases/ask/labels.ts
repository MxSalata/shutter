import type { CaseQuestion, QuestionTier } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { parseTime } from '@/lib/format';
import { DEMO_ANSWERS_RECORDED } from './recorded';

/** The label of a demo answer that is not a recording. */
export const SAMPLE_LABEL = 'Example (sample data)';

export const TIERS: { value: QuestionTier; label: string; hint: string }[] = [
  { value: 'explain', label: 'Explain', hint: 'One agent, plain words. Quick.' },
  {
    value: 'board',
    label: 'Ask the board',
    hint: 'Three specialist agents and the coordinator agent. Deeper, slower.',
  },
];

export const tierLabel = (tier: string) => TIERS.find((t) => t.value === tier)?.label ?? tier;

/** The board members as the board's cards name them. */
export const MEMBER_NAMES: Record<string, string> = {
  explain: 'Explain',
  conformance: 'Conformance',
  encounter: 'Encounter Integrity',
  impact: 'Impact Analysis',
  coordinator: 'Coordinator',
};

// In UTC, the zone the API carries times in, so a recording reads as made on the same day wherever it is read
const day = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

/** Whether the server marks the answer as a recorded one (mode `replay`). */
const isRecorded = (q: CaseQuestion) => q.mode === 'replay';

/**
 * Where an answer came from, in a sentence: sample data in a demo whose answers are not recordings (see recorded.ts),
 * a recorded answer with its date and model, or a live answer. The date is `recordedAt` when the question carries it
 * (the demo's mock does; the server does not send it yet), otherwise `answeredAt`. In the trial the word "live" is kept
 * for the live system alone, so a recording reads as one made from a real run.
 */
export function provenanceText(q: CaseQuestion): string {
  if (TRIAL && !DEMO_ANSWERS_RECORDED) return SAMPLE_LABEL;
  if (isRecorded(q)) {
    const at = parseTime(q.recordedAt ?? q.answeredAt);
    const recorded = TRIAL ? 'Recorded from a real run' : 'Recorded live';
    if (at && q.model) return `${recorded} on ${day.format(at)} with ${q.model}`;
    if (at) return `${recorded} on ${day.format(at)}`;
    return 'Recorded answer';
  }
  if (q.source === 'free') return 'Answered live';
  return 'Answered';
}

/**
 * The badge beside the suggested questions, from the same source as each answer's provenance: sample answers in a
 * demo whose answers are not recordings, recorded answers only when an answer shown is a replay, otherwise none.
 */
export function answersBadge(asked: CaseQuestion[]): string | null {
  if (TRIAL && !DEMO_ANSWERS_RECORDED) return 'Sample answers';
  if (asked.some((q) => q.source === 'suggested' && isRecorded(q))) return 'Recorded answers';
  return null;
}

/** What the trial says of a question it has no recording for: it has recordings only, and where any question goes. */
export const TRIAL_NO_ANSWER =
  'The trial has recorded answers only. Pick a suggested question; on a live system, any question goes to the board.';

/**
 * The trial's cases with recorded questions and a recorded What-if card. On any other case the trial has neither, and
 * it says so rather than work one out: the mock knows no catalogue entry there, though the case's own page names one.
 * A test holds this to the recordings. A live page never loads the recordings, so it is written out here.
 */
export const TRIAL_ASK_CASES = ['C-000001', 'C-000002', 'C-000008', 'C-000053', 'C-000054', 'C-000055'];

/** The trial's case held at its approval (`HELD_CASES`, which a test holds this to). */
const TRIAL_HELD_CASE = 'C-000002';

/**
 * How a recorded conversation stands against the held case on the page: its answers were recorded after the recorded
 * approval and the resend that followed, which have not happened here until someone approves it. Once approved, the
 * page replays them and the answers are true of it again.
 */
export function heldAnswersNote(caseId: string, state: string | undefined, approver: boolean): string | null {
  if (caseId !== TRIAL_HELD_CASE) return null;
  const recorded = 'Recorded after this case was approved in the recording; here ';
  if (state === 'awaiting_approval') return `${recorded}it waits for ${approver ? 'you' : 'an approver'}.`;
  if (state === 'blocked') return `${recorded}it was rejected.`;
  return null;
}

/** The opening of an answer is at most this many words, a card body's budget; the rest waits behind a disclosure. */
const LEAD_WORDS = 40;
const wordCount = (text: string) => text.split(/\s+/).filter(Boolean).length;

/**
 * An answer split for reading: its first paragraph when that is short, otherwise its first sentences up to 40 words
 * (always at least one), and the rest, which "Show the whole answer" opens. Nothing is cut mid-sentence and
 * nothing is left out: the opening and the rest together are the whole answer.
 */
export function answerParts(text: string): { lead: string; rest: string } {
  const paragraphs = (text ?? '')
    .split(/\n/)
    .map((p) => p.trim())
    .filter(Boolean);
  if (!paragraphs.length) return { lead: '', rest: '' };
  const [first, ...others] = paragraphs;
  if (wordCount(first) <= LEAD_WORDS) return { lead: first, rest: others.join('\n\n') };
  const sentences = first.split(/(?<=[.!?])\s+(?=[A-Z0-9"'(])/);
  let taken = 1;
  while (taken < sentences.length && wordCount(sentences.slice(0, taken + 1).join(' ')) <= LEAD_WORDS)
    taken++;
  const lead = sentences.slice(0, taken).join(' ');
  const rest = [sentences.slice(taken).join(' '), ...others].filter(Boolean).join('\n\n');
  return { lead, rest };
}
