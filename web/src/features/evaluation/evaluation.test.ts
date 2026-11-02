import { describe, expect, it } from 'vitest';
import evaluation from '../../../../docs/readme/evaluation.json';
import evaluationText from '../../../../docs/readme/evaluation.md?raw';
import comparisonText from '../../../../docs/readme/comparison.md?raw';
import {
  comparisonCells,
  dayRange,
  filterPasses,
  firstSentence,
  levelPattern,
  notYetMeasured,
  passKey,
  passName,
  passPlayed,
  played,
  playedLine,
  readFilters,
  type Evaluation,
  type EvaluationPass,
} from './evaluation';

const data = evaluation as unknown as Evaluation;

describe('the evaluation', () => {
  it('reads the document as the script wrote it', () => {
    expect(data.totals.runs).toBe(100);
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
    expect(passName({ ...base, scenario: 'S22', receiver: 'Records Out' })).toBe('S22 Records Out');
    expect(passName({ ...base, scenario: 'S22', receiver: '' })).toBe('S22');
  });
});

describe('the played outcomes', () => {
  it('counts rules alone over the scored passes that were played with rules alone', () => {
    // The two S11 incident passes were not played end to end, and S7's first pass is not scored
    expect(played(data, 'rules')).toEqual({ matches: 4, of: 11 });
  });

  it('counts the board on the same passes as rules alone, so the two figures compare like with like', () => {
    expect(played(data, 'board_live', 'rules')).toEqual({ matches: 11, of: 11 });
  });

  it("says how a scored pass ended when played, and nothing for one that wasn't or isn't scored", () => {
    const s1 = data.passes.find((p) => p.scenario === 'S1')!;
    expect(playedLine(s1)).toBe('Played by the board: as expected; by rules alone: not as expected');
    const s2 = data.passes.find((p) => p.scenario === 'S2')!;
    expect(playedLine(s2)).toBe('Played by the board: as expected; by rules alone: as expected');
    const unscored = data.passes.find((p) => p.scenario === 'S7' && !p.scored)!;
    expect(playedLine(unscored)).toBe('');
    const incident = data.passes.find((p) => p.scenario === 'S11')!;
    expect(playedLine(incident)).toBe('');
  });
});

describe("each pass's played results, for the table's marks", () => {
  const find = (id: string, round = 1) => data.passes.find((p) => p.scenario === id && p.round === round)!;

  it('splits rules alone into as expected, stopped by the gate with nothing written, and written wrongly', () => {
    expect(passPlayed(find('S2'))).toEqual({ board: 'as-expected', rules: 'as-expected' });
    expect(passPlayed(find('S1'))).toEqual({ board: 'as-expected', rules: 'stopped' });
    expect(passPlayed(find('S8'))).toEqual({ board: 'as-expected', rules: 'wrote-wrongly' });
    // S7's first pass was planned again: its case belongs to the second
    expect(passPlayed(find('S7'))).toBeNull();
    expect(passPlayed(find('S7', 2))).toEqual({ board: 'as-expected', rules: 'stopped' });
    expect(passPlayed(find('S11'))).toEqual({ board: 'not-played', rules: 'not-played' });
  });

  it("says only 'not as expected' for a document that does not record how rules alone ended", () => {
    const s1 = find('S1');
    const older = { ...s1, played: { ...s1.played, rules: { status: 'differs', cost_usd: null } } };
    expect(passPlayed(older)?.rules).toBe('differs');
  });

  it('gives every pass a key of its own, where the document names two alike', () => {
    expect(data.passes.filter((p) => passName(p) === 'S23a')).toHaveLength(2);
    expect(new Set(data.passes.map(passKey)).size).toBe(data.passes.length);
  });
});

