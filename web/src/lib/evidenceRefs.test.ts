import { describe, expect, it } from 'vitest';
import type { AgentRun, Plan } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { catalogueEntriesOf, citationsOf, citationWords, evidenceSection } from './evidenceRefs';

type Recorded = { runs: AgentRun[]; plan: { plan: Plan & { snapshotId?: string } } };
const recorded = (id: string) => (fixtures.cases as unknown as Record<string, Recorded>)[id];

describe("the evidence the board's members and the plan cite", () => {
  it("ties each ref to its Evidence section's anchor and title, naming the case's receiver", () => {
    expect(evidenceSection('message')).toEqual({
      ref: 'message',
      id: 'evidence-message',
      title: 'The HL7 message',
    });
    expect(evidenceSection('ward_state', 'Downstream Out')?.title).toBe("Downstream Out's encounter");
    expect(evidenceSection('timeline')?.id).toBe('evidence-timeline');
    expect(evidenceSection('catalogue:E7')).toBeNull();
  });

  it('says on C-000008 that Encounter Integrity did not cite the schema validation, and every member the timeline', () => {
    const c = recorded('C-000008');
    const cites = citationsOf(c.runs, c.plan.plan);
    const validation = cites.find((x) => x.ref === 'validation')!;
    expect(validation.members).not.toContain('encounter');
    expect(validation.members).toEqual(expect.arrayContaining(['conformance', 'impact']));
    expect(validation.plan).toBe(true);
    expect(citationWords(validation)).toBe('Cited by Conformance, Impact Analysis and the plan');
    const timeline = cites.find((x) => x.ref === 'timeline')!;
    expect(citationWords(timeline)).toBe('Cited by all three agents and the plan');
    expect(citationWords(cites.find((x) => x.ref === 'later_event')!)).toBe('Not cited');
    expect(catalogueEntriesOf(c.plan.plan.evidenceRefs)).toEqual(['E7']);
  });

  it('counts only the round whose runs made the plan, and names the plan alone when no member cites a section', () => {
    const run = (code: string, snapshotId: string, refs: string[]) =>
      ({ memberCode: code, snapshotId, result: { evidence_refs: refs } }) as unknown as AgentRun;
    const cites = citationsOf([run('conformance', '1', ['message']), run('conformance', '2', ['route'])], {
      evidenceRefs: ['receipt'],
      snapshotId: '2',
    });
    expect(cites.find((x) => x.ref === 'message')!.members).toEqual([]);
    expect(cites.find((x) => x.ref === 'route')!.members).toEqual(['conformance']);
    expect(citationWords(cites.find((x) => x.ref === 'receipt')!)).toBe('Cited by the plan');
  });
});
