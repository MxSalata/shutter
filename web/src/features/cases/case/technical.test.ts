import { describe, expect, it } from 'vitest';
import {
  catalogueEntryOf,
  digestPrefix,
  failureCode,
  messageContentsLink,
  planLabel,
  portalBaseOf,
  utcMillis,
} from './technical';

describe("the Technical facts' words", () => {
  it("name the receiver's answer by its status and reason code, and nothing when it gave none", () => {
    expect(failureCode({ failureHttpStatus: 409, failureReasonCode: 'bed_occupied' })).toBe(
      '409 bed_occupied',
    );
    expect(failureCode({ failureReasonCode: 'merge' })).toBe('merge');
    expect(failureCode({})).toBe('');
  });

  it("give a digest's first twelve characters without its algorithm", () => {
    expect(digestPrefix('sha256:c32d519e968bb1ceca8b4666aed317c64f58f197b9771e8b4958b464b241793e')).toBe(
      'c32d519e968b',
    );
    expect(digestPrefix('abcdef0123456789')).toBe('abcdef012345');
    expect(digestPrefix(undefined)).toBe('');
  });

  it('name the plan by its version and digest, and say nothing of a case with no plan', () => {
    expect(planLabel({ planVersion: 2, planDigest: 'sha256:07a74c78526c5aaa' })).toBe('v2 07a74c78526c');
    expect(planLabel({ planDigest: 'sha256:07a74c78526c5aaa' })).toBe('07a74c78526c');
    expect(planLabel({})).toBe('');
  });

  it("take the plan's catalogue entry, else the one the site's policy named", () => {
    expect(catalogueEntryOf({ catalogueEntry: 'E7', planCreatedBy: 'run:12' })).toBe('E7');
    expect(catalogueEntryOf({ planCreatedBy: 'policy:E16' })).toBe('E16');
    expect(catalogueEntryOf({ planCreatedBy: 'rules' })).toBe('');
  });

  it('write a time in UTC to the millisecond, with its date when asked, and nothing for a time that is not one', () => {
    expect(utcMillis('2026-11-02T14:34:44.605Z')).toBe('14:34:44.605Z');
    expect(utcMillis('2026-11-02T14:34:44Z', true)).toBe('2026-11-02 14:34:44.000Z');
    expect(utcMillis('not a time')).toBe('');
    expect(utcMillis(undefined)).toBe('');
  });

  it("read the Management Portal's base from the case's trace link, and link a message by its header", () => {
    const base = portalBaseOf({
      links: {
        visualTrace: '/csp/healthshare/shutter/EnsPortal.VisualTrace.zen?SESSIONID=9625',
        workflowTrace: '',
      },
    });
    expect(base).toBe('/csp/healthshare/shutter/');
    expect(messageContentsLink(base, '9625')).toBe(
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=9625',
    );
    expect(portalBaseOf({})).toBe('');
  });
});
