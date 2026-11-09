import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, seg } from './client';
import { keys, useCasePart } from './hooks';
import type {
  CorrectionDraftView,
  FurtherStop,
  ReceiverCheck,
  RecoveryControl,
  WarehouseHistoryView,
} from './types';

/*
 * The hooks of the pilot features (history correction, warehouse history, a released stop, the recovery switch, what to
 * check at the receiver), apart from api/hooks.ts: only the lazy pages that use them load them, so the shell's entry
 * chunk stays within its budget (e2e/trial.spec.ts).
 */

/**
 * Reads the drafted correction's text (CONTRACTS 10). A mutation, though it is a GET: the server records every read of
 * a drawn draft on the case, so only a person's click may send one, never a refresh or an invalidation. Nothing keeps
 * the text once the block is gone.
 */
export function useReadCorrectionDraft(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.get<CorrectionDraftView>(`/cases/${seg(caseId)}/correction-draft`),
    gcTime: 0,
    onSuccess: () => client.invalidateQueries({ queryKey: keys.part(caseId, 'events') }),
  });
}

/** Warehouse history's newest read, and whether it is on at all. A server older than the route answers 404, read as null. */
export const useWarehouseHistory = (id: string) =>
  useCasePart<WarehouseHistoryView>(id, 'warehouse-history', '/warehouse-history', false);

/** Read warehouse history now, when a person asks. It changes nothing on the case. */
export function useReadWarehouseHistory(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.post<WarehouseHistoryView>(`/cases/${seg(caseId)}/warehouse-history`),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: keys.part(caseId, 'warehouse-history') });
    },
  });
}

/** The rows that stop a write for another visit's movement, read afresh, with the digest a release must name (CONTRACTS 6.5). */
export function useFurtherStop(caseId: string, enabled: boolean) {
  return useQuery({
    queryKey: keys.part(caseId, 'further-stop'),
    enabled,
    queryFn: () => api.get<FurtherStop>(`/cases/${seg(caseId)}/further-stop`),
  });
}

/**
 * An approver releases that one stop for the rows they read, with a reason. 409 rows_changed when a fresh read gives other
 * rows, not_releasable when the stop isn't only another visit's movement. The case then goes through fresh evidence.
 */
export function useFurtherRelease(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      digest,
      reason,
      idempotencyKey,
    }: {
      digest: string;
      reason: string;
      idempotencyKey: string;
    }) =>
      api.post<{ caseId: string; state: string }>(
        `/cases/${seg(caseId)}/further-release`,
        { digest, reason },
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
    },
  });
}

export function useStopRecovery() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: { reason: string }) => api.post<RecoveryControl>('/recovery-control/stop', body),
    onSuccess: (data) => client.setQueryData(keys.recoveryControl, data),
  });
}

export function useClearRecovery() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: { reason: string; expectedGeneration: number }) =>
      api.post<RecoveryControl>('/recovery-control/clear', body),
    onSuccess: (data) => client.setQueryData(keys.recoveryControl, data),
  });
}

/** What to check at the receiver (GET /cases/{id}/receiver-check): no model and no receiver call, read when it is opened. */
export function useReceiverCheck(caseId: string, enabled = true) {
  return useCasePart<ReceiverCheck>(caseId, 'receiver-check', '/receiver-check', false, enabled);
}
