import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { coreTable } from '@/test/coreTables';
import { approvalText, effectsOf, lessStrict, type EffectId, type EffectLine } from './effects';
import { blankReceiver } from './setupStore';

const POLICY = {
  '1': { single: 'approval', ordered: 'approval', interleaved: 'board' },
  '2': { single: 'approval', ordered: 'approval', interleaved: 'board' },
  '3': { single: 'approval', ordered: 'per_chain', interleaved: 'board' },
};
const profile = (more: Partial<SiteProfile> = {}): SiteProfile => ({
  receivers: [],
  policy: POLICY,
  ...more,
});
const receiver = (more: Partial<SiteReceiver> = {}): SiteReceiver => ({ name: 'R', tier: 2, ...more });
const rank = (p: SiteProfile, r: SiteReceiver, id: EffectId) =>
  effectsOf(p, r).find((l) => l.id === id)!.rank;
const text = (p: SiteProfile, r: SiteReceiver, id: EffectId) =>
  effectsOf(p, r).find((l) => l.id === id)!.text;

describe('What Shutter will do here', () => {
  it("reads the kind's default, a receiver's override and an older profile's site-wide policy as the server does", () => {
    const rows: [string, SiteProfile, SiteReceiver, 0 | 1, RegExp][] = [
      ['no kind: current state', profile(), receiver(), 0, /closes, no write/],
      ['current state', profile(), receiver({ category: 'current_state' }), 0, /closes, no write/],
      ['history of record', profile(), receiver({ category: 'history_of_record' }), 1, /asks a person/],
      ['orders and results', profile(), receiver({ category: 'orders_results' }), 1, /goes to a person/],
      [
        'its own policy over its kind',
        profile(),
        receiver({ category: 'history_of_record', history_policy: 'current' }),
        0,
        /closes, no write/,
      ],
      [
        'correct on a current state receiver',
        profile(),
        receiver({ category: 'current_state', history_policy: 'correct' }),
        1,
        /asks a person/,
      ],
      ['no kind, site-wide correct', profile({ history_policy: 'correct' }), receiver(), 1, /asks a person/],
      [
        'a kind beats the site-wide policy',
        profile({ history_policy: 'correct' }),
        receiver({ category: 'current_state' }),
        0,
        /closes, no write/,
      ],
      [
        'a FHIR receiver stops for a person',
        profile({ history_policy: 'correct' }),
        receiver({ fhir: { base: '/fhir' } } as Partial<SiteReceiver>),
        1,
        /stops for a person/,
      ],
    ];
    for (const [name, p, r, expected, words] of rows) {
      expect([name, rank(p, r, 'overtaken')]).toEqual([name, expected]);
      expect(text(p, r, 'overtaken')).toMatch(words);
    }
  });

  it("reads who approves from the policy row of the tier, the draft's included", () => {
    expect(rank(profile(), receiver({ tier: 2 }), 'approval.single')).toBe(1);
    const automatic = profile({ policy: { ...POLICY, '2': { ...POLICY['2'], single: 'automatic' } } });
    expect(rank(automatic, receiver({ tier: 2 }), 'approval.single')).toBe(0);
    expect(rank(automatic, receiver({ tier: 2 }), 'approval.ordered')).toBe(1);
    // Tier 3 made automatic is read as it is written: nothing is safest by nature
    const tier3 = profile({ policy: { ...POLICY, '3': { single: 'automatic' } } });
    expect(rank(tier3, receiver({ tier: 3 }), 'approval.single')).toBe(0);
    // A kind the row does not set needs one approval
    expect(rank(tier3, receiver({ tier: 3 }), 'approval.interleaved')).toBe(1);
    expect(approvalText(tier3, receiver({ tier: 3 }))).toBe(
      'At tier 3: single failures, automatic; ordered chains, one approval; interleaved chains, one approval.',
    );
    // A tier that is not answered names nobody, and is compared with nothing
    const unanswered = { name: 'New' } as unknown as SiteReceiver;
    expect(rank(profile(), unanswered, 'approval.single')).toBeNull();
    expect(approvalText(profile(), unanswered)).toBe('The tier is not answered, so nobody is named yet.');
  });

  it('says a receiver that starts here is never written to', () => {
    const fresh = blankReceiver();
    expect(fresh.api).toBeUndefined();
    expect(fresh.features).toEqual({
      conditional_writes: false,
      receipts: false,
      history: false,
      dry_run: false,
    });
    expect(rank(profile(), fresh, 'case_write')).toBe(1);
    expect(text(profile(), fresh, 'case_write')).toMatch(/the gate blocks every write/);
    expect(rank(profile(), fresh, 'engine_resend')).toBe(1);
  });

  it('reads a write as possible on the defaults, with all four features, and never at orders and results', () => {
    expect(rank(profile(), receiver(), 'case_write')).toBe(0);
    const all = { conditional_writes: true, receipts: true, history: true, dry_run: true };
    expect(rank(profile(), receiver({ features: all }), 'case_write')).toBe(0);
    expect(rank(profile(), receiver({ features: { ...all, dry_run: false } }), 'case_write')).toBe(1);
    expect(rank(profile(), receiver({ features: all, category: 'orders_results' }), 'case_write')).toBe(1);
    expect(rank(profile(), receiver({ engine_resend: true }), 'engine_resend')).toBe(0);
    expect(rank(profile(), receiver(), 'mode')).toBe(1);
    expect(rank(profile({ recovery: { mode: 'enabled' } }), receiver(), 'mode')).toBe(0);
  });

  it('finds the line a change makes less strict, and nothing where a line has no answer on one side', () => {
    const strict = effectsOf(profile(), receiver({ category: 'history_of_record', tier: 3 }));
    const looser = effectsOf(profile(), receiver({ category: 'current_state', tier: 3 }));
    expect(lessStrict(strict, looser)?.id).toBe('overtaken');
    expect(lessStrict(looser, strict)).toBeNull();
    expect(lessStrict(strict, strict)).toBeNull();
    // A receiver that is not in the other profile is compared with nothing
    expect(lessStrict(null, looser)).toBeNull();
    const automatic = profile({ policy: { ...POLICY, '1': { single: 'automatic' } } });
    expect(
      lessStrict(strict, effectsOf(automatic, receiver({ category: 'history_of_record', tier: 1 })))?.id,
    ).toBe('approval.single');
    // An unanswered tier gives no line to be less strict than
    const unanswered = effectsOf(profile(), {
      name: 'New',
      category: 'history_of_record',
    } as unknown as SiteReceiver);
    expect(
      lessStrict(unanswered, effectsOf(automatic, receiver({ category: 'history_of_record', tier: 1 }))),
    ).toBeNull();
    const writes = effectsOf(profile(), receiver({ category: 'history_of_record' }));
    const blocked = effectsOf(
      profile(),
      receiver({ category: 'history_of_record', ...blankReceiver(), name: 'R' }),
    );
    expect(lessStrict(blocked, writes)?.id).toBe('case_write');
  });

  it("compares who approves by the policy's own values, which are not points on one scale", () => {
    const lines = (policy: string): EffectLine[] => [
      { id: 'approval.ordered', label: '', text: '', rank: policy === 'automatic' ? 0 : 1, policy },
    ];
    for (const [was, now] of [
      ['per_chain', 'approval'],
      ['approval', 'per_chain'],
      ['approval', 'board'],
      ['board', 'approval'],
      ['per_chain', 'board'],
      ['approval', 'automatic'],
      ['person', 'automatic'],
    ])
      expect([was, now, lessStrict(lines(was), lines(now))?.id]).toEqual([was, now, 'approval.ordered']);
    for (const [was, now] of [
      ['automatic', 'per_chain'],
      ['automatic', 'board'],
      ['board', 'board'],
    ])
      expect([was, now, lessStrict(lines(was), lines(now))]).toEqual([was, now, null]);
  });

  it("refuses the review's case: tier 3 to tier 2 on the core's Base() policy, with no line at automatic", () => {
    const three = effectsOf(profile(), receiver({ name: 'Lab Out', tier: 3 }));
    const two = effectsOf(profile(), receiver({ name: 'Lab Out', tier: 2 }));
    expect(three.find((l) => l.id === 'approval.ordered')).toMatchObject({ rank: 1, policy: 'per_chain' });
    expect(two.find((l) => l.id === 'approval.ordered')).toMatchObject({ rank: 1, policy: 'approval' });
    expect(lessStrict(three, two)?.id).toBe('approval.ordered');
    expect(lessStrict(two, three)?.id).toBe('approval.ordered');
    // A site whose interleaved values differ by tier keeps board
    const mixed = profile({ policy: { ...POLICY, '2': { ...POLICY['2'], interleaved: 'approval' } } });
    expect(
      lessStrict(effectsOf(mixed, receiver({ tier: 1 })), effectsOf(mixed, receiver({ tier: 2 })))?.id,
    ).toBe('approval.interleaved');
  });
});

describe('What Shutter will do here, the table Shutter.Test.ProfileSetup runs at the server', () => {
  const rows = coreTable<{
    name: string;
    profile?: Partial<SiteProfile>;
    receiver: SiteReceiver;
    expect: Record<string, number | string>;
  }>('ProfileSetup', 'EffectRows');

  it('has the rows of the server class', () => {
    expect(rows.length).toBeGreaterThan(12);
  });

  it.each(rows.map((row) => [row.name, row] as const))('%s', (_name, row) => {
    const base: SiteProfile = {
      receivers: [],
      policy: {
        '1': { single: 'approval' },
        '2': { single: 'approval', ordered: 'approval', interleaved: 'board' },
        '3': { single: 'approval', ordered: 'per_chain' },
      },
      ...row.profile,
    };
    // An approval line by the policy's own value, as the core keeps it; every other line by its rank
    const ranks = Object.fromEntries(
      effectsOf(base, row.receiver)
        .filter((l) => l.rank !== null)
        .map((l) => [l.id, l.policy ?? l.rank]),
    );
    expect(ranks).toEqual(row.expect);
    // In the lines' own order, as the core compares them
    expect(Object.keys(ranks)).toEqual(Object.keys(row.expect));
  });
});
