import type { CaseDetail, SiteProfile, SiteTeam } from '@/api/types';

/*
 * What sending an escalation will do, said before the press (CONTRACTS 10 and 18), and which team the Automatic choice
 * names. Pure, so a table test holds them.
 */

/**
 * Whether a send can leave at all, by the rule the server applies (Shutter.Util.RecoveryControl.MailSuppressed): in shadow
 * mode (any recovery.mode but an explicit "enabled") no email goes and no email file is written, unless the site's
 * notifications.shadow_delivery says "enabled". "unknown" while the profile has not been read.
 */
export function mailOutcome(profile: SiteProfile | null | undefined): 'suppressed' | 'mail' | 'unknown' {
  if (!profile) return 'unknown';
  if (profile.recovery?.mode === 'enabled') return 'mail';
  return profile.notifications?.shadow_delivery === 'enabled' ? 'mail' : 'suppressed';
}

/** The words for shadow mode, before a send and after it. */
export const SHADOW_NO_MAIL =
  'Shutter is in shadow mode, so sending emails nobody and saves no email file: the escalation will read Not sent. To send it, the site enables recovery, or allows email in shadow mode (notifications.shadow_delivery in the site profile), and someone sends it again.';

/** The dialog's first line: what Send does, through the mail server, to a file, or not at all in shadow mode. */
export function sendConsequence(
  outcome: ReturnType<typeof mailOutcome>,
  whom: string,
  again = false,
): string {
  if (outcome === 'suppressed') return SHADOW_NO_MAIL;
  const sends = again ? `This sends the same text to ${whom}` : `This emails ${whom}`;
  const file = `With no mail server set, it is saved as an email file${again ? ' again' : ''} and nobody is emailed.`;
  const shadow = outcome === 'unknown' ? ' In shadow mode nothing is emailed or saved.' : '';
  return `${sends} through the site's mail server. ${file}${shadow}`;
}

/** The toast after a send: what its line will show. */
export function sentNotice(
  outcome: ReturnType<typeof mailOutcome>,
  seq: number,
  again = false,
): { title: string; line: string } {
  if (outcome === 'suppressed')
    return {
      title: `Escalation ${seq} recorded, not sent`,
      line: 'Shadow mode emails nobody and saves no email file, so its line reads Not sent.',
    };
  return {
    title: `Escalation ${seq} queued${again ? ' again' : ''}`,
    line: `Its line shows whether the mail server took it or it was saved as an email file${again ? ' again' : ''}.`,
  };
}

/**
 * The team the Automatic choice drafts for, by the server's rule (Shutter.Util.EscalationDraft.Team): for a merge, the
 * first team whose sources list the case's sending application; else the first whose receivers list the case's receiver;
 * else the site's first team. Undefined with no teams.
 */
export function automaticTeam(
  c: Pick<CaseDetail, 'event' | 'receiver' | 'sourceSystem' | 'operationKey'>,
  teams: SiteTeam[],
): SiteTeam | undefined {
  if (!teams.length) return undefined;
  const source = c.sourceSystem || (c.operationKey ?? '').split('^')[0] || '';
  const bySource = c.event === 'merge' ? teams.find((t) => t.sources?.includes(source)) : undefined;
  return bySource ?? teams.find((t) => t.receivers?.includes(c.receiver ?? '')) ?? teams[0];
}
