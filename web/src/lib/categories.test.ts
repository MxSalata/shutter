import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { categoryOf, historyPolicyOf } from './categories';

const receiver = (extra: Partial<SiteReceiver>): SiteReceiver => ({ name: 'R', tier: 2, ...extra });
const site = (history_policy?: string) => ({ receivers: [], policy: {}, history_policy }) as SiteProfile;

describe('a receiver category and the history policy it derives, as the server reads them', () => {
  it('reads an entry with no category as current state', () => {
    expect(categoryOf(receiver({}))).toBe('current_state');
    expect(categoryOf(receiver({ category: 'something else' }))).toBe('current_state');
    expect(categoryOf(receiver({ category: 'history_of_record' }))).toBe('history_of_record');
  });

  it('derives the policy from the category, unless the entry sets its own', () => {
    expect(historyPolicyOf(receiver({ category: 'history_of_record' }))).toBe('correct');
    expect(historyPolicyOf(receiver({ category: 'current_state' }), site('correct'))).toBe('current');
    expect(historyPolicyOf(receiver({ category: 'orders_results' }))).toBe('current');
    expect(historyPolicyOf(receiver({ category: 'history_of_record', history_policy: 'current' }))).toBe(
      'current',
    );
  });

  it('falls back to the deprecated site-wide answer only for an entry with neither', () => {
    expect(historyPolicyOf(receiver({}), site('correct'))).toBe('correct');
    expect(historyPolicyOf(receiver({}), site())).toBe('current');
  });
});