describe("the per-scenario table's filters", () => {
  const names = (search: string) =>
    filterPasses(data.passes, readFilters(new URLSearchParams(search))).map(passName);

  it('reads the address, and ignores what it does not know', () => {
    expect(
      readFilters(new URLSearchParams('show=rules-differs&decides=board&outweighed=impact&sort=cost')),
    ).toEqual({ show: 'rules-differs', decides: 'board', outweighed: 'impact', sort: 'cost' });
    expect(readFilters(new URLSearchParams('show=everything&decides=nobody&sort=up'))).toEqual({
      show: 'all',
      decides: '',
      outweighed: '',
      sort: 'scenario',
    });
  });

  it("shows rules alone's misses, split as the comparison tile's marks split them", () => {
    expect(names('show=rules-differs')).toEqual(['S1', 'S3', 'S6', 'S7 pass 2', 'S8', 'S10', 'S13']);
    expect(names('show=rules-stopped')).toEqual(['S1', 'S3', 'S6', 'S7 pass 2', 'S10', 'S13']);
    expect(names('show=rules-wrote')).toEqual(['S8']);
  });

  it('shows the passes of an agreement level, or every pass that was not unanimous', () => {
    expect(names('show=with-a-minority')).toEqual(['S21']);
    expect(names('show=against-all-three')).toEqual(['S22 Records Out']);
    expect(names('show=not-unanimous')).toHaveLength(data.passes.length - data.totals.agreement.unanimous);
  });

  it('combines the filters, and sorts the dearest or the slowest first', () => {
    expect(names('show=not-unanimous&decides=person')).toEqual(['S10', 'S21', 'S23b Records Out']);
    const byCost = filterPasses(data.passes, readFilters(new URLSearchParams('sort=cost')));
    expect(byCost.map((p) => p.cost_usd)).toEqual(
      [...data.passes.map((p) => p.cost_usd)].sort((a, b) => b - a),
    );
    const bySpeed = filterPasses(data.passes, readFilters(new URLSearchParams('sort=elapsed')));
    expect(bySpeed[0].elapsed_ms).toBe(Math.max(...data.passes.map((p) => p.elapsed_ms)));
  });

  it("draws an agreement level's dots as most of its passes show them", () => {
    // Conformance is the usual dissenter when the plan has the majority
    expect(levelPattern(data.passes, 'with the majority')).toEqual({
      conformance: false,
      encounter: true,
      impact: true,
    });
    expect(levelPattern(data.passes, 'unanimous')).toEqual({
      conformance: true,
      encounter: true,
      impact: true,
    });
    // A level no pass has: the specialists in order, up to its count
    expect(levelPattern([], 'with a minority')).toEqual({
      conformance: true,
      encounter: false,
      impact: false,
    });
  });
});

describe('the words the page builds', () => {
  it("splits a Not yet measured item into its first sentence and the rest, keeping a file's name whole", () => {
    expect(firstSentence('Each pass is one. Nothing here shows more.')).toEqual({
      first: 'Each pass is one.',
      rest: 'Nothing here shows more.',
    });
    const one = 'Shutter can run scenario_check.py --modes single, but no runs are here.';
    expect(firstSentence(one)).toEqual({ first: one, rest: '' });
  });

  it("reads the comparison's cells by scenario, the bold marks dropped", () => {
    const cells = comparisonCells(comparisonText);
    expect(cells.S8.board).toMatch(/^as expected: escalated, escalate, no write/);
    expect(cells.S8.rules).toMatch(/^differs: resolved, resend, one write/);
    expect(cells.S1.rules).toMatch(/^differs: blocked, resend, no write/);
    expect(comparisonCells('no table')).toEqual({});
  });

  it('dates the recordings as one range, the year once', () => {
    expect(dayRange('2026-10-25T13:22:49Z', '2026-11-01T07:15:42Z')).toBe('25 Oct to 1 Nov 2026');
    expect(dayRange('2026-10-25T08:00:00Z', '2026-10-25T18:00:00Z')).toBe('25 Oct 2026');
    expect(dayRange('2026-12-30T08:00:00Z', '2027-01-02T08:00:00Z')).toBe('30 Dec 2026 to 2 Jan 2027');
    expect(dayRange('', '')).toBe('');
  });
});
