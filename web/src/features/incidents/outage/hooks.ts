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

/** A person's act on an outage, with the row's version (CONTRACTS 17.3 and 17.8). */
export interface OutageActBody {
  act: string;
  until?: string;
  reason?: string;
  /** For `handled_by_hand`: the offered message, and what was checked at the receiver. */
  headerId?: string;
  note?: string;
  version?: number;
}

/**
 * A person's act on an outage (Shutter_Approve): pause until a time, read the set again, close with a reason, or close one
 * offered message as already handled by hand. An Idempotency-Key, when given, replays the first answer.
 */
export function useOutageAct(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ idempotencyKey, ...body }: OutageActBody & { idempotencyKey?: string }) =>
      api.post<Outage>(`/outages/${seg(id)}/acts`, body, { idempotencyKey }),
    onSuccess: () => client.invalidateQueries({ queryKey: KEY }),
  });
}

/** The approval of an offered set (CONTRACTS 17.8): the digest it names, a note, and at a receiver whose duplicates are unknown, receiverChecked. */
export interface OutageApprovalBody {
  digest: string;
  note: string;
  version: number;
  receiverChecked?: boolean;
}

/** One approval: the engine then sends each offered message again, in order, from Shutter's production. */
export function useApproveOutage(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ idempotencyKey, ...body }: OutageApprovalBody & { idempotencyKey: string }) =>
      api.post<Outage>(`/outages/${seg(id)}/approvals`, body, { idempotencyKey }),
    // A refusal (the set or the row moved on) reads the row again too, so the card shows what it is now
    onSettled: () => client.invalidateQueries({ queryKey: KEY }),
  });
}
