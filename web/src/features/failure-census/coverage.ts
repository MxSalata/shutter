import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, seg } from '@/api/client';

/** The census's totals (CONTRACTS 17): every one is null when the source could not be read, never 0. */
export interface CensusTotals {
  deliveries: number | null;
  completed: number | null;
  notFinished: number | null;
  failures: number | null;
  eligible: number | null;
  exact: number | null;
  none: number | null;
  ambiguous: number | null;
  excluded: number | null;
  unassessable: number | null;
  missingIds: number | null;
  evidenceGaps: number | null;
  distinctCases: number | null;
}

export interface CensusItem {
  deliveryHeaderId: string;
  target: string;
  sessionId: string;
  originHeaderId: string;
  timeCreated: string;
  sourceStatus: string;
  family: string;
  resendOf: string;
  caseIds: string;
  linkQuality: 'exact' | 'ambiguous' | 'none';
  eligibility: 'in_scope' | 'excluded' | 'unknown';
  explanation: string;
}

export interface CensusReport {
  runId: string;
  receiver: string;
  namespace: string;
  window: { from: string; to: string };
  cutoff: string;
  sourceRead: 'ok' | 'unavailable';
  sourceError: string;
  completeness: 'complete' | 'incomplete' | 'unknown';
  reasons: string[];
  scanned: number | null;
  startedAt: string;
  requestedBy: string;
  statement: string;
  totals: CensusTotals;
  items?: CensusItem[];
}

export interface CensusOverview {
  enabled: boolean;
  statement: string;
  maxWindowHours: number;
  maxHeaders: number;
  scopes: { receiver: string; namespace: string; item: string }[];
  items: CensusReport[];
}

/** What each reason code means, for a person reading the report. */
export const REASON_WORDS: Record<string, string> = {
  source_unreadable: 'The source namespace could not be read.',
  header_cap_hit: 'The read stopped at the most headers allowed, so later deliveries were not looked at.',
  case_cap_hit: "The read stopped at the most cases allowed, so some of Shutter's cases were not looked at.",
  header_ids_missing: 'Message headers around this period are gone from the source: purged or deleted.',
  window_older_than_kept_headers: 'This period reaches back past the oldest headers the source keeps.',
  own_messages_purged:
    "Shutter's own message store no longer reaches back to this period, so a link may be lost.",
  case_origin_purged: 'A case in this period names a source header that is gone.',
  body_missing: 'A failed delivery has no case, and its message is gone from the source.',
  settling: 'A failure is too new to say it has no case: its forward may still be on its way.',
  census_failed: 'The census stopped before it finished.',
};

export function useCensusOverview() {
  return useQuery({
    queryKey: ['failure-census'],
    queryFn: () => api.get<CensusOverview>('/failure-census'),
  });
}

export function useCensusReport(runId: string | null) {
  return useQuery({
    queryKey: ['failure-census', runId],
    queryFn: () => api.get<CensusReport>(`/failure-census/${seg(runId ?? '')}`),
    enabled: runId !== null,
  });
}

export function useStartCensus() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      receiver,
      from,
      to,
      idempotencyKey,
    }: {
      receiver: string;
      from: string;
      to: string;
      idempotencyKey: string;
    }) => api.post<CensusReport>('/failure-census', { receiver, from, to }, { idempotencyKey }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: ['failure-census'] });
    },
  });
}

/** A whole second in ISO UTC, as the route asks for. */
export const isoSeconds = (when: Date) => `${when.toISOString().slice(0, 19)}Z`;
