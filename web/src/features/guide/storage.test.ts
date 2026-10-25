import { afterEach, describe, expect, it, vi } from 'vitest';
import { INITIAL } from './controller';
import { forgetProgress, GUIDE_KEY, loadProgress, saveProgress } from './storage';

afterEach(() => {
  vi.restoreAllMocks();
  localStorage.clear();
  forgetProgress();
});

describe('the guide storage', () => {
  it('keeps the progress under its namespaced key, and nothing else', () => {
    const p = { ...INITIAL, chapter: 's8', step: 1, completed: ['scenarios'] };
    saveProgress(p);
    expect(JSON.parse(localStorage.getItem(GUIDE_KEY)!)).toEqual(p);
    expect(Object.keys(JSON.parse(localStorage.getItem(GUIDE_KEY)!)).sort()).toEqual(
      ['chapter', 'completed', 'dismissed', 'scope', 'step', 'version'].sort(),
    );
    expect(loadProgress()).toEqual(p);
  });

  it('starts afresh from a damaged or older value', () => {
    localStorage.setItem(GUIDE_KEY, '{not json');
    expect(loadProgress()).toEqual(INITIAL);
    localStorage.setItem(GUIDE_KEY, JSON.stringify({ ...INITIAL, version: 0 }));
    expect(loadProgress()).toEqual(INITIAL);
  });

  it('falls back to memory when storage refuses, and forgets it on sign-out', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError');
    });
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError');
    });
    const p = { ...INITIAL, dismissed: true };
    expect(() => saveProgress(p)).not.toThrow();
    expect(loadProgress()).toEqual(p);
    forgetProgress();
    expect(loadProgress()).toEqual(INITIAL);
  });
});
