import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { HELD_OUT } from './heldOut';

/** The held-out card's figures, each read back from the document it quotes. */
const doc = readFileSync(join(__dirname, '../../../../docs/readme/fair-test.md'), 'utf8');

/** The cells of the first table row whose first cell starts with `label`. */
function row(label: string): string[] {
  const line = doc.split('\n').find((l) => l.startsWith(`| ${label}`));
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

  it('gives the strict mean loss of the board, the single investigator and Site policy as the results table does', () => {
    // Mode | Runs | R | D | N+ | N- | F | Wp | Wx | Strict mean | Lenient mean
    expect(row('The board')[9]).toBe(HELD_OUT.board);
    expect(row('Single investigator, as settled here')[9]).toBe(HELD_OUT.single);
    expect(row('Site policy (no key')[9]).toBe(HELD_OUT.policy);
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
