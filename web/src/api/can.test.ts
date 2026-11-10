import { describe, expect, it } from 'vitest';
import { envFrom, trialUser } from '@/env/mode';
import { readOnlyDemo, resolveCan, scenariosHidden, showsRoleBadges } from './can';
import type { Me } from './types';

const me = (over: Partial<Me> = {}): Me => ({ username: 'u', operator: false, approver: false, ...over });

describe('resolveCan', () => {
  it('takes what the server answers in `can`', () => {
    const demo = me({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: false, scenarios: false },
    });
    expect(resolveCan(demo)).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: false,
      reset: false,
      liveAgents: false,
    });
  });

  it('derives every power from the operator and approver flags when the server sends no `can`', () => {
    expect(resolveCan(me({ operator: true, approver: true }))).toEqual({
      operate: true,
      approve: true,
      configure: true,
      scenarios: true,
      reset: true,
      liveAgents: false,
    });
    expect(resolveCan(me({ operator: true }))).toEqual({
      operate: true,
      approve: false,
      configure: false,
      scenarios: true,
      reset: true,
      liveAgents: false,
    });
    expect(resolveCan(me())).toEqual({
      operate: false,
      approve: false,
      configure: false,
      scenarios: false,
      reset: false,
      liveAgents: false,
    });
  });

  it('derives only what a partial `can` leaves out', () => {
    const partial = me({ operator: true, approver: true, can: { configure: false } });
    expect(resolveCan(partial)).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: true,
      reset: true,
      liveAgents: false,
    });
  });

  it('takes the right to spend the model budget from the server, and never derives it', () => {
    const judge = me({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: false, scenarios: false, liveAgents: true },
    });
    expect(resolveCan(judge).liveAgents).toBe(true);
    // A server older than the judges' live agents has no route to convene the board
    expect(resolveCan(me({ operator: true, approver: true })).liveAgents).toBe(false);
  });

  it('lets nobody who is not signed in do anything', () => {
    expect(resolveCan(null)).toEqual({
      operate: false,
      approve: false,
      configure: false,
      scenarios: false,
      reset: false,
      liveAgents: false,
    });
    expect(resolveCan(undefined)).toEqual({
      operate: false,
      approve: false,
      configure: false,
      scenarios: false,
      reset: false,
      liveAgents: false,
    });
  });

  it("splits running from resetting (1.4.3): a judge runs and does not reset; an older server's one right is both", () => {
    const judge = resolveCan(
      me({
        operator: true,
        approver: true,
        can: {
          operate: true,
          approve: true,
          configure: false,
          scenarios: true,
          reset: false,
          liveAgents: true,
        },
      }),
    );
    expect([judge.scenarios, judge.reset]).toEqual([true, false]);
    expect(scenariosHidden(judge)).toBe(false);
    const older = resolveCan(me({ operator: true, can: { operate: true, scenarios: true } }));
    expect([older.scenarios, older.reset]).toEqual([true, true]);
    const olderDemo = resolveCan(me({ operator: true, approver: true, can: { scenarios: false } }));
    expect([olderDemo.scenarios, olderDemo.reset]).toEqual([false, false]);
  });
});

describe('the role badges', () => {
  it('are shown for the operator and approver flags of GET /me, so a reason never asks for a role the menu shows', () => {
    expect(showsRoleBadges(me({ operator: true, approver: true }))).toBe(true);
    expect(showsRoleBadges(me({ operator: true }))).toBe(true);
    expect(showsRoleBadges(me())).toBe(false);
    expect(showsRoleBadges(null)).toBe(false);
  });
});

describe('what the public demo hides', () => {
  const demo = resolveCan(
    me({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: false, scenarios: false },
    }),
  );

  it('hides the scenario controls and the saves from the demo role only', () => {
    expect(scenariosHidden(demo)).toBe(true);
    expect(readOnlyDemo(demo)).toBe(true);
  });

  it('keeps them for an approver, an operator and a server that sends no `can`', () => {
    const approver = resolveCan(me({ operator: true, approver: true }));
    const operator = resolveCan(me({ operator: true }));
    const reader = resolveCan(me());
    for (const can of [approver, operator, reader]) {
      expect(scenariosHidden(can)).toBe(false);
      expect(readOnlyDemo(can)).toBe(false);
    }
  });
});

describe('the mock switch', () => {
  it('signs the trial in as the demo role with ?as=demo, and as the approver otherwise', () => {
    const user = (search: string) => trialUser(envFrom(search, true).role);
    expect(user('?as=demo').username).toBe('demo');
    expect(user('').username).toBe('approver');
    expect(user('?as=other').username).toBe('approver');
    expect(user('?x=1&as=demo').username).toBe('demo');
  });
});
