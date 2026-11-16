import { useMutation, useQuery } from '@tanstack/react-query';
import { api, newIdempotencyKey, seg } from './client';
import { isAnswering } from './hooks';
import type { SendSetupTurn, SetupTurnAsked, SetupTurnView } from './types';

/*
 * The hooks of Set up the site's typed answers (CONTRACTS 14.7), apart from api/hooks.ts: only the lazy page that uses
 * them loads them, so the shell's entry chunk stays within its budget (e2e/trial.spec.ts). Nothing here stores a
 * profile: the route keeps the turn's own row.
 */

const turnKey = (id: string) => ['setup-turn', id] as const;

/** Sends what a person typed about a receiver: 202 with the turn's id, then useSetupTurn reads what was drafted. */
export function useSendSetupTurn() {
  return useMutation({
    mutationFn: ({
      turn,
      idempotencyKey,
    }: {
      turn: SendSetupTurn;
      idempotencyKey?: string;
      /** What to do with the 202: run by the mutation itself, so it runs even when the card that sent it has closed. */
      accepted?: (asked: SetupTurnAsked) => void;
    }) =>
      api.post<SetupTurnAsked>('/site-profile/setup-turns', turn, {
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      }),
    onSuccess: (asked, { accepted }) => accepted?.(asked),
  });
}

/** One turn of Set up the site, read every 2 s until it is answered or refused. */
export function useSetupTurn(turnId: string | undefined) {
  return useQuery({
    queryKey: turnKey(turnId ?? ''),
    enabled: !!turnId,
    queryFn: () => api.get<SetupTurnView>(`/site-profile/setup-turns/${seg(turnId!)}`),
    refetchInterval: (q) => (isAnswering(q.state.data?.state) ? 2_000 : false),
  });
}
