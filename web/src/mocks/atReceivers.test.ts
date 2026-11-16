import { describe, expect, it } from 'vitest';
import type { SiteProfile } from '@/api/types';
import type { CatalogueEntry, CatalogueView } from '@/features/site-guide/model';
import shippedFile from '../../../knowledge/catalogue/catalogue.json';
import recorded from './catalogue-recorded.json';
import { atReceiversOf } from './atReceivers';
import { catalogueView, resetMock } from './handlers';

/**
 * The trial's GET /catalogue and the real route cannot drift apart: the mock serves the route's recorded answer, and
 * works out atReceivers for the trial's own profile with a port of the core's Matcher.AtReceiver, which must give the
 * recorded rows exactly on the profile they were recorded with. A change to the shipped catalogue makes the recording
 * stale, and this test says so: record it again (the file's note says how).
 */

const catalogue = recorded.catalogue as unknown as CatalogueView;
const profile = recorded.siteProfile.profile as unknown as SiteProfile;

describe("the trial's catalogue and the recorded route", () => {
  it('was recorded on a profile with receivers, and every shipped entry carries the route’s rows', () => {
    expect(profile.receivers.length).toBeGreaterThan(1);
    for (const e of catalogue.shipped) expect(e.atReceivers?.length).toBe(profile.receivers.length);
  });

  it("gives the route's own rows on the recorded profile, entry by entry and receiver by receiver", () => {
    for (const { atReceivers, ...e } of catalogue.shipped as CatalogueEntry[])
      expect({ id: e.id, rows: atReceiversOf(e, profile) }).toEqual({ id: e.id, rows: atReceivers });
  });

  it('gives the route’s rows on the recorded profile with an authoritative source too, as the core would', () => {
    // E7's alternative names the case's other source: with a source named, the row says what applies then, apart
    const named = { ...profile, authoritative_source: 'BEDMGR' };
    const e7 = (catalogue.shipped as CatalogueEntry[]).find((e) => e.id === 'E7')!;
    const rows = atReceiversOf(e7, named);
    expect(
      rows.every((r) => r.whenOtherSource.length === 1 && r.whenOtherSource[0].otherSource === 'BEDMGR'),
    ).toBe(true);
    expect(rows[0].whenOtherSource[0].outcome).toBe('none');
    expect(rows[0].outcome).toBe('escalate');
  });

  it('is current with the shipped catalogue: record the route again when the catalogue changes', () => {
    const strip = (e: Record<string, unknown>): Record<string, unknown> => {
      const { atReceivers: _a, source: _s, ...rest } = e;
      // The store reads an entry with no alternatives as an empty list
      return { ...rest, alternatives: rest.alternatives ?? [] };
    };
    const file = (shippedFile as unknown as Record<string, unknown>[]).map(strip);
    const answer = (catalogue.shipped as unknown as Record<string, unknown>[]).map(strip);
    expect(answer).toEqual([...file].sort((a, b) => (String(a.id) < String(b.id) ? -1 : 1)));
  });

  it("serves the trial's own profile: a saved change reaches the rows", () => {
    resetMock('approver');
    const view = catalogueView({ ...profile, receivers: [profile.receivers[0]] });
    expect(view.shipped.every((e) => e.atReceivers?.length === 1)).toBe(true);
    // The recorded version, with the generation and the trial's active sample entry after it
    expect(view.version).toBe(`${catalogue.version};g1:L1@1`);
  });
});
