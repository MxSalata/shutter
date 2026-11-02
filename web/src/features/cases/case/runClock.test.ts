import { describe, expect, it } from 'vitest';
import type { AgentRun } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { call, livePass, run } from '@/test/runs';
import {
  clockLabel,
  clockSentence,
  offsetSeconds,
  partSeconds,
  passClock,
  passRuns,
  passSeconds,
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

  it('draws nothing for the recording the trial replays: its starts were stamped when it was replayed', () => {
    for (const id of ['C-000002', 'C-000008', 'C-000009', 'C-000033']) {
      expect(passRuns(recorded(id)).length, id).toBe(4);
      expect(passClock(recorded(id)), id).toBeNull();
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
