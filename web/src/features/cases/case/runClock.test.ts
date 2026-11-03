import { describe, expect, it } from 'vitest';
import type { AgentRun } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { call, livePass, replayedPass, run } from '@/test/runs';
import {
  clockLabel,
  clockSentence,
  investigationRuns,
  offsetSeconds,
  partSeconds,
  passClock,
  passRuns,
  passSeconds,
  REPLAYED_WORDS,
  rowFigures,
} from './runClock';

/** The recorded runs of a case in the trial's fixtures. */
const recorded = (id: string) => (fixtures.cases as unknown as Record<string, { runs: AgentRun[] }>)[id].runs;

describe("the run's own clock", () => {
  it('draws a live pass on one axis from its first start: the specialists in member order, the coordinator last', () => {
    const clock = passClock(livePass())!;
    expect(clock.precision).toBe('ms');
    expect(clock.rows.map((r) => [r.member, r.start, r.durationMs])).toEqual([
      ['conformance', 0, 14_735],
      ['encounter', 2, 11_644],
      ['impact', 5, 15_976],
      ['coordinator', 15_990, 14_921],
    ]);
    expect(clock.totalMs).toBe(15_990 + 14_921);
    expect(clock.startedAt).toBe('2026-10-25T13:28:51.100Z');
    expect(clock.overlap).toBe('together');
    expect(clock.rows.map((r) => r.name)).toEqual([
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Coordinator',
    ]);
  });

  it('puts each tool call where it ran: the row is written when the tool answers, so from its time less its duration', () => {
    const [conformance, encounter] = passClock(livePass())!.rows;
    expect(conformance.marks.map((m) => [m.from, m.to])).toEqual([
      [4_191, 4_192],
      [4_197, 4_201],
      [12_337, 12_337],
    ]);
    // A refused call ran nothing: it stands at its time, marked as refused
    expect(encounter.marks.map((m) => [m.from, m.refused])).toEqual([
      [3_984, false],
      [4_900, true],
    ]);
    expect([encounter.calls, encounter.refused]).toEqual([2, 1]);
  });

  it('says it in Plain words, and in one sentence for a screen reader', () => {
    const clock = passClock(livePass())!;
    expect(clockSentence(clock)).toBe(
      'The three specialists worked at the same time, then the coordinator wrote the plan. The pass took 31 s.',
    );
    expect(clockLabel(clock)).toBe(
      'When each agent worked: the three specialists at the same time, then the coordinator; the pass took 31 s.',
    );
  });

  it("gives each run's split from AI Hub's counters, or says the timings are as recorded", () => {
    const [conformance, encounter] = passClock(livePass())!.rows;
    expect(rowFigures(conformance)).toBe('model 11.2 s, tools 0.8 s, 1,240 reasoning tokens');
    expect(rowFigures(encounter)).toBe('timings as recorded');
    // Empty is not zero: a zero the build counted is a figure
    expect(rowFigures({ ...encounter, toolMs: 17, reasoningTokens: 0 })).toBe(
      'tools 17 ms, 0 reasoning tokens',
    );
  });

  it('draws a replayed pass as the recording ran it: the specialists from 0, the coordinator after the slowest', () => {
    const clock = passClock(replayedPass())!;
    expect(clock.replayed).toBe(true);
    // The replay's own starts, all within the same tenth of a second, are left out; the durations are the recording's
    expect(clock.rows.map((r) => [r.member, r.start, r.durationMs])).toEqual([
      ['conformance', 0, 14_735],
      ['encounter', 0, 11_644],
      ['impact', 0, 15_976],
      ['coordinator', 15_976, 14_921],
    ]);
    expect(clock.totalMs).toBe(15_976 + 14_921);
    expect(clock.overlap).toBe('together');
    // When the replay ran, not when the recording was made
    expect(clock.startedAt).toBe('2026-11-02T14:15:08.656Z');
    expect(clockSentence(clock)).toBe(
      'The three specialists worked at the same time, then the coordinator wrote the plan. The recorded pass took 31 s.',
    );
    expect(clockLabel(clock)).toBe(
      'When each agent worked, replayed with the times as recorded: the three specialists at the same time, then the coordinator; the recorded pass took 31 s.',
    );
    expect(REPLAYED_WORDS).toMatch(
      /^A replay calls no model and answers at once, so its own starts are left out\./,
    );
  });

  it("puts a replayed run's tool calls at their times in that run, its bar moved with them", () => {
    const [conformance, encounter, , coordinator] = passClock(replayedPass())!.rows;
    expect(conformance.marks.map((m) => [m.from, m.to])).toEqual([
      [4_191, 4_192],
      [4_197, 4_201],
      [12_337, 12_337],
    ]);
    expect(encounter.marks.map((m) => [m.from, m.refused])).toEqual([
      [3_982, false],
      [4_898, true],
    ]);
    // The coordinator's call 12.0 s into its run, from where its bar starts
    expect(coordinator.marks.map((m) => [m.from, m.to])).toEqual([[15_976 + 12_032, 15_976 + 12_032]]);
  });

  it('keeps a replayed call that sits up to a second past its bar, and drops every mark beyond that', () => {
    // The recording kept its start to the second, so a call can sit up to a second late in its run
    const late = replayedPass();
    const end = Date.parse(late[2].startedAtMs as string) + late[2].durationMs;
    late[2] = { ...late[2], toolCalls: [call(1, new Date(end + 900).toISOString(), 1)] };
    const kept = passClock(late)!.rows[2];
    expect(kept.marks.map((m) => [m.from, m.to])).toEqual([[15_976, 15_976]]);
    late[2] = { ...late[2], toolCalls: [call(1, new Date(end + 1_100).toISOString(), 1)] };
    expect(passClock(late)!.rows.every((r) => r.marks.length === 0)).toBe(true);
  });

  it('draws a replayed pass with bars and no marks when a run has no start to the millisecond', () => {
    const pass = replayedPass();
    pass[1] = { ...pass[1], startedAtMs: null };
    const clock = passClock(pass)!;
    expect(clock.replayed).toBe(true);
    expect(clock.rows.map((r) => r.start)).toEqual([0, 0, 0, 15_976]);
    expect(clock.rows.every((r) => r.marks.length === 0)).toBe(true);
  });

  it('draws no replayed pass with a run of no duration, and no such picture for a pass partly live', () => {
    const noDuration = replayedPass();
    noDuration[3] = { ...noDuration[3], durationMs: 0 };
    expect(passClock(noDuration)).toBeNull();
    // One live run among replays: the live rule judges it, and the replay's starts contradict the durations
    const mixed = replayedPass();
    mixed[0] = { ...mixed[0], mode: 'live' };
    expect(passClock(mixed)).toBeNull();
  });

  it("draws the trial's recorded board passes as replays, every call on its run's bar", () => {
    for (const id of ['C-000002', 'C-000008', 'C-000009', 'C-000033']) {
      const runs = recorded(id);
      expect(passRuns(runs).length, id).toBe(4);
      const clock = passClock(runs)!;
      expect(clock, id).not.toBeNull();
      expect(clock.replayed, id).toBe(true);
      const [conformance, encounter, impact, coordinator] = clock.rows;
      expect([conformance.start, encounter.start, impact.start], id).toEqual([0, 0, 0]);
      expect(coordinator.start, id).toBe(Math.max(conformance.end, encounter.end, impact.end));
      for (const r of clock.rows) {
        expect(r.marks.length, `${id} ${r.member}`).toBe(r.calls);
        for (const m of r.marks) {
          expect(m.from).toBeGreaterThanOrEqual(r.start);
          expect(m.to).toBeLessThanOrEqual(r.end);
        }
      }
    }
  });

  it('falls back to the starts to the second, with bars and no marks', () => {
    const pass = livePass().map((r) => ({ ...r, startedAtMs: undefined }));
    const clock = passClock(pass)!;
    expect(clock.precision).toBe('s');
    expect(clock.rows.map((r) => r.start)).toEqual([0, 0, 0, 16_000]);
    expect(clock.rows.every((r) => r.marks.length === 0)).toBe(true);
    expect(offsetSeconds(16_000, clock.precision)).toBe('16 s');
    // One run without its millisecond start puts them all on the start to the second: a replay's two stamps may come
    // from two clocks
    const mixed = livePass();
    mixed[1] = { ...mixed[1], startedAtMs: null };
    expect(passClock(mixed)!.precision).toBe('s');
  });

  it('draws nothing when a run has no start or no duration, or the pass has no coordinator yet', () => {
    const noStart = livePass();
    noStart[2] = { ...noStart[2], startedAt: '', startedAtMs: undefined };
    expect(passClock(noStart)).toBeNull();
    const noDuration = livePass();
    noDuration[0] = { ...noDuration[0], durationMs: 0 };
    expect(passClock(noDuration)).toBeNull();
    expect(passClock(livePass().slice(0, 3))).toBeNull();
    expect(passClock([])).toBeNull();
    expect(passClock(undefined)).toBeNull();
  });

  it('draws nothing when the coordinator started before the specialists had answered', () => {
    const early = livePass();
    early[3] = { ...early[3], startedAtMs: '2026-10-25T13:29:05.000Z' };
    expect(passClock(early)).toBeNull();
    // Within the clock's precision it is the same moment
    const close = livePass();
    close[3] = { ...close[3], startedAtMs: '2026-10-25T13:29:06.900Z' };
    expect(passClock(close)).not.toBeNull();
  });

  it("drops every mark when one run's calls do not fit its bar, so no bar reads as the model's time alone", () => {
    const stray = livePass();
    stray[2] = { ...stray[2], toolCalls: [call(1, '2026-10-25T13:29:30.000Z', 1)] };
    const clock = passClock(stray)!;
    expect(clock.rows.every((r) => r.marks.length === 0)).toBe(true);
    // A run that counted calls without listing them leaves the others unmarked too
    const counted = livePass();
    counted[2] = { ...counted[2], toolCalls: [], toolCallCount: 6 };
    expect(passClock(counted)!.rows.every((r) => r.marks.length === 0)).toBe(true);
  });

  it("keeps the investigation's runs and leaves a question's out, whatever their roles", () => {
    const asked = [
      run({ id: 'q1', role: 'coordinator', memberCode: 'coordinator', questionId: 'Q-000001' }),
      run({ id: 'q2', role: 'explain', memberCode: 'explain', questionId: 'Q-000001' }),
    ];
    const pass = livePass();
    expect(investigationRuns([...pass, ...asked]).map((r) => r.id)).toEqual(pass.map((r) => r.id));
    expect(investigationRuns(pass.map((r) => ({ ...r, questionId: null })))).toHaveLength(pass.length);
    expect(investigationRuns(undefined)).toEqual([]);
  });

  it("reads the latest pass: the last coordinator's snapshot, the last run of each specialist, Ask's runs left out", () => {
    const earlier = livePass().map((r) => ({ ...r, id: `old-${r.id}`, snapshotId: 8 }));
    const asked = run({ id: 'q', memberCode: 'impact', questionId: 'Q1', snapshotId: 9 });
    const pass = passRuns([...earlier, ...livePass(), asked]);
    expect(pass.map((r) => r.id)).toEqual([53, 54, 55, 56]);
    // Two passes and no snapshot to tell them apart: none is drawn
    const unknown = [...earlier, ...livePass()].map((r) => ({ ...r, snapshotId: undefined }));
    expect(passRuns(unknown)).toEqual([]);
  });

  it('says when the specialists worked one after another, or partly at the same time', () => {
    const apart = livePass();
    apart[1] = { ...apart[1], startedAtMs: '2026-10-25T13:29:06.000Z', durationMs: 4_000 };
    apart[2] = { ...apart[2], startedAtMs: '2026-10-25T13:29:10.000Z', durationMs: 3_000 };
    apart[3] = { ...apart[3], startedAtMs: '2026-10-25T13:29:13.500Z' };
    const one = passClock(apart)!;
    expect(one.overlap).toBe('apart');
    expect(clockSentence(one)).toMatch(
      /^The three specialists worked one after another, then the coordinator/,
    );
    const partly = livePass();
    partly[2] = { ...partly[2], startedAtMs: '2026-10-25T13:29:03.000Z', durationMs: 3_000 };
    expect(passClock(partly)!.overlap).toBe('partly');
    const single = livePass().filter((r) => r.memberCode !== 'encounter' && r.memberCode !== 'impact');
    expect(clockSentence(passClock(single)!)).toMatch(/^The specialist worked first, then the coordinator/);
  });

  it('writes its times as the clock knows them', () => {
    expect([passSeconds(30_911), passSeconds(8_420), passSeconds(64_400)]).toEqual([
      '31 s',
      '8.4 s',
      '1 min 4 s',
    ]);
    expect([partSeconds(17), partSeconds(800), partSeconds(11_200)]).toEqual(['17 ms', '0.8 s', '11.2 s']);
    expect([offsetSeconds(14_620, 'ms'), offsetSeconds(14_620, 's')]).toEqual(['14.6 s', '15 s']);
  });
});
