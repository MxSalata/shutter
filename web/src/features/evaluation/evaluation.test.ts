import { describe, expect, it } from 'vitest';
import evaluation from '../../../../docs/readme/evaluation.json';
import evaluationText from '../../../../docs/readme/evaluation.md?raw';
import { notYetMeasured, passName, type Evaluation, type EvaluationPass } from './evaluation';

const data = evaluation as unknown as Evaluation;

describe('the evaluation', () => {
  it('reads the document as the script wrote it', () => {
    expect(data.totals.runs).toBe(56);
    expect(data.totals.board_matches).toBe(data.totals.scored_passes);
    expect(
      data.passes.every((p) =>
        ['conformance', 'encounter', 'impact', 'coordinator'].every((m) => m in p.members),
      ),
    ).toBe(true);
  });

  it("lists the document's Not yet measured items, with their leads", () => {
    const items = notYetMeasured(evaluationText);
    expect(items.length).toBeGreaterThanOrEqual(4);
    expect(items[0].title).toBe('Repeat runs.');
    expect(items[0].text).toMatch(/^Each pass above is one recording per member/);
    expect(items.some((i) => i.title === 'The single investigator.')).toBe(true);
    // Inline code marks are dropped; the words stay
    expect(items.find((i) => i.title === 'The single investigator.')?.text).toContain(
      'scenario_check.py --modes single',
    );
    expect(items.every((i) => !i.text.includes('`'))).toBe(true);
  });

  it('parses only the list under the heading, up to the next one', () => {
    const md =
      '## A\n\n- not this\n\n## Not yet measured\n\n- **One.** First\n  continued\n- plain item\n\n## B\n\n- nor this\n';
    expect(notYetMeasured(md)).toEqual([
      { title: 'One.', text: 'First continued' },
      { title: '', text: 'plain item' },
    ]);
    expect(notYetMeasured('## Other\n- x')).toEqual([]);
  });

  it('names a pass as the document does', () => {
    const base = { scenario: 'S7', incident: false, round: 1, rounds: 1 } as EvaluationPass;
    expect(passName(base)).toBe('S7');
    expect(passName({ ...base, round: 2, rounds: 2 })).toBe('S7 pass 2');
    expect(
      passName({ ...base, scenario: 'S11', incident: true, encounter: 'ENC-1103', event: 'transfer' }),
    ).toBe('S11 ENC-1103 transfer');
  });
});
