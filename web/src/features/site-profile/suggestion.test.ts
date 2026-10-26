import { describe, expect, it } from 'vitest';
import type { SiteProfile, WhatIfFact } from '@/api/types';
import { recordedSiteProfile } from '@/mocks/profile';
import {
  SUGGEST_PARAM,
  applySuggestion,
  fieldLabel,
  parseSuggestion,
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
  it('travels in the Site profile address and is read back the same', () => {
    const s = suggestionFromFact('C-000008', W1);
    const href = suggestionHref(s);
    expect(href.startsWith('/site-profile?suggest=')).toBe(true);
    const raw = new URLSearchParams(href.split('?')[1]).get(SUGGEST_PARAM);
    expect(parseSuggestion(raw)).toEqual({
      caseId: 'C-000008',
      fact: 'W1',
      field: 'authoritative_source',
      from: '',
      to: 'BEDMGR',
      why: 'The bed manager placement would stand.',
      affects: ['same-time movements'],
    });
  });

  it('refuses a parameter that is not a suggestion', () => {
    expect(parseSuggestion(null)).toBeNull();
    expect(parseSuggestion('not json')).toBeNull();
    expect(parseSuggestion(JSON.stringify({ field: 'authoritative_source' }))).toBeNull();
    expect(parseSuggestion(JSON.stringify({ field: '', to: 'X', from: '' }))).toBeNull();
    expect(parseSuggestion(JSON.stringify({ field: 'merges', to: { a: 1 }, from: '' }))).toBeNull();
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
