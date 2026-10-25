import {
  useApprovals,
  useAttempts,
  useBlockedReason,
  useClosure,
  useEscalations,
  usePlan,
  useRuns,
  useSnapshot,
} from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import type { CaseFacts } from './outcome';
import { safetyReceipt } from './receipt';

/** The case's facts as the top of the page reads them; the queries are the ones the tabs read too. */
export function useCaseFacts(c: CaseDetail, open: boolean): CaseFacts {
  const stopped = c.state === 'blocked' || c.state === 'escalated';
  const handled = c.state === 'resolved' && c.disposition === 'handled_by_hand';
  const plan = usePlan(c.caseId, open);
  const approvals = useApprovals(c.caseId, open);
  const attempts = useAttempts(c.caseId, open);
  const closure = useClosure(c.caseId, !open);
  const snapshot = useSnapshot(c.caseId, open);
  const blocked = useBlockedReason(c.caseId, stopped);
  const escalations = useEscalations(c.caseId, stopped || handled);
  const runs = useRuns(c.caseId, open);
  // Approvals not read stay undefined, so who released a write reads unknown rather than "not approved"
  const approvalsRead = approvals.isSuccess ? approvals.data : undefined;
  const receipt = safetyReceipt({
    c,
    plan: plan.data,
    approvals: approvalsRead,
    attempts: attempts.data,
    closure: closure.data,
    snapshot: snapshot.data,
  });
  // A part not read yet stays undefined, so the sentences say unknown instead of guessing
  return {
    c,
    receipt,
    plan: plan.isSuccess ? plan.data : undefined,
    planError: plan.isError ? plan.error : undefined,
    retryPlan: () => void plan.refetch(),
    approvals: approvalsRead,
    attempts: attempts.isSuccess ? attempts.data : undefined,
    blocked: blocked.isSuccess ? blocked.data : stopped ? undefined : null,
    snapshot: snapshot.data,
    escalations: escalations.isSuccess ? escalations.data : undefined,
    runs: runs.isSuccess ? runs.data : undefined,
    runsSettled: runs.isSuccess || runs.isError,
  };
}
