import type { SiteProfile, SiteProfileVersionEntry, SiteProfileView } from '@/api/types';
import fixtures from './fixtures.json';
import seed from '../../../knowledge/site/profile.json';

/**
 * The recorded site profile and its versions, as the demo serves them. The current one was recorded from the seed with
 * its allowed mail domains; older versions in the history were stored before the seed named them, and a profile that
 * names teams with no allowed domains now allows no address, so such a version, restored, takes the seed's. The
 * fixtures themselves are not changed.
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
  // The demo seeds recovery as enabled (CONTRACTS 18).
  return view ? { ...view, profile: { ...withSeedMail(view.profile), recovery: { mode: 'enabled' } } } : null;
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
