import { afterEach, describe, expect, it, vi } from 'vitest';
import { journal } from '@/trial/journal';
import { lockNetworkForTrial, TRIAL_POLICY, TRIAL_REFUSAL, unlockForTests } from './guard';

const added = () => document.head.querySelectorAll('meta[http-equiv="Content-Security-Policy"]');

describe('the trial lock', () => {
  const original = window.fetch;
  afterEach(() => {
    window.fetch = original;
    unlockForTests();
    journal.clear();
    added().forEach((m) => m.remove());
    delete window.shutterTrial;
  });

  it('refuses a request to the API in a trial page, and counts it', async () => {
    const sent = vi.fn(() => Promise.resolve(new Response('{}')));
    window.fetch = sent;
    lockNetworkForTrial({ csp: true });
    await expect(window.fetch('/api/shutter/me')).rejects.toThrow(TRIAL_REFUSAL);
    await expect(window.fetch(new URL('/api/shutter/cases', window.location.href))).rejects.toThrow(
      TRIAL_REFUSAL,
    );
    expect(sent).not.toHaveBeenCalled();
    expect(journal.counts().refused).toBe(2);
    // Anything else, such as the page's own files, still loads
    await window.fetch('/assets/app.js');
    expect(sent).toHaveBeenCalledTimes(1);
    expect(window.shutterTrial?.journal).toBe(journal);
  });

  it("adds exactly one policy, connect-src 'none', and counts the browser's refusals", () => {
    lockNetworkForTrial({ csp: true });
    lockNetworkForTrial({ csp: true });
    expect([...added()].map((m) => m.getAttribute('content'))).toEqual([TRIAL_POLICY]);
    expect(TRIAL_POLICY).toBe("connect-src 'none'");
    document.dispatchEvent(new Event('securitypolicyviolation', { bubbles: true }));
    expect(journal.counts().violations).toBe(1);
  });

  it('adds nothing in a live page, which never calls it', () => {
    expect(added()).toHaveLength(0);
    expect(window.fetch).toBe(original);
    expect(window.shutterTrial).toBeUndefined();
  });
});
