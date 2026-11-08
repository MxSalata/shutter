/**
 * Whether the trial's answers to the pages' suggested questions are real recorded runs. They are not yet: the answers in
 * mocks/pageQuestions.ts are written by hand from what each page shows, so the trial labels each "Example (sample data)".
 * Once the suggested questions have been asked on an instance with a model and their answers copied into the mock, set
 * this to true and the trial labels them "Recorded from a real run on <date> with <model>", as the case answers are.
 */
export const PAGE_ANSWERS_RECORDED = false;
