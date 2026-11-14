import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { HELD_OUT } from './heldOut';

/** The held-out card's figures, each read back from the document it quotes. */
const doc = readFileSync(join(__dirname, '../../../../docs/readme/fair-test.md'), 'utf8');

/** The 1.4.3 rerun's run records, which the same-gate example is read from. */
const r143Runs = JSON.parse(
  readFileSync(join(__dirname, '../../../../docs/readme/fair-test/results-r143-all.json'), 'utf8'),
) as {
  about: string;
  site_profile: string;
  modes: Record<string, { cases: Record<string, { runs: R143Run[] }> }>;
};

interface R143Run {
  proposal: string;
  final_state: string;
  category: string;
  gate: { stage: string; outcome: string; codes: string[] }[];
  attempts: { key: string | null; outcome: string | null }[];
  receiver_final: { version: number; history: string[] };
}

/** The section the document gives release 1.4.3's rerun in. */
const R143_HEADING = '## Release 1.4.3: all 12 cases rerun';
const r143 = doc.slice(doc.indexOf(`\n${R143_HEADING}\n`), doc.indexOf('\n## The files\n'));

/** The section the document gives release 1.1.x's own rows in, once it has one. */
const V111_HEADING = '## Release 1.1.x';
const v111 = doc.includes(`\n${V111_HEADING}\n`) ? doc.slice(doc.indexOf(`\n${V111_HEADING}\n`)) : null;

/** The cells of the first table row whose first cell starts with `label`, in the whole document or in one part of it. */
function row(label: string, text = doc): string[] {
  const line = text.split('\n').find((l) => l.startsWith(`| ${label}`));
  expect(line, `a row starting "${label}"`).toBeDefined();
  return line!
    .split('|')
    .slice(1, -1)
    .map((c) => c.trim().replace(/\*\*/g, ''));
}

