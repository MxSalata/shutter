import { describe, expect, it } from 'vitest';
import {
  back,
  goToChapter,
  INITIAL,
  isProgress,
  next,
  positionOf,
  skipChapter,
  start,
  welcomeDue,
  type GuideProgress,
} from './controller';
import { chapterById, SCOPES } from './registry';

const at = (chapter: string, step = 0, more: Partial<GuideProgress> = {}): GuideProgress => ({
  ...INITIAL,
  chapter,
  step,
  ...more,
});

describe('the guide controller', () => {
  it('opens the welcome only before the guide was started, finished or dismissed', () => {
    expect(welcomeDue(INITIAL)).toBe(true);
    expect(welcomeDue({ ...INITIAL, dismissed: true })).toBe(false);
    expect(welcomeDue(at('s2'))).toBe(false);
    expect(welcomeDue({ ...INITIAL, completed: ['scenarios'] })).toBe(false);
  });

  it('starts a scope at its first chapter and step', () => {
    const p = start(INITIAL, 'all');
    expect(p).toMatchObject({ scope: 'all', chapter: 'scenarios', step: 0 });
    expect(positionOf(p)).toMatchObject({
      n: 1,
      m: 3,
      chapterN: 1,
      chapterM: SCOPES.all.length,
      first: true,
    });
  });

  it('moves through a chapter, then finishes it and opens the next one in the scope', () => {
    let p = start(INITIAL, 'quick');
    p = next(next(p));
    expect(positionOf(p)).toMatchObject({ n: 3, m: 3 });
    p = next(p);
    // The quick scope goes from Scenarios straight to the S2 case
    expect(p).toMatchObject({ chapter: 's2', step: 0, completed: ['scenarios'] });
  });

  it('goes back across chapters, and nowhere before the first step', () => {
    expect(back(start(INITIAL, 'quick'))).toEqual(start(INITIAL, 'quick'));
    const p = back(at('s2', 0));
    expect(p).toMatchObject({ chapter: 'scenarios', step: chapterById('scenarios')!.steps.length - 1 });
  });

  it('skips a chapter without finishing it', () => {
    const p = skipChapter(at('s2', 1));
    expect(p).toMatchObject({ chapter: 's8', step: 0, completed: [] });
  });

  it('ends after the last step of the scope, every chapter finished and the welcome no longer due', () => {
    const last = chapterById('evaluation')!;
    const p = next(at('evaluation', last.steps.length - 1, { completed: ['scenarios', 's2', 's8', 's20'] }));
    expect(p).toMatchObject({ chapter: null, step: 0, dismissed: true });
    expect(p.completed).toEqual(['scenarios', 's2', 's8', 's20', 'evaluation']);
    expect(positionOf(p)).toBeUndefined();
    // Skipping the last chapter ends the guide too, leaving it unfinished
    expect(skipChapter(at('evaluation'))).toMatchObject({ chapter: null, completed: [] });
  });

  it('opens a picked chapter in the current scope when it has it, among all sections otherwise', () => {
    expect(goToChapter(at('scenarios'), 's8')).toMatchObject({ scope: 'quick', chapter: 's8', step: 0 });
    expect(goToChapter(at('scenarios'), 'health')).toMatchObject({ scope: 'all', chapter: 'health' });
    expect(goToChapter(at('scenarios'), 'nowhere')).toEqual(at('scenarios'));
  });

  it('keeps a stored step inside its chapter', () => {
    expect(positionOf(at('s20', 9))).toMatchObject({ n: 2, m: 2 });
    // A chapter outside the scope is no position
    expect(positionOf(at('health'))).toBeUndefined();
  });

  it('reads only progress of its own version and shape', () => {
    expect(isProgress(INITIAL)).toBe(true);
    expect(isProgress(at('s8', 2))).toBe(true);
    expect(isProgress({ ...INITIAL, version: 2 })).toBe(false);
    expect(isProgress({ ...INITIAL, scope: 'everything' })).toBe(false);
    expect(isProgress({ ...INITIAL, chapter: 'health' })).toBe(false);
    expect(isProgress({ ...INITIAL, step: -1 })).toBe(false);
    expect(isProgress({ ...INITIAL, completed: [1] })).toBe(false);
    expect(isProgress('{}')).toBe(false);
    expect(isProgress(null)).toBe(false);
  });
});
