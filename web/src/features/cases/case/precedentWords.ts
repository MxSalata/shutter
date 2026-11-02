import type { PrecedentSummary } from '@/api/types';
import { asObject } from '@/lib/json';
import { formatDay, formatInt } from '@/lib/format';

/** The window a precedent counts in when a summary does not say: the server's default (CONTRACTS 6.4). */
export const PRECEDENT_DAYS = 180;

/**
 * The precedents a snapshot summary carries (`precedents`, CONTRACTS 6.4, v1.35), or null when it carries none that
 * can be read: a snapshot collected before v1.35, or one whose collector failed to read them. Nothing is said then.
 */
export function precedentsOf(summary: unknown): PrecedentSummary | null {
  const p = asObject(asObject(summary)?.precedents);
  if (!p || typeof p.error === 'string') return null;
  const approved = Number(p.approved);
  const rejected = Number(p.rejected);
  if (!Number.isFinite(approved) || !Number.isFinite(rejected)) return null;
  const days = Number(p.windowDays);
  return {
    approved,
    rejected,
    lastDecision: p.lastDecision === 'approved' || p.lastDecision === 'rejected' ? p.lastDecision : '',
    lastApprover: typeof p.lastApprover === 'string' ? p.lastApprover : '',
    lastAt: typeof p.lastAt === 'string' ? p.lastAt : '',
    lastCaseId: typeof p.lastCaseId === 'string' ? p.lastCaseId : '',
    samePolicy: p.samePolicy === true,
    windowDays: Number.isFinite(days) && days > 0 ? days : PRECEDENT_DAYS,
    signature: typeof p.signature === 'string' ? p.signature : '',
  };
}

const times = (n: number) => `${formatInt(n)} ${n === 1 ? 'time' : 'times'}`;

/**
 * The precedents in words, in parts so the case can be a link: "Approved and verified 2 times, rejected 0 times here
 * in the last 180 days; last approved by approver on 2 Nov (case C-000301)." and ", under an earlier policy" when the
 * last decision was taken under another policy or site profile; or "No approver has seen these conditions at this
 * receiver in the last 180 days." They say what happened before, never what to do.
 */
export function precedentWords(p: PrecedentSummary): {
  none: boolean;
  lead: string;
  caseId: string;
  tail: string;
} {
  const days = `in the last ${formatInt(p.windowDays)} days`;
  if (p.approved + p.rejected === 0)
    return {
      none: true,
      lead: `No approver has seen these conditions at this receiver ${days}.`,
      caseId: '',
      tail: '',
    };
  const counts = `Approved and verified ${times(p.approved)}, rejected ${times(p.rejected)} here ${days}`;
  const last = [
    p.lastDecision ? `last ${p.lastDecision}` : 'last decided',
    p.lastApprover ? `by ${p.lastApprover}` : '',
    p.lastAt ? `on ${formatDay(p.lastAt)}` : '',
  ]
    .filter(Boolean)
    .join(' ');
  const earlier = p.samePolicy ? '' : ', under an earlier policy';
  return p.lastCaseId
    ? { none: false, lead: `${counts}; ${last} (case `, caseId: p.lastCaseId, tail: `)${earlier}.` }
    : { none: false, lead: `${counts}; ${last}${earlier}.`, caseId: '', tail: '' };
}

/** The whole sentence, as a screen reader and a test read it. */
export function precedentSentence(p: PrecedentSummary): string {
  const w = precedentWords(p);
  return `${w.lead}${w.caseId}${w.tail}`;
}

/**
 * Who retired a precedent and when, from a 409 already_retired: the server names them only in its detail ("Precedent 7
 * was retired on 2026-11-02T10:00:00Z by approver").
 */
export function retiredBy(detail: string): { by: string; at: string } | null {
  const m = /retired on (\S+) by (.+?)\.?$/.exec(detail);
  return m ? { at: m[1], by: m[2] } : null;
}