describe('the held-out card', () => {
  it("is on release 1.0.0's code, twelve cases of three runs each", () => {
    expect(doc).toMatch(new RegExp(`release ${HELD_OUT.release.replace(/\./g, '\\.')}'s code`));
    expect(doc).toContain('Twelve failed ADT deliveries');
    expect(HELD_OUT.cases).toBe(12);
    expect(doc).toContain(`--repeat ${HELD_OUT.repeats}`);
  });

  it('gives the strict mean loss of the board, the single investigator, Site policy and always escalating as the results table does', () => {
    // Mode | Runs | R | D | N+ | N- | F | Wp | Wx | Strict mean | Lenient mean
    expect(row('The board')[9]).toBe(HELD_OUT.board);
    expect(row('Single investigator, as settled here')[9]).toBe(HELD_OUT.single);
    expect(row('Single investigator, as graded')[9]).toBe(HELD_OUT.singleGraded);
    expect(row('Site policy (no key')[9]).toBe(HELD_OUT.policy);
    // The baseline the sealed rule ranks every mode against
    expect(row('Always escalate, the sealed rule')[9]).toBe(HELD_OUT.escalate);
  });

  it('says why the single investigator has two figures: the F08 runs the page settled', () => {
    // Case | What it tests | Reference | Board | Single | ...
    expect(row(HELD_OUT.disputed)[4]).toMatch(/graded F, F, R/);
    expect(row('Single investigator, as graded')[6]).toBe('2');
  });

  // Release 1.1.x's rows come with the README's own pass over fair-test.md; until the document has them, this waits
  it.skipIf(!v111)("gives release 1.1.1's board as the document's 1.1.x section does", () => {
    const board111 = row('All `claude-opus-5-5`, as graded', v111!);
    // ... | Strict mean | Lenient mean | USD a run
    expect(board111[9]).toBe(HELD_OUT.v111.boardGraded);
    for (const id of HELD_OUT.v111.held) expect(v111).toContain(`**${id},`);
    expect(v111).toContain("release 1.1.1's");
    expect(HELD_OUT.v111.url).toBe(`${HELD_OUT.url}#release-11x`);
  });

  it('names the case Site policy, with no model, wrote wrongly in every run, and the agent modes did not', () => {
    // Case | What it tests | Reference | Board | Single | Site policy | Rules only | Always escalate
    const f = row(HELD_OUT.wroteWrongly);
    expect(f[5]).toBe('Wx');
    expect(f[3]).not.toMatch(/W/);
    expect(f[4]).not.toMatch(/W/);
    expect(row('The board')[8]).toBe('0');
    expect(row('Single investigator, as settled here')[8]).toBe('0');
  });

  it('counts 36 runs in each mode the card names, on release 1.0.0 and on the 1.4.3 rerun', () => {
    // Mode | Runs | ...
    for (const label of ['The board', 'Single investigator, as settled here', 'Rules only']) {
      expect(row(label)[1], `${label}, 1.0.0`).toBe(String(HELD_OUT.runs));
      expect(row(label, r143)[1], `${label}, 1.4.3`).toBe(String(HELD_OUT.runs));
    }
    expect(HELD_OUT.runs).toBe(HELD_OUT.cases * HELD_OUT.repeats);
  });

  it("gives release 1.4.3's rerun as the document's section does, a regression rerun with no wrong write executed", () => {
    const r = HELD_OUT.r143;
    expect(r143).toContain(`release ${r.release}'s whole code`);
    expect(r143).toContain('**This is a regression rerun, not a new held-out test.**');
    // Release 1.4.3, all 12 cases | Runs | R | D | N+ | N- | F | Wp | Wx | Strict mean | Lenient mean | ...
    expect(row('The board', r143)[9]).toBe(r.board);
    expect(row('Single investigator, as settled here', r143)[9]).toBe(r.single);
    expect(row('Single investigator, as graded by', r143)[9]).toBe(r.singleGraded);
    expect(row('Rules only', r143)[9]).toBe(r.rules);
    expect(row('Always escalate, computed', r143)[9]).toBe(HELD_OUT.escalate);
    // Wx, wrong writes executed: 0 in every row of the results table that counts runs (the composed row counts none)
    const lines = r143.split('\n');
    const head = lines.findIndex((l) => l.startsWith('| Release 1.4.3, all 12 cases |'));
    const end = lines.findIndex((l, i) => i > head && !l.startsWith('|'));
    const counted = lines.slice(head + 2, end).filter((l) => /^\d+$/.test(l.split('|')[2].trim()));
    expect(counted).toHaveLength(7);
    for (const line of counted) expect(line.split('|')[9].trim(), line).toBe(String(r.wrongWrites));
    expect(r143).toContain('**No mode executed a wrong write.**');
    expect(r.url).toBe(`${HELD_OUT.url}#release-143-all-12-cases-rerun`);
  });

  it('reads the same-gate example from the run records: F03, both outcomes, and no write in any run', () => {
    const g = HELD_OUT.r143.sameGate;
    // One profile and one gate for every mode, with nothing exempted
    expect(r143Runs.about).toContain("Release 1.4.3's whole code");
    expect(r143Runs.about).toContain('the same gate for every mode');
    expect(r143Runs.site_profile).toContain('No exemption of any kind');
    const runsOf = (mode: string) => r143Runs.modes[mode].cases[g.case].runs;
    for (const mode of ['board', 'single']) {
      const runs = runsOf(mode);
      expect(runs).toHaveLength(g.runs);
      for (const run of runs) {
        expect(run.proposal).toBe(g.agents.proposal);
        expect(run.final_state).toBe(g.agents.state);
        expect(run.gate.map((s) => s.outcome)).toEqual(['pass']);
        expect(run.category).toBe('R');
      }
    }
    const rules = runsOf('rules');
    expect(rules).toHaveLength(g.runs);
    for (const run of rules) {
      expect(run.proposal).toBe(g.rules.proposal);
      expect(run.final_state).toBe(g.rules.state);
      expect(run.gate).toEqual([{ stage: 'proposal', outcome: 'block', codes: [...g.rules.codes] }]);
      // A wrong write proposed and stopped, never executed
      expect(run.category).toBe('Wp');
      expect(run.attempts).toEqual([]);
    }
    // No write in any of the nine runs: no attempt carries an operation key or an outcome, and the receiver ends on
    // the same version with the same three movements, none of them Shutter's
    const all = ['board', 'single', 'rules'].flatMap(runsOf);
    const written = all.flatMap((run) => run.attempts).filter((a) => a.key !== null || a.outcome !== null);
    expect(written).toHaveLength(g.writes);
    expect(new Set(all.map((run) => JSON.stringify(run.receiver_final))).size).toBe(1);
    expect(all[0].receiver_final.history).toHaveLength(3);
    // The document's own per-case rows say the same: Case | What it tests | Reference | Board | Single | ...
    expect(row(g.case)[1]).toBe(g.what);
    // Case | Reference | Board | Single | Site policy, board live | Site policy, board not live | Rules only
    const perCase = row(g.case, r143);
    expect([perCase[2], perCase[3], perCase[6]]).toEqual(['R', 'R', 'Wp']);
    expect(g.url).toBe(HELD_OUT.url.replace('fair-test.md', 'fair-test/results-r143-all.json'));
  });

  it('has the twelve cases the card names, F01 to F12, in the per-case table', () => {
    const ids = doc
      .slice(doc.indexOf('\n## Per case\n'), doc.indexOf('\n## The one disagreement'))
      .split('\n')
      .map((l) => /^\| (F\d\d) \|/.exec(l)?.[1])
      .filter(Boolean);
    expect(ids).toHaveLength(HELD_OUT.cases);
    expect([ids[0], ids[ids.length - 1]]).toEqual(['F01', 'F12']);
  });

  it('links the published document', () => {
    expect(HELD_OUT.url).toBe('https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md');
  });
});
