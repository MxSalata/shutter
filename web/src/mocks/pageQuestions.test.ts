import { describe, expect, it } from 'vitest';
import { GUIDES } from '@/features/assistant/guides';
import { PAGES_WITH_ANSWERS, pageAnswerFor, questionsWithAnswers, suggestedQuestions } from './pageQuestions';

/** The trial's sample answers and the panel's suggested questions are one list: every question has its answer and no more. */
describe("the pages' sample answers", () => {
  it('cover every suggested question of every page, and nothing else', () => {
    expect(PAGES_WITH_ANSWERS.sort()).toEqual(Object.keys(GUIDES).sort());
    for (const page of Object.keys(GUIDES)) {
      expect(questionsWithAnswers(page).sort()).toEqual(suggestedQuestions(page).sort());
      for (const q of suggestedQuestions(page)) {
        const a = pageAnswerFor(page, q);
        expect(a, `${page}: ${q}`).not.toBeNull();
        expect(a!.answer.length).toBeLessThanOrEqual(1200);
        expect(a!.cites).toEqual(['page']);
      }
    }
  });

  it('answer no other question, and never say "live" in the trial', () => {
    expect(pageAnswerFor('cases', 'Resend everything')).toBeNull();
    expect(pageAnswerFor('nowhere', 'What is a case?')).toBeNull();
    for (const page of Object.keys(GUIDES))
      for (const q of suggestedQuestions(page)) {
        const text = pageAnswerFor(page, q)!.answer;
        expect(text.replace(/\blive system\b/gi, ''), `${page}: ${q}`).not.toMatch(/\blive\b/i);
      }
  });

  it('keep every guide to plain words with links into the app', () => {
    for (const [page, g] of Object.entries(GUIDES)) {
      expect(g.what.split(/\s+/).length, page).toBeLessThanOrEqual(60);
      expect(g.next.length, page).toBeGreaterThan(0);
      for (const n of g.next) expect(n.to, `${page}: ${n.label}`).toMatch(/^\//);
      expect(g.questions.length, page).toBeGreaterThan(0);
      expect(g.what.replace(/\blive system\b/gi, ''), page).not.toMatch(/\blive\b/i);
    }
  });
});
