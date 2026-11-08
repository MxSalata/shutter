import { describe, expect, it } from 'vitest';
import type { Scenario } from '@/api/types';
import { PROOF, playedFor } from '@/lib/proof';
import definitions from '../../../../fixtures/scenarios.json';
import {
  hl7Events,
  proofParts,
  recordedLine,
  scenarioCount,
  SCENARIOS_DEFINED,
  splitSummary,
} from './scenarioText';

const scenarios = definitions as unknown as Scenario[];
const def = (id: string) => scenarios.find((s) => s.id === id)!;

describe('splitSummary', () => {
  it('splits at the first full stop followed by a space, and keeps the rest whole', () => {
    expect(splitSummary(def('S1').summary)).toEqual({
      first:
        'Admit to Ward A applied; the 09:20 transfer to Ward B fails before acceptance; the 09:45 transfer to Ward C applies.',
      rest: 'Resending the 09:20 message would move the patient backwards.',
    });
  });

  it('leaves a version number whole', () => {
    expect(splitSummary(def('S17').summary).first).toBe(
      "S2's never-accepted transfer, sent as HL7 2.4 messages to a route that parses 2.5.1.",
    );
  });

  it('gives a one-sentence summary no rest', () => {
    expect(splitSummary('One sentence only.')).toEqual({ first: 'One sentence only.', rest: '' });
  });

  it('loses no word of any scenario', () => {
    for (const s of scenarios) {
      const { first, rest } = splitSummary(s.summary);
      expect(`${first} ${rest}`.trim()).toBe(s.summary.trim());
    }
  });
});

describe('hl7Events', () => {
  it('names each file event in order and marks the delivery that fails', () => {
    expect(hl7Events(def('S2').steps)).toBe('A01, A02 fails');
    expect(hl7Events(def('S1').steps)).toBe('A01, A02 fails, A02');
    expect(hl7Events(def('S5').steps)).toBe('A01, A02 fails, A08');
  });

  it('marks a withheld message, and counts a run of the same event', () => {
    expect(hl7Events(def('S15').steps)).toBe('A01, A02, A40 withheld');
    expect(hl7Events(def('S11').steps)).toBe(
      'A01 ×5, A03, A02 ×4 fails, A01 fails, A02 fails, A08, A02 ×2, A03 ×2 fails',
    );
  });

  it('gives nothing for a scenario with no files', () => {
    expect(hl7Events([{ fault: 'off' }])).toBe('');
  });
});

describe('recordedLine', () => {
  it('says what the comparison recorded, by the split of rules alone', () => {
    expect(recordedLine({ board: 'as-expected', rules: 'stopped' })).toBe(
      'Recorded: board as expected; Rules only stopped by the gate',
    );
    expect(recordedLine({ board: 'as-expected', rules: 'wrote-wrongly' })).toBe(
      'Recorded: board as expected; Rules only wrote, not as expected',
    );
    expect(recordedLine({ board: 'as-expected', rules: 'as-expected' })).toBe(
      'Recorded: board as expected; Rules only as expected',
    );
    expect(recordedLine({ board: 'differs', rules: 'not-played' })).toBe('Recorded: board not as expected');
    expect(recordedLine(null)).toBeNull();
  });

  it("reads the evaluation's own results for the scenarios it played", () => {
    for (const id of ['S1', 'S3', 'S6', 'S7', 'S10', 'S13'])
      expect(recordedLine(playedFor(id))).toMatch(/Rules only stopped by the gate$/);
    expect(recordedLine(playedFor('S8'))).toMatch(/Rules only wrote, not as expected$/);
    for (const id of ['S2', 'S4', 'S5', 'S9'])
      expect(recordedLine(playedFor(id))).toMatch(/Rules only as expected$/);
    expect(recordedLine(playedFor('S20'))).toBeNull();
  });
});

describe('proofParts', () => {
  it('takes its figures from the evaluation, never typed', () => {
    const parts = proofParts(PROOF);
    expect(parts.tested).toBe(
      `Tested on ${PROOF.board!.scored} recorded cases from ${PROOF.board!.scenarios} scenarios (an incident gives several), the board chose the expected action every time.`,
    );
    expect(parts.played).toEqual({
      of: PROOF.played!.of,
      board: PROOF.played!.board,
      rules: PROOF.played!.rules,
    });
    expect(parts.bases).toBe(
      `(${PROOF.board!.scored} scored passes, proposed action; ${PROOF.played!.of} scenarios, played end to end)`,
    );
  });

  it('follows other figures, and leaves out a sentence the evaluation cannot give', () => {
    const board = { matched: 22, scored: 24, passes: 25, cases: 24, notScored: 1 };
    expect(proofParts({ board, played: null })).toEqual({
      tested: 'Tested on 24 recorded cases, the board chose the expected action in 22 of them.',
      played: null,
      bases: '(24 scored passes, proposed action)',
    });
    const played = { of: 9, board: 8, rules: 3, scenarios: [] };
    expect(proofParts({ board: null, played })).toEqual({
      tested: null,
      played: { of: 9, board: 8, rules: 3 },
      bases: '(9 scenarios, played end to end)',
    });
    expect(proofParts({ board: null, played: null })).toEqual({ tested: null, played: null, bases: null });
  });

  it('names the unit: recorded cases, and the scenarios they come from when there are fewer', () => {
    const board = { matched: 24, scored: 24, passes: 25, cases: 24, notScored: 1, scenarios: 19 };
    expect(proofParts({ board, played: null }).tested).toBe(
      'Tested on 24 recorded cases from 19 scenarios (an incident gives several), the board chose the expected action every time.',
    );
    expect(proofParts({ board: { ...board, scenarios: 24 }, played: null }).tested).toBe(
      'Tested on 24 recorded cases, the board chose the expected action every time.',
    );
  });
});

describe('scenarioCount', () => {
  it('counts the scenarios Shutter defines', () => {
    expect(SCENARIOS_DEFINED).toBe(scenarios.length);
  });

  it('says in the trial how many of them have recordings and where the rest run', () => {
    expect(scenarioCount(26, true)).toBe(
      `26 of the ${scenarios.length} scenarios have recordings here; the rest run on an install.`,
    );
    expect(scenarioCount(scenarios.length, true)).toBe(`${scenarios.length} in all.`);
    expect(scenarioCount(scenarios.length, false)).toBe(`${scenarios.length} in all.`);
    expect(scenarioCount(26, false)).toBe('26 in all.');
  });
});
