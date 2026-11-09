import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { SiteProfile } from '@/api/types';
import { glossary } from '@/lib/glossary';
import { RELEASES } from '@/lib/status';
import { recordedSiteProfile } from '@/mocks/profile';
import {
  EFFECT_WORDS,
  KINDS,
  KIND_TERMS,
  POLICY_LABELS,
  TIERS,
  TIER_NAMES,
  checkDraft,
  closeNeedsApprover,
  describeIncident,
  describePath,
  describeSource,
  diffProfiles,
  fieldId,
  incidentRule,
  isDemoPolicy,
  overtakenLine,
  problemField,
  toPutBody,
  validateProfile,
} from './profile';

const recorded = recordedSiteProfile()!.profile;
const copy = (): SiteProfile => structuredClone(recorded);
const FEED_ZONE =
  'feed.time_zone: must be UTC, Europe/London, a fixed offset such as +01:00 (up to 14:00), or an IANA zone name this IRIS knows (for example Europe/Paris)';

describe('the failure census setting (CONTRACTS 19)', () => {
  const base = {
    receivers: [{ name: 'Out', tier: 2 }],
    policy: { '1': { single: 'automatic' }, '2': { single: 'automatic' }, '3': { single: 'approval' } },
  };

  it('a stored profile with it is one the page can save', () => {
    expect(validateProfile({ ...base, failure_census: { enabled: true } })).not.toContain('failure_census');
  });

  it('refuses what is not an object', () => {
    expect(validateProfile({ ...base, failure_census: true })).toBe('failure_census: must be an object');
    expect(validateProfile({ ...base, failure_census: [] })).toBe('failure_census: must be an object');
  });
});

describe('the recovery mode (CONTRACTS 18)', () => {
  const base = (): Record<string, unknown> => ({
    receivers: [{ name: 'Out', tier: 2 }],
    policy: { '1': { single: 'automatic' }, '2': { single: 'automatic' }, '3': { single: 'approval' } },
  });

  it('a stored profile with the mode is one the page can save', () => {
    expect(validateProfile({ ...base(), recovery: { mode: 'enabled' } })).not.toContain('recovery');
    expect(validateProfile({ ...base(), recovery: { mode: 'shadow' } })).not.toContain('recovery');
    expect(validateProfile({ ...base(), notifications: { shadow_delivery: 'disabled' } })).not.toContain(
      'notifications',
    );
  });

  it('refuses what the server refuses', () => {
    expect(validateProfile({ ...base(), recovery: { mode: 'on' } })).toBe(
      'recovery.mode: must be shadow or enabled',
    );
    expect(validateProfile({ ...base(), recovery: { mood: 'enabled' } })).toBe(
      'recovery.mood: unknown setting',
    );
    expect(validateProfile({ ...base(), recovery: 'enabled' })).toBe('recovery: must be an object');
  });

  it('enabling and going back to shadow are spelt out before the save', () => {
    const on = diffProfiles(
      { ...base(), recovery: { mode: 'shadow' } } as never,
      {
        ...base(),
        recovery: { mode: 'enabled' },
      } as never,
    );
    expect(on.find((c) => c.path === 'recovery.mode')?.text).toContain('Recovery enabled');
    const off = diffProfiles({ ...base(), recovery: { mode: 'enabled' } } as never, base() as never);
    expect(off.find((c) => c.path === 'recovery.mode')?.text).toContain('Shadow mode');
  });
});

