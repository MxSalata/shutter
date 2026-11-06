import type { CaseDetail, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import { asObject } from '@/lib/json';

/**
 * What an approval changes at the receiver: what the evidence observed there and when, what the write would make it,
 * and the condition it goes on. From the evidence and the plan only; anything missing is said, not guessed.
 */
export function approvalChange(
  c: Pick<CaseDetail, 'event' | 'ward'>,
  expectedVersion: unknown,
  snapshot: Snapshot | null | undefined,
): { before: string; readAt: string; after: string } {
  const held = asObject(asObject(snapshot?.summary)?.ward_state);
  const where = held?.ward ? String(held.ward) : held?.state ? humanize(String(held.state)) : '';
  const known = where && held?.version !== undefined && held.version !== null;
  return {
    before: known
      ? `${where} at version ${String(held.version)}`
      : snapshot === undefined
        ? 'Not read yet'
        : 'Not in the evidence',
    readAt: known ? (snapshot?.takenAt ?? '') : '',
    after: `${c.ward || `${humanize(c.event)} applied`}, only if the receiver is still at version ${String(expectedVersion)} when it is read again`,
  };
}
