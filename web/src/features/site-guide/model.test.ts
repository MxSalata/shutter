import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import catalogue from '../../../../knowledge/catalogue/catalogue.json';
import {
  alternativesHere,
  entryAtReceivers,
  hasNoRecoveryApi,
  limitsFor,
  patternWords,
  receiverFacts,
  settle,
  stampLine,
  whenHolds,
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

describe('the outcome a site selects, as Shutter.Catalogue.Matcher settles it', () => {
  it("keeps E1's preferred outcome at a current state receiver and takes its alternative at a history of record", () => {
    const p = profile();
    expect(settle(entry('E1'), receiverFacts(bed, p), p)).toEqual([{ outcome: 'none', ref: 'preferred' }]);
    expect(settle(entry('E1'), receiverFacts(pas, p), p)).toEqual([
      { outcome: 'correct_history', ref: 'alternative:1' },
    ]);
  });

  it("reads the receiver's own history policy before its category, and the site-wide one only with neither", () => {
    const p = profile({ history_policy: 'correct' });
    expect(settle(entry('E6'), receiverFacts({ ...pas, history_policy: 'current' }, p), p)[0].outcome).toBe(
      'none',
    );
    expect(settle(entry('E6'), receiverFacts({ ...bed, category: undefined }, p), p)[0].outcome).toBe(
      'correct_history',
    );
    // A FHIR receiver is current whatever else is said
    const fhir = { ...pas, fhir: { base: '/fhir' } } as unknown as SiteReceiver;
    expect(receiverFacts(fhir, p).history_policy).toBe('current');
  });

  it('never takes an alternative marked always: that is the board’s choice', () => {
    const p = profile();
    expect(settle(entry('E3'), receiverFacts(bed, p), p)).toEqual([
      { outcome: 'reconcile', ref: 'preferred' },
    ]);
    expect(whenHolds('always', receiverFacts(bed, p), p)).toBe(true);
  });

  it("states E7's alternative as a condition of the case when the site names an authoritative source", () => {
    const none = profile();
    expect(settle(entry('E7'), receiverFacts(bed, none), none)).toEqual([
      { outcome: 'escalate', ref: 'preferred' },
    ]);
    const named = profile({ authoritative_source: 'PAS' });
    expect(settle(entry('E7'), receiverFacts(bed, named), named)).toEqual([
      {
        outcome: 'none',
        ref: 'alternative:1',
        condition: 'the other system sending at the same time is PAS',
      },
      { outcome: 'escalate', ref: 'preferred' },
    ]);
  });

  it("compares a site-wide flag as written: E8's with_approval never holds, since a profile says allowed or forbidden", () => {
    const p = profile({ unconditional_resend: 'allowed' });
    expect(settle(entry('E8'), receiverFacts(bed, p), p)).toEqual([
      { outcome: 'escalate', ref: 'preferred' },
    ]);
    expect(whenHolds('unconditional_resend: with_approval', receiverFacts(bed, p), p)).toBe(false);
    expect(whenHolds('unconditional_resend: allowed', receiverFacts(bed, p), p)).toBe(true);
    expect(whenHolds('unconditional_resend:', receiverFacts(bed, p), p)).toBe(false);
  });

  it('groups receivers with the same words, and names who releases a write at their tier', () => {
    const p = profile();
    const e2 = entryAtReceivers(entry('E2'), p);
    expect(e2).toHaveLength(1);
    expect(e2[0].receivers).toEqual(['Beds Out', 'Records Out']);
    expect(e2[0].lines[0]).toContain("Nobody is asked: the site's written policy releases the write");
    const e1 = entryAtReceivers(entry('E1'), p);
    expect(e1.map((g) => g.receivers)).toEqual([['Beds Out'], ['Records Out']]);
    expect(e1[1].lines[0]).toContain('a correction of the history by a person (its alternative 1)');
  });

  it('says where each alternative is allowed here', () => {
    const p = profile();
    expect(alternativesHere(entry('E1'), p)[0]).toBe(
      'Alternative 1, a correction of the history by a person: only where history policy: correct, which holds at Records Out.',
    );
    expect(alternativesHere(entry('E8'), p)[0]).toContain('which does not hold at this site');
    expect(alternativesHere(entry('E3'), p)[0]).toContain("the board's or a person's choice");
  });
});

describe('the words', () => {
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
