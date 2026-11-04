import type { Can, Me } from './types';

/**
 * What the signed-in user may do (`GET /me`, `can`, CONTRACTS v1.34). A server older than that sends no `can`, or only
 * some of it: each missing answer is derived from the operator and approver flags exactly as the screens read them
 * before, so nothing changes for such a server. Nobody signed in may do nothing.
 */
export function resolveCan(me: Me | null | undefined): Can {
  if (!me) return { operate: false, approve: false, configure: false, scenarios: false, liveAgents: false };
  return {
    operate: me.can?.operate ?? me.operator,
    approve: me.can?.approve ?? me.approver,
    // Saving the site profile or the library and annotating a review needed the approver role
    configure: me.can?.configure ?? me.approver,
    // Running and resetting scenarios needed the operator role
    scenarios: me.can?.scenarios ?? me.operator,
    // A server older than the judges' live agents has no route to convene the board, so nothing offers it
    liveAgents: me.can?.liveAgents ?? false,
  };
}

/**
 * The public demo's role: it approves and rejects, and cannot change the site. The screens keep what it may read (a
 * pre-filled draft, the review of a change) and replace Save with a note saying so. A site's operator, who cannot
 * approve either, keeps the plain "needs the approver role" notes.
 */
export const readOnlyDemo = (can: Can): boolean => can.approve && !can.configure;

/** The note that stands where Save would be on the online demo. */
export const DEMO_READ_ONLY = "On the online demo you can approve or reject plans; a site's approver saves changes here";

/**
 * The scenario controls are not offered: the user operates the site but may not run scenarios, as on the public demo,
 * which plays its stories by itself. A user who cannot operate at all keeps the disabled controls and their reasons, as
 * does a server that sends no `can` (it derives `scenarios` from `operate`, so this stays false).
 */
export const scenariosHidden = (can: Can): boolean => can.operate && !can.scenarios;
