import { describe, expect, it } from 'vitest';
import type { Mode, Scenario, ScenarioExpected } from '@/api/types';
import { endOf, scenarioDiagram, type DiagramNode } from './scenarioDiagram';
import definitions from '../../../../fixtures/scenarios.json';

const scenarios = definitions as unknown as Scenario[];
const MODES: Mode[] = ['board', 'policy', 'single', 'rules'];
const byId = (id: string) => scenarios.find((s) => s.id === id)!;
/** The modes a scenario is defined for: the row says "not in this mode" in the others. */
const modesOf = (s: Scenario) => MODES.filter((m) => !s.expected.modes || s.expected.modes.includes(m));
const diagram = (id: string, mode: Mode = modesOf(byId(id))[0], technical = false) =>
  scenarioDiagram(byId(id), mode, technical)!;
const messages = (nodes: DiagramNode[]) => nodes.filter((n) => n.kind === 'message');

/** Every message file's sending application (MSH-3), read as text. */
const files = import.meta.glob('../../../../fixtures/S*/*.hl7', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>;
const senderOf = (file: string) => {
  const key = Object.keys(files).find((path) => path.endsWith(`/${file}`));
  return key ? files[key].split('|')[2] : undefined;
};

/** What the scenario expects in the mode, as the row's "What should happen" reads it. */
function expectedWrites(e: ScenarioExpected): number {
  if (e.incident) return (e.encounters ?? []).reduce((n, x) => n + x.writes, 0);
  if (e.by_receiver) return Object.values(e.by_receiver).filter((x) => x.write).length;
  return e.write ? 1 : 0;
}

/** The deliveries that fail with no fault on: the receiver is up and said no. */
function refusedSteps(s: Scenario) {
  let on = false;
  return s.steps.filter((step) => {
    if (step.fault) on = step.fault !== 'off';
    return step.expect === 'delivery_fails' && !on;
  });
}

describe('scenarioDiagram', () => {
  it('covers all 26 scenarios', () => {
    expect(scenarios).toHaveLength(26);
    for (const s of scenarios) expect(diagram(s.id), s.id).not.toBeNull();
  });

  it('ends every scenario, in every mode it plays, as its expected write and disposition say', () => {
    for (const s of scenarios)
      for (const mode of modesOf(s)) {
        const e = { ...s.expected, ...s.expected.by_mode?.[mode] };
        const end = endOf(s, mode);
        const at = `${s.id} in ${mode}`;
        const writes = expectedWrites(e);
        expect(end.writes, at).toBe(writes);
        if (writes > 1) expect(end.kind, at).toBe('writes');
        else if (writes === 1) expect(end.kind, at).toBe('write');
        else if (e.by_receiver)
          // S22: nothing is written, and only one of its two receivers goes to a person
          expect(end.kind, at).toBe('none');
        else if (e.disposition === 'escalate') expect(end.kind, at).toBe('person');
        else expect(end.kind, at).toBe('none');
        if (writes) {
          expect(end.label, at).toBe(`${writes} write${writes === 1 ? '' : 's'}`);
          expect(end.caption, at).toBe(e.case_by_key && !e.incident ? 'this case' : 'conditional');
          expect(end.words, at).toMatch(/conditional/);
        } else expect(end.words, at).toMatch(/nothing written/);
      }
  });

  it('follows the mode: S21 is stopped by the gate in Rules only, and only there', () => {
    expect(endOf(byId('S21'), 'rules').caption).toBe('no write, stopped');
    expect(endOf(byId('S21'), 'rules').words).toMatch(/EVENT_TIME_IMPLAUSIBLE/);
    expect(endOf(byId('S21'), 'board').caption).toBe('no write');
    expect(endOf(byId('S21'), 'board').words).not.toMatch(/EVENT_TIME_IMPLAUSIBLE/);
  });

  it('says the end is what should happen, never what a run did', () => {
    for (const s of scenarios) expect(diagram(s.id).label, s.id).toMatch(/It should end: /);
    // S8 in Rules only wrote when it was recorded, and still should not have
    expect(endOf(byId('S8'), 'rules').kind).toBe('person');
  });

  it('marks exactly the messages that fail or are withheld, in the order they are played', () => {
    for (const s of scenarios) {
      const nodes = diagram(s.id).nodes;
      const sent = s.steps.filter((step) => step.file);
      const failed = sent.filter((step) => step.expect === 'delivery_fails').length;
      const withheld = sent.filter((step) => step.expect === 'withheld').length;
      const refused = refusedSteps(s).length;
      const counted = nodes.find((n) => n.kind === 'messages');
      if (counted?.kind === 'messages') {
        expect(counted.total, s.id).toBe(sent.length);
        expect(counted.failed, s.id).toBe(failed);
        continue;
      }
      const drawn = messages(nodes);
      const count = (mark?: string) =>
        drawn.reduce((n, m) => n + (m.kind === 'message' && m.mark === mark ? m.count : 0), 0);
      expect(count('fails'), s.id).toBe(failed - refused);
      expect(count('refused'), s.id).toBe(refused);
      expect(count('withheld'), s.id).toBe(withheld);
      expect(count(undefined) + count('fails') + count('refused') + count('withheld'), s.id).toBe(
        sent.length,
      );
    }
    expect(diagram('S2', 'board', true).nodes.map((n) => (n.kind === 'message' ? n.event : n.kind))).toEqual([
      'A01',
      'fault',
      'A02',
    ]);
    expect(diagram('S15').nodes.at(-1)).toMatchObject({ event: 'A40', mark: 'withheld' });
    expect(diagram('S16').nodes.at(-1)).toMatchObject({ event: 'A12', mark: 'withheld' });
  });

  it('draws a fault wherever the steps have one, a recovery never, and never a fault the player does not name', () => {
    for (const s of scenarios) {
      const faults = s.steps.filter((step) => step.fault && step.fault !== 'off');
      const nodes = diagram(s.id).nodes.filter((n) => n.kind === 'fault');
      const capability = s.steps.some((step) => step.capabilities) ? 1 : 0;
      if (nodes.length && diagram(s.id).nodes.some((n) => n.kind === 'messages'))
        expect(nodes, s.id).toHaveLength(1);
      else expect(nodes, s.id).toHaveLength(faults.length + capability);
      for (const n of nodes) expect(n.kind === 'fault' && n.caption, s.id).not.toBe('fault');
    }
    expect(diagram('S11').nodes[0]).toMatchObject({ kind: 'fault', caption: 'down ×2' });
    expect(diagram('S10').nodes.at(-1)).toMatchObject({ kind: 'fault', caption: 'no guard' });
    expect(diagram('S22').nodes[1]).toMatchObject({ kind: 'fault', caption: '2 down' });
  });

  it("draws a person's own change at the receiver only where a step makes one", () => {
    for (const s of scenarios)
      expect(
        diagram(s.id).nodes.some((n) => n.kind === 'person'),
        s.id,
      ).toBe(s.steps.some((step) => step.manual));
  });

  it("marks another source's message exactly where a fixture's MSH-3 is not the PAS", () => {
    const others = scenarios.flatMap((s) =>
      s.steps.filter((step) => step.file && senderOf(step.file) !== 'PAS').map(() => s.id),
    );
    // The fixtures were found: a missing glob would otherwise pass this by comparing nothing
    expect(Object.keys(files).length).toBeGreaterThan(50);
    expect(others).toEqual(['S8']);
    for (const s of scenarios) {
      const marked = messages(diagram(s.id).nodes).filter(
        (n) => n.kind === 'message' && n.aside === 'source',
      );
      expect(marked.length, s.id).toBe(others.includes(s.id) ? 1 : 0);
    }
    const last = diagram('S8').nodes.at(-1)!;
    expect(last).toMatchObject({ kind: 'message', aside: 'source' });
    // It is the message after the failure that the bed manager sent
    const file = byId('S8')
      .steps.filter((step) => step.file)
      .at(-1)!.file!;
    expect(senderOf(file)).toBe('BEDMGR');
  });

  it('marks a message for another encounter only where the scenario names that encounter', () => {
    for (const s of scenarios)
      expect(
        messages(diagram(s.id).nodes).some((n) => n.kind === 'message' && n.aside === 'encounter'),
        s.id,
      ).toBe(!!s.expected.other_encounter);
  });

  it('counts a long story rather than drawing it, with the writes of its chains in all', () => {
    expect(diagram('S11').nodes.at(-1)).toMatchObject({ kind: 'messages', total: 17, failed: 8 });
    expect(diagram('S12').nodes.at(-1)).toMatchObject({ kind: 'messages', total: 8, failed: 5 });
    expect(endOf(byId('S11'), 'policy')).toMatchObject({ kind: 'writes', writes: 5, label: '5 writes' });
    expect(endOf(byId('S12'), 'policy')).toMatchObject({ kind: 'writes', writes: 5, label: '5 writes' });
    for (const s of scenarios) expect(diagram(s.id).nodes.length, s.id).toBeLessThanOrEqual(7);
  });

  it("says one of S22's two receivers goes to a person, without saying a person decides for both", () => {
    const end = endOf(byId('S22'), 'board');
    expect(end).toMatchObject({ kind: 'none', caption: 'one to a person' });
    expect(end.words).toMatch(/one goes to a person/);
  });

  it('names messages in plain words in Plain and by their HL7 events in Technical, in the picture and its label', () => {
    expect(diagram('S2').label).toMatch(/admit is delivered/);
    expect(diagram('S2').label).not.toMatch(/A01/);
    expect(diagram('S2', 'board', true).label).toMatch(/A01 is delivered/);
    for (const s of scenarios)
      for (const n of messages(diagram(s.id).nodes))
        expect(n.kind === 'message' && n.plain, s.id).not.toMatch(/^A\d\d$/);
  });

  it("draws S23a's second move as refused by a receiver that is up, apart from the failure while it was down", () => {
    const moves = messages(diagram('S23a').nodes);
    expect(moves.at(-2)).toMatchObject({ plain: 'Move', mark: 'fails', count: 1 });
    expect(moves.at(-1)).toMatchObject({ plain: 'Move', mark: 'refused', count: 1 });
    expect(diagram('S23a').label).toMatch(/move is refused by the receiver/);
    expect(diagram('S23b').nodes.at(-1)).toMatchObject({ mark: 'refused' });
    expect(diagram('S23b').nodes.some((n) => n.kind === 'fault')).toBe(false);
    // Only those two are refusals, and the fixtures say so: a change there changes this list
    expect(scenarios.filter((s) => refusedSteps(s).length).map((s) => s.id)).toEqual(['S23a', 'S23b']);
  });

  it('merges no two messages across the receiver coming back', () => {
    const steps = [
      { fault: 'fail_before_accept' },
      { file: 'X-01-A02.hl7', expect: 'delivery_fails' },
      { fault: 'off' },
      { file: 'X-02-A02.hl7' },
      { file: 'X-03-A02.hl7' },
    ] as Scenario['steps'];
    const drawn = scenarioDiagram({ ...byId('S2'), steps }, 'board')!;
    expect(messages(drawn.nodes).map((n) => n.kind === 'message' && n.count)).toEqual([1, 2]);
  });

  it("captions a write that counts one failure's case as this case's, not the story's", () => {
    expect(endOf(byId('S23a'), 'policy')).toMatchObject({ label: '1 write', caption: 'this case' });
    expect(endOf(byId('S23a'), 'policy').words).toBe('one conditional write in this case');
    expect(endOf(byId('S2'), 'board').caption).toBe('conditional');
  });

  it('says why a case ends with nothing written, a superseded or a reconcile one by that word', () => {
    const ending = (word: string) =>
      scenarios.filter(
        (s) =>
          !s.expected.by_mode &&
          !s.expected.blocked_by &&
          !s.expected.write &&
          s.expected.disposition === word,
      );
    for (const word of ['superseded', 'reconcile']) {
      expect(ending(word).length, word).toBeGreaterThan(0);
      for (const s of ending(word)) {
        const end = endOf(s, modesOf(s)[0]);
        expect(end.caption, s.id).toBe(word);
        expect(end.words, s.id).toMatch(new RegExp(`, ${word}`));
      }
    }
  });

  it('reads as a sentence where a message has an aside', () => {
    expect(diagram('S8').label).toMatch(/from another source, the bed manager, is delivered/);
    const encounter = scenarios.find((s) => s.expected.other_encounter)!;
    expect(diagram(encounter.id).label).toMatch(/, for another encounter, is delivered/);
  });

  it('draws nothing for a list that carries no steps, as an older server may send', () => {
    expect(scenarioDiagram({ ...byId('S2'), steps: [] }, 'board')).toBeNull();
  });
});
