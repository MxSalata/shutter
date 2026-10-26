/**
 * Whether the demo's answers are real recorded runs. The demo serves sample answers (mocks/questions.ts) until the live
 * re-record replaces them with recordings; the re-record sets this to true in the same change, and only then does the
 * demo call them recorded. Until then every demo answer, and the suggested questions' badge, reads as sample data.
 */
export const DEMO_ANSWERS_RECORDED = false;