describe('validateProfile, the port of SiteProfile.Validate', () => {
  it('accepts the recorded profile', () => {
    expect(validateProfile(recorded)).toBe('');
  });

  it("serves the recorded profile, the seed's at the instance's version: two receivers, each with its category, and no site-wide history policy", () => {
    expect(recorded.version).toBe(7);
    expect(recorded.receivers.map((r) => [r.name, r.category])).toEqual([
      ['Downstream Out', 'current_state'],
      ['Records Out', 'history_of_record'],
    ]);
    expect(recorded.receivers[1].demo).toEqual({ namespace: 'RECORDS' });
    expect('history_policy' in recorded).toBe(false);
  });

  it('accepts an IANA zone name with a region, which the server checks against the zones it knows', () => {
    for (const zone of ['Europe/Paris', 'America/Argentina/Buenos_Aires', 'Etc/GMT+2']) {
      const p = copy();
      p.feed = { time_zone: zone };
      expect(validateProfile(p), zone).toBe('');
    }
  });

  it('accepts a receiver with no category, as every profile before categories', () => {
    const p = copy();
    delete p.receivers[0].category;
    expect(validateProfile(p)).toBe('');
  });

  it.each([
    [(p: Record<string, unknown>) => (p.expectedVersion = 3), 'expectedVersion: unknown field'],
    [(p: Record<string, unknown>) => (p.receivers = []), 'receivers: must be a non-empty array'],
    [(p: SiteProfile) => (p.receivers[0].name = ''), 'receivers[0].name: required'],
    [(p: SiteProfile) => (p.receivers[0].tier = 4), 'receivers[0].tier: must be 1, 2 or 3'],
    [
      (p: SiteProfile) => (p.receivers[1].category = 'records'),
      'receivers[1].category: must be current_state, history_of_record or orders_results',
    ],
    [
      (p: SiteProfile) => (p.receivers[0].history_policy = 'keep'),
      'receivers[0].history_policy: must be current or correct',
    ],
    [
      (p: SiteProfile) => ((p.receivers[1] as Record<string, unknown>).demo = 'RECORDS'),
      'receivers[1].demo: must be an object',
    ],
    [
      (p: SiteProfile) => ((p.receivers[1] as Record<string, unknown>).demo = { namespace: 7 }),
      'receivers[1].demo.namespace: must be a string',
    ],
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
      (p: SiteProfile) =>
        (p.receivers[0].api = { base: '/downstream/api', state: '/encounters/{encounter}' }),
      'receivers[0].api.operations: required when api is given',
    ],
    [(p: Record<string, unknown>) => (p.feed = { time_zone: 'GMT' }), FEED_ZONE],
    [(p: Record<string, unknown>) => (p.feed = { time_zone: '+15:00' }), FEED_ZONE],
    [(p: Record<string, unknown>) => (p.feed = { time_zone: 1 }), FEED_ZONE],
    [(p: Record<string, unknown>) => (p.feed = { zone: 'UTC' }), 'feed.zone: unknown setting'],
    [
      (p: Record<string, unknown>) => (p.model_content = { free_text: 'yes' }),
      'model_content.free_text: must be true or false',
    ],
    [
      (p: Record<string, unknown>) => (p.model_content = { names: false }),
      'model_content.names: unknown setting',
    ],
    [
      (p: Record<string, unknown>) => (p.mail = { allowed_domains: 'nhs.net' }),
      'mail.allowed_domains: must be an array of domains',
    ],
    [(p: Record<string, unknown>) => (p.mail = { reply_to: 'x@nhs.net' }), 'mail.reply_to: unknown setting'],
    [(p: Record<string, unknown>) => (p.teams = { id: 'pas' }), 'teams: must be an array'],
    [
      (p: Record<string, unknown>) => (p.teams = [{ id: 'pas', name: 'PAS team' }]),
      'teams[0].mailbox: required',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas.team', pager: '1' }]),
      'teams[0].pager: unknown field',
    ],
    [
      (p: Record<string, unknown>) => (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas.team' }]),
      'teams[0].mailbox: must be one address with one @',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'a@nhs.net@evil.com' }]),
      'teams[0].mailbox: must be one address with one @',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'PAS team <pas@example.nhs.uk>' }]),
      'teams[0].mailbox: must be a bare address, local@domain, with no display name, brackets or spaces',
    ],
    [
      (p: Record<string, unknown>) => (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas@nhs..net' }]),
      'teams[0].mailbox: the domain is not a valid domain name',
    ],
    [
      (p: Record<string, unknown>) => {
        delete p.mail;
        p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas@example.nhs.uk' }];
      },
      'teams[0].mailbox: no allowed mail domains are set in the site profile (mail.allowed_domains)',
    ],
    [
      (p: Record<string, unknown>) => (p.mail = { from: 'shutter@example.nhs.uk\r\nBcc: e@evil.com' }),
      'mail.from: must not contain line breaks or control characters',
    ],
    [
      (p: Record<string, unknown>) => (p.mail = { allowed_domains: ['nhs net'] }),
      'mail.allowed_domains[0]: must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)',
    ],
    [
      (p: Record<string, unknown>) => (p.mail = { allowed_domains: [''] }),
      'mail.allowed_domains[0]: must be a domain',
    ],
    [
      (p: Record<string, unknown>) => {
        p.mail = { allowed_domains: ['nhs.net'] };
        p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas@trust.nhs.net', cc: ['it@example.com'] }];
      },
      'teams[0].cc[0]: not in the allowed domains',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.teams = [
          { id: 'pas', name: 'PAS team', mailbox: 'pas@example.nhs.uk' },
          { id: 'pas', name: 'Integration', mailbox: 'int@example.nhs.uk' },
        ]),
      'teams[1].id: must be unique',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.teams = [{ id: 'pas', name: 'PAS team', mailbox: 'pas@example.nhs.uk', receivers: [''] }]),
      'teams[0].receivers[0]: must be a receiver name',
    ],
    [
      (p: SiteProfile) => (p.incident = { ...p.incident, threshold: 0 }),
      'incident.threshold: must be a whole number of 1 or more',
    ],
    [
      (p: SiteProfile) => (p.incident = { ...p.incident, quiet_seconds: -1 }),
      'incident.quiet_seconds: must be a whole number',
    ],
    [
      (p: SiteProfile) => (p.incident = { ...p.incident, max_intake_seconds: -1 }),
      'incident.max_intake_seconds: must be a whole number',
    ],
    [
      (p: SiteProfile) =>
        (p.approvers = { ...p.approvers, close_needs_approver: 'yes' as unknown as boolean }),
      'approvers.close_needs_approver: must be true or false',
    ],
    [
      (p: Record<string, unknown>) =>
        (p.approvers = { ...(p.approvers as object), close_needs_aprover: true }),
      'approvers.close_needs_aprover: unknown setting',
    ],
    [
      (p: Record<string, unknown>) => (p.approvers = { ...(p.approvers as object), role: 5 }),
      'approvers.role: must be a string',
    ],
    [(p: Record<string, unknown>) => (p.approvers = []), 'approvers: must be an object'],
  ])('refuses a bad profile with the server’s message (%#)', (spoil, message) => {
    const p = copy();
    (spoil as (p: unknown) => void)(p);
    expect(validateProfile(p)).toBe(message);
  });

  it('accepts the further-message, source-skew and source-proof settings, as the server ships and reads them', () => {
    const p = {
      ...copy(),
      further_messages: {
        in_patient_movement: 'stop',
        a08_location: 'stop',
        admission_not_found: 'person',
        scan_seconds: 30,
      },
      feed: { time_zone: 'UTC', source_skew_seconds: 0, prove_origin: false },
    };
    expect(validateProfile(p)).toBe('');
    p.further_messages = {
      in_patient_movement: 'show',
      a08_location: 'show',
      admission_not_found: 'policy',
      scan_seconds: 600,
    };
    p.feed.source_skew_seconds = 3600;
    expect(validateProfile(p)).toBe('');
  });

  it.each([
    [{ further_messages: [] }, 'further_messages: must be an object'],
    [
      { further_messages: { in_patient_movement: 'maybe' } },
      'further_messages.in_patient_movement: must be stop or show',
    ],
    [
      { further_messages: { admission_not_found: 'maybe' } },
      'further_messages.admission_not_found: must be person or policy',
    ],
    [{ further_messages: { a08_location: 'maybe' } }, 'further_messages.a08_location: must be stop or show'],
    [{ further_messages: { in_patient: 'stop' } }, 'further_messages.in_patient: unknown setting'],
    [
      { further_messages: { scan_seconds: 0 } },
      'further_messages.scan_seconds: must be a whole number of seconds from 1 to 600',
    ],
    [
      { further_messages: { scan_seconds: 601 } },
      'further_messages.scan_seconds: must be a whole number of seconds from 1 to 600',
    ],
    [
      { further_messages: { scan_seconds: 1.5 } },
      'further_messages.scan_seconds: must be a whole number of seconds from 1 to 600',
    ],
    [
      { further_messages: { scan_seconds: '30' } },
      'further_messages.scan_seconds: must be a whole number of seconds from 1 to 600',
    ],
    [
      { feed: { source_skew_seconds: 3601 } },
      'feed.source_skew_seconds: must be a whole number of seconds from 0 to 3600',
    ],
    [
      { feed: { source_skew_seconds: '300' } },
      'feed.source_skew_seconds: must be a whole number of seconds from 0 to 3600',
    ],
    [{ feed: { prove_origin: 'yes' } }, 'feed.prove_origin: must be true or false'],
  ])('refuses %j as the server does', (patch, message) => {
    expect(validateProfile({ ...copy(), ...patch })).toBe(message);
  });

  it('accepts what the server accepts: a quiet period of 0 and a tier written as "2"', () => {
    const p = copy();
    p.incident = { ...p.incident, quiet_seconds: 0 };
    (p.receivers[0] as Record<string, unknown>).tier = '2';
    expect(validateProfile(p)).toBe('');
  });

  it('accepts a fixed offset, and a team whose mailboxes are in a subdomain of an allowed domain', () => {
    const p = copy() as SiteProfile & Record<string, unknown>;
    p.feed = { time_zone: '-03:30' };
    p.mail = { from: 'shutter@trust.nhs.net', allowed_domains: ['NHS.net'] };
    p.teams = [
      {
        id: 'pas',
        name: 'PAS team',
        mailbox: 'pas@trust.nhs.net',
        cc: ['oncall@nhs.net'],
        receivers: ['Downstream Out'],
      },
    ];
    expect(validateProfile(p)).toBe('');
  });

  it('refuses a second receiver with the same name, which the core would silently shadow', () => {
    const p = copy();
    p.receivers.push({ ...p.receivers[0] });
    expect(checkDraft(p)).toBe(
      `receivers[${p.receivers.length - 1}].name: another receiver already has this name`,
    );
  });
});

