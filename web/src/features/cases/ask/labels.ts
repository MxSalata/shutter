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

const day = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });

/**
 * Where an answer came from, in a sentence: sample data in the demo until the re-record, the recording's date and model
 * when it is one, or a live answer.
 */
export function provenanceText(q: CaseQuestion): string {
  if (DEMO && !DEMO_ANSWERS_RECORDED) return SAMPLE_LABEL;
  const at = parseTime(q.recording?.recordedAt);
  if (q.recording && at) return `Recorded live on ${day.format(at)} with ${q.recording.model}`;
  if (q.source === 'free') return 'Answered live';
  return 'Answered';
}

/**
 * The badge beside the suggested questions, from the same source as each answer's provenance: sample answers in the
 * demo until the re-record, recorded answers only when an answer shown carries its recording, otherwise none.
 */
export function answersBadge(asked: CaseQuestion[]): string | null {
  if (DEMO && !DEMO_ANSWERS_RECORDED) return 'Sample answers';
  if (asked.some((q) => q.source === 'suggested' && !!q.recording && !!parseTime(q.recording.recordedAt)))
    return 'Recorded answers';
  return null;
}
