import { describe, expect, it } from 'vitest';
import type { AgentItem, Settings } from '@/api/types';
import {
  agentsSentence,
  answeringBadge,
  answeringOf,
  costRange,
  costsSentences,
  dayWords,
  fullSource,
  itemBadge,
  memberOfItem,
  replayFacts,
  replayTile,
  runWord,
  sameCases,
  shortSource,
  sourcesOf,
} from './settingsText';

const item = (over: Partial<AgentItem> = {}): AgentItem => ({
  name: 'Agent Coordinator',
  enabled: true,
  agentClass: 'Shutter.Agent.Coordinator',
  mode: 'auto',
  effectiveMode: 'replay',
  ...over,
});
const settings = (items: AgentItem[], over: Partial<Settings> = {}): Settings =>
  ({ agentItems: items, aiHubPresent: false, ...over }) as Settings;

describe('how the agents answer', () => {
  it('reads the mode the items run in now, not the one set', () => {
    expect(answeringOf(settings([item(), item({ name: 'Agent Impact' })])).kind).toBe('replay');
    expect(answeringOf(settings([item({ effectiveMode: 'live' })])).kind).toBe('live');
    expect(answeringOf(settings([item({ effectiveMode: 'record' })])).kind).toBe('record');
    expect(answeringOf(settings([item({ effectiveMode: 'live' })], { mock: true })).kind).toBe('mimic');
    expect(answeringOf(settings([item(), item({ effectiveMode: 'live' })])).kind).toBe('mixed');
  });

  it('leaves out the runner and the items switched off', () => {
    const board = item({ name: 'Agent Board', agentClass: undefined, effectiveMode: 'live' });
    const off = item({ name: 'Agent Impact', enabled: false, effectiveMode: 'live' });
    expect(answeringOf(settings([item(), board, off])).kind).toBe('replay');
  });

  it("keeps today's sentence for an instance that does not replay", () => {
    const live = settings([item({ effectiveMode: 'live' })], { aiHubPresent: true });
    expect(agentsSentence(live)).toBe('1 AI Hub agent, running live on the configured model provider');
    expect(agentsSentence({ ...live, mock: true })).toBe(
      '1 AI Hub agent, running live against the API mimic (tests/mock): no model is called and the runs cost nothing',
    );
    expect(
      agentsSentence(settings([item({ effectiveMode: 'record' }), item({ effectiveMode: 'record' })])),
    ).toBe('2 agents, running live and recording each run');
    expect(agentsSentence(settings([item(), item({ effectiveMode: 'live' })]))).toBe(
      '2 agents, in different modes, as the table shows',
    );
  });

  it('badges the section and each item in the provenance vocabulary', () => {
    expect(answeringBadge('replay')).toMatchObject({ tone: 'neutral', label: 'Replay' });
    expect(answeringBadge('live')).toMatchObject({ tone: 'info', label: 'Runs with real agents' });
    expect(answeringBadge('record')).toMatchObject({ tone: 'info', label: 'Records real runs' });
    expect(answeringBadge('other')).toBeNull();
    expect(itemBadge(item(), false)).toMatchObject({ tone: 'neutral', label: 'Replay' });
    expect(itemBadge(item({ effectiveMode: 'live' }), false)).toMatchObject({ tone: 'info', label: 'Live' });
    expect(itemBadge(item({ effectiveMode: 'live' }), true)).toMatchObject({
      tone: 'neutral',
      label: 'API mimic',
    });
    expect(itemBadge(item({ enabled: false }), false).label).toBe('Disabled');
  });

  it("gives the replay's facts from the evaluation, and leaves out what it cannot give", () => {
    expect(
      replayFacts({
        recordedOn: {
          image: 'irishealth-community:2026.3.0AI.154.0',
          build: '2026.3.0AI.154.0',
          number: '154',
        },
        models: ['claude-opus-5-5'],
      }),
    ).toEqual({ build: '154', models: ['claude-opus-5-5'] });
    expect(replayFacts({ recordedOn: null, models: [] })).toEqual({ build: null, models: [] });
  });

  it("gives each item its board member's code and name, and the runner apart", () => {
    expect(memberOfItem(item())).toEqual({ code: 'coordinator', name: 'Coordinator' });
    expect(memberOfItem(item({ agentClass: 'Shutter.Agent.Encounter' }))).toEqual({
      code: 'encounter',
      name: 'Encounter Integrity',
    });
    expect(memberOfItem(item({ name: 'Agent Board', agentClass: undefined }))).toEqual({
      code: 'runner',
      name: 'Board (runner)',
    });
    expect(memberOfItem(item({ agentClass: 'Site.Agent.Pharmacy' })).code).toBe('pharmacy');
  });
});

describe('the spent tile', () => {
  it('reads as a replay when every item replays and nothing was spent, and as spending otherwise', () => {
    const replaying = settings([item()]);
    expect(replayTile(replaying, 0)).toBe(true);
    expect(replayTile(replaying, undefined)).toBe(true);
    // An instance that replays now but spent on real runs before reads as spending
    expect(replayTile(replaying, 2.5)).toBe(false);
    expect(replayTile(settings([item({ effectiveMode: 'live' })]), 0)).toBe(false);
    expect(replayTile(undefined, 0)).toBe(false);
  });
});

