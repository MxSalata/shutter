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
  stepsIn,
  welcomeDue,
  type GuideProgress,
} from './controller';
import { SCOPES } from './registry';

const at = (path: string, more: Partial<GuideProgress> = {}): GuideProgress => ({
  ...INITIAL,
  at: path,
  ...more,
});

describe('the guide controller', () => {
  it('opens the welcome only before the tour was started, finished or dismissed', () => {
    expect(welcomeDue(INITIAL)).toBe(true);
    expect(welcomeDue({ ...INITIAL, dismissed: true })).toBe(false);
    expect(welcomeDue(at('s2/receipt'))).toBe(false);
    expect(welcomeDue({ ...INITIAL, completed: ['scenarios'] })).toBe(false);
  });

  it('counts the route, not the chapter: step 3 of 9 on the quick tour', () => {
    const p = start(INITIAL, 'quick');
    expect(positionOf(p)).toMatchObject({ path: 'scenarios/start', n: 1, m: 9, first: true, last: false });
    expect(positionOf(at('s2/decision'))).toMatchObject({ n: 3, m: 9 });
    expect(positionOf(at('evaluation/headline'))).toMatchObject({ n: 9, last: true });
    expect(positionOf(start(INITIAL, 'engineer'))).toMatchObject({ path: 's2/receipt-json', m: 6 });
    expect(positionOf(at('s2/evidence'))).toBeUndefined();
  });

  it('steps on with Next, finishing a chapter as the route leaves it, and ends after the last', () => {
    let p = at('scenarios/start');
    p = next(p);
    expect(p).toMatchObject({ at: 's2/receipt', completed: ['scenarios'] });
    p = next(p);
    expect(p).toMatchObject({ at: 's2/decision', completed: ['scenarios'] });
    const end = next(at('evaluation/headline', { completed: ['scenarios'] }));
    expect(end).toMatchObject({ at: null, dismissed: true, completed: ['scenarios', 'evaluation'] });
  });

  it('steps back across chapters, and not before the first', () => {
    expect(back(at('s2/receipt')).at).toBe('scenarios/start');
    expect(back(at('scenarios/start')).at).toBe('scenarios/start');
  });

  it('skips to the next chapter on the route, leaving this one unfinished', () => {
    // The quick tour follows the short route: S3 comes after S2, and S8 after S3
    expect(skipChapter(at('s2/receipt'))).toMatchObject({ at: 's3/receipt', completed: [] });
    expect(skipChapter(at('s3/receipt'))).toMatchObject({ at: 's8/receipt', completed: [] });
    expect(skipChapter(at('evaluation/headline'))).toMatchObject({ at: null, dismissed: true });
  });

  it('opens a chapter on the route that has it, else on every screen', () => {
    expect(goToChapter(at('s2/receipt'), 's8')).toMatchObject({ scope: 'quick', at: 's8/receipt' });
    expect(goToChapter(at('s2/receipt'), 'library')).toMatchObject({ scope: 'all', at: 'library/agents' });
    expect(goToChapter(at('s2/receipt'), 'nowhere').at).toBe('s2/receipt');
    expect(stepsIn('s2', 'quick')).toBe(3);
    expect(stepsIn('s2', 'all')).toBe(4);
    expect(stepsIn('library', 'quick')).toBe(1);
  });

  it('reads back only the progress of this version, on a route that has the step', () => {
    expect(isProgress(INITIAL)).toBe(true);
    expect(isProgress(at('s2/decision'))).toBe(true);
    expect(isProgress({ ...INITIAL, version: 1 })).toBe(false);
    expect(isProgress(at('s2/evidence'))).toBe(false);
    expect(isProgress({ ...INITIAL, scope: 'engineer', at: SCOPES.engineer[0] })).toBe(true);
    expect(isProgress({ ...INITIAL, completed: ['no-such-chapter'] })).toBe(false);
    expect(isProgress(null)).toBe(false);
  });
});
