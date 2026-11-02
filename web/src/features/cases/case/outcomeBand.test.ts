import { afterEach, describe, expect, it, vi } from 'vitest';
import { bandKind, bandStartsOpen, rememberBand } from './outcomeBand';

afterEach(() => {
  vi.restoreAllMocks();
  window.localStorage.clear();
});

describe("the Outcome band's first state", () => {
  it('sorts cases a person may act on from closed ones', () => {
    for (const state of ['awaiting_approval', 'blocked', 'escalated', 'failed', 'rehearsing'])
      expect(bandKind({ state, disposition: 'resend' } as never)).toBe('needs');
    expect(bandKind({ state: 'resolved', disposition: 'superseded' } as never)).toBe('closed');
    expect(bandKind({ state: 'resolved', disposition: 'handled_by_hand' } as never)).toBe('closed');
    expect(bandKind({ state: 'failed', disposition: 'abandoned' } as never)).toBe('closed');
  });

  it('opens for a case that needs a person and stays closed for a closed one, until the reader chooses', () => {
    expect(bandStartsOpen('needs')).toBe(true);
    expect(bandStartsOpen('closed')).toBe(false);
    rememberBand('closed', true);
    expect(bandStartsOpen('closed')).toBe(true);
    // Each kind keeps its own choice
    expect(bandStartsOpen('needs')).toBe(true);
    rememberBand('needs', false);
    expect(bandStartsOpen('needs')).toBe(false);
    expect(bandStartsOpen('closed')).toBe(true);
  });

  it('keeps the defaults when storage cannot be read, holds something else, or refuses a write', () => {
    window.localStorage.setItem('shutter.outcomeBand', 'not json');
    expect(bandStartsOpen('needs')).toBe(true);
    window.localStorage.setItem('shutter.outcomeBand', JSON.stringify({ closed: 'yes' }));
    expect(bandStartsOpen('closed')).toBe(false);
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('denied');
    });
    expect(bandStartsOpen('closed')).toBe(false);
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('quota');
    });
    expect(() => rememberBand('closed', true)).not.toThrow();
  });
});
