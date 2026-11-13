import type { CaseSummary, Mode, ScenarioRun } from '@/api/types';
import { PROVENANCE } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { REPLAY_ONLY } from './scenarioText';

/**
 * How a scenario run executes, said apart from who proposes its plan. The mode names the proposer (the board, the
 * site's policy, one investigator, the rules); it never says whether a model was called. That is read from what the
 * run itself records, never from the address or the account:
 *
 * - the trial's page answers every call from a recording in the browser, so nothing runs there at all;
 * - on IRIS, a run the server marks `replay` had its agents answer from their recordings;
 * - any other run on IRIS is labelled from its own case's agent runs once they exist (`ranOnIris`), so a run that
 *   fell back to recordings is never called live, and until then nothing is claimed.
 */
export const EXECUTION = {
  /** Under the modes, before how runs execute here. */
  lead: 'The mode says who proposes the plan, not how a run executes.',
  /** The trial: every run is a recording shown in the browser. */
  trial:
    'Here every run plays a recording in your browser, Board included: no new inference, and nothing reaches IRIS.',
  /** The way to live agents from the trial. */
  trialRoute:
    "Agents that call a model run on your own install with a model key, and from the judges' sign-in on the online demo.",
  /** A sign-in without the live agents, on IRIS (1.4.4, the online demo's account): scenario runs only, not every feature. */
  replay: REPLAY_ONLY.line,
  /** The way to live agents from such a sign-in. */
  replayRoute:
    "Live agents run from a sign-in that has them (on the online demo, the judges' account) and on your own install with a model key.",
  /** A sign-in with the live agents: nothing is promised before the run; its case says what ran. */
  live: 'From this sign-in the agents run as this install is set. Each case then says what ran: Live model only when a model was called, Recorded replay when its agents answered from their recordings.',
} as const;

/** Why the single investigator cannot be chosen, and the way to it: it has no recordings, so it runs live only. */
export const SINGLE_ROUTE = {
  trial: "To run it: your own install with a model key, or the judges' sign-in on the online demo.",
  replay:
    "To run it: a sign-in with the live agents (the judges' account), or your own install with a model key.",
} as const;

/** How one run executed: the badge, from the provenance vocabulary, and the sentence beside it. */
export interface RunExecution {
  status?: Status;
  words: string;
}

/**
 * How a run executes or executed, for its banner. `ofCase` is the provenance of the run's own case, read from that
 * case's agent runs, when it is known: only it can say a model was called.
 */
export function runExecution(
  run: Pick<ScenarioRun, 'replay' | 'state'>,
  trial: boolean,
  ofCase?: Status,
): RunExecution {
  const over = run.state === 'done';
  if (trial)
    return {
      status: PROVENANCE.recording,
      words: over
        ? 'Played from its recording in your browser: no new inference, and nothing reached IRIS.'
        : 'Playing from its recording in your browser: no new inference.',
    };
  if (run.replay)
    return {
      status: PROVENANCE.replay,
      words: over
        ? 'Its agents answered from their recordings on this IRIS instance: no new inference, nothing spent.'
        : 'Its agents answer from their recordings on this IRIS instance: no new inference.',
    };
  if (ofCase && ofCase.label !== 'Unknown')
    return { status: ofCase, words: ofCase.hint ? `${ofCase.hint}.` : '' };
  return { words: 'Its case says what ran: live only when a model was called.' };
}

const opened = (c: CaseSummary) => Date.parse(c.openedAt);

/**
 * The run's own case among the cases read, newest first, or none. On IRIS it is a case of the run's scenario and mode
 * opened at or after the run started: the scenario's latest case is the previous run's until the new one opens, and
 * that one is never offered as this run's. The trial's cases are the recording's, opened when it was made, so there it
 * is the recorded case of the scenario in the run's mode.
 */
export function runCase(
  cases: CaseSummary[],
  run: Pick<ScenarioRun, 'scenario' | 'mode' | 'startedAt'>,
  trial: boolean,
): CaseSummary | undefined {
  const started = Date.parse(run.startedAt);
  return cases
    .filter((c) => c.scenario === run.scenario && c.mode === run.mode)
    .filter((c) => trial || (!Number.isNaN(started) && opened(c) >= started))
    .sort((a, b) => opened(b) - opened(a) || b.caseId.localeCompare(a.caseId))[0];
}

/** The short route: S2's recovery, then S3's reconciliation and S8's escalation, each in Board mode. */
export const ROUTE: readonly string[] = ['S2', 'S3', 'S8'];
export const ROUTE_MODE: Mode = 'board';

/**
 * What to look at on the run's case and what comes next on the short route, for a run of one of its three in the
 * route's mode; null for any other scenario or mode, which has no next step to offer. The words name parts of the case
 * page as it names them (the outcome, The board, the decision receipt). Nothing here starts a run: the next step is a
 * card to choose.
 */
export function routeNext(scenario: string, mode: Mode): { look: string; next: string } | null {
  if (mode !== ROUTE_MODE) return null;
  if (scenario === 'S2')
    return {
      look: "On its case: decide on the resend. The outcome then says what was written and how the receiver's own history verified it, and The board has each agent's finding.",
      next: 'Next on the short route: S3, in its card below.',
    };
  if (scenario === 'S3')
    return {
      look: "On its case: the outcome says nothing was sent, since the receiver already had the transfer, and The board has each agent's finding.",
      next: 'Next on the short route: S8, in its card below.',
    };
  if (scenario === 'S8')
    return {
      look: "On its case: the outcome says a person decides and nothing was written, and The board has each agent's finding and any dissent it kept.",
      next: 'That is the short route. S20 below shows the approval boundary, and every scenario is listed under it.',
    };
  return null;
}
