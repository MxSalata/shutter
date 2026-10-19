import { describe, expect, it } from 'vitest';
import type { SiteProfile } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  checkDraft,
  describeSource,
  diffProfiles,
  fieldId,
  problemField,
  toPutBody,
  validateProfile,
} from './profile';

const recorded = (fixtures as unknown as { siteProfile: { profile: SiteProfile } }).siteProfile.profile;
const copy = (): SiteProfile => structuredClone(recorded);

describe('validateProfile, the port of SiteProfile.Validate', () => {
  it('accepts the recorded profile', () => {
    expect(validateProfile(recorded)).toBe('');
  });

  it.each([
    [(p: Record<string, unknown>) => (p.expectedVersion = 3), 'expectedVersion: unknown field'],
    [(p: Record<string, unknown>) => (p.receivers = []), 'receivers: must be a non-empty array'],
    [(p: SiteProfile) => (p.receivers[0].name = ''), 'receivers[0].name: required'],
    [(p: SiteProfile) => (p.receivers[0].tier = 4), 'receivers[0].tier: must be 1, 2 or 3'],
    [
      (p: SiteProfile) => ((p.receivers[0] as Record<string, unknown>).cancels = 'no'),
      'receivers[0].cancels: must be true or false',
    ],
    [(p: SiteProfile) => (p.receivers[0].api = { foo: '/x' }), 'receivers[0].api.foo: unknown path'],
    [
      (p: SiteProfile) => (p.receivers[0].features = { bar: true }),
      'receivers[0].features.bar: unknown feature',
    ],
    [
      (p: SiteProfile) => (p.unconditional_resend = 'with_approval'),
      'unconditional_resend: must be forbidden or allowed',
    ],
    [(p: SiteProfile) => (p.policy['4'] = {}), 'policy.4: the tiers are 1, 2 and 3'],
    [
      (p: SiteProfile) => ((p.policy['2'] as Record<string, string>).mixed = 'automatic'),
      'policy.2.mixed: the chain kinds are single, ordered and interleaved',
    ],
    [
      (p: SiteProfile) => (p.policy['1'].single = 'never'),
      'policy.1.single: must be automatic, approval, per_chain or board',
    ],
    [
      (p: SiteProfile) => (p.incident = { ...p.incident, threshold: 0 }),
      'incident.threshold: must be a whole number of 1 or more',
    ],
    [
      (p: SiteProfile) => (p.incident = { ...p.incident, quiet_seconds: -1 }),
      'incident.quiet_seconds: must be a whole number',
    ],
  ])('refuses a bad profile with the server’s message (%#)', (spoil, message) => {
    const p = copy();
    (spoil as (p: unknown) => void)(p);
    expect(validateProfile(p)).toBe(message);
  });

  it('accepts what the server accepts: a quiet period of 0 and a tier written as "2"', () => {
    const p = copy();
    p.incident = { ...p.incident, quiet_seconds: 0 };
    (p.receivers[0] as Record<string, unknown>).tier = '2';
    expect(validateProfile(p)).toBe('');
  });

  it('refuses a second receiver with the same name, which the core would silently shadow', () => {
    const p = copy();
    p.receivers.push({ ...p.receivers[0] });
    expect(checkDraft(p)).toBe('receivers[1].name: another receiver already has this name');
  });
});

describe('the PUT body', () => {
  it('sends the whole profile as read, without its inner version, with expectedVersion', () => {
    const p = copy();
    p.approvers = { ...p.approvers, pager: '1234' };
    const body = toPutBody(p, 3);
    expect(body).not.toHaveProperty('version');
    expect(body.expectedVersion).toBe(3);
    expect(body.receivers[0].api).toEqual(recorded.receivers[0].api);
    expect(body.receivers[0].features).toEqual(recorded.receivers[0].features);
    expect(body.authoritative_source).toBe(recorded.authoritative_source);
    expect(body.unconditional_resend).toBe(recorded.unconditional_resend);
    expect(body.approvers?.pager).toBe('1234');
  });
});

describe('the server’s error path', () => {
  it('names the field', () => {
    expect(
      problemField('The profile is not valid (CONTRACTS 6.4): receivers[0].tier: must be 1, 2 or 3'),
    ).toEqual({ path: 'receivers[0].tier', message: 'must be 1, 2 or 3' });
    expect(fieldId('receivers[0].tier')).toBe('site-receivers-0-tier');
    expect(fieldId('policy.3.single')).toBe('site-policy-3-single');
    expect(fieldId('incident.threshold')).toBe('site-incident-threshold');
    expect(fieldId('receivers[0].api.base')).toBe('');
  });
});

describe('diffProfiles', () => {
  it('is empty for an unchanged copy and ignores the inner version', () => {
    const p = copy();
    p.version = 99;
    expect(diffProfiles(recorded, p)).toEqual([]);
  });

  it('says what changed, from what to what, and marks less oversight', () => {
    const p = copy();
    p.receivers[0].tier = 3;
    p.policy['3'].single = 'automatic';
    p.incident = { ...p.incident, threshold: 8 };
    const texts = diffProfiles(recorded, p).map((c) => c.text);
    expect(texts).toContain('Ward Out, tier: from 2, operations to 3, clinical safety');
    expect(texts).toContain('Tier 3 single failures: from one approval to automatic');
    expect(texts).toContain('Incidents, failures: from 5 to 8');
    expect(texts.join(' ')).not.toContain('->');
    const policy = diffProfiles(recorded, p).find((c) => c.path === 'policy.3.single');
    expect(policy?.lessOversight).toBe(true);
    expect(policy?.tier3Automatic).toBe(true);
  });

  it('reads a renamed receiver as one removed and one added', () => {
    const p = copy();
    p.receivers[0].name = 'Bed Board';
    expect(diffProfiles(recorded, p).map((c) => c.text)).toEqual([
      'Receiver added: Bed Board',
      'Receiver removed: Ward Out',
    ]);
  });
});

describe('describeSource', () => {
  it('names the seed file, a save in Shutter and the defaults', () => {
    expect(describeSource('/home/irisowner/dev/knowledge/site/profile.json')).toBe(
      'Seeded from knowledge/site/profile.json',
    );
    expect(describeSource('api')).toBe('Saved in Shutter');
    expect(describeSource('defaults')).toBe('The built-in defaults, never stored');
  });
});
