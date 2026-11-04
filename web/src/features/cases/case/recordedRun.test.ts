import { describe, expect, it } from 'vitest';
import page from '../../../../../docs/readme/s8-what-the-agents-saw.md?raw';
import type { AgentRun } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { asObject } from '@/lib/json';
import { findRecording, planOf, storyOf } from './recordedRun';

const cases = fixtures.cases as unknown as Record<
  string,
  { detail: { scenario: string }; runs?: AgentRun[] | null }
>;
const boardRuns = Object.values(cases).flatMap((c) =>
  (c.runs ?? []).map((run) => ({ scenario: c.detail.scenario, run })),
);

/** S8's Encounter Integrity on C-000008: the run the panel's story is told with. */
async function encounter() {
  const run = cases['C-000008'].runs!.find((r) => r.memberCode === 'encounter')!;
  const found = await findRecording('S8', run);
  return { run, file: found!.file, story: storyOf(found!.record) };
}

describe('the recording behind a board run', () => {
  it("finds exactly one record for each of the trial's 64 board runs, among 56 files", async () => {
    const files = new Set<string>();
    for (const { scenario, run } of boardRuns) {
      const found = await findRecording(scenario, run);
      expect(found, `${scenario} ${run.memberCode} ${run.promptTokens}`).not.toBeNull();
      expect(found!.record.memberCode).toBe(run.memberCode);
      files.add(found!.file);
    }
    expect(boardRuns).toHaveLength(64);
    expect(files.size).toBe(56);
  });

  it("finds none when no record has the run's token counts, rather than another run's", async () => {
    const { run } = await encounter();
    expect(await findRecording('S8', { ...run, promptTokens: run.promptTokens + 1 })).toBeNull();
    expect(await findRecording('S99', run)).toBeNull();
  });

  it("reads every record the trial uses: the catalogue's advice, its calls' results and a last message", async () => {
    for (const { scenario, run } of boardRuns) {
      const found = await findRecording(scenario, run);
      const story = storyOf(found!.record);
      const where = found!.file;
      expect(story.recordedOn, where).toMatch(/^\d{1,2} [A-Z][a-z]{2} 2026$/);
      expect(story.recordedCase, where).toMatch(/^C-\d{6}$/);
      expect(story.model, where).toBe(run.model);
      expect(story.instructions, where).not.toBe('');
      expect(story.question, where).not.toBe('');
      expect(story.evidence, where).toContain('"catalogue"');
      expect(story.encounter, where).toBe('ENC-T1');
      expect(story.patient, where).toBe('MRN-T1');
      expect(story.matches.length, where).toBeGreaterThan(0);
      for (const m of story.matches) {
        expect(m.preferred, where).not.toBe('');
        expect(m.why, where).not.toBe('');
      }
      const calls = story.turns.flatMap((t) => t.calls);
      expect(calls.length, where).toBe(run.toolCallCount);
      for (const c of calls) expect(c.result, `${where} ${c.name}`).not.toBe('');
      expect(story.lastMessage, where).not.toBe('');
    }
  });

  it('names the dissents the plan on the page kept', async () => {
    for (const { scenario, run } of boardRuns.filter(({ run }) => run.role === 'coordinator')) {
      const found = await findRecording(scenario, run);
      const shown = (asObject(run.result)?.disagreements ?? []) as { member: string }[];
      expect(storyOf(found!.record).dissents.map((d) => d.member)).toEqual(shown.map((d) => d.member));
    }
  });

  it("finds each run's plan in its own pass: the first coordinator not before it, on the same snapshot", () => {
    for (const { runs } of Object.values(cases)) {
      const coordinators = (runs ?? []).filter((r) => r.role === 'coordinator');
      for (const run of runs ?? []) {
        const plan = coordinators.find((c) => Number(c.id) >= Number(run.id));
        expect(plan, `run ${run.id}`).toBeDefined();
        expect(planOf(runs!, run), `run ${run.id}`).toBe(plan);
      }
    }
  });

  it("keeps S7's dissent to its second pass", async () => {
    const runs = cases['C-000007'].runs!;
    const specialists = runs.filter((r) => r.role === 'specialist');
    expect(specialists).toHaveLength(6);
    const plans = await Promise.all(specialists.map((r) => findRecording('S7', planOf(runs, r)!)));
    expect(plans.map((p) => p!.file)).toEqual([
      ...Array<string>(3).fill('scenario-S7-ENC-1007-transfer-coordinator-1.json'),
      ...Array<string>(3).fill('scenario-S7-ENC-1007-transfer-coordinator-1-round2.json'),
    ]);
    expect(plans.map((p) => storyOf(p!.record).dissents.map((d) => d.member))).toEqual([
      [],
      [],
      [],
      ['conformance'],
      ['conformance'],
      ['conformance'],
    ]);
  });

  it("tells S8's Encounter Integrity in full: the query, ELS-2.5, and the ward the preview stopped short of", async () => {
    const { run, story, file } = await encounter();
    expect(file).toBe('scenario-S8-ENC-1008-transfer-encounter-1.json');
    expect(story).toMatchObject({
      recordedOn: '25 Oct 2026',
      recordedCase: 'C-000112',
      model: 'claude-opus-5-5',
      tokensIn: 15356,
      tokensOut: 895,
      matches: [{ id: 'E7', title: 'Two sources at the same time', preferred: 'escalate' }],
    });
    const calls = story.turns.flatMap((t) => t.calls);
    expect(story.turns.map((t) => t.calls.length)).toEqual([3, 1]);
    expect(calls.map((c) => c.name)).toEqual([
      'search_lifecycle',
      'GetWardState',
      'GetReceipt',
      'SubmitFindings',
    ]);
    expect(calls[0].args).toContain('two source systems same event time supersession transfer');
    expect(calls[0].result).toContain('ELS-2.5');
    expect(JSON.parse(calls[1].result)).toMatchObject({
      item: { data: { body: { ward: 'WARD-C', version: 2, state: 'admitted' } } },
    });
    // What Tool calls shows of the same call stops before the ward it holds
    expect(run.toolCalls.find((t) => t.name === 'GetWardState')!.resultPreview).not.toContain('WARD-C');
    expect(calls[3].args).toContain('"disposition": "escalate"');
    expect(story.lastMessage).toMatch(/^I recommended escalating case C-000112/);
  });

  it('does not disagree with the generated page on what the recording holds', async () => {
    const { story, file } = await encounter();
    expect(page).toContain(`recorded live on 2026-10-25 as case ${story.recordedCase}`);
    expect(page).toContain(story.model);
    expect(page).toContain(file);
    expect(page).toContain(story.instructions);
    expect(page).toContain(story.question);
    expect(page).toContain(story.evidence);
    expect(page).toContain(story.lastMessage);
    for (const call of story.turns.flatMap((t) => t.calls).filter((c) => c.name !== 'SubmitFindings')) {
      expect(page).toContain(call.args);
      expect(page).toContain(call.result);
    }
  });
});
