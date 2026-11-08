import { afterEach, describe, expect, it } from 'vitest';
import {
  envFrom,
  JUDGE_PATH_HASH,
  liveHref,
  normalisedSearch,
  pageEnv,
  rememberTrialRole,
  startAddress,
  TRIAL_ROLE_KEY,
  trialHref,
  trialUser,
} from './mode';

describe('envFrom', () => {
  it('is the live system with nothing in the address', () => {
    expect(envFrom('', false)).toEqual({
      trial: false,
      demoBuild: false,
      canLeave: false,
      role: 'approver',
      openGuide: false,
      judgePath: false,
      detail: null,
    });
  });

  it('is the trial with ?trial in the address, in any form, and the trial can be left', () => {
    for (const search of ['?trial', '?trial=1', '?x=1&trial', 'trial'])
      expect(envFrom(search, false)).toMatchObject({ trial: true, canLeave: true, openGuide: false });
  });

  it('opens the quick tour with ?trial=tour and the engineers tour with ?trial=engineer', () => {
    expect(envFrom('?trial=tour', false).openGuide).toBe('quick');
    expect(envFrom('?trial=engineer', false).openGuide).toBe('engineer');
    expect(envFrom('?trial=other', false).openGuide).toBe(false);
  });

  it("takes the judges' path with ?trial=judge, live or on the demo build, and opens no tour", () => {
    expect(envFrom('?trial=judge', false)).toMatchObject({ trial: true, judgePath: true, openGuide: false });
    expect(envFrom('?trial=judge', true).judgePath).toBe(true);
    expect(envFrom('?trial', true).judgePath).toBe(false);
    expect(envFrom('?as=judge', true).judgePath).toBe(false);
  });

  it('picks the starting role with ?as=, and the approver for an unknown one', () => {
    expect(envFrom('?trial&as=operator', false).role).toBe('operator');
    expect(envFrom('?as=demo', true).role).toBe('demo');
    expect(envFrom('?as=judge', true).role).toBe('judge');
    expect(envFrom('?as=root', true).role).toBe('approver');
    expect(envFrom('', true).role).toBe('approver');
  });

  it('reads the Detail level from ?detail=, live and in the trial', () => {
    expect(envFrom('?detail=technical', false).detail).toBe('technical');
    expect(envFrom('?trial&detail=plain', false).detail).toBe('plain');
    expect(envFrom('?detail=everything', false).detail).toBeNull();
  });

  it('makes the demo build always the trial, with no live system to leave for', () => {
    for (const search of ['', '?trial', '?as=demo'])
      expect(envFrom(search, true)).toMatchObject({ trial: true, demoBuild: true, canLeave: false });
  });
});

describe('the addresses of the trial and of the live system', () => {
  afterEach(() => window.history.replaceState(null, '', '/'));

  it('keep the path and the page, and add or drop only the query', () => {
    window.history.replaceState(null, '', '/shutter/?as=demo#/cases/C-000002');
    expect(trialHref()).toBe('/shutter/?trial#/home');
    expect(trialHref('#/cases/C-000002')).toBe('/shutter/?trial#/cases/C-000002');
    expect(trialHref('/evaluation', { tour: true })).toBe('/shutter/?trial=tour#/evaluation');
    expect(trialHref('#/scenarios', { tour: 'engineer', as: 'operator' })).toBe(
      '/shutter/?trial=engineer&as=operator#/scenarios',
    );
    expect(liveHref()).toBe('/shutter/#/home');
    expect(liveHref('#/cases')).toBe('/shutter/#/cases');
  });

  it("sign the trial's roles in as the mock's users of the same name", () => {
    expect(trialUser('demo')).toEqual({ username: 'demo', password: 'shutter' });
    expect(trialUser(envFrom('?as=other', true).role).username).toBe('approver');
  });
});

describe("the judges' path's address", () => {
  it('opens Scenarios in Rules only mode, whatever page it named, and a reload of it is a plain trial page', () => {
    expect(JUDGE_PATH_HASH).toBe('#/scenarios?mode=rules');
    expect(startAddress('?trial=judge', '')).toEqual({ search: '?trial', hash: '#/scenarios?mode=rules' });
    expect(startAddress('?trial=judge&as=operator', '#/cases/C-000008')).toEqual({
      search: '?trial&as=operator',
      hash: '#/scenarios?mode=rules',
    });
    expect(normalisedSearch('?detail=technical&trial=judge')).toBe('?detail=technical&trial');
    // What the reload loads: no judges' path, and the page it is on
    expect(envFrom('?trial', true).judgePath).toBe(false);
    expect(startAddress('?trial', '#/scenarios?mode=rules')).toEqual({
      search: '?trial',
      hash: '#/scenarios?mode=rules',
    });
    expect(startAddress('?trial=tour', '#/cases')).toEqual({ search: '?trial', hash: '#/cases' });
  });
});

describe("the page's environment", () => {
  afterEach(() => sessionStorage.clear());

  it('signs a reloaded trial in as the role the tab chose, unless the address names one', () => {
    expect(pageEnv('?trial', false).role).toBe('approver');
    rememberTrialRole('operator');
    expect(sessionStorage.getItem(TRIAL_ROLE_KEY)).toBe('operator');
    expect(pageEnv('?trial', false).role).toBe('operator');
    expect(pageEnv('', true).role).toBe('operator');
    expect(pageEnv('?trial&as=judge', false).role).toBe('judge');
    // A live page has no trial role to keep
    expect(pageEnv('', false).role).toBe('approver');
  });

  it('is the trial on a build IRIS serves when the address says ?trial', () => {
    expect(pageEnv('?trial', false)).toMatchObject({ trial: true, canLeave: true, demoBuild: false });
    expect(pageEnv('', false)).toMatchObject({ trial: false, canLeave: false });
  });
});
