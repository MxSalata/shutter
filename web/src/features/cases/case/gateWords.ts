import { humanize } from '@/lib/format';
import { checkState } from '@/lib/status';

type Check = { check: string; result: string; reason_code?: string };

const LABELS: Record<string, string> = { pass: 'Passed', block: 'Blocked', unknown: 'Unknown' };

/**
 * The gate's word on the receipt. At the proposal stage the gate passes authorization and rehearsal without checking
 * them (NOT_YET_REQUIRED), so "Passed" beside "2 checked later" would claim more than it did.
 */
export function gateFactLabel(
  outcome: string,
  checks: Check[],
  state: string,
  writesNothing: boolean,
): string | undefined {
  if (outcome !== 'pass') return LABELS[outcome];
  if (writesNothing) return 'Passed: no write';
  if (!checks.some((c) => checkState(c) === 'later')) return LABELS.pass;
  return state === 'awaiting_approval' ? 'Eligible for approval' : 'Passed so far';
}

/** The checks of a later stage, by name: "Checked at dispatch: authorization, rehearsal."; empty when none is left. */
export function laterChecksLine(checks: Check[]): string {
  const later = checks.filter((c) => checkState(c) === 'later').map((c) => humanize(c.check).toLowerCase());
  return later.length ? `Checked at dispatch: ${later.join(', ')}.` : '';
}
