import { describe, expect, it } from 'vitest';
import type { SiteProfile, WhatIfFact } from '@/api/types';
import { recordedSiteProfile } from '@/mocks/profile';
import {
  FACT_PARAM,
  SUGGEST_PARAM,
  applySuggestion,
  fieldLabel,
  parseSuggestion,
  revertSuggestion,
  suggestionFromFact,
  suggestionHref,
  valueLabel,
  type SuggestedChange,
} from './suggestion';

const profile = (): SiteProfile => recordedSiteProfile()!.profile;

const W1: WhatIfFact = {
  id: 'W1',
  kind: 'alternative',
  field: 'authoritative_source',
  from: '',
  to: 'BEDMGR',
  alternative: { outcome: 'none', disposition: 'superseded', when: 'authoritative_source: other_source' },
  would: 'The bed manager placement would stand.',
  affects: ['same-time movements'],
};

const change = (over: Partial<SuggestedChange>): SuggestedChange => ({
  caseId: 'C-000008',
  fact: 'W1',
  field: 'authoritative_source',
  from: '',
  to: 'BEDMGR',
  ...over,
});

describe('a suggested profile change', () => {
  it('carries only the case and the fact in the Site profile address', () => {
    const href = suggestionHref({ caseId: 'C-000008', fact: 'W1' });
    expect(href).toBe('/site-profile?suggest=C-000008&fact=W1');
    const search = new URLSearchParams(href.split('?')[1]);
    expect(search.get(SUGGEST_PARAM)).toBe('C-000008');
    expect(search.get(FACT_PARAM)).toBe('W1');
    expect(parseSuggestion(search)).toEqual({ caseId: 'C-000008', fact: 'W1' });
    // The change itself is built from the fact the case's facts give
    expect(suggestionFromFact('C-000008', W1)).toEqual({
      caseId: 'C-000008',
      fact: 'W1',
      field: 'authoritative_source',
      from: '',
      to: 'BEDMGR',
      why: 'The bed manager placement would stand.',
      affects: ['same-time movements'],
    });
  });

  it('refuses an address that does not name a case and a fact', () => {
    const p = (q: string) => parseSuggestion(new URLSearchParams(q));
    expect(p('')).toBeNull();
    expect(p('suggest=C-000008')).toBeNull();
    expect(p('fact=W1')).toBeNull();
    expect(p(`suggest=${encodeURIComponent(JSON.stringify({ field: 'x' }))}&fact=W1`)).toBeNull();
    expect(p('suggest=C-000008&fact=why')).toBeNull();
  });

  it('sets a top-level setting on a copy, when it still holds the value the facts were read with', () => {
    const p = profile();
    const r = applySuggestion(p, change({}));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.profile.authoritative_source).toBe('BEDMGR');
    expect(p.authoritative_source).toBe('');
  });

  it('sets a tier approval policy and a receiver field by the receiver name', () => {
    const policy = applySuggestion(
      profile(),
      change({ field: 'policy.2.single', from: 'automatic', to: 'approval' }),
    );
    expect(policy.ok && policy.profile.policy['2'].single).toBe('approval');
    const cancels = applySuggestion(
      profile(),
      change({ field: 'receivers[].cancels', receiver: 'Downstream Out', from: false, to: true }),
    );
    expect(cancels.ok && cancels.profile.receivers[0].cancels).toBe(true);
    const category = applySuggestion(
      profile(),
      change({
        field: 'receivers[].category',
        receiver: 'Downstream Out',
        from: null,
        to: 'history_of_record',
      }),
    );
    expect(category.ok && category.profile.receivers[0].category).toBe('history_of_record');
  });

  it('reads an absent category as current_state and an absent history policy as current, as the server does', () => {
    // The design's own example: a receiver with no category field, suggested from current_state
    const p = profile();
    delete (p.receivers[0] as { category?: string }).category;
    delete (p as { history_policy?: string }).history_policy;
    const category = applySuggestion(
      p,
      change({
        field: 'receivers[].category',
        receiver: 'Downstream Out',
        from: 'current_state',
        to: 'history_of_record',
      }),
    );
    expect(category.ok && category.profile.receivers[0].category).toBe('history_of_record');
    const unknown = profile();
    (unknown.receivers[0] as { category?: string }).category = 'something_else';
    expect(
      applySuggestion(
        unknown,
        change({
          field: 'receivers[].category',
          receiver: 'Downstream Out',
          from: 'current_state',
          to: 'history_of_record',
        }),
      ).ok,
    ).toBe(true);
    const history = applySuggestion(p, change({ field: 'history_policy', from: 'current', to: 'correct' }));
    expect(history.ok && history.profile.history_policy).toBe('correct');
    // Already the default: nothing to change
    expect(
      applySuggestion(p, change({ field: 'history_policy', from: 'correct', to: 'current' })),
    ).toMatchObject({ ok: false, reason: 'already', current: 'current' });
  });

  it("reads a receiver's absent history policy from its category, then the site's", () => {
    const fact = (from: string, to: string) =>
      change({ field: 'receivers[].history_policy', receiver: 'Downstream Out', from, to });
    const p = profile();
    delete (p.receivers[0] as { history_policy?: string }).history_policy;
    p.receivers[0].category = 'history_of_record';
    // A history_of_record receiver with no policy of its own already keeps the history straight
    expect(applySuggestion(p, fact('current', 'correct'))).toMatchObject({
      reason: 'already',
      current: 'correct',
    });
    const r = applySuggestion(p, fact('correct', 'current'));
    expect(r.ok && r.profile.receivers[0].history_policy).toBe('current');
    // With no category either, the site-wide policy decides, current when absent
    delete (p.receivers[0] as { category?: string }).category;
    expect(applySuggestion(p, fact('current', 'correct')).ok).toBe(true);
    p.history_policy = 'correct';
    expect(applySuggestion(p, fact('current', 'correct'))).toMatchObject({ reason: 'already' });
  });

  it('puts back only the suggested field, keeping the other edits in the draft', () => {
    const stored = profile();
    const s = change({});
    const applied = applySuggestion(stored, s);
    expect(applied.ok).toBe(true);
    if (!applied.ok) return;
    const draft = applied.profile;
    draft.receivers[0].cancels = !stored.receivers[0].cancels;
    const back = revertSuggestion(draft, stored, s);
    expect(back.authoritative_source).toBe(stored.authoritative_source);
    expect(back.receivers[0].cancels).toBe(!stored.receivers[0].cancels);
    expect(draft.authoritative_source).toBe('BEDMGR');
  });

  it('refuses a stale, an already applied, an unknown field and a missing receiver', () => {
    expect(applySuggestion(profile(), change({ from: 'PAS' }))).toEqual({
      ok: false,
      reason: 'stale',
      current: '',
    });
    const p = profile();
    p.authoritative_source = 'BEDMGR';
    expect(applySuggestion(p, change({})).ok ? 'applied' : 'refused').toBe('refused');
    expect(applySuggestion(p, change({}))).toMatchObject({ reason: 'already' });
    expect(applySuggestion(profile(), change({ field: 'mail.from' }))).toMatchObject({
      reason: 'unsupported',
    });
    expect(applySuggestion(profile(), change({ field: 'receivers[].api' }))).toMatchObject({
      reason: 'unsupported',
    });
    expect(
      applySuggestion(
        profile(),
        change({ field: 'receivers[].cancels', receiver: 'Elsewhere', from: false, to: true }),
      ),
    ).toMatchObject({ reason: 'no_receiver' });
  });

  it('names fields and values in words', () => {
    expect(fieldLabel('authoritative_source')).toBe('Authoritative source');
    expect(fieldLabel('policy.2.single')).toBe('Approval of tier 2 single failures');
    expect(fieldLabel('receivers[].category', 'Downstream Out')).toBe('Category of Downstream Out');
    expect(valueLabel('authoritative_source', '')).toBe('none named');
    expect(valueLabel('receivers[].category', null)).toBe('not set');
    expect(valueLabel('receivers[].cancels', true)).toBe('yes');
    expect(valueLabel('authoritative_source', 'BEDMGR')).toBe('BEDMGR');
  });
});