describe('the costs in words', () => {
  const totals = { spentUsd: 0, liveRuns: 0, replayedRuns: 64, reviewRuns: 2 };

  it('says "spent here" in the trial and the live runs elsewhere, the replays free, the reviews apart', () => {
    expect(costsSentences(totals, true)).toEqual({
      spent: '$0.00',
      rest: " spent here: every answer is a replay. 64 replayed runs cost nothing. The production reviews' agent answered 2 times, listed apart below.",
    });
    expect(costsSentences(totals, false).rest).toBe(
      " spent on 0 live agent runs. 64 replayed runs cost nothing. The production reviews' agent answered 2 times, listed apart below.",
    );
  });

  it('counts in the right number, and names the mimic', () => {
    expect(
      costsSentences({ spentUsd: 1.5, liveRuns: 1, replayedRuns: 1, mockRuns: 1, reviewRuns: 1 }, false),
    ).toEqual({
      spent: '$1.50',
      rest: " spent on 1 live agent run. 1 replayed run costs nothing. 1 run against the API mimic costs nothing, since no model answered it. The production reviews' agent answered 1 time, listed apart below.",
    });
  });

  it('names a run by how it was made, and never "live" in the trial', () => {
    expect(runWord('replay')).toBe('replayed');
    expect(runWord('record')).toBe('recorded');
    // Outside the trial: the live system's word
    expect(runWord('live')).toBe('live');
    expect(runWord(undefined)).toBe('');
  });

  it('writes the board pass as a range, or one figure when both round the same', () => {
    expect(costRange(0.3449, 0.5039)).toBe('$0.34 to $0.50');
    expect(costRange(0.341, 0.344)).toBe('$0.34');
  });
});

describe('the price sources', () => {
  const p = (over = {}) => ({
    model: 'claude-opus-5-5',
    source: 'Anthropic list prices per million tokens, from the pricing page read on 2026-10-16 (seed 3)',
    asOf: '2026-10-16',
    ...over,
  });

  it('shortens the providers\' list prices to "List price, read 16 Oct 2026"', () => {
    expect(shortSource(p())).toBe('List price, read 16 Oct 2026');
    expect(shortSource(p({ asOf: '' }))).toBe('List price');
    expect(dayWords('2026-01-05')).toBe('5 Jan 2026');
    expect(dayWords('last week')).toBe('last week');
  });

  it('shows any other source as it was stored, with its date', () => {
    expect(shortSource(p({ source: 'Negotiated rate' }))).toBe('Negotiated rate (2026-10-16)');
    expect(fullSource(p({ source: 'Negotiated rate, 2026-10-16' }))).toBe('Negotiated rate, 2026-10-16');
  });

  it('lists each distinct source once with the models it prices', () => {
    expect(sourcesOf([p(), p({ model: 'claude-haiku-5-5' }), p({ model: 'x', source: 'Other' })])).toEqual([
      { source: `${p().source}`, models: ['claude-opus-5-5', 'claude-haiku-5-5'] },
      { source: 'Other (2026-10-16)', models: ['x'] },
    ]);
  });
});

describe('the cases in one line', () => {
  const row = (caseId: string, runs = 4, replayedRuns = runs, costUsd = 0) => ({
    caseId,
    runs,
    replayedRuns,
    costUsd,
  });

  it('collapses cases that are alike', () => {
    const rows = Array.from({ length: 16 }, (_, i) => row(`C-${i}`));
    expect(sameCases(rows)).toBe('Every case (16): 4 runs each, all replayed, $0.00');
  });

  it('names the few cases that have another number of runs', () => {
    const rows = [row('C-1'), row('C-2'), row('C-3', 8), row('C-4')];
    expect(sameCases(rows)).toBe('Every case (4): 4 runs each, all replayed, $0.00, except C-3 (8 runs)');
    const two = [row('C-1'), row('C-2'), row('C-3', 8), row('C-4', 6), row('C-5')];
    expect(sameCases(two)).toBe(
      'Every case (5): 4 runs each, all replayed, $0.00, except C-3 (8 runs) and C-4 (6 runs)',
    );
  });

  it('says none replayed for live cases that cost the same', () => {
    expect(sameCases([row('C-1', 2, 0, 0.5), row('C-2', 2, 0, 0.5)])).toBe(
      'Every case (2): 2 runs each, none replayed, $0.50',
    );
  });

  it('leaves the table when the cases differ in cost, in replays, or in many run counts', () => {
    expect(sameCases([row('C-1'), row('C-2', 4, 4, 0.3)])).toBeNull();
    expect(sameCases([row('C-1'), row('C-2', 4, 0)])).toBeNull();
    expect(sameCases([row('C-1', 4, 2), row('C-2', 4, 2)])).toBeNull();
    expect(
      sameCases([row('C-1'), row('C-2', 5), row('C-3', 6), row('C-4', 7), row('C-5', 8), row('C-6')]),
    ).toBeNull();
    expect(sameCases([row('C-1')])).toBeNull();
    expect(sameCases([])).toBeNull();
  });
});
