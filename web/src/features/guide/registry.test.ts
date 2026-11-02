import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CHAPTERS, enabled, pathOf, RANKED_REVIEW_RECORDED, SCOPES, stepAt, tourMinutes } from './registry';

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

/** The case story's steps, as CaseStory's StoryStep type lists them. */
const STORY_STEPS = ['failed', 'evidence', 'proposed', 'decision', 'written', 'verified', 'compare'];

const STEPS = CHAPTERS.flatMap((c) => c.steps.map((s) => ({ c, s, path: pathOf(c, s) })));
const words = (s: string) => s.split(/\s+/).filter(Boolean).length;

describe('the guide registry', () => {
  it('has unique chapter ids and step ids within each chapter', () => {
    const ids = CHAPTERS.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const c of CHAPTERS) expect(new Set(c.steps.map((s) => s.id)).size).toBe(c.steps.length);
  });

  it('makes the quick tour the 9 steps from a case to the proof, and the engineers tour 6', () => {
    expect(SCOPES.quick).toEqual([
      'scenarios/start',
      's2/receipt',
      's2/decision',
      's2/verified',
      's8/receipt',
      's8/compare',
      's8/ask',
      's20/receipt',
      'evaluation/headline',
    ]);
    expect(SCOPES.engineer).toEqual([
      's2/receipt-json',
      's2/gate',
      's8/evidence-cited',
      's8/compare',
      's8/trace',
      'evaluation/rules-differs',
    ]);
  });

  it("gives every screen every enabled step that is not the engineers' alone, one to four a chapter", () => {
    expect(RANKED_REVIEW_RECORDED).toBe(true);
    expect(SCOPES.all).toHaveLength(32);
    expect(SCOPES.all).toContain('review/agent');
    expect(SCOPES.all).toEqual(
      STEPS.filter(({ c, s }) => enabled(c, s) && !(s.scopes.length === 1 && s.scopes[0] === 'engineer')).map(
        (x) => x.path,
      ),
    );
    for (const c of CHAPTERS) {
      const n = SCOPES.all.filter((p) => p.startsWith(`${c.id}/`)).length;
      expect(n, c.id).toBeGreaterThan(0);
      expect(n, c.id).toBeLessThanOrEqual(4);
    }
  });

  it('points every step at a target a screen carries, by attribute, and every try-it at a control that has it', () => {
    // A story step's section carries data-tour={`case-${value}`}: only the story's own steps may lean on that form
    const story = SOURCE.includes('data-tour={`case-${value}`}');
    for (const { s, path } of STEPS) {
      const named =
        SOURCE.includes(`data-tour="${s.target}"`) ||
        SOURCE.includes(`tour="${s.target}"`) ||
        (story && s.target.startsWith('case-') && STORY_STEPS.includes(s.target.slice(5)));
      expect(named, `${path}: ${s.target}`).toBe(true);
      for (const a of [s.tryIt, s.chip].filter((x) => !!x)) {
        const marked =
          SOURCE.includes(`data-tour-action="${a.action}"`) ||
          SOURCE.includes(`tourAction="${a.action}"`) ||
          SOURCE.includes(`tourAction: '${a.action}'`) ||
          (a.action.startsWith('run-') && SOURCE.includes('data-tour-action={`run-${s.id}`}'));
        expect(marked, `${path}: ${a.action}`).toBe(true);
      }
    }
    // The finish card points at S20's Run button
    expect(SOURCE.includes('data-tour-action={`run-${s.id}`}')).toBe(true);
  });

  it('opens a story step or a tab only on a case', () => {
    for (const { s, path } of STEPS) if (s.open || s.tab) expect('scenario' in s.place, path).toBe(true);
  });

  it('keeps to its word budgets: title 6, say 25, detail 40, a try-it or chip 8', () => {
    for (const { s, path } of STEPS) {
      expect(words(s.title), `${path} title`).toBeLessThanOrEqual(6);
      expect(words(s.say), `${path} say`).toBeLessThanOrEqual(25);
      if (s.detail) expect(words(s.detail), `${path} detail`).toBeLessThanOrEqual(40);
      for (const a of [s.tryIt, s.chip].filter((x) => !!x))
        expect(words(a.text), `${path} ${a.action}`).toBeLessThanOrEqual(8);
    }
  });

  it('keeps the wording rules: no dashes, no exclamations, and never a person approving every write', () => {
    for (const { c, s } of STEPS) {
      const text = `${c.title} ${s.title} ${s.say} ${s.detail ?? ''} ${s.tryIt?.text ?? ''} ${s.chip?.text ?? ''}`;
      expect(text).not.toMatch(/[\u2013\u2014!]/);
      expect(text).not.toMatch(/a person (approves|releases) (every|each|all)/i);
      expect(text).not.toMatch(/\b(simply|just|easy|try anything|every action works)\b/i);
    }
    // Where a step speaks of releasing fixes in general, it names both a person and the written policy
    const general = STEPS.filter(({ s }) => /every (write|fix)/i.test(s.say));
    expect(general.length).toBeGreaterThan(0);
    for (const { s } of general) expect(s.say).toMatch(/a person, or the site's written policy/);
  });

  it('explains a word on the quick tour before it uses it', () => {
    const terms = ['gate', 'receiver', 'write', 'release', 'pass', 'production'];
    const known = new Set<string>();
    for (const path of SCOPES.quick) {
      const { step } = stepAt(path)!;
      for (const t of step.introduces ?? []) known.add(t);
      for (const t of terms.filter((x) => !known.has(x)))
        expect(`${step.title} ${step.say}`, `${path} uses "${t}" first`).not.toMatch(
          new RegExp(`\\b${t}\\b`, 'i'),
        );
    }
  });

  it('says how long each route takes from its own words, about 4 minutes for the quick tour', () => {
    expect(tourMinutes('quick')).toBe(4);
    expect(tourMinutes('engineer')).toBeGreaterThanOrEqual(2);
    expect(tourMinutes('all')).toBeGreaterThan(tourMinutes('quick'));
  });

  it('reads the proof and the costs from the evaluation, never typed', () => {
    expect(stepAt('evaluation/headline')!.step.say).toBe(
      'On 24 recorded failures the board chose the expected action every time. Played end to end on 11, the board got 11, simple rules 4.',
    );
    expect(stepAt('settings/costs')!.step.say).toMatch(/cost \$0\.34 to \$0\.50\.$/);
  });
});
