import { useSettings } from '@/api/hooks';
import type { SiteProfileView } from '@/api/types';
import { usePageAccess } from '@/features/assistant/access';
import { liveUnavailable, type LiveUnavailable } from '@/lib/liveAgents';

/**
 * Whether Ask Shutter can read a typed answer on Set up the site (CONTRACTS 14.7), and what the page says when it
 * cannot. It needs, in the order the server refuses: the site's own switch (the stored profile's
 * model_content.setup_answers, off unless a person saved it on), the live agents' resource, a model to answer, and the
 * day's budget. Never in the trial, which has no model. Whatever the state, every question keeps its control.
 */
export interface Drafting {
  /** A typed answer can be sent now. */
  can: boolean;
  /**
   * on: it can. off: the site has not switched it on. trial: no model in the trial. unavailable: a reader who may not
   * ask, no model key, or the live agents cannot run now.
   */
  state: 'on' | 'off' | 'trial' | 'unavailable';
  /** Why not, in a sentence; "" when it can. */
  why: string;
  /** The live agents cannot run now: the notice's own state, for its component. */
  notice: LiveUnavailable | null;
  /** Who the reader is and how the agents run are both read. */
  ready: boolean;
}

/** What the page says while the site's switch is off. */
export const DRAFTING_OFF =
  'Reading typed answers is switched off in the site profile (question 11, What the model sees).';

export function useDrafting(base: SiteProfileView | null): Drafting {
  const access = usePageAccess();
  const settings = useSettings().data;
  const ready = access.ready && !!base;
  if (access.trial)
    return { can: false, state: 'trial', why: 'Needs a real model: not in the trial.', notice: null, ready };
  if (base?.profile.model_content?.setup_answers !== true)
    return { can: false, state: 'off', why: DRAFTING_OFF, notice: null, ready };
  if (!access.open || !access.free)
    return { can: false, state: 'unavailable', why: access.short, notice: null, ready };
  const notice = liveUnavailable(settings);
  if (notice)
    return {
      can: false,
      state: 'unavailable',
      why: 'The live agents cannot run now.',
      notice,
      ready,
    };
  return { can: ready, state: 'on', why: '', notice: null, ready };
}

/** What the page says of what is typed, wherever a typed answer can be sent. */
export const TYPED_NOTE =
  "What you type goes to the model with this receiver's name and description, and is kept with the questions log. Do not type patient details, passwords or addresses.";

/** What Ask Shutter does on the page in each state, said plainly under the lead. */
export function draftingLine(d: Drafting): string {
  switch (d.state) {
    case 'on':
      return "Ask Shutter explains each question, and reads an answer typed in your own words: it drafts a receiver's description, and the kind and tier of a receiver being added, for you to review. It sets nothing else and saves nothing.";
    case 'off':
      return `Ask Shutter explains each question here. It does not read typed answers: ${DRAFTING_OFF.charAt(0).toLowerCase()}${DRAFTING_OFF.slice(1)}`;
    case 'trial':
      return 'Ask Shutter explains each question here. It does not read typed answers in the trial, which has no model.';
    default:
      return `Ask Shutter explains each question here. It cannot read typed answers now: ${d.why.charAt(0).toLowerCase()}${d.why.slice(1)}`;
  }
}
