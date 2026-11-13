import { describe, expect, it } from 'vitest';
import type { CaseSummary } from '@/api/types';
import { PROVENANCE } from '@/lib/status';
import { EXECUTION, ROUTE, routeNext, runCase, runExecution, SINGLE_ROUTE } from './execution';
import { REPLAY_ONLY } from './scenarioText';

const summary = (caseId: string, scenario: string, mode: string, openedAt: string) =>
  ({ caseId, scenario, mode, openedAt }) as unknown as CaseSummary;

describe('how a run executes, apart from who proposes', () => {
  it("calls the trial's run a browser recording with no new inference, whatever the run's own mark says", () => {
    for (const replay of [true, false, undefined]) {
      const how = runExecution({ replay, state: 'done' }, true);
      expect(how.status).toBe(PROVENANCE.recording);
      expect(how.words).toBe(
        'Played from its recording in your browser: no new inference, and nothing reached IRIS.',
      );
    }
    expect(runExecution({ state: 'running' }, true).words).toBe(
      'Playing from its recording in your browser: no new inference.',
    );
  });

  it('calls a run the server marked as a replay a recorded replay on IRIS, with no new inference', () => {
    const how = runExecution({ replay: true, state: 'done' }, false);
    expect(how.status).toBe(PROVENANCE.replay);
    expect(how.words).toBe(
      'Its agents answered from their recordings on this IRIS instance: no new inference, nothing spent.',
    );
    // A case that says live cannot overrule the server's own mark
    expect(runExecution({ replay: true, state: 'done' }, false, PROVENANCE.live).status).toBe(
      PROVENANCE.replay,
    );
  });

  it("calls a run live only when its own case's agent runs say a model was called", () => {
    // Not marked as a replay, and no case yet: nothing is claimed, least of all live
    const before = runExecution({ replay: false, state: 'running' }, false);
    expect(before.status).toBeUndefined();
    expect(before.words).toBe('Its case says what ran: live only when a model was called.');
    // Its case's runs were all recordings (the install replays, or the run fell back): a recorded replay, never live
    const fellBack = runExecution({ replay: false, state: 'done' }, false, PROVENANCE.replay);
    expect(fellBack.status).toBe(PROVENANCE.replay);
    expect(fellBack.words).toBe('Replayed from a recorded live run: no model was called now.');
    // A model was called, as the case's runs record
    const live = runExecution({ replay: false, state: 'done' }, false, PROVENANCE.live);
    expect(live.status).toBe(PROVENANCE.live);
    expect(live.words).toBe('A model was called for this run.');
    // While the case's runs are still being read
    expect(
      runExecution({ replay: false, state: 'done' }, false, { tone: 'neutral', label: 'Unknown' }).status,
    ).toBeUndefined();
  });

  it('keeps the words about replays to scenario runs, and says the way to live agents', () => {
    expect(EXECUTION.replay).toBe(REPLAY_ONLY.line);
    expect(EXECUTION.replay).toMatch(/^Scenario runs from this sign-in replay the recorded agents/);
    expect(EXECUTION.replay).toContain('no new inference');
    expect(EXECUTION.trial).toContain('no new inference');
    // Nothing says the account or the page makes no model call at all: chat has its own labels
    for (const words of Object.values(EXECUTION)) expect(words).not.toMatch(/no model (call|is called)/);
    expect(EXECUTION.trialRoute).toMatch(/your own install with a model key/);
    expect(EXECUTION.replayRoute).toMatch(/your own install with a model key/);
    expect(SINGLE_ROUTE.trial).toMatch(/^To run it: /);
    expect(SINGLE_ROUTE.replay).toMatch(/^To run it: /);
  });
});

describe("the run's own case", () => {
  const run = { scenario: 'S2', mode: 'board' as const, startedAt: '2026-11-13T10:00:00Z' };

  it('is a case of its scenario and mode opened at or after the run started, never an earlier one', () => {
    const earlier = summary('C-000010', 'S2', 'board', '2026-11-13T09:59:59Z');
    // Before the run's case opens, the scenario's latest case is the previous run's: it is not offered
    expect(runCase([earlier], run, false)).toBeUndefined();
    const own = summary('C-000011', 'S2', 'board', '2026-11-13T10:00:04Z');
    expect(runCase([earlier, own], run, false)).toBe(own);
    // The same second counts: both times are to the second
    const same = summary('C-000012', 'S2', 'board', '2026-11-13T10:00:00Z');
    expect(runCase([same], run, false)).toBe(same);
  });

  it("leaves out another scenario's case, another mode's, and one with an unreadable time", () => {
    const cases = [
      summary('C-000020', 'S3', 'board', '2026-11-13T10:00:05Z'),
      summary('C-000021', 'S2', 'rules', '2026-11-13T10:00:05Z'),
      summary('C-000022', 'S2', 'board', 'not a time'),
    ];
    expect(runCase(cases, run, false)).toBeUndefined();
    expect(runCase(cases, { ...run, startedAt: '' }, false)).toBeUndefined();
  });

  it('takes the newest when a run opened several, as one failure at several receivers does', () => {
    const a = summary('C-000030', 'S2', 'board', '2026-11-13T10:00:03Z');
    const b = summary('C-000031', 'S2', 'board', '2026-11-13T10:00:06Z');
    expect(runCase([a, b], run, false)).toBe(b);
  });

  it("is the recorded case of the scenario in the run's mode in the trial, whose cases were opened when it was recorded", () => {
    const recorded = summary('C-000002', 'S2', 'board', '2026-11-02T14:16:25Z');
    const rules = summary('C-000015', 'S2', 'rules', '2026-11-02T14:20:58Z');
    expect(runCase([rules, recorded], run, true)).toBe(recorded);
    // No recording in the run's mode: none, so the banner names the recording there is and never calls it the run's
    expect(runCase([rules], run, true)).toBeUndefined();
  });
});

describe('the short route', () => {
  it('is S2, S3 and S8 in Board, each with what to look at and the step after it, and nothing for any other run', () => {
    expect(ROUTE).toEqual(['S2', 'S3', 'S8']);
    expect(routeNext('S2', 'board')?.next).toBe('Next on the short route: S3, in its card below.');
    expect(routeNext('S3', 'board')?.next).toBe('Next on the short route: S8, in its card below.');
    expect(routeNext('S8', 'board')?.next).toMatch(/^That is the short route\./);
    // What to look at names the agents' findings on the case, where the board's panel is
    for (const id of ROUTE)
      expect(routeNext(id, 'board')?.look).toMatch(/The board has each agent's finding/);
    // S20 is the optional approval-boundary card, never one of the three
    expect(ROUTE).not.toContain('S20');
    expect(routeNext('S20', 'rules')).toBeNull();
    expect(routeNext('S5', 'board')).toBeNull();
    // A route scenario played in another mode has no board to point at, and is not a step of the route
    expect(routeNext('S8', 'rules')).toBeNull();
    expect(routeNext('S2', 'policy')).toBeNull();
  });
});
