import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { layer1WordCount } from '@/test/words';
import {
  KIND_WRITTEN,
  RECOVERY_WRITTEN,
  TIER_WRITTEN,
  kindFocus,
  recoveryFocus,
  tierFocus,
} from './askAbout';
import { newReceiver } from './profile';

/**
 * What "Ask Shutter about this" sends for the site profile's consequential questions: the answer on the page and what it
 * does, read as the page reads them, never left to the model; the question asked; the written explanation.
 */

const receiver = (patch: Partial<SiteReceiver>): SiteReceiver => ({
  ...newReceiver(),
  name: 'Records Out',
  ...patch,
});

describe("a receiver's kind", () => {
  it("names the kind and the category's own line for an overtaken failure", () => {
    const f = kindFocus(receiver({ category: 'history_of_record' }), 1);
    expect(f).toMatchObject({
      page: 'site-profile',
      id: 'site-receivers-1-category',
      title: 'What kind of system is Records Out?',
      question:
        'What does History of record mean for Records Out, and what would each other kind change? Explain each; do not recommend one.',
      answer: 'History of record',
      written: KIND_WRITTEN,
    });
    expect(f.consequence).toBe(
      'A PAS, an electronic patient record, a clinical data warehouse. Overtaken failure: asks a person to correct by hand.',
    );
  });

  it('reads an unanswered kind as the server does, and a receiver’s own history policy over its kind’s', () => {
    const unanswered = kindFocus(receiver({ category: undefined }), 0);
    expect(unanswered.answer).toBe('Not answered: read as Current state');
    expect(unanswered.consequence).toMatch(/Overtaken failure: closes, no write\.$/);
    // A receiver with no kind and no policy of its own follows the profile's deprecated site-wide answer, as the server's
    // ReceiverHistoryPolicy does; a receiver with a kind does not
    const legacy = { receivers: [], policy: {}, history_policy: 'correct' } as SiteProfile;
    expect(kindFocus(receiver({ category: undefined }), 0, legacy).consequence).toMatch(
      /asks a person to correct by hand\. \(the site-wide history policy\)$/,
    );
    expect(kindFocus(receiver({ category: 'current_state' }), 0, legacy).consequence).toMatch(
      /closes, no write\.$/,
    );
    const own = kindFocus(receiver({ category: 'current_state', history_policy: 'correct' }), 0);
    expect(own.consequence).toMatch(/asks a person to correct by hand\. \(its own history policy\)$/);
    expect(kindFocus(receiver({ category: 'odd' }), 0).answer).toBe(
      'Kept as stored: odd, read as Current state',
    );
    expect(kindFocus(receiver({ name: '  ' }), 0).title).toBe('What kind of system is this receiver?');
  });
});

describe("a receiver's tier", () => {
  it('names who releases each kind of write at that tier, as the policy is drafted', () => {
    const policy: SiteProfile['policy'] = { '3': { single: 'automatic', ordered: 'per_chain' } };
    const f = tierFocus(receiver({ tier: 3 }), 0, policy);
    expect(f).toMatchObject({
      id: 'site-receivers-0-tier',
      title: 'The tier of Records Out',
      question:
        'What does tier 3 mean for Records Out, and what would each other tier change? Explain each; do not recommend one.',
      answer: 'Tier 3, clinical safety',
      written: TIER_WRITTEN,
    });
    // A kind the policy leaves out needs one approval, as the release matrix reads it
    expect(f.consequence).toBe(
      'Who releases a write at tier 3: single failures, automatic; ordered chains, an approval per chain; interleaved chains, one approval.',
    );
  });

  it('keeps a tier the table does not have as stored, and says so', () => {
    const f = tierFocus(receiver({ tier: 7 }), 0, {});
    expect(f.answer).toBe('Kept as stored: 7');
    expect(f.consequence).toBe('Not a tier the approval table has.');
  });
});

describe('enabling recovery', () => {
  it('says what shadow mode sends, and what enabling it allows', () => {
    const off = recoveryFocus({ receivers: [], policy: {} });
    expect(off).toMatchObject({
      id: 'site-recovery-mode',
      title: 'Enable recovery',
      answer: 'Off: shadow mode',
    });
    expect(off.question).toBe(
      'What would enabling recovery here change, and what stays the same? Explain it; do not recommend on or off.',
    );
    expect(off.consequence).toMatch(/sends no recovery write/);
    const on = recoveryFocus({ receivers: [], policy: {}, recovery: { mode: 'enabled' } } as SiteProfile);
    expect(on.answer).toBe('On: recovery enabled');
    expect(on.consequence).toMatch(/only through the gate and the approvals/);
    expect(on.consequence).toMatch(
      /a plan made while it was off is not released: it needs a fresh investigation\.$/,
    );
    expect(on.written).toBe(RECOVERY_WRITTEN);
  });
});

describe('the words', () => {
  it('keep to the house style: no long dashes, and every text within the summary’s 200 characters but the written ones', () => {
    const all = [
      kindFocus(receiver({}), 0),
      tierFocus(receiver({}), 0, {}),
      recoveryFocus({ receivers: [], policy: {} }),
    ];
    for (const f of all) {
      for (const t of Object.values(f)) expect(t).not.toMatch(/[\u2013\u2014]/);
      for (const t of [f.title, f.answer, f.consequence]) expect(t.length).toBeLessThanOrEqual(200);
    }
  });
});

describe('the written explanations', () => {
  // DESIGN 1.4: a card body is at most 40 words, split into list items past 2 sentences; each is one card's body, open
  // where no live answer is given and in a closed "Written explanation" under a live one
  it.each([
    ['kind', KIND_WRITTEN],
    ['tier', TIER_WRITTEN],
    ['recovery', RECOVERY_WRITTEN],
  ])('keeps the %s’s to a card body: 40 words, 2 sentences', (_, text) => {
    const p = document.createElement('p');
    p.textContent = text;
    expect(layer1WordCount(p)).toBeLessThanOrEqual(40);
    expect(text.match(/[.?!](\s|$)/g)).toHaveLength(2);
  });

  it('asks every question to explain, never to recommend', () => {
    const all = [
      kindFocus(receiver({}), 0),
      tierFocus(receiver({ tier: 2 }), 0, {}),
      tierFocus(receiver({ tier: 9 }), 0, {}),
      recoveryFocus({ receivers: [], policy: {} }),
      recoveryFocus({ receivers: [], policy: {}, recovery: { mode: 'enabled' } } as SiteProfile),
    ];
    for (const f of all)
      expect(f.question).toMatch(/ Explain (each|it); do not recommend (one|on or off)\.$/);
  });
});
