import { afterEach, describe, expect, it } from 'vitest';
import { normalisedSearch } from '@/env/mode';
import { enterTrialPage, takeTrialVisit, TRIAL_VISITED_KEY } from './visit';

afterEach(() => {
  sessionStorage.clear();
  window.history.replaceState(null, '', '/');
});

describe("the tab's memory of the trial", () => {
  it('marks the tab on a trial page, and a live page takes the mark once', () => {
    window.history.replaceState(null, '', '/shutter/?trial#/scenarios');
    enterTrialPage();
    expect(sessionStorage.getItem(TRIAL_VISITED_KEY)).toBe('1');
    expect(document.documentElement.dataset.shutterEnv).toBe('trial');
    expect(takeTrialVisit()).toBe(true);
    expect(takeTrialVisit()).toBe(false);
  });

  it('turns ?trial=tour and ?trial=engineer into ?trial after start, keeping the rest of the address', () => {
    expect(normalisedSearch('?trial=tour')).toBe('?trial');
    expect(normalisedSearch('?trial=engineer&as=judge')).toBe('?trial&as=judge');
    expect(normalisedSearch('?as=demo&trial=tour&detail=technical')).toBe('?as=demo&trial&detail=technical');
    expect(normalisedSearch('?trial')).toBe('?trial');
    window.history.replaceState({ idx: 3 }, '', '/shutter/?trial=tour&as=operator#/cases');
    enterTrialPage();
    expect(window.location.search).toBe('?trial&as=operator');
    expect(window.location.hash).toBe('#/cases');
    // React Router's own state survives
    expect(window.history.state).toEqual({ idx: 3 });
  });

  it("leaves ?trial after the judges' path so a reload does not take it again, and the page env/mode.ts opened", () => {
    // env/mode.ts has already set the page at load, before the router read it (mode.test.ts, startAddress)
    window.history.replaceState({ idx: 0 }, '', '/shutter/?trial=judge#/scenarios?mode=rules');
    enterTrialPage();
    expect(window.location.search).toBe('?trial');
    expect(window.location.hash).toBe('#/scenarios?mode=rules');
    expect(window.history.state).toEqual({ idx: 0 });
    // The start sets no page of its own: the address is rewritten once, at load
    window.history.replaceState({ idx: 1 }, '', '/shutter/?trial=judge#/home');
    enterTrialPage();
    expect(window.location.hash).toBe('#/home');
  });
});
