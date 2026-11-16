import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import catalogue from '../../../../knowledge/catalogue/catalogue.json';
import {
  alternativesOf,
  askedWords,
  entryAtReceivers,
  hasNoRecoveryApi,
  limitsFor,
  patternWords,
  stampLine,
  type AtReceiver,
  type CatalogueEntry,
} from './model';

const entry = (id: string) => (catalogue as unknown as CatalogueEntry[]).find((e) => e.id === id)!;

const bed: SiteReceiver = {
  name: 'Beds Out',
  system: 'the bed manager',
  category: 'current_state',
  tier: 2,
  api: { base: '/x' },
  features: { conditional_writes: true, receipts: true, history: true, dry_run: true },
};
const pas: SiteReceiver = { ...bed, name: 'Records Out', category: 'history_of_record' };
const profile = (over: Partial<SiteProfile> = {}): SiteProfile => ({
  receivers: [bed, pas],
  policy: { '2': { single: 'automatic', ordered: 'approval', interleaved: 'board' } },
  ...over,
});

const row = (
  receiver: string,
  outcome: string,
  outcomeRef = 'preferred',
  extra: Partial<AtReceiver> = {},
): AtReceiver => ({
  receiver,
  kind: '',
  category: 'current_state',
  decides: 'policy',
  outcome,
  outcomeRef,
  whenOtherSource: [],
  ...extra,
});

describe("an entry at each receiver, in words, from the route's rows", () => {
  it('groups receivers with the same words, and names who releases a write at their tier', () => {
    const p = profile();
    const e2 = entryAtReceivers(
      { ...entry('E2'), atReceivers: [row('Beds Out', 'resend'), row('Records Out', 'resend')] },
      p,
    );
    expect(e2).toHaveLength(1);
    expect(e2[0].receivers).toEqual(['Beds Out', 'Records Out']);
    expect(e2[0].lines[0]).toContain("Nobody is asked: the site's written policy releases the write");
    // With the route's holds, they follow every release by policy; with none listed, the answer is said to be silent
    const held = entryAtReceivers({ ...entry('E2'), atReceivers: [row('Beds Out', 'resend')] }, p, [
      { hold: 'site_entry', when: "one of this site's own entries stopped the case before" },
      { hold: 'origin', when: "the case's source cannot be proved (feed.prove_origin)" },
    ]);
    expect(held[0].lines[0]).toContain(
      "after the gate and the dry run, unless one of this site's own entries stopped the case before or the case's source cannot be proved (feed.prove_origin): then an approver releases it.",
    );
    expect(e2[0].lines[0]).toContain("which this install's answer does not list");
    const e1 = entryAtReceivers(
      {
        ...entry('E1'),
        atReceivers: [row('Beds Out', 'none'), row('Records Out', 'correct_history', 'alternative:1')],
      },
      p,
    );
    expect(e1.map((g) => g.receivers)).toEqual([['Beds Out'], ['Records Out']]);
    expect(e1[1].lines[0]).toContain('a correction of the history by a person (its alternative 1)');
  });

  it("puts what depends on the case's other source first, then what applies otherwise", () => {
    const at = entryAtReceivers(
      {
        ...entry('E7'),
        atReceivers: [
          row('Beds Out', 'escalate', 'preferred', {
            decides: 'board',
            whenOtherSource: [
              {
                flag: 'authoritative_source',
                otherSource: 'PAS',
                decides: 'board',
                outcome: 'none',
                outcomeRef: 'alternative:1',
              },
            ],
          }),
        ],
      },
      profile(),
    );
    expect(at[0].lines[0]).toMatch(
      /^When the other system sending at the same time is PAS: closed, nothing sent \(its alternative 1\)\./,
    );
    expect(at[0].lines[1]).toMatch(/^Otherwise: a person\./);
  });

  it('leaves out orders and results and FHIR receivers, which the part says once', () => {
    const at = entryAtReceivers(
      {
        ...entry('E2'),
        atReceivers: [
          row('Lab', 'resend', 'preferred', { category: 'orders_results' }),
          row('Ward FHIR', 'resend', 'preferred', { kind: 'fhir_r4' }),
        ],
      },
      profile(),
    );
    expect(at).toEqual([]);
  });

  it('leaves out a receiver with no recovery API: no write is offered there, so the part says once that a person decides', () => {
    const old: SiteReceiver = {
      name: 'Lab Old',
      system: 'the old lab system',
      category: 'current_state',
      tier: 2,
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    };
    const p = profile({ receivers: [bed, old] });
    const at = entryAtReceivers(
      { ...entry('E2'), atReceivers: [row('Beds Out', 'resend'), row('Lab Old', 'resend')] },
      p,
    );
    expect(at.map((g) => g.receivers)).toEqual([['Beds Out']]);
  });

  it('lists the alternatives as the catalogue writes them', () => {
    expect(alternativesOf(entry('E1'))[0]).toBe(
      'Alternative 1, a correction of the history by a person: where history policy: correct.',
    );
    expect(alternativesOf(entry('E3'))[0]).toContain("the board's or a person's choice");
  });
});

describe('the words', () => {
  it("says a policy of board convenes the board before the entry's outcome is read", () => {
    const board =
      "The board of agents settles the case, as the site's policy for this tier asks; any write it proposes waits for a person.";
    for (const outcome of ['none', 'resend', 'correct_history']) {
      expect(askedWords(outcome, 'board', 'policy')).toBe(board);
      expect(askedWords(outcome, 'board', 'policy')).not.toContain('Nobody is asked');
    }
  });

  it("says a closure waits for a person when one of the site's own entries stopped the case before", () => {
    for (const outcome of ['none', 'reconcile'])
      expect(askedWords(outcome, 'approval', 'policy')).toBe(
        "Nobody is asked: the case closes once the receiver is read again and agrees, unless one of this site's own entries stopped the case before: then a person closes it.",
      );
  });

  it('writes a pattern in the words the core gives a site entry', () => {
    expect(patternWords(entry('E6').pattern)).toBe(
      'When a message fails, is rejected or gets no answer, and encounter state is discharged',
    );
    expect(patternWords({ event: 'admit', delivery: 'failed' })).toBe('When an admission fails');
  });

  it('knows a receiver with no recovery API as the core does', () => {
    expect(hasNoRecoveryApi(bed)).toBe(false);
    expect(hasNoRecoveryApi({ ...bed, api: undefined })).toBe(true);
    expect(hasNoRecoveryApi({ name: 'Old', tier: 1 })).toBe(false);
    expect(hasNoRecoveryApi({ name: 'Lab', tier: 3, category: 'orders_results' })).toBe(true);
  });

  it('lists shadow mode as a limit until recovery is enabled', () => {
    expect(limitsFor(profile()).map((l) => l.title)).toContain('Shadow mode');
    expect(limitsFor(profile({ recovery: { mode: 'enabled' } })).map((l) => l.title)).not.toContain(
      'Shadow mode',
    );
  });

  it('stamps the trial as sample data', () => {
    const s = {
      trial: true,
      profileVersion: 3,
      saved: '',
      catalogueVersion: 'E1@5',
      gatePolicy: '2026-11-07.1',
      release: '1.4.8',
      exportedAt: '15 Nov 2026, 23:50 GMT',
    };
    expect(stampLine(s)).toBe(
      'Trial (sample data) · Site profile version 3 · catalogue E1@5 · gate policy 2026-11-07.1 · release 1.4.8 · exported 15 Nov 2026, 23:50 GMT',
    );
    expect(stampLine({ ...s, trial: false })).not.toContain('Trial');
  });
});
