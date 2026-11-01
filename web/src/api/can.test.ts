import { describe, expect, it } from 'vitest';
import { demoUserFor } from '@/demo';
import { readOnlyDemo, resolveCan, scenariosHidden } from './can';
import type { Me } from './types';

const me = (over: Partial<Me> = {}): Me => ({ username: 'u', operator: false, approver: false, ...over });

describe('resolveCan', () => {
  it('takes what the server answers in `can`', () => {
    const demo = me({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: false, scenarios: false },
    });
    expect(resolveCan(demo)).toEqual({ operate: true, approve: true, configure: false, scenarios: false });
  });

  it('derives every power from the operator and approver flags when the server sends no `can`', () => {
    expect(resolveCan(me({ operator: true, approver: true }))).toEqual({
      operate: true,
      approve: true,
      configure: true,
      scenarios: true,
    });
    expect(resolveCan(me({ operator: true }))).toEqual({
      operate: true,
      approve: false,
      configure: false,
      scenarios: true,
    });
    expect(resolveCan(me())).toEqual({ operate: false, approve: false, configure: false, scenarios: false });
  });

  it('derives only what a partial `can` leaves out', () => {
    const partial = me({ operator: true, approver: true, can: { configure: false } });
    expect(resolveCan(partial)).toEqual({ operate: true, approve: true, configure: false, scenarios: true });
  });

  it('lets nobody who is not signed in do anything', () => {
    expect(resolveCan(null)).toEqual({ operate: false, approve: false, configure: false, scenarios: false });
    expect(resolveCan(undefined)).toEqual({
      operate: false,
      approve: false,
      configure: false,
      scenarios: false,
    });
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
  it('signs "Try the demo" in as the demo role with ?as=demo, and as the approver otherwise', () => {
    expect(demoUserFor('?as=demo').username).toBe('demo');
    expect(demoUserFor('').username).toBe('approver');
    expect(demoUserFor('?as=other').username).toBe('approver');
    expect(demoUserFor('?x=1&as=demo').username).toBe('demo');
  });
});
