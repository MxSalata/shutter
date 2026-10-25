import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CHAPTERS, SCOPES } from './registry';

/** Every source file of the app, read once: the guide's targets must be attributes the screens really carry. */
function sources(dir: string): string {
  return readdirSync(dir)
    .map((name) => join(dir, name))
    .map((path) =>
      statSync(path).isDirectory()
        ? sources(path)
        : /\.tsx?$/.test(path) && !/\.test\.tsx?$/.test(path) && !path.includes('features/guide')
          ? readFileSync(path, 'utf8')
          : '',
    )
    .join('\n');
}
const SOURCE = sources(join(__dirname, '..', '..'));

describe('the guide registry', () => {
  it('has unique chapter ids and step ids within each chapter', () => {
    const ids = CHAPTERS.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const c of CHAPTERS) expect(new Set(c.steps.map((s) => s.id)).size).toBe(c.steps.length);
  });

  it('gives each screen one to four steps, and the quick route the five chapters of the demonstration', () => {
    for (const c of CHAPTERS) {
      expect(c.steps.length).toBeGreaterThan(0);
      expect(c.steps.length).toBeLessThanOrEqual(4);
    }
    expect(SCOPES.quick).toEqual(['scenarios', 's2', 's8', 's20', 'evaluation']);
    expect(SCOPES.all).toEqual(CHAPTERS.map((c) => c.id));
  });

  it('points every step at a target a screen carries, by attribute', () => {
    for (const c of CHAPTERS)
      for (const s of c.steps) {
        // A story step's target is the step itself: data-tour={`case-${value}`}
        const own = s.open && s.target === `case-${s.open}`;
        const named =
          SOURCE.includes(`data-tour="${s.target}"`) ||
          SOURCE.includes(`tour="${s.target}"`) ||
          (s.target.startsWith('case-') && SOURCE.includes('data-tour={`case-${value}`}'));
        expect(named || own, `${c.id}/${s.id}: ${s.target}`).toBe(true);
      }
  });

  it('opens a story step only on a case, and shows that step or a section inside it', () => {
    for (const c of CHAPTERS)
      for (const s of c.steps) if (s.open) expect('scenario' in s.place, `${c.id}/${s.id}`).toBe(true);
  });

  it('keeps the wording rules: no dashes, and never a person approving every write', () => {
    for (const c of CHAPTERS)
      for (const s of c.steps) {
        const text = `${c.title} ${s.title} ${s.text}`;
        expect(text).not.toMatch(/[\u2013\u2014]/);
        expect(text).not.toMatch(/a person (approves|releases) (every|each|all)/i);
      }
    // Where a step speaks of releasing writes in general, it names both a person and the written policy
    const general = CHAPTERS.flatMap((c) => c.steps).filter((s) => /every write/i.test(s.text));
    expect(general.length).toBeGreaterThan(0);
    for (const s of general) expect(s.text).toMatch(/a person, or the site's written policy/);
  });
});
