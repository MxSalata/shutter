import type { PathologyPath, ScenarioRun } from '@/api/types';
import { ORDERS_RESULTS_BRIEF } from '@/lib/categories';
import { SCENARIOS_DEFINED } from './scenarioText';

/**
 * The pathology paths on the online demo (1.4.6, clarity item 7): P1, a result the demo's results system refuses, and P2,
 * an outage of that receiver, played through the demo hospital's results route. They are counted apart from the
 * scenarios, offered only where the server lists them (a live demo with the route installed; never the trial, whose
 * outage routes answer not_in_trial), and say what runs: no agent and no model. A refused result goes to a person with
 * no resend; an outage's messages go again only after one approval, and Completed is the engine's word, not a check at
 * the receiver. The words reuse the orders-and-results brief the Site profile's card says.
 */
export const PATHOLOGY_WORDS = {
  title: 'Pathology on the demo (optional)',
  lead: `Two paths on the demo hospital's results route, counted apart from the ${SCENARIOS_DEFINED} scenarios. No agent runs and no model is called. ${ORDERS_RESULTS_BRIEF}`,
  link: 'Optional, after these three: pathology on the demo, a refused result and a receiver outage.',
  notPlayed: 'Not played yet',
  /** P2 is refused while the last run's outage is open: each run opens its own (Shutter.Scenarios.Runner, PathologyRefusal). */
  outageOpen: 'P2 runs again once this outage is closed: approve its resend or close it on Incidents.',
  noAgent: 'No agent runs on this path and no model is called.',
  /** Between the press of Run and the server's answer. */
  starting:
    'Asking the scenario player to start it. No agent runs and no model is called. A link to what it opens, its case or its outage, appears here once it has played.',
} as const;

/** Where the group starts, for the link after the main route. */
export const PATHOLOGY_ANCHOR = 'pathology';

/** Whether a run is one of the pathology paths. */
export const isPathologyRun = (run: ScenarioRun | null | undefined, paths: PathologyPath[] | undefined) =>
  !!run && !!paths?.some((p) => p.id === run.scenario);
