import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { HELD_OUT } from './heldOut';

/** The held-out card's figures, each read back from the document it quotes. */
const doc = readFileSync(join(__dirname, '../../../../docs/readme/fair-test.md'), 'utf8');

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

  it('links the published document', () => {
    expect(HELD_OUT.url).toBe('https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md');
  });
});