describe('the PUT body', () => {
  it('sends the whole profile as read, without its inner version, with expectedVersion', () => {
    const p = copy();
    p.feed = { time_zone: 'Europe/London' };
    const body = toPutBody(p, 3);
    expect(body).not.toHaveProperty('version');
    expect(body.expectedVersion).toBe(3);
    expect(body.receivers[0].api).toEqual(recorded.receivers[0].api);
    expect(body.receivers[0].features).toEqual(recorded.receivers[0].features);
    expect(body.authoritative_source).toBe(recorded.authoritative_source);
    expect(body.unconditional_resend).toBe(recorded.unconditional_resend);
    expect(body.approvers).toEqual(recorded.approvers);
    expect(body.mail).toEqual(recorded.mail);
    expect(body.feed?.time_zone).toBe('Europe/London');
  });

  it('sends an IANA zone as stored', () => {
    const p = copy();
    p.feed = { time_zone: 'Europe/Paris' };
    expect(toPutBody(p, 7).feed).toEqual({ time_zone: 'Europe/Paris' });
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
    // A problem with one entry of a list belongs to the list's control
    expect(fieldId('teams[1].mailbox')).toBe('site-teams-1-mailbox');
    expect(fieldId('teams[0].cc[2]')).toBe('site-teams-0-cc');
    expect(fieldId('mail.allowed_domains[0]')).toBe('site-mail-allowed_domains');
    expect(fieldId('feed.time_zone')).toBe('site-feed-time_zone');
    expect(fieldId('model_content.free_text')).toBe('site-model_content-free_text');
    expect(describePath('teams[0].cc[2]')).toBe('Team 1, copies 3');
    expect(describePath('teams[1].id')).toBe('Team 2, id');
    expect(describePath('mail.allowed_domains[0]')).toBe('Mail, allowed domains 1');
    expect(describePath('feed.time_zone')).toBe('Feed, time zone');
    expect(fieldId('approvers.close_needs_approver')).toBe('site-approvers-close_needs_approver');
    expect(describePath('approvers.close_needs_approver')).toBe('Approvers, closing a case by hand');
  });
});

