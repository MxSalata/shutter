import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, seg } from '@/api/client';
import type { Outage, OutageList } from './types';

/*
 * The outage routes' hooks, kept with the incidents page that alone uses them, so the shell's entry chunk stays within its
 * budget. A server or trial with no outage routes (404, or 501 not_in_trial) reads as "no outages, nothing watched".
 */

const KEY = ['outages'] as const;

function absent(e: unknown): boolean {
  const status = (e as { status?: number } | null)?.status;
  return status === 404 || status === 501;
}

/** Every outage, open or closed, and one reading per watched receiver; null when this server has no outage routes. */
export function useOutages() {
  return useQuery({
    queryKey: KEY,
    queryFn: async (): Promise<OutageList | null> => {
      try {
        return await api.get<OutageList>('/outages?state=all');
      } catch (e) {
        if (absent(e)) return null;
        throw e;
      }
    },
    refetchInterval: (q) => (q.state.data?.items.some((o) => o.state !== 'closed') ? 5_000 : 15_000),
  });
}

/** A person's act on an outage: pause until a time, read the set again, or close with a reason (Shutter_Approve). */
export function useOutageAct(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: { act: string; until?: string; reason?: string; version?: number }) =>
      api.post<Outage>(`/outages/${seg(id)}/acts`, body),
    onSuccess: () => client.invalidateQueries({ queryKey: KEY }),
  });
}
