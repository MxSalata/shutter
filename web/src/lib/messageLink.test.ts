import { describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { messageContentsLink, runMessageLink, withHeaderClass } from './messageLink';

const SHUTTER = '/csp/healthshare/shutter/';

/** A link as releases before 1.4.5 wrote it: the page and the header's id, with no class. */
const before = (base: string, id: string) =>
  `${base}EnsPortal.MessageContents.zen?${new URLSearchParams({ HeaderId: id })}`;

describe("a link to a message's page in the Management Portal", () => {
  it("names the header's class before its id, as the page needs to open it", () => {
    expect(messageContentsLink(SHUTTER, '244')).toBe(
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=244',
    );
  });

  it("is built under the base path it is given, another namespace's too, from an id as a number or as text", () => {
    expect(messageContentsLink('/csp/healthshare/hospital/', 66)).toBe(
      '/csp/healthshare/hospital/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=66',
    );
    expect(messageContentsLink('/csp/shutter/', '9625')).toBe(
      '/csp/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=9625',
    );
  });

  it('keeps an id from adding a parameter of its own', () => {
    expect(messageContentsLink(SHUTTER, '7&HeaderClass=x')).toBe(
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=7%26HeaderClass%3Dx',
    );
  });
});

describe('a link that arrives', () => {
  it('gains the header class when it opens a message and names none', () => {
    expect(before(SHUTTER, '244')).not.toContain('HeaderClass');
    expect(withHeaderClass(before(SHUTTER, '244'))).toBe(messageContentsLink(SHUTTER, '244'));
    expect(withHeaderClass(before('https://shutter.example/csp/healthshare/shutter/', '244'))).toBe(
      'https://shutter.example/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=244',
    );
  });

  it('is left as it came when it names a class already, before the id or after it', () => {
    const built = messageContentsLink(SHUTTER, '244');
    expect(withHeaderClass(built)).toBe(built);
    expect(withHeaderClass(withHeaderClass(before(SHUTTER, '244')))).toBe(built);
    const after = `${before(SHUTTER, '244')}&HeaderClass=Ens.MessageHeader`;
    expect(withHeaderClass(after)).toBe(after);
  });

  it('is left as it came when it opens another page, or nothing', () => {
    const trace = '/csp/healthshare/shutter/EnsPortal.VisualTrace.zen?SESSIONID=244';
    expect(withHeaderClass(trace)).toBe(trace);
    expect(withHeaderClass('/csp/healthshare/shutter/EnsPortal.MessageContents.zen')).toBe(
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen',
    );
    expect(withHeaderClass('')).toBe('');
  });
});

describe("an agent run's message", () => {
  it('opens by the link the API sent, with the header class added when the link has none', () => {
    expect(
      runMessageLink({ messageLink: before(SHUTTER, '16615'), ensMessageId: '16615' }, '/csp/other/'),
    ).toBe(messageContentsLink(SHUTTER, '16615'));
    const sent = messageContentsLink(SHUTTER, '16615');
    expect(runMessageLink({ messageLink: sent, ensMessageId: '16615' }, '/csp/other/')).toBe(sent);
  });

  it("is built from the portal's base path when the API sent no link", () => {
    expect(runMessageLink({ ensMessageId: '16615' }, SHUTTER)).toBe(messageContentsLink(SHUTTER, '16615'));
    expect(runMessageLink({ messageLink: '', ensMessageId: '16615' }, SHUTTER)).toBe(
      messageContentsLink(SHUTTER, '16615'),
    );
  });

  it("opens with the header class for every run the trial's recording holds, whatever release recorded it", () => {
    const runs = Object.values(fixtures.cases).flatMap((c) =>
      (c.runs ?? []).filter((r) => r.messageLink && r.ensMessageId),
    );
    expect(runs.length).toBeGreaterThan(0);
    for (const run of runs)
      expect(runMessageLink(run, '/csp/other/')).toBe(messageContentsLink(SHUTTER, run.ensMessageId));
  });
});
