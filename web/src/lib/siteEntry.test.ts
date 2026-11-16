import { describe, expect, it } from 'vitest';
import { displacedWords, isSiteEntryId, planSiteMatch, siteMatchOf, withoutItWords } from './siteEntry';

const summary = (catalogue: unknown) => ({ catalogue });

const site = {
  decision: 'person',
  entry: 'L1',
  outcome: 'escalate',
  matches: [
    {
      id: 'L1',
      version: 2,
      title: 'A failed transfer into the isolation ward',
      origin: 'site',
      decides: 'person',
      preferred: { outcome: 'escalate', why: 'Infection control places every patient in this ward by hand.' },
      alternatives: [],
      instructions: "Ring the ward's nurse in charge before anything is entered. Do not resend.",
      team: 'infection-control',
    },
  ],
  overridden: [{ id: 'E2', decides: 'policy', outcome: 'resend' }],
  site_also: [
    {
      id: 'L4',
      version: 1,
      title: 'Any failed transfer this week',
      instructions: 'Tell the bed manager.',
      team: '',
    },
  ],
};

describe("one of the site's own scenarios on a case", () => {
  it('tells a site entry id from a shipped one', () => {
    expect(isSiteEntryId('L1')).toBe(true);
    expect(isSiteEntryId('L40')).toBe(true);
    expect(isSiteEntryId('E2')).toBe(false);
    expect(isSiteEntryId('L0')).toBe(false);
    expect(isSiteEntryId('L1@2')).toBe(false);
    expect(isSiteEntryId(undefined)).toBe(false);
  });

  it("reads the match, its instructions, the other site entries' and what it displaced from the evidence", () => {
    const match = siteMatchOf(summary(site));
    expect(match?.id).toBe('L1');
    expect(match?.version).toBe(2);
    expect(match?.why).toMatch(/Infection control/);
    expect(match?.instructions).toMatch(/Ring the ward/);
    expect(match?.team).toBe('infection-control');
    expect(match?.also).toEqual([
      {
        id: 'L4',
        version: 1,
        title: 'Any failed transfer this week',
        instructions: 'Tell the bed manager.',
        team: undefined,
      },
    ]);
    expect(match?.displaced).toEqual([{ id: 'E2', decides: 'policy', outcome: 'resend' }]);
  });

  it('is undefined for a shipped match, several matches, none, or evidence with no catalogue', () => {
    expect(siteMatchOf(summary({ matches: [{ id: 'E2', decides: 'policy' }] }))).toBeUndefined();
    expect(siteMatchOf(summary({ matches: [{ id: 'E2' }, { id: 'E10' }] }))).toBeUndefined();
    expect(siteMatchOf(summary({ matches: [] }))).toBeUndefined();
    expect(siteMatchOf({})).toBeUndefined();
    expect(siteMatchOf(null)).toBeUndefined();
    // A row that only claims to be a site entry's, under a shipped id, is not one.
    expect(siteMatchOf(summary({ matches: [{ id: 'E2', origin: 'site' }] }))).toBeUndefined();
  });

  it('says what the case would have done without it', () => {
    expect(withoutItWords([{ id: 'E2', decides: 'policy', outcome: 'resend' }])).toBe(
      'Without it: E2, a resend by site policy.',
    );
    expect(withoutItWords([{ id: 'E1', decides: 'policy', outcome: 'none' }])).toBe(
      'Without it: E1, closed, nothing sent by site policy.',
    );
    expect(withoutItWords([{ id: 'E13', decides: 'person', outcome: 'escalate' }])).toBe(
      'Without it: E13, a person decides.',
    );
    expect(withoutItWords([])).toBe('Without it: no shipped entry matches, so this would be a new pattern.');
    expect(
      withoutItWords([
        { id: 'E2', decides: 'policy', outcome: 'resend' },
        { id: 'E10', decides: 'board', outcome: 'resend' },
      ]),
    ).toBe('Without it: E2, E10 all match, so the board would decide.');
    expect(displacedWords({ id: 'E9', decides: 'board', outcome: 'some_new_outcome' })).toBe(
      'E9, some new outcome decided by the board',
    );
  });
});

describe('planSiteMatch', () => {
  it('lends a plan the site entry only from its own snapshot', () => {
    const snapshot = { id: 12, summary: summary(site) };
    expect(planSiteMatch({ snapshotId: 12 }, snapshot)?.id).toBe('L1');
    expect(planSiteMatch({ snapshotId: '12' }, snapshot)?.id).toBe('L1');
    expect(planSiteMatch({ snapshotId: 11 }, snapshot)).toBeUndefined();
    expect(planSiteMatch({}, snapshot)?.id).toBe('L1');
    expect(planSiteMatch(null, snapshot)).toBeUndefined();
    expect(planSiteMatch({ snapshotId: 12 }, null)).toBeUndefined();
  });
});
