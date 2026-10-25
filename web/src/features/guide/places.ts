import { useQuery } from '@tanstack/react-query';
import { api } from '@/api/client';
import type { CaseList, CaseSummary, IncidentList, Mode, ReviewList } from '@/api/types';
import type { GuidePlace, GuideStep } from './registry';

/**
 * Where a step leads. A case, incident or review is found among the ones already there, read through the API (in
 * the demo, the recorded ones); when there is none, the step says so and offers to go on. The guide only reads: it
 * never plays a scenario or starts a review to make one.
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

export async function resolvePlace(place: GuidePlace, open?: string): Promise<ResolvedPlace> {
  if ('page' in place) return { path: place.page };
  if ('scenario' in place) {
    const list = await api.get<CaseList>(`/cases?scenario=${encodeURIComponent(place.scenario)}&limit=100`);
    const c = caseOf(list.items, place.scenario, place.mode);
    if (!c) {
      const mode = place.mode ? ` in ${MODE_NAMES[place.mode]} mode` : '';
      return {
        missing: `There is no ${place.scenario} case${mode} here yet. The guide never plays a scenario: play ${place.scenario} from Scenarios yourself if you want one, or go on to the next step.`,
      };
    }
    return { path: `/cases/${encodeURIComponent(c.caseId)}${open ? `?open=${open}` : ''}` };
  }
  if ('incident' in place) {
    const list = await api.get<IncidentList>('/incidents?limit=100');
    const newest = [...list.items].sort((a, b) => b.openedAt.localeCompare(a.openedAt))[0];
    if (!newest)
      return {
        missing:
          'There is no incident here yet: one opens when several deliveries to one receiver fail within a few minutes, as in scenarios S11 and S12. The guide never plays them; go on to the next step.',
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
        'There is no finished production review here yet. Starting one is your own action on Production review; go on to the next step.',
    };
  return { path: `/reviews/${encodeURIComponent(newest.reviewId)}` };
}

/** The step's place, read when the step opens; a read that fails explains itself like a missing case. */
export function usePlace(step: GuideStep | undefined) {
  return useQuery({
    queryKey: ['guide-place', step?.place, step?.open],
    queryFn: async (): Promise<ResolvedPlace> => {
      try {
        return await resolvePlace(step!.place, step!.open);
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
