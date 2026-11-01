import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import slice from '../../../docs/readme/evaluation.json?proof';
import { PROOF, playedFor, proofFrom, type ProofSource } from './proof';

describe("the proof's figures, from the board's evaluation", () => {
  it("counts the board's proposals: 24 of 24 scored passes, 25 passes in 24 cases, 1 not scored", () => {
    expect(PROOF.board).toEqual({ matched: 24, scored: 24, passes: 25, cases: 24, notScored: 1 });
    expect(PROOF.specialists).toEqual({ conformance: 13, encounter: 21, impact: 23 });
  });

  it('compares the board and simple rules on one base: the same 11 failures, 11 against 4', () => {
    expect(PROOF.played).toEqual({
      of: 11,
      board: 11,
      rules: 4,
      scenarios: ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S10', 'S13'],
    });
  });

  it("splits simple rules' 7 misses into 6 the gate stopped with nothing written and S8, which wrote", () => {
    expect(PROOF.rulesMisses).toEqual({
      total: 7,
      stopped: ['S1', 'S3', 'S6', 'S7', 'S10', 'S13'],
      wrote: ['S8'],
    });
    expect(playedFor('S8')).toEqual({ board: 'as-expected', rules: 'wrote-wrongly' });
    expect(playedFor('S1')).toEqual({ board: 'as-expected', rules: 'stopped' });
    expect(playedFor('S2')).toEqual({ board: 'as-expected', rules: 'as-expected' });
    // Not in the comparison's table, and an incident's chains are played per encounter
    expect(playedFor('S22')).toBeNull();
    expect(playedFor('S11')).toBeNull();
  });

  it('says who the cited entries leave the decision to, over the 24 scored passes: 16, 3 and 5', () => {
    expect(PROOF.entryDecides).toEqual({ policy: 16, board: 3, person: 5, of: 24 });
  });

  it('gives the cost of a pass, the runs and their total, when and where they were recorded, and the model', () => {
    expect(PROOF.costPerPass!.min.toFixed(2)).toBe('0.34');
    expect(PROOF.costPerPass!.max.toFixed(2)).toBe('0.50');
    expect(PROOF.runs).toBe(100);
    expect(PROOF.totalUsd!.toFixed(2)).toBe('10.00');
    expect(PROOF.recordedFrom).toBe('2026-10-25T13:22:49Z');
    expect(PROOF.recordedTo).toBe('2026-11-01T07:15:42Z');
    expect(PROOF.recordedOn).toEqual({
      image: 'irishealth-community:2026.3.0AI.154.0',
      build: '2026.3.0AI.154.0',
      number: '154',
    });
    expect(PROOF.models).toEqual(['claude-opus-5-5']);
    expect(PROOF.agreement).toEqual({
      unanimous: 12,
      'with the majority': 11,
      'with a minority': 1,
      'against all three': 1,
    });
  });

  it('leaves out what an older evaluation cannot say, rather than typing it', () => {
    const older: ProofSource = {
      sources: {},
      totals: { runs: 100 },
      passes: slice.passes.map((p) => ({
        ...p,
        played: p.played?.rules
          ? { ...p.played, rules: { status: p.played.rules.status, cost_usd: null } }
          : p.played,
      })),
    };
    const proof = proofFrom(older);
    expect(proof.played?.of).toBe(11);
    expect(proof.rulesMisses).toBeNull();
    expect(proof.board).toBeNull();
    expect(proof.recordedOn).toBeNull();
    expect(proofFrom({ sources: {}, totals: {}, passes: [] })).toMatchObject({
      played: null,
      rulesMisses: null,
      entryDecides: null,
      costPerPass: null,
      runs: null,
    });
  });

  it('reads a small slice of the document, never the whole of it, so the pages that show a figure stay small', () => {
    const whole = readFileSync(join(__dirname, '../../../docs/readme/evaluation.json'), 'utf8');
    expect(JSON.stringify(slice).length).toBeLessThan(whole.length / 4);
    for (const p of slice.passes) expect(p).not.toHaveProperty('members');
    // lib/proof.ts imports the slice and nothing else of the evaluation
    const source = readFileSync(join(__dirname, 'proof.ts'), 'utf8');
    expect(source.match(/from '[^']*evaluation\.json[^']*'/g)).toEqual([
      "from '../../../docs/readme/evaluation.json?proof'",
    ]);
  });
});
