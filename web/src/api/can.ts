import type { Can, Me } from './types';

/**
 * What the signed-in user may do (`GET /me`, `can`, CONTRACTS v1.34). A server older than that sends no `can`, or only
 * some of it: each missing answer is derived from the operator and approver flags exactly as the screens read them
 * before, so nothing changes for such a server. Nobody signed in may do nothing.
 */
export function resolveCan(me: Me | null | undefined): Can {
  if (!me)
    return {
      operate: false,
      approve: false,
      configure: false,
      scenarios: false,
      reset: false,
      liveAgents: false,
    };
  // Running and resetting scenarios needed the operator role
  const scenarios = me.can?.scenarios ?? me.operator;
  return {
    operate: me.can?.operate ?? me.operator,
    approve: me.can?.approve ?? me.approver,
    // Saving the site profile or the library and annotating a review needed the approver role
    configure: me.can?.configure ?? me.approver,
    scenarios,
    // A server older than 1.4.3 has one right for running and resetting
    reset: me.can?.reset ?? scenarios,
    stopRecovery: me.can?.stopRecovery,
    // A server older than the judges' live agents has no route to convene the board, so nothing offers it
    liveAgents: me.can?.liveAgents ?? false,
  };
}

/**
 * The public demo's role: it approves and rejects, and cannot change the site. Its editors work as an approver's do,
 * and their Save is locked with the demo's note (`saveLocked`); a site's operator, who cannot approve either, reads that
 * only an approver saves.
 */
export const readOnlyDemo = (can: Can): boolean => can.approve && !can.configure;

/**
 * The page is for looking at: the user operates the site but may not run scenarios, as on the public demo, which plays
 * its stories by itself, so its controls are greyed out with the reason said once. A user who cannot operate at all keeps
 * a reason under each control, as does a server that sends no `can` (it derives `scenarios` from `operate`, so this stays false).
 */
export const scenariosHidden = (can: Can): boolean => can.operate && !can.scenarios;

/**
 * Whether the user menu shows the user a role badge: "operator" and "approver" come from GET /me's two flags
 * (AppLayout's UserMenu). The public demo's viewer and a judge have both, so a reason never tells them they need the
 * operator or approver role; it says what their sign-in lacks.
 */
export const showsRoleBadges = (me: Me | null | undefined): boolean => !!me && (me.operator || me.approver);
