import { useQuery } from '@tanstack/react-query';
import { api } from '@/api/client';
import type { CaseList, CaseSummary, IncidentList, Mode, ReviewList } from '@/api/types';
import type { GuidePlace, GuideStep } from './registry';

/**
 * Where a step leads. A case, incident or review is found among the recorded ones, read through the API (the guide
 * runs only in the trial, so every place of the quick tour resolves); the "not here" answer stays only as a safeguard.
 * A case's address can open a story step (`?open=`) and a tab (`?tab=`); a page's place may carry its own query.
 */
export type ResolvedPlace = { path: string } | { missing: string };

const MODE_NAMES: Record<Mode, string> = {
  board: 'board',
  policy: 'Site policy',
  single: 'Single investigator',
  rules: 'Rules only',
};

const newestFirst = (a: CaseSummary, b: CaseSummary) => b.openedAt.localeCompare(a.openedAt);

/** The scenario's newest case in the mode; with no mode, the newest in board mode if there is one, else any. */
export function caseOf(cases: CaseSummary[], scenario: string, mode?: Mode): CaseSummary | undefined {
  const of = cases.filter((c) => c.scenario === scenario).sort(newestFirst);
  if (mode) return of.find((c) => c.mode === mode);
  return of.find((c) => c.mode === 'board') ?? of[0];
}

export async function resolvePlace(place: GuidePlace, open?: string, tab?: string): Promise<ResolvedPlace> {
  if ('page' in place) return { path: place.page };
  if ('scenario' in place) {
    const list = await api.get<CaseList>(`/cases?scenario=${encodeURIComponent(place.scenario)}&limit=100`);
    const c = caseOf(list.items, place.scenario, place.mode);
    if (!c) {
      const mode = place.mode ? ` in ${MODE_NAMES[place.mode]} mode` : '';
      return {
        missing: `There is no ${place.scenario} case${mode} here yet. Run ${place.scenario} from Scenarios if you want one, or go on to the next step.`,
      };
    }
    const query = [open ? `open=${open}` : '', tab ? `tab=${tab}` : ''].filter(Boolean).join('&');
    return { path: `/cases/${encodeURIComponent(c.caseId)}${query ? `?${query}` : ''}` };
  }
  if ('incident' in place) {
    const list = await api.get<IncidentList>('/incidents?limit=100');
    const newest = [...list.items].sort((a, b) => b.openedAt.localeCompare(a.openedAt))[0];
    if (!newest)
      return {
        missing:
          'There is no incident here yet: one opens when several deliveries to one receiver fail within a few minutes, as in scenarios S11 and S12. Go on to the next step.',
      };
    return { path: `/incidents/${encodeURIComponent(newest.incidentId)}` };
  }
  const list = await api.get<ReviewList>('/production-reviews');
  const newest = list.items
    .filter((r) => r.state === 'done')
    .sort((a, b) => b.startedAt.localeCompare(a.startedAt))[0];
  if (!newest)
    return {
      missing:
        'There is no finished production review here yet. Start one on Production review, or go on to the next step.',
    };
  return { path: `/reviews/${encodeURIComponent(newest.reviewId)}` };
}

/** The step's place, read when the step opens; a read that fails explains itself like a missing case. */
export function usePlace(step: GuideStep | undefined) {
  return useQuery({
    queryKey: ['guide-place', step?.place, step?.open, step?.tab],
    queryFn: async (): Promise<ResolvedPlace> => {
      try {
        return await resolvePlace(step!.place, step!.open, step!.tab);
      } catch {
        return {
          missing:
            'The page for this step could not be found just now. Go on to the next step, or try again later.',
        };
      }
    },
    enabled: !!step,
    staleTime: 15_000,
    retry: false,
  });
}
