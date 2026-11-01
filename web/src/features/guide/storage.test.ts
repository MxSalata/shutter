import { afterEach, describe, expect, it, vi } from 'vitest';
import { INITIAL } from './controller';
import { forgetProgress, GUIDE_KEY, loadProgress, saveProgress } from './storage';

afterEach(() => {
  vi.restoreAllMocks();
  localStorage.clear();
  forgetProgress();
});

describe('the guide storage', () => {
  it('keeps the progress under its v2 key, and nothing else', () => {
    expect(GUIDE_KEY).toBe('shutter:guide:v2');
    const p = { ...INITIAL, scope: 'engineer' as const, at: 's8/trace', completed: ['s2'] };
    saveProgress(p);
    expect(JSON.parse(localStorage.getItem(GUIDE_KEY)!)).toEqual(p);
    expect(Object.keys(JSON.parse(localStorage.getItem(GUIDE_KEY)!)).sort()).toEqual(
      ['at', 'completed', 'dismissed', 'scope', 'version'].sort(),
    );
    expect(loadProgress()).toEqual(p);
  });

  it('starts afresh from a damaged or older value, the first guide included', () => {
    localStorage.setItem(GUIDE_KEY, '{not json');
    expect(loadProgress()).toEqual(INITIAL);
    localStorage.setItem(GUIDE_KEY, JSON.stringify({ ...INITIAL, version: 1, chapter: 's2', step: 0 }));
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
