import type { CaseDetail, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import { asObject } from '@/lib/json';

/** The evidence behind a case, while it is being read (`undefined`) or when there is none (`null`). */
export type ApprovalEvidence = Snapshot | null | undefined;

/**
 * What an approval changes at the receiver: what the evidence read there and when, and what the write would make it.
 * The reading is as old as the evidence and the receiver may have moved since, which the dispatch gate finds, so it is
 * never worded as what the receiver holds now. Anything missing is said, not guessed.
 */
export function approvalChange(
  c: Pick<CaseDetail, 'event' | 'ward'>,
  snapshot: ApprovalEvidence,
): { held: string; readAt: string; after: string } {
  const read = asObject(asObject(snapshot?.summary)?.ward_state);
  const where = read?.ward ? String(read.ward) : read?.state ? humanize(String(read.state)) : '';
  const known = where && read?.version !== undefined && read.version !== null;
  return {
    held: known
      ? `${where} at version ${String(read.version)}`
      : snapshot === undefined
        ? 'Not read yet'
        : 'Not in the evidence',
    readAt: known ? (snapshot?.takenAt ?? '') : '',
    after: c.ward || `${humanize(c.event)} applied`,
  };
}
