import type { SiteProfile, SiteProfileVersionEntry, SiteProfileView } from '@/api/types';
import { SEED_SOURCE } from '@/features/site-profile/profile';
import fixtures from './fixtures.json';
import seed from '../../../knowledge/site/profile.json';

/**
 * The recorded site profile and its versions, as the demo serves them. They were recorded before the seed named its
 * allowed mail domains, and a profile that names teams with no allowed domains now allows no address; the server
 * re-stores the seed's at its next install or knowledge refresh, so a recorded profile with teams and no mail settings
 * takes the seed's. The fixtures themselves are not changed.
 */
const recorded = fixtures as unknown as {
  siteProfile?: SiteProfileView | null;
  siteProfileHistory?: SiteProfileVersionEntry[] | null;
};

function withSeedMail(profile: SiteProfile): SiteProfile {
  return profile.teams?.length && !profile.mail ? { ...profile, mail: structuredClone(seed.mail) } : profile;
}

/**
 * The seed as the server stores it when its file changes: the recorded profile came from the seed (version 3, one
 * receiver and a site-wide history policy), and the server follows the seed's file until a person saves a profile in
 * the app, so it now holds the seed's version 6 (two receivers, each with its category, CONTRACTS 1.25) as the next
 * stored version. The time is when S22's cases were recorded on a test instance with that seed.
 */
const SEEDED_AT = '2026-10-26T02:13:13Z';

function reseeded(view: SiteProfileView): SiteProfileView {
  const follows = view.source.endsWith(SEED_SOURCE);
  if (!follows || JSON.stringify(view.profile) === JSON.stringify(seed)) return view;
  return {
    ...view,
    profile: structuredClone(seed) as SiteProfile,
    version: view.version + 1,
    updatedAt: SEEDED_AT,
    updatedBy: '',
  };
}

export function recordedSiteProfile(): SiteProfileView | null {
  const view = recorded.siteProfile ? structuredClone(recorded.siteProfile) : null;
  return view ? reseeded({ ...view, profile: withSeedMail(view.profile) }) : null;
}

export function recordedSiteProfileHistory(): SiteProfileVersionEntry[] {
  const history = structuredClone(recorded.siteProfileHistory ?? []).map((v) =>
    v.profile ? { ...v, profile: withSeedMail(v.profile) } : v,
  );
  const now = recordedSiteProfile();
  if (now && !history.some((v) => v.version === now.version))
    history.unshift({
      version: now.version,
      source: now.source,
      updatedAt: now.updatedAt,
      updatedBy: now.updatedBy,
      profile: now.profile,
    });
  return history;
}
