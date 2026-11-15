import type { SiteProfile, SiteReceiver } from '@/api/types';
import type { PageFocus } from '@/features/assistant/store';
import type { Tone } from '@/lib/tone';
import {
  SETUP_PAGE,
  answerText,
  consequence,
  whyQuestion,
  type QuestionId,
  type SetupQuestion,
} from './fields';
import type { AnswerStatus } from './setupStore';

/** What the cards of Set up the site share: their badges' words, their ids, and what "Why does this matter?" asks. */

/** A question's badge, by how its answer stands. */
export const STATUS_WORDS: Record<AnswerStatus, { label: string; tone: Tone }> = {
  in_force: { label: 'In force', tone: 'neutral' },
  you: { label: 'You set this', tone: 'info' },
  ask: { label: 'Drafted by Ask Shutter', tone: 'attention' },
  onboarding: { label: 'From onboarding: confirm', tone: 'attention' },
  unanswered: { label: 'Not answered', tone: 'neutral' },
  left: { label: 'Left for now', tone: 'neutral' },
};

/** The badge's words, with the version for an answer in force: "In force, version 12". */
export const statusLabel = (status: AnswerStatus, version: number): string =>
  status === 'in_force' ? `In force, version ${version}` : STATUS_WORDS[status].label;

/** The ids of a question's card, its heading and its control, by where it stands on the page. */
export const cardId = (q: QuestionId) => `setup-card-${q}`;
export const cardTitleId = (q: QuestionId) => `setup-card-${q}-title`;
export const controlId = (key: string) => `setup-${key}`;

/** What "Why does this matter?" opens: the question, the answer on the page and what it does, in the page's words. */
export function whyFocus(q: SetupQuestion, r: SiteReceiver, profile: SiteProfile): PageFocus {
  return {
    page: SETUP_PAGE,
    id: cardId(q.id),
    title: q.text,
    question: whyQuestion(q, r.name),
    answer: answerText(q, r) || 'Not answered',
    consequence: consequence(q, r, profile),
    written: q.written,
  };
}

export const SUMMARY_TITLE_ID = 'setup-summary-title';
export const ASK_HERE_ID = 'setup-ask-here';

/** Focus on an element once the page has drawn it. */
export const focusLater = (id: string) => window.setTimeout(() => document.getElementById(id)?.focus(), 0);
