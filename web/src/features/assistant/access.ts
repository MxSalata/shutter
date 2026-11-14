import { useMe, useSettings } from '@/api/hooks';
import { TRIAL } from '@/env/mode';
import type { PageAsked } from './store';

/**
 * Who may ask Ask Shutter about a page, and the pieces the page's chat and a question's "Ask Shutter about this" share.
 */

/** The id of a question's heading in the thread, by the question's id. */
export const turnId = (qid: string) => `ask-page-${qid}`;

/** A page with nothing asked yet: one array, so the store's selector returns the same value each time. */
export const NO_ASKED: PageAsked[] = [];

/** Why a page question cannot be asked live, as the server refuses it (403 live_agents_only). */
export const PAGE_JUDGES_ONLY =
  "Questions about a page are answered live only, and that needs the judges' account. The guide below says what this page is and what to try.";

/** Whether the person may ask about the page, and if not, why. */
export interface PageAccess {
  /** A question goes to the server (live, or the trial's mock for its suggested questions). */
  open: boolean;
  /** The free text box takes a question of one's own. */
  free: boolean;
  why: string;
  /** Why no live answer is given, in a few words of its own, where the page's guide is not beside it. */
  short: string;
  badge?: string;
  trial?: boolean;
  /** Who the reader is and how the agents run are both read: until then nothing is decided. */
  ready: boolean;
}

/** Why a reader without the live agents gets no live answer, where the page's guide is not beside it. */
const JUDGES_SHORT = "Live answers need the judges' account.";

/**
 * Who may ask: in the trial, the suggested questions (the mock answers them) and no question of one's own; elsewhere the
 * operator role and the live agents' resource (the server answers 403 to anyone else, so the panel says so first) and a
 * model to answer (a configured provider, or the API mimic on a test instance).
 */
export function usePageAccess(): PageAccess {
  const me = useMe().data;
  const s = useSettings().data;
  const ready = !!me && !!s;
  // The trial's demo role is the live demo's public user, who has no live agents: as on the live demo, where a page has no
  // recorded answers and the server answers 403, its suggested questions are not offered
  if (TRIAL && me?.can?.liveAgents === false)
    return {
      open: false,
      free: false,
      why: PAGE_JUDGES_ONLY,
      short: JUDGES_SHORT,
      badge: 'Judges only',
      ready,
    };
  if (TRIAL)
    return {
      open: true,
      free: false,
      trial: true,
      why: 'Needs a real model: not in the trial.',
      short: 'The trial gives no live answers.',
      ready,
    };
  if (!me?.operator)
    return {
      open: false,
      free: false,
      why: 'Asking needs the operator role.',
      short: 'Asking needs the operator role.',
      ready,
    };
  if (me.can?.liveAgents === false)
    return {
      open: false,
      free: false,
      why: PAGE_JUDGES_ONLY,
      short: JUDGES_SHORT,
      badge: 'Judges only',
      ready,
    };
  if (s && !s.providerConfigured && !s.mock)
    return {
      open: false,
      free: false,
      why: 'Live answers need a model key, and none is configured here. The guide below says what this page is and what to try.',
      short: 'Live answers need a model key, and none is configured here.',
      ready,
    };
  return { open: true, free: true, why: '', short: '', ready };
}
