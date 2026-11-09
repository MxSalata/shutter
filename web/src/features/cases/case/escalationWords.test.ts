import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteTeam } from '@/api/types';
import { SHADOW_NO_MAIL, automaticTeam, mailOutcome, sendConsequence, sentNotice } from './escalationWords';

const profile = (more: Partial<SiteProfile>) => ({ receivers: [], ...more }) as unknown as SiteProfile;

describe('what sending an escalation will do', () => {
  it('reads shadow mode as the server does: no email and no file, unless the site allows email in shadow mode', () => {
    expect(mailOutcome(undefined)).toBe('unknown');
    expect(mailOutcome(profile({}))).toBe('suppressed');
    expect(mailOutcome(profile({ recovery: { mode: 'shadow' } }))).toBe('suppressed');
    expect(mailOutcome(profile({ recovery: { mode: 'enabled' } }))).toBe('mail');
    expect(mailOutcome(profile({ notifications: { shadow_delivery: 'enabled' } }))).toBe('mail');
    expect(mailOutcome(profile({ notifications: { shadow_delivery: 'disabled' } }))).toBe('suppressed');
  });

  it('says before the press that shadow mode emails nobody and saves no file, and never promises a file then', () => {
    const shadow = sendConsequence('suppressed', 'the Integration team');
    expect(shadow).toBe(SHADOW_NO_MAIL);
    expect(shadow).toMatch(/emails nobody and saves no email file: the escalation will read Not sent/);
    expect(shadow).not.toMatch(/it is saved as an email file/);
    expect(sendConsequence('mail', 'the Integration team')).toBe(
      "This emails the Integration team through the site's mail server. With no mail server set, it is saved as an email file and nobody is emailed.",
    );
    expect(sendConsequence('mail', 'a@example.nhs.uk', true)).toBe(
      "This sends the same text to a@example.nhs.uk through the site's mail server. With no mail server set, it is saved as an email file again and nobody is emailed.",
    );
    expect(sendConsequence('unknown', 'x')).toMatch(/In shadow mode nothing is emailed or saved\.$/);
  });

  it('says after the press what the line will show', () => {
    expect(sentNotice('suppressed', 2)).toEqual({
      title: 'Escalation 2 recorded, not sent',
      line: 'Shadow mode emails nobody and saves no email file, so its line reads Not sent.',
    });
    expect(sentNotice('mail', 2, true).title).toBe('Escalation 2 queued again');
    expect(sentNotice('mail', 2).line).toMatch(/saved as an email file\.$/);
  });
});

describe("the team Automatic names, by the server's rule", () => {
  const teams: SiteTeam[] = [
    { id: 'integration', name: 'Integration team', mailbox: 'i@x', receivers: ['Downstream Out'] },
    { id: 'lab', name: 'Lab team', mailbox: 'l@x', receivers: ['Quillon O9 Out'] },
    { id: 'pas', name: 'PAS team', mailbox: 'p@x', sources: ['PAS'] },
  ];
  const c = (receiver: string, event = 'r01', sourceSystem = 'QUILLON') => ({
    receiver,
    event,
    sourceSystem,
    operationKey: '',
  });

  it("names the team that lists the receiver, else the site's first, and for a merge the source's team first", () => {
    expect(automaticTeam(c('Quillon O9 Out'), teams)?.name).toBe('Lab team');
    expect(automaticTeam(c('Quillon O4 Out'), teams)?.name).toBe('Integration team');
    expect(automaticTeam(c('Downstream Out', 'merge', 'PAS'), teams)?.name).toBe('PAS team');
    expect(automaticTeam(c('Downstream Out', 'transfer', 'PAS'), teams)?.name).toBe('Integration team');
    expect(automaticTeam(c('Downstream Out'), [])).toBeUndefined();
  });
});