describe('the two-person rule for closing a case by hand', () => {
  it('is off unless the profile says true, as the server reads it', () => {
    expect(closeNeedsApprover(recorded)).toBe(false);
    expect(closeNeedsApprover(undefined)).toBe(false);
    const p = copy();
    p.approvers = { ...p.approvers, close_needs_approver: false };
    expect(validateProfile(p)).toBe('');
    expect(closeNeedsApprover(p)).toBe(false);
    p.approvers.close_needs_approver = true;
    expect(validateProfile(p)).toBe('');
    expect(closeNeedsApprover(p)).toBe(true);
  });

  it('reads as a change only when it moves, an explicit off being the same as no answer', () => {
    const off = copy();
    off.approvers = { ...off.approvers, close_needs_approver: false };
    expect(diffProfiles(recorded, off)).toEqual([]);
    const on = copy();
    on.approvers = { ...on.approvers, close_needs_approver: true };
    expect(diffProfiles(recorded, on)).toEqual([
      {
        path: 'approvers.close_needs_approver',
        text: 'Closing a case by hand: only an approver, from now on',
      },
    ]);
    expect(diffProfiles(on, off).map((c) => c.text)).toEqual([
      'Closing a case by hand: an operator too, from now on',
    ]);
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
    expect(texts).toContain('Downstream Out, tier: from 2, operations to 3, clinical safety');
    expect(texts).toContain('Tier 3 single failures: from one approval to automatic');
    expect(texts).toContain('Incidents, failures: from 5 to 8');
    expect(texts.join(' ')).not.toContain('->');
    const policy = diffProfiles(recorded, p).find((c) => c.path === 'policy.3.single');
    expect(policy?.lessOversight).toBe(true);
    expect(policy?.tier3Automatic).toBe(true);
  });

  it("says a receiver's category changed, and what an overtaken failure does there now", () => {
    const p = copy();
    p.receivers[0].category = 'history_of_record';
    const texts = diffProfiles(recorded, p).map((c) => c.text);
    expect(texts).toContain('Downstream Out, category: from current state to history of record');
    expect(texts).toContain(
      'Downstream Out, an overtaken failure: the history is corrected by hand (from its category)',
    );
    const q = copy();
    q.receivers[1].history_policy = 'current';
    expect(diffProfiles(recorded, q).map((c) => c.text)).toEqual([
      'Records Out, an overtaken failure: kept as current, closed with no write (set on the receiver, not from its category)',
    ]);
  });

  it('names the teams, mail, zone and note-text changes', () => {
    // From a profile with no teams, whatever the recorded one has
    const base = copy();
    delete base.teams;
    const p = structuredClone(base);
    const team = { id: 'pas', name: 'PAS team', mailbox: 'pas@trust.nhs.net', receivers: ['Downstream Out'] };
    p.teams = [team];
    p.mail = { allowed_domains: ['nhs.net'] };
    p.feed = { time_zone: 'UTC' };
    p.model_content = { free_text: true };
    expect(diffProfiles(base, p).map((c) => c.text)).toEqual([
      'Team added: PAS team <pas@trust.nhs.net>, for Downstream Out, and any receiver no team names',
      'Allowed mail domains: nhs.net',
      'Feed time zone: from Europe/London to UTC. Every operation key read from now on uses it',
      'Note text: sent to the model from now on',
    ]);
    const q = structuredClone(p);
    q.teams = [
      { ...team, mailbox: 'pas.team@trust.nhs.net' },
      { id: 'int', name: 'Integration', mailbox: 'int@trust.nhs.net', receivers: [] },
    ];
    // As the server routes: the first team also takes what no team names; a later team naming none, only when picked
    expect(diffProfiles(p, q).map((c) => c.text)).toEqual([
      'Team pas changed: PAS team <pas.team@trust.nhs.net>, for Downstream Out, and any receiver no team names',
      'Team added: Integration <int@trust.nhs.net>, for no receiver: only when a person picks it on the case',
    ]);
    const r = structuredClone(q);
    r.teams = [q.teams[1], q.teams[0]];
    expect(diffProfiles(q, r).map((c) => c.text)).toEqual([
      'Cases no team names: now to Integration, before to PAS team',
    ]);
  });

  it('names a change of the first team even with other team changes, and a reorder further down', () => {
    const a = (id: string, receivers: string[] = ['Downstream Out']) => ({
      id,
      name: id.toUpperCase(),
      mailbox: `${id}@trust.nhs.net`,
      receivers,
    });
    const p = copy();
    p.teams = [a('x'), a('y')];
    const q = structuredClone(p);
    q.teams = [a('y'), a('x'), a('z')];
    expect(diffProfiles(p, q).map((c) => c.text)).toEqual([
      'Team added: Z <z@trust.nhs.net>, for Downstream Out',
      'Cases no team names: now to Y, before to X',
    ]);
    const r = structuredClone(q);
    r.teams = [a('y'), a('z'), a('x')];
    expect(diffProfiles(q, r).map((c) => c.text)).toEqual([
      'Teams reordered: where two teams name a receiver, the earlier one gets its cases',
    ]);
  });

  it('reads a renamed receiver as one removed and one added', () => {
    const p = copy();
    p.receivers[0].name = 'Bed Board';
    expect(diffProfiles(recorded, p).map((c) => c.text)).toEqual([
      'Receiver added: Bed Board',
      'Receiver removed: Downstream Out',
    ]);
  });

  describe("a receiver's outage keys, set where none was", () => {
    it.each([
      ['engine_resend', true, 'Downstream Out, the engine resend: on'],
      [
        'ack_level',
        'application',
        'Downstream Out, what a Completed header proves: from not set to application',
      ],
      ['watch', { namespace: 'LAB', item: 'Lab Out' }, 'Downstream Out, its watch changed'],
      ['mail', { to: ['lab@trust.nhs.net'], on: ['open'] }, 'Downstream Out, its outage mail changed'],
      ['approvers', ['A. Person'], 'Downstream Out, its approvers changed'],
      [
        'resend_approval_minutes',
        999999,
        'Downstream Out, minutes an approval to resend lasts: from not set to 999999',
      ],
      [
        'duplicates',
        { behaviour: 'refuses', code: 'AE' },
        'Downstream Out, how it treats duplicates changed',
      ],
      ['hold', { minutes: 25 }, 'Downstream Out, its hold changed'],
      ['runbook', 'https://example.nhs.uk/runbook', 'Downstream Out, its runbook changed'],
      ['call', '01632 960000', 'Downstream Out, who to call changed'],
      ['settle_minutes', 8, 'Downstream Out, minutes to settle: from not set to 8'],
      ['window_minutes', 9, 'Downstream Out, minutes in the window: from not set to 9'],
    ])('%s reads as a change', (key, value, text) => {
      const p = copy();
      p.receivers[0][key] = value;
      expect(diffProfiles(recorded, p).map((c) => c.text)).toEqual([text]);
    });

    it('reads the engine resend turned off, and an explicit false where nothing was said', () => {
      const p = copy();
      p.receivers[0].engine_resend = true;
      const q = structuredClone(p);
      q.receivers[0].engine_resend = false;
      expect(diffProfiles(p, q).map((c) => c.text)).toEqual(['Downstream Out, the engine resend: off']);
      expect(diffProfiles(recorded, q).map((c) => c.text)).toEqual([
        'Downstream Out, the engine resend: off',
      ]);
    });

    it('reads a key taken away, which puts the receiver back on the default', () => {
      const p = copy();
      p.receivers[0].engine_resend = true;
      p.receivers[0].settle_minutes = 8;
      expect(diffProfiles(p, recorded).map((c) => c.text)).toEqual([
        'Downstream Out, the engine resend: off',
        'Downstream Out, minutes to settle: from 8 to not set',
      ]);
    });

    it('prints no address, number or link from what it only says changed', () => {
      const p = copy();
      p.receivers[0].runbook = 'https://example.nhs.uk/runbook';
      p.receivers[0].call = '01632 960000';
      p.receivers[0].mail = { to: ['lab@trust.nhs.net'], on: ['open'] };
      const words = diffProfiles(recorded, p)
        .map((c) => c.text)
        .join(' ');
      for (const hidden of ['example.nhs.uk', '01632', 'lab@trust']) expect(words).not.toContain(hidden);
    });

    it('takes no oversight line from any of them, since a person still approves each engine resend', () => {
      const p = copy();
      p.receivers[0].engine_resend = true;
      p.receivers[0].ack_level = 'application';
      expect(diffProfiles(recorded, p).some((c) => c.lessOversight)).toBe(false);
    });
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

describe('isDemoPolicy', () => {
  it("tells the demo's own policy, marked in the source, from the shipped answers", () => {
    expect(isDemoPolicy('/home/irisowner/dev/knowledge/site/profile.json (demo)')).toBe(true);
    expect(isDemoPolicy('/home/irisowner/dev/knowledge/site/profile.json (demo) (live hospital)')).toBe(true);
    expect(isDemoPolicy('/home/irisowner/dev/knowledge/site/profile.json')).toBe(false);
    expect(isDemoPolicy('/home/irisowner/dev/knowledge/site/profile.json (live hospital)')).toBe(false);
    expect(isDemoPolicy(undefined)).toBe(false);
  });
});

describe('the words the restyled page reads from the model', () => {
  it('heads the three chain kinds with the glossary’s plain terms, one for each kind the profile names', () => {
    expect(KINDS.map((k) => glossary(KIND_TERMS[k]).term)).toEqual([
      'One failed message',
      'Several, in a row',
      'Several, with deliveries between',
    ]);
  });

  it('names the three tiers in full, the words the matrix and the grid share', () => {
    expect(TIERS.map((t) => `Tier ${t}: ${TIER_NAMES[t]}`)).toEqual([
      'Tier 1: information',
      'Tier 2: operations',
      'Tier 3: clinical safety',
    ]);
  });

  it('shortens the approval choices, one for each release the shared map knows', () => {
    expect(Object.keys(POLICY_LABELS).sort()).toEqual(Object.keys(RELEASES).sort());
    for (const label of Object.values(POLICY_LABELS)) expect(label.length).toBeLessThanOrEqual(26);
    expect(POLICY_LABELS.automatic).toBe('Automatic (written policy)');
  });

  it('says what an overtaken failure does in one line, by category and policy', () => {
    expect(overtakenLine('current_state', 'current')).toBe('Overtaken failure: closes, no write.');
    expect(overtakenLine('history_of_record', 'correct')).toBe(
      'Overtaken failure: asks a person to correct by hand.',
    );
    // A receiver whose own policy differs from its category's is read by the policy
    expect(overtakenLine('current_state', 'correct')).toBe(
      'Overtaken failure: asks a person to correct by hand.',
    );
    expect(overtakenLine('orders_results', 'current')).toBe('Every failure goes to a person.');
  });

  it('keeps each icon’s words short enough for a tooltip', () => {
    expect(EFFECT_WORDS.acts).toBe('Changes what Shutter does');
    expect(EFFECT_WORDS.record).toBe('Kept on record; nothing reads it yet');
  });

  it('gives the incident rule in one line, with the core’s defaults for what is not set', () => {
    expect(incidentRule(recorded)).toBe('An incident opens at 5 failures to one receiver within 10 minutes.');
    const p = copy();
    p.incident = { threshold: 8, window_minutes: 3 };
    expect(incidentRule(p)).toBe('An incident opens at 8 failures to one receiver within 3 minutes.');
    delete p.incident;
    expect(incidentRule(p)).toBe('An incident opens at 5 failures to one receiver within 10 minutes.');
    // The full sentence stays for the question’s second layer
    expect(describeIncident(p)).toMatch(/takes no more cases after 60 seconds with no new failure/);
  });
});

describe("validateProfile on a receiver's outage keys, the table Shutter.Test.ProfileWatch runs at the server", () => {
  const source = readFileSync(
    join(__dirname, '../../../../tests/unit/Shutter/Test/ProfileWatch.cls'),
    'utf8',
  );
  const table = /XData Rows \[ MimeType = application\/json \]\n\{\n(\[[\s\S]*?\n\])\n\}/.exec(source);
  const rows = JSON.parse(table![1]) as {
    name: string;
    receiver: object;
    top?: object;
    expect: string;
  }[];

  it('has the rows of the server class', () => {
    expect(rows.length).toBeGreaterThan(60);
  });

  it.each(rows.map((row) => [row.name, row] as const))('%s', (_name, row) => {
    const profile = { receivers: [{ name: 'R', tier: 2, ...row.receiver }], policy: {}, ...row.top };
    expect(validateProfile(profile)).toBe(row.expect);
  });

  it('leaves a recorded profile with none of the keys as it was', () => {
    for (const r of recorded.receivers) expect(r).not.toHaveProperty('watch');
    expect(validateProfile(recorded)).toBe('');
  });

  it('points the server path of a new key at no control, and names it in the alert', () => {
    expect(fieldId('receivers[0].watch.item')).toBe('');
    expect(describePath('receivers[0].watch.item')).toBe('Receiver 1, watch.item');
    expect(problemField('receivers[0].mail.on[1]: must be open, needs_person or closed')).toEqual({
      path: 'receivers[0].mail.on[1]',
      message: 'must be open, needs_person or closed',
    });
  });
});
