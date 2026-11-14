import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import slice from '../../../docs/readme/evaluation.json?proof';
import {
  CATALOGUE_COHORT,
  cohortLabel,
  FIRST_RELEASE,
  PROOF,
  recordedBefore,
  playedFor,
  playedResult,
  proofFrom,
  type ProofSource,
} from './proof';

describe("the proof's figures, from the board's evaluation", () => {
  it("counts the board's proposals: 24 of 24 scored passes, 25 passes in 24 cases, 1 not scored", () => {
    expect(PROOF.board).toEqual({
      matched: 24,
      scored: 24,
      passes: 25,
      cases: 24,
      notScored: 1,
      scenarios: 19,
    });
    expect(PROOF.specialists).toEqual({ conformance: 13, encounter: 21, impact: 23 });
  });

  it('compares the board and Rules only on one base: the same 11 failures, 11 against 4', () => {
    expect(PROOF.played).toEqual({
      of: 11,
      board: 11,
      rules: 4,
      scenarios: ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S10', 'S13'],
    });
  });

  it("splits Rules only's 7 misses into 6 the gate stopped with nothing written and S8, which wrote", () => {
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

  it('gives the played result of any one pass, as the per-scenario figures read it', () => {
    expect(
      playedResult({
        board_live: { status: 'as expected' },
        rules: { status: 'differs', state: 'blocked', wrote: false },
      }),
    ).toEqual({ board: 'as-expected', rules: 'stopped' });
    expect(
      playedResult({ board_live: { status: 'differs' }, rules: { status: 'differs', wrote: true } }),
    ).toEqual({
      board: 'differs',
      rules: 'wrote-wrongly',
    });
    expect(playedResult(undefined)).toEqual({ board: 'not-played', rules: 'not-played' });
    for (const id of ['S1', 'S8'])
      expect(
        playedResult(
          (slice as ProofSource).passes.find((p) => p.scenario === id && p.played?.board_live)?.played,
        ),
      ).toEqual(playedFor(id));
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

describe('the cohort and release said beside the figures', () => {
  const changelog = readFileSync(join(__dirname, '../../../CHANGELOG.md'), 'utf8');

  it("takes the first release's day from the changelog", () => {
    const version = FIRST_RELEASE.version.replace(/\./g, '\\.');
    const heading = new RegExp(`^## ${version} \\((\\d+ \\w+ \\d{4})\\)$`, 'm').exec(changelog);
    expect(heading, 'the 1.0.0 heading of CHANGELOG.md').not.toBeNull();
    const day = new Date(`${heading![1]} UTC`).toISOString().slice(0, 10);
    expect(day).toBe(FIRST_RELEASE.day);
  });

  it("names the catalogue demonstration as recorded before release 1.0.0, from the runs' own dates", () => {
    expect(PROOF.recordedFrom! < PROOF.recordedTo!).toBe(true);
    expect(PROOF.recordedTo!.slice(0, 10) < FIRST_RELEASE.day).toBe(true);
    expect(recordedBefore(PROOF)).toBe('before release 1.0.0');
    expect(cohortLabel(PROOF)).toBe('Catalogue demonstration, recorded before release 1.0.0');
  });

  it('gives the cohort alone when the runs are not dated, or one is as late as the release', () => {
    expect(recordedBefore({})).toBe('');
    expect(cohortLabel({})).toBe(CATALOGUE_COHORT);
    expect(cohortLabel({ recordedTo: null })).toBe(CATALOGUE_COHORT);
    expect(cohortLabel({ recordedTo: `${FIRST_RELEASE.day}T00:00:00Z` })).toBe(CATALOGUE_COHORT);
    expect(cohortLabel({ recordedTo: '2026-11-05T23:59:59Z' })).toBe(
      'Catalogue demonstration, recorded before release 1.0.0',
    );
  });
});
