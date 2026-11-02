import type { CaseDetail } from '@/api/types';

/**
 * Whether the case page's Outcome band starts open. It opens for a case a person may still have to act on (waiting for
 * an approval, blocked, escalated, failed, or still running) and stays closed for a closed one (resolved, superseded,
 * handled by hand, abandoned), whose one-line outcome says it all. A reader's own choice is remembered in this browser,
 * one for each of the two kinds, so closing the band on a resolved case keeps resolved cases closed without hiding the
 * next approval. Storage that cannot be read or written (a private window, a full quota) leaves the defaults.
 */
export type BandKind = 'needs' | 'closed';

const KEY = 'shutter.outcomeBand';

/** Which of the two kinds the case is, by its state when the page opened. */
export function bandKind(c: Pick<CaseDetail, 'state' | 'disposition'>): BandKind {
  return c.state === 'resolved' || ['handled_by_hand', 'abandoned'].includes(c.disposition)
    ? 'closed'
    : 'needs';
}

function stored(): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(KEY) ?? '{}');
    return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** The band's first state on a case of this kind: the reader's choice when one is kept, else the kind's default. */
export function bandStartsOpen(kind: BandKind): boolean {
  const choice = stored()[kind];
  return typeof choice === 'boolean' ? choice : kind === 'needs';
}

/** Keeps the reader's choice for cases of this kind; a storage that refuses it changes nothing on the page. */
export function rememberBand(kind: BandKind, open: boolean): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify({ ...stored(), [kind]: open }));
  } catch {
    /* not kept: the band still opens and closes */
  }
}
