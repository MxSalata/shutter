import type { SiteProfile, SiteProfileVersionEntry, SiteProfileView } from '@/api/types';
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

export function recordedSiteProfile(): SiteProfileView | null {
  const view = recorded.siteProfile ? structuredClone(recorded.siteProfile) : null;
  return view ? { ...view, profile: withSeedMail(view.profile) } : null;
}

export function recordedSiteProfileHistory(): SiteProfileVersionEntry[] {
  return structuredClone(recorded.siteProfileHistory ?? []).map((v) =>
    v.profile ? { ...v, profile: withSeedMail(v.profile) } : v,
  );
}
