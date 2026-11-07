import type { CaseDetail } from '@/api/types';

/** The case whose board a plan's decision came from: a follower's plan is `lead:<case>` (CONTRACTS 6.6). */
export function planLeader(createdBy: string | null | undefined): string {
  return createdBy?.startsWith('lead:') ? createdBy.slice('lead:'.length) : '';
}

/**
 * The board a case follows: while it waits, `followsCase` names the leader, and the workflow clears that once the
 * decision is taken, when the plan's author names it instead. A case that fell to the rules path follows nobody.
 */
export function followedBoard(
  c: Pick<CaseDetail, 'followsCase' | 'planCreatedBy'>,
): { caseId: string; note: string } | null {
  if (c.followsCase)
    return { caseId: c.followsCase, note: 'Waiting for its decision; keeps its own gate and approval' };
  const leader = planLeader(c.planCreatedBy);
  return leader ? { caseId: leader, note: 'Took its decision; keeps its own gate and approval' } : null;
}
