import type { CaseSummary } from '@/api/types';

/**
 * The facts Technical shows of a case's message, route, trace and plan, as the cases list and the case header word them
 * (CONTRACTS 5, the Technical detail). Each reads only what the server sent, and is empty when it sent nothing.
 */

/** The failure as the receiver answered it, "503 ward_unavailable"; empty when it gave no answer. */
export function failureCode(c: Pick<CaseSummary, 'failureHttpStatus' | 'failureReasonCode'>): string {
  return [c.failureHttpStatus ? String(c.failureHttpStatus) : '', c.failureReasonCode ?? '']
    .filter(Boolean)
    .join(' ');
}

/** A digest's first twelve characters, without its algorithm: "sha256:c32d519e968bb1ce..." reads "c32d519e968b". */
export function digestPrefix(digest: string | undefined | null): string {
  if (!digest) return '';
  const at = digest.indexOf(':');
  return (at >= 0 ? digest.slice(at + 1) : digest).slice(0, 12);
}

/** The current plan as Technical names it, "v2 c32d519e968b"; empty for a case with no plan. */
export function planLabel(c: Pick<CaseSummary, 'planVersion' | 'planDigest'>): string {
  return [c.planVersion ? `v${c.planVersion}` : '', digestPrefix(c.planDigest)].filter(Boolean).join(' ');
}

/** The catalogue entry of the case's plan, else the one the site's policy named when it made the plan. */
export function catalogueEntryOf(c: Pick<CaseSummary, 'catalogueEntry' | 'planCreatedBy'>): string {
  if (c.catalogueEntry) return c.catalogueEntry;
  return c.planCreatedBy?.startsWith('policy:') ? c.planCreatedBy.slice('policy:'.length) : '';
}

/** A time in UTC to the millisecond, as the Management Portal's trace shows it: "14:36:12.707Z"; with the date in front when asked. */
export function utcMillis(iso: string | undefined | null, withDate = false): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const s = d.toISOString();
  return withDate ? `${s.slice(0, 10)} ${s.slice(11, 23)}Z` : `${s.slice(11, 23)}Z`;
}

/** The Management Portal's base path, from the case's Visual Trace link ("/csp/healthshare/shutter/"); empty without one. */
export function portalBaseOf(c: Pick<CaseSummary, 'links'>): string {
  const trace = c.links?.visualTrace ?? '';
  const at = trace.indexOf('EnsPortal.');
  return at > 0 ? trace.slice(0, at) : '';
}

/** The Management Portal's page of one message, by its header id. */
export function messageContentsLink(base: string, headerId: string): string {
  return `${base}EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(headerId)}`;
}
