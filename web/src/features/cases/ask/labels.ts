import type { CaseQuestion, QuestionTier } from '@/api/types';
import { DEMO } from '@/demo';
import { parseTime } from '@/lib/format';
import { DEMO_ANSWERS_RECORDED } from './recorded';

/** The label of a demo answer that is not a recording. */
export const SAMPLE_LABEL = 'Example (sample data)';

export const TIERS: { value: QuestionTier; label: string; hint: string }[] = [
  { value: 'explain', label: 'Explain', hint: 'One agent, plain words. Quick.' },
  {
    value: 'board',
    label: 'Ask the board',
    hint: 'Three specialists and the coordinator. Deeper, slower.',
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
 * (the demo's mock does; the server does not send it yet), otherwise `answeredAt`.
 */
export function provenanceText(q: CaseQuestion): string {
  if (DEMO && !DEMO_ANSWERS_RECORDED) return SAMPLE_LABEL;
  if (isRecorded(q)) {
    const at = parseTime(q.recordedAt ?? q.answeredAt);
    if (at && q.model) return `Recorded live on ${day.format(at)} with ${q.model}`;
    if (at) return `Recorded live on ${day.format(at)}`;
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
  if (DEMO && !DEMO_ANSWERS_RECORDED) return 'Sample answers';
  if (asked.some((q) => q.source === 'suggested' && isRecorded(q))) return 'Recorded answers';
  return null;
}
