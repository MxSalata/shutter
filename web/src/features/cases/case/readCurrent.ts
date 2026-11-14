import { useMutation, useQueryClient } from '@tanstack/react-query';
import { api, seg } from '@/api/client';
import { keys } from '@/api/hooks';
import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
import { isApiError } from '@/lib/errors';

/**
 * The case, its plan and its evidence read from the server at the press, for the review that replaces one the case
 * moved under (a stale plan or case version). Nothing comes from what the page read before: each read goes to the
 * server and lands in the page's cache under the page's own keys, so the page shows what the new review opens on. A
 * plan or evidence the server answers 404 for reads as null, as the page reads it. A failed read is said at once, with
 * no retry behind it, since a person is waiting on it. A read, never a write: it sends no decision and carries none
 * over. It lives with the case page, not in the shared hooks, so it adds nothing to the entry chunk.
 */
export function useReadCurrentReview(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const path = `/cases/${seg(caseId)}`;
      const part = <T>(name: string, rest: string) =>
        client.fetchQuery({
          queryKey: keys.part(caseId, name),
          queryFn: async (): Promise<T | null> => {
            try {
              return await api.get<T>(`${path}${rest}`);
            } catch (e) {
              if (isApiError(e) && e.isNotFound) return null;
              throw e;
            }
          },
          staleTime: 0,
          retry: false,
        });
      const [c, view, snapshot] = await Promise.all([
        client.fetchQuery({
          queryKey: keys.case(caseId),
          queryFn: () => api.get<CaseDetail>(path),
          staleTime: 0,
          retry: false,
        }),
        part<PlanView>('plan', '/plan'),
        part<Snapshot>('snapshot', '/snapshot'),
      ]);
      return { c, view, snapshot };
    },
  });
}
